///////////////////////////////////////////////////////////
// control_unit_sequence
///////////////////////////////////////////////////////////

class control_unit_sequence extends uvm_sequence #(apb_transaction);
      `uvm_object_utils(control_unit_sequence)

   //-------------------------------------------------------- 
   // Member functions
   //--------------------------------------------------------
	
   function new (string name = "");
      super.new(name);
   endfunction

   
   task body;

      /////////////////////////////////////////////////////////////////////
      // Variable declarations
      /////////////////////////////////////////////////////////////////////      

      uvm_event irq_event;
      apb_transaction write_tx;            // APB transaction object
      int i;                         // Loop index
      int stream_wdata;     // Data to write to FIFOs

      /////////////////////////////////////////////////////////////////////      
      // Executable code
      /////////////////////////////////////////////////////////////////////

      reset_test_stats;       
      irq_event = uvm_event_pool::get_global("irq_out");
      write_tx = apb_transaction::type_id::create("write_tx");

       // Step 1: Write random config data to all DSP_REGS
      for (int addr = DSP_REGS_START_ADDRESS; addr < DSP_REGS_END_ADDRESS; addr += 4) begin
         write_tx.addr = addr;
         write_tx.data = $urandom();
         write_tx.write_mode = '1;
	 write_tx.fail = 0;
         start_item(write_tx);
         finish_item(write_tx);
      end
      update_test_stats;
      // Step 2: Initialize stream_wdata
      stream_wdata = 1;

      // Step 3: Fill FIFO (Left: 1,3,5,... Right: 2,4,6,...)
      for (i = 0; i < AUDIO_FIFO_SIZE; i++) begin
         write_tx.addr = LEFT_FIFO_ADDRESS + i * 4;
         write_tx.data = stream_wdata;
         write_tx.write_mode = '1;
	 write_tx.fail = 0;
         start_item(write_tx); finish_item(write_tx);
         stream_wdata++;

         write_tx.addr = RIGHT_FIFO_ADDRESS+ i * 4;
         write_tx.data = stream_wdata;
         write_tx.write_mode = '1;
	 write_tx.fail = 0;
         start_item(write_tx); finish_item(write_tx);
         stream_wdata++;
      end
      update_test_stats;

      // Step 4: Write to CFG_REG to enable filter
      write_tx.addr = CFG_REG_ADDRESS;
      write_tx.data = DSP_FILTER_ON;
      write_tx.write_mode = '1;
      write_tx.fail = 0;
      start_item(write_tx); finish_item(write_tx);
      update_test_stats;
      // Step 5: Write CMD_CFG to CMD_REG
      write_tx.addr = CMD_REG_ADDRESS;
      write_tx.data = CMD_CFG;
      write_tx.write_mode = '1;
      write_tx.fail = 0;
      start_item(write_tx); finish_item(write_tx);
      update_test_stats;
      // Step 6: Write maximum volume to LEVEL_REG
      write_tx.addr = LEVEL_REG_ADDRESS;
      write_tx.data = 32'h7FFF_7FFF;
      write_tx.write_mode = '1;
      write_tx.fail = 0;
      start_item(write_tx); finish_item(write_tx);
      update_test_stats;

      // Step 7: Write CMD_LEVEL to CMD_REG
      write_tx.addr = CMD_REG_ADDRESS;
      write_tx.data = CMD_LEVEL;
      write_tx.write_mode = '1;
      write_tx.fail = 0;
      start_item(write_tx); finish_item(write_tx);
      update_test_stats;

      // Step 8: Write CMD_START to CMD_REG
      write_tx.addr = CMD_REG_ADDRESS;
      write_tx.data = CMD_START;
      write_tx.write_mode = '1;
      write_tx.fail = 0;
      start_item(write_tx); finish_item(write_tx);
      update_test_stats;

      
      // Step 9–11: IRQ handling and refilling FIFO
      repeat (4) begin
	 stream_wdata=1;
         irq_event.wait_trigger(); // Step 8: wait for interrupt
         #(INTERRUPT_LATENCY);     // simulate CPU latency

         // Step 9: Fill FIFO again
         for (i = 0; i < AUDIO_FIFO_SIZE; i++) begin
            write_tx.addr = LEFT_FIFO_ADDRESS + i * 4;
            write_tx.data = stream_wdata;
            write_tx.write_mode = '1;
            write_tx.fail = 0;
            start_item(write_tx); finish_item(write_tx);
            stream_wdata++;

            write_tx.addr = RIGHT_FIFO_ADDRESS+ i * 4;
            write_tx.data = stream_wdata;
            write_tx.write_mode = '1;
            write_tx.fail = 0;
            start_item(write_tx); finish_item(write_tx);
            stream_wdata++;
         end
         update_test_stats;
         // Step 10: Acknowledge interrupt
         write_tx.addr = CMD_REG_ADDRESS;
         write_tx.data = CMD_IRQACK;
         write_tx.write_mode = '1;
	 write_tx.fail = 0;
         start_item(write_tx); finish_item(write_tx);
         update_test_stats;
         #10us;
      end

      // Step 11: Stop playback
      write_tx.addr = CMD_REG_ADDRESS;
      write_tx.data = CMD_STOP;
      write_tx.write_mode = '1;
      write_tx.fail = 0;
      start_item(write_tx); finish_item(write_tx);
      update_test_stats;

      // Step 12: Clear command
      write_tx.addr = CMD_REG_ADDRESS;
      write_tx.data = CMD_CLR;
      write_tx.write_mode = '1;
      write_tx.fail = 0;
      start_item(write_tx); finish_item(write_tx);
      update_test_stats;;

      // Step 13: Wait to let CLR take effect
      #10us; 
   endtask

   //----------------------------------------------------------------
   // Notice! This sequence can only access the control_unit's APB
   //         bus ports. Therefore the test program functions that need
   //         access to other ports are not implemented.
   //-----------------------------------------------------------------

endclass 

