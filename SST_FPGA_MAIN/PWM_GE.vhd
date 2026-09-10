LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.std_logic_arith.all;
USE ieee.std_logic_signed.all;

ENTITY PWM_GE IS
	PORT(
		CLKIN	:	IN STD_LOGIC;
		CLK128M	:	IN STD_LOGIC;
		START	:	IN STD_LOGIC;
		RES		:	IN STD_LOGIC;
		Ui_aTZ,Ui_bTZ,Ui_cTZ	:	IN STD_LOGIC_VECTOR(15 downto 0);		
		DCa1TZ,DCa2TZ,DCa3TZ,DCa4TZ,DCa5TZ,DCa6TZ,DCa7TZ	:	IN STD_LOGIC_VECTOR(15 downto 0);
		DCb1TZ,DCb2TZ,DCb3TZ,DCb4TZ,DCb5TZ,DCb6TZ,DCb7TZ	:	IN STD_LOGIC_VECTOR(15 downto 0);		
		DCc1TZ,DCc2TZ,DCc3TZ,DCc4TZ,DCc5TZ,DCc6TZ,DCc7TZ	:	IN STD_LOGIC_VECTOR(15 downto 0);
		
		PWM1A,	PWM_1A,	 PWM1B,	 PWM_1B,  PWM1C,  PWM_1C,  PWM2A,  PWM_2A,	PWM2B,	PWM_2B,  PWM2C,  PWM_2C,  PWM3A,  PWM_3A,  PWM3B,  PWM_3B,	PWM3C,	PWM_3C  : 	OUT STD_LOGIC;
		PWM4A,	PWM_4A,	 PWM4B,	 PWM_4B,  PWM4C,  PWM_4C,  PWM5A,  PWM_5A,	PWM5B,	PWM_5B,  PWM5C,  PWM_5C,  PWM6A,  PWM_6A,  PWM6B,  PWM_6B,	PWM6C,	PWM_6C	: 	OUT STD_LOGIC;
		PWM7A,	PWM_7A,	 PWM7B,	 PWM_7B,  PWM7C,  PWM_7C	: 	OUT STD_LOGIC;
		TXCLK	:	OUT STD_LOGIC		
		);
END ENTITY;

ARCHITECTURE BEHAV OF PWM_GE IS

CONSTANT MAXCNT	:	INTEGER	:=10667;
CONSTANT MDUCNT	:	INTEGER	:=7680;
	
SIGNAL TR1C,TR2C,TR3C,TR4C,TR5C,TR6C,TR7C	: INTEGER RANGE -65535 TO 65535 :=0;
SIGNAL var1_amvw, var1_bmvw, var1_cmvw, var2_amvw, var2_bmvw, var2_cmvw, var3_amvw, var3_bmvw, var3_cmvw:INTEGER RANGE -16383 TO 16383:=0;
SIGNAL var4_amvw, var4_bmvw, var4_cmvw, var5_amvw, var5_bmvw, var5_cmvw, var6_amvw, var6_bmvw, var6_cmvw:INTEGER RANGE -16383 TO 16383:=0;
SIGNAL var7_amvw, var7_bmvw, var7_cmvw:INTEGER RANGE -16383 TO 16383:=0;

SIGNAL start_sync1 : STD_LOGIC := '0';
SIGNAL start_sync2 : STD_LOGIC := '0';
SIGNAL start_last  : STD_LOGIC := '0';
SIGNAL start_last2 : STD_LOGIC := '0';
SIGNAL txclk_reg : STD_LOGIC := '0';

BEGIN

TXCLK <= txclk_reg;

