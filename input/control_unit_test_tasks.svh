
//////////////////////////////////////////////////////////////////////////////////////
task reset_test;
//////////////////////////////////////////////////////////////////////////////////////   
   @(negedge clk);   
   req_in = '0;
   apb.init;
   rst_n = '1;   
   @(negedge clk);   
   rst_n = '0;
   @(negedge clk);
   @(negedge clk);   
   rst_n = '1;
endtask

//////////////////////////////////////////////////////////////////////////////////////
task apb_test;
//////////////////////////////////////////////////////////////////////////////////////
   
 // Print a message to user   
   $info("apb_test");

   // 1.
   reset_test;
   req_in = '0;
   
   // 2
   addr = CMD_REG_ADDRESS;
   wdata = CMD_NOP;
   apb.write(addr, wdata, wfail);
   apb.read(addr, rdata, rfail);   
   ia_apb_test1: assert (!wfail && !rfail) else 
     assert_error("ia_apb_test1");  // See assert_error in audioport_pkg.sv

   //3 
   repeat(10)
     @(posedge clk);
   
   // 4
   addr = AUDIOPORT_START_ADDRESS-4;
   wdata = $urandom;
   apb.write(addr, wdata, wfail);
   apb.read(addr, rdata, rfail);   

   update_test_stats; // See audioport_pkg.sv
    
endtask

//////////////////////////////////////////////////////////////////////////////////////
task address_decoding_test;
//////////////////////////////////////////////////////////////////////////////////////
   // Declaration of loop variable
   longint current_addr;
   $info("address_decoding_test");

   // 1. Execute reset_test
   reset_test;

   // 2. Execute a read access to all valid addresses in range 
   // AUDIOPORT_START_ADDRESS : AUDIOPORT_END_ADDRESS
   current_addr = AUDIOPORT_START_ADDRESS;
   
   while (current_addr <= AUDIOPORT_END_ADDRESS) begin
      addr = current_addr;
      apb.read(addr, rdata, rfail);
      
      // Verification of specific register data is handled by 
      // whitebox assertions in Week 3; this task triggers the logic.
      current_addr = current_addr + 4;
   end

   // 3. Execute a read access to an address outside audioport range
   addr = AUDIOPORT_START_ADDRESS - 4;
   apb.read(addr, rdata, rfail);

   $display("Info: Read executed outside range at %h (Logic checked by whitebox assertion)", addr);

   update_test_stats;
   
endtask


//////////////////////////////////////////////////////////////////////////////////////
task register_test;
//////////////////////////////////////////////////////////////////////////////////////

// 1. Declarations first (Static task requirement)
   longint current_addr;
   int i;
   logic [31:0] expected_data;
   int A;

   // 2. Initialization
   $info("register_test");
   A = 3; // Student number constant
   i = 0;

   // Step 1: Execute reset_test
   reset_test;

   // Step 2: Loop through all valid addresses
   current_addr = AUDIOPORT_START_ADDRESS;
   
   while (current_addr <= AUDIOPORT_END_ADDRESS) begin
      
      // Calculate data: A + i
      // Note: For FIFO registers, only 24 bits are significant
      expected_data = A + i;
      
      // Execute Write
      addr = current_addr;
      wdata = expected_data;
      apb.write(addr, wdata, wfail);
      
      // Execute Read immediately after
      apb.read(addr, rdata, rfail);
      
      // Step 2.1: Compare with immediate assertion
      ia_register_test_1: assert (rdata == expected_data && !wfail && !rfail) else 
         $error("ia_register_test_1 failed at addr %h. Expected %h, Got %h", addr, expected_data, rdata);

      // Increment for next register
      current_addr = current_addr + 4;
      i = i + 1;
   end

   update_test_stats;
   
endtask


