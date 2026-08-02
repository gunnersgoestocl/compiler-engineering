# Loop deletion

Worked example, for calibration. Everything below was produced by running the
commands shown, on LLVM 22.1.8.

| | |
|---|---|
| **Class** | `LoopDeletionPass` (legacy: `NA`) |
| **CLI name** | `loop-deletion` |
| **Scope** | Loop (plain `loop(...)` is fine — it does not need MemorySSA) |
| **Source** | `llvm/lib/Transforms/Scalar/LoopDeletion.cpp` |
| **Library** | ScalarOpts |

## Description

Removes a loop entirely when running it cannot affect the rest of the program: the
loop has no side effects, and no value it computes is used after it. The point is
not the loop's own cost — it is that other passes routinely *create* such loops
(`indvars` hoists a computation out, `dce` removes the last consumer) and someone
has to collect the empty shell that is left.

## In / Out

```llvm
; In -- ir/loop-deletion.ll
define void @dead_loop(i64 %ub) {
entry:
  br label %loop
loop:
  %iv  = phi i64 [ 0, %entry ], [ %iv1, %loop ]
  %iv1 = add nuw nsw i64 %iv, 1
  %c   = icmp ult i64 %iv1, %ub
  br i1 %c, label %loop, label %end
end:
  ret void
}

define void @has_side_effect(i64 %ub, ptr %p) mustprogress {
entry:
  br label %loop
loop:
  %iv  = phi i64 [ 0, %entry ], [ %iv1, %loop ]
  %iv1 = add i64 %iv, 1
  store i64 %iv, ptr %p
  %c   = icmp ult i64 %iv1, %ub
  br i1 %c, label %loop, label %end
end:
  ret void
}
```

```llvm
; Out
define void @dead_loop(i64 %ub) {
entry:
  br label %end
end:
  ret void
}

define void @has_side_effect(i64 %ub, ptr %p) #0 {
entry:
  br label %loop            ; unchanged
loop:
  %iv  = phi i64 [ 0, %entry ], [ %iv1, %loop ]
  %iv1 = add i64 %iv, 1
  store i64 %iv, ptr %p, align 4
  %c   = icmp ult i64 %iv1, %ub
  br i1 %c, label %loop, label %end
end:
  ret void
}
```

Reproduce with:

```sh
opt -passes='loop-deletion' ir/loop-deletion.ll -S
```

## Explanation of the example

In `@dead_loop`, the induction variable chain `%iv`/`%iv1` feeds only `%c`, and
`%c` feeds only the loop's own branch. Nothing outside the loop reads anything the
loop computes, and no instruction in it writes memory or calls anything. So the
loop is replaced by a direct branch to `%end` and its blocks are dropped.

`@has_side_effect` is identical except for the `store`. Stores are observable, so
the loop stays — untouched, not even partially simplified.

Note what is left behind: `br label %end` jumping to a block with one predecessor.
`loop-deletion` does not merge them. `simplifycfg` does, exactly as in the
`indvars` → `simplifycfg` pairing from `lab/run.sh`. Nearly every pass in this
chapter leaves something for a cleanup pass.

## Legality

Two conditions, and the second is the interesting one.

**1. No observable effects.** No stores, no calls that could have effects, no
volatile accesses, and no value live-out of the loop.

**2. The loop must be known to terminate.** Deleting a loop that runs forever is
not a valid optimization — non-termination is observable behaviour. Here are two
functions with *identical bodies*, differing only in an attribute:

```llvm
define void @unprovable(i64 %n) {                        ; no attribute
entry:
  br label %loop
loop:
  %iv  = phi i64 [ 0, %entry ], [ %iv1, %loop ]
  %iv1 = mul i64 %iv, 3        ; 0 * 3 == 0, forever
  %c   = icmp ult i64 %iv1, %n
  br i1 %c, label %loop, label %end
end:
  ret void
}
```

`%iv` starts at 0 and `%iv1 = %iv * 3` keeps it at 0, so if `0 < %n` this loop
never exits. The pass leaves it alone. Add `mustprogress` to the function and the
same loop is deleted:

```text
$ opt -passes='loop-deletion' ir/loop-deletion-legality.ll -S
define void @unprovable(i64 %n) {          ; loop KEPT
  ...
define void @unprovable_mp(i64 %n) #0 {    ; loop DELETED
entry:
  br label %end
end:
  ret void
}
```

`mustprogress` is the promise C++ and C make that a side-effect-free loop will
terminate; with it, looping forever is UB, so the pass may assume it does not
happen. Without it, LLVM must fall back on proving a finite trip count via
`ScalarEvolution`, and here it cannot.

This is a sharp instance of session 3's legality-before-profitability point: the
profitability question is trivial (deleting code is always cheaper), and the
entire pass is a legality argument.

## Target-specific elements

**None.**

```sh
$ git grep -nE 'TargetTransformInfo|TargetLibraryInfo|TargetLowering' \
    $LLVM_SRC/llvm/lib/Transforms/Scalar/LoopDeletion.cpp
$   # no hits
```

It depends on `LoopInfo`, `DominatorTree`, and `ScalarEvolution` — all generic.
Which makes sense: whether a loop is observable is a property of the IR's
semantics, not of any machine.

## Would this matter for a new target?

Yes, day one, and for free. It is target-independent, cheap, and cleans up after
passes you *will* be running (`indvars`, `licm`, `dce`). It belongs in the same
category as `mem2reg` and `simplifycfg`: not a performance play for your
architecture, just maintenance you would otherwise have to write yourself.

## Notes / surprises

- **Do not use the live counter as your dead-loop example.** My first attempt used
  a loop whose induction variable fed the exit condition and expected it to be
  deleted anyway. It is deleted — but for a subtler reason than I assumed, and the
  same mistake in the `adce` card (exercise 1, answer 2) produces a pass that
  appears to do nothing. Always write the negative case too.
- **`mustprogress` changes the answer.** If you are testing this pass against IR
  you wrote by hand, you do not get `mustprogress`, but IR from Clang generally
  does. So hand-written tests can make the pass look weaker than it is in a real
  pipeline. This is the same class of problem as quiz 5's missing `target triple`:
  the test is not wrong, it is just not the input the pass normally sees.
- **A volatile load is a side effect.** `load volatile` in the loop blocks deletion
  even though a plain `load` would not, which is a quicker way to write the
  negative case than a `store`.
