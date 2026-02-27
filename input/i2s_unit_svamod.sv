////////////////////////////////////////////////////////////////////////////////////////////
//
// SystemVerilog assertion module file for control_unit
//
//    Contents:
//    1. X-Checks
//    2. Assumptions fro formal verification
//    3. Blackbox assertions
//    4. Whitebox assertions
//    5. Covergroups
//
////////////////////////////////////////////////////////////////////////////////////////////

`include "audioport.svh"

import audioport_pkg::*;
import audioport_util_pkg::*;

module i2s_unit_svamod
  (
   input logic 	      clk,
   input logic 	      rst_n,
   input logic 	      play_in,
   input logic [23:0] audio0_in,
   input logic [23:0] audio1_in,
   input logic 	      tick_in,
   input logic 	      req_out,
   input logic 	      sck_out,
   input logic 	      ws_out,
   input logic 	      sdo_out
`ifndef SYSTEMC_DUT
   , input logic        play_active_r
   , input logic        stop_pending_r
   , input logic [2:0]  div_cnt_r
   , input logic        sck_r
   , input logic [5:0]  bit_cnt_r
   , input logic [47:0] in_reg_r
   , input logic [47:0] shreg_r
   , input logic        ws_r
   , input logic        req_out_r

   , input logic        start_req
   , input logic        stop_req
   , input logic        exit_play
   , input logic        div_wrap
   , input logic        sck_fall_pulse
   , input logic        last_bit
   , input logic        frame_end_pulse
   , input logic        in_reg_load_en
   , input logic [47:0] in_reg_d
   , input logic        load_shreg
   , input logic        shift_shreg
   , input logic        ws_next
   , input logic        req_pulse
`endif
   );

   /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
   // 1. X-checks
   /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

   `xcheck(play_in);
   `xcheck(audio0_in);
   `xcheck(audio1_in);
   `xcheck(tick_in);
   `xcheck(req_out);
   `xcheck(sck_out);
   `xcheck(ws_out);
   `xcheck(sdo_out);
`ifndef SYSTEMC_DUT
// -------------------------------------------------------------------------
   // X-check internal DUT signals added as ports
   // -------------------------------------------------------------------------
   // Registers (reg)
   `xcheck(play_active_r);
   `xcheck(stop_pending_r);
   `xcheck(div_cnt_r);
   `xcheck(sck_r);
   `xcheck(bit_cnt_r);
   `xcheck(in_reg_r);
   `xcheck(shreg_r);
   `xcheck(ws_r);
   `xcheck(req_out_r);

   // Combinational signals (comb)
   `xcheck(start_req);
   `xcheck(stop_req);
   `xcheck(exit_play);
   `xcheck(div_wrap);
   `xcheck(sck_fall_pulse);
   `xcheck(last_bit);
   `xcheck(frame_end_pulse);
   `xcheck(in_reg_load_en);
   `xcheck(in_reg_d);
   `xcheck(load_shreg);
   `xcheck(shift_shreg);
   `xcheck(ws_next);
   `xcheck(req_pulse);
