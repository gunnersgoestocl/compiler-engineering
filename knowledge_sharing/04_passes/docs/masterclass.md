# Masterclass: Survey of the Existing Passes

Technical companion to `slides/main.typ`. The slides are the presentation; this is
the reference — longer arguments, the parts that did not fit, and the places where
observed behaviour and the book diverge.

All commands verified on **LLVM 22.1.8** (Homebrew). Chapter 8 spans pages 201–238.

---

## 1. Why this chapter exists in a backend book

The book is about writing an LLVM backend. Chapter 8 is the one chapter that is
purely about the middle end, and the author justifies it immediately:

> "although you can connect an LLVM backend right after a frontend and skip all the
> middle-end optimizations, you realistically do not want to re-implement all the
> optimizations that are perfectly doable in the middle end. For instance, there is
> zero benefit in reimplementing your own `mem2reg` pass; at best your
> implementation will be equivalent and at worst you'll introduce a bunch of bugs!"

There is a second, subtler argument a few lines later:

> "The deeper into the compiler pipeline you get, the more you are tied to the
> target, and the easier certain things are to do, but conversely, the harder other
> things are."

So the chapter is about *where* to solve a problem, not only *whether* to reuse.
You cannot make that judgement without an inventory. Chapter 9 supplies the
criteria for deciding; Chapter 8 supplies the inventory.

The chapter's stated goals are only two:

1. make you aware of what the middle end is capable of
2. teach you some of the ways you can approach a transformation that you do not know

The second is the real subject. The chapter covers 13 passes with identity cards
out of several hundred, and is explicit that this is a sample.

Terminology note the book sets early: it uses *transformation* as the general
concept and *pass* as the LLVM realisation of it.

---

## 2. Finding the unknown

### 2.1 Top-down, via `opt`

`opt` drives every LLVM-IR-to-LLVM-IR pass, so its help output is an index of the
middle end. Two caveats make it a two-command procedure rather than one.

**Caveat 1: `--help` mixes both pass managers.** The legacy pass manager also
drives the backends, so the list includes passes that are not IR-to-IR passes and
that `opt` cannot run. The book's phrasing is blunt: "yes, `opt` is lying to you!"

**Caveat 2: the name does not tell you.** `--passes=gvn` works.
`--passes=aarch64-O0-prelegalizer-combiner` does not — obvious from the name.
`--passes=aa` also does not, and `aa` is entirely target-independent.

Hence:

```sh
opt --print-passes
```

which lists only what the new pass manager supports, grouped by scope. Drop the
`Machine ...` sections and you have the middle end.

On LLVM 22 the section list is longer than the chapter implies:

```text
Module passes:              Module passes with params:      Module analyses:
CGSCC passes:               CGSCC passes with params:       CGSCC analyses:
Function passes:            Function passes with params:    Function analyses:
LoopNest passes:            Loop passes:                    Loop passes with params:
Loop analyses:
Machine module passes (WIP):
Machine function passes (WIP):
Machine function analyses (WIP):
```

Practical consequences:

- A pass listed only under `... with params` is a normal pass; the suffix means it
  accepts `<flag;flag>` arguments. `sroa` appears as
  `sroa<preserve-cfg;modify-cfg>`, so **match loosely when grepping**.
- The `Machine ...` sections carry `(WIP)` in LLVM 22 — the machine-level NPM port
  is in progress. The chapter's instruction to ignore them still applies.
- `LoopNest passes` is a scope the chapter does not mention.

### 2.2 Bottom-up, via the source tree

Generic IR passes live under `Analysis/` and `Transforms/` (both in
`include/llvm/` and `lib/`). The `Transforms/` subdivision is the useful map:

| Subdirectory | Contents |
|---|---|
| `InstCombine` | simple rewrite patterns beneficial for all targets |
| `AggressiveInstCombine` | a more aggressive version of the above |
| `IPO` | interprocedural — applies across procedures, e.g. inlining |
| `Scalar` | everything non-vector. Most passes are here, loop optimizations included |
| `Vectorize` | produces vector-typed IR (SIMD) |
| `Utils` | generally useful passes and helper functions |
| `Instrumentation` | adds structures alongside the IR: PGO, sanitizers |
| `Coroutines` | coroutine lowering; highly source-language specific |
| `HipStdPar` | HIP C++ standard parallelism support |

