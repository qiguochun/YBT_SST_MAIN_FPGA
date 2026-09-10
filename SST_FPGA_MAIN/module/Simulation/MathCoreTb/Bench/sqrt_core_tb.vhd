--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   sqrt_core_tb.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   sqrt_core TB。
--------------------------------------------------------------------------------
--Version           :   Rev 0.1
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity sqrt_core_tb is
end entity sqrt_core_tb;

architecture sim of sqrt_core_tb is

    constant D_WIDTH    : positive := 32;
    constant Q_WIDTH    : positive := D_WIDTH / 2;
    constant CLK_PERIOD : time     := 10 ns;
    constant PIPE_LAT   : positive := Q_WIDTH + 1;

    signal i_sys_clk : std_logic := '0';
    signal i_sys_rst : std_logic := '1';
    signal i_data    : std_logic_vector(D_WIDTH - 1 downto 0) := (others => '0');
    signal i_valid   : std_logic := '0';
    signal o_quot    : std_logic_vector(Q_WIDTH - 1 downto 0);
    signal o_rem     : std_logic_vector(Q_WIDTH downto 0);
    signal o_valid   : std_logic;

begin

    U_DUT : entity work.sqrt_core
        generic map (
            D_WIDTH => D_WIDTH
        )
        port map (
            i_sys_clk => i_sys_clk,
            i_sys_rst => i_sys_rst,
            i_data    => i_data,
            i_valid   => i_valid,
            o_quot    => o_quot,
            o_rem     => o_rem,
            o_valid   => o_valid
        );

    i_sys_clk <= not i_sys_clk after CLK_PERIOD / 2;

    stimulus : process
        variable v_error_count : natural := 0;
        variable v_timeout     : boolean;

        procedure run_one (
            constant din  : in natural;
            constant expq : in natural
        ) is
        begin
            i_data  <= std_logic_vector(to_unsigned(din, D_WIDTH));
            i_valid <= '1';
            wait until rising_edge(i_sys_clk);
            i_valid <= '0';

            v_timeout := true;
            for i in 1 to PIPE_LAT + 5 loop
                wait until rising_edge(i_sys_clk);
                if o_valid = '1' then
                    v_timeout := false;
                    exit;
                end if;
            end loop;

            if v_timeout then
                report "TIMEOUT D=" & integer'image(din) severity error;
                v_error_count := v_error_count + 1;
            elsif to_integer(unsigned(o_quot)) /= expq then
                report "FAIL D=" & integer'image(din) &
                       " expectQ=" & integer'image(expq) &
                       " gotQ=" & integer'image(to_integer(unsigned(o_quot))) &
                       " R=" & integer'image(to_integer(signed(o_rem)))
                    severity error;
                v_error_count := v_error_count + 1;
            else
                report "PASS sqrt(" & integer'image(din) & ")=" &
                       integer'image(to_integer(unsigned(o_quot))) &
                       " R=" & integer'image(to_integer(signed(o_rem)))
                    severity note;
            end if;

            wait for 5 * CLK_PERIOD;
        end procedure;
    begin
        i_sys_rst <= '1';
        i_valid   <= '0';
        i_data    <= (others => '0');
        wait for 2 * CLK_PERIOD;
        i_sys_rst <= '0';
        wait for 2 * CLK_PERIOD;

        report "========== SqrtCore TB ==========" severity note;

        run_one(0, 0);
        run_one(1, 1);
        run_one(4, 2);
        run_one(9, 3);
        run_one(16, 4);
        run_one(25, 5);
        run_one(100, 10);
        run_one(144, 12);
        run_one(256, 16);
        run_one(1024, 32);
        run_one(10000, 100);

        report "========== Summary ==========" severity note;
        if v_error_count = 0 then
            report "ALL PASS" severity note;
        else
            report "Errors=" & integer'image(v_error_count) severity error;
        end if;

        wait for 10 * CLK_PERIOD;
        stop(0);
        wait;
    end process;

end architecture sim;
