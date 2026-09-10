--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   llc_ramp.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   LLC 缓启斜坡。i_start 上升沿初始化并启动：
--                      STAGE0 爬 duty（频率 F_START）→
--                      STAGE1 降频到 F_END（duty 保持最大）→
--                      STAGE2 进入时一次算 Vref 步进 (目标-Vo)/T_VREF_MS。
--                      目标 = min(i_edv, V_FULL)。仅复位或再次启动脉冲回初始。
--                      o_done[2:0] 单拍：bit0 占空比爬满，bit1 频率到 F_END，bit2 Vref 到终点。
--------------------------------------------------------------------------------
--Version           :   Rev 1.0
--modifier          :   Qigc
--Modify Date       :   2026.09.03
--Modify Record     :   初始版本
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity llc_ramp is
    generic (
        DUTY_MAX    : natural := 1024;          -- 1024 = 50%
        -- 频率编码：实际频率(Hz)/10，以适配 16bit（8000=80.0kHz）
        F_START     : natural := 8000;          -- 80.0 kHz
        F_END       : natural := 4500;          -- 45.0 kHz
        -- 开环阶段时长（1 ms 计数）
        T_STAGE0_MS : natural := 500;           -- STAGE0 正常斜坡 ms
        T_STAGE1_MS : natural := 500;           -- STAGE1 正常斜坡 ms
        -- STAGE2 电压缓启（Vo 编码 V*10）
        T_VREF_MS   : natural := 500;           -- STAGE2 Vref 斜坡 ms
        V_FULL      : natural := 26212           -- 总目标电压 800.0 V 因为有对应码值
    );
    port (
        -- Global Clock
        i_sys_clk : in  std_logic;
        i_sys_rst : in  std_logic;

        -- User Interface
        i_delay_1ms : in  std_logic;              -- delay_core 1 ms 单周期
        i_start     : in  std_logic;              -- 启动脉冲：上升沿初始化并开始三段
        i_vo        : in  unsigned(15 downto 0);  -- 当前输出电压 Vo (V*10)
        i_edv       : in  unsigned(15 downto 0);  -- Vref 上限

        o_duty  : out unsigned(15 downto 0);
        o_freq  : out unsigned(15 downto 0);        -- 开关频率（Hz/10）
        o_vref  : out unsigned(15 downto 0);
        o_state : out unsigned(2 downto 0);         -- 0=IDLE 1=ST0 2=ST1 3=ST2
        o_done  : out std_logic_vector(2 downto 0)  -- [0]占空比 [1]频率 [2]幅值，各单拍
    );
end entity llc_ramp;

architecture rtl of llc_ramp is

    -- STAGE0 起始占空比：DUTY_MAX 的 10%
    constant DUTY_MIN_ST0 : natural := DUTY_MAX / 10;
    constant DUTY_SPAN    : natural := DUTY_MAX - DUTY_MIN_ST0;
    constant FREQ_SPAN : natural := F_START - F_END;  -- 降频幅度（正）
    constant V_ST2_MAX : natural := V_FULL * 9 / 10;  -- STAGE1 提前进 STAGE2 的电压阈值（0.9×V_FULL）
    
    -- 编译期步长（向上取整，避免时长变大后 step=0）
    constant C_DUTY_STEP : natural := (DUTY_SPAN + T_STAGE0_MS - 1) / T_STAGE0_MS;
    constant C_FREQ_STEP : natural := (FREQ_SPAN + T_STAGE1_MS - 1) / T_STAGE1_MS;

    type t_flow is (IDLE, ST0, ST1, ST2);
    signal r_flow : t_flow := IDLE;

    signal r_duty      : unsigned(15 downto 0) := to_unsigned(DUTY_MIN_ST0, 16);
    signal r_freq      : integer := F_START;
    signal r_vref      : unsigned(15 downto 0) := (others => '0');
    signal r_vref_step : unsigned(15 downto 0) := (others => '0');
    signal r_delay_1ms_d : std_logic := '0';
    signal r_start_d     : std_logic := '0';
    signal w_ms_tick     : std_logic;
    signal w_start_edge  : std_logic;
    signal r_enter_st2 : std_logic := '0';  -- ST1→ST2 单拍，锁存 Vo/目标并算步进
    signal r_duty_done : std_logic := '0';
    signal r_freq_done : std_logic := '0';
    signal r_vref_done : std_logic := '0';
    signal r_vref_hit  : std_logic := '0';  -- Vref 已到终点，避免每 ms 重复脉冲