This table alone answers quiz 3 by elimination, which is the chapter's point in
including it.

Two entries deserve expansion because they catch people out:

- **`Scalar` holds the loop passes.** `licm`, `indvars`, `loop-unroll`,
  `loop-rotate`, `loop-deletion`, `loop-reduce` are all in `Transforms/Scalar`.
  There is no `Transforms/Loop`. "Scalar" here means "not vectorization", not
  "not loops".
- **`Utils` holds things that are not passes.** `SimplifyLibCalls.cpp` lives there
  and has no CLI name at all — see §7.

### 2.3 Landing on the implementation

Both routes end at a source file, and the chapter's advice about what to do there
is the most reusable part of the section:

```sh
# CLI name -> class name -> file
git grep "always-inline" llvm/lib/Passes/PassRegistry.def
git grep -l "class AlwaysInlinerPass" llvm

# or: description string -> file
git grep -l "Inliner for always_inline functions" llvm

# then: the tests, which are the real documentation
git grep -l 'RUN: .*always-inline' llvm/test
```

Read the header comment (some cite the paper the pass implements), then **extract a
test's `RUN:` line and edit the input IR**. That last step is what separates knowing
a pass's name from knowing its behaviour, and it is what exercise 3 requires.

---

## 3. The new pass manager CLI

Session 3 did not reach this. Chapter 8 needs one idea from it: **the pipeline
string encodes scope**.

```sh
opt --passes='function(print,consthoist,loop(print),instcombine<max-iterations=3>),globaldce'
```

- `module(...)`, `function(...)`, `loop(...)` open a nested pipeline; these are the
  `XXXPassAdaptor`s from the Chapter 5 exercise
- with no keyword the scope is **inferred from the first pass named**
- `print` is registered once per scope; the enclosing scope decides which runs
- `<...>` passes pass-specific flags, which are implementation-specific and not
  stable across releases

### 3.1 Three scope errors, in increasing nastiness

**(a) Function pass named where a module pass is expected.**

```text
$ opt -passes='dce,globaldce' scope.ll -S
opt: unknown function pass 'globaldce'
```

`dce` fixed the scope to function. Read the error's middle word: it names the
inferred scope, which is the actual diagnosis.

**(b) The quiz-4 chain.** `indvars` leaves `br i1 false`; `simplifycfg` removes it.
Chaining them naively:

```text
$ opt -passes='indvars,simplifycfg' indvars.ll -S
opt: unknown loop pass 'simplifycfg'
```

`indvars` is a Loop pass. Correct form:

```sh
opt -passes='loop(indvars),simplifycfg' indvars.ll -S
```

which collapses four basic blocks to one — neither pass could do that alone.

**(c) `loop` vs `loop-mssa`.** Not in the book. There are two loop scopes:

| Scope | Guarantees |
|---|---|
| `loop(...)` | LCSSA form, innermost-first traversal |
| `loop-mssa(...)` | the same, plus a maintained `MemorySSA` |

```text
$ opt -passes='licm'            licm.ll -S    # works
$ opt -passes='loop(licm)'      licm.ll -S
LLVM ERROR: LICM requires MemorySSA (loop-mssa)
$ opt -passes='loop-mssa(licm)' licm.ll -S    # works
```

`licm`'s entire legality argument is about memory, so it requires `MemorySSA`. Two
properties make this worse than (a) and (b):

- **Being explicit is what breaks it.** The inferred scope was already
  `loop-mssa`; naming `loop` overrode a correct default with a worse one.
- **It fails at run time, not parse time.** `opt` accepts the string and only
  aborts when a loop reaches `licm`. On input without loops it passes silently.

### 3.2 Scope changes the IR, not just the pass

The clearest single demonstration in this module:

```sh
opt --passes='function(print,loop(print))' lab/ir/loop.ll -disable-output
```

Both printers print `%end`. The function printer:

```llvm
end:
  %tmp = add i64 %iv_plus_1, %src
  %res = add i64 %tmp, %iv_plus_1
```

