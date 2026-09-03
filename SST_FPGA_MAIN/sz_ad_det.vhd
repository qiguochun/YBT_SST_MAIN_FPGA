LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.all;
USE IEEE.STD_LOGIC_arith.all;
USE IEEE.STD_LOGIC_signed.all;
USE IEEE.NUMERIC_STD.all;

ENTITY sz_ad_det IS
	PORT(
			CLKIN	:	IN STD_LOGIC;
			CLK128M	:	IN 	STD_LOGIC;			        	--128MHZ
		
			addtin	:	IN STD_LOGIC_VECTOR(15 DOWNTO 0);
			CTBL  	:	IN STD_LOGIC_VECTOR(15 DOWNTO 0);
			K1T   	:	IN STD_LOGIC_VECTOR(15 DOWNTO 0);
			K2T   	:	IN STD_LOGIC_VECTOR(15 DOWNTO 0);
			CtMode	:	IN STD_LOGIC_VECTOR(15 DOWNTO 0);
			AdMode	:	IN STD_LOGIC_VECTOR(15 DOWNTO 0);
			P_GL	:	IN STD_LOGIC_VECTOR(15 DOWNTO 0);		
			Q_GL	:	IN STD_LOGIC_VECTOR(15 DOWNTO 0);	--电流控制时为最大补偿功率，无功/电压控制时为指令功率
			Rat_HI	:	IN STD_LOGIC_VECTOR(15 DOWNTO 0);
			PA_DC	:	IN STD_LOGIC_VECTOR(15 DOWNTO 0);
			PB_DC	:	IN STD_LOGIC_VECTOR(15 DOWNTO 0);
			PC_DC	:	IN STD_LOGIC_VECTOR(15 DOWNTO 0);
			PC_Udl	:	IN STD_LOGIC_VECTOR(15 DOWNTO 0);

			KP   	:	IN STD_LOGIC_VECTOR(15 DOWNTO 0);
			KR   	:	IN STD_LOGIC_VECTOR(15 DOWNTO 0);
			KiPH   	:	IN STD_LOGIC_VECTOR(15 DOWNTO 0);
			Arin	:	IN STD_LOGIC_VECTOR(15 DOWNTO 0);
			Brin	:	IN STD_LOGIC_VECTOR(15 DOWNTO 0);
			Crin	:	IN STD_LOGIC_VECTOR(15 DOWNTO 0);	
		
			Dua,Dub,Duc		:	IN STD_LOGIC_VECTOR(15 DOWNTO 0);	--Test
			Dia,Dib,Dic		:	IN STD_LOGIC_VECTOR(15 DOWNTO 0);	--Test
			
			Reset 	:	OUT STD_LOGIC;
			Int_ps 	:	OUT STD_LOGIC;
			CLK5HZ	:	OUT STD_LOGIC;
			FHXZ	:	OUT STD_LOGIC;
		
			ad1cs	:	OUT STD_LOGIC;
			ad2cs	:	OUT STD_LOGIC;
			ad1rd	:	OUT STD_LOGIC;
			ad2rd	:	OUT STD_LOGIC;
			adconv	:	OUT STD_LOGIC;
	
			CLKAD	:	OUT  STD_LOGIC;
			CLKzz	:	OUT  STD_LOGIC;
			LEDres	:	OUT  STD_LOGIC;
					
			ua,ub,uc	 	:	OUT STD_LOGIC_VECTOR(15 DOWNTO 0);			
			va,vb,vc	 	:	OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
			isa,isb,isc 	:	OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
			ila,ilb,ilc 	:	OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
			ica,icb,icc		:	OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
			ilqa,ilqb,ilqc	:	OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
			ipa,ipb,ipc		:	OUT STD_LOGIC_VECTOR(15 DOWNTO 0);		
			coswtPllO		:	OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
			sinwtPllO		:	OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
			UdPllO			:	OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
			UqPllO			:	OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
			
			atz,btz,ctz		:	OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
			iea,ieb,iec		:	OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
			udl,idl 		:	OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
			uas,ubs,ucs		:	OUT STD_LOGIC_VECTOR(15 DOWNTO 0)
		);
END ENTITY;

ARCHITECTURE BEHAV OF sz_ad_det IS

CONSTANT NUMD	:	INTEGER	:=2048;
CONSTANT NUMW	:	INTEGER	:=11;

SIGNAL 	sig_RES		:	STD_LOGIC:='1';
SIGNAL 	sig_ADover	:	STD_LOGIC:='0';
SIGNAL 	sig_clk5Hz	:	STD_LOGIC:='0';
SIGNAL 	sig_ADover_d,sig_clk5Hz_d : STD_LOGIC:='0';

SIGNAL	sig_ua,sig_ub,sig_uc,sig_isa,sig_isb,sig_isc	:	STD_LOGIC_VECTOR(15 DOWNTO 0):=(OTHERS=>'0');
SIGNAL	sig_uatz,sig_ubtz,sig_uctz						:	INTEGER RANGE -65535 TO 65535:=0;
SIGNAL	sig_ila,sig_ilb,sig_ilc,sig_ica,sig_icb,sig_icc	:	STD_LOGIC_VECTOR(15 DOWNTO 0):=(OTHERS=>'0');
SIGNAL	sig_uba,sig_ubb,sig_ubc			:	STD_LOGIC_VECTOR(15 DOWNTO 0):=(OTHERS=>'0');

