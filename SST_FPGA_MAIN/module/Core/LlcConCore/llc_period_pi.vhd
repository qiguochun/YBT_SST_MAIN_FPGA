--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   llc_period_pi.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   Stage2 周期 PI：err = Vref - DCO，限幅后 PI 调周期。
--                      输出周期限幅 [T_START, T_END]；乘加分两拍降低组合深度。
--------------------------------------------------------------------------------
--Version           :   Rev 0.1
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity llc_period_pi is
    generic (
        T_START : natural := 1600;
        T_END   : natural := 5120;
        ERR_SAT : natural := 400;
        PI_Q    : natural := 4096
    );
    port (
        -- Global Clock
        i_sys_clk : in  std_logic;
        i_sys_rst : in  std_logic;

        -- User Interface
        i_tick   : in  std_logic;
        i_enable : in  std_logic;                    -- STAGE2
        i_vref   : in  signed(15 downto 0);
        i_dco    : in  signed(15 downto 0);
        i_kp     : in  signed(15 downto 0);          -- Q12
        i_ki     : in  signed(15 downto 0);          -- Q12
        o_period : out unsigned(15 downto 0)
    );
end entity llc_period_pi;

architecture rtl of llc_period_pi is

    type t_pipe is (IDLE, ERR_CALC, I_UPDATE, P_UPDATE);
    signal r_pipe : t_pipe := IDLE;

    signal r_err_sat  : signed(15 downto 0) := (others => '0');
    signal r_pi_sum   : signed(31 downto 0) := (others => '0');
    signal r_integral : signed(31 downto 0) := to_signed(T_START, 32);
    signal r_period   : unsigned(15 downto 0) := to_unsigned(T_START, 16);
    signal r_kp       : signed(15 downto 0) := (others => '0');
    signal r_ki       : signed(15 downto 0) := (others => '0');

begin

    o_period <= r_period;

    process (i_sys_clk, i_sys_rst)
        variable v_err     : integer;
        variable v_err_sat : integer;
        variable v_ki_term : integer;
        variable v_kp_term : integer;
        variable v_sum     : integer;
        variable v_cmd     : integer;
        variable v_i_q     : integer;
    begin
        if i_sys_rst = '1' then
            r_pipe     <= IDLE;
            r_err_sat  <= (others => '0');
            r_pi_sum   <= (others => '0');
            r_integral <= to_signed(T_START, 32);
            r_period   <= to_unsigned(T_START, 16);
            r_kp       <= (others => '0');
            r_ki       <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            case r_pipe is
                when IDLE =>
                    if (i_tick = '1') and (i_enable = '1') then
                        r_kp   <= i_kp;
                        r_ki   <= i_ki;
                        r_pipe <= ERR_CALC;
                    end if;

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
                    r_pipe    <= I_UPDATE;

                when I_UPDATE =>
                    -- integral*Q + KI*err，再限幅到 [T_START,T_END]*Q
                    v_ki_term := to_integer(r_ki) * to_integer(r_err_sat);
                    v_sum     := to_integer(r_integral) * PI_Q + v_ki_term;
                    if v_sum > T_END * PI_Q then
                        v_sum := T_END * PI_Q;
                    elsif v_sum < T_START * PI_Q then
                        v_sum := T_START * PI_Q;
                    end if;
                    r_pi_sum <= to_signed(v_sum, 32);
                    r_pipe   <= P_UPDATE;

                when P_UPDATE =>
                    v_kp_term := to_integer(r_kp) * to_integer(r_err_sat);
                    v_i_q     := to_integer(r_pi_sum) / PI_Q;
                    v_cmd     := v_i_q + (v_kp_term / PI_Q);

                    if v_cmd < T_START then
                        v_cmd      := T_START;
                        r_integral <= to_signed(T_START, 32);
                    elsif v_cmd > T_END then
                        v_cmd      := T_END;
                        r_integral <= to_signed(T_END, 32);
                    else
                        r_integral <= to_signed(v_i_q, 32);
                    end if;

                    r_period <= to_unsigned(v_cmd, 16);
                    r_pipe   <= IDLE;

                when others =>
                    r_pipe <= IDLE;
            end case;
        end if;
    end process;

end architecture rtl;
