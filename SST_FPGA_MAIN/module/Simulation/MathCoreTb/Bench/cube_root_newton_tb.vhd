--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   cube_root_newton_tb.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   cube_root_newton TB。
--------------------------------------------------------------------------------
--Version           :   Rev 0.1
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity cube_root_newton_tb is
end entity cube_root_newton_tb;

architecture sim of cube_root_newton_tb is

    constant WIDTH      : positive := 16;
    constant ITERATIONS : positive := 20;
    constant CLK_PERIOD : time     := 10 ns;
    constant TIMEOUT    : time     := 2 ms;

    signal i_sys_clk    : std_logic := '0';
    signal i_sys_rst    : std_logic := '1';
    signal i_data       : signed(WIDTH - 1 downto 0) := (others => '0');
    signal i_data_valid : std_logic := '0';
    signal o_data       : signed(WIDTH - 1 downto 0);
    signal o_data_valid : std_logic;
    signal o_busy       : std_logic;

    type t_int_arr is array (0 to 9) of integer;
    -- skip din=1 (xn=iData>>>1 becomes 0, divide-by-zero)
    -- and 32767 may overflow intermediate path on WIDTH=16
    constant C_TEST_IN  : t_int_arr := (0, 8, 27, 64, 125, 1000, 1331, -8, -27, -64);
    constant C_TEST_EXP : t_int_arr := (0, 2, 3, 4, 5, 10, 11, -2, -3, -4);

begin

    U_DUT : entity work.cube_root_newton
        generic map (
            WIDTH      => WIDTH,
            ITERATIONS => ITERATIONS
        )
        port map (
            i_sys_clk    => i_sys_clk,
            i_sys_rst    => i_sys_rst,
            i_data       => i_data,
            i_data_valid => i_data_valid,
            o_data       => o_data,
            o_data_valid => o_data_valid,
            o_busy       => o_busy
        );

    i_sys_clk <= not i_sys_clk after CLK_PERIOD / 2;

    monitor : process (i_sys_clk)
    begin
        if rising_edge(i_sys_clk) then
            if o_data_valid = '1' then
                report "cbrt result=" & integer'image(to_integer(o_data))
                    severity note;
            end if;
        end if;
    end process;

    stimulus : process
        variable v_error_count : natural := 0;
        variable v_tol         : integer;

        procedure run_test_case (
            constant test_num : in natural;
            constant din      : in integer;
            constant expv     : in integer
        ) is
        begin
            report "Case " & integer'image(test_num) &
                   ": in=" & integer'image(din) &
                   " expect=" & integer'image(expv)
                severity note;

            i_data       <= to_signed(din, WIDTH);
            i_data_valid <= '1';
            wait until rising_edge(i_sys_clk);
            i_data_valid <= '0';

            wait until rising_edge(i_sys_clk) and o_data_valid = '1' for TIMEOUT;
            if o_data_valid /= '1' then
                report "  TIMEOUT" severity error;
                v_error_count := v_error_count + 1;
            else
                if abs(din) >= 1000 then
                    v_tol := 1;
                else
                    v_tol := 0;
                end if;
                if abs(to_integer(o_data) - expv) > v_tol then
                    report "  FAIL expect=" & integer'image(expv) &
                           " got=" & integer'image(to_integer(o_data))
                        severity error;
                    v_error_count := v_error_count + 1;
                else
                    report "  PASS" severity note;
                end if;
            end if;

            wait until o_busy = '0' for TIMEOUT;
            wait for 10 * CLK_PERIOD;
        end procedure;
    begin
        i_sys_rst    <= '1';
        i_data       <= (others => '0');
        i_data_valid <= '0';
        wait for 2 * CLK_PERIOD;
        i_sys_rst    <= '0';
        wait for 2 * CLK_PERIOD;

        report "========== CubeRootNewton TB ==========" severity note;

        for i in 0 to 9 loop
            run_test_case(i, C_TEST_IN(i), C_TEST_EXP(i));
        end loop;

        report "Busy check..." severity note;
        if o_busy /= '0' then
            report "FAIL idle busy should be 0" severity error;
            v_error_count := v_error_count + 1;
        end if;
        i_data       <= to_signed(64, WIDTH);
        i_data_valid <= '1';
        wait until rising_edge(i_sys_clk);
        i_data_valid <= '0';
        -- busy is Moore-registered: need one more cycle after state leaves IDLE
        wait until rising_edge(i_sys_clk);
        wait until rising_edge(i_sys_clk);
        if o_busy /= '1' then
            report "FAIL busy after start should be 1" severity error;
            v_error_count := v_error_count + 1;
        end if;
        wait until rising_edge(i_sys_clk) and o_data_valid = '1' for TIMEOUT;
        wait until o_busy = '0' for TIMEOUT;
        if o_busy /= '0' then
            report "FAIL busy after done should be 0" severity error;
            v_error_count := v_error_count + 1;
        end if;

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
