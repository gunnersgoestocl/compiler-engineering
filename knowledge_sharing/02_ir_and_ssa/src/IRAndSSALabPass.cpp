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

void printOperandList(const Instruction &I) {
  errs() << "    operands:";
  if (I.getNumOperands() == 0) {
    errs() << " <none>\n";
    return;
  }

  for (const Use &Op : I.operands())
    errs() << " " << valueLabel(*Op.get());
  errs() << "\n";
}

void printUseList(const Instruction &I) {
  if (I.getType()->isVoidTy())
    return;

  errs() << "    users:";
  if (I.use_empty()) {
    errs() << " <none>\n";
    return;
  }

  for (const User *U : I.users()) {
    if (const auto *UserInst = dyn_cast<Instruction>(U))
      errs() << " " << instructionResultLabel(*UserInst);
    else
      errs() << " <non-instruction-user>";
  }
  errs() << "\n";
}

void printPhiDetails(const PHINode &Phi) {
  errs() << "    phi-incoming:";
  for (unsigned I = 0, E = Phi.getNumIncomingValues(); I != E; ++I) {
    errs() << " [" << valueLabel(*Phi.getIncomingValue(I)) << " from %"
           << Phi.getIncomingBlock(I)->getName() << "]";
  }
  errs() << "\n";
}

void printFunctionIRFacts(Function &F, DominatorTree &DT) {
  errs() << "[Function] @" << F.getName() << " args=" << F.arg_size()
         << " blocks=" << F.size() << "\n";

  errs() << "[CFG-RPO]";
  for (BasicBlock *BB : ReversePostOrderTraversal<Function *>(&F))
    errs() << " %" << BB->getName();
  errs() << "\n";

  for (BasicBlock &BB : F) {
    errs() << "[Block] %" << BB.getName() << " preds="
           << pred_size(&BB) << " succs=" << succ_size(&BB);

    if (DomTreeNode *Node = DT.getNode(&BB)) {
      if (DomTreeNode *IDom = Node->getIDom())
        errs() << " idom=%" << IDom->getBlock()->getName();
      else
        errs() << " idom=<entry>";
    }
    errs() << "\n";

    for (Instruction &I : BB) {
      errs() << "  [Inst] " << instructionResultLabel(I)
             << " opcode=" << I.getOpcodeName();

      if (!I.getType()->isVoidTy())
        errs() << " type=" << *I.getType();
      errs() << "\n";

      printOperandList(I);
      printUseList(I);

      if (const auto *Phi = dyn_cast<PHINode>(&I))
        printPhiDetails(*Phi);
    }
  }
}

std::optional<APInt> evaluateConstantBinaryOp(const BinaryOperator &I,
                                              const APInt &LHS,
                                              const APInt &RHS) {
  if (LHS.getBitWidth() != RHS.getBitWidth())
    return std::nullopt;

  bool Overflow = false;
  const auto *OBO = dyn_cast<OverflowingBinaryOperator>(&I);
  const bool HasNUW = OBO && OBO->hasNoUnsignedWrap();
  const bool HasNSW = OBO && OBO->hasNoSignedWrap();

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
  case Instruction::UDiv:
    if (RHS.isZero())
      return std::nullopt;
    if (cast<PossiblyExactOperator>(&I)->isExact() && !LHS.urem(RHS).isZero())
      return std::nullopt;
    return LHS.udiv(RHS);
  case Instruction::SDiv:
    if (RHS.isZero())
      return std::nullopt;
    if (LHS.isMinSignedValue() && RHS.isAllOnes())
      return std::nullopt;
    if (cast<PossiblyExactOperator>(&I)->isExact() && !LHS.srem(RHS).isZero())
      return std::nullopt;
    return LHS.sdiv(RHS);
  case Instruction::And:
    return LHS & RHS;
  case Instruction::Or:
    return LHS | RHS;
  case Instruction::Xor:
    return LHS ^ RHS;
  default:
    return std::nullopt;
  }
}

bool foldConstantBinaryOperators(Function &F) {
  bool Changed = false;
  std::vector<Instruction *> Worklist;
  std::vector<Instruction *> MaybeDead;
  SmallPtrSet<Instruction *, 32> PendingDead;

  for (Instruction &I : instructions(F))
    Worklist.push_back(&I);

  while (!Worklist.empty()) {
    Instruction *I = Worklist.back();
    Worklist.pop_back();

    if (PendingDead.count(I))
      continue;

    auto *BO = dyn_cast<BinaryOperator>(I);
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

    for (User *U : BO->users()) {
      if (auto *UserInst = dyn_cast<Instruction>(U))
        Worklist.push_back(UserInst);
    }

    Constant *Folded = ConstantInt::get(BO->getType(), *Result);
    errs() << "[Fold] " << valueLabel(*BO) << " -> " << valueLabel(*Folded)
           << "\n";

    BO->replaceAllUsesWith(Folded);
    if (PendingDead.insert(BO).second)
      MaybeDead.push_back(BO);
    Changed = true;
  }

  for (Instruction *I : MaybeDead) {
    if (isInstructionTriviallyDead(I)) {
      I->eraseFromParent();
      Changed = true;
    }
  }

  bool RemovedDead;
  do {
    RemovedDead = false;
    for (BasicBlock &BB : F) {
      for (auto It = BB.begin(), End = BB.end(); It != End;) {
        Instruction &I = *It++;
        if (isInstructionTriviallyDead(&I)) {
          I.eraseFromParent();
          RemovedDead = true;
          Changed = true;
        }
      }
    }
  } while (RemovedDead);

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
