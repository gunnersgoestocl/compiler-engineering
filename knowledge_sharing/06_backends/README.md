# 09–13: Into the Backend

This session continues from sessions 1–4, which stayed entirely in the middle
end: LLVM setup, the IR object graph, SSA and dominance, how to write a pass,
and what passes already exist. Session 4 ended on a cliff-hanger — every
interesting pass was asking the *target* something.

Today we cross that line. First we answer those questions, then we meet the IR
on the other side of them.

Aligned with four textbook themes:

- **Chapter 9**: connecting a target — intrinsics, `TargetTransformInfo`,
  injecting passes into the default pipelines
- **Chapter 11**: Machine IR — the `.mir` format, operands, registers, SSA-ness
- **Chapter 12** *(lightly)*: the MC layer — assembly syntax and encodings
- **Chapter 13**: the machine pass pipeline — three stages, and where to inject

Chapter 10 (debugging) is skipped: it is a tools chapter, and this module uses
those tools rather than surveying them.

## What Is Implemented

- `slides/main.typ` — 42-slide English deck (34 content slides), with the key
  mechanisms drawn as cetz diagrams rather than described in prose
- `docs/talk_script_25min_ja.md` — Japanese presenter script covering every
  slide, with a ◎/○/△ priority on each so slides can be skipped live
- `lab/` — nine stages covering all four chapters, each self-checking
- `exercises/01_read_the_mir/` — reading comprehension, with answers
- `exercises/02_register_units/` — the upstream ch11 exercise, build-free
- `exercises/03_encode_an_instruction/` — ch11's exercise carried into ch12
- `docs/masterclass.md` — technical companion to the slides, holding everything
  the deck no longer has room for
- `TASK.md` — the module's specification, including findings made while building it

