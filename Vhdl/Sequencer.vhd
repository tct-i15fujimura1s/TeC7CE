-- Sequencer.vhd
-- 情報電子工学総合実験(CE1)用 TeC CPU の制御部
--
-- (c)2014 - 2019 by Dept. of Computer Science and Electronic Engineering,
--            Tokuyama College of Technology, JAPAN

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

entity Sequencer is
  Port ( Clk   : in  STD_LOGIC;
         -- 入力
         Reset : in  STD_LOGIC;
         OP    : in  STD_LOGIC_VECTOR (3 downto 0);
         Rd    : in  STD_LOGIC_VECTOR (1 downto 0); -- WRはない
         Rx    : in  STD_LOGIC_VECTOR (1 downto 0); -- ダイレクト, G1, G2, イミディエイト
         Flag  : in  STD_LOGIC_VECTOR (2 downto 0); -- CSZ
         Stop  : in  STD_LOGIC;
         -- CPU内部の制御用に出力
         --   レジスタの書き込み制御
         LI    : out  STD_LOGIC;
         LDR   : out  STD_LOGIC;
         LF    : out  STD_LOGIC;
         SPINC : out  STD_LOGIC;
         SPDEC : out  STD_LOGIC;
         PCINC : out  STD_LOGIC;
         LR    : out  STD_LOGIC;
         LPC   : out  STD_LOGIC;
         --   アドレスの計算用
         MA    : out  STD_LOGIC; -- ADD, DR
         DSP   : out  STD_LOGIC; -- '0', DR
         IND   : out  STD_LOGIC_VECTOR (1 downto 0); -- G1, G2, SP, PC
         MD    : out  STD_LOGIC; -- ALU, PC
         -- CPU外部へ出力
         We    : out  STD_LOGIC;
         Halt  : out  STD_LOGIC
         );
end Sequencer;

architecture Behavioral of Sequencer is
  signal Stat  : STD_LOGIC_VECTOR(3  downto 0); -- State
  signal NxtSt : STD_LOGIC_VECTOR(3  downto 0); -- Next State
  signal DecSt : STD_LOGIC_VECTOR(13 downto 0); -- Decoded State
  signal Type1 : STD_LOGIC;                     -- LD/ADD/SUB/CMP/AND/OR/XOR
  signal Jmp   : STD_LOGIC;                     -- JMP
  signal Jz    : STD_LOGIC;                     -- JZ
  signal Jc    : STD_LOGIC;                     -- JC
  signal Jm    : STD_LOGIC;                     -- JM
  signal JmpCnd: STD_LOGIC;                     -- Jmp Condition
  signal Indx  : STD_LOGIC;                     -- Indexed mode
  signal Immd  : STD_LOGIC;                     -- Immediate mode

