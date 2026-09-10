--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   vo_ma_filter.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   Vo 2048 点滑动平均，对齐旧版 dc_DABCON：
--                      i_tick(=sz_sys/CLKAD) 握手，每个 AD 周期只进窗 1 点；
--                      RAM_16_2048 OLD_DATA；有符号累加，o_dco = sum/2048。
--------------------------------------------------------------------------------
--Version           :   Rev 1.0
--modifier          :   Qigc
--Modify Date       :   2026.09.03
--Modify Record     :   初始版本
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

    signal r_dco   : std_logic_vector(15 downto 0) := (others => '0');
    signal r_done  : std_logic := '0';
    signal w_clkram : std_logic := '0';
    signal w_addr   : std_logic_vector(ADDR_W - 1 downto 0) := (others => '0');
    signal w_wdata  : std_logic_vector(15 downto 0) := (others => '0');
    signal w_rdata  : std_logic_vector(15 downto 0);

begin

    o_dco  <= r_dco;
    o_done <= r_done;

    U_RAM : entity work.RAM_16_2048
        port map (
            aclr    => i_sys_rst,
            address => w_addr,
            clock   => w_clkram,
            data    => w_wdata,
            wren    => '1',
            q       => w_rdata
        );

    -- 与 dc_DABCON Main 相同：START 高采一次，算完等 START 低再进入下一拍
    process (i_sys_clk, i_sys_rst)
        variable v_index : integer range 0 to DEPTH - 1 := 0;
        variable v_step  : integer range 0 to 15 := 0;
        variable v_add   : integer := 0;
        variable v_dco   : integer := 0;
    begin
        if i_sys_rst = '1' then
            v_index  := 0;
            v_step   := 0;
            v_add    := 0;
            v_dco    := 0;
            w_clkram <= '0';
            w_addr   <= (others => '0');
            w_wdata  <= (others => '0');
            r_dco    <= (others => '0');
            r_done   <= '0';
        elsif rising_edge(i_sys_clk) then
            r_done <= '0';
            case v_step is
                when 0 =>
                    if i_tick = '1' then
                        w_wdata <= i_vo;
                        w_addr  <= std_logic_vector(to_unsigned(v_index, ADDR_W));
                        v_step  := 1;
                    end if;

                when 1 =>
                    v_step := 2;

                when 2 =>
                    w_clkram <= '1';
                    v_step   := 3;

                when 3 =>
                    v_step := 4;

                when 4 =>
                    w_clkram <= '0';
                    v_step   := 5;

                when 5 =>
                    v_add := v_add - to_integer(signed(w_rdata)) + to_integer(signed(w_wdata));
                    v_dco := v_add / DEPTH;
                    r_dco <= std_logic_vector(to_signed(v_dco, 16));
                    r_done <= '1';
                    v_step := 6;

                when 6 =>
                    v_step := 7;
                when 7 =>
                    v_step := 8;
                when 8 =>
                    v_step := 9;
                when 9 =>
                    v_step := 10;

                when 10 =>
                    if v_index = DEPTH - 1 then
                        v_index := 0;
                    else
                        v_index := v_index + 1;
                    end if;
                    v_step := 11;

                when 11 =>
                    if i_tick = '0' then
                        v_step := 0;
                    end if;

                when others =>
                    null;
            end case;
        end if;
    end process;

end architecture rtl;
