// 1.
#include "dsp_unit.h"

void dsp_unit::dsp_proc()
{
  // Local variables
  bool                tick_in_v;
  bool                clr_in_v;
  bool                filter_cfg_v;
  sc_uint<16>         level0_v;
  sc_uint<16>         level1_v;  
  sc_int<DATABITS>    audio0_in_v;
  sc_int<DATABITS>    audio1_in_v;
  sc_int<DATABITS>    audio0_out_v;
  sc_int<DATABITS>    audio1_out_v;

  // Explicit arithmetic widths to keep Catapult sizing cleaner
  enum {
    COEFF_BITS      = 32,
    LEVEL_BITS      = 16,
    FIR_GROWTH_BITS = 6,   // ceil(log2(FILTER_TAPS)) for 51 taps
    FIR_PROD_BITS   = DATABITS + COEFF_BITS,
    FIR_ACC_BITS    = FIR_PROD_BITS + FIR_GROWTH_BITS,
    SCALE_MUL_BITS  = DATABITS + LEVEL_BITS + 1
  };
  
  ///////////////////////////////////////////////////////////
  // Reset Section
  ///////////////////////////////////////////////////////////

 reset_protocol:
  {  
    // 2.
    audio0_out.write(0);
    audio1_out.write(0);
    tick_out.write(0);
  DATA_RESET_LOOP: for (int i=0; i < FILTER_TAPS; ++i)
      {
        data0_r[i] = 0;
        data1_r[i] = 0;
      }
  RESET_WAIT: wait();
  }
  
  ///////////////////////////////////////////////////////////
  // Processing Loop
  ///////////////////////////////////////////////////////////
  
 PROCESS_LOOP: while(true)
    {

      // 3.
      audio0_out_v = 0;
      audio1_out_v = 0;      
      read_inputs(tick_in_v, clr_in_v, filter_cfg_v, level0_v, level1_v, audio0_in_v, audio1_in_v);

    scheduled_region:
      {
	
        // 4.
        if (clr_in_v)
          {
          for (int i = 0; i < FILTER_TAPS; ++i)
              {
                data0_r[i] = 0;
                data1_r[i] = 0;
              }

            audio0_out_v = 0;
            audio1_out_v = 0;
          }     
        else if (tick_in_v)
          {
            // Shift input samples once for both operating modes
            SHIFT_LOOP: for (int i = FILTER_TAPS - 1; i > 0; --i)
              {
                data0_r[i] = data0_r[i - 1];
                data1_r[i] = data1_r[i - 1];
              }

            data0_r[0] = audio0_in_v;
            data1_r[0] = audio1_in_v;

            if (filter_cfg_v == DSP_FILTER_OFF)	  
              {
                // To do: Bypass filters
                audio0_out_v = audio0_in_v;
                audio1_out_v = audio1_in_v;    
              }
            else
              {
                // To do: Execute filters

                // FIR0 filter for left channel
                sc_int<FIR_ACC_BITS> left_channel_accumulator_r = 0;

                // FIR1 filter for right channel
                sc_int<FIR_ACC_BITS> right_channel_accumulator_r = 0;

                FIR_ACC_LOOP: for (int i = 0; i < FILTER_TAPS; ++i)
                  {
                    sc_int<DATABITS>   data0_v  = data0_r[i];
                    sc_int<DATABITS>   data1_v  = data1_r[i];
                    sc_int<COEFF_BITS> coeff0_v = dsp_regs_r[i].read();
                    sc_int<COEFF_BITS> coeff1_v = dsp_regs_r[i + FILTER_TAPS].read();

                    sc_int<FIR_PROD_BITS> left_prod_v  = data0_v * coeff0_v;
                    sc_int<FIR_PROD_BITS> right_prod_v = data1_v * coeff1_v;

                    left_channel_accumulator_r  = left_channel_accumulator_r + left_prod_v;
                    right_channel_accumulator_r = right_channel_accumulator_r + right_prod_v;
                  }

                // Convert accumulators to 24-bit
                // Coefficients are <1.31>, so scale result by shifting right 31 bits
                sc_int<FIR_ACC_BITS> left_shifted_v  = left_channel_accumulator_r >> 31;
                sc_int<FIR_ACC_BITS> right_shifted_v = right_channel_accumulator_r >> 31;

                // Saturate filter result before narrowing to DATABITS
                const sc_int<FIR_ACC_BITS> MAX_AUDIO_VAL = (sc_int<FIR_ACC_BITS>(1) << (DATABITS - 1)) - 1;
                const sc_int<FIR_ACC_BITS> MIN_AUDIO_VAL = -(sc_int<FIR_ACC_BITS>(1) << (DATABITS - 1));

                if (left_shifted_v > MAX_AUDIO_VAL)
                  audio0_out_v = MAX_AUDIO_VAL.to_int();
                else if (left_shifted_v < MIN_AUDIO_VAL)
                  audio0_out_v = MIN_AUDIO_VAL.to_int();
                else
                  audio0_out_v = left_shifted_v.to_int();

                if (right_shifted_v > MAX_AUDIO_VAL)
                  audio1_out_v = MAX_AUDIO_VAL.to_int();
                else if (right_shifted_v < MIN_AUDIO_VAL)
                  audio1_out_v = MIN_AUDIO_VAL.to_int();
                else
                  audio1_out_v = right_shifted_v.to_int();
              }
	    
            // To do: Scale outputs
            const sc_uint<16> MAX_OUT = 0x8000; 
            if (level0_v > MAX_OUT) level0_v = MAX_OUT;
            if (level1_v > MAX_OUT) level1_v = MAX_OUT;

            // Use explicit-width intermediate values for cleaner HLS mapping
            sc_uint<17> level0_ext_v = level0_v;
            sc_uint<17> level1_ext_v = level1_v;

            sc_int<SCALE_MUL_BITS> sc0 = sc_int<DATABITS>(audio0_out_v) * sc_int<17>(level0_ext_v);
            sc_int<SCALE_MUL_BITS> sc1 = sc_int<DATABITS>(audio1_out_v) * sc_int<17>(level1_ext_v);

            sc_int<SCALE_MUL_BITS> sc0_shifted_v = sc0 >> 15;
            sc_int<SCALE_MUL_BITS> sc1_shifted_v = sc1 >> 15;

            // Saturate scaled result before narrowing to DATABITS
            const sc_int<SCALE_MUL_BITS> MAX_SCALE_VAL = (sc_int<SCALE_MUL_BITS>(1) << (DATABITS - 1)) - 1;
            const sc_int<SCALE_MUL_BITS> MIN_SCALE_VAL = -(sc_int<SCALE_MUL_BITS>(1) << (DATABITS - 1));

            if (sc0_shifted_v > MAX_SCALE_VAL)
              audio0_out_v = MAX_SCALE_VAL.to_int();
            else if (sc0_shifted_v < MIN_SCALE_VAL)
              audio0_out_v = MIN_SCALE_VAL.to_int();
            else
              audio0_out_v = sc0_shifted_v.to_int();

            if (sc1_shifted_v > MAX_SCALE_VAL)
              audio1_out_v = MAX_SCALE_VAL.to_int();
            else if (sc1_shifted_v < MIN_SCALE_VAL)
              audio1_out_v = MIN_SCALE_VAL.to_int();
            else
              audio1_out_v = sc1_shifted_v.to_int();

          }
        // NOTICE! Delete the next two lines when your code is done!      
      }
      
      // 5.
      write_outputs(audio0_out_v, audio1_out_v);
    }
  
}


