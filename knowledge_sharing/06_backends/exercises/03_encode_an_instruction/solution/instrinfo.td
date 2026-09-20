//===- solution/instrinfo.td - reference answer ----------------------------===//
//
// One possible answer. The only real decisions are the bit ranges, and those
// come from the layout diagram, not from taste.
//===----------------------------------------------------------------------===//

def ADD : ALU<0b0001, "add">;
def SUB : ALU<0b0010, "sub">;

// TASK 1: the whole point of putting the encoding in a class is that adding
// another member of the family costs one line.
def AND : ALU<0b0011, "and">;

// TASK 2: a second encoding family. Same 16-bit word, different partition --
// no src1 field, and ten bits of immediate instead of the ALU family's six
// dead bits.
//
//  15      12 11  10 9                       0
// +----------+------+-------------------------+
// |   opcode | dst  |        imm (10 bits)    |
// +----------+------+-------------------------+
class IMM<bits<4> opc, string mnemonic> : Instruction<> {
  let Namespace = "Tiny";

  bits<16> Inst;
  bits<2>  dst;
  bits<10> imm;

  let Inst{15-12} = opc;
  let Inst{11-10} = dst;
  let Inst{9-0}   = imm;

  let OutOperandList = (outs GPR16:$dst);
  let InOperandList  = (ins i32imm:$imm);
  let AsmString      = mnemonic # " $dst, $imm";
}

// TASK 3: isAsCheapAsAMove tells the machine passes they may rematerialise
// this instruction instead of keeping its result live in a register.
def MOVI : IMM<0b1000, "movi"> {
  let isAsCheapAsAMove = true;
}
