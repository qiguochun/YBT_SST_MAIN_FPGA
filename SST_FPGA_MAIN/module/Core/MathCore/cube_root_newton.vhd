--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   cube_root_newton.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   牛顿迭代法求立方根：x = (2*xn + a/xn^2)/3。
--                      依赖 mult_axb（平方，3 拍）与 signed_division（两次除法）。
--------------------------------------------------------------------------------
--Version           :   Rev 0.2
--modifier          :   Qigc
--Modify Date       :   2026.09.03
--Modify Record     :   S1 等待对齐 mult_axb 3 拍（原 2 拍偏短）
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cube_root_newton is
    generic (
        WIDTH      : positive := 16;  -- 数据位宽
        ITERATIONS : positive := 20   -- 牛顿迭代次数
    );
    port (
        -- Global Clock
        i_sys_clk : in  std_logic;
        i_sys_rst : in  std_logic;  -- 异步复位，高有效

        -- User Interface
        i_data       : in  signed(WIDTH - 1 downto 0);  -- 输入，约 -32767~32767
        i_data_valid : in  std_logic;                   -- 启动有效
        o_data       : out signed(WIDTH - 1 downto 0);  -- 立方根结果
        o_data_valid : out std_logic;                   -- 结果有效脉冲
        o_busy       : out std_logic                    -- 忙标志
    );
end entity cube_root_newton;

architecture rtl of cube_root_newton is

    function clogb2(depth : natural) return natural is
        variable v_tmp : natural := depth;
        variable v_log : natural := 0;
    begin
        while v_tmp > 0 loop
            v_tmp := v_tmp / 2;
            v_log := v_log + 1;
        end loop;
        return v_log;
    end function;

    -- 派生位宽（与原 Verilog 参数保持一致）
    constant XN_WIDTH      : positive := WIDTH - 1;                 -- xn 位宽
    constant XN_SQ_WIDTH   : positive := (WIDTH - 1) * 2;           -- xn^2 位宽
    constant DIV1_WIDTH    : positive := (WIDTH - 2) * 2 + 1;       -- 第一次除法位宽
    constant CNT_ITER_BW   : natural  := clogb2(ITERATIONS);

    type t_state is (IDLE, S1, S2, S3, S4);
    signal r_state      : t_state := IDLE;
    signal w_next_state : t_state;

    signal r_a              : signed(WIDTH - 1 downto 0) := (others => '0');
    signal r_xn             : signed(XN_WIDTH - 1 downto 0) := (others => '0');
    signal r_cnt_iteration  : unsigned(CNT_ITER_BW - 1 downto 0) := (others => '0');
    signal r_s1_delay       : unsigned(1 downto 0) := (others => '0');  -- 等 mult_axb 3 拍
    signal r_state_d1       : t_state := IDLE;

    signal w_xn_multi2      : signed(WIDTH - 1 downto 0);
    signal w_xn_square      : std_logic_vector(XN_SQ_WIDTH - 1 downto 0);

    signal w_div1_start     : std_logic;
    signal w_div1_done      : std_logic;
    signal w_div1_quot      : signed(DIV1_WIDTH - 1 downto 0);
    signal w_div1_dvd       : signed(DIV1_WIDTH - 1 downto 0);
    signal w_div1_dvs       : signed(DIV1_WIDTH - 1 downto 0);

    signal r_div2_dvd       : signed(DIV1_WIDTH - 1 downto 0) := (others => '0');
    signal w_div2_start     : std_logic;
    signal w_div2_done      : std_logic;
    signal w_div2_quot      : signed(DIV1_WIDTH - 1 downto 0);

    signal r_data       : signed(WIDTH - 1 downto 0) := (others => '0');
    signal r_data_valid : std_logic := '0';
    signal r_busy       : std_logic := '0';

