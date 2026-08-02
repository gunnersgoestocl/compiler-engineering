# Exercise 2: Answers

All outputs below were produced with LLVM 22.1.8 via `./run.sh`.

---

## Case A — `mem2reg` before or after `dce`?

```text
$ opt -passes='dce,mem2reg' ir/order.ll -S
define void @dead_through_memory(i64 %in) {
entry:
  %v = mul i64 %in, 3      ; <-- dead, and nothing will ever remove it
  ret void
}

$ opt -passes='mem2reg,dce' ir/order.ll -S
define void @dead_through_memory(i64 %in) {
entry:
  ret void
}
```

**Why `dce` cannot see it in the first ordering.** `dce`'s question is "does this
instruction have zero users and no side effects?" At the time it runs:

- `%v` has a user — the `store`
- the `store` has a *side effect*, so it is not removable regardless of users

So `dce` correctly declines both. `mem2reg` then deletes the `alloca` and the
`store` (the slot is never loaded), and `%v` becomes garbage — but the pass that
collects garbage has already run.

**The lesson.** The chapter puts it as: run `mem2reg` "in your pipeline as soon as
possible", because "the IR produced by this pass is the starting point of any sane
optimizations". Case A is the narrow version of that claim: it is not that `dce`
is weak, it is that *before* `mem2reg` the dead value is hidden behind memory, and
reasoning about memory needs alias analysis. After `mem2reg` it is a plain SSA
value with no users, and the cheapest possible pass can see it.

Note this is also why a real pipeline reruns cheap cleanups *after* structural
passes rather than once at the front.

---

## Case B — `lcssa` then `instcombine`

```text
$ opt -passes='lcssa' ir/loop.ll -S
end:
  %iv_plus_1.lcssa = phi i64 [ %iv_plus_1, %loop ]
  %tmp = add i64 %iv_plus_1.lcssa, %src
  %res = add i64 %tmp, %iv_plus_1.lcssa

$ opt -passes='lcssa,instcombine' ir/loop.ll -S
end:
  %reass.add = shl i64 %iv_plus_1, 1
  %res = add i64 %src, %reass.add
```

**Where it went.** `instcombine` saw a phi with exactly one incoming value, which
is by definition redundant, and folded it away. (It also noticed
`x + src + x = src + 2x` and emitted a shift, which is incidental here.)

**Where `lcssa` belongs.** Immediately before its consumer. "Early, once" is wrong
because LCSSA form is not an invariant that later passes preserve — the chapter
calls it *ephemeral*. Any pass that simplifies phis can undo it, and `instcombine`
in particular is expected to run repeatedly throughout a pipeline.

**Why loop passes are exempt.** `LoopAnalysisManager` guarantees that the loops
handed to a loop pass's `run` method are already in LCSSA form. You do not request
it and cannot lose it, because the guarantee is re-established on entry to the loop
scope. The `printers` stage of `lab/run.sh` shows this happening: the function
printer sees no `.lcssa` value, the loop printer — same pipeline, same input, one
scope deeper — sees one.

That guarantee is also why `licm`'s output in the slides contains an `.lcssa` phi
that the input never had.

---

## Case C — who enables whom?

### C1: `instcombine` does not subsume `reassociate`

```text
$ opt -passes='instcombine' ir/order.ll -S      # @chain: all 9 instructions intact
$ opt -passes='reassociate' ir/order.ll -S
  %t5 = add i64 %a, 15
  %t6 = add i64 %t5, %b
  %t7 = add i64 %t6, %c
  %t8 = add i64 %t7, %d
  %t9 = add i64 %t8, %e
```

9 instructions to 5, and `1+2+3+4+5` collected into `15`. `instcombine` removes
*nothing*.

**Why.** `instcombine` is a large set of *local* rewrite patterns: it looks at an
instruction and its immediate operands. Folding this chain requires reordering
across nine instructions to bring the five constants adjacent — a global
reassociation over the whole expression tree, which is a different algorithm, not
a missing pattern. Adding more patterns would not fix it.

So the size of `instcombine`'s pattern library (~1,500 test files) is not a proxy
for reach. Passes are not totally ordered by strength.

### C2: `reassociate` exposes, `early-cse` eliminates

```text
$ opt -passes='instcombine,early-cse' ir/order.ll -S    # @cse_exposed: unchanged
  %x1 = add i64 %a, %b
  %x2 = add i64 %x1, %c
  %y1 = add i64 %b, %c
  %y2 = add i64 %y1, %a
  %r  = mul i64 %x2, %y2

$ opt -passes='reassociate' ir/order.ll -S
  %x1 = add i64 %b, %a
  %x2 = add i64 %x1, %c
  %y1 = add i64 %b, %a      ; <-- now IDENTICAL to %x1
  %y2 = add i64 %y1, %c     ; <-- now IDENTICAL to %x2
  %r  = mul i64 %y2, %x2

$ opt -passes='reassociate,early-cse' ir/order.ll -S
  %x1 = add i64 %b, %a
  %x2 = add i64 %x1, %c
  %r  = mul i64 %x2, %x2
```