Trcout:PROCESS(RES,CLK128M)
	VARIABLE updown1a,updown2a,updown3a,updown4a,updown5a,updown6a,updown7a	:	STD_LOGIC:='0';
	VARIABLE cnt1a,   cnt2a,   cnt3a,   cnt4a,   cnt5a,   cnt6a,   cnt7a	:	INTEGER RANGE -65535  TO 65535 :=0;
	BEGIN
	IF(RES='1')		THEN
		updown1a:='0';		cnt1a:=MAXCNT;
		updown2a:='0';		cnt2a:=(MAXCNT*5)/7;
		--updown3a:='0';		cnt3a:=(MAXCNT*3)/7;
		--updown4a:='0';		cnt4a:=(MAXCNT*1)/7;
		updown5a:='0';		cnt5a:=-(MAXCNT*1)/7;
		updown6a:='0';		cnt6a:=-(MAXCNT*3)/7;
		updown7a:='0';		cnt7a:=-(MAXCNT*5)/7;
		updown3a:='0';		cnt3a:=MAXCNT;
		updown4a:='0';		cnt4a:=0;		
	ELSIF rising_edge(CLK128M)	THEN
		IF(cnt1a>=MAXCNT)		THEN	updown1a:='0';			--1
		ELSIF(cnt1a<=-MAXCNT)	THEN	updown1a:='1';
		END IF;		
		IF(updown1a='1')		THEN	cnt1a:=cnt1a+1;									
		ELSE							cnt1a:=cnt1a-1;
		END IF; 
		
		IF(cnt2a>=MAXCNT)		THEN	updown2a:='0';			--2
		ELSIF(cnt2a<=-MAXCNT)	THEN	updown2a:='1';
		END IF;		
		IF(updown2a='1')		THEN	cnt2a:=cnt2a+1;									
		ELSE							cnt2a:=cnt2a-1;
		END IF;
		
		IF(cnt3a>=MAXCNT)		THEN	updown3a:='0';			--3
		ELSIF(cnt3a<=-MAXCNT)	THEN	updown3a:='1';
		END IF;		
		IF(updown3a='1')		THEN	cnt3a:=cnt3a+1;									
		ELSE							cnt3a:=cnt3a-1;
		END IF; 
		
		IF(cnt4a>=MAXCNT)		THEN	updown4a:='0';			--4
		ELSIF(cnt4a<=-MAXCNT)	THEN	updown4a:='1';
		END IF;		
		IF(updown4a='1')		THEN	cnt4a:=cnt4a+1;									
		ELSE							cnt4a:=cnt4a-1;
		END IF;
		
		IF(cnt5a>=MAXCNT)		THEN	updown5a:='0';			--5
		ELSIF(cnt5a<=-MAXCNT)	THEN	updown5a:='1';
		END IF;		
		IF(updown5a='1')		THEN	cnt5a:=cnt5a+1;									
		ELSE							cnt5a:=cnt5a-1;
		END IF; 
		
		IF(cnt6a>=MAXCNT)		THEN	updown6a:='0';			--6
		ELSIF(cnt6a<=-MAXCNT)	THEN	updown6a:='1';
		END IF;		
		IF(updown6a='1')		THEN	cnt6a:=cnt6a+1;									
		ELSE							cnt6a:=cnt6a-1;
		END IF;
		
		IF(cnt7a>=MAXCNT)		THEN	updown7a:='0';			--7
		ELSIF(cnt7a<=-MAXCNT)	THEN	updown7a:='1';
		END IF;		
		IF(updown7a='1')		THEN	cnt7a:=cnt7a+1;									
		ELSE							cnt7a:=cnt7a-1;
		END IF;	
	END IF;	
	TR1C<=(cnt1a*MDUCNT)/8192;		
	TR2C<=(cnt2a*MDUCNT)/8192;		
	TR3C<=(cnt3a*MDUCNT)/8192;		
	TR4C<=(cnt4a*MDUCNT)/8192;		
	TR5C<=(cnt5a*MDUCNT)/8192;
	TR6C<=(cnt6a*MDUCNT)/8192;		
	TR7C<=(cnt7a*MDUCNT)/8192;		
END PROCESS Trcout;


