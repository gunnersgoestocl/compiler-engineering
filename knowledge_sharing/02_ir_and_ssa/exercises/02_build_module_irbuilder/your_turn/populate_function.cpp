#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"

#include <memory>

using namespace llvm;

// TODO: build a Module containing exactly this function, using IRBuilder:
//
// define i32 @branch_and_phi(i32 %x, i1 %flag) {
// entry:
//   br i1 %flag, label %then, label %else
//
// then:
//   %a = add nsw i32 40, 2
//   br label %merge
//
// else:
//   %b = mul nsw i32 8, 2
//   br label %merge
//
// merge:
//   %y = phi i32 [ %a, %then ], [ %b, %else ]
//   %z = add nsw i32 %y, %x
//   ret i32 %z
// }
//
// Steps:
// 1. Create the Module and the Function (FunctionType::get, Function::Create).
// 2. Create the four BasicBlocks and attach them to the function.
// 3. Use IRBuilder<NoFolder> (llvm/IR/NoFolder.h), one SetInsertPoint per
//    block, to populate each block. Plain IRBuilder<> constant-folds
//    add/mul of two ConstantInts immediately, so %a and %b would never
//    become real instructions -- NoFolder disables that so the built IR
//    matches the target exactly.
// 4. Build the phi with Builder.CreatePHI(...) and PHINode::addIncoming for
//    each predecessor -- notice this is the one place a "definition" needs
//    to know which predecessor block it is coming from.
// 5. Every block must end with a terminator (br or ret) before you move on.
std::unique_ptr<Module> myBuildModule(LLVMContext &Ctxt) { return nullptr; }
