--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   cube_root_iter_tb.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   cube_root_iter TB。
--------------------------------------------------------------------------------
--Version           :   Rev 0.1
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity cube_root_iter_tb is
end entity cube_root_iter_tb;

architecture sim of cube_root_iter_tb is

    constant WIDTH      : positive := 32;
    constant ITER_NUM   : positive := 10;
    constant CLK_PERIOD : time     := 10 ns;
    constant TIMEOUT    : time     := 2 ms;

    signal i_sys_clk : std_logic := '0';
    signal i_sys_rst : std_logic := '1';
    signal i_start   : std_logic := '0';
    signal i_data    : signed(WIDTH - 1 downto 0) := (others => '0');
    signal o_data    : signed(WIDTH - 1 downto 0);
    signal o_done    : std_logic;

begin

    U_DUT : entity work.cube_root_iter
        generic map (
            WIDTH    => WIDTH,
            ITER_NUM => ITER_NUM
        )
        port map (
            i_sys_clk => i_sys_clk,
            i_sys_rst => i_sys_rst,
            i_start   => i_start,
            i_data    => i_data,
            o_data    => o_data,
            o_done    => o_done
        );

    i_sys_clk <= not i_sys_clk after CLK_PERIOD / 2;

    stimulus : process
        variable v_error_count : natural := 0;

        procedure run_one (
            constant din  : in integer;
            constant expv : in integer
        ) is
        begin
            i_data  <= to_signed(din, WIDTH);
            i_start <= '1';
            wait until rising_edge(i_sys_clk);
            i_start <= '0';

            wait until rising_edge(i_sys_clk) and o_done = '1' for TIMEOUT;
            if o_done /= '1' then
                report "TIMEOUT din=" & integer'image(din) severity error;
                v_error_count := v_error_count + 1;
            elsif to_integer(o_data) /= expv then
                report "FAIL din=" & integer'image(din) &
                       " expect=" & integer'image(expv) &
                       " got=" & integer'image(to_integer(o_data))
                    severity error;
                v_error_count := v_error_count + 1;
            else
                report "PASS din=" & integer'image(din) &
                       " cbrt=" & integer'image(to_integer(o_data))
                    severity note;
            end if;

            wait for 5 * CLK_PERIOD;
        end procedure;
    begin
        i_sys_rst <= '1';
        i_start   <= '0';
        i_data    <= (others => '0');
        wait for 2 * CLK_PERIOD;
        i_sys_rst <= '0';
        wait for 2 * CLK_PERIOD;

        report "========== CubeRootIter TB ==========" severity note;

        run_one(27, 3);
        run_one(64, 4);
        run_one(125, 5);
        run_one(-27, -3);

        report "========== Summary ==========" severity note;
        if v_error_count = 0 then
            report "ALL PASS" severity note;
        else
            report "Errors=" & integer'image(v_error_count) severity error;
        end if;

        wait for 10 * CLK_PERIOD;
        stop(0);
        wait;
    end process;

end architecture sim;
