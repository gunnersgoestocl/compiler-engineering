//===- epilogue.td - target boilerplate -----------------------------------===//
//
// Included last, after the instruction records exist. The Target record has to
// come after the instructions it refers to, which is why this is a separate
// file rather than the bottom of common.td.
//===----------------------------------------------------------------------===//

def TinyInstrInfo : InstrInfo;
def TinyAsmWriter : AsmWriter { let AsmWriterClassName = "InstPrinter"; }
def Tiny : Target {
  let InstructionSet = TinyInstrInfo;
  let AssemblyWriters = [TinyAsmWriter];
}

// LLVM 22 requires every target to say which register class the generic
// pseudo-instructions' pointer operands use.
defm : RemapAllTargetPseudoPointerOperands<GPR16>;