MVWGE : PROCESS(RES, CLKIN)
BEGIN
    IF RES = '1' THEN
        start_sync1 <= '0';    start_sync2 <= '0';    start_last  <= '0';
        start_last2 <= '0';
        var1_amvw <= 0;        var1_bmvw <= 0;        var1_cmvw <= 0;
        var2_amvw <= 0;        var2_bmvw <= 0;        var2_cmvw <= 0;
        var3_amvw <= 0;        var3_bmvw <= 0;        var3_cmvw <= 0;
        var4_amvw <= 0;        var4_bmvw <= 0;        var4_cmvw <= 0;
        var5_amvw <= 0;        var5_bmvw <= 0;        var5_cmvw <= 0;
        var6_amvw <= 0;        var6_bmvw <= 0;        var6_cmvw <= 0;
        var7_amvw <= 0;        var7_bmvw <= 0;        var7_cmvw <= 0;
    ELSIF rising_edge(CLKIN) THEN
        start_sync1 <= START;
        start_sync2 <= start_sync1;
        start_last <= start_sync2;
        start_last2 <= start_last;
        IF (start_sync2='1' AND start_last='0') THEN
            var1_amvw <= CONV_INTEGER(Ui_aTZ) + CONV_INTEGER(DCa1TZ);
            var1_bmvw <= CONV_INTEGER(Ui_bTZ) + CONV_INTEGER(DCb1TZ);
            var1_cmvw <= CONV_INTEGER(Ui_cTZ) + CONV_INTEGER(DCc1TZ);

            var2_amvw <= CONV_INTEGER(Ui_aTZ) + CONV_INTEGER(DCa2TZ);
            var2_bmvw <= CONV_INTEGER(Ui_bTZ) + CONV_INTEGER(DCb2TZ);
            var2_cmvw <= CONV_INTEGER(Ui_cTZ) + CONV_INTEGER(DCc2TZ);

            var3_amvw <= CONV_INTEGER(Ui_aTZ) + CONV_INTEGER(DCa3TZ);
            var3_bmvw <= CONV_INTEGER(Ui_bTZ) + CONV_INTEGER(DCb3TZ);
            var3_cmvw <= CONV_INTEGER(Ui_cTZ) + CONV_INTEGER(DCc3TZ);

            var4_amvw <= CONV_INTEGER(Ui_aTZ) + CONV_INTEGER(DCa4TZ);
            var4_bmvw <= CONV_INTEGER(Ui_bTZ) + CONV_INTEGER(DCb4TZ);
            var4_cmvw <= CONV_INTEGER(Ui_cTZ) + CONV_INTEGER(DCc4TZ);

            var5_amvw <= CONV_INTEGER(Ui_aTZ) + CONV_INTEGER(DCa5TZ);
            var5_bmvw <= CONV_INTEGER(Ui_bTZ) + CONV_INTEGER(DCb5TZ);
            var5_cmvw <= CONV_INTEGER(Ui_cTZ) + CONV_INTEGER(DCc5TZ);

            var6_amvw <= CONV_INTEGER(Ui_aTZ) + CONV_INTEGER(DCa6TZ);
            var6_bmvw <= CONV_INTEGER(Ui_bTZ) + CONV_INTEGER(DCb6TZ);
            var6_cmvw <= CONV_INTEGER(Ui_cTZ) + CONV_INTEGER(DCc6TZ);

            var7_amvw <= CONV_INTEGER(Ui_aTZ) + CONV_INTEGER(DCa7TZ);
            var7_bmvw <= CONV_INTEGER(Ui_bTZ) + CONV_INTEGER(DCb7TZ);
            var7_cmvw <= CONV_INTEGER(Ui_cTZ) + CONV_INTEGER(DCc7TZ);
        END IF;
    END IF;
END PROCESS MVWGE;

