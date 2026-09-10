LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.std_logic_arith.all;
USE ieee.std_logic_signed.all;

ENTITY TEST_CON IS
	PORT(
		RES	:	in std_logic;
		CLK	:	in std_logic;
		HARM:	in std_logic_vector(15 downto 0);
		ua	:	out std_logic_vector(15 downto 0);
		ub	:	out std_logic_vector(15 downto 0);
		uc	:	out std_logic_vector(15 downto 0);
		ia	:	out std_logic_vector(15 downto 0);
		ib	:	out std_logic_vector(15 downto 0);
		ic	:	out std_logic_vector(15 downto 0)
		);
end TEST_CON;

architecture behav of TEST_CON is

CONSTANT NumD :   INTEGER := 2048;

component TEST_sinwt is
	port(
			clkin	:	in std_logic;
			addr	:	in std_logic_vector(15 downto 0);  
			modu	:	in std_logic_vector(15 downto 0);  
			sino 	: 	out std_logic_vector(15 downto 0)          
            );
end component;

signal	addrua	:	 std_logic_vector(15 downto 0):="0000000000000000";
signal	addrub	:	 std_logic_vector(15 downto 0):="0000000000000000";
signal	addruc	:	 std_logic_vector(15 downto 0):="0000000000000000";

signal	addria	:	 std_logic_vector(15 downto 0):="0000000000000000";
signal	addrib	:	 std_logic_vector(15 downto 0):="0000000000000000";
signal	addric	:	 std_logic_vector(15 downto 0):="0000000000000000";

begin

--address
process(res,clk)
	variable addrua_mid:integer range -8191 to 8191:=0;
	variable addrub_mid:integer range -8191 to 8191:=0;
	variable addruc_mid:integer range -8191 to 8191:=0;
	
	variable addria_mid:integer range -8191 to 8191:=0;
	variable addrib_mid:integer range -8191 to 8191:=0;
	variable addric_mid:integer range -8191 to 8191:=0;
	
	begin
	
	if(res='1') then
		addrua_mid:=3*NumD/4;				addrub_mid:=3*NumD/4+NumD*2/3-NumD;				addruc_mid:=3*NumD/4+NumD/3-NumD;
		addria_mid:=3*NumD/4+1*NumD/6;		addrib_mid:=3*NumD/4+NumD*2/3-NumD+1*NumD/6;		addric_mid:=3*NumD/4+NumD/3-NumD+1*NumD/6;
	elsif(clk'event and clk='1')	then	
		if(addrua_mid=NumD) then			addrua_mid:=1;
		else								addrua_mid:=addrua_mid+1;
		end if;
		addrua<=conv_std_logic_vector(addrua_mid,16);
		if(addrub_mid=NumD) then			addrub_mid:=1;
		else								addrub_mid:=addrub_mid+1;
		end if;
		addrub<=conv_std_logic_vector(addrub_mid,16);
		if(addruc_mid=NumD) then			addruc_mid:=1;
		else								addruc_mid:=addruc_mid+1;
		end if;
		addruc<=conv_std_logic_vector(addruc_mid,16);
	
		
		if(addria_mid>NumD-CONV_INTEGER(HARM)) then	addria_mid:=addria_mid+CONV_INTEGER(HARM)-NumD;
		else											addria_mid:=addria_mid+CONV_INTEGER(HARM);
		end if;
		addria<=conv_std_logic_vector(addria_mid,16);
		if(addrib_mid>NumD-CONV_INTEGER(HARM)) then	addrib_mid:=addrib_mid+CONV_INTEGER(HARM)-NumD;
		else											addrib_mid:=addrib_mid+CONV_INTEGER(HARM);
		end if;
		addrib<=conv_std_logic_vector(addrib_mid,16);	
		if(addric_mid>NumD-CONV_INTEGER(HARM)) then	addric_mid:=addric_mid+CONV_INTEGER(HARM)-NumD;
		else											addric_mid:=addric_mid+CONV_INTEGER(HARM);
		end if;
		addric<=conv_std_logic_vector(addric_mid,16);	
	end if;
	
end process;

outusa:TEST_sinwt port map(
			clkin=>clk,
			addr=>addrua,
			modu=>conv_std_logic_vector(1400,16),
			sino=>ua);
outusb:TEST_sinwt port map(
			clkin=>clk,
			addr=>addrub,
			modu=>conv_std_logic_vector(1400,16),
			sino=>ub);			
outusc:TEST_sinwt port map(
			clkin=>clk,
			addr=>addruc,
			modu=>conv_std_logic_vector(1400,16),
			sino=>uc);
outiba:TEST_sinwt port map(
			clkin=>clk,
			addr=>addria,
			modu=>conv_std_logic_vector(1324,16),
			sino=>ia);
outibb:TEST_sinwt port map(
			clkin=>clk,
			addr=>addrib,
			modu=>conv_std_logic_vector(1324,16),
			sino=>ib);			
outibc:TEST_sinwt port map(
			clkin=>clk,
			addr=>addric,
			modu=>conv_std_logic_vector(1324,16),
			sino=>ic);					
end behav;