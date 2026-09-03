--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   filter_core.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   多通道 ADC 采样低通滤波聚合（电压/电流）。
--------------------------------------------------------------------------------
--Version           :   Rev 0.1
--modifier          :
--Modify Date       :
--Modify Record     :
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity filter_core is
    generic (
        CLK_FREQ : natural := 100  -- 保留原接口；本层未直接使用
    );
    port (
        -- Global Clock
        i_sys_clk                : in  std_logic;
        i_adc_sample_sequence_done : in  std_logic;

        -- User Interface : inputs
        i_llc_bus_voltage_a      : in  signed(31 downto 0);
        i_llc_bus_voltage_b      : in  signed(31 downto 0);
        i_bus_total_voltage      : in  signed(31 downto 0);
        i_bus_total_voltage_pre  : in  signed(31 downto 0);
        i_bus_voltage_a32        : in  signed(31 downto 0);
        i_bus_voltage_b32        : in  signed(31 downto 0);
        i_llc_bus_current_a32    : in  signed(31 downto 0);
        i_llc_bus_current_b32    : in  signed(31 downto 0);
        i_bus_total_current_a32  : in  signed(31 downto 0);
        i_bus_total_current_b32  : in  signed(31 downto 0);

        -- User Interface : outputs
        o_llc_bus_vol_filter_a   : out signed(31 downto 0);
        o_llc_bus_vol_filter_b   : out signed(31 downto 0);
        o_bus_total_vol_filter   : out signed(31 downto 0);
        o_bus_total_vol_filter_pre : out signed(31 downto 0);
        o_bus_vol_filter_a       : out signed(31 downto 0);
        o_bus_vol_filter_b       : out signed(31 downto 0);
        o_llc_bus_cur_filter_a   : out signed(31 downto 0);
        o_llc_bus_cur_filter_b   : out signed(31 downto 0);
        o_bus_total_cur_filter_a : out signed(31 downto 0);
        o_bus_total_cur_filter_b : out signed(31 downto 0)
    );
end entity filter_core;

architecture rtl of filter_core is

    -- 电压通道：WC=3140；电流：WC=6280；母线总电流：WC=30；FS=53418
    constant C_FS_ADC : integer := 53418;
    constant C_WC_VOL : integer := 3140;
    constant C_WC_CUR : integer := 6280;
    constant C_WC_ITOT : integer := 30;

begin

    -- ===================== LLC 母线电压 A/B =====================
    u_lpf_llc_vol_a : entity work.lpf_tustin
        generic map (
            TRI_MODE => 0,
            WC       => C_WC_VOL,
            FS       => C_FS_ADC
        )
        port map (
            i_sys_clk      => i_sys_clk,
            i_input        => i_llc_bus_voltage_a,
            i_sample_pulse => i_adc_sample_sequence_done,
            o_output       => o_llc_bus_vol_filter_a
        );

    u_lpf_llc_vol_b : entity work.lpf_tustin
        generic map (
            TRI_MODE => 0,
            WC       => C_WC_VOL,
            FS       => C_FS_ADC
        )
        port map (
            i_sys_clk      => i_sys_clk,
            i_input        => i_llc_bus_voltage_b,
            i_sample_pulse => i_adc_sample_sequence_done,
            o_output       => o_llc_bus_vol_filter_b
        );

    -- ===================== 母线总压 / 预估值 =====================
    u_lpf_bus_tot_vol : entity work.lpf_tustin
        generic map (
            TRI_MODE => 0,
            WC       => C_WC_VOL,
            FS       => C_FS_ADC
        )
        port map (
            i_sys_clk      => i_sys_clk,
            i_input        => i_bus_total_voltage,
            i_sample_pulse => i_adc_sample_sequence_done,
            o_output       => o_bus_total_vol_filter
        );

    u_lpf_bus_tot_vol_pre : entity work.lpf_tustin
        generic map (
            TRI_MODE => 0,
            WC       => C_WC_VOL,
            FS       => C_FS_ADC
        )
        port map (
            i_sys_clk      => i_sys_clk,
            i_input        => i_bus_total_voltage_pre,
            i_sample_pulse => i_adc_sample_sequence_done,
            o_output       => o_bus_total_vol_filter_pre
        );

    -- ===================== 核心母线电压 A/B =====================
    u_lpf_bus_vol_a : entity work.lpf_tustin
        generic map (
            TRI_MODE => 0,
            WC       => C_WC_VOL,
            FS       => C_FS_ADC
        )
        port map (
            i_sys_clk      => i_sys_clk,
            i_input        => i_bus_voltage_a32,
            i_sample_pulse => i_adc_sample_sequence_done,
            o_output       => o_bus_vol_filter_a
        );

    u_lpf_bus_vol_b : entity work.lpf_tustin
        generic map (
            TRI_MODE => 0,
            WC       => C_WC_VOL,
            FS       => C_FS_ADC
        )
        port map (
            i_sys_clk      => i_sys_clk,
            i_input        => i_bus_voltage_b32,
            i_sample_pulse => i_adc_sample_sequence_done,
            o_output       => o_bus_vol_filter_b
        );

    -- ===================== LLC 母线电流 A/B =====================
    u_lpf_llc_cur_a : entity work.lpf_tustin
        generic map (
            TRI_MODE => 0,
            WC       => C_WC_CUR,
            FS       => C_FS_ADC
        )
        port map (
            i_sys_clk      => i_sys_clk,
            i_input        => i_llc_bus_current_a32,
            i_sample_pulse => i_adc_sample_sequence_done,
            o_output       => o_llc_bus_cur_filter_a
        );

    u_lpf_llc_cur_b : entity work.lpf_tustin
        generic map (
            TRI_MODE => 0,
            WC       => C_WC_CUR,
            FS       => C_FS_ADC
        )
        port map (
            i_sys_clk      => i_sys_clk,
            i_input        => i_llc_bus_current_b32,
            i_sample_pulse => i_adc_sample_sequence_done,
            o_output       => o_llc_bus_cur_filter_b
        );

    -- ===================== 母线总电流 A/B（更低截止） =====================
    u_lpf_bus_tot_cur_a : entity work.lpf_tustin
        generic map (
            TRI_MODE => 0,
            WC       => C_WC_ITOT,
            FS       => C_FS_ADC
        )
        port map (
            i_sys_clk      => i_sys_clk,
            i_input        => i_bus_total_current_a32,
            i_sample_pulse => i_adc_sample_sequence_done,
            o_output       => o_bus_total_cur_filter_a
        );

    u_lpf_bus_tot_cur_b : entity work.lpf_tustin
        generic map (
            TRI_MODE => 0,
            WC       => C_WC_ITOT,
            FS       => C_FS_ADC
        )
        port map (
            i_sys_clk      => i_sys_clk,
            i_input        => i_bus_total_current_b32,
            i_sample_pulse => i_adc_sample_sequence_done,
            o_output       => o_bus_total_cur_filter_b
        );

end architecture rtl;
