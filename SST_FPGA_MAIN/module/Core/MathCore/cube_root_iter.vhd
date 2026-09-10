--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   cube_root_iter.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   牛顿迭代立方根：x = (2*x + a/(x*x)) / 3。
--                      
--                      状态机按 SQUARE -> DIV -> DIV3 对齐时序，利于 128 MHz。
--------------------------------------------------------------------------------
--Version           :   Rev 0.0
--modifier          :
--Modify Date       :
--Modify Record     :
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cube_root_iter is
    generic (
        WIDTH    : positive := 32;  -- 数据位宽
        ITER_NUM : positive := 10   -- 迭代次数
    );
    port (
        -- Global Clock
        i_sys_clk : in  std_logic;
        i_sys_rst : in  std_logic;  -- 异步复位，高有效

        -- User Interface
        i_start : in  std_logic;                     -- 启动脉冲
        i_data  : in  signed(WIDTH - 1 downto 0);    -- 输入
        o_data  : out signed(WIDTH - 1 downto 0);    -- 立方根结果
        o_done  : out std_logic                      -- 完成脉冲
    );
end entity cube_root_iter;

architecture rtl of cube_root_iter is

    -- mult_axb：输入打拍 + 乘 + 输出打拍 = 3
    -- 另加 1 拍：r_x 与 mult 输入寄存器同沿更新时需多等 1 拍
    constant MULT_WAIT : positive := 4;

    type t_state is (IDLE, SQUARE, CALC_DIV, CALC_DIV3);
    signal r_state : t_state := IDLE;

    signal r_a        : signed(WIDTH - 1 downto 0) := (others => '0');  -- 锁存被开方数
    signal r_x        : signed(WIDTH - 1 downto 0) := (others => '0');
    signal r_dout     : signed(WIDTH - 1 downto 0) := (others => '0');
    signal r_iter_cnt : unsigned(3 downto 0) := (others => '0');
    signal r_busy     : std_logic := '0';
    signal r_done     : std_logic := '0';
    signal r_mult_cnt : unsigned(2 downto 0) := (others => '0');

    signal w_mult_p : std_logic_vector(2 * WIDTH - 1 downto 0);

    signal r_div_start  : std_logic := '0';
    signal r_div_dvd    : signed(WIDTH - 1 downto 0) := (others => '0');
    signal r_div_dvs    : signed(WIDTH - 1 downto 0) := (others => '0');
    signal w_div_done   : std_logic;
    signal w_div_quot   : signed(WIDTH - 1 downto 0);

    signal r_div3_start : std_logic := '0';
    signal r_div3_dvd   : signed(WIDTH - 1 downto 0) := (others => '0');
    signal r_div3_dvs   : signed(WIDTH - 1 downto 0) := (others => '0');
    signal w_div3_done  : std_logic;
    signal w_div3_quot  : signed(WIDTH - 1 downto 0);

begin

    o_data <= r_dout;
    o_done <= r_done;

    -- ===================== x * x（3 拍流水，消除组合乘） =====================
    U_MULT_X2 : entity work.mult_axb
        generic map (
            AWIDTH     => WIDTH,
            BWIDTH     => WIDTH,
            PWIDTH     => 2 * WIDTH,
            TC         => 1,
            PREFER_DSP => true
        )
        port map (
            i_sys_clk => i_sys_clk,
            i_a       => std_logic_vector(r_x),
            i_b       => std_logic_vector(r_x),
            o_p       => w_mult_p
        );

    -- ===================== a / (x*x) =====================
    U_DIV : entity work.signed_division
        generic map (
            WIDTH_DVD => WIDTH,
            WIDTH_DVS => WIDTH
        )
        port map (
            i_sys_clk   => i_sys_clk,
            i_sys_rst   => i_sys_rst,
            i_start     => r_div_start,
            i_dividend  => r_div_dvd,
            i_divisor   => r_div_dvs,
            o_quotient  => w_div_quot,
            o_remainder => open,
            o_done      => w_div_done,
            o_busy      => open
        );

    -- ===================== (2*x + a/(x*x)) / 3 =====================
    U_DIV3 : entity work.signed_division
        generic map (
            WIDTH_DVD => WIDTH,
            WIDTH_DVS => WIDTH
        )
        port map (
            i_sys_clk   => i_sys_clk,
            i_sys_rst   => i_sys_rst,
            i_start     => r_div3_start,
            i_dividend  => r_div3_dvd,
            i_divisor   => r_div3_dvs,
            o_quotient  => w_div3_quot,
            o_remainder => open,
            o_done      => w_div3_done,
            o_busy      => open
        );

    -- ===================== 主状态机 =====================
    process (i_sys_clk, i_sys_rst)
        variable v_x2 : signed(WIDTH - 1 downto 0);
    begin
        if i_sys_rst = '1' then
            r_state      <= IDLE;
            r_a          <= (others => '0');
            r_x          <= (others => '0');
            r_dout       <= (others => '0');
            r_iter_cnt   <= (others => '0');
            r_done       <= '0';
            r_busy       <= '0';
            r_mult_cnt   <= (others => '0');
            r_div_start  <= '0';
            r_div_dvd    <= (others => '0');
            r_div_dvs    <= (others => '0');
            r_div3_start <= '0';
            r_div3_dvd   <= (others => '0');
            r_div3_dvs   <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            r_div_start  <= '0';
            r_div3_start <= '0';

            case r_state is
                when IDLE =>
                    r_done <= '0';
                    if (i_start = '1') and (r_busy = '0') then
                        r_a        <= i_data;
                        r_x        <= i_data;
                        r_iter_cnt <= (others => '0');
                        r_busy     <= '1';
                        r_mult_cnt <= (others => '0');
                        r_state    <= SQUARE;
                    end if;

                when SQUARE =>
                    if r_mult_cnt = to_unsigned(MULT_WAIT - 1, r_mult_cnt'length) then
                        v_x2 := signed(w_mult_p(WIDTH - 1 downto 0));
                        -- 防除零：x^2=0 时用 1
                        if v_x2 = 0 then
                            v_x2 := to_signed(1, WIDTH);
                        end if;

                        r_div_dvd   <= r_a;
                        r_div_dvs   <= v_x2;
                        r_div_start <= '1';
                        r_mult_cnt  <= (others => '0');
                        r_state     <= CALC_DIV;
                    else
                        r_mult_cnt <= r_mult_cnt + 1;
                    end if;

                when CALC_DIV =>
                    if w_div_done = '1' then
                        r_div3_dvd   <= shift_left(r_x, 1) + w_div_quot;
                        r_div3_dvs   <= to_signed(3, WIDTH);
                        r_div3_start <= '1';
                        r_state      <= CALC_DIV3;
                    end if;

                when CALC_DIV3 =>
                    if w_div3_done = '1' then
                        r_x        <= w_div3_quot;
                        r_iter_cnt <= r_iter_cnt + 1;
                        if (r_iter_cnt + 1) < ITER_NUM then
                            r_mult_cnt <= (others => '0');
                            r_state    <= SQUARE;
                        else
                            r_dout  <= w_div3_quot;
                            r_done  <= '1';
                            r_busy  <= '0';
                            r_state <= IDLE;
                        end if;
                    end if;

                when others =>
                    r_state <= IDLE;
            end case;
        end if;
    end process;

end architecture rtl;
