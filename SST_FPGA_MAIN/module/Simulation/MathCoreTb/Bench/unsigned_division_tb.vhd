--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   unsigned_division_tb.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   unsigned_division TB。
--------------------------------------------------------------------------------
--Version           :   Rev 0.1
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity unsigned_division_tb is
end entity unsigned_division_tb;

architecture sim of unsigned_division_tb is

    constant WIDTH_DVD  : positive := 24;
    constant WIDTH_DVS  : positive := 16;
    constant CLK_PERIOD : time     := 10 ns;

    signal i_sys_clk   : std_logic := '0';
    signal i_sys_rst   : std_logic := '1';
    signal i_start     : std_logic := '0';
    signal i_dividend  : std_logic_vector(WIDTH_DVD - 1 downto 0) := (others => '0');
    signal i_divisor   : std_logic_vector(WIDTH_DVS - 1 downto 0) := (others => '0');
    signal o_quotient  : std_logic_vector(WIDTH_DVD - 1 downto 0);
    signal o_remainder : std_logic_vector(WIDTH_DVS - 1 downto 0);
    signal o_done      : std_logic;
    signal o_busy      : std_logic;

begin

    U_DUT : entity work.unsigned_division
        generic map (
            WIDTH_DVD => WIDTH_DVD,
            WIDTH_DVS => WIDTH_DVS
        )
        port map (
            i_sys_clk   => i_sys_clk,
            i_sys_rst   => i_sys_rst,
            i_start     => i_start,
            i_dividend  => i_dividend,
            i_divisor   => i_divisor,
            o_quotient  => o_quotient,
            o_remainder => o_remainder,
            o_done      => o_done,
            o_busy      => o_busy
        );

    i_sys_clk <= not i_sys_clk after CLK_PERIOD / 2;

    stimulus : process
        variable v_test_count  : natural := 0;
        variable v_error_count : natural := 0;

        procedure run_one (
            constant dvd_i : in natural;
            constant dvs_i : in natural;
            constant exp_q : in natural;
            constant exp_r : in natural;
            constant name  : in string
        ) is
        begin
            v_test_count := v_test_count + 1;
            report "TEST: " & name severity note;

            i_dividend <= std_logic_vector(to_unsigned(dvd_i, WIDTH_DVD));
            i_divisor  <= std_logic_vector(to_unsigned(dvs_i, WIDTH_DVS));
            i_start    <= '1';
            wait until rising_edge(i_sys_clk);
            i_start    <= '0';

            wait until rising_edge(i_sys_clk) and o_done = '1';

            if (to_integer(unsigned(o_quotient)) /= exp_q) or
               (to_integer(unsigned(o_remainder)) /= exp_r) then
                report "  FAIL expect Q=" & integer'image(exp_q) &
                       " R=" & integer'image(exp_r) &
                       " got Q=" & integer'image(to_integer(unsigned(o_quotient))) &
                       " R=" & integer'image(to_integer(unsigned(o_remainder)))
                    severity error;
                v_error_count := v_error_count + 1;
            else
                report "  PASS " &
                       integer'image(dvd_i) & " / " & integer'image(dvs_i) &
                       " = " & integer'image(to_integer(unsigned(o_quotient))) &
                       " ... " & integer'image(to_integer(unsigned(o_remainder)))
                    severity note;
            end if;

            wait for 10 * CLK_PERIOD;
        end procedure;
    begin
        i_sys_rst <= '1';
        i_start   <= '0';
        wait for 2 * CLK_PERIOD;
        i_sys_rst <= '0';
        wait for 2 * CLK_PERIOD;

        report "========== Unsigned Division TB ==========" severity note;

        run_one(1000000, 256, 3906, 64, "1000000 / 256");
        run_one(123456, 789, 156, 372, "123456 / 789");
        run_one(32767, 1024, 31, 1023, "32767 / 1024");
        run_one(0, 5, 0, 0, "0 / 5");
        run_one(5, 10, 0, 5, "5 / 10");

        report "========== Summary ==========" severity note;
        report "Total=" & integer'image(v_test_count) &
               " Errors=" & integer'image(v_error_count) severity note;
        if v_error_count = 0 then
            report "ALL PASS" severity note;
        else
            report "HAS ERRORS" severity error;
        end if;

        wait for 10 * CLK_PERIOD;
        stop(0);
        wait;
    end process;

end architecture sim;
