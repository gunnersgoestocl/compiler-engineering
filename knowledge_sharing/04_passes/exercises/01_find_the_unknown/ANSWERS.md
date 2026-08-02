# Exercise 1: Answers

The **commands** matter more than the names. Each entry below shows the route, not
just the destination.

CLI names and scopes were confirmed against LLVM 22.1.8. Source paths are the
expected ones — confirm them in *your* checkout with the `git grep` shown, since
files do get moved between releases and this repo has no LLVM source tree in it.

---

## 1. Common subexpression elimination

| | |
|---|---|
| CLI name | `early-cse` (also `early-cse<memssa>`; `gvn` is the heavier relative) |
| Scope | Function |
| Source | `llvm/lib/Transforms/Scalar/EarlyCSE.cpp` |

The chapter answers this one itself, as quiz 3, purely by elimination on the
directory table: an optimization (`Transforms`), function-scoped (not `IPO`),
non-vector (not `Vectorize`) → `Scalar`.

```sh
$ ls $LLVM_SRC/llvm/lib/Transforms/Scalar | grep -i cse
EarlyCSE.cpp
GVN.cpp          # global value numbering -- CSE plus redundancy elimination
```

Worth knowing the pair: `early-cse` is the cheap local one meant to run often;
`gvn` catches more but costs more.

## 2. Aggressive dead code elimination

| | |
|---|---|
| CLI name | `adce` |
| Scope | Function |
| Source | `llvm/lib/Transforms/Scalar/ADCE.cpp` |

The distinction from `dce` is the whole point, and it is worth reproducing. Two
counters, only one of which anything depends on:

```llvm
define void @dead_cycle(i64 %ub) {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %loop ]    ; live: %c depends on it
  %d = phi i64 [ 0, %entry ], [ %d1, %loop ]    ; dead cycle
  %i1 = add i64 %i, 1
  %d1 = add i64 %d, 2
  %c = icmp ult i64 %i1, %ub
  br i1 %c, label %loop, label %end
end:
  ret void
}
```

`dce` asks "does this instruction have zero users?" — `%d` is used by `%d1` and
`%d1` by `%d`, so it keeps both, forever:

```text
$ opt -passes=dce dead_cycle.ll -S
  %i = phi i64 ...     %d = phi i64 ...     %i1 = add ...     %d1 = add ...
```

`adce` inverts the question: assume everything is dead, then mark live only what
is reachable *backwards* from something with an effect. Nothing observable
depends on `%d`, so the cycle goes — and `%i`'s cycle correctly stays, because
the branch needs it:

```text
$ opt -passes=adce dead_cycle.ll -S
  %i = phi i64 ...                          %i1 = add ...
```

Two things to be careful about when you build this yourself:

- Put **both phis at the top** of the block. Interleaving them with the `add`s
  gives `PHI nodes not grouped at top of basic block!` — the verifier again,
  catching a rule that is easy to forget.
- Do not use the *live* counter as your example of a dead cycle. `%i` feeds
  `%c`, which feeds a branch, and control flow is live by default, so `adce`
  keeps it. If your test shows `adce` changing nothing, this is probably why.

```sh
$ opt --help | grep -i 'aggressive dead'
```

## 3. Scalar replacement of aggregates

| | |
|---|---|
| CLI name | `sroa` (listed as `sroa<preserve-cfg;modify-cfg>`) |
| Scope | Function |
| Source | `llvm/lib/Transforms/Scalar/SROA.cpp` |

The relationship to `mem2reg` is the useful part, and it is a one-command
demonstration:

```llvm
%pair = type { i32, i32 }
define i32 @fields(i32 %a, i32 %b) {
entry:
  %p  = alloca %pair
  %f0 = getelementptr inbounds %pair, ptr %p, i32 0, i32 0
  store i32 %a, ptr %f0
  %f1 = getelementptr inbounds %pair, ptr %p, i32 0, i32 1
  store i32 %b, ptr %f1
  %x = load i32, ptr %f0
  %y = load i32, ptr %f1
  %r = add i32 %x, %y
  ret i32 %r
}
```

```text
$ opt -passes=mem2reg fields.ll -S     # unchanged. every instruction survives.
$ opt -passes=sroa    fields.ll -S
define i32 @fields(i32 %a, i32 %b) {
entry:
  %r = add i32 %a, %b
  ret i32 %r
}
```

`mem2reg` can only promote an `alloca` that is loaded and stored *as a whole*; one
accessed field-by-field through GEPs is opaque to it, so it does nothing at all.
`sroa` splits the aggregate first, and then each piece is promotable.

