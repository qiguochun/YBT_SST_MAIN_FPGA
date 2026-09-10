LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.all;
USE IEEE.NUMERIC_STD.all;

ENTITY sz_ad_tx IS
	PORT(
		szres	:	IN STD_LOGIC;		
		CLKIN	:	IN STD_LOGIC;	--30MHZ
		clcgz	:	IN STD_LOGIC;
		zc_r	:	IN STD_LOGIC;
		clktx	:	IN STD_LOGIC;
		OPra	:	IN STD_LOGIC_VECTOR(51 DOWNTO 0);
		PWM1	:	IN STD_LOGIC;
		PWM2	:	IN STD_LOGIC;
		llcduty: IN STD_LOGIC_VECTOR(15 DOWNTO 0);
		zc_t	:	OUT STD_LOGIC;
		Cerrd	:	OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
		Uhd		:	OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
		Cit	:	OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
		sinFt	:	OUT STD_LOGIC;		
		Led_tx	:	OUT STD_LOGIC	
		);
END sz_ad_tx;

ARCHITECTURE BEHAV OF sz_ad_tx IS

CONSTANT zc_DELAY  :  INTEGER:=12;
CONSTANT zc_dtIN   :  INTEGER:=51;			--系统控制器接收数据				
CONSTANT zc_dtOUT  :  INTEGER:=70;			--系统控制器下发数据
CONSTANT zc_TIMEOUT:  INTEGER:=50000;		--30 MHz下约1.67 ms
CONSTANT zc_LEDCNT :  INTEGER:=5000;
SIGNAL sig_zcclk   :  STD_LOGIC:='0';
SIGNAL sig_zcclk_d :  STD_LOGIC:='0';
SIGNAL sig_zcdtin  :  STD_LOGIC_VECTOR(zc_dtIN-1  DOWNTO 0):=(OTHERS=>'0');
SIGNAL sig_zcdtout :  STD_LOGIC_VECTOR(zc_dtOUT-1 DOWNTO 0):=(OTHERS=>'0');
SIGNAL sig_zcsync   : STD_LOGIC := '0';		--消除亚稳态
SIGNAL sig_zcFiberR:  STD_LOGIC:='0';
SIGNAL sig_zcFiberT:  STD_LOGIC:='0';		--zc_t= not sig_zcFiberT
SIGNAL sig_zcsinFt :  STD_LOGIC:='0';		--Zc单次通迅故障
SIGNAL sig_zcFinish:  STD_LOGIC:='0';		--通讯完成
SIGNAL sig_zcFinish_d:STD_LOGIC:='0';
SIGNAL sig_led_tx  :  STD_LOGIC:='0';
COMPONENT TX_Comm
	GENERIC ( DELAY : INTEGER := 20; DtinN : INTEGER := 41; DtOUT : INTEGER := 51 );
	PORT
	(
		RESET		:	 IN STD_LOGIC;
		CLK			:	 IN STD_LOGIC;
		TXclk		:	 IN STD_LOGIC;
		FiberR		:	 IN STD_LOGIC;
		TXdtIn		:	 OUT STD_LOGIC_VECTOR(dtinn-1 DOWNTO 0);
		TXdtOut		:	 IN STD_LOGIC_VECTOR(dtout-1 DOWNTO 0);
		FiberT		:	 OUT STD_LOGIC;
		TXSinFt		:	 OUT STD_LOGIC;
		TXFinish	:	 OUT STD_LOGIC );
END COMPONENT;

SIGNAL sig_RES,sig_CLR,sig_Cellzgz	:	STD_LOGIC:='0';
SIGNAL sig_CLR_meta,sig_CLR_sync	:	STD_LOGIC:='1';

BEGIN

Cerrd(14)<= '0';
sig_zcclk<=clktx;		sig_RES<=szres;			sig_CLR<=clcgz;			sinFt<=sig_zcsinFt;
Led_tx<=sig_led_tx;

ZC_ClearSync:PROCESS(sig_RES,CLKIN)
BEGIN
	IF(sig_RES='1') THEN
		sig_CLR_meta<='1';		sig_CLR_sync<='1';
	ELSIF rising_edge(CLKIN) THEN
		sig_CLR_meta<=sig_CLR;
		sig_CLR_sync<=sig_CLR_meta;
	END IF;
END PROCESS ZC_ClearSync;

ZC_EventDelay:PROCESS(sig_RES,CLKIN)
BEGIN
	IF(sig_RES='1') THEN
		sig_zcclk_d<='0';
		sig_zcFinish_d<='0';
	ELSIF rising_edge(CLKIN) THEN
		sig_zcclk_d<=sig_zcclk;
		sig_zcFinish_d<=sig_zcFinish;
	END IF;
END PROCESS ZC_EventDelay;