begin

    o_duty <= r_duty;
    o_freq <= to_unsigned(r_freq, 16);
    o_vref <= r_vref;
    o_done <= r_vref_done & r_freq_done & r_duty_done;  -- [2]幅值 [1]频率 [0]占空比

    process (r_flow)
    begin
        case r_flow is
            when IDLE =>
                o_state <= to_unsigned(0, 3);
            when ST0 =>
                o_state <= to_unsigned(1, 3);
            when ST1 =>
                o_state <= to_unsigned(2, 3);
            when ST2 =>
                o_state <= to_unsigned(3, 3);
        end case;
    end process;

    w_ms_tick    <= i_delay_1ms and (not r_delay_1ms_d);      --1ms上升沿
    w_start_edge <= i_start and (not r_start_d);              --启动脉冲上升沿

    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_delay_1ms_d <= '0';
            r_start_d     <= '0';
        elsif rising_edge(i_sys_clk) then
            r_delay_1ms_d <= i_delay_1ms;                     --1ms打一拍   
            r_start_d     <= i_start;                         --启动脉冲打一拍
        end if;
    end process;

    -- ===================== 启动脉冲初始化 + 三段顺序斜坡 =====================
    process (i_sys_clk, i_sys_rst)
        variable v_duty : integer;
        variable v_freq : integer;
    begin
        if i_sys_rst = '1' then               
            r_duty      <= to_unsigned(DUTY_MIN_ST0, 16);
            r_freq      <= F_START;
            r_flow      <= IDLE;
            r_enter_st2 <= '0';
            r_duty_done <= '0';
            r_freq_done <= '0';
        elsif rising_edge(i_sys_clk) then
            r_enter_st2 <= '0';                           --ST1→ST2 单拍
            r_duty_done <= '0';
            r_freq_done <= '0';

            if w_start_edge = '1' then
                -- 启动脉冲：值回初始，从 STAGE0 开始
                r_duty <= to_unsigned(DUTY_MIN_ST0, 16);
                r_freq <= F_START;
                r_flow <= ST0;

            elsif w_ms_tick = '1' then                     --1ms脉冲上升沿
                case r_flow is
                    when ST0 =>
                        v_duty := to_integer(r_duty) + C_DUTY_STEP;
                        if v_duty >= DUTY_MAX then
                            r_duty      <= to_unsigned(DUTY_MAX, 16);
                            r_freq      <= F_START;
                            r_flow      <= ST1;
                            r_duty_done <= '1';
                        else
                            r_duty <= to_unsigned(v_duty, 16);
                            r_freq <= F_START;
                        end if;

                    when ST1 =>
                        r_duty <= to_unsigned(DUTY_MAX, 16);
                        v_freq := r_freq - C_FREQ_STEP;
                        -- 降到终点频率，或 Vo 已高于 V_ST2_MAX：停降频进 STAGE2
                        if (v_freq <= F_END) or (i_vo > to_unsigned(V_ST2_MAX, 16)) then
                            if v_freq <= F_END then
                                r_freq      <= F_END;
                                r_freq_done <= '1';
                            else
                                r_freq <= v_freq;
                            end if;
                            r_flow      <= ST2;
                            r_enter_st2 <= '1';
                        else
                            r_freq <= v_freq;
                        end if;

                    when ST2 =>
                        r_duty <= to_unsigned(DUTY_MAX, 16);
                        -- 频率保持 STAGE1 终点；Vref 由下面进程爬

                    when others =>
                        null;
                end case;
            end if;
        end if;
    end process;

    -- ===================== 电压缓启：进 ST2 时一次算步进，之后每 ms 爬升 =====================
    process (i_sys_clk, i_sys_rst)
        variable v_next : unsigned(15 downto 0);
        variable v_cap  : unsigned(15 downto 0);
        variable v_in   : unsigned(15 downto 0);
        variable v_span : unsigned(15 downto 0);
        variable v_step : unsigned(15 downto 0);
    begin
        if i_sys_rst = '1' then
            r_vref      <= (others => '0');
            r_vref_step <= (others => '0');
            r_vref_done <= '0';
            r_vref_hit  <= '0';
        elsif rising_edge(i_sys_clk) then
            r_vref_done <= '0';
            if w_start_edge = '1' then
                r_vref      <= (others => '0');
                r_vref_step <= (others => '0');
                r_vref_hit  <= '0';
            elsif r_enter_st2 = '1' then
                -- 起点=当前 Vo，终点=min(i_edv,V_FULL)，步进=(终点-起点)/T_VREF_MS
                v_in := i_vo;
                if i_edv < V_FULL then
                    v_cap := i_edv;
                else
                    v_cap := to_unsigned(V_FULL, 16);
                end if;
                r_vref <= v_in;
                if v_in >= v_cap then
                    r_vref_step <= (others => '0');
                    r_vref_done <= '1';
                    r_vref_hit  <= '1';
                else
                    v_span := v_cap - v_in;
                    v_step := resize(v_span / T_VREF_MS, 16);
                    if v_step = 0 then
                        r_vref_step <= to_unsigned(1, 16);
                    elsif v_step > 32 then
                        r_vref_step <= to_unsigned(32, 16);
                    else
                        r_vref_step <= v_step;
                    end if;
                end if;
            elsif (w_ms_tick = '1') and (r_flow = ST2) then
                if i_edv < V_FULL then
                    v_cap := i_edv;
                else
                    v_cap := to_unsigned(V_FULL, 16);
                end if;
                v_next := r_vref + r_vref_step;
                if (r_vref >= v_cap) or (v_next < r_vref) or (v_next > v_cap) then
                    r_vref <= v_cap;
                    if r_vref_hit = '0' then
                        r_vref_done <= '1';
                        r_vref_hit  <= '1';
                    end if;
                else
                    r_vref <= v_next;
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
