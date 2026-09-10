LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.all;
USE IEEE.STD_LOGIC_arith.all;
USE IEEE.STD_LOGIC_signed.all;

ENTITY lg_kzzsc IS
	PORT(
		Reset	:	IN STD_LOGIC;
		CLKIN	:	IN STD_LOGIC;
		Ressig	:	IN STD_LOGIC;
		Zgz		:	IN STD_LOGIC;	
		Hwork	:	IN STD_LOGIC;
		Dsoft	:	IN STD_LOGIC;		
		Dwork	:	IN STD_LOGIC;
		Idzl	:	IN STD_LOGIC_VECTOR(15 DOWNTO 0);	
		P0ra	:	IN STD_LOGIC_VECTOR(15 DOWNTO 0);
		P1ra	:	IN STD_LOGIC_VECTOR(15 DOWNTO 0);
		llcduty: IN STD_LOGIC_VECTOR(15 DOWNTO 0);
		conb	 :	OUT STD_LOGIC_VECTOR(51 DOWNTO 0)
		);
END ENTITY;

ARCHITECTURE BEHAV OF lg_kzzsc IS
BEGIN
PROCESS(Reset,CLKIN)
	BEGIN
	IF(Reset='1') THEN
		conb(51 DOWNTO 47)<="10100";	
		conb(46 DOWNTO 42)<="10100";
		conb(41 DOWNTO 29)<=(OTHERS=>'0');
		conb(28 DOWNTO 16)<=(OTHERS=>'0');			
		conb(15 DOWNTO 0) <=(OTHERS=>'0');
	ELSIF(CLKIN'EVENT AND CLKIN='1') THEN
		IF(Ressig='1')		THEN	--清故障
			conb(51 DOWNTO 47)<="01001";	--清故障
			conb(46 DOWNTO 42)<="10100";	--D闭锁
		ELSIF(Zgz='1') 	  	THEN	--重故障
			conb(51 DOWNTO 47)<="10100";	--H闭锁	
			conb(46 DOWNTO 42)<="10100";	--D闭锁			
		ELSE
	-----------------------------------------------
			IF(Hwork = '1')	THEN
				conb(51 DOWNTO 47)<="11010";--H工作
			ELSE
				conb(51 DOWNTO 47)<="10100";--H闭锁
			END IF;
	-----------------------------------------------			
			IF(Dsoft = '1')	THEN
				conb(46 DOWNTO 42)<="10011";--D软启
			ELSIF(Dwork = '1')	THEN
				conb(46 DOWNTO 42)<="11010";--D工作			
			ELSE
				conb(46 DOWNTO 42)<="10100";--D闭锁
			END IF;			
	-----------------------------------------------	
		END IF;
		conb(41 DOWNTO 29)<=Idzl(15 DOWNTO 3);
		conb(28 DOWNTO 16)<=P0ra(12 DOWNTO 0);
		conb(15 DOWNTO 0) <=P1ra;
	END IF;
END PROCESS;
END behav;