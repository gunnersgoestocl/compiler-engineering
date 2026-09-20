//===- your_turn/reginfo.td ------------------------------------------------===//
//
// Describe the register hierarchy of textbook Figure 11.2:
//
//               +-----------+-----------+-----------+
// 128-bit quad  |    q0     |    q1     |     q2    |
//               +-----+-----+-----+-----+-----------+
// 64-bit double |  d0 | d1  |  d2 |     |           |
//               +--+--+--+--+-----+-----+-----------+
// 32-bit single |s0|s1|s2|  |           |           |
//               +--+--+--+--+-----------+-----------+
//
// An empty cell means no architectural register exists there -- it is not
// addressable. The hierarchy is deliberately irregular, and that irregularity
// is the whole point: it is what makes the register-unit count interesting.
//
// Read the picture carefully before you start:
//
//   - q0 spans four singles' worth of bits, and both halves are addressable
//     as doubles (d0, d1)
//   - q1 spans the same width, but only its LOW half is addressable (d2).
//     There is no register for its high half.
//   - q2 has no addressable sub-registers at all
//   - d0 is fully covered by s0 and s1
//   - d1's low half is s2; its high half is not addressable (there is no s3)
//   - d2 has no addressable singles under it
//
// TASK
// ----
// 1. Declare the SubRegIndex records you need. A SubRegIndex takes a size and
//    an offset, both in bits: SubRegIndex<size> or SubRegIndex<size, offset>.
//    You need four: the low and high 32-bit halves of a double, and the low
//    and high 64-bit halves of a quad.
//
// 2. Declare all nine registers. For each one that HAS addressable
//    sub-registers, set SubRegs and SubRegIndices. Where a register is fully
//    determined by its sub-registers, also set CoveredBySubRegs = true.
//
// 3. Declare one RegisterClass per layer: SINGLES (f32, 32-bit alignment),
//    DOUBLES (f64, 64), QUADS (f128, 128).
//
// Then run ../run.sh to compare your register units against the solution.
//
// Predict the unit count before you run it. How few units can describe all
// nine registers?
//===----------------------------------------------------------------------===//

include "llvm/Target/Target.td"

let Namespace = "Fig112" in {

// TODO 1: the four SubRegIndex records.


// TODO 2: the nine registers. One is done for you.
def s0 : Register<"s0">;


} // end namespace Fig112

// TODO 3: one register class per layer. One is started for you -- it is
// deliberately incomplete, because it only lists s0.
//
// Hint: (sequence "s%u", 0, 2) expands to (add s0, s1, s2).
def SINGLES : RegisterClass<"Fig112", [f32], 32, (add s0)>;

// Boilerplate. Every TableGen backend dealing with low-level information needs
// a record implementing the Target class. Leave this alone.
def Fig112InstrInfo : InstrInfo;
def Fig112 : Target { let InstructionSet = Fig112InstrInfo; }
