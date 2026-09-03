--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   vo_ma_filter.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   Vo 2048 点滑动平均（推断 BRAM）。
--                      每 i_tick：读旧样点、写新样点、sum += new - old，
--                      o_dco = sum / 2048。同一进程内先读后写，等价 OLD_DATA。
--------------------------------------------------------------------------------
--Version           :   Rev 0.1
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vo_ma_filter is
    generic (
        DEPTH  : positive := 2048;
        ADDR_W : positive := 11
    );
    port (
        -- Global Clock
        i_sys_clk : in  std_logic;
        i_sys_rst : in  std_logic;

        -- User Interface
        i_tick : in  std_logic;
        i_vo   : in  std_logic_vector(15 downto 0);
        o_dco  : out std_logic_vector(15 downto 0);
        o_done : out std_logic
    );
end entity vo_ma_filter;

architecture rtl of vo_ma_filter is

    constant SHIFT_DIV : natural := 11;  -- /2048

    type t_ram is array (0 to DEPTH - 1) of std_logic_vector(15 downto 0);
    signal r_ram : t_ram := (others => (others => '0'));

    signal r_addr : unsigned(ADDR_W - 1 downto 0) := (others => '0');
    signal r_sum  : signed(31 downto 0) := (others => '0');
    signal r_dco  : unsigned(15 downto 0) := (others => '0');
    signal r_done : std_logic := '0';

    -- 帮助综合推断 BRAM
    attribute ramstyle : string;
    attribute ramstyle of r_ram : signal is "M9K";

begin

    o_dco  <= std_logic_vector(r_dco);
    o_done <= r_done;

    process (i_sys_clk, i_sys_rst)
        variable v_addr : integer;
        variable v_old  : signed(31 downto 0);
        variable v_new  : signed(31 downto 0);
        variable v_sum  : signed(31 downto 0);
    begin
        if i_sys_rst = '1' then
            r_addr <= (others => '0');
            r_sum  <= (others => '0');
            r_dco  <= (others => '0');
            r_done <= '0';
        elsif rising_edge(i_sys_clk) then
            r_done <= '0';
            if i_tick = '1' then
                v_addr := to_integer(r_addr);
                -- 先读后写：得到窗内将被替换的旧样点
                v_old := resize(signed(r_ram(v_addr)), 32);
                v_new := resize(signed(i_vo), 32);
                r_ram(v_addr) <= i_vo;

                v_sum := r_sum - v_old + v_new;
                if v_sum < 0 then
                    v_sum := (others => '0');
                end if;
                r_sum  <= v_sum;
                r_dco  <= unsigned(v_sum(SHIFT_DIV + 15 downto SHIFT_DIV));
                r_addr <= r_addr + 1;
                r_done <= '1';
            end if;
        end if;
    end process;

end architecture rtl;
