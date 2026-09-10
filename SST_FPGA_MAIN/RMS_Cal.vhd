LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.all;
USE IEEE.STD_LOGIC_arith.all;
USE IEEE.STD_LOGIC_signed.all;

ENTITY RMS_Cal IS
	PORT(
			RES  :  IN STD_LOGIC;
			CLKIN:  IN STD_LOGIC;
			START:  IN STD_LOGIC;
			DtI  :  IN STD_LOGIC_VECTOR(15 DOWNTO 0);
			DtO  :  OUT STD_LOGIC_VECTOR(15 DOWNTO 0)		
			);
END RMS_Cal;

ARCHITECTURE BEHAV OF RMS_Cal IS

CONSTANT NUMD : INTEGER	:=2048;
CONSTANT NUMW : INTEGER	:=11;		--11:2048;10:1024

---------------------------COMPONENT--------------------------------------
SIGNAL sig_CLKsqrt	:	STD_LOGIC:='0';
SIGNAL sig_addrsqrt	: 	STD_LOGIC_VECTOR(NUMW-1 DOWNTO 0):=(OTHERS=>'0');
SIGNAL sig_Nsqrt,sig_Osqrt : STD_LOGIC_VECTOR(19 DOWNTO 0):=(OTHERS=>'0');
COMPONENT RAM1_20_2048
	PORT
	(
		aclr	: IN STD_LOGIC  := '0';
		address	: IN STD_LOGIC_VECTOR (10 DOWNTO 0);
		clock	: IN STD_LOGIC  := '1';
		data	: IN STD_LOGIC_VECTOR (19 DOWNTO 0);
		wren	: IN STD_LOGIC ;
		q		: OUT STD_LOGIC_VECTOR (19 DOWNTO 0)
	);
END COMPONENT;

SIGNAL sig_SQRTi	:	STD_LOGIC_VECTOR(31 downto 0):="00000000000000000000000000000000";
SIGNAL sig_SQRTo	:	STD_LOGIC_VECTOR(15 downto 0):="0000000000000000";
COMPONENT SQRT_32
	PORT
	(
		radical	: 	IN STD_LOGIC_VECTOR (31 DOWNTO 0);
		q		: 	OUT STD_LOGIC_VECTOR (15 DOWNTO 0);
		remainder: 	OUT STD_LOGIC_VECTOR (16 DOWNTO 0)
	);
END COMPONENT;
---------------------------COMPONENT--------------------------------------

BEGIN

Main:PROCESS(RES,CLKIN)
	VARIABLE Index 		:	INTEGER RANGE 0 TO NumD-1:=0;
	VARIABLE Step	 	:	INTEGER RANGE 0 TO 15:=0;
	VARIABLE var_mdt 	:	INTEGER RANGE -524287 TO 524287:=0;
	VARIABLE var_adddt	:	INTEGER RANGE -2147483647 TO 2147483647:=0;		
	BEGIN
	IF(RES='1') THEN
		sig_CLKsqrt<='0';			sig_addrsqrt<=(OTHERS=>'0');		sig_Nsqrt<=(OTHERS=>'0');
		sig_SQRTi<=(OTHERS=>'0');	DtO<=(OTHERS=>'0');	
		Index:=0; 					Step:=0;			var_mdt:=0;			var_adddt:=0;												
	ELSIF(CLKIN'EVENT AND CLKIN='1') THEN
		CASE Step IS
			WHEN  0	=>	IF(START='1')	THEN
							var_mdt:=(CONV_INTEGER(DtI)*CONV_INTEGER(DtI))/2048;
							IF(var_mdt>524287)		THEN	sig_Nsqrt<=CONV_STD_LOGIC_VECTOR(524287,20);
							ELSIF(var_mdt<-524287)  THEN	sig_Nsqrt<=CONV_STD_LOGIC_VECTOR(-524287,20);
							ELSE							sig_Nsqrt<=CONV_STD_LOGIC_VECTOR(var_mdt,20);
							END IF;							
							sig_addrsqrt<=CONV_STD_LOGIC_VECTOR(Index,NUMW);	
							DtO<=sig_SQRTo;						
							Step:=1;
						END IF;
							
			WHEN  1 => 	Step:=2;
			WHEN  2 => 	Step:=3;	
			WHEN  3 => 	sig_CLKsqrt<='1';
						Step:=4;
						
			WHEN  4	=> 	Step:=5;			
			WHEN  5 => 	Step:=6;
			WHEN  6 => 	sig_CLKsqrt<='0';
						var_adddt:=var_adddt-CONV_INTEGER(sig_Osqrt)+var_mdt;
						sig_SQRTi<=CONV_STD_LOGIC_VECTOR(var_adddt,32);
						Step:=7;
						
			WHEN  7	=> 	IF(Index=NumD-1)		THEN		Index:=0;
						ELSE								Index:=Index+1;
						END IF;
						Step:=8;

			WHEN 8	 => IF(START = '0')			THEN								
							Step:=0;
						END IF;
							
			WHEN OTHERS =>	NULL;
		END CASE;
	END IF;	
END PROCESS Main;


RAM20:RAM1_20_2048 PORT map(
			aclr	=>	RES,
			address	=>	sig_addrsqrt,
			clock	=>	sig_CLKsqrt,
			data	=>	sig_Nsqrt,
			wren	=>	'1',
			q		=>	sig_Osqrt);
			
SQRT32:SQRT_32 PORT map(
			radical	=>	sig_SQRTi,
			q	=>	sig_SQRTo);

END BEHAV;