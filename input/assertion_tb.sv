// input/assertion_tb.sv
module assertion_tb;

   // Clock and reset
   logic clk = '0, rst_n = 0;
   always #10ns clk = ~clk;
   initial @(negedge clk) rst_n = '1;

   // ------------------------------------------------------------------
   // Constants & Parameters
   // ------------------------------------------------------------------
   localparam [31:0] CMD_REG_ADDRESS = 32'h8000_0000; 
   localparam [31:0] CMD_CFG   = 32'h0000_0002; 

   // ------------------------------------------------------------------
   // Signal Declarations
   // ------------------------------------------------------------------
   logic        cfg_out;    // Signal under test
   logic        PSEL, PENABLE, PWRITE, PREADY;
   logic [31:0] PADDR, PWDATA;
   
   // Auxiliary for cleaner code
   logic apb_write_access;
   assign apb_write_access = PSEL && PENABLE && PWRITE && PREADY;

   ///////////////////////////////////////////////////////////////////
   // Test data generation process
   ///////////////////////////////////////////////////////////////////
   initial begin
      // Initialize
      rst_n   = '0;
      cfg_out = '0;
      PSEL=0; PENABLE=0; PWRITE=0; PREADY=1; PADDR=0; PWDATA=0;
      @(negedge clk);
      rst_n   = '1;
      @(negedge clk);

      // --------------------------------------------------------
      // TEST: f_cfg_out_valid_high
      // --------------------------------------------------------
      $info("Test f_cfg_out_valid_high");

      // CASE 1: PASS
      // Scenario: cfg_out is High, AND we are writing the CFG command.
      PSEL=1; PENABLE=1; PWRITE=1; PREADY=1;
      PADDR  = CMD_REG_ADDRESS;
      PWDATA = CMD_CFG;
      
      cfg_out = '1; // Signal goes high validly
      @(negedge clk);

      // Clear everything
      cfg_out = '0; 
      PSEL=0; PENABLE=0;
      @(negedge clk);

      // CASE 2: FAIL ("Ghost Pulse")
      // Scenario: cfg_out goes High, BUT nobody wrote the command.
      $info("Test f_cfg_out_valid_high: FAIL Case");
      PSEL=0; // No APB access
      
      cfg_out = '1; // Error! Signal appeared without cause
      @(negedge clk);
      
      // Cleanup
      cfg_out = '0;
      @(negedge clk);
      
      #100ns;
      $finish;
   end

   ///////////////////////////////////////////////////////////////////
   // Properties and assertions
   ///////////////////////////////////////////////////////////////////
   
   // Requirement: If cfg_out is high... then we MUST be writing CMD_CFG to CMD_REG.
   property f_cfg_out_valid_high;
      @(posedge clk) disable iff (rst_n == '0)
      cfg_out |-> 
      (
         apb_write_access && 
         (PADDR == CMD_REG_ADDRESS) && 
         (PWDATA == CMD_CFG)
      );
   endproperty

   a_f_cfg_out_valid_high: assert property(f_cfg_out_valid_high)
      else $error("Assertion f_cfg_out_valid_high FAILED (Ghost Pulse detected)");
      
   c_f_cfg_out_valid_high: cover property(f_cfg_out_valid_high);

endmodule
