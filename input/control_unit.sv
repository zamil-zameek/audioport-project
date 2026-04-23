`include "audioport.svh"
import audioport_pkg::*;

module control_unit
(
   input  logic                         clk,
   input  logic                         rst_n,
   input  logic                         PSEL,
   input  logic                         PENABLE,
   input  logic                         PWRITE,
   input  logic [31:0]                  PADDR,
   input  logic [31:0]                  PWDATA,
   input  logic                         req_in,

   output logic [31:0]                  PRDATA,
   output logic                         PSLVERR,
   output logic                         PREADY,
   output logic                         irq_out,
   output logic [31:0]                  cfg_reg_out,
   output logic [31:0]                  level_reg_out,
   output logic [DSP_REGISTERS*32-1:0]   dsp_regs_out,
   output logic                         cfg_out,
   output logic                         clr_out,
   output logic                         level_out,
   output logic                         tick_out,
   output logic [23:0]                  audio0_out,
   output logic [23:0]                  audio1_out,
   output logic                         play_out
);

   // =========================================================================
   // Internal signals (declared according to rtlspecs)
   // =========================================================================

   // APB decode
   logic [$clog2(AUDIOPORT_REGISTERS+2)-1:0] rindex;
   logic                                    apbwrite;
   logic                                    apbread;

   // Register bank (Style 1)
   logic [AUDIOPORT_REGISTERS-1:0][31:0]     rbank_r;
   

   // Command indicators (combinational)
   logic                                    clr;
   logic                                    cfg;
   logic                                    start;
   logic                                    stop;
   logic                                    level;
   logic                                    irqack;

   // -----------------------------------------------------------------
   // Register bank helper types/functions (to keep always_ff qlint-clean)
   // -----------------------------------------------------------------
  typedef logic [AUDIOPORT_REGISTERS-1:0][31:0] rbank_t;

function automatic rbank_t rbank_next(
   input rbank_t cur,
   input logic apbwrite_i,
   input logic [$clog2(AUDIOPORT_REGISTERS+2)-1:0] rindex_i,
   input logic [31:0] pwdata_i,
   input logic start_i,
   input logic stop_i
);
   rbank_t nxt;
   nxt = cur;

   // APB write into register bank
   if (apbwrite_i && (rindex_i < AUDIOPORT_REGISTERS)) begin
      nxt[rindex_i] = pwdata_i;
   end

   // Internal STATUS_PLAY updates from START/STOP
   if (!(apbwrite_i && (rindex_i == STATUS_REG_INDEX))) begin
      if (start_i) nxt[STATUS_REG_INDEX][STATUS_PLAY] = 1'b1;
      if (stop_i)  nxt[STATUS_REG_INDEX][STATUS_PLAY] = 1'b0;
   end

   return nxt;
endfunction


   // Mode and req-tick (registers)
   logic                                    play_r;
   logic                                    req_r;

   // Left FIFO (Style 2)
   logic [AUDIO_FIFO_SIZE-1:0][23:0]         ldata_r,   ldata_ns;
   logic [$clog2(AUDIO_FIFO_SIZE)-1:0]       lhead_r,   lhead_ns;
   logic [$clog2(AUDIO_FIFO_SIZE)-1:0]       ltail_r,   ltail_ns;
   logic                                    llooped_r, llooped_ns;
   logic                                    lempty;
   logic                                    lfull;
   logic [23:0]                              lfifo;

   // Right FIFO (Style 2)  (Ex2.2 regs + related comb)
   logic [AUDIO_FIFO_SIZE-1:0][23:0]         rdata_r,   rdata_ns;
   logic [$clog2(AUDIO_FIFO_SIZE)-1:0]       rhead_r,   rhead_ns;
   logic [$clog2(AUDIO_FIFO_SIZE)-1:0]       rtail_r,   rtail_ns;
   logic                                    rlooped_r, rlooped_ns;
   logic                                    rempty;
   logic                                    rfull;
   logic [23:0]                              rfifo;

   // IRQ register (Ex2.2)
   logic                                    irq_r;

   // =========================================================================
   // Interconnect outputs + static APB responses (Ex1)
   // =========================================================================
   assign PSLVERR = 1'b0;  // zero-wait, no error
   assign PREADY  = 1'b1;  // zero wait states

   assign play_out  = play_r;
// tick_out is req_in delayed by 1 cycle, but must be forced low when not in play mode
   assign tick_out  = play_r & req_r;
   assign irq_out   = irq_r;


   // Register output ports
   assign cfg_reg_out   = rbank_r[CFG_REG_INDEX];
   assign level_reg_out = rbank_r[LEVEL_REG_INDEX];

   // DSP regs concatenation: DSP_REGS_START_INDEX .. DSP_REGS_END_INDEX
   genvar gi;
   generate
      for (gi = 0; gi < DSP_REGISTERS; gi++) begin : gen_dsp_regs
         assign dsp_regs_out[gi*32 +: 32] = rbank_r[DSP_REGS_START_INDEX + gi];
      end
   endgenerate

   // Audio outputs: current FIFO front values (0 if empty)
   assign audio0_out = lfifo;
   assign audio1_out = rfifo;

   // Command pulse outputs (1-cycle pulses during APB ACCESS write to CMD_REG)
   assign cfg_out   = cfg;
   assign level_out = level;
   // CMD_CLR only acts in standby
   assign clr_out   = clr;

   // =========================================================================
   // Combinational Logic: APB Decoder (Ex1)
   // =========================================================================
   always_comb begin : apb_decoder
      rindex   = '0;
      apbwrite = 1'b0;
      apbread  = 1'b0;

      if (PSEL) begin
         // rindex = address bits (word aligned)
         rindex   = PADDR[$clog2(AUDIOPORT_REGISTERS+2)+1:2];
         apbwrite = (PSEL && PENABLE && PREADY &&  PWRITE);
         apbread  = (PSEL && PENABLE && PREADY && !PWRITE);
      end
   end

   // =========================================================================
   // Combinational Logic: Command decode (Ex2.2 comb signals)
   // =========================================================================
   always_comb begin : cmd_decoder
      clr    = 1'b0;
      cfg    = 1'b0;
      start  = 1'b0;
      stop   = 1'b0;
      level  = 1'b0;
      irqack = 1'b0;

      if (apbwrite && (rindex == CMD_REG_INDEX)) begin
         unique case (PWDATA)
	   CMD_CLR: clr = (!play_r);
            CMD_CFG:    cfg    = 1'b1;
            CMD_START:  start  = 1'b1;
            CMD_STOP:   stop   = 1'b1;
            CMD_LEVEL:  level  = 1'b1;
            CMD_IRQACK: irqack = 1'b1;
            default:    ; // CMD_NOP or unknown -> no-op
         endcase
      end
   end

   // =========================================================================
   // Sequential Logic: mode register (Ex1)
   // =========================================================================
   always_ff @(posedge clk or negedge rst_n) begin : mode_reg
      if (!rst_n) begin
         play_r <= 1'b0;
      end else if (start) begin
         play_r <= 1'b1;
      end else if (stop) begin
         play_r <= 1'b0;
      end
   end
   

   // =========================================================================
   // Sequential Logic: req register (Ex1)
   // =========================================================================
   always_ff @(posedge clk or negedge rst_n) begin : req_reg
      if (!rst_n) begin
         req_r <= 1'b0;
      end else if (play_r) begin
         req_r <= req_in;
      end else begin
         req_r <= 1'b0;
      end
   end

   // =========================================================================
   // Sequential Logic: Register bank (Style 1)  (Ex2.1 + status play bit update)
   // =========================================================================
// Register bank (Style 1): single always_ff, no blocking assignments inside
always_ff @(posedge clk or negedge rst_n) begin : register_bank
   if (!rst_n) begin
      rbank_r <= '0;
   end else begin
      rbank_r <= rbank_next(rbank_r, apbwrite, rindex, PWDATA, start, stop);
   end
end


   // =========================================================================
   // Left FIFO flags + front value (Ex2.1 comb)
   // =========================================================================
   always_comb begin : left_fifo_flags
      lempty = (lhead_r == ltail_r) && !llooped_r;
      lfull  = (lhead_r == ltail_r) &&  llooped_r;
      lfifo  = lempty ? 24'd0 : ldata_r[ltail_r];
   end

   // =========================================================================
   // Right FIFO flags + front value (Ex2.2 comb)
   // =========================================================================
   always_comb begin : right_fifo_flags
      rempty = (rhead_r == rtail_r) && !rlooped_r;
      rfull  = (rhead_r == rtail_r) &&  rlooped_r;
      rfifo  = rempty ? 24'd0 : rdata_r[rtail_r];
   end

   // =========================================================================
   // Left FIFO next-state (Style 2)  (Ex2.1)
   // Safe-defaults used:
   // - APB read pop has priority over playback pop if both occur same cycle.
   // - reset-to-zero on CMD_CLR in standby.
   // =========================================================================
   always_comb begin : left_fifo_next
      ldata_ns   = ldata_r;
      lhead_ns   = lhead_r;
      ltail_ns   = ltail_r;
      llooped_ns = llooped_r;

      // CMD_CLR acts only in standby mode: clear FIFO regs synchronously
      if (clr && !play_r) begin
         ldata_ns   = '0;
         lhead_ns   = '0;
         ltail_ns   = '0;
         llooped_ns = 1'b0;
      end else begin
         // WRITE (APB) to LEFT FIFO
         if (apbwrite && (rindex == LEFT_FIFO_INDEX) && !lfull) begin
            ldata_ns[lhead_r] = PWDATA[23:0];

            if (lhead_r == AUDIO_FIFO_SIZE-1) begin
               lhead_ns   = '0;
               llooped_ns = ~llooped_ns;
            end else begin
               lhead_ns = lhead_r + 1'b1;
            end
         end

         // READ/POP conditions
         // APB FIFO read pops
         if (apbread && (rindex == LEFT_FIFO_INDEX) && !lempty) begin
            if (ltail_r == AUDIO_FIFO_SIZE-1) begin
               ltail_ns   = '0;
               llooped_ns = ~llooped_ns;
            end else begin
               ltail_ns = ltail_r + 1'b1;
            end
         end
         // Playback pop (only if no APB pop this cycle)
         else if (play_r && req_r && !lempty) begin
            if (ltail_r == AUDIO_FIFO_SIZE-1) begin
               ltail_ns   = '0;
               llooped_ns = ~llooped_ns;
            end else begin
               ltail_ns = ltail_r + 1'b1;
            end
         end
      end
   end

   // =========================================================================
   // Left FIFO registers (Style 2)  (Ex2.1)
   // =========================================================================
   always_ff @(posedge clk or negedge rst_n) begin : left_fifo_regs
      if (!rst_n) begin
         ldata_r   <= '0;
         lhead_r   <= '0;
         ltail_r   <= '0;
         llooped_r <= 1'b0;
      end else begin
         ldata_r   <= ldata_ns;
         lhead_r   <= lhead_ns;
         ltail_r   <= ltail_ns;
         llooped_r <= llooped_ns;
      end
   end

   // =========================================================================
   // Right FIFO next-state (Style 2)  (Ex2.2)
   // Safe-defaults used:
   // - APB read pop has priority over playback pop if both occur same cycle.
   // - reset-to-zero on CMD_CLR in standby.
   // =========================================================================
   always_comb begin : right_fifo_next
      rdata_ns   = rdata_r;
      rhead_ns   = rhead_r;
      rtail_ns   = rtail_r;
      rlooped_ns = rlooped_r;

      // CMD_CLR acts only in standby mode: clear FIFO regs synchronously
      if (clr && !play_r) begin
         rdata_ns   = '0;
         rhead_ns   = '0;
         rtail_ns   = '0;
         rlooped_ns = 1'b0;
      end else begin
         // WRITE (APB) to RIGHT FIFO
         if (apbwrite && (rindex == RIGHT_FIFO_INDEX) && !rfull) begin
            rdata_ns[rhead_r] = PWDATA[23:0];

            if (rhead_r == AUDIO_FIFO_SIZE-1) begin
               rhead_ns   = '0;
               rlooped_ns = ~rlooped_ns;
            end else begin
               rhead_ns = rhead_r + 1'b1;
            end
         end

         // READ/POP conditions
         // APB FIFO read pops
         if (apbread && (rindex == RIGHT_FIFO_INDEX) && !rempty) begin
            if (rtail_r == AUDIO_FIFO_SIZE-1) begin
               rtail_ns   = '0;
               rlooped_ns = ~rlooped_ns;
            end else begin
               rtail_ns = rtail_r + 1'b1;
            end
         end
         // Playback pop (only if no APB pop this cycle)
         else if (play_r && req_r && !rempty) begin
            if (rtail_r == AUDIO_FIFO_SIZE-1) begin
               rtail_ns   = '0;
               rlooped_ns = ~rlooped_ns;
            end else begin
               rtail_ns = rtail_r + 1'b1;
            end
         end
      end
   end

   // =========================================================================
   // Right FIFO registers (Style 2)  (Ex2.2)
   // =========================================================================
   always_ff @(posedge clk or negedge rst_n) begin : right_fifo_regs
      if (!rst_n) begin
         rdata_r   <= '0;
         rhead_r   <= '0;
         rtail_r   <= '0;
         rlooped_r <= 1'b0;
      end else begin
         rdata_r   <= rdata_ns;
         rhead_r   <= rhead_ns;
         rtail_r   <= rtail_ns;
         rlooped_r <= rlooped_ns;
      end
   end

   // =========================================================================
   // IRQ control (Ex2.2 sequential + interconnect)
   // - Raised when in play mode and both FIFOs are empty (registered -> next cycle)
   // - Lowered by CMD_IRQACK or CMD_STOP
   // =========================================================================
   always_ff @(posedge clk or negedge rst_n) begin : irq_reg
      if (!rst_n) begin
         irq_r <= 1'b0;
      end else if (stop || irqack) begin
         irq_r <= 1'b0;
      end else if (play_r && lempty && rempty) begin
         irq_r <= 1'b1;
      end
   end

   // =========================================================================
   // PRDATA mux + FIFO read side-effects handled in FIFO next-state
   // =========================================================================
  always_comb begin : prdata_mux
   // Default when not selected (matches ar_prdata_off)
   PRDATA = 32'd0;

   // PRDATA is driven whenever the peripheral is selected (PSEL),
   // independent of read/write phase (matches ar_prdata_* properties).
   if (PSEL) begin
      if (rindex < AUDIOPORT_REGISTERS) begin
         PRDATA = rbank_r[rindex];
      end else if (rindex == LEFT_FIFO_INDEX) begin
         PRDATA = {8'd0, lfifo};
      end else if (rindex == RIGHT_FIFO_INDEX) begin
         PRDATA = {8'd0, rfifo};
      end else begin
         PRDATA = 32'd0;
      end
   end
end


endmodule
