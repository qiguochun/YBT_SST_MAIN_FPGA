--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   llc_ramp.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   LLC 缓启斜坡合集。
--                      STAGE0/1 开环：duty / 频率按编译期步长每 ms 累加；
--                      进入 STAGE2 时采样 Vo，按 (目标-Vo)/T_VREF_MS
--                      计算每 ms 步进；T_VREF_MS = 从当前爬到目标的时长。
--                      目标 = min(i_edv, V_FULL)。
--                      频率全程计算/输出，不用周期。
--                      i_run=0：回初始（由 FSM 停机/disable 清 run）。
--------------------------------------------------------------------------------
--Version           :   Rev 1.3
--modifier          :   Qigc
--Modify Date       :   2026.09.04
--Modify Record     :   STAGE2 步进按 (目标-Vo)/T，目标=min(i_edv,V_FULL)
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity llc_ramp is
    generic (
        DUTY_MAX    : natural := 1024;          -- 1024 = 50%
        -- 频率编码：实际频率(Hz)/10，以适配 16bit（8000=80.0kHz）
        F_START     : natural := 8000;          -- 80.0 kHz
        F_END       : natural := 6000;          -- 60.0 kHz
        -- 开环阶段时长（1 ms 计数）
        T_STAGE0_MS : natural := 500;           -- STAGE0 正常斜坡 ms
        T_STAGE1_MS : natural := 500;           -- STAGE1 正常斜坡 ms
        -- STAGE2 电压缓启（Vo 编码 V*10）
        T_VREF_MS   : natural := 500;           -- STAGE2 Vref 斜坡 ms
        V_FULL      : natural := 8000           -- 总目标电压 800.0 V
    );
    port (
        -- Global Clock
        i_sys_clk : in  std_logic;
        i_sys_rst : in  std_logic;

        -- User Interface
        i_delay_1ms : in  std_logic;              -- delay_core 1 ms 单周期
        i_run       : in  std_logic;              -- FSM 使能锁存后才为 1
        i_state     : in  unsigned(2 downto 0);   -- 0/1 开环；>=2 电压缓启
        i_vo        : in  unsigned(15 downto 0);  -- 当前输出电压 Vo (V*10)
        i_edv       : in  unsigned(15 downto 0);  -- Vref 上限

        o_duty : out unsigned(15 downto 0);
        o_freq : out unsigned(15 downto 0);  -- 开关频率（Hz/10）
        o_vref : out unsigned(15 downto 0)
    );
end entity llc_ramp;

architecture rtl of llc_ramp is

    -- STAGE0 起始占空比：DUTY_MAX 的 10%
    constant DUTY_MIN_ST0 : natural := DUTY_MAX / 10;
    constant DUTY_SPAN    : natural := DUTY_MAX - DUTY_MIN_ST0;
    constant FREQ_SPAN    : integer := F_END - F_START;  -- 负值：频率下降

    -- 编译期步长（向上取整，避免时长变大后 step=0）
    constant C_DUTY_STEP : natural := (DUTY_SPAN + T_STAGE0_MS - 1) / T_STAGE0_MS;
    constant C_FREQ_STEP : integer := FREQ_SPAN / T_STAGE1_MS;

    signal r_duty      : unsigned(15 downto 0) := to_unsigned(DUTY_MIN_ST0, 16);
    signal r_freq      : integer := F_START;
    signal r_vref      : unsigned(15 downto 0) := (others => '0');
    signal r_vref_step : unsigned(15 downto 0) := (others => '0');
    signal r_state_d   : unsigned(2 downto 0) := (others => '0');
    signal r_delay_1ms_d : std_logic := '0';
    signal w_ms_tick     : std_logic;

    -- 进入 STAGE2 后：减/除 分拍，缩短组合路径
    type t_step_pipe is (P_IDLE, P_SUB, P_DIV);
    signal r_step_pipe : t_step_pipe := P_IDLE;
    signal r_span      : unsigned(15 downto 0) := (others => '0');  -- V_FULL - Vo

