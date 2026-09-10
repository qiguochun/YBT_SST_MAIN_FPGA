--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   llc_period_pi.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   电压环 PI（无谐振、无前馈）。
--                      电压码：800V=26212，约 32.765 码/V（与 Burst/ramp 一致）。
--                      频率整数：1 LSB = 10 Hz。LLC 降频增增益。
--                      err = Vo - min(i_vref,V_REF)。|err|≤ERR_DEAD（默认 0.5 V）时 PI 误差作 0；
--                      否则钳到 ERR_SAT≈40 V。
--                      输出 f = F_MIN + Kp×err + ∫err，再钳 F_MIN~F_MAX。
--                      I 为误差积分（Q14，频率整数×2^PI_SHIFT），每拍 I := I + Ki口×err。
--                      卡在 F_MIN 且 err<0 时仍可往负积，I 下限为 -I_FLOOR（默认 -5.0 kHz）。
--                      口上（PI_SHIFT=14，Ts=40 µs / 25 kHz）：
--                        Kp口 = Kp[Hz/V] × 16384 / 10 / 32.765
--                        Ki口 = Ki[Hz/(V·s)] × Ts × 16384 / 10 / 32.765
--                      例：Kp=10 Hz/V → i_kp=500；Ki=5500 Hz/(V·s) → i_ki=11。
--                      i_enable 须按控制周期给脉冲（含积分）。i_recalc：按
--                      i_freq_ref 重装积分。i_reset 清状态。每轮约 7 个 sys_clk。
--------------------------------------------------------------------------------
--Version           :   Rev 1.0
--modifier          :   Qigc
--Modify Date       :   2026.09.03
--Modify Record     :   初始版本
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity llc_period_pi is
    generic (
        CLK_FREQ : positive := 30_000_000;        
        F_MAX_HZ : natural  := 6000;           --最大频率60K
        F_MIN_HZ : natural  := 2500;           --最小频率25K

        ERR_SAT  : natural  := 1310;           -- 误差限幅 ≈40V（40×32.765）
        ERR_DEAD : natural  := 16;             -- 死区 ≈0.5V（0.5×32.765）
        PI_SHIFT : natural  := 14;             -- I/增益定点：I 存频率整数×2^PI_SHIFT（Q14）
        I_FLOOR  : natural  := 500;            -- 积分负下限 5.0 kHz（口上 LSB）

        V_REF    : natural  := 26212           -- 800.0 V 码值
    );
    port (
        i_sys_clk : in  std_logic;
        i_sys_rst : in  std_logic;

        i_enable   : in  std_logic;               -- 脉冲：算完一轮（含积分）
        i_recalc   : in  std_logic;               -- 脉冲：按参考频率重算积分项后保持
        i_reset    : in  std_logic;               -- 脉冲：回初始

        i_vo       : in  unsigned(15 downto 0);   -- 反馈电压码（800V=26212）
        i_vref     : in  unsigned(15 downto 0);   -- 参考电压码
        i_freq_ref : in  unsigned(15 downto 0);   -- 参考频率（Hz/10），recalc 用 

        i_kp      : in  signed(31 downto 0);
        i_ki      : in  signed(31 downto 0);

        o_freq    : out unsigned(15 downto 0)
    );
end entity llc_period_pi;