ZC_ledComm:PROCESS(sig_RES,CLKIN)
VARIABLE var_cnt : INTEGER RANGE 0 TO 8191:=0;
BEGIN
	IF(sig_RES='1') THEN
		var_cnt:=0;
		sig_led_tx<='0';
	ELSIF rising_edge(CLKIN) THEN
		IF(sig_zcFinish='1' AND sig_zcFinish_d='0') THEN
			IF(var_cnt >= zc_LEDCNT) THEN
				var_cnt:=1;
				sig_led_tx<=NOT sig_led_tx;
			ELSE
				var_cnt:=var_cnt+1;
			END IF;
		END IF;
	END IF;
END PROCESS ZC_ledComm;

ZC_sc:PROCESS(sig_RES,CLKIN)	--sig_zcdtout
BEGIN
	IF(sig_RES='1') THEN
		sig_zcdtout<=(OTHERS=>'0');
	ELSIF rising_edge(CLKIN) THEN
		IF(sig_zcclk='1' AND sig_zcclk_d='0') THEN
			sig_zcdtout<=llcduty(15 DOWNTO 0)&OPra(51 DOWNTO 42) & PWM1 & PWM2 & OPra(41 DOWNTO 0);
		END IF;
	END IF;
END PROCESS ZC_sc;

ZC_Detect:PROCESS(sig_RES,CLKIN)
    BEGIN
	IF(sig_RES='1') THEN
		sig_zcsync<='0';		sig_zcFiberR<='0';
	ELSIF rising_edge(CLKIN) THEN
		sig_zcsync	<=	zc_r;
		sig_zcFiberR<=	sig_zcsync;
	END IF;
END PROCESS ZC_Detect;

ZC_Error:PROCESS(sig_RES,CLKIN)
	VARIABLE var_clkR :  STD_LOGIC:='0';
	VARIABLE var_cntR,var_cntF	:  INTEGER RANGE 0 TO 65535:=0;
	VARIABLE var_zcRFt,var_zccommFt	:	STD_LOGIC:='0';
	BEGIN
	IF(sig_RES = '1')	THEN
		var_clkR:='0';		var_cntR:=0;			var_zcRFt:='0';
		var_cntF:=0;		var_zccommFt:='0';		Cerrd(5)<='0';			Cerrd(15)<='0';		
	ELSIF rising_edge(CLKIN) THEN
		IF(sig_CLR_sync='1') THEN
			var_clkR:='0';		var_cntR:=0;			var_zcRFt:='0';
			var_cntF:=0;		var_zccommFt:='0';		Cerrd(5)<='0';			Cerrd(15)<='0';
		ELSE
			IF(sig_zcFiberR = var_clkR) THEN						
				IF(var_cntR>=zc_TIMEOUT) THEN
					var_zcRFt:='1';
				ELSE
					var_cntR:=var_cntR+1;
				END IF;
			ELSE
				var_cntR:=0;		var_clkR := sig_zcFiberR;
			END IF;
			IF(sig_zcFinish='0')  		THEN
				IF(var_cntF>=zc_TIMEOUT) THEN
					var_zccommFt:='1';
				ELSE
					var_cntF:=var_cntF+1;	
				END IF;
			ELSE
				var_cntF:=0;
			END IF;
			Cerrd(5) <= var_zcRFt OR var_zccommFt;
			Cerrd(15)<= var_zcRFt OR var_zccommFt OR sig_Cellzgz;
		END IF;
	END IF;  
END PROCESS ZC_Error;

	ZC_COMM: TX_Comm
	GENERIC MAP(
		DELAY   => zc_DELAY,
		DtinN   => zc_dtIN,
		DtOUT   => zc_dtOUT)
	PORT MAP(
		RESET    => sig_RES,
		CLK      => CLKIN,
		TXclk    => sig_zcclk,
		FiberR   => zc_r,
		TXdtIn   => sig_zcdtin,
		TXdtOut  => sig_zcdtout,
		FiberT   => sig_zcFiberT,
		TXSinFt  => sig_zcsinFt,
		TXFinish => sig_zcFinish
	);		
zc_t<=NOT sig_zcFiberT;

ZC_Decodeout:PROCESS(sig_RES,CLKIN)
BEGIN
	IF(sig_RES='1')THEN
		sig_Cellzgz<='0';		Cerrd(13 DOWNTO 6)<=(OTHERS=>'0');			Cerrd(4 DOWNTO 0)<=(OTHERS=>'0');
		Uhd<=(OTHERS=>'0');		Cit<=(OTHERS=>'0');
	ELSIF rising_edge(CLKIN) THEN
		IF(sig_zcFinish='1' AND sig_zcFinish_d='0') THEN
			CASE sig_zcdtin(50 DOWNTO 46) IS
				WHEN "01101" => sig_Cellzgz <='1';
				WHEN "10110" => sig_Cellzgz <='0';
				WHEN OTHERS  => NULL;
			END CASE;
			Cerrd(13 DOWNTO 6)<=sig_zcdtin(45 DOWNTO 38);
			Cerrd(4 DOWNTO 0) <=sig_zcdtin(36 DOWNTO 32);
			Uhd<=sig_zcdtin(31 DOWNTO 16);
			Cit<=sig_zcdtin(15 DOWNTO 0);
		END IF;
	END IF;
END PROCESS ZC_Decodeout;

END BEHAV;