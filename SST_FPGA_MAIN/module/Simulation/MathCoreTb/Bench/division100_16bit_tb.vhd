--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   division100_16bit_tb.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   division100_16bit TB。
--                      自带 i_cnt_1us 激励。
--------------------------------------------------------------------------------
--Version           :   Rev 0.1
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity division100_16bit_tb is
end entity division100_16bit_tb;

architecture sim of division100_16bit_tb is

    constant CLK_PERIOD : time     := 10 ns;
    constant CNT_1US    : positive := 100;

    signal i_sys_clk : std_logic := '0';
    signal i_sys_rst : std_logic := '1';
    signal i_cnt_1us : std_logic := '0';

    signal i_data_in0 : signed(15 downto 0) := (others => '0');
    signal i_data_in1 : signed(15 downto 0) := (others => '0');
    signal i_data_in2 : signed(15 downto 0) := (others => '0');
    signal i_data_in3 : signed(15 downto 0) := (others => '0');
    signal i_data_in4 : signed(15 downto 0) := (others => '0');
    signal i_data_in5 : signed(15 downto 0) := (others => '0');
    signal i_data_in6 : signed(15 downto 0) := (others => '0');
    signal i_data_in7 : signed(15 downto 0) := (others => '0');

    signal o_data_out0 : signed(15 downto 0);
    signal o_data_out1 : signed(15 downto 0);
    signal o_data_out2 : signed(15 downto 0);
    signal o_data_out3 : signed(15 downto 0);
    signal o_data_out4 : signed(15 downto 0);
    signal o_data_out5 : signed(15 downto 0);
    signal o_data_out6 : signed(15 downto 0);
    signal o_data_out7 : signed(15 downto 0);

    signal r_us_cnt : unsigned(7 downto 0) := (others => '0');

begin

    U_DUT : entity work.division100_16bit
        port map (
            i_sys_clk   => i_sys_clk,
            i_sys_rst   => i_sys_rst,
            i_cnt_1us   => i_cnt_1us,
            i_data_in0  => i_data_in0,
            i_data_in1  => i_data_in1,
            i_data_in2  => i_data_in2,
            i_data_in3  => i_data_in3,
            i_data_in4  => i_data_in4,
            i_data_in5  => i_data_in5,
            i_data_in6  => i_data_in6,
            i_data_in7  => i_data_in7,
            o_data_out0 => o_data_out0,
            o_data_out1 => o_data_out1,
            o_data_out2 => o_data_out2,
            o_data_out3 => o_data_out3,
            o_data_out4 => o_data_out4,
            o_data_out5 => o_data_out5,
            o_data_out6 => o_data_out6,
            o_data_out7 => o_data_out7
        );

    i_sys_clk <= not i_sys_clk after CLK_PERIOD / 2;

    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_us_cnt  <= (others => '0');
            i_cnt_1us <= '0';
        elsif rising_edge(i_sys_clk) then
            if r_us_cnt = CNT_1US - 1 then
                r_us_cnt  <= (others => '0');
                i_cnt_1us <= '1';
            else
                r_us_cnt  <= r_us_cnt + 1;
                i_cnt_1us <= '0';
            end if;
        end if;
    end process;

    stimulus : process
        variable v_error_count : natural := 0;

        procedure set_inputs (
            constant v0, v1, v2, v3, v4, v5, v6, v7 : in integer
        ) is
        begin
            i_data_in0 <= to_signed(v0, 16);
            i_data_in1 <= to_signed(v1, 16);
            i_data_in2 <= to_signed(v2, 16);
            i_data_in3 <= to_signed(v3, 16);
            i_data_in4 <= to_signed(v4, 16);
            i_data_in5 <= to_signed(v5, 16);
            i_data_in6 <= to_signed(v6, 16);
            i_data_in7 <= to_signed(v7, 16);
        end procedure;

        procedure check_chan (
            constant name : in string;
            signal   dout : in signed(15 downto 0);
            constant din  : in integer;
            constant expv : in integer
        ) is
        begin
            if abs(to_integer(dout) - expv) > 2 then
                report name & " FAIL in=" & integer'image(din) &
                       " out=" & integer'image(to_integer(dout)) &
                       " expect~=" & integer'image(expv)
                    severity error;
                v_error_count := v_error_count + 1;
            else
                report name & " PASS in=" & integer'image(din) &
                       " out=" & integer'image(to_integer(dout)) &
                       " expect~=" & integer'image(expv)
                    severity note;
            end if;
        end procedure;

        procedure wait_us_pulses (constant n : in positive) is
        begin
            for i in 1 to n loop
                wait until rising_edge(i_sys_clk) and i_cnt_1us = '1';
            end loop;
        end procedure;
    begin
        i_sys_rst <= '1';
        set_inputs(0, 0, 0, 0, 0, 0, 0, 0);
        wait for 2 * CLK_PERIOD;
        i_sys_rst <= '0';
        wait for 2 * CLK_PERIOD;

        set_inputs(1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000);
        wait_us_pulses(3);

        report "Test1 Positive:" severity note;
        check_chan("ch0", o_data_out0, 1000, 10);
        check_chan("ch1", o_data_out1, 2000, 20);
        check_chan("ch2", o_data_out2, 3000, 30);
        check_chan("ch3", o_data_out3, 4000, 40);
        check_chan("ch4", o_data_out4, 5000, 50);
        check_chan("ch5", o_data_out5, 6000, 60);
        check_chan("ch6", o_data_out6, 7000, 70);
        check_chan("ch7", o_data_out7, 8000, 80);

        set_inputs(-1000, -2000, -3000, -4000, -5000, -6000, -7000, -8000);
        wait_us_pulses(3);

        report "Test2 Negative:" severity note;
        check_chan("ch0", o_data_out0, -1000, -10);
        check_chan("ch1", o_data_out1, -2000, -20);
        check_chan("ch2", o_data_out2, -3000, -30);
        check_chan("ch3", o_data_out3, -4000, -40);
        check_chan("ch4", o_data_out4, -5000, -50);
        check_chan("ch5", o_data_out5, -6000, -60);
        check_chan("ch6", o_data_out6, -7000, -70);
        check_chan("ch7", o_data_out7, -8000, -80);

        set_inputs(32767, -32768, 0, 1, -1, 99, 100, 101);
        wait_us_pulses(3);

        report "Test3 Boundary:" severity note;
        check_chan("ch0", o_data_out0, 32767, 327);
        check_chan("ch1", o_data_out1, -32768, -327);
        check_chan("ch2", o_data_out2, 0, 0);
        check_chan("ch3", o_data_out3, 1, 0);
        check_chan("ch4", o_data_out4, -1, 0);
        check_chan("ch5", o_data_out5, 99, 0);
        check_chan("ch6", o_data_out6, 100, 1);
        check_chan("ch7", o_data_out7, 101, 1);

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
