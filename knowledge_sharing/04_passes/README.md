# 08: Survey of the Existing Passes

This session continues from sessions 1–3, which covered LLVM setup, the IR object
graph, SSA and dominance, and how to write a pass. Chapter 8 turns the question
around: not *how do I write a pass*, but **what already exists, how do I find it,
and how do I read it**.

Aligned with one textbook theme:

- **Chapter 8**: finding unknown passes; helper, analysis, canonicalization, and
  optimization passes

## Draft status

This is a **draft**. What is here is complete and verified; what is missing is
listed at the bottom under [Not Yet Done](#not-yet-done).

## What Is Implemented

- `slides/main.typ` — 46-slide English deck, one concrete example per slide
- `lab/` — seven `opt`-only stages filling the chapter's coverage gaps, each
  self-checking
- `exercises/01_find_the_unknown/` — discovery methodology as a drill, with answers
- `exercises/02_pass_order/` — four ordering cases, runnable and self-checking
- `exercises/03_write_an_id_card/` — template, worked example, and a card index
- `docs/masterclass.md` — technical companion to the slides
- `TASK.md` — the module's specification, including findings made while building it

**Nothing in this module compiles.** There is no CMake step, no `LLVM_DIR`, no
plugin. Every stage is a plain `opt` invocation, which matches the character of
Chapter 8's own exercise: the chapter has no C++ to write, only diffs to read.

## Requirements

`opt` on `PATH`. That is all.

```sh
export PATH="/opt/homebrew/opt/llvm/bin:$PATH"   # Homebrew LLVM on macOS
opt --version
```

Verified against **LLVM 22.1.8** (Homebrew). The book targets LLVM 20.1.1; every
example in `LLVM-Code-Generation/ch8/` was re-run on 22.1.8 and matches the book
exactly, so this material is not version-fragile. Where LLVM 22 differs from the
book at all, it is noted in place.

To use a different `opt`:

```sh
OPT=/path/to/opt ./lab/run.sh
```

## The Lab

```sh
cd 08_passes/lab
./run.sh              # all stages, with input/output diffs
./run.sh mem2reg      # one stage
./run.sh --check      # all stages, plus assert each one's invariant
./run.sh --list       # stage names
```

Outputs land in `lab/out/`.

Upstream `ch8/` covers the chapter's optimization passes well but has no input for
the first half of the chapter. The stages fill those gaps:

| Stage | What it shows |
|---|---|
| `verify` | the verifier firing on a non-dominating use — session 2's dominance rule, broken on purpose |
| `mem2reg` | promotion, including the phi-inserting case and an `alloca` that escapes and cannot be promoted |
| `analysis` | `print<loops>` and `print<domtree>`, contrasted with `require<target-ir>` which produces nothing |
| `printers` | `function(print,loop(print))`: one name, two passes, chosen by scope |
| `scope-trap` | two pipeline strings that fail, and the `loop` vs `loop-mssa` distinction |
| `lcssa-ephemeral` | `lcssa` then `instcombine`: the phi is gone again |
| `pass-order` | `indvars` then `simplifycfg` (quiz 4), correctly scoped |

## The Upstream Chapter Exercise

Do this too — it is where the optimization-pass identity cards come from.

```sh
cd LLVM-Code-Generation/ch8
cmake -GNinja -DCMAKE_BUILD_TYPE=Debug -DLLVM_DIR="$(llvm-config --cmakedir)" -Bbuild .
ninja -Cbuild                          # runs every pass -> build/xxx.out.ll
diff -U10 dce.ll build/dce.out.ll      # the actual exercise
ninja -Cbuild -v                       # see the opt command used
touch dce.ll && ninja -Cbuild          # re-run one pass
```

19 inputs, named `<cli_name>.ll`. Three exceptions: `xor.ll`,
`canonical_form.ll`, and `value_tracking.ll` all exercise `instcombine`.

`loop-reduce.c` and `loop-vectorize.c` sit beside their `.ll` files, so those two
can be shown as C → IR → optimized IR.

## Exercises

```sh
cd 08_passes/exercises/02_pass_order && ./run.sh --check
```

1. **`01_find_the_unknown/`** — seven paraphrased descriptions; find each pass's
   CLI name, scope, source file, and a test. Descriptions are deliberately not
   greppable. One of the seven is not a pass at all. Needs an LLVM *source*
   checkout (`export LLVM_SRC=...`); `ANSWERS.md` gives the route, not just the
   name.
2. **`02_pass_order/`** — four cases where order decides the outcome:
   `mem2reg`/`dce`, `lcssa`/`instcombine`, `reassociate`/`early-cse`, and
   `instcombine` undoing a deliberate target-specific rewrite. Runnable and
   self-checking.
3. **`03_write_an_id_card/`** — pick a pass the chapter does not cover and produce
   its identity card, with input IR you wrote and ran yourself.
   `cards/loop-deletion.md` is a worked example.

Exercise 3 is the one that tests what the chapter is actually about. The chapter
covers 13 passes with cards out of several hundred, and says so; extending the
catalog is its own closing suggestion.

## Slides

```sh
cd 08_passes/slides
typst compile main.typ          # -> main.pdf, 46 slides
typst watch main.typ            # while editing
```

Needs Typst 0.14+ with network access on first run (it fetches `touying` and
`numbly` from the package registry).

Structure:

| Section | Slides |
|---|---|
| Session Bridge | where sessions 1–3 left off; Chapter 8's place between Ch. 5 and Ch. 9 |
| Finding What You Do Not Know | top-down via `opt`, bottom-up via directories, landing on the implementation |
| The New Pass Manager CLI | the bridge for session 3's unfinished slide; scope traps |
| Helper Passes | verifier, printers, analyses, `ValueTracking` |
| Canonicalization | canonical form, `instcombine`, `mem2reg`, `lcssa` |
| Optimization Passes | the identity-card format; IPO, Scalar, Vectorize; the target-API theme |
| Hands-On | the diff workflow, this module's additions, the exercises |
| Check Your Understanding | the chapter's five quiz questions plus three follow-ups |

Every IR transformation on the slides was produced by running it on LLVM 22.1.8,
not transcribed from the book.

## Two Corrections to the Book

1. **ValueTracking bit count.** The book says the mask
   `u0xfffffffffffffffc` zeroes "the first three least significant bits". It is
   **two** — this is in the published errata (p.209). The conclusion is unaffected:
   `%a` is a multiple of 4, so `%a urem 2` is 0.
2. **Loop scopes.** The book presents `module`, `function`, and `loop` as the
   pipeline scope keywords. There is a fourth, `loop-mssa`, and `licm` requires it:
   `-passes='loop(licm)'` aborts with `LICM requires MemorySSA (loop-mssa)`. Bare
   `-passes=licm` works because the inferred scope is already `loop-mssa`. Covered
   in the `scope-trap` stage and on its own slide.

## Not Yet Done

Deliberately deferred in this draft:

- **Japanese presenter material.** Sessions 2's `cheatsheet_ja.md` and
  `talk_script_25min_ja.md` (kept in `../others/`, outside version control) have no
  counterpart here yet. Needs the slide order to settle first.
- **Timing.** 46 slides is more than a 25-minute slot holds. The Optimization
  Passes section is the obvious place to compress — probably by collapsing the
  Scalar cards into fewer slides and pointing at `ch8/` for the rest. No cuts made
  yet, because which passes matter depends on how much of Chapter 9 follows.
- **A `mem2reg` counterpart upstream.** `lab/` covers it, but a PR to the book's
  repository adding `ch8/mem2reg.ll` would be the tidier fix.
- **Exercise 1 self-checking.** Unlike exercises 2 and 3, it has no `run.sh`;
  answers are prose. A script could at least verify the CLI names resolve.