The loop printer, same pipeline, same input, one scope deeper:

```llvm
; Exit blocks
end:
  %iv_plus_1.lcssa = phi i64 [ %iv_plus_1, %loop ]
  %tmp = add i64 %iv_plus_1.lcssa, %src
  %res = add i64 %tmp, %iv_plus_1.lcssa
```

There is no `lcssa` in that pipeline. Entering the loop scope caused
`LoopAnalysisManager` to establish LCSSA form, because it guarantees that to loop
passes. So the scope keyword selects *which guarantees are established before your
pass runs* — and that is also why `licm`'s output contains an `.lcssa` phi its input
never had.

Docs: <https://llvm.org/docs/NewPassManager.html#invoking-opt>

---

## 4. Helper passes

Optional, IR-preserving, and — the chapter insists — critical.

### 4.1 The verifier

Checks the IR is well formed. The chapter's two examples: that a definition
dominates all its uses (SSA), and that `fadd`'s operands share a floating-point
type.

```text
$ opt -passes=verify lab/ir/use_before_def.ll -disable-output
Instruction does not dominate all uses!
  %a = add i64 1, 2
  %res = add i64 %a, 3
error: input module is broken!
```

That is session 2's dominance slide, as a diagnostic.

| How | What |
|---|---|
| `opt -passes=verify` | once, explicitly |
| `opt -verify-each` | after every pass in the pipeline |
| `llc` | on by default across codegen; `-disable-verify` to stop |
| NPM | `VerifierPass(bool FatalErrors)`, or `VerifyEachPass=true` on `StandardInstrumentations` |
| legacy | `createVerifierPass(bool FatalErrors)` |

**Only the first of the chapter's two examples can be demonstrated from a `.ll`
file.** A type mismatch is caught by the *parser*:

```text
opt: file.ll:3:22: error: '%y' defined with type 'i32' but expected 'i64'
```

The verifier never runs. This is worth understanding rather than working around,
because it explains what the verifier is *for*: the textual parser already
type-checks files, so the verifier guards against IR **built in memory by a pass**,
where nothing does. `IRBuilder` will assemble a mismatched `add` (its check is an
assertion, compiled out in release builds), and a release LLVM will carry the
malformed instruction until some later pass trips over it — far from the cause.

Which is quiz 2 restated: when an existing pass crashes on your custom pass's
output, the first suspect is your output. Use `-verify-each` so the failure is
attributed to the pass that introduced it. Full discussion in
`lab/ir/type_mismatch.md`.

### 4.2 The printers

One per scope, all registered as `print`.

```sh
opt -print-after-all                # after every pass
opt -print-before=instcombine       # before one named pass
opt --passes='function(print)'      # positionally, in a pipeline
```

Legacy names were `print-module`/`print-function`/`print-loop`, but the chapter
notes a recent `opt` probably no longer wires them up.

The loop printer adds structure labels (`; Preheader:`, `; Loop:`,
`; Exit blocks`) that only make sense per-loop — see §3.2.

### 4.3 Analyses

| Analysis | NPM class | Result | CLI |
|---|---|---|---|
| Target transform info | `TargetIRAnalysis` | `TargetTransformInfo` | `target-ir` |
| Loop info | `LoopAnalysis` | `LoopInfo` | `loops` |
| Alias analysis | `AAManager` | `AAResults` | `aa` |
| Block frequency | `BlockFrequencyAnalysis` | `BlockFrequencyInfo` | `block-freq` |
| Dominator tree | `DominatorTreeAnalysis` | `DominatorTree` | `domtree` |

```cpp
// legacy
auto &TTI = getAnalysis<TargetTransformInfoWrapperPass>().getTTI(F);
// new
auto &TTI = FAM.getResult<TargetIRAnalysis>(F);
```

The chapter gives this snippet once and then declares the rest mechanical, which
is fair.

**Most analyses are invisible.** `require<target-ir>` computes the analysis and, if
nothing consumes it, produces no output at all. Compare:

```text
$ opt -passes='print<loops>' lab/ir/loop.ll -disable-output
Loop info for function 'def_in_loop_use_outside':
Loop at depth 1 containing: %loop<header><latch><exiting>

$ opt -passes='require<target-ir>' lab/ir/loop.ll -disable-output
                                     (nothing)
```

`loops`, `domtree`, and `block-freq` have printers. `domtree` additionally has
`verify<domtree>`.

**Alias analysis is a collection, not an analysis.** It exposes one question — can
these two pointers alias — but answers it by consolidating several analyses that
augment each other. The chapter's illustration:

| Analysis | Reasoning | Cost |
|---|---|---|
| type-based | under strict aliasing, `float*` cannot alias `int*` | cheap |
| range-based | conservatively bound the memory a pointer can reach | expensive |

If the cheap one settles it, the expensive one never runs. Drive it through
`AAManager`; `PassBuilder::buildDefaultAAPipeline` wires up the common and
target-specific ones. This is the analysis behind session 3's legality example
(does `B[1] = val2` invalidate a cached `A[0]`), and behind `licm`'s hoisting
argument.

**`domtree` is in the `IR` library, not `Analysis`** — the chapter explains that
it is inseparable from SSA and used throughout LLVM. If you maintain it yourself,
use `DomTreeUpdater` from `Analysis`.

### 4.4 ValueTracking

Not a pass; a helper class in `Analysis`.

```llvm
%a    = and i64 %b, u0xfffffffffffffffc
%mod  = urem i64 %a, 2
%cond = icmp eq i64 %mod, 0
```

`%b` is unknown, but the mask forces the low **two** bits of `%a` to zero, so `%a`
is a multiple of 4, so `%mod` is 0 and `%cond` is `true`:

```text
$ opt -passes=instcombine ch8/value_tracking.ll -S
define i1 @foo(i64 %b) { ret i1 true }
```

> **Correction.** The book says "the first three least significant bits". The
> published errata (p.209) corrects this to **two**, which is what the mask does.
> The conclusion is unchanged.

```cpp
KnownBits computeKnownBits(const Value *V, const DataLayout &DL, /* ... */);
```

"Very easy to use and extremely powerful, although it can be compile-time
intensive."

The chapter closes the section by pointing at **scalar evolution** as the other
analysis worth studying — it is what `indvars` and `loop-reduce` are built on.

---

## 5. Canonicalization

### 5.1 What canonical form is, and why it is not enforced

Session 1 introduced the term. Chapter 8 gives the consequences. For `a = b - c`:

```llvm
%a = sub i64 %b, %c                 ; canonical

%neg_c = sub i64 0, %c              ; equally valid, not canonical
%a = add i64 %b, %neg_c
```

Two consequences:

1. in the standard pipeline, anything not canonical will be canonicalized
2. **optimizations are tested almost exclusively on the canonical form** — feed
   them non-canonical IR and they miss opportunities or hit rough edges

So why not canonicalize at construction? Because one target's preferred form is
another's adverse form. The right-hand version suits a target with add and negate
but no subtract, and LLVM deliberately leaves that representable.

And there is no specification:

> "there is no documented canonical representation or one true canonicalization
> pass. Instead, this representation is something that evolves over time and that
> you build a feel for. The rule of thumb is that canonical representation is the
> simplest way you can represent something."

### 5.2 instcombine

`InstCombinePass` (legacy `InstructionCombiningPass`), CLI `instcombine`, in its
own library under `Transforms/InstCombine`.

It does two distinguishable things.

**Canonical rewrites.** `ch8/canonical_form.ll` contains both spellings of `b - c`
in two functions; one pass and they converge:

```text
$ opt -passes=instcombine ch8/canonical_form.ll -S
define i64 @canonical_form(i64 %b, i64 %c)     { %a = sub i64 %b, %c  ... }
define i64 @non_canonical_form(i64 %b, i64 %c) { %a = sub i64 %b, %c  ... }
```

A canonical rewrite need not be faster. The book's `inttoptr` example expands an
implicit 64→32-bit truncation into an explicit `trunc` — identical cost, but now
other passes can see the added logic and fold it (`trunc (zext x)` → no-op).

