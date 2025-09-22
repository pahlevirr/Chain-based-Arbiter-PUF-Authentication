library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity Flip_Flop_Symmetrical is port (
  A: in std_logic; -- Acts like clock.
  B: in std_logic;
  Q: out std_logic);
end Flip_Flop_Symmetrical;

architecture Behavioral of Flip_Flop_Symmetrical is

begin

  D_FLIP_FLOP: process(A)
  begin
    if (A = '1' and A'event) then
      Q <= B;
    end if;
  end process;
  
end Behavioral;