SIGNAL 	sig_ADstart	: STD_LOGIC:='0';	--102.4kHz
SIGNAL 	CLKRomPll  	: STD_LOGIC:='0';
SIGNAL 	addrCosPll,addrSinPll		: STD_LOGIC_VECTOR(NUMW-1 DOWNTO 0):=(OTHERS=>'0');
SIGNAL 	sig_coswtPll,sig_sinwtPll 	: STD_LOGIC_VECTOR(15 DOWNTO 0):=(OTHERS=>'0');
SIGNAL 	sig_UdPll,sig_UqPll  : STD_LOGIC_VECTOR(15 DOWNTO 0):=(OTHERS=>'0');
CONSTANT Kp_Pll	:	INTEGER := 65;		--0.2*2048/(2*pi)
CONSTANT Ki_Pll	:	INTEGER := 6520;	--20*2048/(2*pi)
COMPONENT ROM2_16_2048
	PORT
	(
		address_a: IN STD_LOGIC_VECTOR (NUMW-1 DOWNTO 0);
		address_b: IN STD_LOGIC_VECTOR (NUMW-1 DOWNTO 0);
		clock	 : IN STD_LOGIC := '1';
		q_a		 : OUT STD_LOGIC_VECTOR (15 DOWNTO 0);
		q_b		 : OUT STD_LOGIC_VECTOR (15 DOWNTO 0)
	);
END COMPONENT;


SIGNAL 	sig_PorQ,sig_PQ1u,sig_PQ2u	: 	INTEGER RANGE -65535 TO 65535:=0;
SIGNAL	sig_PQu2rst					:	INTEGER RANGE -2147483647 TO 2147483647:=65536;
SIGNAL 	sig_PQiA,sig_PQiB 			:	INTEGER RANGE -131071 TO 131071:=0;
SIGNAL 	sig_rstA,sig_rstB,sig_rstC	:	INTEGER RANGE -65535 TO 65535:=0;
---------------------------COMPONENT--------------------------------------
SIGNAL CLKram	:	STD_LOGIC:='0';
SIGNAL addrQdt	:  	STD_LOGIC_VECTOR(NUMW-1 downTO 0):=(OTHERS=>'0');
SIGNAL FFUndt,FFUodt,FFQndt,FFQodt	: 	STD_LOGIC_VECTOR(31 DOWNTO 0):=(OTHERS=>'0');
COMPONENT RAM_32_2048
	PORT
	(
		aclr		: IN STD_LOGIC  := '0';
		address		: IN STD_LOGIC_VECTOR (NUMW-1 DOWNTO 0);
		clock		: IN STD_LOGIC  := '1';
		data		: IN STD_LOGIC_VECTOR (31 DOWNTO 0);
		wren		: IN STD_LOGIC ;
		q		: OUT STD_LOGIC_VECTOR (31 DOWNTO 0)
	);
END COMPONENT;
---------------------------COMPONENT--------------------------------------


BEGIN

