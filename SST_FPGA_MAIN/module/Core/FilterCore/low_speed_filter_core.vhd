--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   low_speed_filter_core.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   低速（约 1Hz 采样）电池电压 Tustin 低通。
--------------------------------------------------------------------------------
--Version           :   Rev 0.0
--modifier          :
--Modify Date       :
--Modify Record     :
--------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity low_speed_filter_core is
    generic (
        CLK_FREQ : natural := 100  -- 保留原接口；本层未直接使用
    );
    port (
        -- Global Clock
        i_sys_clk          : in  std_logic;
        i_sys_clk_1s_pulse : in  std_logic;

        -- User Interface
        i_bat_voltage         : in  signed(31 downto 0);
        i_bat_average_voltage : in  signed(31 downto 0);
        o_bat_voltage         : out signed(31 downto 0);
        o_bat_average_voltage : out signed(31 downto 0)
    );
end entity low_speed_filter_core;

architecture rtl of low_speed_filter_core is

    -- WC=1, FS=1：约 0.16Hz 截止 @ 1Hz 采样（与原注释一致）
    constant C_WC_BAT : integer := 1;
    constant C_FS_1HZ : integer := 1;

begin

    u_lpf_bat_vol : entity work.lpf_tustin
        generic map (
            TRI_MODE => 0,
            WC       => C_WC_BAT,
            FS       => C_FS_1HZ
        )
        port map (
            i_sys_clk      => i_sys_clk,
            i_input        => i_bat_voltage,
            i_sample_pulse => i_sys_clk_1s_pulse,
            o_output       => o_bat_voltage
        );

    u_lpf_bat_avg_vol : entity work.lpf_tustin
        generic map (
            TRI_MODE => 0,
            WC       => C_WC_BAT,
            FS       => C_FS_1HZ
        )
        port map (
            i_sys_clk      => i_sys_clk,
            i_input        => i_bat_average_voltage,
            i_sample_pulse => i_sys_clk_1s_pulse,
            o_output       => o_bat_average_voltage
        );

end architecture rtl;
