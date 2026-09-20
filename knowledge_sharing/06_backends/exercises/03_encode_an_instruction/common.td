//===- common.td - the parts of the target you do not have to write --------===//
//
// Registers and the ALU encoding family, shared by your_turn/ and solution/.
// Identical to ../../lab/td/tiny.td, minus the instruction records.
//
// Included first by both your_turn/target.td and solution/target.td, which
// then include their own instruction records and finally epilogue.td.
//===----------------------------------------------------------------------===//

include "llvm/Target/Target.td"

// --- Registers: four 16-bit registers, r0..r3, encoded as 0..3 ------------
//
// NOTE: the field is HWEncoding, with a capital W. The textbook writes
// HwEncoding (pp. 344, 361); that spelling does not compile.
let Namespace = "Tiny" in {
  foreach i = 0-3 in {
    def R#i : Register<"r"#i> { let HWEncoding{1-0} = i; }
  }
}
def GPR16 : RegisterClass<"Tiny", [i16], 16, (sequence "R%u", 0, 3)>;

// --- The ALU encoding family ----------------------------------------------
//
//  15      12 11  10 9   8 7   6 5           0
// +----------+------+-----+-----+-------------+
// |  opcode  | dst  |src0 |src1 |      0      |
// +----------+------+-----+-----+-------------+
class ALU<bits<4> opc, string mnemonic> : Instruction<> {
  let Namespace = "Tiny";

  bits<16> Inst;
  bits<2> dst;
  bits<2> src0;
  bits<2> src1;

  // Bits are written high-to-low, matching how ISA documents draw them.
  let Inst{15-12} = opc;
  let Inst{11-10} = dst;
  let Inst{9-8}   = src0;
  let Inst{7-6}   = src1;
  let Inst{5-0}   = 0;

  let OutOperandList = (outs GPR16:$dst);
  let InOperandList  = (ins GPR16:$src0, GPR16:$src1);
  let AsmString      = mnemonic # " $dst, $src0, $src1";
}