**Nothing in this module compiles.** No CMake step, no `LLVM_DIR`, no plugin, no
LLVM source checkout. See [Why nothing compiles](#why-nothing-compiles).

## Requirements

`opt`, `llc`, `llvm-mc`, `llvm-tblgen` and `llvm-config` on `PATH`. `clang` is
optional — it is needed by exactly one lab stage, which skips itself without it.

```sh
export PATH="/opt/homebrew/opt/llvm/bin:$PATH"   # Homebrew LLVM on macOS
llc --version
```

Verified against **LLVM 22.1.8** (Homebrew), host `arm64-apple-darwin`. The book
targets LLVM 20.1.1. Where the two differ it is noted in place, and four
concrete divergences are collected in `docs/masterclass.md` §5.

To use a different toolchain, every tool is overridable:

```sh
LLC=/path/to/llc TBLGEN=/path/to/llvm-tblgen ./lab/run.sh
```

## Why Nothing Compiles

Chapters 9, 11 and 12 are written as a build diary. They grow a fictional
backend called **H2BLB** ("how to build an LLVM backend") inside a *fork of
LLVM*, and the recurring hands-on instruction is:

```sh
$ git diff gen-register-info_ch11^..gen-register-info_ch11
```

That is a good way to write a book and a bad way to run a 25-minute session: it
needs a second LLVM clone and a from-source build before anything is observable.

So this module inverts it. Every claim these four chapters make is demonstrated
instead on a target that already did the work:

| The chapter's subject | How we observe it here |
|---|---|
| `XXXTargetTransformInfo` | one input, eight `-mtriple`/`-mcpu`/`-mattr` combinations |
| target intrinsics via Clang | `__builtin_arm_crc32b` → `llvm.aarch64.crc32b` |
| `registerPassBuilderCallbacks` | `opt -O1 -debug-pass-manager`, with and without `-mtriple` |
| `.mir` format and shrinking | `llc -stop-before`, `-simplify-mir`, `-run-pass` |
| `MachineOperand` concepts | x86 `CMOV`/`CALL`, two-address form, inline-asm early clobber |
| register units | `llvm-tblgen` on textbook Figure 11.2 |
| `gen-instr-info`, `gen-emitter` | `llvm-tblgen` on a 40-line target description |
| the machine pass pipeline | `llc -stop-after` at three points, `-debug-pass=Structure` |

The cost is that we never *write* a backend, so the sheer quantity of mechanical
plumbing is captured as a checklist instead — `docs/masterclass.md` §1.1, which
is more useful on paper than on a slide anyway.

## The Lab

```sh
cd 09_13_backend
./lab/run.sh              # all nine stages
./lab/run.sh tti          # one stage
./lab/run.sh --check      # all stages, plus 55 assertions
./lab/run.sh --list       # stage names
```

Outputs land in `lab/out/`.

| Stage | Ch. | What it shows |
|---|---|---|
| `bringup` | 9 | what a backend physically is: six libraries, and the macro over `Targets.def` that calls your `LLVMInitialize*` functions by name |
| `tti` | 9 | one input file, eight invocations, four qualitatively different answers — all from `TargetTransformInfo`. With no triple, the vectorizer does nothing at all |
| `intrinsics` | 9 | a target builtin from C to LLVM IR, feature gate included — plus the chapter's own example of when *not* to add an intrinsic |
| `inject` | 9 | AArch64's `LoopIdiomVectorizePass` appearing only because of `-mtriple`, which is chapter 9's quiz 5 |
| `mir` | 11 | 114 → 75 → 27 lines, and the round trip that proves the shrinking was legal |
| `operands` | 11 | implicit-def/implicit, `dead`, register masks, tied operands breaking SSA, and early clobber as one character of inline asm |
| `registers` | 11 | five register units for nine registers — and four register classes nobody declared |
| `encoding` | 12 | `let Inst{11-10} = dst;` becoming `Value \|= (op & 0x3) << 10;`, then an AArch64 instruction's bits decoded field by field |
| `pipeline` | 13 | the three stages as `isSSA`/`noPhis`/`noVRegs`, the whole codegen pipeline, and a pass crashing at the wrong stage |

## Exercises

```sh
cd exercises/02_register_units      && ./run.sh --check
cd exercises/03_encode_an_instruction && ./run.sh --check
```

1. **`01_read_the_mir/`** — six questions on reading `.mir`, four of them the
   book's own quiz questions. Operand anatomy, the SSA trick question, block
   order as semantics, command simplification, shrinking, and naming the
   pipeline stage from its properties. Nothing to build; `ANSWERS.md` gives the
   confirming command for each, not just the fact.
2. **`02_register_units/`** — describe Figure 11.2's irregular nine-register
   hierarchy in TableGen and measure the register-unit count. This is the
   upstream `ch11/register_units` exercise with the build step removed. The
   "going further" section measures three follow-up edits, one of which is the
   entire argument for register units.
3. **`03_encode_an_instruction/`** — reuse an encoding family, write a new one
   with `AsmString` and `Inst`, and set an instruction property. Carries the
   upstream `ch11/instr_info` exercise through to chapter 12, and fixes it: see
   below.

Exercise 3 is the one that tests what chapters 11 and 12 are jointly about —
that a target description is *data*, and the assembler is generated from it.

## Slides

```sh
cd slides
typst compile main.typ          # -> main.pdf, 42 slides
typst watch main.typ            # while editing
```

Needs Typst 0.14+ with network access on first run (it fetches `touying` and
`numbly` from the package registry).

| Section | Content slides |
|---|---|
| Session Bridge | 2 |
| Chapter 9 | 5 — the six directories; who calls `LLVMInitialize*`; intrinsics; TTI as the seam; injecting a pass |
| Chapter 11 | 12 — why a second IR; `.mir` and shrinking it; `MachineInstr`/`MCInstrDesc`; implicit operands, tied operands, early clobber; registers and units; SSA at the machine level |
| Chapter 12 | 4 — why now; `.td` → encoder; a real ISA's bits; the three MC components |
| Chapter 13 | 5 — three stages; where to inject; reusing a generic pass; properties; three passes worth knowing |
| Wrapping Up | 3 |

Eight of them are **cetz diagrams** rather than prose: the compilation pipeline,
the backend's directory/library map, the `LLVMInitialize*` call chain, the
`MachineInstr` operand array, Figure 11.2's register hierarchy with its units,
the 16-bit instruction encoding, MC as the hub of the binary tools, and the
three lowering stages as property bands. Every number in them comes from a lab
stage.

Every transformation and every number on the slides was produced by running it
on LLVM 22.1.8.

The deck deliberately carries **more than a 25-minute slot holds** (34 content
slides ≈ 40 minutes read straight through). The selection happens live instead:
`docs/talk_script_25min_ja.md` marks every slide ◎ / ○ / △ and gives three
courses — ◎ only (~18 min), ◎+○ (~24 min, recommended), everything (~40 min) —
plus a one-line bridge to say while skipping past each △.

`docs/talk_script_25min_ja.md` is the Japanese script: one section per slide with
a time budget, plus a prioritised list of what to cut if you are running late and
a set of anticipated questions.

## Four Corrections to the Book

1. **`HwEncoding` does not compile.** The book spells the register encoding
   field `HwEncoding` (pp. 344, 361); it is **`HWEncoding`**, capital W.
   TableGen says `Value 'HwEncoding' unknown!`. Also, a bit-range assignment
   cannot appear in a `let ... in` statement — put it in the record body.
2. **The empty-function trick needs two lines, not one.** Chapter 11 says you
   can delete the LLVM IR section and keep referenced symbols by defining empty
   functions. True, but providing *any* IR section switches off automatic
   `Function` synthesis, so you must stub the function **and** declare the
   callee, or the parser reports
   `function 'sum4' isn't defined in the provided LLVM IR`.
3. **The `-mtriple` advice hides behind a matching host.** The chapter is right
   that `-mtriple` must come back after deleting the IR section — but on an
   arm64 Mac, omitting it works anyway, because `llc` falls back to the host
   triple. The same file fails on an x86 host. Force `-mtriple=x86_64` to see
   the real failure mode.
4. **`ch11/instr_info` no longer builds.** LLVM 22 requires every target to
   remap the generic pseudo-instructions' pointer operands. Add
   `defm : RemapAllTargetPseudoPointerOperands<GPR16>;` to
   `ch11/instr_info/mytarget.td` and it builds again. `ch11/register_units` is
   unaffected.

There is also one thing the book does not mention that changes how you read the
Machine IR: **machine pass properties are not enforced in a release build.**
Running `machine-cp` before register allocation segfaults rather than
complaining, because the assertion is compiled out. `lab/run.sh pipeline` shows
it.

## The Upstream Chapter Exercises

Worth doing too, with the fixes above.

```sh
cd LLVM-Code-Generation/ch13        # the three lowering stages
cmake -GNinja -DCMAKE_BUILD_TYPE=Debug -DLLVM_DIR="$(llvm-config --cmakedir)" -Bbuild .
ninja -Cbuild                       # -> build/{ssa,no-phi,no-vreg}.mir
```

`ch13` needs no C++ and reduces to three `llc` invocations, which is why
`lab/run.sh pipeline` reproduces it directly. `ch11/mir_format` ships
pre-generated full/simplified/shrunk dumps that are worth diffing against your
own. `ch11/register_units` and `ch11/instr_info` are the originals of exercises
2 and 3 here; they need the CMake build, and `instr_info` needs the one-line fix.

## Not Yet Done

Deliberately deferred in this draft:

- **A Japanese cheat sheet.** The talk script exists
  (`docs/talk_script_25min_ja.md`); the one-page terminology sheet that session 2
  kept in `../others/` has no counterpart here yet.
- **More diagrams.** Eight slides are now figures; the ones still carrying their
  argument as prose are `Where To Inject` (the `TargetPassConfig` hooks would
  draw well onto the pipeline figure) and `Two Conventions To Respect`.
- **A GlobalISel-shaped hole.** Chapter 11 mentions `MachineIRBuilder` and the
  `regBankSelected` property; both belong to GlobalISel, which the book does not
  reach until Chapter 14. They are named here and not explained.
- **Register pressure has no lab stage.** The `getRegClassWeight` /
  `getRegPressureSetLimit` family is described in `docs/masterclass.md` §2.5 but
  not demonstrated, because nothing in the standard toolchain prints pressure
  sets. It would need a real pass to observe.