Read the middle output carefully — it is the interesting one. `reassociate`
rewrote both chains into the *same* form and then stopped. It did not deduplicate
anything; the function still computes `b+a` twice. All it did was make the two
computations *syntactically identical*, which is precisely what "exposing CSE"
means.

`early-cse` then does the elimination. But run on the original IR it finds nothing,
because `(a+b)+c` and `(b+c)+a` are not the same expression tree — CSE matches
structure, not algebra.

**The implication.** Neither pass alone gets `%r = mul i64 %x2, %x2`. Picking
passes "by usefulness" one at a time would rate `reassociate` here as *useless*:
run it alone and the instruction count does not drop. Its value is entirely in
what it enables downstream. This is why the chapter's advice is to learn what
exists as a *catalog* rather than evaluating passes in isolation — and why real
pipelines interleave enablers with cleanups instead of sorting passes by
individual benefit.

---

## Case D — `instcombine` undoes your target-specific form

```text
$ opt -passes='instcombine' ir/target_form.ll -S
define i64 @target_prefers_add_and_negate(i64 %b, i64 %c) {
  %a = sub i64 %b, %c        ; your add+negate is gone
  ret i64 %a
}
```

Your pass produced a valid, deliberate, non-canonical form. `instcombine` restored
the canonical one, because that is its job — and it has no way to know the form was
intentional.

**The two ways out, both from the chapter:**

1. **Stop running `instcombine` after target-specific constructs appear.** The
   chapter describes this as the normal pipeline shape: "a typical compiler
   pipeline uses instcombine heavily in the middle-end pipeline until
   target-specific passes are introduced. At this point, instcombine is not
   invoked anymore."

2. **Use the `simplifyXXXInst` helpers directly** (`Analysis` library):
   `simplifyBinOp`, `simplifyAddInst`, and friends. You get instcombine-grade
   folding without the canonicalization step that reverts your work.

**The related trap, worth stating.** Since `instcombine` does not run at `-O0`,
the IR there is mostly *not* canonical. Any pass that must run at every
optimization level — your lowering passes — has to be correct on non-canonical
input. If you only ever test at `-O2`, you will not find out.

---

## A defensible ordering

One reasonable answer to the closing task. There is no single correct pipeline;
what matters is that each position has a reason.

```sh
opt -passes='function(mem2reg,instcombine,reassociate,instcombine,\
                      loop-mssa(licm,indvars),simplifycfg,dce)'
```

| Position | Why there |
|---|---|
| `mem2reg` first | everything downstream wants SSA values, not memory (Case A) |
| `instcombine` | canonicalize before passes that assume canonical form |
| `reassociate` | an enabler; needs canonical input, produces work for the next cleanup (Case C) |
| `instcombine` again | collect what `reassociate` exposed — the cleanup pattern |
| `loop-mssa(...)` | scope keyword required: `licm` and `indvars` are Loop passes. See below for why `loop-mssa` and not `loop` |
| `licm` before `indvars` | hoisting invariants first gives `indvars` a simpler loop |
| `simplifycfg` | cleans up the constant branches `indvars` leaves (quiz 4) |
| `dce` last | after the structural passes have exposed dead values |

On `lab/ir/loop.ll` this collapses the entire loop:

```text
define i64 @def_in_loop_use_outside(i64 %src, i64 %upper_bound) {
entry:
  %umax = call i64 @llvm.umax.i64(i64 %upper_bound, i64 1)
  %reass.add = shl i64 %umax, 1
  %res = add i64 %reass.add, %src
  ret i64 %res
}
```

### A third scope, which the chapter does not mention

Write `loop(licm, indvars)` in that pipeline and it dies — but only once it
actually meets a loop:

```text
$ opt -passes='loop(licm)' licm.ll -S
LLVM ERROR: LICM requires MemorySSA (loop-mssa)
```

There are **two** loop scopes in the new pass manager:

| Scope | Provides |
|---|---|
| `loop(...)` | the loop guarantees (LCSSA form, innermost-first order) |
| `loop-mssa(...)` | the same, plus a maintained `MemorySSA` |

`licm` reasons about memory — that is the whole basis of the legality argument in
the slides, that nothing in the loop writes memory — so it requires `MemorySSA`
and rejects the plain `loop` scope.

Two things make this worth its own note:

- **The bare form works.** `-passes=licm` is fine, because with no keyword the
  scope is *inferred*, and inference picks `loop-mssa`. So being explicit is what
  breaks it: you are overriding a correct default with a worse one.
- **It fails at run time, not parse time.** `opt` accepts the pipeline string and
  only aborts when a loop actually reaches `licm`. On input with no loops it
  passes silently — which is exactly how this survives a careless test.

Both are the same lesson as the `indvars,simplifycfg` trap in `lab/run.sh`, one
level deeper: the scope keyword is not decoration, it selects which guarantees the
pass manager establishes before your pass runs.

`lcssa` appears nowhere on purpose: `licm` and `indvars` are loop passes and get
LCSSA form guaranteed (Case B). Adding it explicitly would be harmless but
redundant — and putting it at the front would be actively misleading, since
`instcombine` would remove it before the loop passes ran.

Also note what this pipeline does *not* do: run `instcombine` after every pass.
The chapter warns it "can become a compile-time sink if you run it too often", so
two placements with a stated reason beats seven placements out of caution.
