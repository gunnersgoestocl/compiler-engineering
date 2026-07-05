#include "llvm/ADT/APInt.h"
#include "llvm/ADT/STLExtras.h"  // For make_early_inc_range.
#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/Constants.h"    // For ConstantInt.
#include "llvm/IR/Function.h"
#include "llvm/IR/InstrTypes.h"   // For BinaryOperator.
#include "llvm/IR/Instruction.h"
#include "llvm/IR/Operator.h"     // For OverflowingBinaryOperator.

#include <optional>

using namespace llvm;

namespace {

// Reference implementation only handles Add/Sub/Mul, and only when the
// nsw/nuw flags (if present) would not be violated by the fold. See if you
// can beat it in your_turn/populate_function.cpp by also handling UDiv,
// SDiv, and the bitwise operators -- watch out for division by zero and
// signed INT_MIN / -1.
std::optional<APInt> evaluateConstantBinaryOp(const BinaryOperator &I,
                                               const APInt &LHS,
                                               const APInt &RHS) {
  if (LHS.getBitWidth() != RHS.getBitWidth())
    return std::nullopt;

  const auto *OBO = dyn_cast<OverflowingBinaryOperator>(&I);
  const bool HasNUW = OBO && OBO->hasNoUnsignedWrap();
  const bool HasNSW = OBO && OBO->hasNoSignedWrap();
  bool Overflow = false;

  switch (I.getOpcode()) {
  case Instruction::Add: {
    APInt Result = HasNUW ? LHS.uadd_ov(RHS, Overflow) : LHS + RHS;
    if (HasNUW && Overflow)
      return std::nullopt;
    Result = HasNSW ? LHS.sadd_ov(RHS, Overflow) : Result;
    if (HasNSW && Overflow)
      return std::nullopt;
    return Result;
  }
  case Instruction::Sub: {
    APInt Result = HasNUW ? LHS.usub_ov(RHS, Overflow) : LHS - RHS;
    if (HasNUW && Overflow)
      return std::nullopt;
    Result = HasNSW ? LHS.ssub_ov(RHS, Overflow) : Result;
    if (HasNSW && Overflow)
      return std::nullopt;
    return Result;
  }
  case Instruction::Mul: {
    APInt Result = HasNUW ? LHS.umul_ov(RHS, Overflow) : LHS * RHS;
    if (HasNUW && Overflow)
      return std::nullopt;
    Result = HasNSW ? LHS.smul_ov(RHS, Overflow) : Result;
    if (HasNSW && Overflow)
      return std::nullopt;
    return Result;
  }
  default:
    return std::nullopt;
  }
}

} // namespace

// Takes \p Foo and applies a simple constant-folding optimization.
// \returns true if \p Foo was modified, false otherwise.
bool solutionConstantPropagation(Function &Foo) {
  bool MadeChanges = false;

  for (BasicBlock &BB : Foo) {
    for (Instruction &Instr : make_early_inc_range(BB)) {
      auto *BO = dyn_cast<BinaryOperator>(&Instr);
      if (!BO)
        continue;

      auto *LHS = dyn_cast<ConstantInt>(BO->getOperand(0));
      auto *RHS = dyn_cast<ConstantInt>(BO->getOperand(1));
      if (!LHS || !RHS)
        continue;

      std::optional<APInt> Result =
          evaluateConstantBinaryOp(*BO, LHS->getValue(), RHS->getValue());
      if (!Result)
        continue;

      Constant *Folded = ConstantInt::get(BO->getType(), *Result);
      BO->replaceAllUsesWith(Folded);
      BO->eraseFromParent();
      MadeChanges = true;
    }
  }

  return MadeChanges;
}
