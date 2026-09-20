# Task: Into the Backend

Create a learning module for the fifth LLVM session. The audience has seen:

- `01_intro.pdf` — LLVM setup, compiler pipeline, ABI vocabulary, CMake,
  directory structure, and the term *canonical form*
- `02_ir_and_ssa.pdf` — IR object hierarchy, CFGs, RPO, critical/back edges, IR
  syntax and types, target triple and data layout, SSA, dominance, def-use,
  legality before profitability, and the `ir-ssa-lab` pass
- `03_pass.pdf` — legality/profitability in depth, what a pass is, the four
  scopes, pass manager internals, and the legacy pass manager template
- `08_passes` — discovering unknown passes; helper, analysis, canonicalization
  and optimization passes; the new-pass-manager CLI and its scoping rules

This session covers four textbook themes:

- **Chapter 9**: adding a target, intrinsics, `TargetTransformInfo`, injecting
  passes into the default pipelines
- **Chapter 11**: Machine IR — the `.mir` format, `MachineInstr` and
  `MachineOperand`, registers and register units, SSA at the machine level
- **Chapter 12** *(lightly)*: the MC layer — assembly syntax and instruction
  encodings
- **Chapter 13**: the machine pass pipeline — the three lowering stages, and
  where to inject

Chapter 10 (debugging) is deliberately out of scope: it is a tools chapter, and
this module uses those tools rather than surveying them.

## The structural problem to solve

Chapters 9, 11 and 12 are written as a **build diary**. They develop a fictional
backend (H2BLB) inside a *fork of LLVM*, and the repeated hands-on instruction
is "look at the commit tagged `hook-up-mc-reginfo_ch11` in the companion
repository". Following that needs a second LLVM clone and a from-source build
before anything at all is observable.

That is unworkable for a 25-minute session. **The module must therefore
demonstrate every claim these chapters make on targets that already exist**,
using only tools that ship with an LLVM install. Nothing may require CMake,
`LLVM_DIR`, a plugin, or an LLVM source checkout — this preserves the character
established by `08_passes`, where `opt` was the only requirement.

The cost of that trade is that the audience never *writes* a backend, so the
sheer quantity of mechanical plumbing must be captured as a written checklist
instead (`docs/masterclass.md` §1.1).

## Required Learning Outcomes

After this session, the audience should be able to:

1. Explain what a backend must register with LLVM to be reachable from `llc`
   and from Clang, and why those functions are `extern "C"`.
2. Decide whether a target-specific construct needs an intrinsic, inline
   assembly, or nothing at all, and explain the cost of each.
3. Explain how `TargetTransformInfo` connects a generic middle-end pass to a
   specific target, and predict what an unimplemented TTI does to the
   optimizer's decisions.
4. Inject a pass into the default middle-end pipeline and diagnose why an
   injected pass does not run.
5. Read a `.mir` file: block properties, operand types, implicit vs explicit
   operands, register masks, tied operands, early clobber, sub-register indices.
6. Shrink a `.mir` file to a minimal reproducer and say which fields are
   mandatory, which are recomputed, and which are dangerous to remove.
7. Decide whether a given piece of Machine IR is in SSA form, using the actual
   rule rather than intuition.
8. Explain register classes, sub-registers, register tuples and register units,
   and say why units exist.
9. Describe a target's registers and instructions in TableGen, including
   assembly syntax and bit-level encoding, and read the encoder TableGen
   generates from it.
10. Name the three stages of the machine pass pipeline, the passes that cause
    each transition, and pick a correct injection point for a new pass.

## Required Hands-On

`lab/run.sh` must provide one independently runnable, self-checking (`--check`)
stage per idea, covering all four chapters:

| Stage | Chapter | Demonstrates |
|---|---|---|
| `tti` | 9 | one input, eight triple/CPU/feature combinations, four different answers |
| `intrinsics` | 9 | a target builtin from C to IR, including the feature gate |
| `inject` | 9 | a target-injected middle-end pass, and quiz 5 |
| `mir` | 11 | generating, simplifying, hand-shrinking, and re-running `.mir` |
| `operands` | 11 | implicit/explicit, register masks, tied operands, early clobber |
| `registers` | 11 | register units computed from Figure 11.2's hierarchy |
| `encoding` | 12 | `.td` → encoder and printer; a real ISA's bits decoded by hand |
| `pipeline` | 13 | the three stages, the properties, and a wrong-stage crash |

## Exercises

