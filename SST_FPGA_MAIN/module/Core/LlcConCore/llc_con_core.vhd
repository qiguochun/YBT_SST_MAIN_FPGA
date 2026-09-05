--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   llc_con_core.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   LLC 缓启控制核顶层（规范接口）。
--                      聚合：delay_core 时基 / 滑动平均 / 阶段 FSM / 斜坡。
--                      频率 PIR 暂不例化，后续再补；STAGE2/3 频率暂跟开环。
--                      i_enable 脉冲启动；i_disable 停机回初始。
--------------------------------------------------------------------------------
--Version           :   Rev 1.5
--modifier          :   Qigc
--Modify Date       :   2026.09.05
--Modify Record     :   去掉外部 i_delay_*；核内自例化 delay_core
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity llc_con_core is
    generic (
        CLK_FREQ : positive := 30_000_000  -- 系统时钟频率 Hz（PIR 后续用）
    );
    port (
        -- Global Clock
        i_sys_clk : in  std_logic;
        i_sys_rst : in  std_logic;  -- 异步复位，高有效
        i_tick    : in  std_logic;  -- AD/控制节拍（暂仅 vo_ma_filter）
        i_enable  : in  std_logic := '0';  -- 缓启启动脉冲
        i_disable : in  std_logic := '0';  -- 同步停机：清运行并回初始，高有效

        -- Analog / Param
        i_vo    : in  std_logic_vector(15 downto 0);
        i_edv   : in  std_logic_vector(15 downto 0);
        i_kp    : in  std_logic_vector(15 downto 0);  -- 预留：PIR，暂未使用
        i_ki    : in  std_logic_vector(15 downto 0);  -- 预留：PIR，暂未使用
        i_d2set : in  std_logic_vector(15 downto 0);

        -- Command Out
        o_duty_cmd : out std_logic_vector(15 downto 0);
        o_period   : out std_logic_vector(15 downto 0);  -- f_sw（Hz/10）
        o_state    : out std_logic_vector(2 downto 0);
        o_done     : out std_logic;
        o_dco      : out std_logic_vector(15 downto 0);
        o_run_en   : out std_logic                       -- 运行使能：正常跑=1，停/故障=0
    );
end entity llc_con_core;

architecture rtl of llc_con_core is

    ---------------------------------------------------------------------------
    -- 缓启参数（architecture 常量）
    -- 正常时长 → llc_ramp；超时时长 → llc_stage_fsm
    ---------------------------------------------------------------------------
    constant T_RAMP0_MS    : natural := 2000;    -- STAGE0 开环 duty 斜坡
    constant T_RAMP1_MS    : natural := 2000;    -- STAGE1 开环频率斜坡
    constant T_RAMP2_MS    : natural := 2000;    -- STAGE2：当前电压→目标 的爬升时长
    constant T_TO0_MS      : natural := 5000;   -- STAGE0 超时
    constant T_TO1_MS      : natural := 5000;   -- STAGE1 超时
    constant T_TO2_MS      : natural := 5000;   -- STAGE2 超时
    constant V_STAGE1_DONE : natural := 7200;   -- STAGE1→2：电压提到 720.0 V 可提前停降频
    constant V_STAGE2_DONE : natural := 8000;   -- STAGE2 完成 800.0 V
    constant V_FULL        : natural := 8000;   -- 额定上限 800.0 V（Vref 封顶）
    constant DUTY_DONE     : natural := 1024;   -- 50%
    constant DUTY_MAX      : natural := 1024;
    constant F_START       : natural := 8000;   -- 80.0 kHz
    constant F_END         : natural := 5000;   -- 50.0 kHz
    constant F_MIN         : natural := 2500;   -- 25.0 kHz（PIR 后续用）

    signal w_dco         : std_logic_vector(15 downto 0);
    signal w_ma_done     : std_logic;
    signal w_state       : unsigned(2 downto 0);
    signal w_done        : std_logic;
    signal w_phase_done  : std_logic_vector(2 downto 0);
    signal w_timeout_err : std_logic_vector(2 downto 0);
    signal w_run         : std_logic;
    signal w_fault_hold  : std_logic;
    signal w_ol_duty     : unsigned(15 downto 0);
    signal w_ol_freq     : unsigned(15 downto 0);
    signal w_vref        : unsigned(15 downto 0);  -- ramp 产出，PIR 后续接
    signal w_delay_1ms   : std_logic;
    signal w_delay_1s    : std_logic;

    signal r_duty   : unsigned(15 downto 0) := (others => '0');
    signal r_freq   : unsigned(15 downto 0) := to_unsigned(F_START, 16);
    signal r_run_en : std_logic := '0';

    -- 预留口保持连通，避免被综合优化掉
    signal w_d2set_keep : std_logic_vector(15 downto 0);
    signal w_kp_keep    : std_logic_vector(15 downto 0);
    signal w_ki_keep    : std_logic_vector(15 downto 0);
    signal w_vref_cap   : unsigned(15 downto 0);

