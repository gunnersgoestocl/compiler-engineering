// Demo, not an exercise: def-use chains are not scoped to a function.
//
// The "Def-Use in LLVM" slide says a use is a Use object hanging off some
// User. It does not say the User has to live in the same function as the
// Value's other uses. A global is the easiest place to see this: two
// unrelated functions can both use it, so walking @counter's use-list from
// one function's load walks straight into the other function.
#include "llvm/AsmParser/Parser.h" // For parseAssemblyString.
#include "llvm/IR/Function.h"
#include "llvm/IR/Instructions.h" // For LoadInst.
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Support/SourceMgr.h" // For SMDiagnostic.

using namespace llvm;

static const char *InputIR =
    "@counter = external global i32\n"
    "\n"
    "define i32 @read_in_foo() {\n"
    "entry:\n"
    "  %v = load i32, ptr @counter, align 4\n"
    "  ret i32 %v\n"
    "}\n"
    "\n"
    "define i32 @read_in_bar() {\n"
    "entry:\n"
    "  %v = load i32, ptr @counter, align 4\n"
    "  ret i32 %v\n"
    "}\n";

int main() {
  LLVMContext Context;
  SMDiagnostic Err;
  std::unique_ptr<Module> M = parseAssemblyString(InputIR, Err, Context);
  if (!M) {
    Err.print("def_use_scope_change", errs());
    return 1;
  }

  outs() << *M << "\n";

  Function *Bar = M->getFunction("read_in_bar");
  auto &LoadInBar = cast<LoadInst>(*Bar->front().begin());

  // A load's operand 0 is the pointer it reads: here, the global itself.
  Value *Global = LoadInBar.getOperand(0);
  outs() << "Walking the def-use chain of " << Global->getName()
         << ", found starting from a load inside @" << Bar->getName()
         << "\n";

  for (User *U : Global->users()) {
    auto *UserInst = dyn_cast<Instruction>(U);
    if (!UserInst) {
      outs() << "  non-instruction user: " << *U << "\n";
      continue;
    }
    Function *UserFunc = UserInst->getFunction();
    outs() << "  use in @" << UserFunc->getName() << ": " << *UserInst
           << "\n";
    if (UserFunc != Bar)
      outs() << "    -> not in @" << Bar->getName()
             << ": def-use just crossed a function boundary\n";
  }

  return 0;
}