1. `exercises/01_read_the_mir/` — reading comprehension for the `.mir` format.
   Six questions, four of them the book's own quiz questions, with answers that
   give the confirming command rather than just the fact. Nothing to build.
2. `exercises/02_register_units/` — the upstream `ch11/register_units` exercise
   with the build step removed: describe Figure 11.2's hierarchy in TableGen and
   measure the register-unit count. Self-checking.
3. `exercises/03_encode_an_instruction/` — carries the upstream
   `ch11/instr_info` exercise through to chapter 12: reuse an encoding family,
   write a new one with `AsmString` and `Inst`, and set an instruction property.
   Self-checking against the generated encoder.

## Constraints

- Every claim shown on the slides or in the docs must be **reproduced by
  running it**, not transcribed from the book. Record the LLVM version.
- Where the book and the observed behaviour disagree, the observed behaviour
  wins and the discrepancy is documented in place.
- Slides stay self-contained: each carries its own concrete example, readable
  without narration, per the convention set in `02_ir_and_ssa/slides/main.typ`.
- Four chapters in one session means the compression is the deliverable. Prefer
  cutting a mechanism to cutting the evidence for it: a claim without a runnable
  demonstration should be dropped rather than asserted.

## Findings While Building This

Recorded because they are material, not incidental — each became slide, lab, or
exercise content. All verified on LLVM 22.1.8 against a book written for 20.1.1.

1. **`HwEncoding` does not exist.** The book (pp. 344, 361) spells the register
   encoding field `HwEncoding`; TableGen rejects it with
   `Value 'HwEncoding' unknown!`. It is `HWEncoding`, capital W. Separately, a
   bit-range assignment cannot appear in a `let ... in` statement — it has to go
   in the record body.
2. **The upstream `ch11/instr_info` exercise no longer builds.** LLVM 22
   requires every target to remap the generic pseudo-instructions' pointer
   operands: `defm : RemapAllTargetPseudoPointerOperands<GPR16>;`. One line, but
   a hard stop without it. `ch11/register_units` is unaffected, because
   `gen-register-info` never processes instruction records.
3. **The book's empty-function trick needs two lines, not one.** Providing *any*
   LLVM IR section switches off automatic `Function` synthesis, so declaring the
   callee alone gives `function 'sum4' isn't defined in the provided LLVM IR`.
   You must stub the function *and* declare the callee. The stub body can be
   `unreachable`; the parser never checks that it relates to the Machine IR.
4. **The `-mtriple` advice hides behind a matching host.** Chapter 11 correctly
   says to re-supply `-mtriple` after deleting the IR section — but on an
   arm64 Mac, omitting it works anyway, because `llc` falls back to the host
   triple. "It worked without `-mtriple`" is evidence about the host, not the
   file. Forcing `-mtriple=x86_64` shows the real failure.
5. **Machine pass properties are documentation, not enforcement.**
   `machine-cp` requires `NoVRegs`, and running it on SSA MIR *segfaults*
   (exit 138) rather than reporting anything — a release build compiles the
   assertion out. This sharpens chapter 13's advice about injection points from
   a preference into a correctness requirement.
6. **TableGen synthesises register classes nobody asked for.** Figure 11.2's
   three declared classes become seven, because the irregular hierarchy makes
   "a double" and "a double with an addressable low half" distinct operand
   constraints. Regularising the hierarchy removes them again — and adding a
   register *tuple* adds a register and a class but **zero** register units,
   which is the whole argument for units, measurable in one command.
7. **An overlapping `Inst` range silently drops an operand.** Widening an
   immediate so it overlaps the destination field does not merge or OR the two —
   the later assignment wins and the destination is simply never encoded, with
   no diagnostic. Nothing in the description language prevents describing an
   instruction that cannot work.
8. **`llc` has no flag that lists pass names.** `--print-passes` does not exist,
   and a wrong `-run-pass` name only reports `is not registered`. The
   `Pass Arguments:` line of `-debug-pass=Structure` is the actual index, and it
   doubles as chapter 13's Figure 13.1 in concrete form.
9. **AArch64 injects exactly one middle-end pass**, `LoopIdiomVectorizePass`,
   which makes chapter 9's quiz 5 reproducible in two commands on a real target
   instead of a hypothetical one.
10. **The default `TargetTransformInfo` disables vectorization entirely.** With
    no `-mtriple`, the vectorizer produces nothing at all — not a conservative
    width, nothing. An unimplemented TTI does not mean "sensible defaults"; it
    means every cost query answers "equally cheap".