begin

    -- STAGE2：Vref 爬向额定；目标取 min(i_edv, V_FULL)，由 llc_ramp 内部再截一次
    w_vref_cap   <= to_unsigned(V_FULL, 16) when w_state = 2 else unsigned(i_edv);
    w_d2set_keep <= i_d2set;
    w_kp_keep    <= i_kp;
    w_ki_keep    <= i_ki;

    w_fault_hold <= '1' when (w_timeout_err /= "000") or (w_state = 4)  else '0';

    o_duty_cmd <= std_logic_vector(r_duty);
    o_period   <= std_logic_vector(r_freq);
    o_state    <= std_logic_vector(w_state);
    o_done     <= w_done and w_phase_done(2);
    o_dco      <= w_dco;
    o_run_en   <= r_run_en;

    -- 核内时基：与 i_sys_clk 同域，保证 1ms 单周期脉冲
    U_DELAY : entity work.delay_core
        generic map (
            CLK_FREQ => CLK_FREQ
        )
        port map (
            i_sys_clk   => i_sys_clk,
            i_sys_rst   => i_sys_rst,
            o_delay_1us => open,
            o_delay_1ms => w_delay_1ms,
            o_delay_1s  => w_delay_1s
        );

    U_VO_MA : entity work.vo_ma_filter
        port map (
            i_sys_clk => i_sys_clk,
            i_sys_rst => i_sys_rst,
            i_tick    => i_tick,
            i_vo      => i_vo,
            o_dco     => w_dco,
            o_done    => w_ma_done
        );

    U_STAGE_FSM : entity work.llc_stage_fsm
        generic map (
            T_STAGE0_MS   => T_TO0_MS,
            T_STAGE1_MS   => T_TO1_MS,
            T_STAGE2_MS   => T_TO2_MS,
            DUTY_DONE     => DUTY_DONE,
            F_STAGE1_DONE => F_END,
            V_STAGE1_DONE => V_STAGE1_DONE,
            V_STAGE2_DONE => V_STAGE2_DONE
        )
        port map (
            i_sys_clk     => i_sys_clk,
            i_sys_rst     => i_sys_rst,
            i_delay_1ms   => w_delay_1ms,
            i_enable      => i_enable,
            i_restart     => i_disable,
            i_duty        => w_ol_duty,
            i_freq        => w_ol_freq,
            i_vo          => unsigned(w_dco),
            o_run         => w_run,
            o_state       => w_state,
            o_done        => w_done,
            o_phase_done  => w_phase_done,
            o_timeout_err => w_timeout_err
        );

    U_RAMP : entity work.llc_ramp
        generic map (
            T_STAGE0_MS => T_RAMP0_MS,
            T_STAGE1_MS => T_RAMP1_MS,
            T_VREF_MS   => T_RAMP2_MS,
            V_FULL      => V_FULL,
            F_START     => F_START,
            F_END       => F_END
        )
        port map (
            i_sys_clk   => i_sys_clk,
            i_sys_rst   => i_sys_rst,
            i_delay_1ms => w_delay_1ms,
            i_run       => w_run,
            i_state     => w_state,
            i_vo        => unsigned(w_dco),
            i_edv       => w_vref_cap,
            o_duty      => w_ol_duty,
            o_freq      => w_ol_freq,
            o_vref      => w_vref
        );

    -- U_PERIOD_PI：暂不例化，后续补充 PIR

    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_duty   <= (others => '0');
            r_freq   <= to_unsigned(F_START, 16);
            r_run_en <= '0';
        elsif rising_edge(i_sys_clk) then
            if (i_disable = '1') or (w_run = '0') or (w_fault_hold = '1') then
                -- 未运行 / 停机 / 超时FAULT：duty=0，频率 80 kHz，运行使能=0
                r_duty   <= (others => '0');
                r_freq   <= to_unsigned(F_START, 16);
                r_run_en <= '0';
            else
                -- w_run=1：按阶段输出开环指令，运行使能=1
                r_run_en <= '1';
                r_duty   <= w_ol_duty;
                case to_integer(w_state) is
                    when 0 | 1 | 2 =>
                        -- STAGE2 暂无 PIR：频率继续跟开环（停在 F_END）
                        r_freq <= w_ol_freq;
                    when 3 =>
                        r_duty <= to_unsigned(DUTY_MAX, 16);
                        r_freq <= w_ol_freq;
                    when others =>
                        r_freq <= to_unsigned(F_START, 16);
                end case;
            end if;
        end if;
    end process;

end architecture rtl;
