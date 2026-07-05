# 02: LLVM IR, Target Details, and SSA

This session continues from the previous session, which covered LLVM setup, compiler basics, building LLVM, and basic tool usage. This chapter moves from "how to run LLVM tools" to "how LLVM represents programs internally."

The material is aligned with three textbook themes:

- Chapter 3: LLVM core objects, CFGs, traversal order, and how compiler concepts map to LLVM APIs
- Chapter 7: LLVM IR syntax, types, target triples, data layouts, and attributes
- Chapter 4: SSA, dominance, def-use chains, and the legality constraints behind optimization

## What Was Implemented

- `src/IRAndSSALabPass.cpp`: complete LLVM New Pass Manager plugin
- `template/IRAndSSALabPass.cpp`: student template with TODO markers, also built as its own plugin (`IRAndSSALabPassTemplate`) so you can iterate without touching `src/`
- `tests/test.ll`: compact SSA IR with `FileCheck` checks, including an irreducible CFG and named-struct/array/vector type examples
- `tests/test.c`: C source that motivates the IR examples
- `tests/test_o0.ll`: clang `-O0`-style IR for comparison
- `exercises/`: three smaller, standalone hands-on pieces (see below)
- `docs/masterclass.md`: technical explanation and lab guide
- `../others/cheatsheet_ja.md`: Japanese presenter cheatsheet (broader background/Q&A reference, kept outside version control)
- `../others/talk_script_25min_ja.md`: Japanese, timed (25-minute) delivery script keyed to the current slide order (kept outside version control)
- `slides/main.typ`: English slide deck for the session, written to be self-contained (each slide includes its own concrete example, no verbal narration required to follow it)

The pass is intentionally both an inspector and a small optimizer. It prints:

- module name, target triple, and data layout
- functions, basic blocks, instructions, operands, and users
- CFG order using Reverse Post-Order
- predecessor/successor counts and immediate dominators
- phi-node incoming values

It also folds simple constant integer binary operators so the audience can see how `replaceAllUsesWith` updates SSA def-use chains.

## Build

Run these commands in an environment where LLVM provides `llvm-config`, `opt`, `FileCheck`, and `clang` on `PATH`. Tested against LLVM 22.1.8 (Homebrew); header locations for `PassPlugin.h` and `CFGAnalyses` are guarded with `__has_include` so this also builds against LLVM 15-19 layouts.

```sh
cd 02_ir_and_ssa
export PATH="/opt/homebrew/opt/llvm/bin:$PATH" // if you have installed llvm in your mac.
cmake -S . -B build -DLLVM_DIR="$(llvm-config --cmakedir)"
cmake --build build
```

This builds the main pass (`IRAndSSALabPass`), the unfilled student template as its own plugin (`IRAndSSALabPassTemplate`), and the three exercises under `exercises/`.

### Recommended Order for `template/IRAndSSALabPass.cpp`

The full pass bundles several skills at once (New Pass Manager plumbing, dominance/RPO, `APInt`-based legality-checked folding), which is a lot to take on in one jump right after first contact with LLVM IR. Do it in this order instead of head-on:

1. **Do `exercises/01_const_fold_standalone/` first.** It isolates the constant-fold-with-legality problem (what becomes Step 4 below) with no RPO/dominance/printing to worry about, and gives fast, plugin-free feedback.
2. **Fill in `template/IRAndSSALabPass.cpp` in the four stages marked in its TODO comments.** `tests/template_checkpoints.ll` has a matching `STEP1`/`STEP2`/`STEP3` `FileCheck` prefix for the first three stages, so you get a pass/fail signal after each one instead of only at the very end:
   - `STEP1`: function/block enumeration only (name, arg count, block count).
   - `STEP2`: add the RPO walk and per-block predecessor/successor/immediate-dominator info.
   - `STEP3`: add per-instruction opcode/type/operands/users/phi-incoming (completes `printFunctionIRFacts`).
   - Step 4 (`evaluateConstantBinaryOp` + `foldConstantBinaryOperators`): port your Step-1 exercise logic in, then switch to the real acceptance test -- `tests/test.ll`'s `TRACE`/`IR` checks, pointed at `build/IRAndSSALabPassTemplate.dylib`.

```sh
cmake --build build --target IRAndSSALabPassTemplate

opt -load-pass-plugin=build/IRAndSSALabPassTemplate.dylib \
  -passes="ir-ssa-lab" -disable-output tests/template_checkpoints.ll 2>&1 \
  | FileCheck tests/template_checkpoints.ll --check-prefix=STEP1
```

## Run the Lab Pass

```sh
opt -load-pass-plugin=build/IRAndSSALabPass.dylib \
  -passes="ir-ssa-lab" \
  -S tests/test.ll
```

On Linux, the plugin extension is usually `.so` instead of `.dylib`.

To see only the analysis trace:

```sh
opt -load-pass-plugin=build/IRAndSSALabPass.dylib \
  -passes="ir-ssa-lab" \
  -disable-output tests/test.ll
```

## Test

```sh
opt -load-pass-plugin=build/IRAndSSALabPass.dylib \
  -passes="ir-ssa-lab" \
  -disable-output tests/test.ll 2>&1 | FileCheck tests/test.ll --check-prefix=TRACE

opt -load-pass-plugin=build/IRAndSSALabPass.dylib \
  -passes="ir-ssa-lab" \
  -S tests/test.ll 2>/dev/null | FileCheck tests/test.ll --check-prefix=IR
```

## Generate IR From C

```sh
clang -S -emit-llvm -O0 -Xclang -disable-O0-optnone tests/test.c -o /tmp/test_o0.ll
clang -S -emit-llvm -O1 tests/test.c -o /tmp/test_o1.ll
```

At `-O0`, clang preserves source-level variables with `alloca`, `load`, and `store`, so SSA is less visible. At `-O1`, mem2reg and other canonicalization passes make phi nodes and scalar SSA values much easier to inspect.

## Additional Exercises

Three smaller, lower-friction pieces live under `exercises/`. Each is a plain
executable (no `opt -load-pass-plugin` step), following a `your_turn/`
(TODO) vs. `solution/` split. See each directory's `README.md` for details.

- `exercises/01_const_fold_standalone/`: a warm-up before the full lab pass.
  Populate constant folding for one function at a time; the same `nsw`
  legality question from `keeps_poison_case` shows up here too.
- `exercises/02_build_module_irbuilder/`: Chapter 3's object hierarchy from
  the construction side -- build the `branch_and_phi` module from scratch
  with `IRBuilder`, including the `phi` node.
- `exercises/03_def_use_scope_change/`: a demo (not a fill-in exercise)
  showing that a def-use chain can cross function boundaries through a
  shared global.

```sh
cmake --build build --target const_fold_standalone
cmake --build build --target build_module_irbuilder
cmake --build build --target def_use_scope_change
```

