 library IEEE;
 use IEEE.std_logic_1164.all;
 
 entity mux2 is
 port(
	data0      : in  std_logic;
	data1      : in  std_logic;
	sel     : in  std_logic;
	result       : out std_logic
	);
 end mux2;
 architecture rtl of mux2 is
	-- declarative part: empty
 begin
 p_mux : process(data0,data1,sel)
 begin
	case sel is
	  when '0' => result <= data0 ;
	  when '1' => result <= data1 ;
	  when others => NULL;
	end case;
 end process p_mux;
 end rtl;