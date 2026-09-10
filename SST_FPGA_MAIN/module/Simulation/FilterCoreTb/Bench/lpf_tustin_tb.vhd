--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   lpf_tustin_tb.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   lpf_tustin 冒烟：阶跃响应单调逼近且稳态误差有界。
--------------------------------------------------------------------------------
--Version           :   Rev 0.1
--modifier          :
--Modify Date       :
--Modify Record     :
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity lpf_tustin_tb is
end entity lpf_tustin_tb;

architecture sim of lpf_tustin_tb is

    constant C_CLK_PERIOD : time := 10 ns;  -- 100 MHz

    signal i_sys_clk      : std_logic := '0';
    signal i_input        : signed(31 downto 0) := (others => '0');
    signal i_sample_pulse : std_logic := '0';
    signal o_output       : signed(31 downto 0);

    signal r_stop : boolean := false;

    procedure p_pulse_sample(
        signal clk   : in  std_logic;
        signal pulse : out std_logic
    ) is
    begin
        wait until rising_edge(clk);
        pulse <= '1';
        wait until rising_edge(clk);
        pulse <= '0';
        -- 留出流水拍（采样链 6 拍 + 余量）
        for i in 1 to 20 loop
            wait until rising_edge(clk);
        end loop;
    end procedure;

begin

    i_sys_clk <= not i_sys_clk after C_CLK_PERIOD / 2 when not r_stop else '0';

    u_dut : entity work.lpf_tustin
        generic map (
            TRI_MODE => 0,
            WC       => 6280,
            FS       => 53418
        )
        port map (
            i_sys_clk      => i_sys_clk,
            i_input        => i_input,
            i_sample_pulse => i_sample_pulse,
            o_output       => o_output
        );

    process
        variable v_prev : signed(31 downto 0);
        variable v_fail : boolean := false;
        constant C_STEP : signed(31 downto 0) := to_signed(5000, 32);
        constant C_TOL  : integer := 50;  -- 稳态容差
    begin
        wait for 100 ns;
        i_input <= C_STEP;

        -- 预热若干采样
        for k in 1 to 5 loop
            p_pulse_sample(i_sys_clk, i_sample_pulse);
        end loop;

        v_prev := o_output;

        -- 阶跃后输出应总体上升（允许偶发持平）
        for k in 1 to 200 loop
            p_pulse_sample(i_sys_clk, i_sample_pulse);
            if o_output < v_prev - 2 then
                report "FAIL: non-monotonic decrease at sample " & integer'image(k)
                    severity error;
                v_fail := true;
                exit;
            end if;
            v_prev := o_output;
        end loop;

        if (to_integer(o_output) < to_integer(C_STEP) - C_TOL) or
           (to_integer(o_output) > to_integer(C_STEP) + C_TOL) then
            report "FAIL: steady-state out of range, y=" & integer'image(to_integer(o_output))
                severity error;
            v_fail := true;
        end if;

        if not v_fail then
            report "PASS: lpf_tustin step response OK, y=" & integer'image(to_integer(o_output))
                severity note;
            report "ALL PASS" severity note;
        else
            report "ALL FAIL" severity error;
        end if;

        r_stop <= true;
        wait;
    end process;

end architecture sim;
