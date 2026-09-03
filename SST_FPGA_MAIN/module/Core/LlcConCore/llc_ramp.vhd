--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   llc_ramp.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   LLC 缓启斜坡合集。
--                      STAGE0/1 开环：duty / period 斜坡；
--                      STAGE2：Vref Q16 斜坡（约 1000V/s），上限 i_edv。
--------------------------------------------------------------------------------
--Version           :   Rev 0.1
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity llc_ramp is
    generic (
        DUTY_MAX      : natural := 5000;
        DUTY_MIN_ST0  : natural := 1000;
        T_START       : natural := 1600;
        T_END         : natural := 5120;
        T_STAGE0_MAX  : natural := 5120;
        T_STAGE1_MAX  : natural := 10240;
        PI_Q          : natural := 4096;
        SCALE0_Q12    : natural := 52429;  -- 65536/5120*4096
        SCALE1_Q12    : natural := 26214;  -- 65536/10240*4096
        VREF_STEP_Q16 : natural := 6400   -- 每 tick Q16 增量
    );
    port (
        -- Global Clock
        i_sys_clk : in  std_logic;
        i_sys_rst : in  std_logic;

        -- User Interface
        i_tick     : in  std_logic;
        i_state    : in  unsigned(2 downto 0);   -- 0/1 开环；>=2 保持最大 duty
        i_timer    : in  unsigned(15 downto 0);
        i_enable   : in  std_logic;              -- STAGE2：Vref 斜坡使能
        i_load     : in  std_logic;              -- 进入 STAGE2 时加载 Vref
        i_load_val : in  unsigned(15 downto 0);  -- 通常为当前 Vo
        i_edv      : in  unsigned(15 downto 0);  -- Vref 上限

        o_duty   : out unsigned(15 downto 0);
        o_period : out unsigned(15 downto 0);
        o_vref   : out unsigned(15 downto 0)
    );
end entity llc_ramp;

architecture rtl of llc_ramp is

    signal r_duty   : unsigned(15 downto 0) := (others => '0');
    signal r_period : unsigned(15 downto 0) := to_unsigned(T_START, 16);
    signal r_vref   : unsigned(15 downto 0) := (others => '0');
    signal r_frac   : unsigned(15 downto 0) := (others => '0');

begin

    o_duty   <= r_duty;
    o_period <= r_period;
    o_vref   <= r_vref;

    -- ===================== 开环 duty / period =====================
    process (i_sys_clk, i_sys_rst)
        variable v_t1     : integer;
        variable v_k      : integer;
        variable v_tmp    : integer;
        variable v_duty   : integer;
        variable v_period : integer;
    begin
        if i_sys_rst = '1' then
            r_duty   <= (others => '0');
            r_period <= to_unsigned(T_START, 16);
        elsif rising_edge(i_sys_clk) then
            if i_tick = '1' then
                if i_state = 0 then
                    -- k = timer * SCALE0 / PI_Q，限幅到 0..65535
                    v_tmp := to_integer(i_timer) * SCALE0_Q12;
                    v_k   := v_tmp / PI_Q;
                    if v_k > 65535 then
                        v_k := 65535;
                    elsif v_k < 0 then
                        v_k := 0;
                    end if;

                    v_tmp  := v_k * (DUTY_MAX - DUTY_MIN_ST0);
                    v_duty := DUTY_MIN_ST0 + (v_tmp / 65536);
                    if v_duty > DUTY_MAX then
                        v_duty := DUTY_MAX;
                    end if;

                    r_duty   <= to_unsigned(v_duty, 16);
                    r_period <= to_unsigned(T_START, 16);

                elsif i_state = 1 then
                    r_duty <= to_unsigned(DUTY_MAX, 16);
                    v_t1   := to_integer(i_timer) - T_STAGE0_MAX;
                    if v_t1 < 0 then
                        v_t1 := 0;
                    end if;

                    if v_t1 < T_STAGE1_MAX then
                        v_tmp := v_t1 * SCALE1_Q12;
                        v_k   := v_tmp / PI_Q;
                        if v_k > 65535 then
                            v_k := 65535;
                        elsif v_k < 0 then
                            v_k := 0;
                        end if;
                        v_tmp    := v_k * (T_END - T_START);
                        v_period := T_START + (v_tmp / 65536);
                    else
                        v_period := T_END;
                    end if;
                    r_period <= to_unsigned(v_period, 16);

                elsif i_state >= 2 then
                    -- 闭环/完成阶段保持最大占空比；周期由 PI 覆盖
                    r_duty <= to_unsigned(DUTY_MAX, 16);
                end if;
            end if;
        end if;
    end process;

    -- ===================== STAGE2 Vref 斜坡 =====================
    process (i_sys_clk, i_sys_rst)
        variable v_frac : integer;
        variable v_int  : integer;
    begin
        if i_sys_rst = '1' then
            r_vref <= (others => '0');
            r_frac <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            if i_load = '1' then
                r_vref <= i_load_val;
                r_frac <= (others => '0');
            elsif (i_tick = '1') and (i_enable = '1') then
                v_frac := to_integer(r_frac) + VREF_STEP_Q16;
                v_int  := to_integer(r_vref);
                if v_frac >= 65536 then
                    v_int  := v_int + 1;
                    v_frac := v_frac - 65536;
                end if;
                if v_int > to_integer(i_edv) then
                    v_int  := to_integer(i_edv);
                    v_frac := 0;
                end if;
                r_vref <= to_unsigned(v_int, 16);
                r_frac <= to_unsigned(v_frac, 16);
            end if;
        end if;
    end process;

end architecture rtl;
