--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   lpf_core.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   一阶低通（差分方程 + 有符号除法归一化）。
--                      依赖 MathCore/signed_division。
--------------------------------------------------------------------------------
--Version           :   Rev 0.1
--modifier          :
--Modify Date       :
--Modify Record     :
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity lpf_core is
    generic (
        WC        : integer := 6280;
        CALC_GAIN : integer := 1;
        FREQ      : integer := 40000;       -- 采样/归一化频率
        CLK_FREQ  : integer := 20000000     -- 系统时钟频率 (Hz)
    );
    port (
        -- Global Clock
        i_sys_clk : in  std_logic;

        -- User Interface
        i_input   : in  signed(31 downto 0);
        o_output  : out signed(31 downto 0)
    );
end entity lpf_core;

architecture rtl of lpf_core is

    constant C_UK0     : signed(47 downto 0) := (others => '0');
    constant C_UK1     : signed(47 downto 0) := to_signed(WC, 48);
    constant C_YK1     : signed(47 downto 0) := to_signed(WC - FREQ, 48);
    constant C_FREQ    : signed(31 downto 0) := to_signed(FREQ, 32);
    constant C_GAIN    : signed(31 downto 0) := to_signed(CALC_GAIN, 32);
    constant C_CNT_MAX : natural := CLK_FREQ / FREQ;

    signal r_input1  : signed(47 downto 0) := (others => '0');
    signal r_input0  : signed(47 downto 0) := (others => '0');
    signal r_output1 : signed(47 downto 0) := (others => '0');
    signal r_output  : signed(47 downto 0) := (others => '0');
    signal r_cnt     : unsigned(15 downto 0) := (others => '0');

    signal r_sig1         : signed(47 downto 0) := (others => '0');
    signal r_sig2         : signed(47 downto 0) := (others => '0');
    signal r_sig3         : signed(47 downto 0) := (others => '0');
    signal r_out_with_calc : signed(47 downto 0) := (others => '0');

    signal w_output_with_gain      : signed(47 downto 0);
    signal w_output_with_gain_done : std_logic;
    signal w_output_div_q          : signed(47 downto 0);
    signal w_output_div_done       : std_logic;
    signal r_output_div_done       : std_logic_vector(2 downto 0) := (others => '0');

    signal w_start_div0 : std_logic;

begin

    -- 原 Verilog 将 48bit 商接到 32bit 输出：取低 32bit
    o_output <= w_output_div_q(31 downto 0);

    w_start_div0 <= '1' when r_cnt = 0 else '0';

    -- ===================== 采样分频计数 =====================
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

    process (i_sys_clk)
    begin
        if rising_edge(i_sys_clk) then
            r_output_div_done <= r_output_div_done(1 downto 0) & w_output_div_done;
        end if;
    end process;

    -- ===================== 乘加拆拍 =====================
    process (i_sys_clk)
        variable v_p1 : signed(95 downto 0);
        variable v_p2 : signed(95 downto 0);
        variable v_p3 : signed(95 downto 0);
    begin
        if rising_edge(i_sys_clk) then
            if r_output_div_done(0) = '1' then
                -- uk0=0 时 sig1 恒 0；截取低 48bit 与 Verilog 一致
                v_p1 := r_input0 * C_UK0;
                r_sig1 <= resize(resize(v_p1, 48) * to_signed(CALC_GAIN, 48), 48);
                v_p2 := r_input1 * C_UK1;
                r_sig2 <= resize(v_p2, 48);
                v_p3 := r_output1 * C_YK1;
                r_sig3 <= resize(v_p3, 48);
            end if;
        end if;
    end process;

    process (i_sys_clk)
    begin
        if rising_edge(i_sys_clk) then
            if r_output_div_done(2) = '1' then
                r_out_with_calc <= r_sig1 + r_sig2 - r_sig3;
            end if;
        end if;
    end process;

    -- ===================== /FREQ =====================
    u_div_freq : entity work.signed_division
        generic map (
            WIDTH_DVD => 48,
            WIDTH_DVS => 32
        )
        port map (
            i_sys_clk   => i_sys_clk,
            i_sys_rst   => '0',
            i_start     => w_start_div0,
            i_dividend  => r_out_with_calc,
            i_divisor   => C_FREQ,
            o_quotient  => w_output_with_gain,
            o_remainder => open,
            o_done      => w_output_with_gain_done,
            o_busy      => open
        );

    -- ===================== /CALC_GAIN =====================
    u_div_gain : entity work.signed_division
        generic map (
            WIDTH_DVD => 48,
            WIDTH_DVS => 32
        )
        port map (
            i_sys_clk   => i_sys_clk,
            i_sys_rst   => '0',
            i_start     => w_output_with_gain_done,
            i_dividend  => w_output_with_gain,
            i_divisor   => C_GAIN,
            o_quotient  => w_output_div_q,
            o_remainder => open,
            o_done      => w_output_div_done,
            o_busy      => open
        );

    -- ===================== 状态更新（保持原行为） =====================
    process (i_sys_clk)
    begin
        if rising_edge(i_sys_clk) then
            if w_output_with_gain_done = '1' then
                r_output <= w_output_with_gain;
            else
                r_output1 <= r_output;
                r_input0  <= resize(i_input, 48);
                r_input1  <= resize(r_input0 * to_signed(CALC_GAIN, 48), 48);  -- 48x48 截低 48
            end if;
        end if;
    end process;

end architecture rtl;
