--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   mult_axb.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   流水线乘法器 A * B，延迟 3 拍。
--                      TC=0 无符号，TC=1 有符号；USE_DSP 控制综合偏好 DSP。
--------------------------------------------------------------------------------
--Version           :   Rev 0.1
--modifier          :
--Modify Date       :
--Modify Record     :
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mult_axb is
    generic (
        AWIDTH  : positive := 18;  -- 乘数 A 位宽
        BWIDTH  : positive := 18;  -- 乘数 B 位宽
        PWIDTH  : positive := 36;  -- 乘积输出位宽
        TC      : natural  := 0;   -- 0: 无符号, 1: 有符号
        PREFER_DSP : boolean := true  -- true: 偏好 DSP, false: 偏好 LUT（由约束覆盖）
    );
    port (
        -- Global Clock
        i_sys_clk : in  std_logic;

        -- User Interface
        i_a : in  std_logic_vector(AWIDTH - 1 downto 0);  -- 乘数 A
        i_b : in  std_logic_vector(BWIDTH - 1 downto 0);  -- 乘数 B
        o_p : out std_logic_vector(PWIDTH - 1 downto 0)   -- 乘积 P
    );
end entity mult_axb;

architecture rtl of mult_axb is

    -- 有符号通路寄存器
    signal r_a_s : signed(AWIDTH - 1 downto 0) := (others => '0');
    signal r_b_s : signed(BWIDTH - 1 downto 0) := (others => '0');

    -- 无符号通路寄存器（高位补 0）
    signal r_a_u : unsigned(AWIDTH downto 0) := (others => '0');
    signal r_b_u : unsigned(BWIDTH downto 0) := (others => '0');

    -- 乘积寄存器，预留 2 bit 余量后截取到 PWIDTH
    signal r_prod : signed(PWIDTH + 1 downto 0) := (others => '0');
    signal r_p_d1 : std_logic_vector(PWIDTH - 1 downto 0) := (others => '0');

    -- 综合偏好 DSP（与 PREFER_DSP 对应；勿与 generic 同名）
    attribute use_dsp : string;
    attribute use_dsp of r_prod : signal is "yes";

begin

    -- ===================== 输入打拍 =====================
    g_unsigned_in : if TC = 0 generate
        process (i_sys_clk)
        begin
            if rising_edge(i_sys_clk) then
                r_a_u <= '0' & unsigned(i_a);
                r_b_u <= '0' & unsigned(i_b);
            end if;
        end process;
    end generate;

    g_signed_in : if TC /= 0 generate
        process (i_sys_clk)
        begin
            if rising_edge(i_sys_clk) then
                r_a_s <= signed(i_a);
                r_b_s <= signed(i_b);
            end if;
        end process;
    end generate;

    -- ===================== 乘法打拍 =====================
    g_unsigned_mul : if TC = 0 generate
        process (i_sys_clk)
            variable v_prod : unsigned(AWIDTH + BWIDTH + 1 downto 0);
        begin
            if rising_edge(i_sys_clk) then
                v_prod := r_a_u * r_b_u;
                r_prod <= signed(resize(v_prod, PWIDTH + 2));
            end if;
        end process;
    end generate;

    g_signed_mul : if TC /= 0 generate
        process (i_sys_clk)
            variable v_prod : signed(AWIDTH + BWIDTH - 1 downto 0);
        begin
            if rising_edge(i_sys_clk) then
                v_prod := r_a_s * r_b_s;
                r_prod <= resize(v_prod, PWIDTH + 2);
            end if;
        end process;
    end generate;

    -- ===================== 输出打拍 =====================
    process (i_sys_clk)
    begin
        if rising_edge(i_sys_clk) then
            r_p_d1 <= std_logic_vector(r_prod(PWIDTH - 1 downto 0));
        end if;
    end process;

    o_p <= r_p_d1;

end architecture rtl;