-------------------------------------------------------1.复位时钟---------------------------------------------------------------
P_reset:PROCESS(CLKIN)		--sig_RES
	VARIABLE var_cnt:INTEGER RANGE 0 TO 4095:=0;
	BEGIN
	IF(CLKIN'EVENT AND CLKIN='1')	THEN
		IF(var_cnt>=2999) THEN
			sig_RES<='0';
		ELSE
			var_cnt:=var_cnt+1;			sig_RES<='1';	
		END IF;
	END IF;
END PROCESS P_reset;
Reset<=sig_RES;

P_EVENT_DELAY:PROCESS(CLKIN)
	BEGIN
	IF(CLKIN'EVENT AND CLKIN='1') THEN
		IF(sig_RES='1') THEN
			sig_ADover_d<='0';		sig_clk5Hz_d<='0';
		ELSE
			sig_ADover_d<=sig_ADover;
			sig_clk5Hz_d<=sig_clk5Hz;
		END IF;
	END IF;
END PROCESS P_EVENT_DELAY;

P_TX:PROCESS(CLKIN)
	VARIABLE  var_cnt : INTEGER RANGE 0 TO 7:=0;
	BEGIN
	IF(CLKIN'EVENT AND CLKIN='1') THEN
		IF(sig_RES='1') THEN
			var_cnt:=0;	CLKzz<='0';
		ELSIF(sig_ADover='1' AND sig_ADover_d='0') THEN
			var_cnt:=var_cnt+1;
			CASE var_cnt IS
				WHEN 1	=>	CLKzz	<='0';
				WHEN 3	=>	CLKzz	<='1';
				WHEN 4	=>	var_cnt	:=0;
				WHEN OTHERS=>NULL;
			END CASE;
		END IF;
	END IF;
END PROCESS P_TX;

P_CLK12_8KHZ:PROCESS(CLKIN)
	VARIABLE  var_cnt : INTEGER RANGE 0 TO 15:=0;
	BEGIN
	IF(CLKIN'EVENT AND CLKIN='1') THEN
		IF(sig_RES='1') THEN
			var_cnt:=0;	Int_ps<='0';
		ELSIF(sig_ADover='1' AND sig_ADover_d='0') THEN
			var_cnt:=var_cnt+1;
			CASE var_cnt IS
				WHEN 1	=>	Int_ps	<='0';
				WHEN 5	=>	Int_ps	<='1';
				WHEN 8	=>	var_cnt	:= 0;
				WHEN OTHERS=>NULL;
			END CASE;
		END IF;
	END IF;
END PROCESS P_CLK12_8KHZ;

P_CLK5HZ:PROCESS(CLKIN)		--CLK5HZ
    VARIABLE  var_cnt : INTEGER RANGE 0 TO 8388607:=0;
    BEGIN
	IF(CLKIN'EVENT AND CLKIN='1') THEN
		IF(sig_RES='1') THEN
			var_cnt:=0;		sig_clk5Hz<='0';
		ELSE
			var_cnt:=var_cnt+1;
			CASE var_cnt IS 
				WHEN 1       =>  sig_clk5Hz <=	'1';
				WHEN 3000001 =>  sig_clk5Hz <=	'0';
				WHEN 6000000 =>  var_cnt:=	 0;
				WHEN OTHERS=>NULL;
			END CASE;
		END IF;
	END IF;
END PROCESS P_CLK5HZ;
CLK5HZ<=sig_clk5Hz;

P_LEDRES:PROCESS(CLKIN)
    VARIABLE  var_cnt 	: INTEGER RANGE 0 TO 31:=0;
	VARIABLE  var_ledres: STD_LOGIC:='0';
    BEGIN
	IF(CLKIN'EVENT AND CLKIN='1') THEN
		IF(sig_RES='1') THEN
			var_cnt:=0;	var_ledres:='0';	LEDres<='0';
		ELSE
			IF(sig_clk5Hz='1' AND sig_clk5Hz_d='0')	THEN
				IF(var_cnt<=25)	THEN
					var_cnt:=var_cnt+1;
					var_ledres:='1';
				ELSE
					var_ledres:='0';
				END IF;	
			END IF;
			LEDres<=sig_clk5Hz AND var_ledres;
		END IF;
	END IF;
END PROCESS P_LEDRES;
-------------------------------------------------------1.复位时钟---------------------------------------------------------------

------------------------------------------------------2.AD采样控制--------------------------------------------------------------
P_ADCON:PROCESS(sig_RES,CLKIN)
VARIABLE var_cnt : 	INTEGER RANGE 0 TO 255:=0;
VARIABLE Step	 : 	INTEGER RANGE 0 TO 31:=0;
VARIABLE var_ad1da1ta,var_ad1da2ta,var_ad1da3ta,var_ad1da4ta,var_ad1da5ta,var_ad1da6ta,var_ad1da7ta,var_ad1da8ta:STD_LOGIC_VECTOR(15 DOWNTO 0):=(OTHERS=>'0');
VARIABLE var_ad2da1ta,var_ad2da2ta,var_ad2da3ta,var_ad2da4ta,var_ad2da5ta,var_ad2da6ta,var_ad2da7ta,var_ad2da8ta:STD_LOGIC_VECTOR(15 DOWNTO 0):=(OTHERS=>'0');
VARIABLE var_isa,var_isb,var_isc :  INTEGER RANGE -32767 TO 32767:=0;
VARIABLE var_ila,var_ilb,var_ilc :  INTEGER RANGE -32767 TO 32767:=0;
VARIABLE var_ica,var_icb,var_icc :  INTEGER RANGE -32767 TO 32767:=0;

BEGIN
	IF(sig_RES='1')	THEN
		var_cnt:=0;	 	Step:=0;		sig_ADover<='0';
		adconv<='1';	ad1cs<='1';	 	ad1rd<='1';	 		ad2cs<='1';  		ad2rd<='1';	 	
		var_ad1da1ta:=(OTHERS=>'0');		var_ad1da2ta:=(OTHERS=>'0');		var_ad1da3ta:=(OTHERS=>'0');		var_ad1da4ta:=(OTHERS=>'0');
		var_ad1da5ta:=(OTHERS=>'0');		var_ad1da6ta:=(OTHERS=>'0');		var_ad1da7ta:=(OTHERS=>'0');		var_ad1da8ta:=(OTHERS=>'0');
		var_ad2da1ta:=(OTHERS=>'0');		var_ad2da2ta:=(OTHERS=>'0');		var_ad2da3ta:=(OTHERS=>'0');		var_ad2da4ta:=(OTHERS=>'0');
		var_ad2da5ta:=(OTHERS=>'0');		var_ad2da6ta:=(OTHERS=>'0');		var_ad2da7ta:=(OTHERS=>'0');		var_ad2da8ta:=(OTHERS=>'0');
		var_isa:=0;							var_isb:=0;							var_isc:=0;
		var_ila:=0;							var_ilb:=0;							var_ilc:=0;
		var_ica:=0;							var_icb:=0;							var_icc:=0;

		sig_ua<=(OTHERS=>'0');		sig_ub<=(OTHERS=>'0');		sig_uc<=(OTHERS=>'0');		--u
		uas<=(OTHERS=>'0');			ubs<=(OTHERS=>'0');			ucs<=(OTHERS=>'0');		sig_uatz<=0;	sig_ubtz<=0;	sig_uctz<=0;	--uas=k1*ua+k2*(ub-uc)
		va<=(OTHERS=>'0');			vb<=(OTHERS=>'0');			vc<=(OTHERS=>'0');		--v
		sig_isa<=(OTHERS=>'0');		sig_isb<=(OTHERS=>'0');		sig_isc<=(OTHERS=>'0');		--is
		sig_ila<=(OTHERS=>'0');		sig_ilb<=(OTHERS=>'0');		sig_ilc<=(OTHERS=>'0');		--il
		sig_ica<=(OTHERS=>'0');		sig_icb<=(OTHERS=>'0');		sig_icc<=(OTHERS=>'0');		--ic
		udl<=(OTHERS=>'0');		idl<=(OTHERS=>'0');								--ud,id
	ELSIF(CLKIN'EVENT AND CLKIN='1') THEN
		CASE Step IS
			WHEN 0	=>	IF(sig_ADstart='1') THEN
							adconv<='0';			sig_ADover<='0';			Step := 1;
						END IF;
			WHEN 1	=>	var_cnt:=var_cnt+1;
						IF(var_cnt=3)  THEN			adconv<='1';  var_cnt:=0;	Step := 2;
						END IF;		
-----------------------------------------------AD1---------------------------------------------
			WHEN 2	=>	var_cnt:=var_cnt+1;
						IF(var_cnt=120)	THEN		ad1cs<='0';	  var_cnt:=0;	Step := 3;
						END IF;	
			WHEN 3	=>	var_cnt:=var_cnt+1;		---------ad1ch1							
						IF(var_cnt=1)	    THEN	ad1rd<='0';	
						ELSIF(var_cnt=2)	THEN	var_ad1da1ta:=addtin;			
						ELSIF(var_cnt=3)  	THEN	ad1rd<='1';	  var_cnt:=0;	Step := 4;
						END IF;					
			WHEN 4	=>	var_cnt:=var_cnt+1;		---------ad1ch2
						IF(var_cnt=1)	    THEN	ad1rd<='0';	
						ELSIF(var_cnt=2)	THEN	var_ad1da2ta:=addtin;			
						ELSIF(var_cnt=3)  	THEN	ad1rd<='1';	  var_cnt:=0;	Step := 5;
						END IF;	
			WHEN 5	=>	var_cnt:=var_cnt+1;		---------ad1ch3
						IF(var_cnt=1)	    THEN	ad1rd<='0';	
						ELSIF(var_cnt=2)	THEN	var_ad1da3ta:=addtin;			
						ELSIF(var_cnt=3)  	THEN	ad1rd<='1';	  var_cnt:=0;	Step := 6;
						END IF;	
			WHEN 6	=>	var_cnt:=var_cnt+1;		---------ad1ch4		
						IF(var_cnt=1)	    THEN	ad1rd<='0';	
						ELSIF(var_cnt=2)	THEN	var_ad1da4ta:=addtin;			
						ELSIF(var_cnt=3)  	THEN	ad1rd<='1';	  var_cnt:=0;	Step := 7;
						END IF;	
			WHEN 7	=>	var_cnt:=var_cnt+1;		---------ad1ch5	
						IF(var_cnt=1)	    THEN	ad1rd<='0';	
						ELSIF(var_cnt=2)	THEN	var_ad1da5ta:=addtin;			
						ELSIF(var_cnt=3)  	THEN	ad1rd<='1';	  var_cnt:=0;	Step := 8;
						END IF;	
			WHEN 8	=>	var_cnt:=var_cnt+1;		---------ad1ch6	
						IF(var_cnt=1)	    THEN	ad1rd<='0';	
						ELSIF(var_cnt=2)	THEN	var_ad1da6ta:=addtin;			
						ELSIF(var_cnt=3)  	THEN	ad1rd<='1';	  var_cnt:=0;	Step := 9;
						END IF;	
			WHEN 9	=>	var_cnt:=var_cnt+1;		---------ad1ch7	
						IF(var_cnt=1)	    THEN	ad1rd<='0';	
						ELSIF(var_cnt=2)	THEN	var_ad1da7ta:=addtin;			
						ELSIF(var_cnt=3)  	THEN	ad1rd<='1';	  var_cnt:=0;	Step := 10;
						END IF;	
			WHEN 10	=>	var_cnt:=var_cnt+1;		---------ad1ch8	
						IF(var_cnt=1)	    THEN	ad1rd<='0';	
						ELSIF(var_cnt=2)	THEN	var_ad1da8ta:=addtin;			
						ELSIF(var_cnt=3)  	THEN	ad1rd<='1';	  var_cnt:=0;	Step := 11;		ad1cs<='1';	
						END IF;					
-----------------------------------------------AD2---------------------------------------------
			WHEN 11	=>	var_cnt:=var_cnt+1;
						IF(var_cnt=2)	THEN		ad2cs<='0';	  var_cnt:=0;	Step := 12;
						END IF;	
			WHEN 12	=>	var_cnt:=var_cnt+1;		---------ad2ch1						
						IF(var_cnt=1)	    THEN	ad2rd<='0';	
						ELSIF(var_cnt=2)	THEN	var_ad2da1ta:=addtin;			
						ELSIF(var_cnt=3)  	THEN	ad2rd<='1';	  var_cnt:=0;	Step := 13;
						END IF;					
			WHEN 13	=>	var_cnt:=var_cnt+1;		---------ad2ch2
						IF(var_cnt=1)	    THEN	ad2rd<='0';	
						ELSIF(var_cnt=2)	THEN	var_ad2da2ta:=addtin;			
						ELSIF(var_cnt=3)  	THEN	ad2rd<='1';	  var_cnt:=0;	Step := 14;
						END IF;	
			WHEN 14	=>	var_cnt:=var_cnt+1;		---------ad1ch3
						IF(var_cnt=1)	    THEN	ad2rd<='0';	
						ELSIF(var_cnt=2)	THEN	var_ad2da3ta:=addtin;			
						ELSIF(var_cnt=3)  	THEN	ad2rd<='1';	  var_cnt:=0;	Step := 15;
						END IF;	
			WHEN 15	=>	var_cnt:=var_cnt+1;		---------ad2ch4
						IF(var_cnt=1)	    THEN	ad2rd<='0';	
						ELSIF(var_cnt=2)	THEN	var_ad2da4ta:=addtin;			
						ELSIF(var_cnt=3)  	THEN	ad2rd<='1';	  var_cnt:=0;	Step := 16;
						END IF;	
			WHEN 16	=>	var_cnt:=var_cnt+1;		---------ad2ch5
						IF(var_cnt=1)	    THEN	ad2rd<='0';	
						ELSIF(var_cnt=2)	THEN	var_ad2da5ta:=addtin;			
						ELSIF(var_cnt=3)  	THEN	ad2rd<='1';	  var_cnt:=0;	Step := 17;
						END IF;	
			WHEN 17	=>	var_cnt:=var_cnt+1;		---------ad2ch6
						IF(var_cnt=1)	    THEN	ad2rd<='0';	
						ELSIF(var_cnt=2)	THEN	var_ad2da6ta:=addtin;			
						ELSIF(var_cnt=3)  	THEN	ad2rd<='1';	  var_cnt:=0;	Step := 18;
						END IF;	
			WHEN 18	=>	var_cnt:=var_cnt+1;		---------ad2ch7
						IF(var_cnt=1)	    THEN	ad2rd<='0';	
						ELSIF(var_cnt=2)	THEN	var_ad2da7ta:=addtin;			
						ELSIF(var_cnt=3)  	THEN	ad2rd<='1';	  var_cnt:=0;	Step := 19;
						END IF;	
			WHEN 19	=>	var_cnt:=var_cnt+1;		---------ad2ch8
						IF(var_cnt=1)	    THEN	ad2rd<='0';	
						ELSIF(var_cnt=2)	THEN	var_ad2da8ta:=addtin;			
						ELSIF(var_cnt=3)  	THEN	ad2rd<='1';	  var_cnt:=0;	Step := 20;		ad2cs<='1';
						END IF;	
			WHEN 20	=>	var_cnt:=var_cnt+1;			---------adOUT
						--------------------------测试---------------------------------------
						-- var_ad2da4ta:=Dua;		var_ad2da1ta:=Dub;			var_ad2da2ta:=Duc;
						-- var_ad1da1ta:=Dia; 		var_ad1da2ta:=Dic;
						-- var_ad2da7ta:=Dia; 		var_ad2da8ta:=Dic;						
						--------------------------测试---------------------------------------	
						IF(var_cnt=1)	    THEN							
							--sig_ua<=var_ad2da4ta;	sig_ub<=var_ad2da1ta;	sig_uc<=var_ad2da2ta;	--u							
							sig_ua <= CONV_std_logic_vector( (CONV_INTEGER(var_ad2da4ta)*4 + CONV_INTEGER(var_ad2da1ta)*2), 16 );
							sig_ub <= CONV_std_logic_vector( (CONV_INTEGER(var_ad2da1ta)*4 + CONV_INTEGER(var_ad2da2ta)*2), 16 );
							sig_uc <= CONV_std_logic_vector( (CONV_INTEGER(var_ad2da2ta)*4 + CONV_INTEGER(var_ad2da4ta)*2), 16 );
							va<=var_ad2da5ta;		vb<=var_ad2da6ta;		vc<=var_ad2da3ta;		--v
							udl<=var_ad1da7ta;		idl<=var_ad1da8ta;								--ud,id						
							var_ica:=CONV_INTEGER(var_ad2da7ta);	var_icb:=-(CONV_INTEGER(var_ad2da7ta)+CONV_INTEGER(var_ad2da8ta));	var_icc:=CONV_INTEGER(var_ad2da8ta);
							IF(AdMode="0101011001111000") 	THEN	--0x5678,系统侧电流采样
								var_isa:=CONV_INTEGER(var_ad1da1ta);	var_isb:=-(CONV_INTEGER(var_ad1da1ta)+CONV_INTEGER(var_ad1da2ta));	var_isc:=CONV_INTEGER(var_ad1da2ta);
								var_ila:=var_isa - var_ica*(CONV_INTEGER(CTBL))/32768;
								var_ilb:=var_isb - var_icb*(CONV_INTEGER(CTBL))/32768;
								var_ilc:=var_isc - var_icc*(CONV_INTEGER(CTBL))/32768;
							ELSIF(AdMode="0001001000110100") THEN	--0x1234,负荷侧电流采样
								var_ila:=CONV_INTEGER(var_ad1da1ta);	var_ilb:=-(CONV_INTEGER(var_ad1da1ta)+CONV_INTEGER(var_ad1da2ta));	var_ilc:=CONV_INTEGER(var_ad1da2ta);						
								var_isa:=var_ila + var_ica*(CONV_INTEGER(CTBL))/32768;
								var_isb:=var_ilb + var_icb*(CONV_INTEGER(CTBL))/32768;
								var_isc:=var_ilc + var_icc*(CONV_INTEGER(CTBL))/32768;
							END IF;
						ELSIF(var_cnt=4)  THEN	
							sig_uatz <= ( CONV_INTEGER(sig_ua)*CONV_INTEGER(K1T) - ( CONV_INTEGER(sig_ub)-CONV_INTEGER(sig_uc) ) *CONV_INTEGER(K2T) ) /4096;
							sig_ubtz <= ( CONV_INTEGER(sig_ub)*CONV_INTEGER(K1T) - ( CONV_INTEGER(sig_uc)-CONV_INTEGER(sig_ua) ) *CONV_INTEGER(K2T) ) /4096;
							sig_uctz <= ( CONV_INTEGER(sig_uc)*CONV_INTEGER(K1T) - ( CONV_INTEGER(sig_ua)-CONV_INTEGER(sig_ub) ) *CONV_INTEGER(K2T) ) /4096;
							IF(sig_uatz>=32767) 	THEN	uas<=CONV_STD_LOGIC_VECTOR(32767,16);
							ELSIF(sig_uatz<=-32767) THEN	uas<=CONV_STD_LOGIC_VECTOR(-32767,16);
							ELSE							uas<=CONV_STD_LOGIC_VECTOR(sig_uatz,16);
							END IF;
							IF(sig_ubtz>=32767) 	THEN	ubs<=CONV_STD_LOGIC_VECTOR(32767,16);
							ELSIF(sig_ubtz<=-32767) THEN	ubs<=CONV_STD_LOGIC_VECTOR(-32767,16);
							ELSE							ubs<=CONV_STD_LOGIC_VECTOR(sig_ubtz,16);
							END IF;
							IF(sig_uctz>=32767) 	THEN	ucs<=CONV_STD_LOGIC_VECTOR(32767,16);
							ELSIF(sig_uctz<=-32767) THEN	ucs<=CONV_STD_LOGIC_VECTOR(-32767,16);
							ELSE							ucs<=CONV_STD_LOGIC_VECTOR(sig_uctz,16);
							END IF;										
						ELSIF(var_cnt=6)  THEN
							sig_isa<=CONV_STD_LOGIC_VECTOR(var_isa,16);		sig_isb<=CONV_STD_LOGIC_VECTOR(var_isb,16);		sig_isc<=CONV_STD_LOGIC_VECTOR(var_isc,16);
							sig_ila<=CONV_STD_LOGIC_VECTOR(var_ila,16);		sig_ilb<=CONV_STD_LOGIC_VECTOR(var_ilb,16);		sig_ilc<=CONV_STD_LOGIC_VECTOR(var_ilc,16);
							sig_ica<=CONV_STD_LOGIC_VECTOR(var_ica,16);		sig_icb<=CONV_STD_LOGIC_VECTOR(var_icb,16);		sig_icc<=CONV_STD_LOGIC_VECTOR(var_icc,16);
							sig_ADover<='1';	var_cnt:=0;		Step := 21;
						END IF;							
			WHEN 21	=>	IF(sig_ADstart='0')	THEN		Step := 0;	  
						END IF;		
			WHEN OTHERS=>NULL;
		END CASE;
	END IF;
END PROCESS P_ADCON;
ua<=sig_ua;			ub<=sig_ub;			uc<=sig_uc;			isa<=sig_isa;		isb<=sig_isb;		isc<=sig_isc;
ila<=sig_ila;		ilb<=sig_ilb;		ilc<=sig_ilc;		ica<=sig_ica;		icb<=sig_icb;		icc<=sig_icc;		
------------------------------------------------------2.AD采样控制--------------------------------------------------------------

P_ADstart : PROCESS(CLK128M)
    VARIABLE  var_cnt : INTEGER RANGE 0 TO 2047:=0;
    BEGIN
	IF(CLK128M'EVENT AND CLK128M='1' ) THEN
		var_cnt:=var_cnt+1;
		CASE var_cnt IS 
			WHEN  1   =>  sig_ADstart <= '1';
			WHEN 626  =>  sig_ADstart <= '0';
			WHEN 1250 =>  var_cnt := 0;
			WHEN OTHERS=>NULL;
		END CASE;
	END IF;
END PROCESS P_ADstart;

P_PQCON:PROCESS(sig_RES,CLKIN)
	VARIABLE uA_mid,uB_mid 	:	INTEGER RANGE -65535 TO 65535:=0;	--uA,uB
	VARIABLE iA_mid,iB_mid	:	INTEGER RANGE -65535 TO 65535:=0;	--iA,iB
	VARIABLE uadd_mid		:	INTEGER RANGE -2147483647 TO 2147483647:=65536;
	VARIABLE Qadd_mid,QMax_mid,Qrst	:	INTEGER RANGE -2147483647 TO 2147483647:=0;

	VARIABLE Index 	:	INTEGER RANGE 0 TO NUMD-1:=0;
	VARIABLE Step 	:	INTEGER RANGE 0 TO 31:=0;
	VARIABLE var_iqa,var_iqb,var_iqc	:	INTEGER RANGE -65535 TO 65535:=0;
	VARIABLE var_ipa,var_ipb,var_ipc	:	INTEGER RANGE -65535 TO 65535:=0;
	VARIABLE var_iea,var_ieb,var_iec	:	INTEGER RANGE -65535 TO 65535:=0;
	VARIABLE var_Arst,var_Brst,var_Crst	:	INTEGER RANGE -65535 TO 65535:=0;
	BEGIN
	IF(sig_RES='1') THEN
		sig_PorQ<=0;			sig_PQ1u<=0;			sig_PQ2u<=0;			sig_PQu2rst<=65536;		
		CLKram<='0';			addrQdt<=(OTHERS=>'0');	FFUndt<=(OTHERS=>'0');	FFQndt<=(OTHERS=>'0');
		uA_mid:=0;				uB_mid:=0;				iA_mid:=0;				iB_mid:=0;
		uadd_mid:=65536;		Qadd_mid:=0;			QMax_mid:=0;			Qrst:=0;
		Index:=0;				Step:=0;				FHXZ<='0';				CLKAD<='0';	
		var_ipa:=0;				var_ipb:=0;				var_ipc:=0;				
		var_iqa:=0;				var_iqb:=0;				var_iqc:=0;
		var_iea:=0;				var_ieb:=0;				var_iec:=0;
		var_Arst:=0;			var_Brst:=0;			var_Crst:=0;		
		ilqa<=(OTHERS=>'0');	ilqb<=(OTHERS=>'0');	ilqc<=(OTHERS=>'0');	ipa<=(OTHERS=>'0');		ipb<=(OTHERS=>'0');		ipc<=(OTHERS=>'0');					
	ELSIF(CLKIN'EVENT AND CLKIN='1') THEN
		CASE Step IS
			WHEN 0 =>	IF(sig_ADover = '1')	THEN							--sqrt(2/3)=2*6689/16384，sqrt(2)/2=11585/16384
							uA_mid :=((2*CONV_INTEGER(sig_ua) -CONV_INTEGER(sig_ub) -CONV_INTEGER(sig_uc) )*6689)/16384;		uB_mid:= ((CONV_INTEGER(sig_ub) -CONV_INTEGER(sig_uc) )*11585)/16384;
							QMax_mid:=CONV_INTEGER(Q_GL)*32768;			addrQdt<=CONV_STD_LOGIC_VECTOR(Index,NUMW);
							Step:=1;		CLKAD<='1';
						END IF;			
			WHEN 1 =>	Step:=2;					
			WHEN 2 =>	FFUndt<=CONV_STD_LOGIC_VECTOR(((uA_mid/2)*(uA_mid/2)+(uB_mid/2)*(uB_mid/2))/(NUMD/4),32);
						Step:=3;
			WHEN 3 =>	CLKram<='1';		Step:=4;						
			WHEN 4 =>	CLKram<='0';		Step:=5;			
			WHEN 5 =>	uadd_mid:=uadd_mid-CONV_INTEGER(FFUodt)+CONV_INTEGER(FFUndt);
						IF(uadd_mid<=0) 		THEN		sig_PQu2rst<=2147483647;
						ELSE								sig_PQu2rst<=uadd_mid;
						END IF;	
						IF(CtMode="0001001000110100") 	THEN	--0x1234,电流控制
							IF(Qadd_mid>QMax_mid) 	 	THEN		Qrst:=QMax_mid;
							ELSIF(Qadd_mid<-QMax_mid) 	THEN		Qrst:=-QMax_mid;
							ELSE									Qrst:=Qadd_mid;
							END IF;	
						ELSIF(CtMode="0101011001111000") THEN	--0x5678,功率控制
							Qrst:=QMax_mid;
						END IF;		
						IF(Qrst>0)		 		THEN		FHXZ<='0';
						ELSE              					FHXZ<='1';
						END IF;						
						Step:=6;			
			
			WHEN 6 =>	sig_PQ1u<=uB_mid;		sig_PQ2u<=-uA_mid;		sig_PorQ<=Qrst/65536;			--无功功率	
						Step:=7;
			WHEN 7 =>	Step:=8;
			WHEN 8 =>	Step:=9;
			WHEN 9 =>	Step:=10;
			WHEN 10=>	var_iqa:=sig_rstA;		var_iqb:=sig_rstB;		var_iqc:=sig_rstC;
						IF(var_iqa>=32767) 	 	THEN	ilqa<=CONV_STD_LOGIC_VECTOR(32767,16);
						ELSIF(var_iqa<=-32767)  THEN	ilqa<=CONV_STD_LOGIC_VECTOR(-32767,16);
						ELSE							ilqa<=CONV_STD_LOGIC_VECTOR(var_iqa,16);
						END IF;
						IF(var_iqb>=32767)      THEN	ilqb<=CONV_STD_LOGIC_VECTOR(32767,16);
						ELSIF(var_iqb<=-32767)  THEN	ilqb<=CONV_STD_LOGIC_VECTOR(-32767,16);
						ELSE							ilqb<=CONV_STD_LOGIC_VECTOR(var_iqb,16);
						END IF;
						IF(var_iqc>=32767) 	 	THEN	ilqc<=CONV_STD_LOGIC_VECTOR(32767,16);
						ELSIF(var_iqc<=-32767)  THEN	ilqc<=CONV_STD_LOGIC_VECTOR(-32767,16);
						ELSE							ilqc<=CONV_STD_LOGIC_VECTOR(var_iqc,16);
						END IF;
						Step:=11;
						
			WHEN 11	=>	sig_PQ1u<=uA_mid;	sig_PQ2u<=uB_mid;	sig_PorQ<=( CONV_INTEGER(P_GL)+ CONV_INTEGER(PA_DC)+CONV_INTEGER(PB_DC)+CONV_INTEGER(PC_DC)+CONV_INTEGER(PC_Udl))/2;--有功功率,/2=32768/65536
						Step:=12;
			WHEN 12	=>	Step:=13;
			WHEN 13	=>	Step:=14;						
			WHEN 14	=>	Step:=15;	
			WHEN 15	=>	var_ipa:=sig_rstA;		var_ipb:=sig_rstB;		var_ipc:=sig_rstC;
						IF(var_ipa>=32767) 	 	THEN	ipa<=CONV_STD_LOGIC_VECTOR(32767,16);
						ELSIF(var_ipa<=-32767)  THEN	ipa<=CONV_STD_LOGIC_VECTOR(-32767,16);
						ELSE							ipa<=CONV_STD_LOGIC_VECTOR(var_ipa,16);
						END IF;
						IF(var_ipb>=32767)      THEN	ipb<=CONV_STD_LOGIC_VECTOR(32767,16);
						ELSIF(var_ipb<=-32767)  THEN	ipb<=CONV_STD_LOGIC_VECTOR(-32767,16);
						ELSE							ipb<=CONV_STD_LOGIC_VECTOR(var_ipb,16);
						END IF;
						IF(var_ipc>=32767) 	 	THEN	ipc<=CONV_STD_LOGIC_VECTOR(32767,16);
						ELSIF(var_ipc<=-32767)  THEN	ipc<=CONV_STD_LOGIC_VECTOR(-32767,16);
						ELSE							ipc<=CONV_STD_LOGIC_VECTOR(var_ipc,16);
						END IF;
			
			
						Step:=16;
-------------------------------------------------------电流控制----------------------------------------------------------------
			WHEN 16=>	var_iea:=var_iqa + var_ipa - ( (sig_uatz/8)*CONV_INTEGER(PA_DC)*CONV_INTEGER(KiPH) )/2048 + (CONV_INTEGER(sig_ica)*CONV_INTEGER(CTBL))/32768;     
						var_ieb:=var_iqb + var_ipb - ( (sig_ubtz/8)*CONV_INTEGER(PB_DC)*CONV_INTEGER(KiPH) )/2048 + (CONV_INTEGER(sig_icb)*CONV_INTEGER(CTBL))/32768;     
						var_iec:=var_iqc + var_ipc - ( (sig_uctz/8)*CONV_INTEGER(PC_DC)*CONV_INTEGER(KiPH) )/2048 + (CONV_INTEGER(sig_icc)*CONV_INTEGER(CTBL))/32768;  
						IF(var_iea>=32767) 	 	THEN	iea<=CONV_STD_LOGIC_VECTOR(32767,16);
						ELSIF(var_iea<=-32767)  THEN	iea<=CONV_STD_LOGIC_VECTOR(-32767,16);
						ELSE							iea<=CONV_STD_LOGIC_VECTOR(var_iea,16);
						END IF;
						IF(var_ieb>=32767)      THEN	ieb<=CONV_STD_LOGIC_VECTOR(32767,16);
						ELSIF(var_ieb<=-32767)  THEN	ieb<=CONV_STD_LOGIC_VECTOR(-32767,16);
						ELSE							ieb<=CONV_STD_LOGIC_VECTOR(var_ieb,16);
						END IF;
						IF(var_iec>=32767) 	 	THEN	iec<=CONV_STD_LOGIC_VECTOR(32767,16);
						ELSIF(var_iec<=-32767)  THEN	iec<=CONV_STD_LOGIC_VECTOR(-32767,16);
						ELSE							iec<=CONV_STD_LOGIC_VECTOR(var_iec,16);
						END IF;
						Step:=17;
			WHEN 17	=>	Step:=18;
			WHEN 18	=>	Step:=19;
			WHEN 19	=>	var_Arst := sig_uatz + ( var_iea * CONV_INTEGER(KP) )/64 + ( CONV_INTEGER(Arin) * CONV_INTEGER(KR) )/64 ;
						var_Brst := sig_ubtz + ( var_ieb * CONV_INTEGER(KP) )/64 + ( CONV_INTEGER(Brin) * CONV_INTEGER(KR) )/64 ;
						var_Crst := sig_uctz + ( var_iec * CONV_INTEGER(KP) )/64 + ( CONV_INTEGER(Crin) * CONV_INTEGER(KR) )/64 ;
						IF(var_Arst>=9980) 	 	THEN	atz<=CONV_STD_LOGIC_VECTOR(9980,16);
						ELSIF(var_Arst<=-9980) 	THEN	atz<=CONV_STD_LOGIC_VECTOR(-9980,16);
						ELSE							atz<=CONV_STD_LOGIC_VECTOR(var_Arst,16);
						END IF;
						IF(var_Brst>=9980) 	 	THEN	btz<=CONV_STD_LOGIC_VECTOR(9980,16);
						ELSIF(var_Brst<=-9980) 	THEN	btz<=CONV_STD_LOGIC_VECTOR(-9980,16);
						ELSE							btz<=CONV_STD_LOGIC_VECTOR(var_Brst,16);
						END IF;		
						IF(var_Crst>=9980) 	 	THEN	ctz<=CONV_STD_LOGIC_VECTOR(9980,16);
						ELSIF(var_Crst<=-9980) 	THEN	ctz<=CONV_STD_LOGIC_VECTOR(-9980,16);
						ELSE							ctz<=CONV_STD_LOGIC_VECTOR(var_Crst,16);
						END IF;	
						Step:=20;						
-------------------------------------------------------电流控制----------------------------------------------------------------						
						
			WHEN 20=>	IF(Index=NUMD-1)		THEN	Index:=0;
						ELSE							Index:=Index+1;
						END IF;
						Step:=21;	
			WHEN 21 =>	IF(sig_ADover = '0')	THEN	
							Step:=0;		CLKAD<='0';			
						END IF;
			WHEN OTHERS =>	NULL;
		END CASE;
	END IF;	
END PROCESS P_PQCON;

sig_PQiA<=(sig_PQ1u*sig_PorQ)/(sig_PQu2rst/65536);
sig_PQiB<=(sig_PQ2u*sig_PorQ)/(sig_PQu2rst/65536);
						
sig_rstA<=(sig_PQiA*13377)/16384;		--sqrt(2/3)=13377/16384;sqrt(2/3)/2=6689/16384;sqrt(2)/2=11585/16384
sig_rstB<=(-sig_PQiA*6689+sig_PQiB*11585)/16384;
sig_rstC<=(-sig_PQiA*6689-sig_PQiB*11585)/16384;

For_Ulpf:RAM_32_2048 PORT map(
			aclr	=>	sig_RES,
			address	=>	addrQdt,
			clock	=>	CLKram,
			data	=>	FFUndt,
			wren	=>	'1',
			q		=>	FFUodt);				


	


			
END BEHAV;