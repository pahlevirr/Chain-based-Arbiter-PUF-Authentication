library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity XorGate is
    Port ( a : in  STD_LOGIC;
           b : in  STD_LOGIC;
           o : out  STD_LOGIC);
end XorGate;

architecture Behavioral of XorGate is

begin
   o <= a xor b;
end Behavioral;