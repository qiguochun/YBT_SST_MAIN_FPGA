--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   llc_con_core_tb.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   llc_con_core smoke TB: reset, tick, stage0 duty ramp.
--                      NOTE: report strings ASCII for ModelSim VHDL.
--------------------------------------------------------------------------------
--Version           :   Rev 0.1
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity llc_con_core_tb is
end entity llc_con_core_tb;

architecture sim of llc_con_core_tb is

    constant CLK_PERIOD : time := 33.333 ns;  -- 30 MHz

    signal i_sys_clk : std_logic := '0';
    signal i_sys_rst : std_logic := '1';
    signal i_tick    : std_logic := '0';
    signal i_vo      : std_logic_vector(15 downto 0) := (others => '0');
    signal i_edv     : std_logic_vector(15 downto 0) := std_logic_vector(to_unsigned(8000, 16));
    signal i_kp      : std_logic_vector(15 downto 0) := std_logic_vector(to_unsigned(100, 16));
    signal i_ki      : std_logic_vector(15 downto 0) := std_logic_vector(to_unsigned(10, 16));
    signal i_d2set   : std_logic_vector(15 downto 0) := (others => '0');

    signal o_duty_cmd : std_logic_vector(15 downto 0);
    signal o_period   : std_logic_vector(15 downto 0);
    signal o_state    : std_logic_vector(2 downto 0);
    signal o_done     : std_logic;
    signal o_dco      : std_logic_vector(15 downto 0);

    procedure pulse_tick (
        signal clk  : in  std_logic;
        signal tick : out std_logic
    ) is
    begin
        wait until rising_edge(clk);
        tick <= '1';
        wait until rising_edge(clk);
        tick <= '0';
        -- allow MA / PI multi-cycle
        for i in 1 to 8 loop
            wait until rising_edge(clk);
        end loop;
    end procedure;

begin

    U_DUT : entity work.llc_con_core
        port map (
            i_sys_clk  => i_sys_clk,
            i_sys_rst  => i_sys_rst,
            i_tick     => i_tick,
            i_vo       => i_vo,
            i_edv      => i_edv,
            i_kp       => i_kp,
            i_ki       => i_ki,
            i_d2set    => i_d2set,
            o_duty_cmd => o_duty_cmd,
            o_period   => o_period,
            o_state    => o_state,
            o_done     => o_done,
            o_dco      => o_dco
        );

    i_sys_clk <= not i_sys_clk after CLK_PERIOD / 2;

    stimulus : process
        variable v_err : natural := 0;
        variable v_duty0 : integer;
        variable v_duty1 : integer;
    begin
        i_sys_rst <= '1';
        i_vo      <= std_logic_vector(to_unsigned(1000, 16));
        wait for 20 * CLK_PERIOD;
        i_sys_rst <= '0';
        wait for 10 * CLK_PERIOD;

        report "========== LlcConCore TB ==========" severity note;

        -- Stage0: several ticks, duty should rise from ~1000 toward 5000
        for i in 1 to 20 loop
            pulse_tick(i_sys_clk, i_tick);
        end loop;
        v_duty0 := to_integer(unsigned(o_duty_cmd));
        report "After 20 ticks: state=" & integer'image(to_integer(unsigned(o_state))) &
               " duty=" & integer'image(v_duty0) &
               " period=" & integer'image(to_integer(unsigned(o_period)))
            severity note;

        if to_integer(unsigned(o_state)) /= 0 then
            report "FAIL expected STAGE0 early" severity error;
            v_err := v_err + 1;
        end if;
        if v_duty0 < 1000 then
            report "FAIL duty below min" severity error;
            v_err := v_err + 1;
        end if;

        for i in 1 to 200 loop
            pulse_tick(i_sys_clk, i_tick);
        end loop;
        v_duty1 := to_integer(unsigned(o_duty_cmd));
        report "After more ticks: duty=" & integer'image(v_duty1) severity note;
        if v_duty1 < v_duty0 then
            report "FAIL duty did not ramp up" severity error;
            v_err := v_err + 1;
        else
            report "PASS duty ramp" severity note;
        end if;

        -- Drive Vo high to force stage progression later (skip long wait)
        i_vo <= std_logic_vector(to_unsigned(7500, 16));
        -- Fast-forward timers by many ticks toward stage1 end region is slow;
        -- just check MA responds
        for i in 1 to 50 loop
            pulse_tick(i_sys_clk, i_tick);
        end loop;
        report "DCO=" & integer'image(to_integer(unsigned(o_dco))) &
               " state=" & integer'image(to_integer(unsigned(o_state)))
            severity note;

        report "========== Summary ==========" severity note;
        if v_err = 0 then
            report "ALL PASS" severity note;
        else
            report "Errors=" & integer'image(v_err) severity error;
        end if;

        stop(0);
        wait;
    end process;

end architecture sim;
