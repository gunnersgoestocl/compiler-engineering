#include "llvm/ADT/APInt.h"
#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/Constants.h"  // For ConstantInt.
#include "llvm/IR/Function.h"
#include "llvm/IR/InstrTypes.h" // For BinaryOperator.
#include "llvm/IR/Instruction.h"

#include <optional>

using namespace llvm;

// This is likely your first time writing against the LLVM C++ API, so each
// part below has a literal hint. Type it in yourself rather than copying --
// the goal is to see each API call used correctly once, not to save typing.
//
// --- Part 1: evaluate one instruction --------------------------------------
// Goal: given `%r = add nsw i32 40, 2`, compute APInt(32, 42). But if `I`
// has an nsw/nuw flag and the real arithmetic would overflow that flag's
// promise, return std::nullopt instead -- do not fold (see
// keeps_poison_case in main.cpp's sample IR for why this matters).
//
// Hint (write this as its own function, e.g. right above
// myConstantPropagation, taking the instruction and its two constant
// operands):
//
//   #include "llvm/IR/Operator.h" // For OverflowingBinaryOperator.
//
//   std::optional<APInt> evaluateConstantBinaryOp(const BinaryOperator &I,
//                                                  const APInt &LHS,
//                                                  const APInt &RHS) {
//     if (LHS.getBitWidth() != RHS.getBitWidth())
//       return std::nullopt;
//
//     const auto *OBO = dyn_cast<OverflowingBinaryOperator>(&I);
//     const bool HasNUW = OBO && OBO->hasNoUnsignedWrap();
//     const bool HasNSW = OBO && OBO->hasNoSignedWrap();
//     bool Overflow = false;
//
//     switch (I.getOpcode()) {
//     case Instruction::Add: {
//       APInt Result = HasNUW ? LHS.uadd_ov(RHS, Overflow) : LHS + RHS;
//       if (HasNUW && Overflow) return std::nullopt;
//       Result = HasNSW ? LHS.sadd_ov(RHS, Overflow) : Result;
//       if (HasNSW && Overflow) return std::nullopt;
//       return Result;
//     }
//     // Sub/Mul look the same, just with usub_ov/ssub_ov and
//     // umul_ov/smul_ov in place of uadd_ov/sadd_ov.
//     default:
//       return std::nullopt;
//     }
//   }
//
// --- Part 2: walk the function ----------------------------------------------
// Goal: for every BinaryOperator whose two operands are both ConstantInt,
// fold it with Part 1 and rewrite its uses. A plain nested loop is enough
// here -- no RPO, no worklist needed yet (that comes later, in
// template/IRAndSSALabPass.cpp, once one fold can enable another).
//
// Hint (needs #include "llvm/ADT/STLExtras.h" for make_early_inc_range,
// which lets you erase the current instruction mid-loop safely):
//
//   for (BasicBlock &BB : Foo) {
//     for (Instruction &Instr : make_early_inc_range(BB)) {
//       auto *BO = dyn_cast<BinaryOperator>(&Instr);
//       if (!BO) continue;
//
//       auto *LHS = dyn_cast<ConstantInt>(BO->getOperand(0));
//       auto *RHS = dyn_cast<ConstantInt>(BO->getOperand(1));
//       if (!LHS || !RHS) continue;
//
//       std::optional<APInt> Result =
//           evaluateConstantBinaryOp(*BO, LHS->getValue(), RHS->getValue());
//       if (!Result) continue;
//
//       Constant *Folded = ConstantInt::get(BO->getType(), *Result);
//       BO->replaceAllUsesWith(Folded);
//       BO->eraseFromParent();
//       // don't forget to record that you changed something
//     }
//   }
//
// Once Add/Sub/Mul work end to end, try beating the reference implementation
// by also handling UDiv/SDiv (watch for division by zero and signed
// INT_MIN / -1) and the bitwise operators And/Or/Xor (these can't overflow,
// so there are no flags to check).
//
// \returns true if Foo was modified, false otherwise.
bool myConstantPropagation(Function &Foo) {
  return false;
}
