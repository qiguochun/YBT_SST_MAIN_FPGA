--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   llc_con_core.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   LLC 缓启控制核顶层（规范接口）。
--                      聚合：delay_core 时基 / 滑动平均 / 斜坡 / 故障。
--                      启动锁存在本层：i_enable 置位，i_disable/保护清。
--                      频率 PIR 暂不例化，后续再补。
--------------------------------------------------------------------------------
--Version           :   Rev 1.0
--modifier          :   Qigc
--Modify Date       :   2026.09.03
--Modify Record     :   初始版本
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
        i_tick    : in  std_logic;  -- AD 可 102.4 kHz；PIR 须另接 20 kHz
        i_enable  : in  std_logic := '0';  -- 缓启启动：锁存运行
        i_disable : in  std_logic := '0';  -- 同步停机：清运行锁存，高有效

        -- Analog / Param
        i_vo    : in  std_logic_vector(15 downto 0);
        i_id    : in  std_logic_vector(15 downto 0) := (others => '0');  -- Id 瞬时
        i_edv   : in  std_logic_vector(15 downto 0);
        i_kp    : in  std_logic_vector(15 downto 0);  -- 预留：PIR，暂未使用
        i_ki    : in  std_logic_vector(15 downto 0);  -- 预留：PIR，暂未使用
        i_d2set : in  std_logic_vector(15 downto 0);

        -- Command Out
        o_duty_cmd : out std_logic_vector(15 downto 0);
        o_period   : out std_logic_vector(15 downto 0);  -- f_sw（Hz/10）
        o_state    : out std_logic_vector(2 downto 0);
        o_done     : out std_logic;
        o_dco      : out std_logic_vector(15 downto 0);  -- Vo/Ud 滑动平均
        o_dci      : out std_logic_vector(15 downto 0);  -- Id 滑动平均
        o_run_en   : out std_logic;                      -- 运行使能：正常跑=1，停/故障=0
        o_fault    : out std_logic_vector(15 downto 0)   -- [0]过压 [1]过流 [2]超时；全0=正常
    );
end entity llc_con_core;

