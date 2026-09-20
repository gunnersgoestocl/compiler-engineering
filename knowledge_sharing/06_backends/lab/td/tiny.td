//===- tiny.td - a complete 16-bit target description, MC layer included ---===//
//
// Chapters 11 and 12 in ~40 lines. Chapter 11 supplies OutOperandList and
// InOperandList; chapter 12 adds the two fields that turn a Machine-layer
// record into something an assembler can use:
//
//   AsmString   the assembly syntax          -> gen-asm-writer
//   Inst        the bit-level encoding       -> gen-emitter
//
// The point of the exercise is that no C++ is written here. Every line below
// is data; TableGen turns it into the encoder and the printer.
//===----------------------------------------------------------------------===//

include "llvm/Target/Target.td"

// --- Registers: four 16-bit registers, r0..r3, encoded as 0..3 -------------
//
// NOTE: the field is HWEncoding, with a capital W. The textbook writes
// HwEncoding (pp. 344, 361); that spelling does not compile.
let Namespace = "Tiny" in {
  foreach i = 0-3 in {
    def R#i : Register<"r"#i> { let HWEncoding{1-0} = i; }
  }
}
def GPR16 : RegisterClass<"Tiny", [i16], 16, (sequence "R%u", 0, 3)>;

// --- One encoding family, shared by every arithmetic instruction ----------
//
// This is the grouping the chapter 12 introduction warns about: the ISA
// document groups instructions by encoding family, and the target description
// should mirror that grouping. Get it wrong and you rewrite the records later.
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

// Two instructions from that family. Only the opcode field differs.
def ADD : ALU<0b0001, "add">;
def SUB : ALU<0b0010, "sub">;

// --- Boilerplate ----------------------------------------------------------
def TinyInstrInfo : InstrInfo;
def TinyAsmWriter : AsmWriter { let AsmWriterClassName = "InstPrinter"; }
def Tiny : Target {
  let InstructionSet = TinyInstrInfo;
  let AssemblyWriters = [TinyAsmWriter];
}

// LLVM 22 requires every target to say which register class the generic
// pseudo-instructions' pointer operands use. Without this, gen-instr-info
// fails with "missing target override for pseudoinstruction using
// PointerLikeRegClass".
defm : RemapAllTargetPseudoPointerOperands<GPR16>;
