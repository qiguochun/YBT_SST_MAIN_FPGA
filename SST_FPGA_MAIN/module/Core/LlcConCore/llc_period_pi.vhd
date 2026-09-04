--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   llc_period_pi.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   电压环 PIR（PI + 100/200 Hz 谐振）。
--                      err = Vref - DCO（V×10）；输出频率编码 Hz/10。
--                      控制律（频率域，对齐 MATLAB local_period_pir）：
--                        f = f_int - Kp*err - Kr*R100 - 0.35*Kr*R200
--                      谐振器 R(s)=s/(s^2+2ζωs+ω^2)，前向欧拉，节拍 i_tick。
--                      端口保持不变；Burst/电流环/软起等未实现。
--------------------------------------------------------------------------------
--Version           :   Rev 1.0
--modifier          :   Qigc
--Modify Date       :   2026.09.04
--Modify Record     :   由纯 PI 扩展为 PIR（仅本文件）
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity llc_period_pi is
    generic (
        CLK_FREQ : positive := 30_000_000;  -- 系统时钟 Hz（兼容保留）
        -- 频率编码：实际频率(Hz)/10
        F_MAX    : natural := 8000;         -- 80.0 kHz
        F_MIN    : natural := 2500;         -- 25.0 kHz
        ERR_SAT  : natural := 400;          -- 40.0 V（V×10）
        PI_Q     : natural := 4096;         -- Kp/Ki Q12
        -- 谐振：系数按 TICK≈102.4 kHz、ζ=0.03、ω=2π·100 预计算（Q24）
        -- 状态单位：0.1 V 的 Q24；res_hz10 ≈ (KR_SC*dx100 + KR35_SC*dx200) >> 24
        KR_SC    : integer := 5500;         -- Kr/100，Kr=5.5e5 → Hz/10
        KR35_SC  : integer := 1925;         -- 0.35*Kr/100
        R_SAT    : natural := 800;          -- 谐振项限幅 8.0 kHz（Hz/10）
        ERR_GATE : natural := 120;          -- |err|>12 V 时谐振输入置 0
        C_DT     : integer := 164;          -- dt·2^24
        C_W2_100 : integer := 64681439;     -- dt·ω^2·2^24（100 Hz）
        C_D_100  : integer := 6177;         -- dt·2ζω·2^24
        C_W2_200 : integer := 258725758;    -- dt·(2ω)^2·2^24（200 Hz）
        C_D_200  : integer := 12353
    );
    port (
        i_sys_clk : in  std_logic;
        i_sys_rst : in  std_logic;

        i_tick    : in  std_logic;
        i_restart : in  std_logic;
        i_enable  : in  std_logic;
        i_vref    : in  signed(15 downto 0);
        i_dco     : in  signed(15 downto 0);
        i_kp      : in  signed(15 downto 0);  -- Q12
        i_ki      : in  signed(15 downto 0);  -- Q12
        o_freq    : out unsigned(15 downto 0) -- Hz/10
    );
end entity llc_period_pi;

architecture rtl of llc_period_pi is

    type t_pipe is (
        IDLE,
        ERR_CALC,
        RES100,
        RES200,
        RES_MIX,
        I_UPDATE,
        P_CMD
    );
    signal r_pipe : t_pipe := IDLE;

    signal r_err_sat  : signed(15 downto 0) := (others => '0');
    signal r_res_in   : signed(15 downto 0) := (others => '0');
    signal r_res_hz10 : signed(31 downto 0) := (others => '0');
    signal r_f_unsat  : signed(31 downto 0) := (others => '0');
    signal r_integral : signed(31 downto 0) := to_signed(F_MAX, 32);
    signal r_freq     : unsigned(15 downto 0) := to_unsigned(F_MAX, 16);
    signal r_kp       : signed(15 downto 0) := (others => '0');
    signal r_ki       : signed(15 downto 0) := (others => '0');

    -- 谐振器状态（Q24，单位 0.1 V）
    signal r_x100  : signed(31 downto 0) := (others => '0');
    signal r_dx100 : signed(31 downto 0) := (others => '0');
    signal r_x200  : signed(31 downto 0) := (others => '0');
    signal r_dx200 : signed(31 downto 0) := (others => '0');
    -- 候选下一拍（输出饱和时丢弃）
    signal r_x100_n  : signed(31 downto 0) := (others => '0');
    signal r_dx100_n : signed(31 downto 0) := (others => '0');
    signal r_x200_n  : signed(31 downto 0) := (others => '0');
    signal r_dx200_n : signed(31 downto 0) := (others => '0');

    function f_clamp_i(v, lo, hi : integer) return integer is
    begin
        if v > hi then
            return hi;
        elsif v < lo then
            return lo;
        else
            return v;
        end if;
    end function;

    -- Q24 乘加：acc + (c * x)>>24 ，64 位中间结果
    function f_mac_q24(acc : signed(31 downto 0); c : integer; x : signed(31 downto 0))
        return signed is
        variable v_p : signed(63 downto 0);
    begin
        v_p := resize(to_signed(c, 32), 64) * resize(x, 64);
        return resize(acc + resize(shift_right(v_p, 24), 32), 32);
    end function;