begin
-- State machine
  with Stat select
    DecSt <= "000000000000001" when "0000", -- fetch
             "000000000000010" when "0001", -- decode
             "000000000000100" when "0010", -- alu1
             "000000000001000" when "0011", -- alu2
             "000000000010000" when "0100", -- st
             "000000000100000" when "0101", -- shift
             "000000001000000" when "0110", -- jmp
             "000000010000000" when "0111", -- call1
             "000000100000000" when "1000", -- call2
             "000001000000000" when "1001", -- call3
             "000010000000000" when "1010", -- ret
             "000100000000000" when "1011", -- push1
             "001000000000000" when "1100", -- push2
             "010000000000000" when "1101", -- pop
             "100000000000000" when others; -- halt

  Type1 <= '1' when OP="0001" or OP="0011" or OP="0100" or -- LD/ADD/SUB
           OP="0101" or OP="0110" or OP="0111" or -- CMP/AND/OR
           OP="1000" else '0';                    -- XOR

  NxtSt <= "0000" when (DecSt(0)='1' and Stop='1') or    -- Stop
                       (DecSt(1)='1' and OP="0000") or   -- NO
                       (DecSt(1)='1' and OP="1010" and JmpCnd='0') or -- JMP
                       DecSt(3)='1' or DecSt(4)='1' or DecSt(5)='1' or -- LD/.../XOR,SHxx,ST
                       DecSt(6)='1' or DecSt(9)='1' or   -- JMP,CALL
                       DecSt(12)='1' or DecSt(13)='1' or  -- PUSH,POP
                       DecSt(10)='1' or DecSt(14)='1' else -- RET,HALT
           "0001" when DecSt(0)='1' and Stop='0'  else   -- Fetch
           "0010" when DecSt(1)='1' and Type1='1' and Immd='0' else   -- LD/ADD/.../XOR
           "0100" when DecSt(1)='1' and OP="0010" else   -- ST
           "0101" when DecSt(1)='1' and OP="1001" else   -- SHIFT
           "0110" when DecSt(1)='1' and OP="1010" and JmpCnd='1' else -- JMP/JZ/JC/JM
           "0111" when DecSt(1)='1' and OP="1011" else   -- CALL (1)
           "1000" when DecSt(7)='1'               else   -- CALL (2)
           "1001" when DecSt(8)='1'               else   -- CALL (3)
           "1010" when DecSt(1)='1' and OP="1110" else   -- RET
           "1011" when DecSt(1)='1' and OP="1101" and Rx="00" else -- PUSH (1)
           "1100" when DecSt(11)='1'              else   -- PUSH (2)
           "1101" when DecSt(1)='1' and OP="1101" and Rx="10" else -- POP
           "1110";                                       -- HALT/ERROR

  process(Clk, Reset)
  begin
    if (Reset='1') then
      Stat <= "0000";
    elsif (Clk'event and Clk='1') then
      Stat <= NxtSt;
    end if;
  end process;

  -- Control Signals

  MA   <= '0' when DecSt(0)='1' or DecSt(1)='1' or DecSt(8)='1' or DecSt(10)='1' or DecSt(12)='1' or DecSt(13)='1' or -- fetch, decode, call2, ret, push2, pop
              ((DecSt(2)='1' or DecSt(4)='1' or DecSt(6)='1' or DecSt(7)='1') and Indx='1') else '0';  -- index: alu1, st, jmp, call1

  DSP  <= '0' when DecSt(0)='1' or DecSt(1)='1' or DecSt(8)='1' or DecSt(10)='1' or DecSt(12)='1' or DecSt(13)='1' else '1'; -- PC, SP

  IND  <= "11" when DecSt(0)='1' or DecSt(1)='1' else -- PC: fetch, decode
          "10" when DecSt(8)='1' or DecSt(10)='1' or DecSt(12)='1' or DecSt(13)='1' else -- SP: call2, ret, push2, pop
          Rx-"01"; -- Rx-1


  Jmp  <= '1' when Rd="00" else '0';  -- JMP
  Jz   <= '1' when Rd="01" else '0';  -- JZ
  Jc   <= '1' when Rd="10" else '0';  -- JC
  Jm   <= '1' when Rd="11" else '0';  -- JM
  Indx <= '1' when Rx="01" or Rx="10" else '0';  -- Indexed mode
  Immd <= '1' when Rx="11" else '0';  -- Immediate mode

  --        JMP     JZ and Z Flag       JC and C Flag       JM and S Flag
  JmpCnd <= Jmp or (Jz and Flag(0)) or (Jc and Flag(2)) or (Jm and Flag(1));

  LI    <= DecSt(0);
  LDR   <= DecSt(1) or (DecSt(2) and not Immd) or DecSt(10);
  LF    <= '1' when DecSt(3)='1' and OP/="0001" else '0';    -- OP /=LD
  LR    <= '1' when (DecSt(3)='1' and OP/="0101") or         -- OP /=CMP
           DecSt(5)='1' or DecSt(6)='1' or DecSt(9)='1' or DecSt(13)='1' else '0';
           -- XXX: なぜ元の実装では orのあとが DecSt(5) だったかわかっていない
  SPINC <= DecSt(10) or DecSt(13);
  SPDEC <= DecSt(7)  or DecSt(11);
  PCINC <= (DecSt(0) and not Stop) or
           DecSt(2) or DecSt(4) or DecSt(7);
  LPC   <= (DecSt(6) and JmpCnd) or DecSt(9) or DecSt(10);   -- JMP, CALL, RET
  -- PCRetは消した
  DSP   <= '0' when DecSt(0)='1' or DecSt(7)='1' or DecSt(8)='1' or DecSt(12)='1' or DecSt(13)='1' else '1';
  Ma    <= "00" when DecSt(0)='1' or DecSt(1)='1' else       -- "00"=PC
           "01" when DecSt(2)='1' or DecSt(4)='1' else       -- "01"=EA
           "10";                                             -- "10"=SP
  Md    <= not DecSt(7);
  We    <= DecSt(4)  or DecSt(7) or DecSt(9);
  Halt  <= DecSt(13);

end Behavioral;