**Optimizations.** `xor %x, %x` → `0`. Which is why `instcombine` is not in the
`-O0` pipeline, and that has a consequence the chapter states plainly:

> at `-O0` "the IR is mostly not in canonical form. This is okay because the
> expectation of an O0 pipeline is garbage in-garbage out. With that said, this
> means your lowering passes, that is, the ones that must run irrespective of the
> optimization level, must run correctly even in a non-canonical form."

If you only test at `-O2`, you will not discover this.

**Pipeline discipline.** Four operational points:

- most passes never think about canonical form; they rely on `instcombine` being
  re-run periodically
- so insert it in several places when building a pipeline — but it "can become a
  compile-time sink if you run it too often"
- once target-specific constructs appear, `instcombine` may **undo them** by
  restoring the canonical form
- hence the typical shape: `instcombine` heavily until target-specific passes are
  introduced, then not at all

Still want the folds after that point? Use the `simplifyXXXInst` helpers from
`Analysis` (`simplifyBinOp`, `simplifyAddInst`, …) — the simplification without the
canonicalization.

Scale, before you consider reading it: `llvm/test/Transforms/InstCombine` is about
1,500 files and 32k IR function definitions. The chapter's advice is to use it, not
read it, and to upstream missing patterns that are good for all targets.

### 5.3 mem2reg

`PromotePass` (legacy `PromoteLegacyPass`), CLI `mem2reg`, `TransformsUtils`.

Not really canonicalization, but grouped there because "the IR produced by this
pass is the starting point of any sane optimizations". Without it every pass would
have to track memory locations and use alias analysis, and you would get none of
SSA's def-use chains or dominance — "stuck with a compiler technology of another
age".

The `lab/ir/mem2reg.ll` input covers three cases, and the middle one is the
important one:

```llvm
; @needs_phi: the C-level variable is assigned in two blocks
merge:
  %slot.0 = phi i64 [ %x, %then ], [ 0, %else ]     ; mem2reg INSERTED this
  %res = add i64 %slot.0, 1
```

That is session 2's "mem2reg can split one C local variable into several SSA
values" made visible. `@escapes` is the negative case: the `alloca`'s address is
passed to another function, so the memory location must stay real and `mem2reg`
declines.

**Real pipelines run `sroa`, not `mem2reg`.** `mem2reg` can only promote an
`alloca` loaded and stored as a whole. Given a struct accessed field-by-field
through GEPs it does *nothing at all*, while `sroa` splits the aggregate first and
reduces the function to a single `add`. See exercise 1, answer 3, for the
one-command comparison. The chapter presents `mem2reg` because it is the concept;
`sroa` is what you would actually schedule.

### 5.4 lcssa

`LCSSAPass` (legacy `LCSSAWrapperPass`), CLI `lcssa`, `TransformsUtils`.

Loop-closed SSA guarantees no value defined in a loop is used outside it, by adding
phis in the exit blocks:

```llvm
end:
  %iv_plus_1.lcssa = phi i64 [ %iv_plus_1, %loop ]
  %tmp = add i64 %iv_plus_1.lcssa, %src
```

Walking `%iv_plus_1`'s def-use chain now yields only in-loop uses, plus the
`.lcssa` phi itself (which you still filter out — but everything else has moved).

The chapter's GPU aside is worth keeping: inside the loop the induction variable is
identical across lockstep threads, so on some AMD GPUs it can live in a cheap
*scalar* register. Outside the loop it cannot, since `%upper_bound` may differ per
thread. The `.lcssa` value captures exactly that boundary — a representation
choice enabling a lowering decision.

**LCSSA form is ephemeral:**

```text
$ opt -passes='lcssa,instcombine' lab/ir/loop.ll -S
end:
  %reass.add = shl i64 %iv_plus_1, 1
  %res = add i64 %src, %reass.add
```

`instcombine` folded away the single-incoming phi. So:

- place `lcssa` immediately before its consumer, never "early, once"
- if you write a **loop pass**, you get the form guaranteed by
  `LoopAnalysisManager` and cannot lose it (§3.2)

---

## 6. Optimization passes

Unlike canonicalization passes these exist purely for speed, and "may not even be
relevant for your target".

### 6.1 The identity card

