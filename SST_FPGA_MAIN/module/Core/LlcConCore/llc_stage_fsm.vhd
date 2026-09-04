--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   llc_stage_fsm.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   LLC 缓启阶段状态机。
--                      i_enable 脉冲锁存后开始 STAGE0→3；
--                      i_restart 清使能并回 STAGE0 初始。
--                      完成条件满足 → 下一阶段；超时未满足 → 超时错误+FAULT。
--------------------------------------------------------------------------------
--Version           :   Rev 0.8
--modifier          :   Qigc
--Modify Date       :   2026.09.04
--Modify Record     :   使能恢复为脉冲锁存
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity llc_stage_fsm is
    generic (
        T_STAGE0_MS   : natural := 1000;
        T_STAGE1_MS   : natural := 1000;
        T_STAGE2_MS   : natural := 1000;
        DUTY_DONE     : natural := 1024;
        F_STAGE1_DONE : natural := 6000;
        V_STAGE2_DONE : natural := 7200
    );
    port (
        i_sys_clk : in  std_logic;
        i_sys_rst : in  std_logic;

        i_delay_1ms : in  std_logic;
        i_enable    : in  std_logic;  -- 启动脉冲：锁存后开始缓启
        i_restart   : in  std_logic;  -- 同步重启：清使能回 STAGE0
        i_duty      : in  unsigned(15 downto 0);
        i_freq      : in  unsigned(15 downto 0);
        i_vo        : in  unsigned(15 downto 0);

        o_run         : out std_logic;
        o_state       : out unsigned(2 downto 0);
        o_done        : out std_logic;
        o_phase_done  : out std_logic_vector(2 downto 0);
        o_timeout_err : out std_logic_vector(2 downto 0)
    );
end entity llc_stage_fsm;

architecture rtl of llc_stage_fsm is

    type t_state is (STAGE0, STAGE1, STAGE2, STAGE3, FAULT);
    signal r_state       : t_state := STAGE0;
    signal r_run         : std_logic := '0';
    signal r_stage_ms    : unsigned(15 downto 0) := (others => '0');
    signal r_done        : std_logic := '0';
    signal r_phase_done  : std_logic_vector(2 downto 0) := (others => '0');
    signal r_timeout_err : std_logic_vector(2 downto 0) := (others => '0');

begin

    o_run         <= r_run;
    o_done        <= r_done;
    o_phase_done  <= r_phase_done;
    o_timeout_err <= r_timeout_err;

    process (r_state)
    begin
        case r_state is
            when STAGE0 => o_state <= to_unsigned(0, 3);
            when STAGE1 => o_state <= to_unsigned(1, 3);
            when STAGE2 => o_state <= to_unsigned(2, 3);
            when STAGE3 => o_state <= to_unsigned(3, 3);
            when FAULT  => o_state <= to_unsigned(4, 3);
            when others => o_state <= to_unsigned(0, 3);
        end case;
    end process;

    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_state       <= STAGE0;
            r_run         <= '0';
            r_stage_ms    <= (others => '0');
            r_done        <= '0';
            r_phase_done  <= (others => '0');
            r_timeout_err <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            if i_restart = '1' then
                r_state       <= STAGE0;
                r_run         <= '0';
                r_stage_ms    <= (others => '0');
                r_done        <= '0';
                r_phase_done  <= (others => '0');
                r_timeout_err <= (others => '0');

            elsif (i_enable = '1') and (r_run = '0') and (r_state = STAGE0) then
                -- 启动脉冲：锁存运行
                r_run      <= '1';
                r_stage_ms <= (others => '0');

            elsif (r_run = '1') and (i_delay_1ms = '1') then
                case r_state is
                    when STAGE0 =>
                        if i_duty >= DUTY_DONE then
                            r_state         <= STAGE1;
                            r_stage_ms      <= (others => '0');
                            r_phase_done(0) <= '1';
                        elsif r_stage_ms >= T_STAGE0_MS - 1 then
                            r_timeout_err(0) <= '1';
                            r_state          <= FAULT;
                            r_run            <= '0';
                        else
                            r_stage_ms <= r_stage_ms + 1;
                        end if;

                    when STAGE1 =>
                        if i_freq <= F_STAGE1_DONE then
                            r_state         <= STAGE2;
                            r_stage_ms      <= (others => '0');
                            r_phase_done(1) <= '1';
                        elsif r_stage_ms >= T_STAGE1_MS - 1 then
                            r_timeout_err(1) <= '1';
                            r_state          <= FAULT;
                            r_run            <= '0';
                        else
                            r_stage_ms <= r_stage_ms + 1;
                        end if;

                    when STAGE2 =>
                        if i_vo >= V_STAGE2_DONE then
                            r_state         <= STAGE3;
                            r_stage_ms      <= (others => '0');
                            r_phase_done(2) <= '1';
                            r_done          <= '1';
                        elsif r_stage_ms >= T_STAGE2_MS - 1 then
                            r_timeout_err(2) <= '1';
                            r_state          <= FAULT;
                            r_run            <= '0';
                        else
                            r_stage_ms <= r_stage_ms + 1;
                        end if;

                    when STAGE3 =>
                        r_done       <= '1';
                        r_phase_done <= (others => '1');

                    when FAULT =>
                        null;  -- 保持，等 i_restart

                    when others =>
                        r_state       <= STAGE0;
                        r_run         <= '0';
                        r_stage_ms    <= (others => '0');
                        r_done        <= '0';
                        r_phase_done  <= (others => '0');
                        r_timeout_err <= (others => '0');
                end case;
            end if;
        end if;
    end process;

end architecture rtl;