//////////////////////////////////////////////////////////////////////////////////////
task fifo_bus_test;
//////////////////////////////////////////////////////////////////////////////////////
   int i;
   localparam int A = 3; // last digit of student number
   localparam int B = 1; // 2nd to last digit of student number
   logic [31:0] exp;

   $info("fifo_bus_test");

   // 1. Execute reset_test.
   reset_test;

   // 2. Fill LEFT FIFO with A+i
   for (i = 0; i < AUDIO_FIFO_SIZE; i++) begin
      addr  = LEFT_FIFO_ADDRESS;
      wdata = A + i;
      apb.write(addr, wdata, wfail);
   end

   // 3. Fill RIGHT FIFO with B+i
   for (i = 0; i < AUDIO_FIFO_SIZE; i++) begin
      addr  = RIGHT_FIFO_ADDRESS;
      wdata = B + i;
      apb.write(addr, wdata, wfail);
   end

   // 4. Read back LEFT FIFO and compare to A+i
   for (i = 0; i < AUDIO_FIFO_SIZE; i++) begin
      addr = LEFT_FIFO_ADDRESS;
      apb.read(addr, rdata, rfail);

      // Mixed-sim / SystemC: PRDATA may settle in delta after clock edge
      #0;
      rdata = apb.prdata;

      // FIFO stores 24-bit values; PRDATA returns zero-extended 24-bit
      exp = (A + i) & 32'h00FF_FFFF;

      ia_fifo_bus_test_1: assert (rdata == exp)
         else begin
            $error("ia_fifo_bus_test_1 failed i=%0d exp=%h got=%h", i, exp, rdata);
            assert_error("ia_fifo_bus_test_1");
         end
   end

   // 5. Read back RIGHT FIFO and compare to B+i
   for (i = 0; i < AUDIO_FIFO_SIZE; i++) begin
      addr = RIGHT_FIFO_ADDRESS;
      apb.read(addr, rdata, rfail);

      // Mixed-sim / SystemC delta settle
      #0;
      rdata = apb.prdata;

      exp = (B + i) & 32'h00FF_FFFF;

      ia_fifo_bus_test_2: assert (rdata == exp)
         else begin
            $error("ia_fifo_bus_test_2 failed i=%0d exp=%h got=%h", i, exp, rdata);
            assert_error("ia_fifo_bus_test_2");
         end
   end

   update_test_stats;
   
endtask

