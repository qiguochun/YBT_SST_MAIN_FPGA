--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   division100_16bit.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   8 路有符号 16bit 数据分时除以 100。
--                      以 i_cnt_1us 为节拍锁存输入，展宽后轮询送入
--                      signed_div100_16bit，再在下一 1us 节拍同步输出。
--------------------------------------------------------------------------------
--Version           :   Rev 0.0
--modifier          :
--Modify Date       :
--Modify Record     :
--------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity division100_16bit is
    port (
        -- Global Clock
        i_sys_clk : in  std_logic;
        i_sys_rst : in  std_logic;  -- 异步复位，高有效
        i_cnt_1us : in  std_logic;  -- 1 us 公共时基脉冲

        -- User Interface
        i_data_in0 : in  signed(15 downto 0);
        i_data_in1 : in  signed(15 downto 0);
        i_data_in2 : in  signed(15 downto 0);
        i_data_in3 : in  signed(15 downto 0);
        i_data_in4 : in  signed(15 downto 0);
        i_data_in5 : in  signed(15 downto 0);
        i_data_in6 : in  signed(15 downto 0);
        i_data_in7 : in  signed(15 downto 0);

        o_data_out0 : out signed(15 downto 0);
        o_data_out1 : out signed(15 downto 0);
        o_data_out2 : out signed(15 downto 0);
        o_data_out3 : out signed(15 downto 0);
        o_data_out4 : out signed(15 downto 0);
        o_data_out5 : out signed(15 downto 0);
        o_data_out6 : out signed(15 downto 0);
        o_data_out7 : out signed(15 downto 0)
    );
end entity division100_16bit;

architecture rtl of division100_16bit is

    type t_data_arr is array (0 to 7) of signed(15 downto 0);

    signal r_data_in  : t_data_arr := (others => (others => '0'));
    signal r_data_out : t_data_arr := (others => (others => '0'));

    signal r_calc_en : std_logic_vector(7 downto 0) := (others => '0');
    signal w_calc_en : std_logic;

    signal r_idx_in  : unsigned(3 downto 0) := (others => '0');
    signal r_idx_out : unsigned(3 downto 0) := (others => '0');

    signal r_data_mux    : signed(15 downto 0) := (others => '0');
    signal r_data_in_valid : std_logic := '0';

    signal w_data_out       : signed(15 downto 0);
    signal w_data_out_valid : std_logic;

    signal r_data_out0 : signed(15 downto 0) := (others => '0');
    signal r_data_out1 : signed(15 downto 0) := (others => '0');
    signal r_data_out2 : signed(15 downto 0) := (others => '0');
    signal r_data_out3 : signed(15 downto 0) := (others => '0');
    signal r_data_out4 : signed(15 downto 0) := (others => '0');
    signal r_data_out5 : signed(15 downto 0) := (others => '0');
    signal r_data_out6 : signed(15 downto 0) := (others => '0');
    signal r_data_out7 : signed(15 downto 0) := (others => '0');

begin

    w_calc_en <= or r_calc_en;  -- VHDL-2008 归约或

    o_data_out0 <= r_data_out0;
    o_data_out1 <= r_data_out1;
    o_data_out2 <= r_data_out2;
    o_data_out3 <= r_data_out3;
    o_data_out4 <= r_data_out4;
    o_data_out5 <= r_data_out5;
    o_data_out6 <= r_data_out6;
    o_data_out7 <= r_data_out7;

    -- ===================== 1us 锁存 8 路输入 =====================
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_data_in <= (others => (others => '0'));
        elsif rising_edge(i_sys_clk) then
            if i_cnt_1us = '1' then
                r_data_in(0) <= i_data_in0;
                r_data_in(1) <= i_data_in1;
                r_data_in(2) <= i_data_in2;
                r_data_in(3) <= i_data_in3;
                r_data_in(4) <= i_data_in4;
                r_data_in(5) <= i_data_in5;
                r_data_in(6) <= i_data_in6;
                r_data_in(7) <= i_data_in7;
            end if;
        end if;
    end process;

    -- ===================== 1us 脉冲展宽 =====================
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_calc_en <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            r_calc_en <= r_calc_en(6 downto 0) & i_cnt_1us;
        end if;
    end process;

    -- ===================== 分时送入除 100 核 =====================
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_data_in_valid <= '0';
            r_data_mux      <= (others => '0');
            r_idx_in        <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            if w_calc_en = '1' then
                r_data_in_valid <= '1';
                r_data_mux      <= r_data_in(to_integer(r_idx_in(2 downto 0)));
                r_idx_in        <= r_idx_in + 1;
            else
                r_data_in_valid <= '0';
                r_idx_in        <= (others => '0');
            end if;
        end if;
    end process;

    -- ===================== 回收除 100 结果 =====================
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_data_out <= (others => (others => '0'));
            r_idx_out  <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            if w_data_out_valid = '1' then
                r_data_out(to_integer(r_idx_out(2 downto 0))) <= w_data_out;
                r_idx_out <= r_idx_out + 1;
            else
                r_idx_out <= (others => '0');
            end if;
        end if;
    end process;

    -- ===================== 1us 同步输出 =====================
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_data_out0 <= (others => '0');
            r_data_out1 <= (others => '0');
            r_data_out2 <= (others => '0');
            r_data_out3 <= (others => '0');
            r_data_out4 <= (others => '0');
            r_data_out5 <= (others => '0');
            r_data_out6 <= (others => '0');
            r_data_out7 <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            if i_cnt_1us = '1' then
                r_data_out0 <= r_data_out(0);
                r_data_out1 <= r_data_out(1);
                r_data_out2 <= r_data_out(2);
                r_data_out3 <= r_data_out(3);
                r_data_out4 <= r_data_out(4);
                r_data_out5 <= r_data_out(5);
                r_data_out6 <= r_data_out(6);
                r_data_out7 <= r_data_out(7);
            end if;
        end if;
    end process;

    -- ===================== 除 100 核例化 =====================
    U_SIGNED_DIV100 : entity work.signed_div100_16bit
        port map (
            i_sys_clk    => i_sys_clk,
            i_sys_rst    => i_sys_rst,
            i_data       => r_data_mux,
            i_data_valid => r_data_in_valid,
            o_data       => w_data_out,
            o_data_valid => w_data_out_valid
        );

end architecture rtl;
