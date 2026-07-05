#include "llvm/ADT/APInt.h"
#include "llvm/ADT/PostOrderIterator.h"
#include "llvm/ADT/SmallPtrSet.h"
#if __has_include("llvm/Analysis/CFGAnalyses.h")
#include "llvm/Analysis/CFGAnalyses.h"
#else
// LLVM 19+ merged this header into llvm/IR/Analysis.h.
#include "llvm/IR/Analysis.h"
#endif
#include "llvm/IR/CFG.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/Dominators.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/InstIterator.h"
#include "llvm/IR/InstrTypes.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/Operator.h"
#include "llvm/IR/PassManager.h"
#include "llvm/Passes/PassBuilder.h"
#if __has_include("llvm/Passes/PassPlugin.h")
#include "llvm/Passes/PassPlugin.h"
#else
// LLVM 20+ moved this header to llvm/Plugins/PassPlugin.h.
#include "llvm/Plugins/PassPlugin.h"
#endif
#include "llvm/Support/raw_ostream.h"
#include "llvm/Transforms/Utils/Local.h"

#include <optional>
#include <string>
#include <vector>

using namespace llvm;

namespace {

std::string valueLabel(const Value &V) {
  if (const auto *CI = dyn_cast<ConstantInt>(&V)) {
    std::string Text;
    raw_string_ostream OS(Text);
    CI->getValue().print(OS, true);
    return OS.str();
  }

  std::string Text;
  raw_string_ostream OS(Text);
  V.printAsOperand(OS, false);
  return OS.str();
}

std::string instructionResultLabel(const Instruction &I) {
  if (I.getType()->isVoidTy())
    return "<void>";
  return valueLabel(I);
}

void printFunctionIRFacts(Function &F, DominatorTree &DT) {
  // Fill this in one stage at a time and type each hint in yourself rather
  // than reasoning out the API from scratch -- the point of each stage is
  // to see the API used correctly once, then wire it up. Build with
  // `cmake --build build --target IRAndSSALabPassTemplate` after each
  // stage and run the matching check named below; see
  // tests/template_checkpoints.ll's header comment for the exact commands.

  // --- STEP 1: function header line -------------------------------------
  // Goal output:  [Function] @branch_and_phi args=2 blocks=4
  //
  // Hint:
  //   errs() << "[Function] @" << F.getName() << " args=" << F.arg_size()
  //          << " blocks=" << F.size() << "\n";
  //
  // Check: --check-prefix=STEP1

  // --- STEP 2a: Reverse Post-Order block order, one line -----------------
  // Goal output:  [CFG-RPO] %entry %then %else %merge
  //
  // Hint:
  //   errs() << "[CFG-RPO]";
  //   for (BasicBlock *BB : ReversePostOrderTraversal<Function *>(&F))
  //     errs() << " %" << BB->getName();
  //   errs() << "\n";

  // --- STEP 2b: per-block predecessor/successor/dominator info -----------
  // Goal output:  [Block] %merge preds=2 succs=0 idom=%entry
  //
  // Hint (the STEP 3 instruction loop goes inside this same block loop):
  //   for (BasicBlock &BB : F) {
  //     errs() << "[Block] %" << BB.getName()
  //            << " preds=" << pred_size(&BB) << " succs=" << succ_size(&BB);
  //     if (DomTreeNode *Node = DT.getNode(&BB)) {
  //       if (DomTreeNode *IDom = Node->getIDom())
  //         errs() << " idom=%" << IDom->getBlock()->getName();
  //       else
  //         errs() << " idom=<entry>";
  //     }
  //     errs() << "\n";
  //   }
  //
  // Check: --check-prefix=STEP2

  // --- STEP 3: per-instruction opcode/type/operands/users/phi-incoming ---
  // Goal output:
  //   [Inst] %y opcode=phi type=i32
  //     operands: 42 16
  //     users: %z
  //     phi-incoming: [42 from %then] [16 from %else]
  //
  // Hint (place this loop inside the `for (BasicBlock &BB : F)` from
  // STEP 2b, right after you print the "[Block] ..." line):
  //   for (Instruction &I : BB) {
  //     errs() << "  [Inst] " << instructionResultLabel(I)
  //            << " opcode=" << I.getOpcodeName();
  //     if (!I.getType()->isVoidTy())
  //       errs() << " type=" << *I.getType();
  //     errs() << "\n";
  //
  //     errs() << "    operands:";
  //     for (const Use &Op : I.operands())
  //       errs() << " " << valueLabel(*Op.get());
  //     errs() << "\n";
  //
  //     if (!I.getType()->isVoidTy()) {
  //       errs() << "    users:";
  //       for (const User *U : I.users())
  //         if (const auto *UserInst = dyn_cast<Instruction>(U))
  //           errs() << " " << instructionResultLabel(*UserInst);
  //       errs() << "\n";
  //     }
  //
  //     if (const auto *Phi = dyn_cast<PHINode>(&I)) {
  //       errs() << "    phi-incoming:";
  //       for (unsigned Idx = 0, E = Phi->getNumIncomingValues(); Idx != E;
  //            ++Idx)
  //         errs() << " [" << valueLabel(*Phi->getIncomingValue(Idx))
  //                << " from %" << Phi->getIncomingBlock(Idx)->getName()
  //                << "]";
  //       errs() << "\n";
  //     }
  //   }
  //
  // Note: a use's User can be a void instruction (e.g. `ret`, `store`).
  // Printing that User with valueLabel() prints "<badref>" because a void
  // value has no operand form -- that is why the "users:" loop above uses
  // instructionResultLabel() instead, which prints "<void>" for those.
  //
  // Check: --check-prefix=STEP3 (this completes printFunctionIRFacts)
}

// STEP 4. Do not start here -- do exercises/01_const_fold_standalone first.
// That exercise has the same evaluateConstantBinaryOp shape (Add/Sub/Mul
// with nsw/nuw legality) with none of the printing/RPO/dominance machinery
// above to distract you. Once it works there, port the logic over: what is
// new here is only the worklist-driven loop below it, not this function.
std::optional<APInt> evaluateConstantBinaryOp(const BinaryOperator &I,
                                              const APInt &LHS,
                                              const APInt &RHS) {
  // Goal: given `%r = add nsw i32 40, 2`, return APInt(32, 42). But if `I`
  // has an nsw/nuw flag and the real arithmetic would overflow that flag's
  // promise, return std::nullopt instead -- do not fold (see
  // keeps_poison_case in tests/test.ll for why this matters).
  //
  // Hint:
  //   if (LHS.getBitWidth() != RHS.getBitWidth())
  //     return std::nullopt;
  //
  //   bool Overflow = false;
  //   const auto *OBO = dyn_cast<OverflowingBinaryOperator>(&I);
  //   const bool HasNUW = OBO && OBO->hasNoUnsignedWrap();
  //   const bool HasNSW = OBO && OBO->hasNoSignedWrap();
  //
  //   switch (I.getOpcode()) {
  //   case Instruction::Add: {
  //     APInt Result = HasNUW ? LHS.uadd_ov(RHS, Overflow) : LHS + RHS;
  //     if (HasNUW && Overflow) return std::nullopt;
  //     Result = HasNSW ? LHS.sadd_ov(RHS, Overflow) : Result;
  //     if (HasNSW && Overflow) return std::nullopt;
  //     return Result;
  //   }
  //   // Sub/Mul look the same, just with usub_ov/ssub_ov and
  //   // umul_ov/smul_ov in place of uadd_ov/sadd_ov.
  //   case Instruction::UDiv:
  //     if (RHS.isZero()) return std::nullopt;
  //     if (cast<PossiblyExactOperator>(&I)->isExact() && !LHS.urem(RHS).isZero())
  //       return std::nullopt;
  //     return LHS.udiv(RHS);
  //   case Instruction::SDiv:
  //     if (RHS.isZero()) return std::nullopt;
  //     if (LHS.isMinSignedValue() && RHS.isAllOnes()) return std::nullopt;
  //     if (cast<PossiblyExactOperator>(&I)->isExact() && !LHS.srem(RHS).isZero())
  //       return std::nullopt;
  //     return LHS.sdiv(RHS);
  //   case Instruction::And: return LHS & RHS;
  //   case Instruction::Or:  return LHS | RHS;
  //   case Instruction::Xor: return LHS ^ RHS;
  //   default:
  //     return std::nullopt;
  //   }
  return std::nullopt;
}

bool foldConstantBinaryOperators(Function &F) {
  bool Changed = false;
  std::vector<Instruction *> Worklist;
  std::vector<Instruction *> MaybeDead;
  SmallPtrSet<Instruction *, 32> PendingDead;

  // Why a worklist (new compared to exercises/01_const_fold_standalone,
  // which folds in one forward pass): folding `%a` can make its *user*
  // foldable too (e.g. if that user now has two ConstantInt operands), and
  // that user may already be behind us in iteration order. Pushing users
  // back onto the worklist re-examines them. Deletion is deferred to a
  // second pass so that erasing an instruction never invalidates an
  // iterator we are still using.
  //
  // Hint:
  //   for (Instruction &I : instructions(F))
  //     Worklist.push_back(&I);
  //
  //   while (!Worklist.empty()) {
  //     Instruction *I = Worklist.back();
  //     Worklist.pop_back();
  //     if (PendingDead.count(I))
  //       continue;
  //
  //     auto *BO = dyn_cast<BinaryOperator>(I);
  //     if (!BO) continue;
  //     auto *LHS = dyn_cast<ConstantInt>(BO->getOperand(0));
  //     auto *RHS = dyn_cast<ConstantInt>(BO->getOperand(1));
  //     if (!LHS || !RHS) continue;
  //
  //     std::optional<APInt> Result =
  //         evaluateConstantBinaryOp(*BO, LHS->getValue(), RHS->getValue());
  //     if (!Result) continue;
  //
  //     for (User *U : BO->users())
  //       if (auto *UserInst = dyn_cast<Instruction>(U))
  //         Worklist.push_back(UserInst);
  //
  //     Constant *Folded = ConstantInt::get(BO->getType(), *Result);
  //     errs() << "[Fold] " << valueLabel(*BO) << " -> " << valueLabel(*Folded)
  //            << "\n";
  //     BO->replaceAllUsesWith(Folded);
  //     if (PendingDead.insert(BO).second)
  //       MaybeDead.push_back(BO);
  //     Changed = true;
  //   }
  //
  //   for (Instruction *I : MaybeDead) {
  //     if (isInstructionTriviallyDead(I)) {
  //       I->eraseFromParent();
  //       Changed = true;
  //     }
  //   }
  //
  // Once this and evaluateConstantBinaryOp are done, tests/test.ll (the
  // TRACE/IR check-prefixes) is your final acceptance test -- see the
  // "Test" section in README.md, pointed at
  // build/IRAndSSALabPassTemplate.dylib instead of IRAndSSALabPass.dylib.

  return Changed;
}

class IRAndSSALabPass : public PassInfoMixin<IRAndSSALabPass> {
public:
  PreservedAnalyses run(Module &M, ModuleAnalysisManager &MAM) {
    errs() << "[Module] name=" << M.getName() << "\n";
    errs() << "[Target] triple=" << M.getTargetTriple().str() << "\n";
    errs() << "[DataLayout] " << M.getDataLayout().getStringRepresentation()
           << "\n";

    FunctionAnalysisManager &FAM =
        MAM.getResult<FunctionAnalysisManagerModuleProxy>(M).getManager();

    bool Changed = false;
    for (Function &F : M) {
      if (F.isDeclaration())
        continue;

      DominatorTree &DT = FAM.getResult<DominatorTreeAnalysis>(F);
      Changed |= foldConstantBinaryOperators(F);
      printFunctionIRFacts(F, DT);
    }

    if (!Changed)
      return PreservedAnalyses::all();

    PreservedAnalyses PA;
    PA.preserveSet<CFGAnalyses>();
    return PA;
  }
};

} // namespace

extern "C" LLVM_ATTRIBUTE_WEAK PassPluginLibraryInfo llvmGetPassPluginInfo() {
  return {LLVM_PLUGIN_API_VERSION, "IRAndSSALabPass", LLVM_VERSION_STRING,
          [](PassBuilder &PB) {
            PB.registerPipelineParsingCallback(
                [](StringRef Name, ModulePassManager &MPM,
                   ArrayRef<PassBuilder::PipelineElement>) {
                  if (Name == "ir-ssa-lab") {
                    MPM.addPass(IRAndSSALabPass());
                    return true;
                  }
                  return false;
                });
          }};
}
