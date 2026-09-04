--------------------------------------------------------------------------------
--Project Name      :   MAIN_CONTROL_FPGA
--Moudle Name       :   sz_ad_param_sel.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   sz_ad_tx 前置参数选择 + 工程唯一调试串口（A_R2/A_T2）。
--                      SIM_MODE=false：物理参数直连输出，接 sz_ad_tx；串口关闭。
--                      SIM_MODE=true （默认）：
--                        RX：解析上位机命令，写入参数寄存器并驱动可注入输出；
--                        TX：uart_debug_core 约 10ms 一帧经 A_T2 回传当前参数
--                            （VOFA+ SstmcFrame，16 路×32bit）。
--                      OPra 位域拆分（SIM，与 lg_kzzsc/sz_ad_tx 一致）：
--                        [15:0]  / D0~D15  ：物理旁路/清零
--                        [41:29] / D29~D41 ：物理旁路/清零
--                        [51:47]           ：H命令，SIM 固定 "10100"(闭锁)
--                        [46:42]           ：D命令，r_LLC_en=1->"11010"；=0->"10100"
--                        [28:16]           ：串口频率 -> r_P0ra
--                      光纤打包：llcduty & OPra[51:42] & PWM1 & PWM2 & OPra[41:0]
--                        → 模块侧 zz[53:44]=OPra[51:42]，故 D 命令落在 zz[48:44]
--                      CLKIN / szres：仅本模块自用，不旁路输出；
--                      顶层须将同一 CLKIN、szres 直接接到 sz_ad_tx。
--                      帧格式：AA 55 | addr | N | data×N | 55 AA
--                      地址映射（16bit 字，起始地址 + 字索引）：
--                        0x01 : LLC使能  bit0：1=使能(OPra[46:42]=11010)，0=失能(=10100)
--                        0x02 : 频率[15:0] -> r_P0ra（仅回传 CH2；输出改接 i_llc_period）
--                        0x03 : 占空比[15:0] -> r_llcduty（仅回传 CH3；输出改接 i_llc_duty）
--                        0x04 : SR使能   bit0：1=使能，0=失能（仅寄存器/回传）
--                        0x05 : LLC_EN 输出 bit0：1=使能，0=失能（独立端口）
--                      PWM1/PWM2：始终物理旁路。
--                      SIM 输出：o_OPra[28:16]<=i_llc_period[12:0]，o_llcduty<=i_llc_duty
--                      TX 监控通道（uint32，小端）：
--                        CH0=保留0
--                        CH1=LLC_en(0x01), CH2=freq(P0ra), CH3=llcduty(0x03),
--                        CH4=SR_en(0x04), CH5~7=zcdtout 分片, CH8=LLC_EN(0x05),
--                        CH9 =llc o_duty_cmd, CH10=llc o_period(f_sw),
--                        CH11=llc o_dco, CH12=llc 状态打包,
--                        CH13~15=0（预留）
--                        CH12 bit：[2:0]=o_state, [3]=o_done, [4]=o_run_en
--                      r_zcdtout[69:0] =
--                        llcduty[15:0] & OPra[51:42] & PWM1 & PWM2 & OPra[41:0]
--------------------------------------------------------------------------------
--Version           :   Rev 1.2
--modifier          :   Qigc
--Modify Date       :   2026.09.04
--Modify Record     :   CH9~12 回传 llc_con_core 输出（duty/period/dco/state）
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sz_ad_param_sel is
    generic (
        -- true=串口注入参数+10ms回传；false=物理直连（无串口）
        SIM_MODE : boolean  := true;
        CLK_FREQ : positive := 30_000_000;
        UART_BPS : positive := 115_200
    );
    port (
        -- 本模块自用（SIM 模式 UART/寄存器）；顶层另直连至 sz_ad_tx，勿经本模块旁路
        szres   : in  std_logic;
        CLKIN   : in  std_logic;  -- 30 MHz

        -- 物理侧输入；时序类旁路至 sz_ad_tx，参数类经选择后输出
        clcgz   : in  std_logic;
        zc_r    : in  std_logic;
        clktx   : in  std_logic;
        OPra    : in  std_logic_vector(51 downto 0);
        PWM1    : in  std_logic;
        PWM2    : in  std_logic;
        llcduty : in  std_logic_vector(15 downto 0);

        -- 仿真模式串口（正常模式 RX 可悬空，TX 输出恒高）
        i_uart_rxd : in  std_logic := '1';
        o_uart_txd : out std_logic;

        -- 输出至 sz_ad_tx（时钟/复位由顶层直连，不从此处引出）
        o_clcgz   : out std_logic;
        o_zc_r    : out std_logic;
        o_clktx   : out std_logic;
        o_OPra    : out std_logic_vector(51 downto 0);
        o_PWM1    : out std_logic;
        o_PWM2    : out std_logic;
        o_llcduty : out std_logic_vector(15 downto 0);

        -- 串口地址 0x05：bit0=1 使能，=0 失能（顶层可暂不接）
        LLC_EN    : out std_logic;

        -- llc_con_core 监测输入（挂串口 CH9~12；未接时默认 0）
        i_llc_duty   : in std_logic_vector(15 downto 0) := (others => '0');
        i_llc_period : in std_logic_vector(15 downto 0) := (others => '0');
        i_llc_dco    : in std_logic_vector(15 downto 0) := (others => '0');
        i_llc_state  : in std_logic_vector(2 downto 0)  := (others => '0');
        i_llc_done   : in std_logic := '0';
        i_llc_run_en : in std_logic := '0'
    );
