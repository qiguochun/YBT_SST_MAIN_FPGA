LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.std_logic_arith.all;
USE ieee.std_logic_signed.all;

ENTITY dc_HBCON IS
	PORT(
			RESET	:	IN  STD_LOGIC;
			CLKIN	:	IN  STD_LOGIC;
			START	:	IN  STD_LOGIC;
			FH_GX	:	IN  STD_LOGIC;--‘1’=C；‘0’=L
						
			DC1H	:	IN  STD_LOGIC_VECTOR(15 DOWNTO 0);
			DC2H	:	IN  STD_LOGIC_VECTOR(15 DOWNTO 0);
			DC3H	:	IN  STD_LOGIC_VECTOR(15 DOWNTO 0);
			DC4H	:	IN  STD_LOGIC_VECTOR(15 DOWNTO 0);
			DC5H	:	IN  STD_LOGIC_VECTOR(15 DOWNTO 0);
			DC6H	:	IN  STD_LOGIC_VECTOR(15 DOWNTO 0);
			DC7H	:	IN  STD_LOGIC_VECTOR(15 DOWNTO 0);
			
			Udhe	:	IN  STD_LOGIC_VECTOR(15 DOWNTO 0);			
			U1I		:	IN  STD_LOGIC_VECTOR(15 DOWNTO 0);
			U2I		:	IN  STD_LOGIC_VECTOR(15 DOWNTO 0);
			KPall	:	IN  STD_LOGIC_VECTOR(15 DOWNTO 0);
			KIall	:	IN  STD_LOGIC_VECTOR(15 DOWNTO 0);			
			KPind	:	IN  STD_LOGIC_VECTOR(15 DOWNTO 0);
			KIind	:	IN  STD_LOGIC_VECTOR(15 DOWNTO 0);
			
			Perr	:	OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
			RST1H	:	OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
			RST2H	:	OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
			RST3H	:	OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
			RST4H	:	OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
			RST5H	:	OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
			RST6H	:	OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
			RST7H	:	OUT STD_LOGIC_VECTOR(15 DOWNTO 0)		
			);
END dc_HBCON;

ARCHITECTURE BEHAV OF dc_HBCON IS

SIGNAL CHall_ek,CH_ek,sig_VU:	INTEGER RANGE -65535 TO 65535:=0;
SIGNAL CHall_yk1d,CHall_yk	:	INTEGER RANGE -2147483647  TO 2147483647 :=0;
SIGNAL CH_yk1d,CH_yk		:	INTEGER RANGE -2147483647 TO 2147483647:=0; 
SIGNAL CHall_uk,CH_uk		:	INTEGER RANGE -1048575 TO 1048575:=0; 

BEGIN

