--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   signed_division_tb.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   signed_division TB。
--                      NOTE: ModelSim VHDL report strings must be ASCII.
--------------------------------------------------------------------------------
--Version           :   Rev 0.1
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity signed_division_tb is
end entity signed_division_tb;

architecture sim of signed_division_tb is

    constant WIDTH_DVD  : positive := 16;
    constant WIDTH_DVS  : positive := 8;
    constant CLK_PERIOD : time     := 10 ns;

    signal i_sys_clk   : std_logic := '0';
    signal i_sys_rst   : std_logic := '1';
    signal i_start     : std_logic := '0';
    signal i_dividend  : signed(WIDTH_DVD - 1 downto 0) := (others => '0');
    signal i_divisor   : signed(WIDTH_DVS - 1 downto 0) := (others => '0');
    signal o_quotient  : signed(WIDTH_DVD - 1 downto 0);
    signal o_remainder : signed(WIDTH_DVS - 1 downto 0);
    signal o_done      : std_logic;
    signal o_busy      : std_logic;

begin

    U_DUT : entity work.signed_division
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

    monitor : process (i_sys_clk)
    begin
        if rising_edge(i_sys_clk) then
            if o_done = '1' then
                report "DONE: " &
                       integer'image(to_integer(i_dividend)) & " / " &
                       integer'image(to_integer(i_divisor)) & " = " &
                       integer'image(to_integer(o_quotient)) & " ... " &
                       integer'image(to_integer(o_remainder))
                    severity note;
            end if;
        end if;
    end process;

    stimulus : process
        variable v_test_count  : natural := 0;
        variable v_error_count : natural := 0;

        procedure run_division_test (
            constant dvd   : in integer;
            constant dvs   : in integer;
            constant exp_q : in integer;
            constant exp_r : in integer;
            constant name  : in string
        ) is
        begin
            v_test_count := v_test_count + 1;
            report "TEST: " & name severity note;

            i_dividend <= to_signed(dvd, WIDTH_DVD);
            i_divisor  <= to_signed(dvs, WIDTH_DVS);
            i_start    <= '1';
            wait until rising_edge(i_sys_clk);
            i_start    <= '0';

            wait until rising_edge(i_sys_clk) and o_done = '1';

            if (to_integer(o_quotient) /= exp_q) or (to_integer(o_remainder) /= exp_r) then
                report "  FAIL expect Q=" & integer'image(exp_q) &
                       " R=" & integer'image(exp_r) &
                       " got Q=" & integer'image(to_integer(o_quotient)) &
                       " R=" & integer'image(to_integer(o_remainder))
                    severity error;
                v_error_count := v_error_count + 1;
            else
                report "  PASS" severity note;
            end if;

            if dvs /= 0 then
                if dvd /= to_integer(o_quotient) * dvs + to_integer(o_remainder) then
                    report "  WARN consistency check failed" severity warning;
                end if;
            end if;

            wait for 5 * CLK_PERIOD;
        end procedure;
    begin
        i_sys_rst  <= '1';
        i_start    <= '0';
        i_dividend <= (others => '0');
        i_divisor  <= (others => '0');
        wait for 2 * CLK_PERIOD;
        i_sys_rst  <= '0';
        wait for 2 * CLK_PERIOD;

        report "========== Signed Division TB ==========" severity note;

        report "Case1: + / +" severity note;
        run_division_test(100, 7, 14, 2, "100 / 7");
        run_division_test(255, 5, 51, 0, "255 / 5");
        run_division_test(127, 3, 42, 1, "127 / 3");

        report "Case2: + / -" severity note;
        run_division_test(100, -7, -14, 2, "100 / -7");
        run_division_test(50, -6, -8, 2, "50 / -6");

        report "Case3: - / +" severity note;
        run_division_test(-100, 7, -14, -2, "-100 / 7");
        run_division_test(-50, 6, -8, -2, "-50 / 6");

        report "Case4: - / -" severity note;
        run_division_test(-100, -7, 14, -2, "-100 / -7");
        run_division_test(-50, -6, 8, -2, "-50 / -6");

        report "Case5: boundary" severity note;
        run_division_test(32767, 1, 32767, 0, "32767 / 1");
        run_division_test(1, 1, 1, 0, "1 / 1");
        run_division_test(0, 5, 0, 0, "0 / 5");

        report "Case6: |dvd| < |dvs|" severity note;
        run_division_test(5, 10, 0, 5, "5 / 10");
        run_division_test(-5, 10, 0, -5, "-5 / 10");

        report "Case7: control signals" severity note;
        v_test_count := v_test_count + 1;
        if o_busy /= '0' then
            report "  FAIL idle o_busy should be 0" severity error;
            v_error_count := v_error_count + 1;
        end if;
        i_dividend <= to_signed(100, WIDTH_DVD);
        i_divisor  <= to_signed(7, WIDTH_DVS);
        i_start    <= '1';
        wait until rising_edge(i_sys_clk);
        i_start    <= '0';
        wait until rising_edge(i_sys_clk);
        if o_busy /= '1' then
            report "  FAIL busy after start should be 1" severity error;
            v_error_count := v_error_count + 1;
        end if;
        wait until rising_edge(i_sys_clk) and o_done = '1';
        wait for 3 * CLK_PERIOD;

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
