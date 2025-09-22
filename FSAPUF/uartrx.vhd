library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity UartRx is
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        rx         : in  std_logic;
        data_out   : out std_logic_vector(7 downto 0);
        data_valid : out std_logic
    );
end entity;

architecture Behavioral of UartRx is
    constant BAUD_RATE     : integer := 115200;
    constant CLOCK_FREQ    : integer := 50000000;
    constant BAUD_TICK     : integer := CLOCK_FREQ / BAUD_RATE;

    signal baud_cnt  : integer range 0 to BAUD_TICK := 0;
    signal bit_cnt   : integer range 0 to 9 := 0;
    signal rx_shift  : std_logic_vector(7 downto 0);
    signal rx_reg    : std_logic := '1';
    signal rx_state  : std_logic := '0';
begin

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '0' then
                baud_cnt  <= 0;
                bit_cnt   <= 0;
                rx_state  <= '0';
                data_valid <= '0';
            else
                rx_reg <= rx;

                if rx_state = '0' then
                    if rx_reg = '0' then  -- Start bit detected
                        rx_state <= '1';
                        baud_cnt <= BAUD_TICK / 2;
                        bit_cnt <= 0;
                    end if;
                else
                    if baud_cnt = 0 then
                        baud_cnt <= BAUD_TICK;

                        if bit_cnt < 8 then
                            rx_shift <= rx & rx_shift(7 downto 1);
                            bit_cnt <= bit_cnt + 1;
                        else
                            bit_cnt <= 0;
                            rx_state <= '0';
                            data_out <= rx_shift;
                            data_valid <= '1';
                        end if;
                    else
                        baud_cnt <= baud_cnt - 1;
                        data_valid <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture;
