--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   lpf_tustin.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   一阶低通（Tustin/双线性变换）定点实现。
--                      G(s)=WC/(s+WC)；系数 Q23；采样可由外部脉冲或内部计数产生。
--------------------------------------------------------------------------------
--Version           :   Rev 0.1
--modifier          :
--Modify Date       :
--Modify Record     :   系数用整数运算替代 real 常量折叠
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity lpf_tustin is
    generic (
        TRI_MODE  : natural := 0;           -- 0: 外部 i_sample_pulse；1: 内部按 FS 分频
        WC        : integer := 6280;        -- 截止角频率 wn (rad/s 量级，与原工程一致)
        FS        : integer := 53418;       -- 采样频率 (Hz)
        CALC_GAIN : integer := 1;           -- 保留与原接口一致（本模块未使用）
        CLK_FREQ  : integer := 100000000    -- 系统时钟频率 (Hz)，TRI_MODE=1 时有效
    );
    port (
        -- Global Clock
        i_sys_clk      : in  std_logic;

        -- User Interface
        i_input        : in  signed(31 downto 0);
        i_sample_pulse : in  std_logic;  -- TRI_MODE=0 时有效
        o_output       : out signed(31 downto 0)
    );
end entity lpf_tustin;

architecture rtl of lpf_tustin is

    -- Q 格式移位：系数定点位宽 2^23
    -- CALC_GAIN 保留与原 Verilog 接口一致，本算法未使用
    constant C_SHIFT : natural := 23;
    constant C_HALF  : signed(63 downto 0) := to_signed(2 ** (C_SHIFT - 1), 64);  -- 4194304

    -- 内部采样分频计数上限
    constant C_CNT_MAX : natural := CLK_FREQ / FS;

    -- A1 = (2*FS - WC)/(2*FS + WC) * 2^23
    -- B0 = WC/(2*FS + WC) * 2^23
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
    signal r_sum_pre  : signed(63 downto 0) := (others => '0');

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

    -- ===================== 采样脉冲移位链 =====================
    process (i_sys_clk)
    begin
        if rising_edge(i_sys_clk) then
            if TRI_MODE = 1 then
                r_sampling <= r_sampling(4 downto 0) & w_sampling;
            else
                r_sampling <= r_sampling(4 downto 0) & i_sample_pulse;
            end if;
        end if;
    end process;

    -- ===================== 乘：A1*y[n-1], B0*(x[n]+x[n-1]) =====================
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
                r_sum_pre <= r_product1 + r_product2;
            end if;
        end if;
    end process;

    -- ===================== 四舍五入偏置 =====================
    process (i_sys_clk)
    begin
        if rising_edge(i_sys_clk) then
            if r_sampling(3) = '1' then
                if r_sum_pre(63) = '1' then
                    r_sum <= r_sum_pre - C_HALF;
                else
                    r_sum <= r_sum_pre + C_HALF;
                end if;
            end if;
        end if;
    end process;

    -- ===================== 右移取 y[n] =====================
    process (i_sys_clk)
    begin
        if rising_edge(i_sys_clk) then
            if r_sampling(4) = '1' then
                if (r_sum(63) = '1') and (r_sum(C_SHIFT - 1 downto 0) /= 0) then
                    r_yn <= resize(shift_right(r_sum, C_SHIFT) + 1, 32);
                else
                    r_yn <= resize(shift_right(r_sum, C_SHIFT), 32);
                end if;
            end if;
        end if;
    end process;

    -- ===================== 状态更新 =====================
    process (i_sys_clk)
    begin
        if rising_edge(i_sys_clk) then
            if r_sampling(5) = '1' then
                r_yn1 <= r_yn;
                r_xn1 <= r_xn;
                r_xn  <= i_input;
            end if;
        end if;
    end process;

end architecture rtl;
