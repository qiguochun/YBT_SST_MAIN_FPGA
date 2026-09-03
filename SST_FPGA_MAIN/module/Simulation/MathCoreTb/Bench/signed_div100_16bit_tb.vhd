--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   signed_div100_16bit_tb.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   signed_div100_16bit TB。
--------------------------------------------------------------------------------
--Version           :   Rev 0.1
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.env.all;

entity signed_div100_16bit_tb is
end entity signed_div100_16bit_tb;

architecture sim of signed_div100_16bit_tb is

    constant CLK_PERIOD : time := 10 ns;

    signal i_sys_clk    : std_logic := '0';
    signal i_sys_rst    : std_logic := '1';
    signal i_data       : signed(15 downto 0) := (others => '0');
    signal i_data_valid : std_logic := '0';
    signal o_data       : signed(15 downto 0);
    signal o_data_valid : std_logic;

begin

    U_DUT : entity work.signed_div100_16bit
        port map (
            i_sys_clk    => i_sys_clk,
            i_sys_rst    => i_sys_rst,
            i_data       => i_data,
            i_data_valid => i_data_valid,
            o_data       => o_data,
            o_data_valid => o_data_valid
        );

    i_sys_clk <= not i_sys_clk after CLK_PERIOD / 2;

    monitor : process (i_sys_clk)
    begin
        if rising_edge(i_sys_clk) then
            if o_data_valid = '1' then
                report "OUT valid data=" & integer'image(to_integer(o_data))
                    severity note;
            end if;
        end if;
    end process;

    stimulus : process
        variable v_error_count : natural := 0;
        variable v_seed1       : positive := 1;
        variable v_seed2       : positive := 1;
        variable v_rand        : real;
        variable v_din         : integer;
        variable v_exp         : integer;
        variable v_err_abs     : integer;

        procedure test_case (
            constant test_input      : in integer;
            constant check_exact     : in boolean;
            constant expected_result : in integer
        ) is
        begin
            i_data       <= to_signed(test_input, 16);
            i_data_valid <= '1';
            wait until rising_edge(i_sys_clk);
            i_data_valid <= '0';

            wait until rising_edge(i_sys_clk) and o_data_valid = '1';

            v_exp     := test_input / 100;
            v_err_abs := abs(to_integer(o_data) - v_exp);

            if check_exact then
                if abs(to_integer(o_data) - expected_result) > 1 then
                    report "FAIL in=" & integer'image(test_input) &
                           " expect~=" & integer'image(expected_result) &
                           " got=" & integer'image(to_integer(o_data))
                        severity error;
                    v_error_count := v_error_count + 1;
                else
                    report "PASS in=" & integer'image(test_input) &
                           " expect~=" & integer'image(expected_result) &
                           " got=" & integer'image(to_integer(o_data))
                        severity note;
                end if;
            else
                if v_err_abs > 1 then
                    report "FAIL in=" & integer'image(test_input) &
                           " ref=" & integer'image(v_exp) &
                           " got=" & integer'image(to_integer(o_data))
                        severity error;
                    v_error_count := v_error_count + 1;
                else
                    report "PASS in=" & integer'image(test_input) &
                           " got=" & integer'image(to_integer(o_data)) &
                           " ref=" & integer'image(v_exp)
                        severity note;
                end if;
            end if;

            wait for CLK_PERIOD;
        end procedure;
    begin
        i_sys_rst    <= '1';
        i_data       <= (others => '0');
        i_data_valid <= '0';
        wait for 2 * CLK_PERIOD;
        i_sys_rst    <= '0';
        wait for CLK_PERIOD;

        report "=== Boundary ===" severity note;
        test_case(100, true, 1);
        test_case(1000, true, 10);
        test_case(32767, true, 327);
        test_case(-32768, true, -327);

        report "=== Random ===" severity note;
        for i in 0 to 19 loop
            uniform(v_seed1, v_seed2, v_rand);
            v_din := integer(v_rand * 65535.0) - 32768;
            test_case(v_din, false, 0);
        end loop;

        report "=== Continuous stream ===" severity note;
        i_data_valid <= '1';
        for i in 1 to 20 loop
            i_data <= to_signed(i * 100, 16);
            wait until rising_edge(i_sys_clk);
        end loop;
        i_data_valid <= '0';
        wait for 10 * CLK_PERIOD;

        report "========== Summary ==========" severity note;
        if v_error_count = 0 then
            report "ALL PASS" severity note;
        else
            report "Errors=" & integer'image(v_error_count) severity error;
        end if;

        stop(0);
        wait;
    end process;

end architecture sim;
