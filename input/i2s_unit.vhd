-------------------------------------------------------------------------------
-- i2s_unit.vhd:  VHDL RTL model for the i2s_unit.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-------------------------------------------------------------------------------
-- Entity declaration
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2s_unit is
  
  port (
    clk   : in std_logic;
    rst_n : in std_logic;
    play_in : in std_logic;
    tick_in : in std_logic;
    audio0_in : in std_logic_vector(23 downto 0);
    audio1_in : in std_logic_vector(23 downto 0);    
    req_out : out std_logic;
    ws_out : out std_logic;
    sck_out : out std_logic;
    sdo_out : out std_logic
  );
  
end i2s_unit;

-------------------------------------------------------------------------------
-- Architecture declaration
-------------------------------------------------------------------------------

architecture RTL of i2s_unit is

  -----------------------------------------------------------------------------
  -- Sequential state (registers) allocated in Step 1
  -----------------------------------------------------------------------------
  signal play_active_r  : std_logic;                     -- reg (1)
  signal stop_pending_r : std_logic;                     -- reg (1)

  signal div_cnt_r      : unsigned(2 downto 0);          -- reg (3) 0..7
  signal sck_r          : std_logic;                     -- reg (1)

  signal bit_cnt_r      : unsigned(5 downto 0);          -- reg (6) 0..47

  signal in_reg_r       : std_logic_vector(47 downto 0); -- reg (48)
  signal shreg_r        : std_logic_vector(47 downto 0); -- reg (48)

  signal ws_r           : std_logic;                     -- reg (1)
  signal req_out_r      : std_logic;                     -- reg (1)

  -----------------------------------------------------------------------------
  -- Combinational decode/control signals allocated in Step 1
  -----------------------------------------------------------------------------
  signal start_req      : std_logic;                     -- comb
  signal stop_req       : std_logic;                     -- comb
  signal exit_play      : std_logic;                     -- comb

  signal div_wrap       : std_logic;                     -- comb
  signal sck_fall_pulse : std_logic;                     -- comb (1-cycle event)

  signal last_bit       : std_logic;                     -- comb
  signal frame_end_pulse: std_logic;                     -- comb

  signal in_reg_load_en : std_logic;                     -- comb
  signal in_reg_d       : std_logic_vector(47 downto 0); -- comb

  signal load_shreg     : std_logic;                     -- comb
  signal shift_shreg    : std_logic;                     -- comb

  signal ws_next        : std_logic;                     -- comb
  signal req_pulse      : std_logic;                     -- comb

begin

      
  
end RTL;

