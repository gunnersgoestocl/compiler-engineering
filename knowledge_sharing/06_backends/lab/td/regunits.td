//===- regunits.td - the register hierarchy of textbook Figure 11.2 --------===//
//
// Nine architectural registers in three layers:
//
//               +-----------+-----------+-----------+
// 128-bit quad  |    q0     |    q1     |     q2    |
//               +-----+-----+-----+-----+-----------+
// 64-bit double |  d0 | d1  |  d2 |     |           |
//               +--+--+--+--+-----+-----+-----------+
// 32-bit single |s0|s1|s2|  |           |           |
//               +--+--+--+--+-----------+-----------+
//
// Empty cells mean no architectural register exists there -- the hierarchy is
// deliberately irregular, which is what makes register units interesting.
//
// This is the solution to the upstream ch11/register_units exercise, reused
// here as a lab input so `llvm-tblgen` can show us the register units it
// computes. Do the exercise yourself in ../../exercises/02_register_units.
//===----------------------------------------------------------------------===//

include "llvm/Target/Target.td"

let Namespace = "Fig112" in {

// Sub-register indices. Parameters are size and offset, both in bits.
def sub32_low  : SubRegIndex<32>;
def sub32_high : SubRegIndex<32, 32>;
def sub64_low  : SubRegIndex<64>;
def sub64_high : SubRegIndex<64, 64>;

// Layer 1: singles. Leaf registers -- no sub-registers.
def s0 : Register<"s0">;
def s1 : Register<"s1">;
def s2 : Register<"s2">;

// Layer 2: doubles. d0 is fully covered by s0+s1; d1 only has a low half
// (there is no s3); d2 has no addressable singles under it at all.
def d0 : Register<"d0"> {
  let SubRegIndices = [sub32_low, sub32_high];
  let SubRegs = [s0, s1];
  let CoveredBySubRegs = true;
}
def d1 : Register<"d1"> {
  let SubRegIndices = [sub32_low];
  let SubRegs = [s2];
}
def d2 : Register<"d2">;

// Layer 3: quads. Same irregular pattern one level up.
def q0 : Register<"q0"> {
  let SubRegIndices = [sub64_low, sub64_high];
  let SubRegs = [d0, d1];
  let CoveredBySubRegs = true;
}
def q1 : Register<"q1"> {
  let SubRegIndices = [sub64_low];
  let SubRegs = [d2];
}
def q2 : Register<"q2">;

} // end namespace Fig112

// One register class per layer.
def SINGLES : RegisterClass<"Fig112", [f32],   32, (sequence "s%u", 0, 2)>;
def DOUBLES : RegisterClass<"Fig112", [f64],   64, (sequence "d%u", 0, 2)>;
def QUADS   : RegisterClass<"Fig112", [f128], 128, (sequence "q%u", 0, 2)>;

// Boilerplate: every TableGen backend that touches low-level information needs
// a record implementing the Target class to hang everything off.
def Fig112InstrInfo : InstrInfo;
def Fig112 : Target { let InstructionSet = Fig112InstrInfo; }
