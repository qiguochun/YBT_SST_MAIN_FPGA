--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   sqrt_core.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   无符号整数开方（逐位流水线）。
--                      默认 32bit 开方 → 16bit 商 + 17bit 余数，延迟约 Q_WIDTH 拍。
--------------------------------------------------------------------------------
--Version           :   Rev 0.0
--modifier          :
--Modify Date       :
--Modify Record     :
--------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sqrt_core is
    generic (
        D_WIDTH : positive := 32  -- 被开方数位宽（须为偶数）
    );
    port (
        -- Global Clock
        i_sys_clk : in  std_logic;
        i_sys_rst : in  std_logic;  -- 异步复位，高有效

        -- User Interface
        i_data  : in  std_logic_vector(D_WIDTH - 1 downto 0);      -- 被开方数
        i_valid : in  std_logic;                                   -- 输入有效
        o_quot  : out std_logic_vector(D_WIDTH / 2 - 1 downto 0);  -- 平方根（商）
        o_rem   : out std_logic_vector(D_WIDTH / 2 downto 0);      -- 余数
        o_valid : out std_logic                                    -- 输出有效
    );
end entity sqrt_core;

architecture rtl of sqrt_core is

    constant Q_WIDTH : positive := D_WIDTH / 2;
    constant R_WIDTH : positive := Q_WIDTH + 1;

    type t_d_arr is array (1 to Q_WIDTH) of unsigned(D_WIDTH - 1 downto 0);
    type t_q_arr is array (1 to Q_WIDTH) of unsigned(Q_WIDTH - 1 downto 0);
    type t_r_arr is array (1 to Q_WIDTH) of signed(R_WIDTH - 1 downto 0);
    type t_v_arr is array (1 to Q_WIDTH) of std_logic;

    signal r_d_t : t_d_arr := (others => (others => '0'));
    signal r_q_t : t_q_arr := (others => (others => '0'));
    signal r_r_t : t_r_arr := (others => (others => '0'));
    signal r_v_t : t_v_arr := (others => '0');

    signal r_quot  : unsigned(Q_WIDTH - 1 downto 0) := (others => '0');
    signal r_rem   : signed(R_WIDTH - 1 downto 0) := (others => '0');
    signal r_valid : std_logic := '0';

begin

    o_quot  <= std_logic_vector(r_quot);
    o_rem   <= std_logic_vector(r_rem);
    o_valid <= r_valid;

    -- ===================== 首级：取高 2 bit 试减 =====================
    process (i_sys_clk, i_sys_rst)
        variable v_concat_slv : std_logic_vector(R_WIDTH - 1 downto 0);
    begin
        if i_sys_rst = '1' then
            r_r_t(Q_WIDTH) <= (others => '0');
            r_d_t(Q_WIDTH) <= (others => '0');
            r_q_t(Q_WIDTH) <= (others => '0');
            r_v_t(Q_WIDTH) <= '0';
        elsif rising_edge(i_sys_clk) then
            if i_valid = '1' then
                -- 与原设计一致：用当前输出余数低位与输入高 2bit 拼接后减 1
                v_concat_slv := std_logic_vector(r_rem(R_WIDTH - 3 downto 0)) &
                                i_data(D_WIDTH - 1 downto D_WIDTH - 2);
                r_r_t(Q_WIDTH) <= signed(v_concat_slv) - to_signed(1, R_WIDTH);
                r_d_t(Q_WIDTH) <= unsigned(i_data);
                r_q_t(Q_WIDTH) <= (others => '0');
                r_v_t(Q_WIDTH) <= '1';
            else
                r_r_t(Q_WIDTH) <= (others => '0');
                r_d_t(Q_WIDTH) <= (others => '0');
                r_q_t(Q_WIDTH) <= (others => '0');
                r_v_t(Q_WIDTH) <= '0';
            end if;
        end if;
    end process;

    -- ===================== 中间级流水 =====================
    g_stages : for i in Q_WIDTH - 1 downto 1 generate
    begin
        process (i_sys_clk, i_sys_rst)
            variable v_concat_slv : std_logic_vector(R_WIDTH - 1 downto 0);
            variable v_term_p_slv : std_logic_vector(R_WIDTH - 1 downto 0);
            variable v_term_n_slv : std_logic_vector(R_WIDTH - 1 downto 0);
        begin
            if i_sys_rst = '1' then
                r_q_t(i) <= (others => '0');
                r_r_t(i) <= (others => '0');
                r_d_t(i) <= (others => '0');
                r_v_t(i) <= '0';
            elsif rising_edge(i_sys_clk) then
                if r_v_t(i + 1) = '1' then
                    v_concat_slv := std_logic_vector(r_r_t(i + 1)(R_WIDTH - 3 downto 0)) &
                                    std_logic_vector(r_d_t(i + 1)(2 * i - 1 downto 2 * i - 2));
                    -- {0, Q[Q_WIDTH-4:0], 1, 01}
                    v_term_p_slv := '0' &
                                    std_logic_vector(r_q_t(i + 1)(Q_WIDTH - 4 downto 0)) &
                                    "101";
                    -- {0, Q[Q_WIDTH-4:0], 0, 11}
                    v_term_n_slv := '0' &
                                    std_logic_vector(r_q_t(i + 1)(Q_WIDTH - 4 downto 0)) &
                                    "011";

                    if r_r_t(i + 1) >= 0 then
                        r_q_t(i) <= r_q_t(i + 1)(Q_WIDTH - 2 downto 0) & '1';
                        r_r_t(i) <= signed(v_concat_slv) - signed(v_term_p_slv);
                    else
                        r_q_t(i) <= r_q_t(i + 1)(Q_WIDTH - 2 downto 0) & '0';
                        r_r_t(i) <= signed(v_concat_slv) + signed(v_term_n_slv);
                    end if;
                    r_d_t(i) <= r_d_t(i + 1);
                    r_v_t(i) <= '1';
                else
                    r_q_t(i) <= (others => '0');
                    r_r_t(i) <= (others => '0');
                    r_d_t(i) <= (others => '0');
                    r_v_t(i) <= '0';
                end if;
            end if;
        end process;
    end generate;

    -- ===================== 末级输出 =====================
    process (i_sys_clk, i_sys_rst)
        variable v_corr_slv : std_logic_vector(R_WIDTH - 1 downto 0);
    begin
        if i_sys_rst = '1' then
            r_quot  <= (others => '0');
            r_rem   <= (others => '0');
            r_valid <= '0';
        elsif rising_edge(i_sys_clk) then
            if r_v_t(1) = '1' then
                if r_r_t(1) >= 0 then
                    r_quot <= r_q_t(1)(Q_WIDTH - 2 downto 0) & '1';
                    r_rem  <= r_r_t(1);
                else
                    r_quot <= r_q_t(1)(Q_WIDTH - 2 downto 0) & '0';
                    -- {0, Q[Q_WIDTH-3:0], 0, 1}
                    v_corr_slv := '0' &
                                  std_logic_vector(r_q_t(1)(Q_WIDTH - 3 downto 0)) &
                                  "01";
                    r_rem <= r_r_t(1) + signed(v_corr_slv);
                end if;
                r_valid <= '1';
            else
                r_quot  <= (others => '0');
                r_rem   <= (others => '0');
                r_valid <= '0';
            end if;
        end if;
    end process;

end architecture rtl;
