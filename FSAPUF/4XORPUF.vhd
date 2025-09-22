LIBRARY ieee;
USE ieee.std_logic_1164.all;
use IEEE.NUMERIC_STD.ALL;

entity XOR4Arbiter is
	port (
		clk			: in std_logic;
		reset			: in std_logic;
		challenge	: in std_logic_vector(127 downto 0);
		enable_in	: in std_logic_vector(3 downto 0);
		response		: out std_logic;
		ena_get		: in std_logic
		--tail0, tail1, tail2, tail3 : out std_logic --Tailers were used to measure the delay path inside the PUF
	
	);
end XOR4Arbiter;


architecture main of XOR4Arbiter is
	signal len_gate	: std_logic_vector(127 downto 0) := (others => '0');
	signal len2_gate	: std_logic_vector(127 downto 0) := (others => '0');
	signal len3_gate	: std_logic_vector(127 downto 0) := (others => '0');
	signal len4_gate	: std_logic_vector(127 downto 0) := (others => '0');
	signal pulse		: std_logic;
	signal R_plus, R_minus : std_logic;
	
	--clock divider
	signal count: integer:=1;
	signal tmp : std_logic := '0';
	signal clk_out : std_logic;
	signal clk_lock	: std_logic;
	
	signal FF1, FF2 : std_logic;

	attribute KEEP : string;
	attribute KEEP of len_gate   : signal is "true";
	attribute KEEP of len2_gate  : signal is "true";
	attribute KEEP of len3_gate  : signal is "true";
	attribute KEEP of len4_gate  : signal is "true";
	attribute KEEP of R_plus  : signal is "true";
	attribute KEEP of R_minus  : signal is "true";
	attribute KEEP of pulse  : signal is "true";
	
	signal ena_get_sync, ena_get_d : std_logic := '0';
	signal launch_pulse            : std_logic := '0';	
	
	  -- replace clk_out use with a 1-cycle tick in the *clk* domain
  signal tick_cnt    : unsigned(7 downto 0) := (others=>'0');
  signal ce_tick     : std_logic := '0';

  -- handshake + timing
  signal ena_q       : std_logic := '0';
  signal start_pulse : std_logic := '0';
  signal wait_cnt    : unsigned(3 downto 0) := (others=>'0');
  signal sample_stb  : std_logic := '0';
  signal rst_n       : std_logic;

	
	component mux2 
	port(
		data0      	: in  std_logic;
		data1      	: in  std_logic;
		sel    	 	: in  std_logic;
		result      : out std_logic
	);
	end component;
	
	component AndGate
   port(
      a : IN std_logic;
      b : IN std_logic;          
      o : OUT std_logic
      );
   end component;
	
	component FF_Symmetrical is port (
        clk  : in  std_logic;
        ena  : in  std_logic;
        A    : in  std_logic;
        B    : in  std_logic;
        Q    : out std_logic
	);
	end component;
	
begin

	rst_n <= reset;  -- '1' = run, '0' = reset

  ----------------------------------------------------------------
  -- Clock-enable tick generator (no second clock domain!)
  ----------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        tick_cnt <= (others=>'0');
        ce_tick  <= '0';
      else
        if tick_cnt = 9 then            -- /10 tick (adjust as you like)
          tick_cnt <= (others=>'0');
          ce_tick  <= '1';              -- 1-cycle pulse
        else
          tick_cnt <= tick_cnt + 1;
          ce_tick  <= '0';
        end if;
      end if;
    end if;
  end process;

  ----------------------------------------------------------------
  -- Launch exactly once (edge-detect ena_get), only on a tick
  ----------------------------------------------------------------
process(clk)
begin
  if rising_edge(clk) then
    if rst_n = '0' then
      ena_q       <= '0';
      start_pulse <= '0';
    else
      ena_q       <= ena_get;
      start_pulse <= (ena_get and not ena_q) xor ce_tick;  -- 1-cycle pulse
    end if;
  end if;
end process;

  -- Drive stage-0 of all lanes with the single launch pulse
len_gate(0)  <= enable_in(0) and start_pulse;
len2_gate(0) <= enable_in(1) and start_pulse;
len3_gate(0) <= enable_in(2) and start_pulse;
len4_gate(0) <= enable_in(3) and start_pulse;


	-- Generate the 128 arrays of MUX2-1

	buildarbiter1: for i in 1 to len_gate'high generate		-- Generate the Not Gate as much as Signals
		MuxGate_i : mux2 port map ( 
				data0  => len_gate(i-1), 						-- LUT input
				data1	 => len2_gate(i-1),
				sel	 => challenge(i-1), 
				result  => len_gate(i)    						-- LUT general output
			);
	end generate;

	buildarbiter2: for i in 1 to len2_gate'high generate		-- Generate the Not Gate as much as Signals
		MuxGate_ii : mux2 port map ( 
				data0  => len_gate(i-1), 						-- LUT input
				data1	 => len2_gate(i-1),
				sel	 => challenge(i-1), 
				result  => len2_gate(i)    						-- LUT general output
			);
	end generate;
	
	buildarbiter3: for i in 1 to len3_gate'high generate		-- Generate the Not Gate as much as Signals
		MuxGate_iii : mux2 port map ( 
				data0  => len3_gate(i-1), 						-- LUT input
				data1	 => len4_gate(i-1),
				sel	 => challenge(i-1), 
				result  => len3_gate(i)    						-- LUT general output
			);
	end generate;

	buildarbiter4: for i in 1 to len4_gate'high generate		-- Generate the Not Gate as much as Signals
		MuxGate_iv : mux2 port map ( 
				data0  => len3_gate(i-1), 						-- LUT input
				data1	 => len4_gate(i-1),
				sel	 => challenge(i-1), 
				result  => len4_gate(i)    						-- LUT general output
			);
	end generate;
	
	--Tailers were used to measure the delay path inside the PUF
	
	--tail0 <= len_gate(127);
	--tail1 <= len2_gate(127);
	--tail2 <= len3_gate(127);
	--tail3 <= len4_gate(127);

	-- use the SAME clock, and sample only on that strobe
	ArbFF1: FF_Symmetrical
	  port map (
		 clk => clk,
		 ena => ena_get,   -- was ena_get
		 A   => len_gate(127),
		 B   => len2_gate(127),
		 Q   => FF1
	  );
	  
	 ArbFF2: FF_Symmetrical
	  port map (
		 clk => clk,
		 ena => ena_get,   -- was ena_get
		 A   => len3_gate(127),
		 B   => len4_gate(127),
		 Q   => FF2
	  );
	  
	R_plus  <= FF1;  -- lanes (0,2)
	R_minus <= FF2; -- lanes (1,3)
		 
	pulse <= R_plus xor R_minus;
	response <= pulse;
-- Output assignment

end main;