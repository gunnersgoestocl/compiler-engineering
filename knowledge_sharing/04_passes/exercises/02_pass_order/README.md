# Exercise 2: Order Matters

The chapter says most passes "rely on the fact that [`instcombine`] is re-run from
time to time in the pipeline to clean things up", and that when you build your own
pipeline "you may have to insert this pass in a few places". This exercise makes
the cost of getting that wrong concrete.

One input, several pipelines. Predict each output *before* running it.

```sh
cd 08_passes/exercises/02_pass_order
export PATH="/opt/homebrew/opt/llvm/bin:$PATH"   # macOS/Homebrew
./run.sh              # runs every case and shows the output
./run.sh --check      # also asserts the invariant each case is meant to show
```

## Case A — `mem2reg` before or after `dce`?

```sh
opt -passes='dce,mem2reg' ir/order.ll -S
opt -passes='mem2reg,dce' ir/order.ll -S
```

`@dead_through_memory` computes a value, stores it in an `alloca`, and never reads
it back.

- Which order removes more?
- Why can't `dce` see the dead computation in the other order?
- What does this say about the chapter's advice to "run [`mem2reg`] in your
  pipeline as soon as possible"?

## Case B — `lcssa` then `instcombine`

Already shown in `lab/run.sh` (`lcssa-ephemeral`), restated here as a question:

```sh
opt -passes='lcssa'             ir/loop.ll -S
opt -passes='lcssa,instcombine' ir/loop.ll -S
```

- Where did the `.lcssa` phi go?
- You need LCSSA form for a pass you are about to run. Where in the pipeline do
  you put `lcssa`, and why is "early, once" wrong?
- Why does a *loop* pass not have this problem at all?

## Case C — who enables whom?

It is tempting to rank passes by strength and assume `instcombine` subsumes the
small ones. Both halves of this case say otherwise.

**C1.** A nine-instruction add chain with constants scattered through it:

```sh
opt -passes='instcombine' ir/order.ll -S     # look at @chain
opt -passes='reassociate' ir/order.ll -S
```

- How many instructions does each remove?
- `instcombine` has ~1,500 test files of patterns. Why does it not fold this one?

**C2.** `(a+b)+c` and `(b+c)+a` — the same value written two ways:

```sh
opt -passes='instcombine,early-cse' ir/order.ll -S   # look at @cse_exposed
opt -passes='reassociate'           ir/order.ll -S
opt -passes='reassociate,early-cse' ir/order.ll -S
```

The chapter says `reassociate` works partly "by exposing common subexpression
elimination". This is that sentence, executable.

- After `reassociate` alone, how many `add` chains are left, and are they
  identical?
- Which single pass performs the elimination, and why can it not do so without
  `reassociate` first?
- Neither pass alone reaches `%r = mul i64 %x2, %x2`. What does that imply about
  choosing passes for a pipeline "by usefulness"?

## Case D — the trap in the other direction

```sh
opt -passes='instcombine' ir/target_form.ll -S
```

`ir/target_form.ll` contains the non-canonical `add %b, (sub 0, %c)` shape the
chapter uses as its example — pretend a target-specific pass of yours produced it
deliberately, because your imaginary target has add and negate but no subtract.

- What does `instcombine` do to it?
- Your pass ran, produced the form you wanted, and a later `instcombine` undid it.
  The chapter gives two ways out. What are they?

## Write it down

Finish with a pipeline of your own: given `mem2reg`, `instcombine`, `reassociate`,
`dce`, `licm`, `lcssa`, and `simplifycfg`, write an ordering you would defend, and
one sentence per pass saying why it is where it is. Mind the scopes — `licm` is a
Loop pass, so your pipeline string needs `loop(...)`.

`ANSWERS.md` has worked answers for all four cases.
