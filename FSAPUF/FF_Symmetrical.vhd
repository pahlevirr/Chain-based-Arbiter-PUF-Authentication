library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity FF_Symmetrical is
    port (
        clk  : in  std_logic;
        ena  : in  std_logic;
        A    : in  std_logic;
        B    : in  std_logic;
        Q    : out std_logic
    );
end FF_Symmetrical;

architecture Main of FF_Symmetrical is

begin

    process(clk)
    begin
        if rising_edge(clk) then
            if ena = '1' then
                if A > B then
                    Q <= '1';
                else
                    Q <= '0';
                end if;
            end if;
        end if;
    end process;
  
end Main;