begin

    w_xn_multi2 <= resize(shift_left(r_xn, 1), WIDTH);

    -- a 符号扩展到 DIV1_WIDTH，作为被除数
    w_div1_dvd <= resize(r_a, DIV1_WIDTH);
    -- xn^2 截取低 DIV1_WIDTH 位作为除数（与原 Verilog 位宽对接行为一致）
    w_div1_dvs <= signed(w_xn_square(DIV1_WIDTH - 1 downto 0));

    w_div1_start <= '1' when (r_state = S2) and (r_state_d1 = S1) else '0';
    w_div2_start <= '1' when (r_state = S3) and (r_state_d1 = S2) else '0';

    o_data       <= r_data;
    o_data_valid <= r_data_valid;
    o_busy       <= r_busy;

    -- ===================== 状态寄存器 =====================
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_state <= IDLE;
        elsif rising_edge(i_sys_clk) then
            r_state <= w_next_state;
        end if;
    end process;

    -- ===================== 次态组合 =====================
    process (r_state, i_data_valid, r_s1_delay, w_div1_done, w_div2_done, r_cnt_iteration)
    begin
        case r_state is
            when IDLE =>
                if i_data_valid = '1' then
                    w_next_state <= S1;
                else
                    w_next_state <= IDLE;
                end if;
            when S1 =>
                -- mult_axb 延迟 3 拍；计数 0..2 共 3 拍后进 S2
                if r_s1_delay = to_unsigned(2, r_s1_delay'length) then
                    w_next_state <= S2;
                else
                    w_next_state <= S1;
                end if;
            when S2 =>
                if w_div1_done = '1' then
                    w_next_state <= S3;
                else
                    w_next_state <= S2;
                end if;
            when S3 =>
                if w_div2_done = '1' then
                    w_next_state <= S4;
                else
                    w_next_state <= S3;
                end if;
            when S4 =>
                if r_cnt_iteration = to_unsigned(ITERATIONS, r_cnt_iteration'length) then
                    w_next_state <= IDLE;
                else
                    w_next_state <= S1;
                end if;
            when others =>
                w_next_state <= IDLE;
        end case;
    end process;

    -- ===================== 输入 a 锁存 =====================
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_a <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            if r_state = IDLE then
                r_a <= i_data;
            end if;
        end if;
    end process;

    -- ===================== xn 更新 =====================
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_xn <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            if r_state = IDLE then
                r_xn <= resize(shift_right(i_data, 1), XN_WIDTH);
            elsif r_state = S4 then
                r_xn <= w_div2_quot(XN_WIDTH - 1 downto 0);
            end if;
        end if;
    end process;

    -- ===================== 迭代计数 =====================
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_cnt_iteration <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            if r_state = IDLE then
                r_cnt_iteration <= (others => '0');
            elsif w_div2_done = '1' then
                if r_cnt_iteration /= to_unsigned(ITERATIONS, r_cnt_iteration'length) then
                    r_cnt_iteration <= r_cnt_iteration + 1;
                end if;
            end if;
        end if;
    end process;

    -- ===================== S1 延时（等待乘法 3 拍） =====================
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_s1_delay <= (others => '0');
            r_state_d1 <= IDLE;
        elsif rising_edge(i_sys_clk) then
            if r_state = S1 then
                if r_s1_delay < to_unsigned(2, r_s1_delay'length) then
                    r_s1_delay <= r_s1_delay + 1;
                end if;
            else
                r_s1_delay <= (others => '0');
            end if;
            r_state_d1 <= r_state;
        end if;
    end process;

    -- ===================== 平方：xn * xn =====================
    U_MULT_XN_SQ : entity work.mult_axb
        generic map (
            AWIDTH  => XN_WIDTH,
            BWIDTH  => XN_WIDTH,
            PWIDTH  => XN_SQ_WIDTH,
            TC      => 1,
            PREFER_DSP => true
        )
        port map (
            i_sys_clk => i_sys_clk,
            i_a       => std_logic_vector(r_xn),
            i_b       => std_logic_vector(r_xn),
            o_p       => w_xn_square
        );

    -- ===================== 除法1：a / xn^2 =====================
    U_DIV1 : entity work.signed_division
        generic map (
            WIDTH_DVD => DIV1_WIDTH,
            WIDTH_DVS => DIV1_WIDTH
        )
        port map (
            i_sys_clk   => i_sys_clk,
            i_sys_rst   => i_sys_rst,
            i_start     => w_div1_start,
            i_dividend  => w_div1_dvd,
            i_divisor   => w_div1_dvs,
            o_quotient  => w_div1_quot,
            o_remainder => open,
            o_done      => w_div1_done,
            o_busy      => open
        );

    -- ===================== 构造除法2被除数：a/xn^2 + 2*xn =====================
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_div2_dvd <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            if w_div1_done = '1' then
                r_div2_dvd <= w_div1_quot + resize(w_xn_multi2, DIV1_WIDTH);
            end if;
        end if;
    end process;

    -- ===================== 除法2：(...)/3 =====================
    U_DIV2 : entity work.signed_division
        generic map (
            WIDTH_DVD => DIV1_WIDTH,
            WIDTH_DVS => 3
        )
        port map (
            i_sys_clk   => i_sys_clk,
            i_sys_rst   => i_sys_rst,
            i_start     => w_div2_start,
            i_dividend  => r_div2_dvd,
            i_divisor   => to_signed(3, 3),
            o_quotient  => w_div2_quot,
            o_remainder => open,
            o_done      => w_div2_done,
            o_busy      => open
        );

    -- ===================== 输出锁存 =====================
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_data       <= (others => '0');
            r_data_valid <= '0';
        elsif rising_edge(i_sys_clk) then
            if (w_div2_done = '1') and
               (r_cnt_iteration = to_unsigned(ITERATIONS - 1, r_cnt_iteration'length)) then
                r_data       <= w_div2_quot(WIDTH - 1 downto 0);
                r_data_valid <= '1';
            else
                r_data_valid <= '0';
            end if;
        end if;
    end process;

    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_busy <= '0';
        elsif rising_edge(i_sys_clk) then
            if r_state /= IDLE then
                r_busy <= '1';
            else
                r_busy <= '0';
            end if;
        end if;
    end process;

end architecture rtl;