begin

    o_duty <= r_duty;
    o_freq <= to_unsigned(r_freq, 16);
    o_vref <= r_vref;

    w_ms_tick <= i_delay_1ms and (not r_delay_1ms_d);

    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_delay_1ms_d <= '0';
        elsif rising_edge(i_sys_clk) then
            r_delay_1ms_d <= i_delay_1ms;
        end if;
    end process;

    -- ===================== 开环 duty / 频率斜坡（编译期步长，每 ms 累加） =====================
    process (i_sys_clk, i_sys_rst)
        variable v_duty : integer;
        variable v_freq : integer;
    begin
        if i_sys_rst = '1' then
            r_duty <= to_unsigned(DUTY_MIN_ST0, 16);
            r_freq <= F_START;
        elsif rising_edge(i_sys_clk) then
            -- 未运行：回初始（disable/FAULT 会清 w_run）
            if i_run = '0' then
                r_duty <= to_unsigned(DUTY_MIN_ST0, 16);
                r_freq <= F_START;
            elsif w_ms_tick = '1' then
                if i_state = 0 then
                    v_duty := to_integer(r_duty) + C_DUTY_STEP;
                    if v_duty >= DUTY_MAX then
                        v_duty := DUTY_MAX;
                    end if;
                    r_duty <= to_unsigned(v_duty, 16);
                    r_freq <= F_START;

                elsif i_state = 1 then
                    r_duty <= to_unsigned(DUTY_MAX, 16);
                    v_freq := r_freq + C_FREQ_STEP;
                    if v_freq <= F_END then
                        v_freq := F_END;
                    elsif v_freq > F_START then
                        v_freq := F_START;
                    end if;
                    r_freq <= v_freq;

                elsif i_state >= 2 then
                    -- 闭环：仅保持最大 duty；频率由 PI 接管（见 llc_con_core）
                    r_duty <= to_unsigned(DUTY_MAX, 16);
                end if;
            end if;
        end if;
    end process;

    -- ===================== 电压缓启：分拍算步进 + 每 ms 爬升（两段分开） =====================
    process (i_sys_clk, i_sys_rst)
        variable v_enter : boolean;
        variable v_next  : unsigned(15 downto 0);
        variable v_cap   : unsigned(15 downto 0);
    begin
        if i_sys_rst = '1' then
            r_vref      <= (others => '0');
            r_vref_step <= (others => '0');
            r_state_d   <= (others => '0');
            r_step_pipe <= P_IDLE;
            r_span      <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            if i_run = '0' then
                r_vref      <= (others => '0');
                r_vref_step <= (others => '0');
                r_state_d   <= (others => '0');
                r_step_pipe <= P_IDLE;
                r_span      <= (others => '0');
            else
                -- 本拍=2 且 上一拍=1 → 刚进入 STAGE2
                v_enter := (to_integer(i_state) = 2) and (to_integer(r_state_d) = 1);

                ------------------------------------------------------------------
                -- A. 分拍计算 step
                ------------------------------------------------------------------
                case r_step_pipe is
                    when P_IDLE =>
                        if v_enter then
                            r_vref      <= i_vo;
                            r_vref_step <= (others => '0');
                            r_step_pipe <= P_SUB;
                        end if;

                    when P_SUB =>
                        -- 目标 = min(i_edv, V_FULL)；span = 目标 - 当前 Vo
                        -- T_VREF_MS = 从当前爬到目标的时长
                        if i_edv < V_FULL then
                            v_cap := i_edv;
                        else
                            v_cap := to_unsigned(V_FULL, 16);
                        end if;
                        if r_vref >= v_cap then
                            r_span <= (others => '0');
                        else
                            r_span <= v_cap - r_vref;
                        end if;
                        r_step_pipe <= P_DIV;

                    when P_DIV =>
                        r_vref_step <= resize(r_span / T_VREF_MS, 16);
                        r_step_pipe <= P_IDLE;

                    when others =>
                        r_step_pipe <= P_IDLE;
                end case;

                ------------------------------------------------------------------
                -- B. 每 ms 抬高 Vref
                ------------------------------------------------------------------
                if (r_step_pipe = P_IDLE) and (not v_enter)
                    and (w_ms_tick = '1') and (to_integer(i_state) >= 2) then
                    if i_edv < V_FULL then
                        v_cap := i_edv;
                    else
                        v_cap := to_unsigned(V_FULL, 16);
                    end if;
                    v_next := r_vref + r_vref_step;
                    if (r_vref >= v_cap) or (v_next < r_vref) or (v_next > v_cap) then
                        r_vref <= v_cap;
                    else
                        r_vref <= v_next;
                    end if;
                end if;

                r_state_d <= i_state;
            end if;
        end if;
    end process;

end architecture rtl;
