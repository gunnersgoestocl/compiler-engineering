# Warm-Up: Standalone Constant Folding

This is a lower-friction warm-up before the full `ir-ssa-lab` pass in `../../src`.
There is no CMake module library and no `opt -load-pass-plugin` step: you build
one ordinary executable that parses IR in-process.

Populate `myConstantPropagation` in `your_turn/populate_function.cpp`. If this
is your first time using the LLVM C++ API, the TODO comments include literal
code hints for each part -- type them in rather than reasoning out the API
from scratch. If you get stuck anyway, `solution/populate_function.cpp` has a
reference implementation -- but it is intentionally incomplete (Add/Sub/Mul
only). Try to beat it by also handling `udiv`/`sdiv` (watch for division by
zero) and the bitwise operators.

## Build and Run

```sh
cd 02_ir_and_ssa
cmake -S . -B build -DLLVM_DIR="$(llvm-config --cmakedir)"
cmake --build build --target const_fold_standalone
./build/exercises/01_const_fold_standalone/const_fold_standalone
```

You can also pass your own `.ll`/`.bc` file as an argument.

The program clones each function so both implementations see identical
input, runs the reference and your implementation on separate clones, then
reports which one folded more and whether both still verify.

## What to Watch For

- `branch_and_phi`: `%a` and `%b` are constant `add`/`mul` and should fold;
  the `phi` should end up with constant incoming values.
- `keeps_poison_case`: `%bad = add nsw i32 2147483647, 1` must NOT fold.
  `nsw` means signed overflow is poison, not wraparound -- replacing it with
  a concrete `-2147483648` would change the program's meaning.
