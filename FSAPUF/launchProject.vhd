library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;


entity launchproject is
	port (
		mainclock   : in  std_logic                    := '0';             --   clk.clk
		mainreset 	: in  std_logic                    := '0';             -- reset.reset_n
		rx          : in  std_logic;
      tx          : out std_logic;
		tailer0		: out std_logic; --Tailers were used to measure the delay path inside the PUF
		tailer1		: out std_logic;
		tailer2		: out std_logic;
		tailer3		: out std_logic
	);
end entity launchproject;

architecture main of launchproject is
	
	 signal challenge      : std_logic_vector(127 downto 0) := (others => '0');
    signal enable         : std_logic_vector(3 downto 0)   := (others => '0');
    signal rx_byte        : std_logic_vector(7 downto 0);
    signal rx_valid       : std_logic;
    signal response_bit   : std_logic := '0';
	 
    signal tx_busy        : std_logic;

    signal puf_done       : std_logic;
	 
	 -- States
   type state_type is (IDLE, RX_CHAL, LAUNCH, WAIT_SETTLE, CAPTURE, SEND, TX_PULSE);
	signal state        : state_type := IDLE;

	signal rx_count       : integer range 0 to 16 := 0;  -- 0..15=challenge bytes, 16=enable nibble
	signal delay_cnt      : integer range 0 to 255 := 0;
	signal sample_count   : integer range 0 to 8 := 0;

	-- outputs to submodules
	signal puf_enabled    : std_logic := '0';            -- 1-cycle pulse per bit
	signal tx_start       : std_logic := '0';

	-- your existing
	signal tx_data     : std_logic_vector(7 downto 0);


	component Switch_Block_V2
	port (
			clk			: in std_logic;
			reset		: in std_logic;
			challenge	: in std_logic_vector(127 downto 0);
			enable_in	: in std_logic_vector(3 downto 0);
			response	: out std_logic;
			ena_get		: in std_logic;
			tail0, tail1, tail2, tail3 : out std_logic ----Tailers were used to measure the delay path inside the PUF
		
		);
	end component;

	component UartRx
        port (
            clk        : in  std_logic;
            rst        : in  std_logic;
            rx         : in  std_logic;
            data_out   : out std_logic_vector(7 downto 0);
            data_valid : out std_logic
        );
    end component;

    component UartTx
        port (
            clk       : in  std_logic;
            rst       : in  std_logic;
            tx_start  : in  std_logic;
            tx_data   : in  std_logic_vector(7 downto 0);
            tx_busy   : out std_logic;
            tx        : out std_logic
        );
    end component;



begin
	-- PUF
	commswitch: Switch_Block_V2
	  port map(
		 clk       => mainclock,
		 reset     => mainreset,  -- invert here if the PUF expects active-high
		 challenge => challenge,
		 enable_in => enable,
		 response  => response_bit,
		 ena_get   => puf_enabled,  -- now a 1-cycle pulse per bit
		 tail0	=> tailer0, --Tailers were used to measure the delay path inside the PUF
		 tail1	=> tailer1,
		 tail2	=> tailer2,
		 tail3	=> tailer3
	  );
	  
	  
	-- UARTs
	uart_rx_inst: UartRx port map (clk=>mainclock, rst=>mainreset, rx=>rx, data_out=>rx_byte, data_valid=>rx_valid);
	uart_tx_inst: UartTx port map (clk=>mainclock, rst=>mainreset, tx_start=>tx_start, tx_data=>tx_data, tx_busy=>tx_busy, tx=>tx);


	

process(mainclock)
begin
  if rising_edge(mainclock) then
    if mainreset = '0' then
      state         <= IDLE;
      rx_count      <= 0;
      puf_enabled   <= '0';
      tx_start      <= '0';
      delay_cnt     <= 0;
      sample_count  <= 0;
      tx_data       <= (others => '0');
      enable        <= (others => '0');
    else
      -- default deassertions each cycle
      puf_enabled <= '0';
      tx_start    <= '0';

      case state is
        when IDLE =>
          if rx_valid = '1' then
            challenge(127 downto 120) <= rx_byte;
            rx_count <= 1;
            state    <= RX_CHAL;
          end if;

        when RX_CHAL =>
          if rx_valid = '1' then
            if rx_count < 16 then
              -- fill next byte of challenge
              challenge(127 - rx_count*8 downto 120 - rx_count*8) <= rx_byte;
              rx_count <= rx_count + 1;
            else
              -- 17th byte: enable nibble
              enable   <= rx_byte(3 downto 0);
              rx_count <= 0;
              sample_count <= 0;
              tx_data <= (others => '0');
              state   <= LAUNCH;
            end if;
          end if;

        when LAUNCH =>
          -- 1-cycle launch pulse to PUF core
          puf_enabled <= '1';
          delay_cnt   <= 0;
          state       <= WAIT_SETTLE;

        when WAIT_SETTLE =>
          if delay_cnt < 33 then
            delay_cnt <= delay_cnt + 1;   -- give the ladder time to propagate
          else
            state     <= CAPTURE;
          end if;

        when CAPTURE =>
          -- shift in the newly produced bit
          tx_data      <= tx_data(6 downto 0) & response_bit;
          sample_count <= sample_count + 1;

          if sample_count = 7 then         -- got 8 bits
            state <= SEND;
				enable <= (others => '0');
				puf_enabled <= '0';
          else
            state <= LAUNCH;               -- retrigger next bit (next pulse)
          end if;

        when SEND =>
          if tx_busy = '0' then
            state <= TX_PULSE;
          end if;

        when TX_PULSE =>
          -- one-cycle tx_start pulse
          tx_start <= '1';
          state    <= IDLE;

      end case;
    end if;
  end if;
end process;

	 
end;
	