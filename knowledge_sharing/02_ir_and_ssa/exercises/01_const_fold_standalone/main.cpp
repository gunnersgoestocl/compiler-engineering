// A low-friction warm-up for the "ir-ssa-lab" pass in ../../src.
//
// Unlike the main lab, this program is a plain executable: no CMake module
// library, no `opt -load-pass-plugin`. It parses IR in-process, clones each
// function so both implementations see identical input, and reports which
// implementation folded more.
#include "llvm/AsmParser/Parser.h"          // For parseAssemblyString.
#include "llvm/IR/Function.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/Verifier.h"
#include "llvm/IRReader/IRReader.h"         // For parseIRFile.
#include "llvm/Support/raw_ostream.h"
#include "llvm/Support/SourceMgr.h"         // For SMDiagnostic.
#include "llvm/Transforms/Utils/Cloning.h"  // For CloneFunction.

using namespace llvm;

extern bool myConstantPropagation(Function &);
extern bool solutionConstantPropagation(Function &);

static bool checkFunctionCorrectness(Function &F) {
  F.print(outs());
  if (verifyFunction(F, &errs())) {
    errs() << F.getName() << " does not verify\n";
    return false;
  }
  return true;
}

// Same two functions as tests/test.ll in the main lab: a branch/phi merge
// that should fold, and an nsw-overflow case that must NOT fold.
static const char *InputIR =
    "define i32 @branch_and_phi(i32 %x, i1 %flag) {\n"
    "entry:\n"
    "  br i1 %flag, label %then, label %else\n"
    "\n"
    "then:\n"
    "  %a = add nsw i32 40, 2\n"
    "  br label %merge\n"
    "\n"
    "else:\n"
    "  %b = mul nsw i32 8, 2\n"
    "  br label %merge\n"
    "\n"
    "merge:\n"
    "  %y = phi i32 [ %a, %then ], [ %b, %else ]\n"
    "  %z = add nsw i32 %y, %x\n"
    "  ret i32 %z\n"
    "}\n"
    "\n"
    "define i32 @keeps_poison_case() {\n"
    "entry:\n"
    "  %bad = add nsw i32 2147483647, 1\n"
    "  ret i32 %bad\n"
    "}\n";

int main(int argc, char **argv) {
  LLVMContext Context;
  SMDiagnostic Err;
  std::unique_ptr<Module> MyModule;
  if (argc == 2) {
    outs() << "Reading module from '" << argv[1] << "'\n";
    MyModule = parseIRFile(argv[1], Err, Context);
  } else {
    MyModule = parseAssemblyString(InputIR, Err, Context);
  }
  if (!MyModule) {
    Err.print(argv[0], errs());
    return 1;
  }

  SmallVector<Function *> Worklist;
  for (Function &F : *MyModule)
    if (!F.isDeclaration())
      Worklist.push_back(&F);

  ValueToValueMapTy VMap;
  bool HadError = false;
  for (Function *F : Worklist) {
    outs() << "Processing function '" << F->getName() << "'\n";
    F->print(outs());

    // Clone before optimizing so both implementations see the same input.
    auto *ClonedFunc = CloneFunction(F, VMap);

    outs() << "\n## Reference implementation\n";
    bool SolutionChanged = solutionConstantPropagation(*ClonedFunc);
    bool SolutionOk = checkFunctionCorrectness(*ClonedFunc);

    outs() << "\n## Your implementation\n";
    bool YoursChanged = myConstantPropagation(*F);
    bool YoursOk = checkFunctionCorrectness(*F);

    if (!SolutionOk || !YoursOk) {
      HadError = true;
      errs() << "Verifier failure: reference(" << (SolutionOk ? "ok" : "FAIL")
             << ") yours(" << (YoursOk ? "ok" : "FAIL") << ")\n";
    }

    outs() << "\n";
    if (SolutionChanged && !YoursChanged)
      outs() << "The reference folded something but you did not.\n";
    else if (!SolutionChanged && YoursChanged)
      outs() << "You folded something the reference did not -- double check "
                "it did not break legality (nsw/nuw/exact/div-by-zero).\n";
    else if (SolutionChanged && YoursChanged)
      outs() << "Both implementations folded something.\n";
    outs() << "######\n";
  }

  return HadError ? 1 : 0;
}
