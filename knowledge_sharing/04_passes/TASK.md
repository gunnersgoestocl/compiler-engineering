# Task: Survey of the Existing Passes

Create a learning module for the fourth LLVM session. The audience has seen:

- `01_intro.pdf` — LLVM setup, compiler pipeline, ABI vocabulary, CMake, directory
  structure, and the term *canonical form*
- `02_ir_and_ssa.pdf` — IR object hierarchy, CFGs, RPO, critical/back edges, IR
  syntax and types, target triple and data layout, SSA, dominance, def-use,
  legality before profitability, and the `ir-ssa-lab` pass
- `03_pass.pdf` — legality/profitability in depth, what a pass is, the four scopes,
  pass manager internals, and the legacy pass manager implementation template

This session covers one textbook theme:

- Chapter 8: how to discover unknown passes, and what the middle end provides —
  helper passes, analysis passes, canonicalization passes, optimization passes

## Known gap to bridge

`03_pass.pdf` ends its new-pass-manager slide with "Sorry, I was running out of
time. I will upload next week." **The new pass manager was never presented.**
Chapter 8 assumes it throughout: every CLI example uses `-passes=`, and the
scoping rules of the pipeline string are load-bearing for half the chapter.

This module must therefore include a minimal NPM CLI bridge — enough to read
`-passes='function(print,loop(print)),globaldce'` and to understand why scope
matters — without re-teaching all of Chapter 5.

## Required Learning Outcomes

After this session, the audience should be able to:

1. Given only a description of a transformation, find the LLVM pass that does it:
   its CLI name, scope, implementation file, and tests.
2. Decide whether a pass named in `opt --help` is usable as a middle-end pass.
3. Read and write a new-pass-manager pipeline string, including nested scopes, and
   diagnose a scope error from its message.
4. Use the verifier and the printers to inspect and debug a pipeline, and explain
   why invalid IR must never be fed to a pass.
5. Explain what canonical form is, why LLVM does not enforce it at construction,
   and why `instcombine` may undo a deliberate target-specific rewrite.
6. Explain what `mem2reg` and `lcssa` provide to later passes, and why LCSSA form
   is ephemeral.
7. Read an identity card for an optimization pass and reproduce its transformation
   with `opt`.
8. Identify which target APIs (`TargetTransformInfo`, `TargetLibraryInfo`,
   `TargetLowering`) a pass consults, and connect that to Chapter 9.

## Required Hands-On

Chapter 8's own exercise is unlike the others in the book: there is **no C++ to
write**. Each pass ships an input `.ll`, and the exercise is to read the diff
between input and output. This module keeps that character — nothing in it compiles,
`opt` is the only requirement — and fills the chapter's coverage gaps.

`lab/run.sh` must provide stages for the parts of the chapter that upstream `ch8/`
has no input for:

- the verifier firing on IR that violates SSA dominance
- `mem2reg`, including the phi-inserting case and a non-promotable `alloca`
- analyses that can be printed (`print<loops>`, `print<domtree>`) contrasted with
  one that cannot (`require<target-ir>`)
- nested printer scoping (`function(print,loop(print))`)
- pipeline strings that fail, and why
- `lcssa` followed by `instcombine`, showing LCSSA form is ephemeral
- `indvars` followed by `simplifycfg` (quiz 4), correctly scoped

Each stage must be independently runnable and self-checking (`--check`).

## Exercises

1. `exercises/01_find_the_unknown/` — the chapter's second stated goal as a drill:
   seven paraphrased descriptions, no verbatim strings to grep. Produce CLI name,
   scope, source file, and a test for each. Includes one pass that is not a pass.
2. `exercises/02_pass_order/` — four cases where ordering changes the outcome,
   including one where two passes each achieve nothing alone.
3. `exercises/03_write_an_id_card/` — pick a pass the chapter does not cover and
   produce its identity card, with input IR the student wrote and ran. This is the
   exercise that tests the chapter's actual skill.

## Constraints

- Every IR transformation shown in the slides or docs must be **reproduced by
  running it**, not transcribed from the book. Record the LLVM version used.
- Where the book and the observed behaviour disagree, the observed behaviour wins
  and the discrepancy is documented.
- Apply the published errata (the ValueTracking bit count on p.209 is *two*, not
  three).
- Slides stay self-contained: each one carries its own concrete example, readable
  without narration, per the convention set in `02_ir_and_ssa/slides/main.typ`.

## Findings While Building This

Recorded because they are material, not incidental — each became slide or exercise
content. All verified on LLVM 22.1.8 against a book written for LLVM 20.1.1.

1. **Every ch8 example reproduces exactly on LLVM 22.** All 19 inputs, including
   the vectorizers and `loop-reduce`. The book's stability claim holds.
2. **There are two loop scopes, and the book mentions only one.**
   `-passes='loop(licm)'` fails with `LICM requires MemorySSA (loop-mssa)`, while
   bare `-passes=licm` works — being explicit overrides a correct inferred default.
   It fails at run time, not parse time, so inputs without loops pass silently.
3. **Entering a loop scope changes the IR, not just the pass selection.**
   `function(print,loop(print))` prints `%end` twice: the function printer shows no
   `.lcssa` value, the loop printer shows one. `LoopAnalysisManager`'s LCSSA
   guarantee is observable in a single command with no `lcssa` in the pipeline.
4. **`reassociate` alone is worthless on `@cse_exposed`, and that is the point.** It
   rewrites two chains into identical form and stops; `early-cse` then collapses
   them but cannot without it. Neither pass alone improves the function — a
   concrete argument against evaluating passes individually.
5. **A type mismatch cannot demonstrate the verifier.** `add i64 %x, %y` with `%y`
   declared `i32` is rejected by the *parser*, so the verifier never runs. The
   verifier exists for IR built in memory by a pass, which sharpens quiz 2's point.
   Documented in `lab/ir/type_mismatch.md`.
6. **`adce`'s advantage needs a genuinely dead cycle.** A loop counter that feeds
   the exit branch is live, so `adce` keeps it and appears to do nothing. The
   demonstration needs a second counter that feeds only itself.
7. **`sroa` vs `mem2reg` is a one-command lesson.** On a field-wise-accessed struct
   `alloca`, `mem2reg` changes nothing at all and `sroa` reduces the function to a
   single `add`. Real pipelines run `sroa`; the chapter presents `mem2reg`.
