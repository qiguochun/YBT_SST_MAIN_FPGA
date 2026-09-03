--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   llc_stage_fsm.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   LLC 三段缓启阶段状态机。
--                      STAGE0→STAGE1→STAGE2→STAGE3；timer 在 i_tick 递增。
--------------------------------------------------------------------------------
--Version           :   Rev 0.1
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity llc_stage_fsm is
    generic (
        T_STAGE0_MAX : natural := 5120;
        T_STAGE1_MAX : natural := 10240;
        V_STAGE2_TH  : natural := 7200;
        V_DONE_TH    : natural := 7990
    );
    port (
        -- Global Clock
        i_sys_clk : in  std_logic;
        i_sys_rst : in  std_logic;

        -- User Interface
        i_tick     : in  std_logic;
        i_vo       : in  unsigned(15 downto 0);
        o_state    : out unsigned(2 downto 0);
        o_timer    : out unsigned(15 downto 0);
        o_done     : out std_logic;
        o_enter_s2 : out std_logic
    );
end entity llc_stage_fsm;

architecture rtl of llc_stage_fsm is

    type t_state is (STAGE0, STAGE1, STAGE2, STAGE3);
    signal r_state    : t_state := STAGE0;
    signal r_timer    : unsigned(15 downto 0) := (others => '0');
    signal r_done     : std_logic := '0';
    signal r_enter_s2 : std_logic := '0';

begin

    o_timer    <= r_timer;
    o_done     <= r_done;
    o_enter_s2 <= r_enter_s2;

    process (r_state)
    begin
        case r_state is
            when STAGE0 => o_state <= to_unsigned(0, 3);
            when STAGE1 => o_state <= to_unsigned(1, 3);
            when STAGE2 => o_state <= to_unsigned(2, 3);
            when STAGE3 => o_state <= to_unsigned(3, 3);
            when others => o_state <= to_unsigned(0, 3);
        end case;
    end process;

    process (i_sys_clk, i_sys_rst)
        variable v_t_stage1 : integer;
    begin
        if i_sys_rst = '1' then
            r_state    <= STAGE0;
            r_timer    <= (others => '0');
            r_done     <= '0';
            r_enter_s2 <= '0';
        elsif rising_edge(i_sys_clk) then
            r_enter_s2 <= '0';

            if i_tick = '1' then
                if r_state /= STAGE3 then
                    r_timer <= r_timer + 1;
                end if;

                case r_state is
                    when STAGE0 =>
                        if r_timer >= T_STAGE0_MAX - 1 then
                            r_state <= STAGE1;
                        end if;

                    when STAGE1 =>
                        v_t_stage1 := to_integer(r_timer) - T_STAGE0_MAX;
                        if (i_vo >= V_STAGE2_TH) or (v_t_stage1 >= T_STAGE1_MAX - 1) then
                            r_state    <= STAGE2;
                            r_enter_s2 <= '1';
                        end if;

                    when STAGE2 =>
                        if i_vo >= V_DONE_TH then
                            r_state <= STAGE3;
                            r_done  <= '1';
                        end if;

                    when STAGE3 =>
                        r_done <= '1';

                    when others =>
                        r_state <= STAGE0;
                end case;
            end if;
        end if;
    end process;

end architecture rtl;