architecture rtl of llc_period_pi is

    constant C_V_REF : integer := V_REF;
    -- 积分正限：Q14 下 +(F_MAX-F_MIN)，使 F_MIN+I 最高到 60 kHz；负限：-I_FLOOR
    constant C_I_LIM : integer := (F_MAX_HZ - F_MIN_HZ) * (2 ** PI_SHIFT);
    constant C_I_MIN : integer := -I_FLOOR * (2 ** PI_SHIFT);

    type t_pipe is (
        IDLE,                                                  --空闲态
        ERR_CALC,                                              --计算误差
        KP_TERM,                                               --计算KP项
        KI_TERM,                                               --计算KI项
        F_UNSAT,                                               --未限幅频率
        I_ALLOW,                                               --是否允许积分
        I_UPDATE,                                              --更新积分
        P_CMD                                                  --计算命令
    );
    signal r_pipe : t_pipe := IDLE;

    signal r_en_d     : std_logic := '0';                                  --打一拍使能态
    signal r_recalc_d : std_logic := '0';                                  --打一拍重计算态
    signal w_en_rise     : std_logic;                                      --使能上升沿
    signal w_recalc_rise : std_logic;                                      --重计算上升沿


    signal r_hold_i   : std_logic := '0';                                 -- 1=本轮按参考频率重装积分
    signal r_allow_i  : std_logic := '0';                                 -- 1=本轮允许更新积分

    signal r_vo       : unsigned(15 downto 0) := (others => '0');          -- 脉冲到来时锁存的Vo
    signal r_vref     : unsigned(15 downto 0) := to_unsigned(V_REF, 16);   --脉冲到来时锁存的Vref
    signal r_freq_ref : unsigned(15 downto 0) := to_unsigned(F_MIN_HZ, 16); --脉冲到来时锁存的参考频率

    --实际PI使用信号
    signal r_err_sat  : signed(15 downto 0) := (others => '0');            --误差限幅
    signal r_f_unsat  : signed(31 downto 0) := (others => '0');            --未限幅频率（整数，抗饱和用）
    signal r_kp_q     : signed(31 downto 0) := (others => '0');            --比例项 Q14：Kp口×err
    signal r_ki_q     : signed(31 downto 0) := (others => '0');            --积分增量 Q14：Ki口×err
    signal r_integral : signed(31 downto 0) := (others => '0');            --误差积分 Q14

    signal r_freq     : unsigned(15 downto 0) := to_unsigned(F_MAX_HZ, 16); --计算后的频率
    signal r_kp       : signed(31 downto 0) := (others => '0');             --当前计算锁存KP
    signal r_ki       : signed(31 downto 0) := (others => '0');             --当前计算锁存KI

    --限幅函数
    function f_clamp_i(v, lo, hi : integer) return integer is               --限幅函数
    begin
        if v > hi then
            return hi;
        elsif v < lo then
            return lo;
        else
            return v;
        end if;
    end function;


    --32位限幅函数(乘除运算先扩充位数，在做截取)
    function f_sat32(x : signed(63 downto 0)) return signed is                        
        constant C_MAX : signed(63 downto 0) := to_signed(2147483647, 64);
        constant C_MIN : signed(63 downto 0) := to_signed(-2147483647, 64) - 1;
    begin
        if x > C_MAX then
            return to_signed(2147483647, 32);
        elsif x < C_MIN then
            return to_signed(-2147483647, 32) - 1;
        else
            return resize(x, 32);
        end if;
    end function;

    --32位限幅加法函数
    function f_sat_add32(a, b : signed(31 downto 0)) return signed is
    begin
        return f_sat32(resize(a, 64) + resize(b, 64));
    end function;

    --乘积项计算函数，有符号乘法，结果饱和为32位
    function f_pi_acc(
        gain : signed(31 downto 0);
        err  : signed(15 downto 0)
    ) return signed is
    begin
        return f_sat32(resize(gain * err, 64));
    end function;

    -- Qn → 频率整数，四舍五入（正负都先加 2^(n-1) 再算术右移）
    function f_q_to_i(x : signed(31 downto 0)) return signed is    --x为Q14乘积项
        variable v_x   : signed(47 downto 0);
        variable v_rnd : signed(47 downto 0);            
    begin
        if PI_SHIFT = 0 then
            return x;
        end if;
        v_rnd := shift_left(to_signed(1, 48), PI_SHIFT - 1);       --先取定点的一半
        v_x   := resize(x, 48) + v_rnd;                            --加上定点的一半进行四舍五入
        return f_sat32(resize(shift_right(v_x, PI_SHIFT), 64));    --再右移PI_SHIFT位，截取32位
    end function;

