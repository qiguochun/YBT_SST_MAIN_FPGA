LIBRARY ieee;
USE ieee.std_logic_1164.all;

ENTITY IO_Detect IS
    PORT (
        RES  : IN  STD_LOGIC;
        CLK  : IN  STD_LOGIC;
        DIN  : IN  STD_LOGIC;
        DOUT : OUT STD_LOGIC
    );
END IO_Detect;


ARCHITECTURE BEHAV OF IO_Detect IS

    -- 外部异步输入两级同步
    SIGNAL din_sync_1 : STD_LOGIC := '0';
    SIGNAL din_sync_2 : STD_LOGIC := '0';

BEGIN

    PROCESS(CLK, RES)

        VARIABLE cnt   : INTEGER RANGE 0 TO 29999 := 0;
        VARIABLE d_mid : STD_LOGIC := '0';

    BEGIN

        IF RES = '1' THEN

            din_sync_1 <= '0';
            din_sync_2 <= '0';

            DOUT  <= '0';
            cnt   := 0;
            d_mid := '0';

        ELSIF rising_edge(CLK) THEN

            -- 外部输入两级同步
            din_sync_1 <= DIN;
            din_sync_2 <= din_sync_1;

            -- 原有双向去抖逻辑
            IF din_sync_2 /= d_mid THEN

                IF cnt = 29999 THEN

                    d_mid := din_sync_2;
                    cnt   := 0;
                    DOUT  <= d_mid;

                ELSE

                    cnt := cnt + 1;

                END IF;

            ELSE

                cnt := 0;

            END IF;

        END IF;

    END PROCESS;

END BEHAV;