Main:PROCESS(RESET,CLKIN)
VARIABLE Step  : INTEGER RANGE 0 TO 63:=0;
VARIABLE var_dcave:INTEGER RANGE -65535 TO 65535:=0;
VARIABLE CHall_ek_tmp,CH1_ek,CH2_ek,  CH3_ek,CH4_ek,CH5_ek,CH6_ek,CH7_ek	: INTEGER RANGE -65535 TO 65535:=0;
VARIABLE CH1_yk1d,CH2_yk1d,CH3_yk1d,CH4_yk1d,CH5_yk1d,CH6_yk1d,CH7_yk1d		: INTEGER RANGE -2147483647  TO 2147483647 :=0;
BEGIN
	IF(RESET='1') THEN
		CHall_ek<=0;			CH_ek<=0;				sig_VU<=0;				CHall_yk1d<=0;			CH_yk1d<=0;	
		Perr<=(OTHERS=>'0');	
		RST1H<=(OTHERS=>'0');	RST2H<=(OTHERS=>'0');	RST3H<=(OTHERS=>'0');	RST4H<=(OTHERS=>'0');	RST5H<=(OTHERS=>'0');	RST6H<=(OTHERS=>'0');	RST7H<=(OTHERS=>'0');
		Step:=0;				var_dcave:=0;			CHall_ek_tmp:=0;										
		CH1_ek:=0;				CH2_ek:=0;				CH3_ek:=0;				CH4_ek:=0;				CH5_ek:=0;				CH6_ek:=0;				CH7_ek:=0;				
		CH1_yk1d:=0;			CH2_yk1d:=0;			CH3_yk1d:=0;			CH4_yk1d:=0;			CH5_yk1d:=0;			CH6_yk1d:=0;			CH7_yk1d:=0;			
	ELSIF(CLKIN'EVENT AND CLKIN='1') THEN
		CASE Step IS
			WHEN  0 =>	IF(START = '1')	THEN						
							--var_dcave:=(CONV_INTEGER(DC1H)+CONV_INTEGER(DC2H)+CONV_INTEGER(DC3H)+CONV_INTEGER(DC4H)+CONV_INTEGER(DC5H)+CONV_INTEGER(DC6H)+CONV_INTEGER(DC7H))/7;
							var_dcave:=(CONV_INTEGER(DC3H)+CONV_INTEGER(DC4H))/2;
							CHall_ek_tmp:=CONV_INTEGER(Udhe)-var_dcave;
							CH1_ek:=var_dcave-CONV_INTEGER(DC1H);		CH2_ek:=var_dcave-CONV_INTEGER(DC2H);		CH3_ek:=var_dcave-CONV_INTEGER(DC3H);
							CH4_ek:=var_dcave-CONV_INTEGER(DC4H);		CH5_ek:=var_dcave-CONV_INTEGER(DC5H);		CH6_ek:=var_dcave-CONV_INTEGER(DC6H);
							CH7_ek:=var_dcave-CONV_INTEGER(DC7H);		
							IF(CHall_ek_tmp>=2047) 		THEN		CHall_ek<=2047;
							ELSIF(CHall_ek_tmp<=-2047)	THEN		CHall_ek<=-2047;
							ELSE									CHall_ek <= CHall_ek_tmp;
							END IF;
								
							IF(CH1_ek>=2047) 			THEN		CH1_ek:=2047;
							ELSIF(CH1_ek<=-2047)		THEN		CH1_ek:=-2047;
							END IF;								
							IF(CH2_ek>=2047) 			THEN		CH2_ek:=2047;
							ELSIF(CH2_ek<=-2047)		THEN		CH2_ek:=-2047;
							END IF;
							IF(CH3_ek>=2047) 			THEN		CH3_ek:=2047;
							ELSIF(CH3_ek<=-2047)		THEN		CH3_ek:=-2047;
							END IF;							
							IF(CH4_ek>=2047) 			THEN		CH4_ek:=2047;
							ELSIF(CH4_ek<=-2047)		THEN		CH4_ek:=-2047;
							END IF;
								
							IF(CH5_ek>=2047) 			THEN		CH5_ek:=2047;
							ELSIF(CH5_ek<=-2047)		THEN		CH5_ek:=-2047;
							END IF;								
							IF(CH6_ek>=2047) 			THEN		CH6_ek:=2047;
							ELSIF(CH6_ek<=-2047)		THEN		CH6_ek:=-2047;
							END IF;
							IF(CH7_ek>=2047) 			THEN		CH7_ek:=2047;
							ELSIF(CH7_ek<=-2047)		THEN		CH7_ek:=-2047;
							END IF;							
								
							IF(FH_GX='1') THEN
								sig_VU<=CONV_INTEGER(U1I)-CONV_INTEGER(U2I);
							ELSE
								sig_VU<=CONV_INTEGER(U2I)-CONV_INTEGER(U1I);
							END IF;	
							
							Step:=1;
						END IF;
						
			WHEN  1 =>  Step:=2;										--ALL												
			WHEN  2 =>  Step:=3;			
			WHEN  3 =>  Step:=4;						
			WHEN  4	=> 	CHall_yk1d<=CHall_yk;								
					    IF(CHall_uk>2047) THEN		Perr<=CONV_STD_LOGIC_VECTOR(2047,16);
					    ELSIF(CHall_uk<-2047) THEN	Perr<=CONV_STD_LOGIC_VECTOR(-2047,16);
					    ELSE 						Perr<=CONV_STD_LOGIC_VECTOR(CHall_uk,16);
					    END IF;
						Step:=5;						 
					   
			WHEN  5 =>  CH_ek<=CH1_ek;				CH_yk1d<=CH1_yk1d;--HB1						
						Step:=6;						
			WHEN  6 =>  Step:=7;			
			WHEN  7 =>  Step:=8;			
			WHEN  8	=> 	CH1_yk1d:=CH_yk;
						IF(CH_uk>1023) 	 THEN		RST1H<=CONV_STD_LOGIC_VECTOR(1023,16);
						ELSIF(CH_uk<-1023) THEN		RST1H<=CONV_STD_LOGIC_VECTOR(-1023,16);
						ELSE 						RST1H<=CONV_STD_LOGIC_VECTOR(CH_uk,16);
						END IF;
						Step:=9;

			WHEN  9 =>  CH_ek<=CH2_ek;				CH_yk1d<=CH2_yk1d;--HB2
						Step:=10;						
			WHEN 10 =>  Step:=11;			
			WHEN 11 =>  Step:=12;			
			WHEN 12=> 	CH2_yk1d:=CH_yk;
						IF(CH_uk>1023) 	 THEN		RST2H<=CONV_STD_LOGIC_VECTOR(1023,16);
						ELSIF(CH_uk<-1023) THEN		RST2H<=CONV_STD_LOGIC_VECTOR(-1023,16);
						ELSE 						RST2H<=CONV_STD_LOGIC_VECTOR(CH_uk,16);
						END IF;
						Step:=13;

			WHEN 13 =>  CH_ek<=CH3_ek;				CH_yk1d<=CH3_yk1d;--HB3
						Step:=14;						
			WHEN 14 =>  Step:=15;			
			WHEN 15 =>  Step:=16;			
			WHEN 16 => 	CH3_yk1d:=CH_yk;
						IF(CH_uk>1023) 	  THEN		RST3H<=CONV_STD_LOGIC_VECTOR(1023,16);
						ELSIF(CH_uk<-1023) THEN		RST3H<=CONV_STD_LOGIC_VECTOR(-1023,16);
						ELSE 						RST3H<=CONV_STD_LOGIC_VECTOR(CH_uk,16);
						END IF;
						Step:=17;

			WHEN 17 =>  CH_ek<=CH4_ek;				CH_yk1d<=CH4_yk1d;--HB4
						Step:=18;						
			WHEN 18 =>  Step:=19;			
			WHEN 19 =>  Step:=20;			
			WHEN 20 => 	CH4_yk1d:=CH_yk;
						IF(CH_uk>1023) 	  THEN		RST4H<=CONV_STD_LOGIC_VECTOR(1023,16);
						ELSIF(CH_uk<-1023) THEN		RST4H<=CONV_STD_LOGIC_VECTOR(-1023,16);
						ELSE 						RST4H<=CONV_STD_LOGIC_VECTOR(CH_uk,16);
						END IF;
						Step:=21;

			WHEN 21 =>  CH_ek<=CH5_ek;				CH_yk1d<=CH5_yk1d;--HB5
						Step:=22;						
			WHEN 22 =>  Step:=23;			
			WHEN 23 =>  Step:=24;			
			WHEN 24 => 	CH5_yk1d:=CH_yk;
						IF(CH_uk>1023) 	  THEN		RST5H<=CONV_STD_LOGIC_VECTOR(1023,16);
						ELSIF(CH_uk<-1023) THEN		RST5H<=CONV_STD_LOGIC_VECTOR(-1023,16);
						ELSE 						RST5H<=CONV_STD_LOGIC_VECTOR(CH_uk,16);
						END IF;
						Step:=25;

			WHEN 25 =>  CH_ek<=CH6_ek;				CH_yk1d<=CH6_yk1d;--HB6
						Step:=26;						
			WHEN 26 =>  Step:=27;			
			WHEN 27 =>  Step:=28;			
			WHEN 28 => 	CH6_yk1d:=CH_yk;
						IF(CH_uk>1023) 	  THEN		RST6H<=CONV_STD_LOGIC_VECTOR(1023,16);
						ELSIF(CH_uk<-1023) THEN		RST6H<=CONV_STD_LOGIC_VECTOR(-1023,16);
						ELSE 						RST6H<=CONV_STD_LOGIC_VECTOR(CH_uk,16);
						END IF;
						Step:=29;

			WHEN 29 =>  CH_ek<=CH7_ek;				CH_yk1d<=CH7_yk1d;--HB7
						Step:=30;						
			WHEN 30 =>  Step:=31;			
			WHEN 31 =>  Step:=32;			
			WHEN 32 => 	CH7_yk1d:=CH_yk;
						IF(CH_uk>1023) 	  THEN		RST7H<=CONV_STD_LOGIC_VECTOR(1023,16);
						ELSIF(CH_uk<-1023) THEN		RST7H<=CONV_STD_LOGIC_VECTOR(-1023,16);
						ELSE 						RST7H<=CONV_STD_LOGIC_VECTOR(CH_uk,16);
						END IF;
						Step:=33;	
			
			WHEN 33=>	IF(START='0')	THEN
							Step:=0;
						END IF;
							
			WHEN OTHERS =>	NULL;
		END CASE;
	END IF;	
END PROCESS Main;

CHall_yk <= 2000000000  WHEN (CHall_yk1d + CONV_INTEGER(KIall)*CHall_ek) > 2000000000  	ELSE
         -2000000000 	WHEN (CHall_yk1d + CONV_INTEGER(KIall)*CHall_ek) < -2000000000  ELSE
         CHall_yk1d + CONV_INTEGER(KIall)*CHall_ek; 
	 
CH_yk <= 16777215 	WHEN (CH_yk1d + CONV_INTEGER(KIind)*CH_ek) > 16777215 	ELSE
         -16777215	WHEN (CH_yk1d + CONV_INTEGER(KIind)*CH_ek) < -16777215 	ELSE
         CH_yk1d + CONV_INTEGER(KIind)*CH_ek; 
		 
CHall_uk <= -(CONV_INTEGER(KPall)*CHall_ek*2048 + CHall_yk/32) /65536;			--*2

CH_uk <= ( ((CONV_INTEGER(KPind)*CH_ek*2048 + CH_yk/32) /2048) *(sig_VU/4)  )/262144;


END BEHAV;