COMPARE:PROCESS(RES,CLKIN)
	BEGIN
	IF(RES='1')	THEN
		PWM1A  <= '0';  PWM_1A <= '0';  PWM1B  <= '0';  PWM_1B <= '0';  PWM1C  <= '0';  PWM_1C <= '0';
		PWM2A  <= '0';  PWM_2A <= '0';  PWM2B  <= '0';  PWM_2B <= '0';  PWM2C  <= '0';  PWM_2C <= '0';
		PWM3A  <= '0';  PWM_3A <= '0';  PWM3B  <= '0';  PWM_3B <= '0';  PWM3C  <= '0';  PWM_3C <= '0';
		PWM4A  <= '0';  PWM_4A <= '0';  PWM4B  <= '0';  PWM_4B <= '0';  PWM4C  <= '0';  PWM_4C <= '0';
		PWM5A  <= '0';  PWM_5A <= '0';  PWM5B  <= '0';  PWM_5B <= '0';  PWM5C  <= '0';  PWM_5C <= '0';
		PWM6A  <= '0';  PWM_6A <= '0';  PWM6B  <= '0';  PWM_6B <= '0';  PWM6C  <= '0';  PWM_6C <= '0';
		PWM7A  <= '0';  PWM_7A <= '0';  PWM7B  <= '0';  PWM_7B <= '0';  PWM7C  <= '0';  PWM_7C <= '0';	
		txclk_reg <= '0';
	ELSIF rising_edge(CLKIN) THEN
		IF(var1_amvw>=TR1C) 	THEN 	PWM1A <='1';	--1
		ELSE							PWM1A <='0';
		END IF;			
		IF(-var1_amvw>=TR1C) 	THEN 	PWM_1A <='1';
		ELSE 							PWM_1A <='0';
		END IF;						
		IF(var1_bmvw>=TR1C) 	THEN 	PWM1B <='1';
		ELSE							PWM1B <='0';
		END IF;			
		IF(-var1_bmvw>=TR1C) 	THEN 	PWM_1B <='1';
		ELSE 							PWM_1B <='0';
		END IF;						
		IF(var1_cmvw>=TR1C) 	THEN 	PWM1C <='1';
		ELSE							PWM1C <='0';
		END IF;			
		IF(-var1_cmvw>=TR1C) 	THEN 	PWM_1C <='1';
		ELSE 							PWM_1C <='0';
		END IF;		
		
		IF(var2_amvw>=TR2C) 	THEN 	PWM2A <='1';	--2
		ELSE							PWM2A <='0';
		END IF;			
		IF(-var2_amvw>=TR2C) 	THEN 	PWM_2A <='1';
		ELSE 							PWM_2A <='0';
		END IF;						
		IF(var2_bmvw>=TR2C) 	THEN 	PWM2B <='1';
		ELSE							PWM2B <='0';
		END IF;			
		IF(-var2_bmvw>=TR2C) 	THEN 	PWM_2B <='1';
		ELSE 							PWM_2B <='0';
		END IF;						
		IF(var2_cmvw>=TR2C) 	THEN 	PWM2C <='1';
		ELSE							PWM2C <='0';
		END IF;			
		IF(-var2_cmvw>=TR2C) 	THEN 	PWM_2C <='1';
		ELSE 							PWM_2C <='0';
		END IF;			
		
		IF(var3_amvw>=TR3C) 	THEN 	PWM3A <='1';	--3
		ELSE							PWM3A <='0';
		END IF;			
		IF(-var3_amvw>=TR3C) 	THEN 	PWM_3A <='1';
		ELSE 							PWM_3A <='0';
		END IF;						
		IF(var3_bmvw>=TR3C) 	THEN 	PWM3B <='1';
		ELSE							PWM3B <='0';
		END IF;			
		IF(-var3_bmvw>=TR3C) 	THEN 	PWM_3B <='1';
		ELSE 							PWM_3B <='0';
		END IF;						
		IF(var3_cmvw>=TR3C) 	THEN 	PWM3C <='1';
		ELSE							PWM3C <='0';
		END IF;			
		IF(-var3_cmvw>=TR3C) 	THEN 	PWM_3C <='1';
		ELSE 							PWM_3C <='0';
		END IF;						
		
		IF(var4_amvw>=TR4C) 	THEN 	PWM4A <='1';	--4
		ELSE							PWM4A <='0';
		END IF;			
		IF(-var4_amvw>=TR4C) 	THEN 	PWM_4A <='1';
		ELSE 							PWM_4A <='0';
		END IF;						
		IF(var4_bmvw>=TR4C) 	THEN 	PWM4B <='1';
		ELSE							PWM4B <='0';
		END IF;			
		IF(-var4_bmvw>=TR4C) 	THEN 	PWM_4B <='1';
		ELSE 							PWM_4B <='0';
		END IF;						
		IF(var4_cmvw>=TR4C) 	THEN 	PWM4C <='1';
		ELSE							PWM4C <='0';
		END IF;			
		IF(-var4_cmvw>=TR4C) 	THEN 	PWM_4C <='1';
		ELSE 							PWM_4C <='0';
		END IF;							
		
		IF(var5_amvw>=TR5C) 	THEN 	PWM5A <='1';	--5
		ELSE							PWM5A <='0';
		END IF;			
		IF(-var5_amvw>=TR5C) 	THEN 	PWM_5A <='1';
		ELSE 							PWM_5A <='0';
		END IF;						
		IF(var5_bmvw>=TR5C) 	THEN 	PWM5B <='1';
		ELSE							PWM5B <='0';
		END IF;			
		IF(-var5_bmvw>=TR5C) 	THEN 	PWM_5B <='1';
		ELSE 							PWM_5B <='0';
		END IF;						
		IF(var5_cmvw>=TR5C) 	THEN 	PWM5C <='1';
		ELSE							PWM5C <='0';
		END IF;			
		IF(-var5_cmvw>=TR5C) 	THEN 	PWM_5C <='1';
		ELSE 							PWM_5C <='0';
		END IF;							
		
		IF(var6_amvw>=TR6C) 	THEN 	PWM6A <='1';	--6
		ELSE							PWM6A <='0';
		END IF;			
		IF(-var6_amvw>=TR6C) 	THEN 	PWM_6A <='1';
		ELSE 							PWM_6A <='0';
		END IF;						
		IF(var6_bmvw>=TR6C) 	THEN 	PWM6B <='1';
		ELSE							PWM6B <='0';
		END IF;			
		IF(-var6_bmvw>=TR6C) 	THEN 	PWM_6B <='1';
		ELSE 							PWM_6B <='0';
		END IF;						
		IF(var6_cmvw>=TR6C) 	THEN 	PWM6C <='1';
		ELSE							PWM6C <='0';
		END IF;			
		IF(-var6_cmvw>=TR6C) 	THEN 	PWM_6C <='1';
		ELSE 							PWM_6C <='0';
		END IF;							
		
		IF(var7_amvw>=TR7C) 	THEN 	PWM7A <='1';	--7
		ELSE							PWM7A <='0';
		END IF;			
		IF(-var7_amvw>=TR7C) 	THEN 	PWM_7A <='1';
		ELSE 							PWM_7A <='0';
		END IF;						
		IF(var7_bmvw>=TR7C) 	THEN 	PWM7B <='1';
		ELSE							PWM7B <='0';
		END IF;			
		IF(-var7_bmvw>=TR7C) 	THEN 	PWM_7B <='1';
		ELSE 							PWM_7B <='0';
		END IF;						
		IF(var7_cmvw>=TR7C) 	THEN 	PWM7C <='1';
		ELSE							PWM7C <='0';
		END IF;			
		IF(-var7_cmvw>=TR7C) 	THEN 	PWM_7C <='1';
		ELSE 							PWM_7C <='0';
		END IF;	
		-- 保持原来的TXCLK电平形式，仅将上升沿延后一拍，使PWM数据先稳定。
		txclk_reg <= start_sync2 AND start_last AND start_last2;
	END IF;
END PROCESS COMPARE;

END BEHAV;