```text
Pass name
Class pass name (legacy pass name)    CLI name
Description
In                                  | Out
Explanation of the example
Target-specific elements (if any)
```

Each input is `ch8/<cli_name>.ll`. `NA` in the legacy slot means no legacy
equivalent exists — a visible marker of the NPM migration from session 3.
`ArgumentPromotionPass`, `InlinerPass`, `IndVarSimplifyPass`, `SLPVectorizerPass`,
and `LoopVectorizePass` are all `NA`.

The chapter invites you to extend the list, which is exercise 3.

### 6.2 The thirteen, in brief

**IPO** (`Transforms/IPO`)

| Pass | CLI | What, and the catch |
|---|---|---|
| Argument promotion | `argpromotion` | by-reference → by-value. Legal only for `internal` functions, where all uses are visible so the ABI may change. The load moves into the caller — then `mem2reg` deletes the `alloca`/`store`/`load` |
| Dead argument elimination | `deadargelim` | drops unused parameters; again needs all call sites visible. Target-specific: **none** |
| Inliner | `inline` | uses **CGSCC** regions to order decisions from call-graph leaves upward — session 3's children-to-parents traversal with a purpose. `module-inliner` if you want a different order. `@bar` survives in the example because its linkage is not `internal` |

**Scalar** (`Transforms/Scalar`)

| Pass | CLI | What, and the catch |
|---|---|---|
| Dead code elimination | `dce` | zero users and no side effects. You wrote a miniature of this in session 2 |
| Induction variable simplification | `indvars` | trip count is statically known, so the whole chain leaves the loop and is re-expressed via `%ub`. Leaves `br i1 false` for `simplifycfg` |
| Loop invariant code motion | `licm` | hoists the loop-invariant load — legal only because nothing in the loop writes memory. Output carries an `.lcssa` phi because it is a loop pass. Needs `loop-mssa` scope |
| Loop strength reduction | `loop-reduce` | `%idx * 8` becomes `shl 3` plus an `i8` GEP whose scaling factor is 1. Aims at the target's addressing modes. **Requires a target triple** |
| Loop unrolling | `loop-unroll` | fewer branches, and new opportunities for vectorization and scheduling. Targets can override `TargetTransformInfo::getUnrollingPreferences` |
| Reassociate | `reassociate` | groups constants, cancels terms, **exposes CSE**. Hard part is legality: reordering FP arithmetic accumulates rounding differently — session 3's fast-math flags. Target-specific: **none** |
| CFG simplification | `simplifycfg` | removes constant-condition branches and merges blocks. Four blocks → one on `indvars`' output |

**Vectorize** (`Transforms/Vectorize`)

| Pass | CLI | Looks for |
|---|---|---|
| Load store vectorizer | `load-store-vectorizer` | longest chain of same-kind accesses to contiguous addresses |
| SLP vectorizer | `slp-vectorizer` | a straight-line run of similar scalar instructions |
| Loop vectorizer | `loop-vectorize` | a loop body that can process several iterations at once |

### 6.3 Vectorizers need a real target

```llvm
target triple = "aarch64-apple-ios"
```

Which vector types exist is target information carried by `TargetLowering` beneath
`TargetTransformInfo`. Omit the triple and you silently get a default target model:
the pass still runs, still succeeds, and produces IR that does not match what your
compiler produces. That is quiz 5, and there is no error message — the most likely
way this chapter's material bites you.

Note that `ch8/slp-vectorizer.ll` has its triple line **commented out** while
`load-store-vectorizer.ll` and `loop-reduce.ll` do not. Uncommenting it is a
one-line experiment.

### 6.4 The recurring theme — and the bridge to Chapter 9

| API | Consulted by |
|---|---|
| `TargetTransformInfo` | argpromotion, inline, indvars, licm, loop-reduce, loop-unroll, simplifycfg, all three vectorizers |
| `TargetLibraryInfo` | dce, indvars, licm, slp-vectorizer, loop-vectorize |
| `TargetLowering` | loop-reduce, load-store-vectorizer, loop-vectorize |

Only `deadargelim` and `reassociate` consult nothing.

