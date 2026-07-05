# Task: LLVM IR, Target Details, and SSA

Create a learning module for the second LLVM session. The audience has already seen the previous session material in `01_intro.pdf`, which covered LLVM setup, compiler basics, ABI vocabulary, CMake configuration, and basic LLVM tool usage.

This session must focus on the following textbook themes:

- Chapter 3: LLVM core objects, CFGs, traversal order, and how compiler concepts map to LLVM APIs
- Chapter 7: LLVM IR syntax, types, target triples, data layouts, and attributes
- Chapter 4: SSA, dominance, def-use chains, and optimization legality

## Required Learning Outcomes

After this session, the audience should be able to:

1. Identify `Module`, `Function`, `BasicBlock`, and `Instruction` in textual LLVM IR and in C++ APIs.
2. Explain why CFG traversal order matters for forward analyses.
3. Read target triple and data layout information and explain why ABI details affect IR interpretation.
4. Explain SSA, phi nodes, dominance, and def-use/use-def relationships.
5. Understand why an optimization must check legality before profitability.
6. Run an LLVM New Pass Manager plugin that inspects IR and performs a small SSA rewrite.

## Required Hands-On

Implement an LLVM pass named `ir-ssa-lab`.

The pass should:

- print module-level target information
- print function, basic-block, instruction, operand, and user information
- print Reverse Post-Order CFG traversal
- print predecessor/successor counts
- print immediate dominator information
- print phi-node incoming values
- fold simple constant integer binary operators using `APInt`
- update SSA users with `replaceAllUsesWith`
- erase only trivially dead instructions
- avoid unsafe folds involving overflow flags, exact division, and division by zero


## Extensions Implemented

Beyond the `ir-ssa-lab` pass itself, three standalone hands-on pieces live
under `exercises/`, each following a `your_turn/` (TODO) vs. `solution/`
split with a small `main.cpp` harness that needs no `opt -load-pass-plugin`
step:

1. `exercises/01_const_fold_standalone/`: a lower-friction warm-up that
   isolates the constant-folding-with-legality problem (Chapter 4) into a
   single function, before students take on the full pass.
2. `exercises/02_build_module_irbuilder/`: builds Chapter 3's object
   hierarchy from the construction side with `IRBuilder`, reproducing the
   `branch_and_phi` example used throughout the lecture.
3. `exercises/03_def_use_scope_change/`: a demo showing that def-use chains
   are not scoped to a single function, sharpening the Chapter 4 def-use
   discussion.

`tests/test.ll` was also extended with an irreducible CFG (`irreducible_loop`)
to make the "Edges That Matter" slide concrete, and with named-struct,
array, and vector type examples to broaden Chapter 7 coverage beyond the
single anonymous-struct GEP example.

## Staged Checkpoints for `template/IRAndSSALabPass.cpp`

The full `ir-ssa-lab` pass combines several skills (New Pass Manager
plumbing, RPO/dominance, `APInt`-based legality-checked folding) that are a
big jump right after first contact with LLVM IR. Rather than lowering the
bar by cutting content, the template's TODOs are broken into four ordered
stages, with `tests/template_checkpoints.ll` providing a `STEP1`/`STEP2`/
`STEP3` `FileCheck` prefix for the first three, so students get automated
pass/fail feedback after each stage instead of only at the very end. Stage
4 (the fold itself) is explicitly sequenced *after*
`exercises/01_const_fold_standalone`, so the legality-checking logic is
already familiar by the time it needs to be ported into the full pass. See
`README.md`'s "Recommended Order" section for the exact commands.

