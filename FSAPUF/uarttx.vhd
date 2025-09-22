library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity UartTx is
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        tx_start  : in  std_logic;
        tx_data   : in  std_logic_vector(7 downto 0);
        tx_busy   : out std_logic;
        tx        : out std_logic
    );
end entity;

architecture Behavioral of UartTx is
    constant BAUD_RATE  : integer := 115200;
    constant CLOCK_FREQ : integer := 50000000;      -- must match your main clock
    constant BAUD_TICK  : integer := CLOCK_FREQ / BAUD_RATE;

    signal baud_cnt : integer range 0 to BAUD_TICK := 0;
    signal bit_cnt  : integer range 0 to 9 := 0;    -- 0=start, 1..8=data, 9=stop
    signal shiftreg : std_logic_vector(9 downto 0); -- [0]=start, [1..8]=data(0..7), [9]=stop
    signal active   : std_logic := '0';
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '0' then
                tx       <= '1';
                tx_busy  <= '0';
                active   <= '0';
                baud_cnt <= 0;
                bit_cnt  <= 0;

            elsif (tx_start = '1') and (active = '0') then
                -- load frame: start (0), data LSB..MSB, stop (1)
                shiftreg(0) <= '0';
                shiftreg(1) <= tx_data(0);
                shiftreg(2) <= tx_data(1);
                shiftreg(3) <= tx_data(2);
                shiftreg(4) <= tx_data(3);
                shiftreg(5) <= tx_data(4);
                shiftreg(6) <= tx_data(5);
                shiftreg(7) <= tx_data(6);
                shiftreg(8) <= tx_data(7);
                shiftreg(9) <= '1';

                bit_cnt  <= 0;
                baud_cnt <= BAUD_TICK;
                active   <= '1';
                tx_busy  <= '1';

            elsif active = '1' then
                if baud_cnt = 0 then
                    -- drive current bit
                    tx <= shiftreg(bit_cnt);

                    -- last bit? (stop)
                    if bit_cnt = 9 then
                        -- do NOT increment into 10; end cleanly
                        active   <= '0';
                        tx_busy  <= '0';
                        bit_cnt  <= 0;            -- ready for next frame
                        baud_cnt <= 0;
                        tx       <= '1';          -- idle level
                    else
                        bit_cnt  <= bit_cnt + 1;  -- safe: 0..8 only
                        baud_cnt <= BAUD_TICK;
                    end if;
                else
                    baud_cnt <= baud_cnt - 1;
                end if;
            end if;
        end if;
    end process;
end architecture;