The division of labour is consistent: **`TargetLibraryInfo` tends to answer
legality, `TargetTransformInfo` profitability.** (`TargetLibraryInfo`: is this
library call really side-effect-free, does this target have a conforming
`putchar`. `TargetTransformInfo`: is the new sequence cheaper, does this
signature fit the ABI, is this immediate expensive.)

These are not trivia; they are the sockets. Chapter 9 is: subclass
`TargetTransformInfo`, supply your target's costs, add your own intrinsics, inject
your passes into the default pipeline. Every generic pass above then optimizes for
your target without you writing any of them.

---

## 7. Things that are important and are not passes

A recurring shape in this chapter, easy to miss because the chapter is organised
around passes:

| Thing | Where | How you use it |
|---|---|---|
| `ValueTracking` | `Analysis` | call `computeKnownBits` |
| `simplifyXXXInst` | `Analysis` | call it directly, instead of running `instcombine` |
| `simplifyCFG` | `TransformUtils` | call it, instead of running `simplifycfg` |
| `DomTreeUpdater` | `Analysis` | maintain `domtree` yourself |
| `LibCallSimplifier` | `Transforms/Utils` | no CLI name at all; run `instcombine` to get it |

The last one is exercise 1's trick question. `printf("x")` → `putchar('x')` has no
`-passes=` name; it is a helper class invoked from `instcombine`. Searching
`--print-passes` for it finds `libcalls-shrinkwrap` and
`partially-inline-libcalls`, neither of which is it.

The general lesson for pipeline construction: if you want one specific behaviour, a
helper function may be a better fit than scheduling a whole pass — especially when
that pass would also canonicalize away your target-specific work (§5.2).

---

## 8. Quiz answers

1. **Is a CLI name part of the middle end?** Look for it in `opt --print-passes`
   under `Module`/`CGSCC`/`Function`/`Loop`. If it only appears in `--help`, or only
   under `Machine ...`, `opt` cannot run it as an IR pass.
2. **An existing pass crashes on your custom pass's output.** Run the verifier on
   that output first. Invalid IR must never reach a pass. Use `-verify-each` to
   attribute the breakage to the right pass.
3. **Where is CSE?** `Transforms` (optimization), not `IPO` (function-scoped), not
   `Vectorize` → `Scalar`. `llvm/lib/Transforms/Scalar/EarlyCSE.cpp`.
4. **What removes `indvars`' leftover `br i1 false`?** `simplifycfg` — but
   `-passes='indvars,simplifycfg'` fails because `indvars` sets a loop scope. Use
   `-passes='loop(indvars),simplifycfg'`.
5. **Vectorizer test does not match your real compiler's output.** Probably no
   `target triple`, so `TargetLowering` supplied a default target model instead of
   your target's vector preferences.

Three additions this module's material suggests:

6. **You put the IR in LCSSA form early and the consuming pass sees no `.lcssa`
   values.** Something between — likely `instcombine` — removed the extra phi. Place
   `lcssa` immediately before its consumer, or write a loop pass and get the
   guarantee for free.
7. **Your target-specific rewrite keeps being reverted.** `instcombine` restored the
   canonical form. Either stop running it after target-specific constructs appear,
   or use the `simplifyXXXInst` helpers.
8. **Why is `-O0` IR non-canonical, and why does it matter?** `instcombine` is an
   optimization and does not run at `-O0`. It matters because lowering passes run at
   every level, so they must be correct on non-canonical IR.

---

## 9. Version notes

Verified on LLVM 22.1.8; the book targets LLVM 20.1.1.

**All 19 `ch8/` examples reproduce exactly**, including the vectorizers and
`loop-reduce`. This material is not version-fragile — which is the book's own claim
about itself, and it holds two major versions on.

Cosmetic differences only:

- intrinsic declarations carry more attributes (`nocreateundeforpoison` is new), so
  `diff` output includes an `attributes #0 = { ... }` line the book does not show
- `opt --print-passes` has more section headers than the chapter implies (§2.1),
  and the `Machine ...` sections are marked `(WIP)`

One substantive difference, documented in §3.1(c): the `loop-mssa` scope, which the
book does not mention and which `licm` requires.
