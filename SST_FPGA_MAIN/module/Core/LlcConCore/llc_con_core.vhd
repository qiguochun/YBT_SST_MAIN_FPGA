--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   llc_con_core.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   LLC 缓启控制核顶层（规范接口）。
--                      聚合：滑动平均 / 阶段 FSM / 斜坡(llc_ramp) / 周期 PI。
--                      已替代工程内原 dc_DABCON 例化（BDF inst19）。
--------------------------------------------------------------------------------
--Version           :   Rev 0.4
--modifier          :   Qigc
--Modify Date       :   2026.09.03
--Modify Record     :   命名 DAB→LLC（目录/实体/文件）
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity llc_con_core is
    port (
        -- Global Clock
        i_sys_clk : in  std_logic;
        i_sys_rst : in  std_logic;  -- 异步复位，高有效
        i_tick    : in  std_logic;  -- 控制节拍 102.4 kHz 单周期

        -- Analog / Param
        i_vo   : in  std_logic_vector(15 downto 0);  -- Vo (V*10)
        i_edv  : in  std_logic_vector(15 downto 0);  -- Vref 上限
        i_kp   : in  std_logic_vector(15 downto 0);  -- PI KP Q12
        i_ki   : in  std_logic_vector(15 downto 0);  -- PI KI Q12
        i_d2set : in std_logic_vector(15 downto 0);  -- 预留，当前未使用

        -- Command Out
        o_duty_cmd  : out std_logic_vector(15 downto 0);  -- 10000=1.0
        o_period    : out std_logic_vector(15 downto 0);  -- 128MHz 周期计数
        o_state     : out std_logic_vector(2 downto 0);
        o_done      : out std_logic;
        o_dco       : out std_logic_vector(15 downto 0)   -- Vo 滑动平均
    );
end entity llc_con_core;

architecture rtl of llc_con_core is

    constant T_START      : natural := 1600;
    constant T_END        : natural := 5120;
    constant DUTY_MAX     : natural := 5000;

    signal w_dco       : std_logic_vector(15 downto 0);
    signal w_ma_done   : std_logic;
    signal w_state     : unsigned(2 downto 0);
    signal w_timer     : unsigned(15 downto 0);
    signal w_done      : std_logic;
    signal w_enter_s2  : std_logic;

    signal w_ol_duty   : unsigned(15 downto 0);
    signal w_ol_period : unsigned(15 downto 0);
    signal w_vref      : unsigned(15 downto 0);
    signal w_pi_period : unsigned(15 downto 0);

    signal r_duty   : unsigned(15 downto 0) := (others => '0');
    signal r_period : unsigned(15 downto 0) := to_unsigned(T_START, 16);

    signal w_enable_s2 : std_logic;
    signal w_d2set_keep : std_logic_vector(15 downto 0);

begin

    w_enable_s2  <= '1' when w_state = 2 else '0';
    w_d2set_keep <= i_d2set;  -- 预留端口，保持连通避免悬空输入优化掉端口

    o_duty_cmd <= std_logic_vector(r_duty);
    o_period   <= std_logic_vector(r_period);
    o_state    <= std_logic_vector(w_state);
    o_done     <= w_done;
    o_dco      <= w_dco;

    -- ===================== Vo 滑动平均 =====================
    U_VO_MA : entity work.vo_ma_filter
        port map (
            i_sys_clk => i_sys_clk,
            i_sys_rst => i_sys_rst,
            i_tick    => i_tick,
            i_vo      => i_vo,
            o_dco     => w_dco,
            o_done    => w_ma_done
        );

    -- ===================== 阶段 FSM =====================
    U_STAGE_FSM : entity work.llc_stage_fsm
        port map (
            i_sys_clk  => i_sys_clk,
            i_sys_rst  => i_sys_rst,
            i_tick     => i_tick,
            i_vo       => unsigned(i_vo),
            o_state    => w_state,
            o_timer    => w_timer,
            o_done     => w_done,
            o_enter_s2 => w_enter_s2
        );

    -- ===================== 开环 + Vref 斜坡 =====================
    U_RAMP : entity work.llc_ramp
        port map (
            i_sys_clk  => i_sys_clk,
            i_sys_rst  => i_sys_rst,
            i_tick     => i_tick,
            i_state    => w_state,
            i_timer    => w_timer,
            i_enable   => w_enable_s2,
            i_load     => w_enter_s2,
            i_load_val => unsigned(i_vo),
            i_edv      => unsigned(i_edv),
            o_duty     => w_ol_duty,
            o_period   => w_ol_period,
            o_vref     => w_vref
        );

    -- ===================== 周期 PI =====================
    U_PERIOD_PI : entity work.llc_period_pi
        port map (
            i_sys_clk => i_sys_clk,
            i_sys_rst => i_sys_rst,
            i_tick    => i_tick,
            i_enable  => w_enable_s2,
            i_vref    => signed(std_logic_vector(w_vref)),
            i_dco     => signed(w_dco),
            i_kp      => signed(i_kp),
            i_ki      => signed(i_ki),
            o_period  => w_pi_period
        );

    -- ===================== 输出选择 =====================
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_duty   <= (others => '0');
            r_period <= to_unsigned(T_START, 16);
        elsif rising_edge(i_sys_clk) then
            r_duty <= w_ol_duty;
            case to_integer(w_state) is
                when 0 | 1 =>
                    r_period <= w_ol_period;
                when 2 =>
                    r_period <= w_pi_period;
                when 3 =>
                    r_duty   <= to_unsigned(DUTY_MAX, 16);
                    r_period <= w_pi_period;
                when others =>
                    r_period <= to_unsigned(T_START, 16);
            end case;
        end if;
    end process;

end architecture rtl;