architecture rtl of llc_con_core is

    ---------------------------------------------------------------------------
    -- 缓启参数（architecture 常量）
    ---------------------------------------------------------------------------
    constant T_RAMP0_MS : natural := 2000;    -- STAGE0 开环 duty 斜坡
    constant T_RAMP1_MS : natural := 2000;    -- STAGE1 开环频率斜坡
    constant T_RAMP2_MS : natural := 2000;    -- STAGE2：当前电压→目标 的爬升时长
    constant V_FULL     : natural := 8000;    -- 额定上限 800.0 V（Vref 封顶）
    constant F_START    : natural := 8000;    -- 80.0 kHz

    signal w_dco        : std_logic_vector(15 downto 0);
    signal w_dci        : std_logic_vector(15 downto 0);
    signal w_ma_done    : std_logic;
    signal w_id_ma_done : std_logic;
    signal w_fault      : std_logic_vector(15 downto 0);
    signal w_prot_fault : std_logic;
    signal w_state_mon  : unsigned(2 downto 0);
    signal w_ol_duty    : unsigned(15 downto 0);
    signal w_ol_freq    : unsigned(15 downto 0);
    signal w_vref       : unsigned(15 downto 0);
    signal w_ramp_state : unsigned(2 downto 0);
    signal w_ramp_done  : std_logic_vector(2 downto 0);
    signal w_delay_1us  : std_logic;
    signal w_delay_1ms  : std_logic;
    signal w_delay_1s   : std_logic;

    signal r_run      : std_logic := '0';  -- 启动锁存
    signal r_done     : std_logic := '0';  -- 幅值到位锁存
    signal r_enable_d : std_logic := '0';
    signal w_en_edge  : std_logic;
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
    w_vref_cap   <= to_unsigned(V_FULL, 16) when w_ramp_state = 3 else unsigned(i_edv);
    w_state_mon  <= w_ramp_state when r_run = '1' else (others => '0');
    w_d2set_keep <= i_d2set;
    w_kp_keep    <= i_kp;
    w_ki_keep    <= i_ki;

    w_prot_fault <= '1' when w_fault /= x"0000" else '0';
    o_duty_cmd   <= std_logic_vector(r_duty);
    o_period     <= std_logic_vector(r_freq);
    o_state      <= std_logic_vector(w_state_mon);
    o_done       <= r_done;
    o_dco        <= w_dco;
    o_dci        <= w_dci;
    o_run_en     <= r_run_en;
    o_fault      <= w_fault;

    -- 启动锁存：enable 上升沿置位（与 ramp i_start 对齐）；停机/保护清
    w_en_edge <= i_enable and (not r_enable_d);

    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_enable_d <= '0';
            r_run      <= '0';
            r_done     <= '0';
        elsif rising_edge(i_sys_clk) then
            r_enable_d <= i_enable;
            if (i_disable = '1') or (w_prot_fault = '1') then
                r_run  <= '0';
                r_done <= '0';
            elsif w_en_edge = '1' then
                r_run  <= '1';
                r_done <= '0';
            elsif (r_run = '1') and (w_ramp_done(2) = '1') then
                r_done <= '1';
            end if;
        end if;
    end process;

    -- 核内时基：与 i_sys_clk 同域，保证 1ms 单周期脉冲
    U_DELAY : entity work.delay_core
        generic map (
            CLK_FREQ => CLK_FREQ
        )
        port map (
            i_sys_clk   => i_sys_clk,
            i_sys_rst   => i_sys_rst,
            o_delay_1us => w_delay_1us,
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

    U_ID_MA : entity work.id_ma_filter
        port map (
            i_sys_clk => i_sys_clk,
            i_sys_rst => i_sys_rst,
            i_tick    => i_tick,
            i_id      => i_id,
            o_dci     => w_dci,
            o_done    => w_id_ma_done
        );

    U_FAULT : entity work.llc_fault
        port map (
            i_sys_clk   => i_sys_clk,
            i_sys_rst   => i_sys_rst,
            i_delay_1us => w_delay_1us,
            i_delay_1ms => w_delay_1ms,
            i_vin       => i_vo,
            i_iin_ma    => w_dci,
            i_state     => w_state_mon,
            i_done      => w_ramp_done,
            o_fault     => w_fault
        );

    U_RAMP : entity work.llc_ramp
        generic map (
            T_STAGE0_MS => T_RAMP0_MS,
            T_STAGE1_MS => T_RAMP1_MS,
            T_VREF_MS   => T_RAMP2_MS,
            V_FULL      => V_FULL
            -- F_START / F_END 用 llc_ramp 模块默认值
        )
        port map (
            i_sys_clk   => i_sys_clk,
            i_sys_rst   => i_sys_rst,
            i_delay_1ms => w_delay_1ms,
            i_start     => i_enable,
            i_vo        => unsigned(w_dco),
            i_edv       => w_vref_cap,
            o_duty      => w_ol_duty,
            o_freq      => w_ol_freq,
            o_vref      => w_vref,
            o_state     => w_ramp_state,
            o_done      => w_ramp_done
        );

    -- U_PERIOD_PI：暂不例化，后续补充 PIR

    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_duty   <= (others => '0');
            r_freq   <= to_unsigned(F_START, 16);
            r_run_en <= '0';
        elsif rising_edge(i_sys_clk) then
            if (i_disable = '1') or (r_run = '0') or (w_prot_fault = '1') then
                r_duty   <= (others => '0');
                r_freq   <= to_unsigned(F_START, 16);
                r_run_en <= '0';
            else
                r_run_en <= '1';
                r_duty   <= w_ol_duty;
                r_freq   <= w_ol_freq;
            end if;
        end if;
    end process;

end architecture rtl;
