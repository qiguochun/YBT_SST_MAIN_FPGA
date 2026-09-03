--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   signed_division.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   有符号整数除法（恢复余数移位除法）。
--                      Rev 0.2：比较/减并入时钟进程（去掉长组合云），o_busy 寄存输出。
--------------------------------------------------------------------------------
--Version           :   Rev 0.2
--modifier          :   Qigc
--Modify Date       :   2026.09.03
--Modify Record     :   时序优化：移位比较减在 clocked process 内用 variable 完成
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity signed_division is
    generic (
        WIDTH_DVD : positive := 16;  -- 被除数位宽
        WIDTH_DVS : positive := 8    -- 除数位宽
    );
    port (
        -- Global Clock
        i_sys_clk   : in  std_logic;
        i_sys_rst   : in  std_logic;  -- 异步复位，高有效

        -- User Interface
        i_start     : in  std_logic;
        i_dividend  : in  signed(WIDTH_DVD - 1 downto 0);
        i_divisor   : in  signed(WIDTH_DVS - 1 downto 0);
        o_quotient  : out signed(WIDTH_DVD - 1 downto 0);
        o_remainder : out signed(WIDTH_DVS - 1 downto 0);
        o_done      : out std_logic;
        o_busy      : out std_logic
    );
end entity signed_division;

architecture rtl of signed_division is

    function clog2(n : positive) return natural is
        variable v_tmp : natural := n;
        variable v_log : natural := 0;
    begin
        while v_tmp > 1 loop
            v_tmp := v_tmp / 2;
            v_log := v_log + 1;
        end loop;
        return v_log;
    end function;

    constant CNT_WIDTH : natural := clog2(WIDTH_DVD);

    type t_state is (IDLE, BUSY);
    signal r_state : t_state := IDLE;

    signal r_done             : std_logic := '0';
    signal r_busy             : std_logic := '0';
    signal r_quotient         : signed(WIDTH_DVD - 1 downto 0) := (others => '0');
    signal r_remainder        : signed(WIDTH_DVS - 1 downto 0) := (others => '0');
    signal r_dividend_sign    : std_logic := '0';
    signal r_divisor_sign     : std_logic := '0';
    signal r_divisor          : unsigned(WIDTH_DVS - 1 downto 0) := (others => '0');
    signal r_temp_dvd_shifted : unsigned(WIDTH_DVD + WIDTH_DVS - 1 downto 0) := (others => '0');
    signal r_quotient_buf     : unsigned(WIDTH_DVD - 1 downto 0) := (others => '0');
    signal r_cycle_cnt        : unsigned(CNT_WIDTH downto 0) := (others => '0');

begin

    o_quotient  <= r_quotient;
    o_remainder <= r_remainder;
    o_done      <= r_done;
    o_busy      <= r_busy;

    -- ===================== 除法状态机（比较减在沿内完成） =====================
    process (i_sys_clk, i_sys_rst)
        variable v_abs_dvd   : unsigned(WIDTH_DVD - 1 downto 0);
        variable v_abs_dvs   : unsigned(WIDTH_DVS - 1 downto 0);
        variable v_shifted   : unsigned(WIDTH_DVD + WIDTH_DVS - 1 downto 0);
        variable v_high      : unsigned(WIDTH_DVS - 1 downto 0);
        variable v_new_high  : unsigned(WIDTH_DVS - 1 downto 0);
        variable v_quot_next : unsigned(WIDTH_DVD - 1 downto 0);
    begin
        if i_sys_rst = '1' then
            r_state            <= IDLE;
            r_done             <= '0';
            r_busy             <= '0';
            r_temp_dvd_shifted <= (others => '0');
            r_quotient_buf     <= (others => '0');
            r_divisor          <= (others => '0');
            r_cycle_cnt        <= (others => '0');
            r_quotient         <= (others => '0');
            r_remainder        <= (others => '0');
            r_dividend_sign    <= '0';
            r_divisor_sign     <= '0';
        elsif rising_edge(i_sys_clk) then
            case r_state is
                when IDLE =>
                    r_done <= '0';
                    r_busy <= '0';
                    if i_start = '1' then
                        r_dividend_sign <= i_dividend(WIDTH_DVD - 1);
                        r_divisor_sign  <= i_divisor(WIDTH_DVS - 1);

                        if i_dividend < 0 then
                            v_abs_dvd := unsigned(-i_dividend);
                        else
                            v_abs_dvd := unsigned(i_dividend);
                        end if;

                        if i_divisor < 0 then
                            v_abs_dvs := unsigned(-i_divisor);
                        else
                            v_abs_dvs := unsigned(i_divisor);
                        end if;

                        r_divisor          <= v_abs_dvs;
                        r_temp_dvd_shifted <= resize(v_abs_dvd, WIDTH_DVD + WIDTH_DVS);
                        r_quotient_buf     <= (others => '0');
                        r_cycle_cnt        <= (others => '0');
                        r_busy             <= '1';
                        r_state            <= BUSY;
                    end if;

                when BUSY =>
                    -- 单拍商位：<<1 → 比较 → 条件减（variable，无额外组合云扇出）
                    v_shifted := shift_left(r_temp_dvd_shifted, 1);
                    v_high    := v_shifted(WIDTH_DVD + WIDTH_DVS - 1 downto WIDTH_DVD);

                    if v_high >= r_divisor then
                        v_new_high  := v_high - r_divisor;
                        v_quot_next := shift_left(r_quotient_buf, 1) or to_unsigned(1, WIDTH_DVD);
                    else
                        v_new_high  := v_high;
                        v_quot_next := shift_left(r_quotient_buf, 1);
                    end if;

                    r_temp_dvd_shifted <= v_new_high & v_shifted(WIDTH_DVD - 1 downto 0);
                    r_quotient_buf     <= v_quot_next;
                    r_cycle_cnt        <= r_cycle_cnt + 1;
                    r_busy             <= '1';

                    if r_cycle_cnt = to_unsigned(WIDTH_DVD - 1, r_cycle_cnt'length) then
                        if (r_dividend_sign xor r_divisor_sign) = '1' then
                            r_quotient <= -signed(v_quot_next);
                        else
                            r_quotient <= signed(v_quot_next);
                        end if;

                        if r_dividend_sign = '1' then
                            r_remainder <= -signed(v_new_high);
                        else
                            r_remainder <= signed(v_new_high);
                        end if;

                        r_done  <= '1';
                        r_busy  <= '1';  -- done 周期保持 busy，与原行为一致
                        r_state <= IDLE;
                    end if;

                when others =>
                    r_state <= IDLE;
                    r_busy  <= '0';
            end case;
        end if;
    end process;

end architecture rtl;
