# Chapter 3 From the Construction Side: IRBuilder

The rest of this session reads the `Module -> Function -> BasicBlock ->
Instruction` hierarchy out of existing IR. This exercise builds it, using
`IRBuilder`, to produce exactly the `branch_and_phi` function used throughout
the lecture and the main `ir-ssa-lab` tests.

Populate `myBuildModule` in `your_turn/populate_function.cpp`. If you get
stuck, `solution/populate_function.cpp` has a reference implementation.

## Build and Run

```sh
cd 02_ir_and_ssa
cmake -S . -B build -DLLVM_DIR="$(llvm-config --cmakedir)"
cmake --build build --target build_module_irbuilder
./build/exercises/02_build_module_irbuilder/build_module_irbuilder
```

The program prints both modules and runs `verifyModule` on each. A common
mistake is forgetting `PHINode::addIncoming` for one predecessor, or leaving
a `BasicBlock` without a terminator -- `verifyModule` will catch both.

Watch out for one more surprise: plain `IRBuilder<>` constant-folds an
`add`/`mul` of two `ConstantInt`s the moment you call `CreateAdd`/`CreateMul`
-- `%a` and `%b` would silently never become instructions. Use
`IRBuilder<NoFolder>` (`llvm/IR/NoFolder.h`) so the module you build matches
the target IR literally.