This is why real pipelines run `sroa`, not `mem2reg`, even though the chapter
presents `mem2reg` — a good example of the chapter's own advice to check what
exists before reaching for the pass you happen to know.

```sh
$ opt --print-passes | grep sroa
$ git grep -l "class SROAPass" $LLVM_SRC/llvm
```

## 4. Loop rotation

| | |
|---|---|
| CLI name | `loop-rotate` (`loop-rotate<header-duplication;prepare-for-lto>`) |
| Scope | **Loop** |
| Source | `llvm/lib/Transforms/Scalar/LoopRotation.cpp` |

Note the directory: it is a *loop* pass, but loop passes live in `Scalar`, not in
a directory of their own — exactly what the chapter's table says ("This includes
many different optimizations, of which the loop optimizations are unrelated to
vectorization").

Being a Loop pass, this one walks into the scope trap from the lab:

```sh
$ opt -passes='loop-rotate,simplifycfg' ...   # fails
$ opt -passes='loop(loop-rotate),simplifycfg' ...   # works
```

## 5. Jump threading

| | |
|---|---|
| CLI name | `jump-threading` |
| Scope | Function |
| Source | `llvm/lib/Transforms/Scalar/JumpThreading.cpp` |

```sh
$ opt --help | grep -i 'jump thread'
$ git grep "jump-threading" $LLVM_SRC/llvm/lib/Passes/PassRegistry.def
```

Read the header comment on this one — it is a good example of the chapter's claim
that "some passes are more detailed; for instance, the description lists the
research paper that this pass is based on."

## 6. Library call simplification — the trick question

| | |
|---|---|
| CLI name | **none** |
| Scope | n/a |
| Source | `llvm/lib/Transforms/Utils/SimplifyLibCalls.cpp` |

There is no `-passes=simplify-libcalls`:

```sh
$ opt --print-passes | grep -i libcall
  declare-runtime-libcalls
  libcall-lowering-info
  runtime-libcall-info
  libcalls-shrinkwrap
  partially-inline-libcalls
```

None of those is it. `printf("x") → putchar('x')` lives in `LibCallSimplifier`,
a **helper class**, invoked *from* `instcombine` (and `aggressive-instcombine`).
So the way to "run" it is `-passes=instcombine`.

This is the same shape as `ValueTracking` from the chapter: important, in the
`Utils`/`Analysis` libraries, and *not a pass*. Which answers the README's
directory question — `Transforms/Utils` is for "generally useful passes or helper
functions used to transform the LLVM IR", and this is a helper function.

It is also the clearest example of `TargetLibraryInfo`'s purpose: the rewrite is
only legal if the target *has* a conforming `putchar`, and `TargetLibraryInfo` is
what knows that.

## 7. Constant hoisting

| | |
|---|---|
| CLI name | `consthoist` |
| Scope | Function |
| Source | `llvm/lib/Transforms/Scalar/ConstantHoisting.cpp` |

You have already seen this name: it is in the chapter's own nested-pipeline
example, `--passes='function(print,consthoist,loop(print),instcombine<...>)'`.
Reading that example carefully was the shortcut.

Strongly target-driven — it asks the target how expensive a given immediate is:

```sh
$ git grep -n "getIntImmCost" $LLVM_SRC/llvm/lib/Transforms/Scalar/ConstantHoisting.cpp
```

On AArch64 a 64-bit constant may need up to four `movk` instructions, so
materialising one base value and adding small offsets wins. On a target with
cheap large immediates the same pass finds nothing worth doing. It is a good
illustration of the chapter's warning that optimization passes "may not even be
relevant for your target".

---

## The three cross-cutting questions

**Not in `--print-passes`:** number 6. It is a helper class, so you cannot add it
to a pipeline — you get it by running `instcombine`, or by calling
`LibCallSimplifier` yourself.

**Consult `TargetTransformInfo`:** numbers 3 (`sroa`, for promotion profitability)
and 7 (`consthoist`, via `getIntImmCost` / `getIntImmCostInst`). Number 6 uses
`TargetLibraryInfo`, which is a different API — the distinction is the one the
chapter draws repeatedly: `TargetLibraryInfo` tends to answer *legality*,
`TargetTransformInfo` *profitability*.

**Scopes:** only number 4 is a Loop pass. Everything else here is Function-scoped
— consistent with the chapter's remark that most of what exists is in `Scalar`
and function-level.
