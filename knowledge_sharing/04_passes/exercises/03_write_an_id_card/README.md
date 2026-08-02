# Exercise 3: Write an Identity Card

This is the exercise that matters. Everything else in this module hands you a pass
and explains it; here you pick a pass nobody explained and produce the
explanation yourself.

The chapter introduces its card format and then says, explicitly:

> "Feel free to complete this list by yourself or produce your own card format!"

Take it up.

## The task

Pick **one** pass from the middle end that Chapter 8 does *not* cover, and fill in
`CARD_TEMPLATE.md`. Copy it to `cards/<cli-name>.md`.

Suggestions, roughly easiest first:

| Pass | Why it is interesting |
|---|---|
| `adce` | forces you to articulate what `dce` cannot do |
| `sroa` | forces you to articulate what `mem2reg` cannot do |
| `early-cse` / `gvn` | quiz 3's pass, and the difference between the two |
| `loop-rotate` | a Loop pass, so you meet the scope rules again |
| `jump-threading` | needs a CFG with a partially-known condition — harder to write input for |
| `consthoist` | strongly target-driven; try two triples and compare |
| `loop-deletion` | when *is* a loop removable? |
| `tailcallelim` | a legality argument you have to state carefully |
| `float2int`, `lower-switch`, `mergefunc`, `separate-const-offset-from-gep` | off the beaten path |

Do not pick something already in `08_passes/` or `ch8/`.

## What "done" looks like

The card is done when someone who has not read the pass's source can, from your
card alone:

1. say what the pass does, in one sentence, without using the pass's own name
2. predict the output for your `In` example before seeing your `Out`
3. reproduce your `Out` by running one `opt` command you supply
4. say whether the pass could matter for a hypothetical new target, and why

Point 3 is not optional and not a formality. **Write the input IR yourself and run
it.** Do not transcribe an example from a test file or from the pass's header
comment — those often rely on setup that is not visible in the snippet, and if you
have not run yours you do not know that your card is true.

## Method

Use the chapter's own procedure — it is the point of the exercise:

```sh
opt --print-passes | grep NAME             # does it exist, and at what scope?
opt --help | grep -A1 NAME                 # one-line description

git grep NAME $LLVM_SRC/llvm/lib/Passes/PassRegistry.def
git grep -l "class NamePass" $LLVM_SRC/llvm
#   -> read the header comment at the top of the .cpp

git grep -l 'RUN: .*NAME' $LLVM_SRC/llvm/test
#   -> read a test to learn what input shape triggers it,
#      then write your OWN minimal version
```

For the target-specific field, grep the implementation for the three APIs the
chapter kept naming:

```sh
git grep -nE 'TargetTransformInfo|TargetLibraryInfo|TargetLowering' <the-impl-file>
```

If there are no hits, "none" is a real and correct answer — `deadargelim` and
`reassociate` are both "none" in the chapter.

## Two traps you are likely to hit

Both are ones this module hit while being written, so they are not hypothetical:

- **Your pass appears to do nothing.** Check the scope first
  (`loop(...)` vs `loop-mssa(...)` vs bare), then check whether your input actually
  has the shape the pass looks for. A pass that finds nothing exits successfully
  and prints your input back at you.
- **Your example needs a `target triple`.** If the pass consults `TargetLowering`
  — anything vectorization- or address-related — a test without a triple gets a
  default target model. That is quiz 5, and there is no error message.

## Where to put it

```text
cards/
  README.md          # index; add a line for your card
  <cli-name>.md      # your card
```

`cards/loop-deletion.md` is a worked example to calibrate against. Read it after
you have drafted yours, not before.
