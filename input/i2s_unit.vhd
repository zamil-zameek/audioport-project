-------------------------------------------------------------------------------
-- i2s_unit.vhd: VHDL RTL model for the i2s_unit.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-------------------------------------------------------------------------------
-- Entity Declaration
-------------------------------------------------------------------------------
entity i2s_unit is
  port (
    clk       : in std_logic;
    rst_n     : in std_logic;
    play_in   : in std_logic;
    tick_in   : in std_logic;
    audio0_in : in std_logic_vector(23 downto 0);
    audio1_in : in std_logic_vector(23 downto 0);
    req_out   : out std_logic;
    ws_out    : out std_logic;
    sck_out   : out std_logic;
    sdo_out   : out std_logic
  );
end i2s_unit;

-------------------------------------------------------------------------------
-- Architecture Declaration
-------------------------------------------------------------------------------
architecture RTL of i2s_unit is

  signal mode_r      : std_logic;
  signal input_r     : std_logic_vector(47 downto 0);
  signal shift_r     : std_logic_vector(47 downto 0);
  signal counter_r   : unsigned(8 downto 0);
  signal load        : std_logic;
  signal shift       : std_logic;
  signal end_s       : std_logic;
  signal sck_out_sig : std_logic;

begin

  -----------------------------------------------------------------------------
  -- 384-cycle frame counter
  -----------------------------------------------------------------------------
  counter_logic : process(clk, rst_n)
  begin
    if rst_n = '0' then
      counter_r <= (others => '0');
    elsif rising_edge(clk) then
      if mode_r = '1' then
        if counter_r = to_unsigned(383, counter_r'length) then
          counter_r <= (others => '0');
        else
          counter_r <= counter_r + 1;
        end if;
      else
        counter_r <= (others => '0');
      end if;
    end if;
  end process counter_logic;

  -----------------------------------------------------------------------------
  -- Mode control
  -----------------------------------------------------------------------------
  mode_logic : process(clk, rst_n)
  begin
    if rst_n = '0' then
      mode_r <= '0';
    elsif rising_edge(clk) then
      if play_in = '1' then
        mode_r <= '1';
      elsif (mode_r = '1') and (play_in = '0') and (end_s = '1') then
        mode_r <= '0';
      end if;
    end if;
  end process mode_logic;

  -----------------------------------------------------------------------------
  -- Input register
  -----------------------------------------------------------------------------
  input_r_logic : process(clk, rst_n)
  begin
    if rst_n = '0' then
      input_r <= (others => '0');
    elsif rising_edge(clk) then
      if (play_in = '1') and (tick_in = '1') then
        input_r <= audio0_in & audio1_in;
      elsif play_in = '0' then
        input_r <= (others => '0');
      end if;
    end if;
  end process input_r_logic;

  -----------------------------------------------------------------------------
  -- Shift register
  -----------------------------------------------------------------------------
  shift_reg_logic : process(clk, rst_n)
  begin
    if rst_n = '0' then
      shift_r <= (others => '0');
    elsif rising_edge(clk) then
      if mode_r = '1' then
        if load = '1' then
          shift_r <= input_r;
        elsif shift = '1' then
          shift_r <= shift_r(46 downto 0) & '0';
        end if;
      else
        shift_r <= (others => '0');
      end if;
    end if;
  end process shift_reg_logic;

  -----------------------------------------------------------------------------
  -- Frame timing decode
  -----------------------------------------------------------------------------
 comb_block: process(counter_r)
begin

    shift       <= '0';
    sck_out_sig <= '0';

    if counter_r = to_unsigned(3, counter_r'length) then
        req_out <= '1';
        load    <= '1';
    else
        req_out <= '0';
        load    <= '0';
    end if;

    if counter_r(2 downto 0) < "100" then
        sck_out_sig <= '1';
    else
        sck_out_sig <= '0';
    end if;

    if (counter_r >= to_unsigned(11, counter_r'length)) and
       (counter_r(2 downto 0) = "011") then
        shift <= '1';
    end if;
end process comb_block;
  -----------------------------------------------------------------------------
  -- Outputs
  -----------------------------------------------------------------------------
  sdo_out <= shift_r(47) when mode_r = '1' else '0';
  sck_out <= sck_out_sig when mode_r = '1' else '0';
  ws_out  <= '1' when (counter_r > to_unsigned(187, counter_r'length)) and
                       (counter_r < to_unsigned(380, counter_r'length))
             else '0';

  -----------------------------------------------------------------------------
  -- End-of-play timing
  -----------------------------------------------------------------------------
  end_s <= '1' when (counter_r = to_unsigned(7, counter_r'length)) and
                    (play_in = '0')
           else '0';

end RTL;
