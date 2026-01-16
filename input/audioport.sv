//
//  audioport.sv: Top-level module of audioport design.
//

`include "audioport.svh"

import audioport_pkg::*;

module audioport
  
  (input logic clk,
   input logic 	       rst_n,
   input logic 	       mclk,
   // APB interface
   input logic 	       PSEL,
   input logic 	       PENABLE,
   input logic 	       PWRITE,
   input logic [31:0]  PADDR,
   input logic [31:0]  PWDATA,
   output logic [31:0] PRDATA,
   output logic        PREADY,
   output logic        PSLVERR,
   // Interrupt request
   output logic        irq_out,
   // Audio outputs
   output logic        ws_out,
   output logic        sck_out, 
   output logic        sdo_out,
   // Test signals
   input logic 	       test_mode_in,
   input logic 	       scan_en_in
   );

   /////////////////////////////////////////////////////////////////////////////
   // Internal variables
   /////////////////////////////////////////////////////////////////////////////
   logic                          tick;
   logic [23:0] 		  audio0;
   logic [23:0] 		  audio1;
   logic                          cfg;
   logic [31:0] 		  cfg_reg;
   logic [DSP_REGISTERS*32-1:0]   dsp_regs;
   logic                          level;
   logic [31:0]                   level_reg;
   logic                          clr;
   logic                          play;
   logic                          dtick;
   logic [23:0] 		  daudio0;
   logic [23:0] 		  daudio1;
   logic                          req;
   logic                          mtick;
   logic [23:0] 		  maudio0;
   logic [23:0] 		  maudio1;
   logic                          mplay;
   logic                          mreq;
   logic                          muxclk;
   logic                          muxrst_n;
   /////////////////////////////////////////////////////////////////////////////
   

   
   /////////////////////////////////////////////////////////////////////////////
   // control_unit instantiation
   /////////////////////////////////////////////////////////////////////////////
   control_unit control_unit_1 (
      // Inputs
      .clk          (clk),
      .rst_n        (rst_n),
      .PSEL         (PSEL),
      .PENABLE      (PENABLE),
      .PWRITE       (PWRITE),
      .PADDR        (PADDR),
      .PWDATA       (PWDATA),
      .req_in       (req),
      // Outputs
      .PRDATA       (PRDATA),
      .PREADY       (PREADY),
      .PSLVERR      (PSLVERR),
      .irq_out      (irq_out),
      .tick_out     (tick),
      .audio0_out   (audio0),
      .audio1_out   (audio1),
      .cfg_out      (cfg),
      .cfg_reg_out  (cfg_reg),
      .dsp_regs_out (dsp_regs),
      .level_out    (level),
      .level_reg_out(level_reg),
      .clr_out      (clr),
      .play_out     (play)
   );

   /////////////////////////////////////////////////////////////////////////////
   // dsp_unit instantiation
   /////////////////////////////////////////////////////////////////////////////
   dsp_unit dsp_unit_1 (
      // Inputs
      .clk          (clk),
      .rst_n        (rst_n),
      .tick_in      (tick),
      .audio0_in    (audio0),
      .audio1_in    (audio1),
      .cfg_in       (cfg),
      .cfg_reg_in   (cfg_reg),
      .dsp_regs_in  (dsp_regs),
      .level_in     (level),
      .level_reg_in (level_reg),
      .clr_in       (clr),
      // Outputs
      .tick_out     (dtick),
      .audio0_out   (daudio0),
      .audio1_out   (daudio1)
   );

   /////////////////////////////////////////////////////////////////////////////
   // cdc_unit instantiation
   /////////////////////////////////////////////////////////////////////////////
   cdc_unit cdc_unit_1 (
      // Inputs
      .clk             (clk),
      .rst_n           (rst_n),
      .mclk            (mclk),
      .tick_in         (dtick),
      .audio0_in       (daudio0),
      .audio1_in       (daudio1),
      .play_in         (play),
      .req_in          (mreq),
      .test_mode_in    (test_mode_in),
      // Outputs
      .req_out         (req),
      .tick_out        (mtick),
      .audio0_out      (maudio0),
      .audio1_out      (maudio1),
      .play_out        (mplay),
      .muxclk_out      (muxclk),
      .muxrst_n_out    (muxrst_n)
   );

   /////////////////////////////////////////////////////////////////////////////
   // i2s_unit instantiation
   /////////////////////////////////////////////////////////////////////////////
   i2s_unit i2s_unit_1 (
      // Inputs
      .clk             (muxclk),
      .rst_n           (muxrst_n),
      .tick_in         (mtick),
      .audio0_in       (maudio0),
      .audio1_in       (maudio1),
      .play_in         (mplay),
      // Outputs
      .req_out         (mreq),
      .ws_out          (ws_out),
      .sck_out         (sck_out),
      .sdo_out         (sdo_out)
   );

endmodule