//////////////////////////////////////////////////////////////////////////////////////
task prdata_off_test;
//////////////////////////////////////////////////////////////////////////////////////
  logic [31:0] exp_cfg;
   logic [31:0] off_addr;

   $info("prdata_off_test");

   // 1. Reset
   reset_test;

   // 2. Write a known non-zero value to a valid register
   exp_cfg = 32'hA5A5_0001;
   addr    = CFG_REG_ADDRESS;
   wdata   = exp_cfg;
   apb.write(addr, wdata, wfail);

   // 3. Read back the valid register; must be non-zero and equal to what we wrote
   apb.read(addr, rdata, rfail);
   #0; // mixed-sim delta settle (SystemC PRDATA updates)
   rdata = apb.prdata;

   ia_prdata_off_test_1: assert (!wfail && !rfail && (rdata == exp_cfg) && (rdata != 32'h0))
     else assert_error("ia_prdata_off_test_1");

   // 4. Read outside audioport range; PRDATA must be 0
   off_addr = AUDIOPORT_START_ADDRESS - 32'd4;
   apb.read(off_addr, rdata, rfail);
   #0;
   rdata = apb.prdata;

   ia_prdata_off_test_2: assert (rdata == 32'h0)
     else assert_error("ia_prdata_off_test_2");

   // 5. Read back valid register again; must still hold the non-zero value
   addr = CFG_REG_ADDRESS;
   apb.read(addr, rdata, rfail);
   #0;
   rdata = apb.prdata;

   ia_prdata_off_test_3: assert (rdata == exp_cfg)
     else assert_error("ia_prdata_off_test_3");

   update_test_stats;
   
endtask

//////////////////////////////////////////////////////////////////////////////////////
task cmd_start_stop_test;
//////////////////////////////////////////////////////////////////////////////////////   
   $info("cmd_start_stop_test");

endtask

//////////////////////////////////////////////////////////////////////////////////////
task status_test;
//////////////////////////////////////////////////////////////////////////////////////   
   $info("status_test");

endtask

//////////////////////////////////////////////////////////////////////////////////////   
task cmd_clr_test;
//////////////////////////////////////////////////////////////////////////////////////
  
   int i;
   localparam int CBA = 213;

   $info("cmd_clr_test");

   // 1. Execute reset_test (design enters standby mode)
   reset_test;

   // 2. Write value CBA AUDIO_FIFO_SIZE times to both FIFOs
   for (i = 0; i < AUDIO_FIFO_SIZE; i=i+4) begin
      wdata = CBA;
      apb.write(LEFT_FIFO_ADDRESS, wdata, wfail);

      wdata = CBA;
      apb.write(RIGHT_FIFO_ADDRESS, wdata, wfail);
   end

   // 3. Write CMD_CLR into CMD_REG
   addr  = CMD_REG_ADDRESS;
   wdata = CMD_CLR;
   apb.write(addr, wdata, wfail);


   
   // 4. Read AUDIO_FIFO_SIZE times from both FIFOs
   //    and check that all values are zero
   for (i = 0; i < AUDIO_FIFO_SIZE; i=i+4) begin
      apb.read(LEFT_FIFO_ADDRESS, rdata, rfail);
        rdata = apb.prdata;
      ia_cmd_clr_test_1: assert (rdata == 0)
         else assert_error("ia_cmd_clr_test_1");

      apb.read(RIGHT_FIFO_ADDRESS, rdata, rfail);
        rdata = apb.prdata;
      ia_cmd_clr_test_2: assert (rdata == 0)
        else assert_error("ia_cmd_clr_test_2");
   end

   update_test_stats;

 endtask


//////////////////////////////////////////////////////////////////////////////////////
task cmd_cfg_test;
//////////////////////////////////////////////////////////////////////////////////////   
   // Initialization
   $info("cmd_cfg_test");

   // Step 1: Execute reset_test
   // Ensures cfg_out starts in its default state (usually 0)
   reset_test;

   // Step 2: Write the command code CMD_CFG into CMD_REG_ADDRESS
   addr  = CMD_REG_ADDRESS;
   wdata = CMD_CFG;
   apb.write(addr, wdata, wfail);

   // blackbox assertion to be added later.
   $display("Info: CMD_CFG written to %h. Monitor cfg_out in waveform.", addr);

   update_test_stats;
endtask


//////////////////////////////////////////////////////////////////////////////////////
task cmd_level_test;
//////////////////////////////////////////////////////////////////////////////////////   
   $info("cmd_level_test");
// Step 1: Execute reset_test
   // Ensures level_out starts at its default state (0)
   reset_test;

   // Step 2: Write the command code CMD_LEVEL to CMD_REG_ADDRESS
   addr  = CMD_REG_ADDRESS;
   wdata = CMD_LEVEL;
   apb.write(addr, wdata, wfail);

   // Note: The physical pulse/state change on level_out is verified 
   // by the blackbox assertion in a later week.
   $display("Info: CMD_LEVEL written to %h. Monitor level_out in waveform.", addr);

   update_test_stats;
endtask


//////////////////////////////////////////////////////////////////////////////////////
task clr_error_test;
//////////////////////////////////////////////////////////////////////////////////////   
   $info("clr_error_test");

endtask

//////////////////////////////////////////////////////////////////////////////////////
task req_tick_test;
//////////////////////////////////////////////////////////////////////////////////////
   $info("req_tick_test");

   // 1. Execute reset_test.
   reset_test;
   req_in = 1'b0;

   fork : fork_req_tick

      // In apb_control:
      begin : apb_control
         // 2-1.1. Write CMD_START into CMD_REG_ADDRESS.
         addr  = CMD_REG_ADDRESS;
         wdata = CMD_START;
         apb.write(addr, wdata, wfail);

         // 2-1.2. Wait for 50 clock cycles.
         repeat(50) @(posedge clk);

         // 2-1.3. Write CMD_STOP into CMD_REG_ADDRESS.
         addr  = CMD_REG_ADDRESS;
         wdata = CMD_STOP;
         apb.write(addr, wdata, wfail);

         // 2-1.4. Wait for 50 clock cycles.
         repeat(50) @(posedge clk);
      end : apb_control

      // In req_writer:
      begin : req_writer
         // 2-2.1. Wait until play_out rises
         wait (play_out == 1'b1);

         // 2-2.2. Forever: wait 10 cycles, generate 1-cycle req_in pulse,
         // and after the falling edge check tick_out with one-cycle delay behavior.
         forever begin
            repeat(10) @(posedge clk);

            // pulse req_in for exactly 1 cycle
            req_in <= 1'b1;
            @(posedge clk);
            req_in <= 1'b0;

            // "after the falling edge of req_in" -> req_in just went low at this posedge.
            // One-cycle delay requirement means: check tick_out on the *next* posedge.
            @(posedge clk);

            ia_req_tick_test_1: assert ( tick_out === (play_out ? 1'b1 : 1'b0) )
              else assert_error("ia_req_tick_test_1");
         end
      end : req_writer

   join_any

   // 3. End processes
   disable fork_req_tick;
   req_in = 1'b0;

   update_test_stats;

endtask


//////////////////////////////////////////////////////////////////////////////////////
task fifo_test;
//////////////////////////////////////////////////////////////////////////////////////   
   $info("fifo_test");   
endtask

//////////////////////////////////////////////////////////////////////////////////////
task irq_up_test;
//////////////////////////////////////////////////////////////////////////////////////   
   $info("irq_up_test");      

endtask

//////////////////////////////////////////////////////////////////////////////////////
task irq_down_test;
//////////////////////////////////////////////////////////////////////////////////////   
   $info("irq_down_test");
endtask


//////////////////////////////////////////////////////////////////////////////////////
task performance_test;
//////////////////////////////////////////////////////////////////////////////////////   
   int 					    irq_counter;
   logic 				    irq_out_state;
   logic [23:0] 			    stream_wdata;
   logic [23:0] 			    stream_rdata;   
   int 					    cycle_counter;
   
   $info("performance_test");   

   // 1.
   reset_test;
   req_in = '0;

   // 2.
   stream_wdata = 1;
   irq_counter = 0;
   cycle_counter = 0;
   
   // 3.
   for (int i=0; i < AUDIO_FIFO_SIZE; ++i)
     begin
	wdata = stream_wdata;
	apb.write(LEFT_FIFO_ADDRESS, wdata, wfail);
	++stream_wdata;
	wdata = stream_wdata;	
	apb.write(RIGHT_FIFO_ADDRESS, wdata, wfail);
	++stream_wdata;
     end
   
   fork
      
      begin : host_process
	 // 4-1.1.
	 addr = CMD_REG_ADDRESS;
	 wdata = CMD_START;
	 apb.write(addr, wdata, wfail);
	 // 4-1.2.
	 while (irq_counter < 3)
	   begin
	      // 4-1.3.
	      irq.monitor(irq_out_state);
	      // 4-1.4.
	      if (!irq_out_state)
		begin
		   ++cycle_counter;
		   ia_performance_test_1: assert ( cycle_counter < (AUDIO_FIFO_SIZE+1) * CLK_DIV_48000 ) 
		     else
		       begin
			  assert_error("ia_performance_test_1");
			  irq_counter = 3;
		       end
		end
	      // 4-1.5.
	      else
		begin
		   for (int i=0; i < AUDIO_FIFO_SIZE; ++i)
		     begin
			wdata = stream_wdata;
			apb.write(LEFT_FIFO_ADDRESS, wdata, wfail);
			++stream_wdata;
			wdata = stream_wdata;		   
			apb.write(RIGHT_FIFO_ADDRESS, wdata, wfail);
			++stream_wdata;
		     end
		   
		   // 4-1.5.
		   addr = CMD_REG_ADDRESS;
		   wdata = CMD_IRQACK;
		   apb.write(addr, wdata, wfail);
		   irq_counter = irq_counter + 1;
		   cycle_counter = 0;
		end
	   end
	 
	 // 4-1.6.		 
	 addr = CMD_REG_ADDRESS;
	 wdata = CMD_STOP;
	 apb.write(addr, wdata, wfail);

      end : host_process

      begin : req_in_driver

	 // 4-2.1.
	 wait (play_out);
	 // 4-2.2.
	 while(play_out)
	   begin
	      repeat(CLK_DIV_48000-1) @(posedge clk);
	      req_in = '1;
	      @(posedge clk);	      
	      req_in = '0;
	   end
	 
      end : req_in_driver


      begin: audio_out_reader
	 // 4-3.1.
	 stream_rdata = 1;
	 // 4-3.2.
	 forever
	   begin
	      wait(tick_out);
	      ia_performance_test_2: assert ( (audio0_out == stream_rdata) && audio1_out == stream_rdata+1) else assert_error("ia_performance_test_2");
	      stream_rdata = stream_rdata + 2;
	      @(posedge clk);
	   end
	 
      end: audio_out_reader
   join_any
   disable fork;
   
   update_test_stats;      

endtask