`endif   
   /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
   // 2. Blackbox (functional) assumptions and assertions
   /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

`ifdef design_top_is_i2s_unit // Assumptions enabled only in i2s_unit verification

   // play_in_length : f_play_in_stable

   property f_play_in_stable;
   @(posedge clk ) disable iff (rst_n == '0)
     !$stable(play_in) |=> $stable(play_in) [* 384];
   endproperty

   mf_play_in_stable: assume property(f_play_in_stable) else assert_error("mf_play_in_stable");
   cf_play_in_stable: cover property(f_play_in_stable);

   // tick_in_length : f_tick_in_pulse

   property f_tick_in_pulse;
      @(posedge clk ) disable iff (rst_n == '0)
	$rose(tick_in) |=> $fell(tick_in);
   endproperty

   mf_tick_in_pulse: assume property(f_tick_in_pulse) else assert_error("mf_tick_in_pulse");
   cf_tick_in_pulse: cover property(f_tick_in_pulse);

   // tick_in_length : f_tick_in_play_only

   property f_tick_in_play_only;
      @(posedge clk ) disable iff (rst_n == '0)
	!play_in |-> !tick_in;
   endproperty

   mf_tick_in_play_only: assume property(f_tick_in_play_only) else assert_error("mf_tick_in_play_only");
   cf_tick_in_play_only: cover property(f_tick_in_play_only);

`endif //  `ifdef design_top_is_i2s_unit


   
   // data_request : f_req_out_pulse

   property f_req_out_pulse;
      @(posedge clk ) disable iff (rst_n == '0)
	$rose(req_out) |=> $fell(req_out);
   endproperty

   af_req_out_pulse: assert property(f_req_out_pulse) else assert_error("af_req_out_pulse");
   cf_req_out_pulse: cover property(f_req_out_pulse);


   
   // mode_control : f_sck_start
   
   property f_sck_start;
      @(posedge clk ) disable iff (rst_n == '0)
	$rose(play_in)  |=> $rose(sck_out);
   endproperty
   
   af_sck_start: assert property(f_sck_start) else assert_error("af_sck_start");
   cf_sck_start: cover property(f_sck_start);
   
   // data_request : f_req_sck_align

   property f_req_sck_align;
      @(posedge clk ) disable iff (rst_n == '0)
	$fell(req_out) |-> $fell(sck_out);
   endproperty

   af_req_sck_align: assert property(f_req_sck_align) else assert_error("af_req_sck_align");
   cf_req_sck_align: cover property(f_req_sck_align);

   // data_request : f_req_out_seen

   property f_req_out_seen;
      @(posedge clk ) disable iff (rst_n == '0)
	($rose(play_in) || (play_in && $fell(ws_out))) ##1 (play_in throughout ($fell(sck_out) [-> 1])) |-> $past(req_out);
   endproperty

   af_req_out_seen: assert property(f_req_out_seen) else assert_error("af_req_out_seen");
   cf_req_out_seen: cover property(f_req_out_seen);

   // sck_wave : f_sck_wave

   property f_sck_wave;
      @(posedge clk ) disable iff (rst_n == '0)
	$rose(sck_out) |=> (sck_out [*3] ##1 !sck_out[*4]) or
					  (sck_out [*1] ##1 !sck_out[*2]) or 
					  $fell(sck_out);
   endproperty

   af_sck_wave: assert property(f_sck_wave) else assert_error("af_sck_wave");
   cf_sck_wave: cover property(f_sck_wave);

   // ws_wave : f_ws_change

   property f_ws_change;
      @(posedge clk ) disable iff (rst_n == '0)
	!$stable(ws_out) |-> $fell(sck_out);
   endproperty

   af_ws_change: assert property(f_ws_change) else assert_error("af_ws_change");
   cf_ws_change: cover property(f_ws_change);

   // ws_wave : f_ws_wave

   property f_ws_wave;
      @(posedge clk ) disable iff (rst_n == '0)
	!ws_out throughout $rose(sck_out) [-> 24] |=> $rose(ws_out) [-> 1] ##1 (ws_out throughout $rose(sck_out) [-> 24]) ;
   endproperty

   af_ws_wave: assert property(f_ws_wave) else assert_error("af_ws_wave");
   cf_ws_wave: cover property(f_ws_wave);

   // serial_data : f_sdo_change

   property f_sdo_change;
      @(posedge clk ) disable iff (rst_n == '0)
	!$stable(sdo_out) && play_in |-> $fell(sck_out);
   endproperty

   af_sdo_change: assert property(f_sdo_change) else assert_error("af_sdo_change");
   cf_sdo_change: cover property(f_sdo_change);


   /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
   // 3. Whitebox (RTL) assertions
   /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

 `ifndef SYSTEMC_DUT
// ------------------------------------------------------------------------------------------------
   // Mode/control internal consistency
   // ------------------------------------------------------------------------------------------------

   // start_req = play_in & ~play_active_r
   property w_start_req_def;
      @(posedge clk) disable iff (rst_n == '0)
        start_req == (play_in && !play_active_r);
   endproperty
   aw_start_req_def: assert property(w_start_req_def) else assert_error("aw_start_req_def");

   // stop_req = ~play_in & play_active_r
   property w_stop_req_def;
      @(posedge clk) disable iff (rst_n == '0)
        stop_req == (!play_in && play_active_r);
   endproperty
   aw_stop_req_def: assert property(w_stop_req_def) else assert_error("aw_stop_req_def");

   // exit_play = stop_pending_r & frame_end_pulse
   property w_exit_play_def;
      @(posedge clk) disable iff (rst_n == '0)
        exit_play == (stop_pending_r && frame_end_pulse);
   endproperty
   aw_exit_play_def: assert property(w_exit_play_def) else assert_error("aw_exit_play_def");

   // stop_pending_r must set when stop_req and stay set until exit_play
   property w_stop_pending_set;
      @(posedge clk) disable iff (rst_n == '0)
        stop_req |=> stop_pending_r;
   endproperty
   aw_stop_pending_set: assert property(w_stop_pending_set) else assert_error("aw_stop_pending_set");

   property w_stop_pending_hold;
      @(posedge clk) disable iff (rst_n == '0)
        (stop_pending_r && !exit_play) |=> stop_pending_r;
   endproperty
   aw_stop_pending_hold: assert property(w_stop_pending_hold) else assert_error("aw_stop_pending_hold");

   property w_stop_pending_clear;
      @(posedge clk) disable iff (rst_n == '0)
        exit_play |=> !stop_pending_r;
   endproperty
   aw_stop_pending_clear: assert property(w_stop_pending_clear) else assert_error("aw_stop_pending_clear");


   // ------------------------------------------------------------------------------------------------
   // Divider / SCK internal consistency
   // ------------------------------------------------------------------------------------------------

   // div_wrap is true exactly when div_cnt_r == 7
   property w_div_wrap_def;
      @(posedge clk) disable iff (rst_n == '0)
        div_wrap == (div_cnt_r == 3'd7);
   endproperty
   aw_div_wrap_def: assert property(w_div_wrap_def) else assert_error("aw_div_wrap_def");

   // sck_out must mirror sck_r in play, and be 0 in standby
   property w_sck_out_mirror;
      @(posedge clk) disable iff (rst_n == '0)
        play_active_r |-> (sck_out == sck_r);
   endproperty
   aw_sck_out_mirror: assert property(w_sck_out_mirror) else assert_error("aw_sck_out_mirror");

   property w_sck_out_standby0;
      @(posedge clk) disable iff (rst_n == '0)
        !play_active_r |-> (sck_out == 1'b0);
   endproperty
   aw_sck_out_standby0: assert property(w_sck_out_standby0) else assert_error("aw_sck_out_standby0");

   // sck_fall_pulse can only occur in play mode
   property w_sck_fall_play_only;
      @(posedge clk) disable iff (rst_n == '0)
        sck_fall_pulse |-> play_active_r;
   endproperty
   aw_sck_fall_play_only: assert property(w_sck_fall_play_only) else assert_error("aw_sck_fall_play_only");


   // ------------------------------------------------------------------------------------------------
   // Bit counter / frame boundary logic
   // ------------------------------------------------------------------------------------------------

   // last_bit definition
   property w_last_bit_def;
      @(posedge clk) disable iff (rst_n == '0)
        last_bit == (bit_cnt_r == 6'd47);
   endproperty
   aw_last_bit_def: assert property(w_last_bit_def) else assert_error("aw_last_bit_def");

   // frame_end_pulse definition
   property w_frame_end_def;
      @(posedge clk) disable iff (rst_n == '0)
        frame_end_pulse == (play_active_r && sck_fall_pulse && last_bit);
   endproperty
   aw_frame_end_def: assert property(w_frame_end_def) else assert_error("aw_frame_end_def");

   // bit counter advances only on sck_fall_pulse when playing
   property w_bit_cnt_hold_no_fall;
      @(posedge clk) disable iff (rst_n == '0)
        (play_active_r && !sck_fall_pulse) |=> (bit_cnt_r == $past(bit_cnt_r));
   endproperty
   aw_bit_cnt_hold_no_fall: assert property(w_bit_cnt_hold_no_fall) else assert_error("aw_bit_cnt_hold_no_fall");

   property w_bit_cnt_inc;
      @(posedge clk) disable iff (rst_n == '0)
        (play_active_r && sck_fall_pulse && !$past(last_bit)) |-> (bit_cnt_r == ($past(bit_cnt_r) + 6'd1));
   endproperty
   aw_bit_cnt_inc: assert property(w_bit_cnt_inc) else assert_error("aw_bit_cnt_inc");

   property w_bit_cnt_wrap;
      @(posedge clk) disable iff (rst_n == '0)
        (play_active_r && sck_fall_pulse && $past(last_bit)) |-> (bit_cnt_r == 6'd0);
   endproperty
   aw_bit_cnt_wrap: assert property(w_bit_cnt_wrap) else assert_error("aw_bit_cnt_wrap");


   // ------------------------------------------------------------------------------------------------
   // Input register logic
   // ------------------------------------------------------------------------------------------------

   // in_reg_d definition: concat of audio0_in and audio1_in
   property w_in_reg_d_def;
      @(posedge clk) disable iff (rst_n == '0)
        in_reg_d == {audio0_in, audio1_in};
   endproperty
   aw_in_reg_d_def: assert property(w_in_reg_d_def) else assert_error("aw_in_reg_d_def");

   // in_reg_load_en definition
   property w_in_reg_load_en_def;
      @(posedge clk) disable iff (rst_n == '0)
        in_reg_load_en == (tick_in && play_active_r);
   endproperty
   aw_in_reg_load_en_def: assert property(w_in_reg_load_en_def) else assert_error("aw_in_reg_load_en_def");


   // ------------------------------------------------------------------------------------------------
   // Request pulse logic (internal) and output mapping
   // ------------------------------------------------------------------------------------------------

   // req_pulse should be generated at the same boundary as frame_end_pulse
   property w_req_pulse_def;
      @(posedge clk) disable iff (rst_n == '0)
        req_pulse == (play_active_r && sck_fall_pulse && last_bit);
   endproperty
   aw_req_pulse_def: assert property(w_req_pulse_def) else assert_error("aw_req_pulse_def");

   // req_out must mirror req_out_r (design choice in our architecture)
   property w_req_out_mirror;
      @(posedge clk) disable iff (rst_n == '0)
        req_out == req_out_r;
   endproperty
   aw_req_out_mirror: assert property(w_req_out_mirror) else assert_error("aw_req_out_mirror");

   // req_out_r is a 1-cycle pulse corresponding to req_pulse (registered pulse)
   property w_req_out_r_pulse;
      @(posedge clk) disable iff (rst_n == '0)
        req_pulse |-> req_out_r;
   endproperty
   aw_req_out_r_pulse: assert property(w_req_out_r_pulse) else assert_error("aw_req_out_r_pulse");

   property w_req_out_r_single_cycle;
      @(posedge clk) disable iff (rst_n == '0)
        $rose(req_out_r) |=> $fell(req_out_r);
   endproperty
   aw_req_out_r_single_cycle: assert property(w_req_out_r_single_cycle) else assert_error("aw_req_out_r_single_cycle");


   // ------------------------------------------------------------------------------------------------
   // Shift register control signals and data-path behavior
   // ------------------------------------------------------------------------------------------------

   // load_shreg and shift_shreg are mutually exclusive
   property w_load_shift_mutex;
      @(posedge clk) disable iff (rst_n == '0)
        !(load_shreg && shift_shreg);
   endproperty
   aw_load_shift_mutex: assert property(w_load_shift_mutex) else assert_error("aw_load_shift_mutex");

   // load_shreg occurs exactly at the req/frame boundary
   property w_load_shreg_def;
      @(posedge clk) disable iff (rst_n == '0)
        load_shreg == (play_active_r && sck_fall_pulse && last_bit);
   endproperty
   aw_load_shreg_def: assert property(w_load_shreg_def) else assert_error("aw_load_shreg_def");

   // shift_shreg occurs on sck falling edge when not last bit
   property w_shift_shreg_def;
      @(posedge clk) disable iff (rst_n == '0)
        shift_shreg == (play_active_r && sck_fall_pulse && !last_bit);
   endproperty
   aw_shift_shreg_def: assert property(w_shift_shreg_def) else assert_error("aw_shift_shreg_def");

   // When loading, shift register takes input register
   property w_shreg_load;
      @(posedge clk) disable iff (rst_n == '0)
        load_shreg |=> (shreg_r == $past(in_reg_r));
   endproperty
   aw_shreg_load: assert property(w_shreg_load) else assert_error("aw_shreg_load");

   // When shifting, shift register shifts left
   property w_shreg_shift;
      @(posedge clk) disable iff (rst_n == '0)
        shift_shreg |=> (shreg_r == {$past(shreg_r[46:0]), 1'b0});
   endproperty
   aw_shreg_shift: assert property(w_shreg_shift) else assert_error("aw_shreg_shift");


   // ------------------------------------------------------------------------------------------------
   // Serial data / WS internal mapping
   // ------------------------------------------------------------------------------------------------

   // sdo_out should be the MSB of the shift register in play mode
   property w_sdo_mirror;
      @(posedge clk) disable iff (rst_n == '0)
        play_active_r |-> (sdo_out == shreg_r[47]);
   endproperty
   aw_sdo_mirror: assert property(w_sdo_mirror) else assert_error("aw_sdo_mirror");

   // in standby, sdo_out must be 0 (as per spec)
   property w_sdo_standby0;
      @(posedge clk) disable iff (rst_n == '0)
        !play_active_r |-> (sdo_out == 1'b0);
   endproperty
   aw_sdo_standby0: assert property(w_sdo_standby0) else assert_error("aw_sdo_standby0");

   // ws_out must mirror ws_r (design choice in our architecture)
   property w_ws_out_mirror;
      @(posedge clk) disable iff (rst_n == '0)
        ws_out == ws_r;
   endproperty
   aw_ws_out_mirror: assert property(w_ws_out_mirror) else assert_error("aw_ws_out_mirror");

   // ws_next decode from bit_cnt_r: right channel when bit_cnt_r >= 24
   property w_ws_next_def;
      @(posedge clk) disable iff (rst_n == '0)
        ws_next == (bit_cnt_r >= 6'd24);
   endproperty
   aw_ws_next_def: assert property(w_ws_next_def) else assert_error("aw_ws_next_def");

   // ws_r updates only on sck_fall_pulse while in play mode
   property w_ws_hold_no_fall;
      @(posedge clk) disable iff (rst_n == '0)
        (play_active_r && !sck_fall_pulse) |=> (ws_r == $past(ws_r));
   endproperty
   aw_ws_hold_no_fall: assert property(w_ws_hold_no_fall) else assert_error("aw_ws_hold_no_fall");

   property w_ws_update_on_fall;
      @(posedge clk) disable iff (rst_n == '0)
        (play_active_r && sck_fall_pulse) |-> (ws_r == ws_next);
   endproperty
   aw_ws_update_on_fall: assert property(w_ws_update_on_fall) else assert_error("aw_ws_update_on_fall");



 `endif

   /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
   // 4. Covergroups
   /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////



endmodule

