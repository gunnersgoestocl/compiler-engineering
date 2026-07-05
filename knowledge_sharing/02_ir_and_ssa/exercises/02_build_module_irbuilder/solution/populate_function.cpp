#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/Constants.h"    // For ConstantInt.
#include "llvm/IR/DerivedTypes.h" // For FunctionType.
#include "llvm/IR/Function.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/NoFolder.h" // IRBuilder<> would constant-fold %a/%b away.
#include "llvm/IR/Type.h"

#include <memory>

using namespace llvm;

// Builds a Module containing exactly the branch_and_phi function used
// throughout the lecture:
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
std::unique_ptr<Module> solutionBuildModule(LLVMContext &Ctxt) {
  Type *Int32Ty = Type::getInt32Ty(Ctxt);
  Type *Int1Ty = Type::getInt1Ty(Ctxt);

  auto MyModule = std::make_unique<Module>("Solution Module", Ctxt);

  FunctionType *FnTy =
      FunctionType::get(Int32Ty, {Int32Ty, Int1Ty}, /*isVarArg=*/false);
  Function *Fn = Function::Create(FnTy, Function::ExternalLinkage,
                                   "branch_and_phi", MyModule.get());
  Value *X = Fn->getArg(0);
  Value *Flag = Fn->getArg(1);
  X->setName("x");
  Flag->setName("flag");

  auto *EntryBB = BasicBlock::Create(Ctxt, "entry", Fn);
  auto *ThenBB = BasicBlock::Create(Ctxt, "then", Fn);
  auto *ElseBB = BasicBlock::Create(Ctxt, "else", Fn);
  auto *MergeBB = BasicBlock::Create(Ctxt, "merge", Fn);

  // Plain IRBuilder<> uses a ConstantFolder that would fold the `add`/`mul`
  // of two ConstantInts into a ConstantInt right here, so %a and %b would
  // never become real instructions. NoFolder keeps this a literal
  // construction exercise.
  IRBuilder<NoFolder> Builder(EntryBB);
  Builder.CreateCondBr(Flag, ThenBB, ElseBB);

  Builder.SetInsertPoint(ThenBB);
  Value *A = Builder.CreateNSWAdd(ConstantInt::get(Int32Ty, 40),
                                   ConstantInt::get(Int32Ty, 2), "a");
  Builder.CreateBr(MergeBB);

  Builder.SetInsertPoint(ElseBB);
  Value *B = Builder.CreateNSWMul(ConstantInt::get(Int32Ty, 8),
                                   ConstantInt::get(Int32Ty, 2), "b");
  Builder.CreateBr(MergeBB);

  Builder.SetInsertPoint(MergeBB);
  PHINode *Y = Builder.CreatePHI(Int32Ty, /*NumReservedValues=*/2, "y");
  Y->addIncoming(A, ThenBB);
  Y->addIncoming(B, ElseBB);
  Value *Z = Builder.CreateNSWAdd(Y, X, "z");
  Builder.CreateRet(Z);

  return MyModule;
}
