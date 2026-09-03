--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   lpf_tustin_auto_ctrl.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   一阶低通（Tustin）自动采样版：内部按 FS 产生采样节拍。
--                      系数 Q13（*8192）；流水拍数较 lpf_tustin 少一拍。
--------------------------------------------------------------------------------
--Version           :   Rev 0.1
--modifier          :
--Modify Date       :
--Modify Record     :   系数用整数运算替代 real 常量折叠
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity lpf_tustin_auto_ctrl is
    generic (
        WC        : integer := 6280;        -- 截止角频率 wn
        FS        : integer := 40000;       -- 采样频率 (Hz)
        CALC_GAIN : integer := 1;           -- 保留与原接口一致（本模块未使用）
        CLK_FREQ  : integer := 100000000    -- 系统时钟频率 (Hz)
    );
    port (
        -- Global Clock
        i_sys_clk : in  std_logic;

        -- User Interface
        i_input   : in  signed(31 downto 0);
        o_output  : out signed(31 downto 0)
    );
end entity lpf_tustin_auto_ctrl;

architecture rtl of lpf_tustin_auto_ctrl is

    -- CALC_GAIN 保留接口兼容，算法未使用
    constant C_SHIFT   : natural := 13;  -- 8192 = 2^13
    constant C_CNT_MAX : natural := CLK_FREQ / FS;

    -- 用 32x32->64 再除，避免 integer(32) 与 64x64->128 位宽问题
    function f_coeff_a1(p_wc, p_fs : integer) return signed is
        variable v_num  : signed(31 downto 0);
        variable v_den  : signed(31 downto 0);
        variable v_prod : signed(63 downto 0);
    begin
        v_num  := to_signed(2 * p_fs - p_wc, 32);
        v_den  := to_signed(2 * p_fs + p_wc, 32);
        v_prod := v_num * to_signed(2 ** C_SHIFT, 32);
        return resize(v_prod / resize(v_den, 64), 32);
    end function;

    function f_coeff_b0(p_wc, p_fs : integer) return signed is
        variable v_num  : signed(31 downto 0);
        variable v_den  : signed(31 downto 0);
        variable v_prod : signed(63 downto 0);
    begin
        v_num  := to_signed(p_wc, 32);
        v_den  := to_signed(2 * p_fs + p_wc, 32);
        v_prod := v_num * to_signed(2 ** C_SHIFT, 32);
        return resize(v_prod / resize(v_den, 64), 32);
    end function;

    constant C_A1 : signed(31 downto 0) := f_coeff_a1(WC, FS);
    constant C_B0 : signed(31 downto 0) := f_coeff_b0(WC, FS);

    signal r_xn1      : signed(31 downto 0) := (others => '0');
    signal r_yn1      : signed(31 downto 0) := (others => '0');
    signal r_yn       : signed(31 downto 0) := (others => '0');
    signal r_xn       : signed(31 downto 0) := (others => '0');
    signal r_product1 : signed(63 downto 0) := (others => '0');
    signal r_product2 : signed(63 downto 0) := (others => '0');
    signal r_sum      : signed(63 downto 0) := (others => '0');

    signal r_cnt      : unsigned(15 downto 0) := (others => '0');
    signal w_sampling : std_logic;
    signal r_sampling : std_logic_vector(5 downto 0) := (others => '0');

begin

    o_output <= r_yn;

    -- ===================== 内部采样节拍 =====================
    process (i_sys_clk)
    begin
        if rising_edge(i_sys_clk) then
            if r_cnt = to_unsigned(C_CNT_MAX - 1, 16) then
                r_cnt <= (others => '0');
            else
                r_cnt <= r_cnt + 1;
            end if;
        end if;
    end process;

    w_sampling <= '1' when r_cnt = 0 else '0';

    process (i_sys_clk)
    begin
        if rising_edge(i_sys_clk) then
            r_sampling <= r_sampling(4 downto 0) & w_sampling;
        end if;
    end process;

    -- ===================== 乘 =====================
    process (i_sys_clk)
    begin
        if rising_edge(i_sys_clk) then
            if r_sampling(0) = '1' then
                r_product1 <= C_A1 * r_yn1;
                r_product2 <= C_B0 * (r_xn + r_xn1);
            end if;
        end if;
    end process;

    -- ===================== 加 =====================
    process (i_sys_clk)
    begin
        if rising_edge(i_sys_clk) then
            if r_sampling(2) = '1' then
                r_sum <= r_product1 + r_product2;
            end if;
        end if;
    end process;

    -- ===================== 右移取 y[n]（无半位偏置） =====================
    process (i_sys_clk)
    begin
        if rising_edge(i_sys_clk) then
            if r_sampling(3) = '1' then
                r_yn <= resize(shift_right(r_sum, C_SHIFT), 32);
            end if;
        end if;
    end process;

    -- ===================== 状态更新 =====================
    process (i_sys_clk)
    begin
        if rising_edge(i_sys_clk) then
            if r_sampling(4) = '1' then
                r_yn1 <= r_yn;
                r_xn1 <= r_xn;
                r_xn  <= i_input;
            end if;
        end if;
    end process;

end architecture rtl;
