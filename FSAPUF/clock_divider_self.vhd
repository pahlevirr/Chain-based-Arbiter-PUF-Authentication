library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity clock_divider_self is
  generic (
    DIVIDE_BY : integer := 10     -- N cycles between ticks (>= 2)
  );
  port (
    inclk0 : in  std_logic;       -- input clock (e.g., 50 MHz)
    reset  : in  std_logic;       -- active-low in your code elsewhere; adjust if needed
    outclk : out std_logic;       -- we will emit a 1-cycle TICK here (not a free-running clock)
    locked : out std_logic        -- tie high
  );
end entity;

architecture behavior of clock_divider_self is
  signal ce_cnt  : unsigned(15 downto 0) := (others=>'0');
  signal ce_tick : std_logic := '0';
begin
  process(inclk0)
  begin
    if rising_edge(inclk0) then
      if reset = '0' then                -- active-low reset
        ce_cnt  <= (others=>'0');
        ce_tick <= '0';
      else
        if ce_cnt = DIVIDE_BY - 1 then
          ce_cnt  <= (others=>'0');
          ce_tick <= '1';                 -- 1-cycle pulse every DIVIDE_BY cycles
        else
          ce_cnt  <= ce_cnt + 1;
          ce_tick <= '0';
        end if;
      end if;
    end if;
  end process;

  outclk <= ce_tick;   -- repurpose outclk as a tick
  locked <= '1';       -- always "locked"
end architecture;
