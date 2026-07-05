// Chapter 3 from the other direction: instead of reading Module/Function/
// BasicBlock/Instruction out of a parsed .ll file, you build that object
// graph yourself with IRBuilder.
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/Verifier.h"
#include "llvm/Support/raw_ostream.h"

using namespace llvm;

extern std::unique_ptr<Module> myBuildModule(LLVMContext &);
extern std::unique_ptr<Module> solutionBuildModule(LLVMContext &);

int main() {
  LLVMContext Ctxt;
  bool HadError = false;

  for (bool IsReference : {true, false}) {
    const char *Label = IsReference ? "Reference" : "Your solution";
    std::unique_ptr<Module> M =
        IsReference ? solutionBuildModule(Ctxt) : myBuildModule(Ctxt);

    outs() << "\n## " << Label << " implementation\n";
    if (!M) {
      outs() << "Nothing built\n";
      HadError |= true;
      continue;
    }

    M->print(outs(), /*AssemblyAnnotationWriter=*/nullptr);
    if (verifyModule(*M, &errs())) {
      errs() << Label << " does not verify\n";
      HadError = true;
    }
  }

  return HadError ? 1 : 0;
}