begin

    o_freq         <= r_freq;
    w_en_rise      <= i_enable and (not r_en_d);
    w_recalc_rise  <= i_recalc and (not r_recalc_d);

    process (i_sys_clk, i_sys_rst)
        variable v_vref    : integer;
        variable v_err     : integer;
        variable v_err_sat : integer;
        variable v_f_int   : integer;
        variable v_f_unsat : integer;
        variable v_f_cmd   : integer;
    begin
        if i_sys_rst = '1' then
            r_pipe     <= IDLE;
            r_en_d     <= '0';
            r_recalc_d <= '0';
            r_hold_i   <= '0';
            r_allow_i  <= '0';
            r_err_sat  <= (others => '0');
            r_f_unsat  <= (others => '0');
            r_kp_q     <= (others => '0');
            r_ki_q     <= (others => '0');
            r_integral <= (others => '0');
            r_freq     <= to_unsigned(F_MAX_HZ, 16);
            r_kp       <= (others => '0');
            r_ki       <= (others => '0');

        elsif rising_edge(i_sys_clk) then
            r_en_d     <= i_enable;
            r_recalc_d <= i_recalc;
            if i_reset = '1' then
                r_pipe     <= IDLE;
                r_hold_i   <= '0';
                r_allow_i  <= '0';
                r_err_sat  <= (others => '0');
                r_f_unsat  <= (others => '0');
                r_kp_q     <= (others => '0');
                r_ki_q     <= (others => '0');
                r_integral <= (others => '0');
                r_freq     <= to_unsigned(F_MAX_HZ, 16);
                r_kp       <= (others => '0');
                r_ki       <= (others => '0');

            else
                case r_pipe is
                    when IDLE =>
                        if w_en_rise = '1' then                 --触发一次PI流水
                            r_kp     <= i_kp;
                            r_ki     <= i_ki;
                            r_vo     <= i_vo;
                            r_vref   <= i_vref;
                            r_hold_i <= '0';                    --只触发PI流水，不重装积分
                            r_pipe   <= ERR_CALC;
                        elsif w_recalc_rise = '1' then
                            r_kp       <= i_kp;
                            r_ki       <= i_ki;
                            r_vo       <= i_vo;
                            r_vref     <= i_vref;
                            r_hold_i   <= '1';                  --触发一次PI流水，并重装积分
                            r_freq_ref <= i_freq_ref;            --重装参考频率
                            r_pipe     <= ERR_CALC;
                        end if;

                    when ERR_CALC =>
                        v_vref := to_integer(r_vref);
                        if v_vref > C_V_REF then
                            v_vref := C_V_REF;
                        end if;
                        v_err := to_integer(r_vo) - v_vref;
                        if (v_err >= -ERR_DEAD) and (v_err <= ERR_DEAD) then
                            v_err_sat := 0;
                        elsif v_err > ERR_SAT then
                            v_err_sat := ERR_SAT;
                        elsif v_err < -ERR_SAT then
                            v_err_sat := -ERR_SAT;
                        else
                            v_err_sat := v_err;
                        end if;
                        r_err_sat <= to_signed(v_err_sat, 16);
                        r_pipe    <= KP_TERM;

                    when KP_TERM =>
                        r_kp_q <= f_pi_acc(r_kp, r_err_sat);
                        r_pipe <= KI_TERM;

                    when KI_TERM =>
                        r_ki_q <= f_pi_acc(r_ki, r_err_sat);
                        r_pipe <= F_UNSAT;

                    when F_UNSAT =>                                            --算一下积分上下限的限幅
                        -- 未限幅：f = F_MIN + (I + Kp×err)
                        r_f_unsat <= to_signed(
                            F_MIN_HZ + to_integer(f_q_to_i(f_sat_add32(r_integral, r_kp_q))),
                            32);
                        r_pipe    <= I_ALLOW;

                    when I_ALLOW =>
                        v_f_unsat := to_integer(r_f_unsat);
                        -- err=Vo-Vref。开区间照常积；顶到 F_MAX 仅 err<0 往下退。
                        -- 顶到 F_MIN：err>0 往上退；err<0 仍可往负积，但 I 不低于 -I_FLOOR。
                        if ((v_f_unsat > F_MIN_HZ) and (v_f_unsat < F_MAX_HZ)) or
                           ((v_f_unsat >= F_MAX_HZ) and (to_integer(r_err_sat) < 0)) or
                           (v_f_unsat <= F_MIN_HZ) then
                            r_allow_i <= '1';
                        else
                            r_allow_i <= '0';
                        end if;
                        r_pipe <= I_UPDATE;

                    when I_UPDATE =>
                        if r_hold_i = '1' then
                            -- f = F_MIN + (I + Kp×err)/2^N ≈ f_ref
                            -- I = (f_ref - F_MIN)×2^N - Kp×err
                            v_f_int := f_clamp_i(to_integer(r_freq_ref), F_MIN_HZ, F_MAX_HZ) - F_MIN_HZ;
                            v_f_int := f_clamp_i(
                                v_f_int * (2 ** PI_SHIFT) - to_integer(r_kp_q),
                                C_I_MIN, C_I_LIM);
                            r_integral <= to_signed(v_f_int, 32);
                        elsif r_allow_i = '1' then
                            v_f_int := to_integer(f_sat_add32(r_integral, r_ki_q));
                            v_f_int := f_clamp_i(v_f_int, C_I_MIN, C_I_LIM);
                            r_integral <= to_signed(v_f_int, 32);
                        end if;
                        r_pipe <= P_CMD;

                    when P_CMD =>
                        v_f_cmd := F_MIN_HZ + to_integer(f_q_to_i(f_sat_add32(r_integral, r_kp_q)));
                        v_f_cmd := f_clamp_i(v_f_cmd, F_MIN_HZ, F_MAX_HZ);
                        r_freq  <= to_unsigned(v_f_cmd, 16);
                        r_pipe  <= IDLE;

                    when others =>
                        r_pipe <= IDLE;
                end case;
            end if;
        end if;
    end process;

end architecture rtl;
