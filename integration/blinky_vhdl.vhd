-- SPDX-License-Identifier: Apache-2.0
-- VHDL blinky design for openxc7 testing.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity up_counter_vhdl is
  generic (
    WIDTH : integer := 8
  );
  port (
    clk   : in  std_logic;
    reset : in  std_logic;
    \out\ : out std_logic
  );
end entity;

architecture rtl of up_counter_vhdl is
  signal count : unsigned(WIDTH - 1 downto 0) := (others => '0');
begin
  process(clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        count <= (others => '0');
      else
        count <= count + 1;
      end if;
    end if;
  end process;

  \out\ <= count(WIDTH - 1);
end architecture;
