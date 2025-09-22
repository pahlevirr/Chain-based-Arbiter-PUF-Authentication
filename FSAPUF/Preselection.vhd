library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity Preselection is
	port (
		mainclock_ps      : in  std_logic                    := '0';             --   clk.clk
		mainreset_ps 		: in  std_logic                    := '1';             -- reset.reset_n
		ena_out_ps			: in  std_logic_vector(3 downto 0);
		voting_done_ps		: out std_logic;
		voteACK_ps		   : in std_logic;
		res_out_ps			: in std_logic_vector(7 downto 0);
		pulse_stable_ps   : out std_logic_vector(7 downto 0)
		
	);
end entity Preselection;

architecture main of Preselection is

	constant N : integer := 2; -- Number of samples for majority voting	

	signal sample_counter 	: integer range 0 to N := 0;
	
	type integer_array is array (7 downto 0) of integer;
	signal vote_counter   : integer_array := (others => 0);

-- Enumerated type declaration and state signal declaration
	type t_State is (WaitVote, CollectSample, VoteDetermine, VoteWaitACK);
	signal VoteState : t_State := WaitVote;


begin

-- Majority voting process
    process (mainclock_ps, mainreset_ps)
    begin
        if mainreset_ps = '0' then
            sample_counter <= 0;
            vote_counter <= (others => 0);
            pulse_stable_ps <= (others => '0');
            voting_done_ps <= '0';
        elsif rising_edge(mainclock_ps) then
				
				case VoteState is
					
					when WaitVote =>
						if ena_out_ps = "1111" then
							VoteState <= CollectSample;
						end if;
					
					when CollectSample =>
					
						if sample_counter < N then
							 -- Sample the pulse signal
							 for i in 0 to 7 loop
								  if res_out_ps(i) = '1' then
										vote_counter(i) <= vote_counter(i) + 1;
								  end if;
							 end loop;
							 sample_counter <= sample_counter + 1;
							 voting_done_ps <= '0';
						else
							VoteState <= VoteDetermine;
							
						end if;
					
					when VoteDetermine =>
						
						-- Determine the majority vote for each bit position
						for i in 0 to 7 loop
							if vote_counter(i) > (N / 2) then
								pulse_stable_ps(i) <= '1';
							else
								pulse_stable_ps(i) <= '0';
							end if;
						end loop;
						-- Set the done flag
						voting_done_ps <= '1';
						VoteState <= VoteWaitACK;
						
					when VoteWaitACK =>
						if voteACK_ps = '1' then							
							 -- Reset counters for the next round of sampling
							 sample_counter <= 0;
							 vote_counter <= (others => 0);
							 voting_done_ps <= '0';
							 VoteState <= WaitVote;
						end if;
				end case;
        end if;
    end process;

end;