// 6.
#pragma design modulario<in>
void dsp_unit::read_inputs(bool &tick, bool &clr, bool &filter,
			   sc_uint<16> &level0,   sc_uint<16> &level1,
			   sc_int<DATABITS> &audio0, sc_int<DATABITS> &audio1)
{
 input_protocol: {  
  INPUT_LOOP: do {
      wait();
      tick = tick_in.read();
      clr =  clr_in.read();
    } while (!tick && !clr); 
    audio0 = audio0_in.read();	  
    audio1 = audio1_in.read();
    filter = filter_r.read();
    level0 = level0_r.read();
    level1 = level1_r.read();
  }
}

// 7.
#pragma design modulario<out>
void dsp_unit::write_outputs(sc_int<DATABITS> dsp0, sc_int<DATABITS> dsp1)
{
 output_protocol: {
    tick_out.write(1);
    audio0_out.write(dsp0);
    audio1_out.write(dsp1);
    wait();
    tick_out.write(0);
  }
}

// 8.
void dsp_unit::regs_proc()
{
  sc_uint<32>             level_reg;
  sc_bv<DSP_REGISTERS*32> dsp_regs;

  if (rst_n.read() == 0)
    {
    COEFF_RESET_LOOP: for (int i=0; i < DSP_REGISTERS; ++i)
	{
	  dsp_regs_r[i].write(0);
	}
      level0_r.write(0);
      level1_r.write(0);
      filter_r.write(0);
    }
  else
    {
      if (cfg_in.read())
	{
	  sc_uint<32> cfg_reg;
	  cfg_reg = cfg_reg_in.read();		  
	  filter_r.write(cfg_reg[CFG_FILTER]);
	  dsp_regs = dsp_regs_in.read();
	COEFF_WRITE_LOOP: for (int i=0; i < DSP_REGISTERS; ++i)
	    {
	      sc_int<32> c;
	      c = dsp_regs.range((i+1)*32-1, i*32).to_int();
	      dsp_regs_r[i].write(c);
	    }
	}
      else if (level_in.read())
	{
	  level_reg = level_reg_in.read();
	  level0_r.write(level_reg.range(15,0).to_uint());
	  level1_r.write(level_reg.range(31,16).to_uint());
	}
    }
}

#if defined(MTI_SYSTEMC)
SC_MODULE_EXPORT(dsp_unit);
#endif