begin

    o_freq <= r_freq;

    process (i_sys_clk, i_sys_rst)
        variable v_err      : integer;
        variable v_err_sat  : integer;
        variable v_res_in   : integer;
        variable v_dx       : signed(31 downto 0);
        variable v_acc      : signed(31 downto 0);
        variable v_p        : signed(63 downto 0);
        variable v_res      : integer;
        variable v_kp_term  : integer;
        variable v_ki_term  : integer;
        variable v_f_int    : integer;
        variable v_f_unsat  : integer;
        variable v_f_cmd    : integer;
        variable v_drive    : integer;
        variable v_allow_i  : boolean;
        variable v_sat_hi   : boolean;
        variable v_sat_lo   : boolean;
    begin
        if i_sys_rst = '1' then
            r_pipe     <= IDLE;
            r_err_sat  <= (others => '0');
            r_res_in   <= (others => '0');
            r_res_hz10 <= (others => '0');
            r_f_unsat  <= (others => '0');
            r_integral <= to_signed(F_MAX, 32);
            r_freq     <= to_unsigned(F_MAX, 16);
            r_kp       <= (others => '0');
            r_ki       <= (others => '0');
            r_x100     <= (others => '0');
            r_dx100    <= (others => '0');
            r_x200     <= (others => '0');
            r_dx200    <= (others => '0');
            r_x100_n   <= (others => '0');
            r_dx100_n  <= (others => '0');
            r_x200_n   <= (others => '0');
            r_dx200_n  <= (others => '0');

        elsif rising_edge(i_sys_clk) then
            if i_restart = '1' then
                r_pipe     <= IDLE;
                r_err_sat  <= (others => '0');
                r_res_in   <= (others => '0');
                r_res_hz10 <= (others => '0');
                r_f_unsat  <= (others => '0');
                r_integral <= to_signed(F_MAX, 32);
                r_freq     <= to_unsigned(F_MAX, 16);
                r_kp       <= (others => '0');
                r_ki       <= (others => '0');
                r_x100     <= (others => '0');
                r_dx100    <= (others => '0');
                r_x200     <= (others => '0');
                r_dx200    <= (others => '0');
                r_x100_n   <= (others => '0');
                r_dx100_n  <= (others => '0');
                r_x200_n   <= (others => '0');
                r_dx200_n  <= (others => '0');

            else
                case r_pipe is
                    when IDLE =>
                        if (i_tick = '1') and (i_enable = '1') then
                            r_kp   <= i_kp;
                            r_ki   <= i_ki;
                            r_pipe <= ERR_CALC;
                        end if;

                    ----------------------------------------------------------------
                    -- 误差限幅；大误差时谐振输入清零（对齐 MATLAB |err|>12）
                    ----------------------------------------------------------------
                    when ERR_CALC =>
                        v_err := to_integer(i_vref) - to_integer(i_dco);
                        if v_err > ERR_SAT then
                            v_err_sat := ERR_SAT;
                        elsif v_err < -ERR_SAT then
                            v_err_sat := -ERR_SAT;
                        else
                            v_err_sat := v_err;
                        end if;
                        r_err_sat <= to_signed(v_err_sat, 16);

                        if abs(v_err) > ERR_GATE then
                            v_res_in := 0;
                        else
                            v_res_in := v_err_sat;
                        end if;
                        r_res_in <= to_signed(v_res_in, 16);
                        r_pipe   <= RES100;

                    ----------------------------------------------------------------
                    -- 100 Hz：dx += -dt·ω²·x - dt·2ζω·dx + dt·u
                    --         x  += dt·dx_n
                    ----------------------------------------------------------------
                    when RES100 =>
                        v_acc := to_signed(C_DT * to_integer(r_res_in), 32);
                        v_acc := f_mac_q24(v_acc, -C_W2_100, r_x100);
                        v_acc := f_mac_q24(v_acc, -C_D_100, r_dx100);
                        v_dx  := resize(r_dx100 + v_acc, 32);
                        r_dx100_n <= v_dx;
                        -- x_n = x + (C_DT * dx_n)>>24
                        v_p := resize(to_signed(C_DT, 32), 64) * resize(v_dx, 64);
                        r_x100_n <= resize(r_x100 + resize(shift_right(v_p, 24), 32), 32);
                        r_pipe   <= RES200;

                    ----------------------------------------------------------------
                    -- 200 Hz
                    ----------------------------------------------------------------
                    when RES200 =>
                        v_acc := to_signed(C_DT * to_integer(r_res_in), 32);
                        v_acc := f_mac_q24(v_acc, -C_W2_200, r_x200);
                        v_acc := f_mac_q24(v_acc, -C_D_200, r_dx200);
                        v_dx  := resize(r_dx200 + v_acc, 32);
                        r_dx200_n <= v_dx;
                        v_p := resize(to_signed(C_DT, 32), 64) * resize(v_dx, 64);
                        r_x200_n <= resize(r_x200 + resize(shift_right(v_p, 24), 32), 32);
                        r_pipe   <= RES_MIX;

                    ----------------------------------------------------------------
                    -- res = Kr·dx100 + 0.35·Kr·dx200，限幅
                    ----------------------------------------------------------------
                    when RES_MIX =>
                        v_p := resize(to_signed(KR_SC, 32), 64) * resize(r_dx100_n, 64)
                             + resize(to_signed(KR35_SC, 32), 64) * resize(r_dx200_n, 64);
                        v_res := to_integer(resize(shift_right(v_p, 24), 32));
                        v_res := f_clamp_i(v_res, -R_SAT, R_SAT);
                        r_res_hz10 <= to_signed(v_res, 32);

                        -- 未积分前的试探频率（用于 anti-windup）
                        v_f_int   := to_integer(r_integral);
                        v_kp_term := (to_integer(r_kp) * to_integer(r_err_sat)) / PI_Q;
                        v_f_unsat := v_f_int - v_kp_term - v_res;
                        r_f_unsat <= to_signed(v_f_unsat, 32);
                        r_pipe    <= I_UPDATE;

                    ----------------------------------------------------------------
                    -- 积分：f_int -= Ki*err/Q ；带条件 anti-windup
                    ----------------------------------------------------------------
                    when I_UPDATE =>
                        v_f_int   := to_integer(r_integral);
                        v_f_unsat := to_integer(r_f_unsat);
                        v_allow_i :=
                            ((v_f_unsat > F_MIN) and (v_f_unsat < F_MAX)) or
                            ((v_f_unsat >= F_MAX) and (to_integer(r_err_sat) > 0)) or
                            ((v_f_unsat <= F_MIN) and (to_integer(r_err_sat) < 0));

                        if v_allow_i then
                            v_ki_term := (to_integer(r_ki) * to_integer(r_err_sat)) / PI_Q;
                            v_f_int   := f_clamp_i(v_f_int - v_ki_term, F_MIN, F_MAX);
                            r_integral <= to_signed(v_f_int, 32);
                        end if;
                        r_pipe <= P_CMD;

                    ----------------------------------------------------------------
                    -- f_cmd = f_int - Kp*err - res；输出饱和时冻结谐振器
                    ----------------------------------------------------------------
                    when P_CMD =>
                        v_f_int   := to_integer(r_integral);
                        v_kp_term := (to_integer(r_kp) * to_integer(r_err_sat)) / PI_Q;
                        v_drive   := -v_kp_term - to_integer(r_res_hz10);
                        v_f_cmd   := v_f_int + v_drive;

                        v_sat_hi := (v_f_cmd >= F_MAX) and (v_drive > 0);
                        v_sat_lo := (v_f_cmd <= F_MIN) and (v_drive < 0);

                        if not (v_sat_hi or v_sat_lo) then
                            r_x100  <= r_x100_n;
                            r_dx100 <= r_dx100_n;
                            r_x200  <= r_x200_n;
                            r_dx200 <= r_dx200_n;
                        end if;

                        v_f_cmd := f_clamp_i(v_f_cmd, F_MIN, F_MAX);
                        r_freq  <= to_unsigned(v_f_cmd, 16);
                        r_pipe  <= IDLE;

                    when others =>
                        r_pipe <= IDLE;
                end case;
            end if;
        end if;
    end process;

end architecture rtl;
