library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity AndGate is
    Port ( a : in  STD_LOGIC;
           b : in  STD_LOGIC;
           o : out  STD_LOGIC);
end AndGate;

architecture Behavioral of AndGate is

begin
   o <= a and b;
end Behavioral;