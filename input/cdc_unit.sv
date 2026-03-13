`include "audioport.svh"

import audioport_pkg::*;

module cdc_unit
  (
   input  logic        clk,
   input  logic        rst_n,
   input  logic        test_mode_in,
   input  logic [23:0] audio0_in,
   input  logic [23:0] audio1_in,
   input  logic        play_in,
   input  logic        tick_in,
   output logic        req_out,

   input  logic        mclk,
   output logic        muxclk_out,
   output logic        muxrst_n_out,
   output logic [23:0] audio0_out,
   output logic [23:0] audio1_out,
   output logic        play_out,
   output logic        tick_out,
   input  logic        req_in
   );

   // --------------------------------------------------------------------------
   // Internal signals for TESTMUX / RESET_SYNC
   // --------------------------------------------------------------------------
   logic mclkn;
   logic rsync_clk;
   logic mrst_n;
   logic rsync_ff1_r;
   logic rsync_ff2_r;

   // --------------------------------------------------------------------------
   // Internal signals for 1-BIT SYNCHRONIZER (play_in -> play_out)
   // --------------------------------------------------------------------------
   logic play_sff1_r;
   logic play_sff2_r;

   // --------------------------------------------------------------------------
   // Internal signals for PULSE SYNCHRONIZER (req_in -> req_out)
   // --------------------------------------------------------------------------
   logic reqin_sff1_r;
   logic reqin_sff2_r;
   logic reqin_sff2_dly_r;
   logic req_pulse;

   // --------------------------------------------------------------------------
   // Internal signals for MULTIBIT SYNCHRONIZER
   // {audio0_in, audio1_in, tick_in} -> {audio0_out, audio1_out, tick_out}
   // --------------------------------------------------------------------------
   localparam logic [1:0] TX_IDLE = 2'b01;
   localparam logic [1:0] TX_REQ  = 2'b10;

   localparam logic [1:0] RX_IDLE = 2'b01;
   localparam logic [1:0] RX_ACK  = 2'b10;

   logic [1:0]  tx_state_r;
   logic [1:0]  rx_state_r;

   logic [23:0] audio0_tx_r;
   logic [23:0] audio1_tx_r;

   logic        hreq_sff1_r;
   logic        hreq_sff2_r;
   logic        hack_sff1_r;
   logic        hack_sff2_r;

   logic        req;
   logic        ack;
   logic        sreq;
   logic        sack;
   logic        tx_load;
   logic        rx_load;

   // --------------------------------------------------------------------------
   // TESTMUX
   // MUX A: clock to all mclk-domain FFs except RESET SYNCHRONIZER
   // MUX B: clock to RESET SYNCHRONIZER
   // MUX C: reset to all mclk-domain FFs except RESET SYNCHRONIZER
   // --------------------------------------------------------------------------
   assign mclkn       = ~mclk;
   assign muxclk_out  = (test_mode_in == 1'b1) ? clk   : mclk;
   assign rsync_clk   = (test_mode_in == 1'b1) ? clk   : mclkn;
   assign muxrst_n_out = (test_mode_in == 1'b1) ? rst_n : mrst_n;

   // --------------------------------------------------------------------------
   // RESET SYNCHRONIZER
   // Reset release is synchronized to rsync_clk. In normal mode rsync_clk is
   // the complement of mclk so mrst_n changes near the middle of the mclk cycle.
   // --------------------------------------------------------------------------
   always_ff @(posedge rsync_clk or negedge rst_n)
     begin : reset_sync_regs
       if (rst_n == 1'b0)
         begin
           rsync_ff1_r <= 1'b0;
           rsync_ff2_r <= 1'b0;
         end
       else
         begin
           rsync_ff1_r <= 1'b1;
           rsync_ff2_r <= rsync_ff1_r;
         end
     end : reset_sync_regs

   assign mrst_n = rsync_ff2_r;

   // --------------------------------------------------------------------------
   // 1-BIT SYNCHRONIZER
   // play_in (clk domain) -> play_out (mclk domain)
   // --------------------------------------------------------------------------
   always_ff @(posedge muxclk_out or negedge muxrst_n_out)
     begin : bit_sync_regs
       if (muxrst_n_out == 1'b0)
         begin
           play_sff1_r <= 1'b0;
           play_sff2_r <= 1'b0;
         end
       else
         begin
           play_sff1_r <= play_in;
           play_sff2_r <= play_sff1_r;
         end
     end : bit_sync_regs

   assign play_out = play_sff2_r;

   // --------------------------------------------------------------------------
   // PULSE SYNCHRONIZER
   // req_in (mclk domain pulse) -> req_out (clk domain pulse)
   // Implemented as 2FF synchronizer + rising-edge detect.
   // --------------------------------------------------------------------------
   always_ff @(posedge clk or negedge rst_n)
     begin : pulse_sync_regs
       if (rst_n == 1'b0)
         begin
           reqin_sff1_r     <= 1'b0;
           reqin_sff2_r     <= 1'b0;
           reqin_sff2_dly_r <= 1'b0;
         end
       else
         begin
           reqin_sff1_r     <= req_in;
           reqin_sff2_r     <= reqin_sff1_r;
           reqin_sff2_dly_r <= reqin_sff2_r;
         end
     end : pulse_sync_regs

   assign req_pulse = reqin_sff2_r & ~reqin_sff2_dly_r;
   assign req_out   = req_pulse;

   // --------------------------------------------------------------------------
   // MULTIBIT SYNCHRONIZER
   // Handshake-based CDC for {audio0_in, audio1_in} with tick_in as enable.
   //
   // TX side (clk domain):
   //   - capture data when tick_in == 1 and no transaction is active
   //   - drive req directly from TX FSM state bit
   //
   // RX side (mclk domain):
   //   - synchronize req to sreq
   //   - capture data when synchronized req is first seen
   //   - drive ack directly from RX FSM state bit
   //   - generate tick_out as a registered 1-cycle pulse on accepted transfer
   // --------------------------------------------------------------------------

   // Request / acknowledge driven directly from one-hot state bits
   assign req  = tx_state_r[1];
   assign ack  = rx_state_r[1];
   assign sreq = hreq_sff2_r;
   assign sack = hack_sff2_r;

   // TX accepts a new transfer request only when idle and previous ack is low
   assign tx_load = (tx_state_r == TX_IDLE) && (tick_in == 1'b1) && (sack == 1'b0);

   // RX loads output registers only once, when entering the ACK state
   assign rx_load = (rx_state_r == RX_IDLE) && (sreq == 1'b1);

   // TX FSM and TX data registers (clk domain)
   always_ff @(posedge clk or negedge rst_n)
     begin : tx_domain_regs
       if (rst_n == 1'b0)
         begin
           tx_state_r  <= TX_IDLE;
           audio0_tx_r <= '0;
           audio1_tx_r <= '0;
         end
       else
         begin
           case (tx_state_r)
             TX_IDLE:
               begin
                 if (tx_load)
                   begin
                     tx_state_r  <= TX_REQ;
                     audio0_tx_r <= audio0_in;
                     audio1_tx_r <= audio1_in;
                   end
               end

             TX_REQ:
               begin
                 if (sack == 1'b1)
                   tx_state_r <= TX_IDLE;
               end

             default:
               begin
                 tx_state_r  <= TX_IDLE;
                 audio0_tx_r <= '0;
                 audio1_tx_r <= '0;
               end
           endcase
         end
     end : tx_domain_regs

   // Synchronize request into mclk domain
   always_ff @(posedge muxclk_out or negedge muxrst_n_out)
     begin : req_sync_regs
       if (muxrst_n_out == 1'b0)
         begin
           hreq_sff1_r <= 1'b0;
           hreq_sff2_r <= 1'b0;
         end
       else
         begin
           hreq_sff1_r <= req;
           hreq_sff2_r <= hreq_sff1_r;
         end
     end : req_sync_regs

   // RX FSM and RX data/output registers (mclk domain)
   always_ff @(posedge muxclk_out or negedge muxrst_n_out)
     begin : rx_domain_regs
       if (muxrst_n_out == 1'b0)
         begin
           rx_state_r  <= RX_IDLE;
           audio0_out  <= '0;
           audio1_out  <= '0;
           tick_out    <= 1'b0;
         end
       else
         begin
           // Default pulse output is low except on accepted transfer
           tick_out <= 1'b0;

           case (rx_state_r)
             RX_IDLE:
               begin
                 if (rx_load)
                   begin
                     rx_state_r <= RX_ACK;
                     audio0_out <= audio0_tx_r;
                     audio1_out <= audio1_tx_r;
                     tick_out   <= 1'b1;
                   end
               end

             RX_ACK:
               begin
                 if (sreq == 1'b0)
                   rx_state_r <= RX_IDLE;
               end

             default:
               begin
                 rx_state_r <= RX_IDLE;
                 audio0_out <= '0;
                 audio1_out <= '0;
                 tick_out   <= 1'b0;
               end
           endcase
         end
     end : rx_domain_regs

   // Synchronize acknowledge into clk domain
   always_ff @(posedge clk or negedge rst_n)
     begin : ack_sync_regs
       if (rst_n == 1'b0)
         begin
           hack_sff1_r <= 1'b0;
           hack_sff2_r <= 1'b0;
         end
       else
         begin
           hack_sff1_r <= ack;
           hack_sff2_r <= hack_sff1_r;
         end
     end : ack_sync_regs

endmodule
