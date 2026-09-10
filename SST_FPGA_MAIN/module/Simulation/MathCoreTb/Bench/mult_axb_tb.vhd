--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   mult_axb_tb.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   mult_axb TB, pipeline latency = 3.
--------------------------------------------------------------------------------
--Version           :   Rev 0.1
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity mult_axb_tb is
end entity mult_axb_tb;

architecture sim of mult_axb_tb is

    constant AWIDTH     : positive := 16;
    constant BWIDTH     : positive := 16;
    constant PWIDTH     : positive := 32;
    constant CLK_PERIOD : time     := 10 ns;
    constant PIPE_DLY   : positive := 3;

    signal i_sys_clk : std_logic := '0';
    signal i_a_s     : std_logic_vector(AWIDTH - 1 downto 0) := (others => '0');
    signal i_b_s     : std_logic_vector(BWIDTH - 1 downto 0) := (others => '0');
    signal o_p_s     : std_logic_vector(PWIDTH - 1 downto 0);
    signal i_a_u     : std_logic_vector(AWIDTH - 1 downto 0) := (others => '0');
    signal i_b_u     : std_logic_vector(BWIDTH - 1 downto 0) := (others => '0');
    signal o_p_u     : std_logic_vector(PWIDTH - 1 downto 0);

begin

    U_DUT_S : entity work.mult_axb
        generic map (
            AWIDTH     => AWIDTH,
            BWIDTH     => BWIDTH,
            PWIDTH     => PWIDTH,
            TC         => 1,
            PREFER_DSP => true
        )
        port map (
            i_sys_clk => i_sys_clk,
            i_a       => i_a_s,
            i_b       => i_b_s,
            o_p       => o_p_s
        );

    U_DUT_U : entity work.mult_axb
        generic map (
            AWIDTH     => AWIDTH,
            BWIDTH     => BWIDTH,
            PWIDTH     => PWIDTH,
            TC         => 0,
            PREFER_DSP => true
        )
        port map (
            i_sys_clk => i_sys_clk,
            i_a       => i_a_u,
            i_b       => i_b_u,
            o_p       => o_p_u
        );

    i_sys_clk <= not i_sys_clk after CLK_PERIOD / 2;

    stimulus : process
        variable v_error_count : natural := 0;
        variable v_exp         : integer;

        procedure check_signed(constant a, b : in integer) is
        begin
            i_a_s <= std_logic_vector(to_signed(a, AWIDTH));
            i_b_s <= std_logic_vector(to_signed(b, BWIDTH));
            for i in 1 to PIPE_DLY loop
                wait until rising_edge(i_sys_clk);
            end loop;
            wait until rising_edge(i_sys_clk);
            v_exp := a * b;
            if to_integer(signed(o_p_s)) /= v_exp then
                report "SIGNED FAIL " & integer'image(a) & "*" & integer'image(b) &
                       " expect=" & integer'image(v_exp) &
                       " got=" & integer'image(to_integer(signed(o_p_s)))
                    severity error;
                v_error_count := v_error_count + 1;
            else
                report "SIGNED PASS " & integer'image(a) & "*" & integer'image(b) &
                       " = " & integer'image(to_integer(signed(o_p_s)))
                    severity note;
            end if;
        end procedure;

        procedure check_unsigned(constant a, b : in natural) is
        begin
            i_a_u <= std_logic_vector(to_unsigned(a, AWIDTH));
            i_b_u <= std_logic_vector(to_unsigned(b, BWIDTH));
            for i in 1 to PIPE_DLY loop
                wait until rising_edge(i_sys_clk);
            end loop;
            wait until rising_edge(i_sys_clk);
            v_exp := a * b;
            if to_integer(unsigned(o_p_u)) /= v_exp then
                report "UNSIGNED FAIL " & integer'image(a) & "*" & integer'image(b)
                    severity error;
                v_error_count := v_error_count + 1;
            else
                report "UNSIGNED PASS " & integer'image(a) & "*" & integer'image(b) &
                       " = " & integer'image(to_integer(unsigned(o_p_u)))
                    severity note;
            end if;
        end procedure;
    begin
        wait for 5 * CLK_PERIOD;
        report "========== MultAxB TB ==========" severity note;

        check_signed(12, 34);
        check_signed(-12, 34);
        check_signed(-12, -34);
        check_signed(100, 0);
        check_signed(255, 255);

        check_unsigned(12, 34);
        check_unsigned(1000, 20);
        check_unsigned(65535, 1);

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
