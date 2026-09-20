//===- your_turn/instrinfo.td ----------------------------------------------===//
//
// The target: 16-bit instruction word, four 16-bit registers r0..r3 encoded
// as 0..3. Registers and the ALU encoding family are already defined in
// ../common.td, which this file is included into.
//
// The ALU class gives you this layout for free:
//
//    15      12 11  10 9   8 7   6 5           0
//   +----------+------+-----+-----+-------------+
//   |  opcode  | dst  |src0 |src1 |      0      |
//   +----------+------+-----+-----+-------------+
//
// and two instructions already use it:
//
//   def ADD : ALU<0b0001, "add">;
//   def SUB : ALU<0b0010, "sub">;
//
// TASK 1 -- reuse an existing family
// ----------------------------------
// Add an `AND` instruction with opcode 0b0011, mnemonic "and".
// This should be one line.
//
// TASK 2 -- a new encoding family
// -------------------------------
// Add a `MOVI` instruction that materialises an immediate into a register:
//
//     movi r1, 42
//
// It does not fit the ALU family: it has one register operand and one
// immediate, and the immediate needs room. Use this layout:
//
//    15      12 11  10 9                       0
//   +----------+------+-------------------------+
//   |   0b1000 | dst  |        imm (10 bits)    |
//   +----------+------+-------------------------+
//
// Write a new TableGen class for it -- call it `IMM` -- following the shape of
// `ALU` in ../common.td. You will need:
//
//   - bits<16> Inst, and a bits<10> field for the immediate
//   - OutOperandList = (outs GPR16:$dst)
//   - InOperandList  = (ins i32imm:$imm)
//   - an AsmString using $dst and $imm
//   - let Inst{...} assignments covering all 16 bits
//
// Remember the bit order: write ranges high-to-low (Inst{11-10}), the way ISA
// documents draw them. Inst{10-11} is legal TableGen and means the reverse.
//
// TASK 3 -- mark it cheap
// -----------------------
// Materialising a constant is cheap enough that the machine passes should be
// allowed to rematerialise it rather than keeping it in a register. Set the
// property that says so. (Look for `isAsCheapAsAMove` in
// llvm/include/llvm/Target/Target.td.)
//
// Then run ../run.sh.
//===----------------------------------------------------------------------===//

def ADD : ALU<0b0001, "add">;
def SUB : ALU<0b0010, "sub">;

// TODO 1: AND, opcode 0b0011.


// TODO 2: the IMM class, and a MOVI record using it.


// TODO 3: give MOVI the isAsCheapAsAMove property.
