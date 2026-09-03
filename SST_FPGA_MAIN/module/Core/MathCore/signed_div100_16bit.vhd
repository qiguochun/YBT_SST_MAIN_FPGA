--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   signed_div100_16bit.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   有符号 16bit 近似除以 100（移位加法，3 级流水）。
--                      近似式：1/100 ≈ 2^-6 - 2^-7 + 2^-8 - 2^-9 + 2^-10
--                                      - 2^-11 - 2^-12 - 2^-13 + 2^-14 + 2^-15
--------------------------------------------------------------------------------
--Version           :   Rev 0.1
--modifier          :
--Modify Date       :
--Modify Record     :   补全 >>>15 项
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity signed_div100_16bit is
    port (
        -- Global Clock
        i_sys_clk : in  std_logic;
        i_sys_rst : in  std_logic;  -- 异步复位，高有效（兼容接口；本模块主要靠 valid 流水）

        -- User Interface
        i_data       : in  signed(15 downto 0);  -- 输入数据
        i_data_valid : in  std_logic;            -- 输入有效
        o_data       : out signed(15 downto 0);  -- 输出 ≈ i_data / 100
        o_data_valid : out std_logic             -- 输出有效（相对输入延迟 4 拍）
    );
end entity signed_div100_16bit;

architecture rtl of signed_div100_16bit is

    signal r_data_valid : std_logic_vector(3 downto 0) := (others => '0');
    signal r_data_stage : signed(15 downto 0) := (others => '0');

    signal r_shift6  : signed(15 downto 0) := (others => '0');
    signal r_shift7  : signed(15 downto 0) := (others => '0');
    signal r_shift8  : signed(15 downto 0) := (others => '0');
    signal r_shift9  : signed(15 downto 0) := (others => '0');
    signal r_shift10 : signed(15 downto 0) := (others => '0');
    signal r_shift11 : signed(15 downto 0) := (others => '0');
    signal r_shift12 : signed(15 downto 0) := (others => '0');
    signal r_shift13 : signed(15 downto 0) := (others => '0');
    signal r_shift14 : signed(15 downto 0) := (others => '0');
    signal r_shift15 : signed(15 downto 0) := (others => '0');

    signal r_data1 : signed(15 downto 0) := (others => '0');
    signal r_data2 : signed(15 downto 0) := (others => '0');
    signal r_data3 : signed(15 downto 0) := (others => '0');
    signal r_data  : signed(15 downto 0) := (others => '0');

begin

    o_data_valid <= r_data_valid(3);
    o_data       <= r_data;

    -- ===================== valid 流水打拍 =====================
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_data_valid <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            r_data_valid <= r_data_valid(2 downto 0) & i_data_valid;
        end if;
    end process;

    -- ===================== 输入锁存 =====================
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_data_stage <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            if i_data_valid = '1' then
                r_data_stage <= i_data;
            end if;
        end if;
    end process;

    -- ===================== 算术右移展开 =====================
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_shift6  <= (others => '0');
            r_shift7  <= (others => '0');
            r_shift8  <= (others => '0');
            r_shift9  <= (others => '0');
            r_shift10 <= (others => '0');
            r_shift11 <= (others => '0');
            r_shift12 <= (others => '0');
            r_shift13 <= (others => '0');
            r_shift14 <= (others => '0');
            r_shift15 <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            if r_data_valid(0) = '1' then
                r_shift6  <= shift_right(r_data_stage, 6);
                r_shift7  <= shift_right(r_data_stage, 7);
                r_shift8  <= shift_right(r_data_stage, 8);
                r_shift9  <= shift_right(r_data_stage, 9);
                r_shift10 <= shift_right(r_data_stage, 10);
                r_shift11 <= shift_right(r_data_stage, 11);
                r_shift12 <= shift_right(r_data_stage, 12);
                r_shift13 <= shift_right(r_data_stage, 13);
                r_shift14 <= shift_right(r_data_stage, 14);
                r_shift15 <= shift_right(r_data_stage, 15);
            end if;
        end if;
    end process;

    -- ===================== 部分和 =====================
    -- (2^-6 - 2^-7 + 2^-8) + (-2^-9 + 2^-10 - 2^-11) + (-2^-12 - 2^-13 + 2^-14 + 2^-15)
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_data1 <= (others => '0');
            r_data2 <= (others => '0');
            r_data3 <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            if r_data_valid(1) = '1' then
                r_data1 <= r_shift6 - r_shift7 + r_shift8;
                r_data2 <= -r_shift9 + r_shift10 - r_shift11;
                r_data3 <= -r_shift12 - r_shift13 + r_shift14 + r_shift15;
            end if;
        end if;
    end process;

    -- ===================== 求和输出 =====================
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_data <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            if r_data_valid(2) = '1' then
                r_data <= r_data1 + r_data2 + r_data3;
            end if;
        end if;
    end process;

end architecture rtl;
