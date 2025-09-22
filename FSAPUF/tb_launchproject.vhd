library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity tb_launchproject is
end entity;

architecture sim of tb_launchproject is
  -- DUT ports
  signal mainclock : std_logic := '0';
  signal mainreset : std_logic := '1';  -- active-low in DUT; we'll assert '0' then deassert '1'
  signal rx        : std_logic := '1';  -- UART idle high
  signal tx        : std_logic;

  -- clock/baud parameters
  constant CLK_FREQ_HZ : integer := 50_000_000;     -- 50 MHz
  constant CLK_PERIOD  : time    := 20 ns;

  constant BAUD_HZ     : integer := 115_200;
  constant BIT_TIME    : time    := integer(1_000_000_000.0 / real(BAUD_HZ)) * 1 ns;

  procedure wait_clocks(n : natural) is
  begin
    for i in 1 to n loop
      wait until rising_edge(mainclock);
    end loop;
  end procedure;

  -- drive one UART byte on tb->DUT rx (8N1, LSB-first)
  procedure uart_send_byte(signal uart_rx : out std_logic; data : std_logic_vector(7 downto 0)) is
  begin
    uart_rx <= '0';                   -- start
    wait for BIT_TIME;
    for i in 0 to 7 loop              -- data LSB first
      uart_rx <= data(i);
      wait for BIT_TIME;
    end loop;
    uart_rx <= '1';                   -- stop
    wait for BIT_TIME;
    wait for (BIT_TIME/4);            -- small gap
  end procedure;

  -- send a full PUF transaction: 16 challenge bytes, then 1 enable byte
  procedure send_challenge_and_enable(
    signal uart_rx : out std_logic;
    constant chal  : std_logic_vector(127 downto 0);
    constant en_nib: std_logic_vector(3 downto 0)
  ) is
    variable b : std_logic_vector(7 downto 0);
  begin
    -- First received byte maps to challenge(127:120), then descends
    for k in 15 downto 0 loop
      b := chal(k*8+7 downto k*8);
      uart_send_byte(uart_rx, b);
    end loop;
    uart_send_byte(uart_rx, "0000" & en_nib);
  end procedure;

  -- VHDL-93 friendly random fill: procedure with variable seeds
  procedure fill_rand_128(variable s1, s2 : inout positive;
                          variable v      : out   std_logic_vector) is
    variable r : real;
  begin
    for i in v'range loop
      uniform(s1, s2, r);
      if r < 0.5 then v(i) := '0'; else v(i) := '1'; end if;
    end loop;
  end procedure;

  component launchproject
    port (
      mainclock : in  std_logic;
      mainreset : in  std_logic;
      rx        : in  std_logic;
      tx        : out std_logic
    );
  end component;

begin
  -- DUT
  dut: launchproject
    port map (
      mainclock => mainclock,
      mainreset => mainreset,
      rx        => rx,
      tx        => tx
    );

  -- 50 MHz clock
  clk_gen : process
  begin
    loop
      mainclock <= '0'; wait for (CLK_PERIOD/2);
      mainclock <= '1'; wait for (CLK_PERIOD/2);
    end loop;
  end process;

  -- stimulus
  stim : process
    variable seed1 : positive := 101;
    variable seed2 : positive := 303;
    variable chal  : std_logic_vector(127 downto 0);
    constant N_TXN : integer := 200;
  begin
    -- proper reset: assert low then release high
    rx        <= '1';
    mainreset <= '0';
    wait for 500 ns;
    wait_clocks(10);
    mainreset <= '1';
    wait_clocks(50);

    -- a couple of deterministic warm-ups
    chal := x"0123456789ABCDEF_F0E1D2C3B4A59687";
    send_challenge_and_enable(rx, chal, "0011");
    wait for 3 ms;

    chal := x"AA55AA5533CC33CC_FF00FF000F0FF0F0";
    send_challenge_and_enable(rx, chal, "0011");
    wait for 3 ms;

    -- randomized sweep for coverage
    for t in 1 to N_TXN loop
      fill_rand_128(seed1, seed2, chal);

      case (t mod 4) is
        when 0 => send_challenge_and_enable(rx, chal, "0011");
        when 1 => send_challenge_and_enable(rx, chal, "1100");
        when 2 => send_challenge_and_enable(rx, chal, "0101");
        when others => send_challenge_and_enable(rx, chal, "1010");
      end case;

      wait for 3 ms;
    end loop;

    -- finish sim (VHDL-93): park forever
    wait;
  end process;
end architecture;