end entity sz_ad_param_sel;

architecture rtl of sz_ad_param_sel is

    signal w_OPra_sel    : std_logic_vector(51 downto 0);
    signal w_llcduty_sel : std_logic_vector(15 downto 0);
    signal w_uart_txd    : std_logic;
    signal w_LLC_EN      : std_logic := '0';

begin

    -- 非时钟时序信号旁路（CLKIN/szres 不经此路径）
    o_clcgz <= clcgz;
    o_zc_r  <= zc_r;
    o_clktx <= clktx;
    o_PWM1  <= '0';  -- 物理旁路
    o_PWM2  <= '0';  -- 物理旁路

    o_OPra     <= w_OPra_sel;
    o_llcduty  <= w_llcduty_sel;
    o_uart_txd <= w_uart_txd;
    LLC_EN     <= w_LLC_EN;

    ------------------------------------------------------------------
    -- 正常模式：参数直连，TX 空闲，LLC_EN 固定失能
    ------------------------------------------------------------------
    g_normal : if not SIM_MODE generate
    begin
        w_OPra_sel    <= OPra;
        w_llcduty_sel <= llcduty;
        w_uart_txd    <= '1';
        w_LLC_EN      <= '0';
    end generate g_normal;

    ------------------------------------------------------------------
    -- 仿真模式：串口解析写寄存器 + TX 回传当前参数
    ------------------------------------------------------------------
    g_sim : if SIM_MODE generate

        constant C_PARAM_COUNT : positive := 16;
        constant C_DATA_WIDTH  : positive := 32;

        signal w_mon_buf    : std_logic_vector(C_PARAM_COUNT * C_DATA_WIDTH - 1 downto 0);
        signal w_start_addr : std_logic_vector(7 downto 0);
        signal w_data_wr_en : std_logic;
        signal w_data_idx   : std_logic_vector(7 downto 0);
        signal w_data_word  : std_logic_vector(15 downto 0);

        signal r_LLC_en     : std_logic := '0';                          -- 地址0x01 OPra D命令
        signal r_P0ra       : std_logic_vector(15 downto 0) := (others => '0');  -- 地址0x02 频率
        signal r_llcduty    : std_logic_vector(15 downto 0) := (others => '0');  -- 地址0x03 占空比
        signal r_SR_en      : std_logic := '0';                          -- 地址0x04
        signal r_llc_en_out : std_logic := '0';                          -- 地址0x05 -> LLC_EN 端口
        -- 与 sz_ad_tx.sig_zcdtout 同构：70bit 发送数据镜像
        signal r_zcdtout : std_logic_vector(69 downto 0) := (others => '0');

    begin

        w_LLC_EN <= r_llc_en_out;
        -- 工程唯一串口：RX 解析上位机命令，TX 约 10ms 回传当前参数
        U_UART_DEBUG : entity work.uart_debug_core
            generic map (
                CLK_FREQ    => CLK_FREQ,
                UART_BPS    => UART_BPS,
                PARAM_COUNT => C_PARAM_COUNT,
                DATA_WIDTH  => C_DATA_WIDTH
            )
            port map (
                i_sys_clk        => CLKIN,
                i_sys_rst        => szres,
                i_mon_buf        => w_mon_buf,
                o_uart_txd       => w_uart_txd,
                i_uart_rxd       => i_uart_rxd,
                o_cmd_frame_vld  => open,
                o_cmd_frame_err  => open,
                o_cmd_start_addr => w_start_addr,
                o_cmd_length     => open,
                o_cmd_data_wr_en => w_data_wr_en,
                o_cmd_data_idx   => w_data_idx,
                o_cmd_data_word  => w_data_word,
                o_uart_rx_vld    => open
            );

        -- 70bit 发送帧镜像（同 sz_ad_tx 打包；用实际选出的 duty/OPra）
        r_zcdtout <= w_llcduty_sel(15 downto 0)
                   & w_OPra_sel(51 downto 42)
                   & '0' & '0'
                   & w_OPra_sel(41 downto 0);

        -- 监测缓冲：
        --   CH1~4 命令回显；CH5~7 = I5/I6/I7；CH8 = LLC_EN
        --   CH9~12 = llc_con_core 输出
        process (r_LLC_en, r_P0ra, r_llcduty, r_SR_en, r_llc_en_out, r_zcdtout,
                 i_llc_duty, i_llc_period, i_llc_dco,
                 i_llc_state, i_llc_done, i_llc_run_en)
        begin
            w_mon_buf <= (others => '0');
            w_mon_buf(63 downto 32)   <= (31 downto 1 => '0') & r_LLC_en;   -- CH1
            w_mon_buf(95 downto 64)   <= x"0000" & r_P0ra;                  -- CH2 频率
            w_mon_buf(127 downto 96)  <= x"0000" & r_llcduty;               -- CH3 占空比
            w_mon_buf(159 downto 128) <= (31 downto 1 => '0') & r_SR_en;    -- CH4
            -- I5 / I6 / I7（与 zzdtin 分片方式一致）
            w_mon_buf(191 downto 160) <= r_zcdtout(31 downto 0);            -- CH5/I5
            w_mon_buf(223 downto 192) <= r_zcdtout(63 downto 32);           -- CH6/I6
            w_mon_buf(255 downto 224) <= (31 downto 6 => '0')
                                       & r_zcdtout(69 downto 64);           -- CH7/I7 高位补0
            w_mon_buf(287 downto 256) <= (31 downto 1 => '0') & r_llc_en_out;  -- CH8 LLC_EN
            -- llc_con_core 观测（CH9~12）
            w_mon_buf(319 downto 288) <= x"0000" & i_llc_duty;              -- CH9  duty
            w_mon_buf(351 downto 320) <= x"0000" & i_llc_period;            -- CH10 period
            w_mon_buf(383 downto 352) <= x"0000" & i_llc_dco;               -- CH11 dco
            w_mon_buf(415 downto 384) <= (31 downto 5 => '0')
                                       & i_llc_run_en                       -- [4]
                                       & i_llc_done                         -- [3]
                                       & i_llc_state;                       -- [2:0]
        end process;

        ------------------------------------------------------------------
        -- 命令码解析：addr = start_addr + data_idx
        --   0x01 LLC使能  bit0（OPra D命令）
        --   0x02 频率     -> r_P0ra
        --   0x03 占空比   -> r_llcduty
        --   0x04 SR使能   bit0
        --   0x05 LLC_EN   bit0 -> 端口 LLC_EN
        ------------------------------------------------------------------
        process (CLKIN, szres)
            variable v_addr : integer range 0 to 255;
        begin
            if szres = '1' then
                r_LLC_en      <= '0';
                r_P0ra        <= (others => '0');
                r_llcduty     <= (others => '0');
                r_SR_en       <= '0';
                r_llc_en_out  <= '0';
            elsif rising_edge(CLKIN) then
                if w_data_wr_en = '1' then
                    v_addr := to_integer(unsigned(w_start_addr) + unsigned(w_data_idx));
                    case v_addr is
                        when 1 =>  -- LLC使能：1=使能，0=失能
                            r_LLC_en <= w_data_word(0);
                        when 2 =>  -- 频率
                            r_P0ra <= w_data_word;
                        when 3 =>  -- 占空比
                            r_llcduty <= w_data_word;
                        when 4 =>  -- SR使能：1=使能，0=失能
                            r_SR_en <= w_data_word(0);
                        when 5 =>  -- LLC_EN 输出：1=使能，0=失能
                            r_llc_en_out <= w_data_word(0);
                        when others =>
                            null;
                    end case;
                end if;
            end if;
        end process;

        -- OPra：频率来自 llc_con_core.o_period；D/H 命令仍由串口注入
        w_OPra_sel(51 downto 47) <= "10100";  -- H闭锁
        w_OPra_sel(46 downto 42) <= "11010" when r_LLC_en = '1' else "10100";  -- D工作/闭锁
        w_OPra_sel(41 downto 29) <= (others => '0');
        w_OPra_sel(28 downto 16) <= i_llc_period(12 downto 0);  -- f_sw（Hz/10）低13位
        w_OPra_sel(15 downto 0)  <= (others => '0');
        w_llcduty_sel <= i_llc_duty;  -- 占空比来自 llc_con_core.o_duty_cmd

    end generate g_sim;

end architecture rtl;
