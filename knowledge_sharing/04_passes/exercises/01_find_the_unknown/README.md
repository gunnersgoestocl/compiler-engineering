# Exercise 1: Find the Unknown

Chapter 8 states two goals. The second one — "to teach you some of the ways you
can approach a transformation that you do not know" — is the one this exercise
drills.

You need an LLVM **source checkout** for this exercise, because the whole point is
navigating it. `opt` alone is not enough.

```sh
export LLVM_SRC=/path/to/llvm-project     # the repo, not the install prefix
```

## The task

For each description below, produce four things:

1. the **CLI name** (`opt -passes=...`)
2. the **scope** (Module / CGSCC / Function / Loop)
3. the **implementation file**
4. one **test** that exercises it, and the `RUN:` line from it

Do not search the descriptions verbatim — they are paraphrased, so string
matching will not save you. Use the two routes from the chapter:

- **top-down**: `opt --print-passes` for the scope, `opt --help` for descriptions,
  then `PassRegistry.def` or the description string to reach the source
- **bottom-up**: narrow by directory first (`Transforms/{IPO,Scalar,Vectorize,...}`),
  then read filenames

### The passes

| # | Description | Difficulty |
|---|---|---|
| 1 | Recognises that two computations produce the same value and reuses the first result instead of recomputing. | warm-up (this is quiz 3) |
| 2 | Removes a *group* of instructions that only feed each other — e.g. a loop counter whose sole consumer is its own increment. Plain `dce` cannot: each one has a user. | easy |
| 3 | Breaks an `alloca` of a struct or array into one `alloca` per field, so each piece can then be promoted to a register. | medium |
| 4 | Rotates a loop so the condition is tested at the *bottom* instead of the top, turning a `while` into a guarded `do/while`. | medium |
| 5 | When a conditional branch's condition is already known on *some* incoming paths, duplicates the block so those paths jump straight to their destination. | medium |
| 6 | Replaces a call to a known standard-library function with a cheaper equivalent — e.g. `printf` with a one-character constant format string becomes `putchar`. | harder: which directory? |
| 7 | Finds large constants that are expensive to materialise on the target, computes one *base* constant at a common dominator, and rewrites the others as cheap offsets from it. | harder: strongly target-influenced |

## Questions to answer as you go

- One of these is **not in `opt --print-passes` at all**. Which, and what does
  that tell you about how you would use it?
- Two of them consult `TargetTransformInfo`. Which, and where in the source is
  the call?
- Number 6 is not under `Transforms/Scalar` despite being scalar and non-IPO.
  Where is it, and does the chapter's directory table explain why?
- Number 7's CLI name appears in the chapter itself. Where? (Hint: the slide
  about nested pipelines.)

## Self-check

```sh
# Once you have a candidate name, confirm it exists and get its scope.
# Note that some entries carry a "<flag;flag>" suffix, so match loosely:
opt --print-passes | grep -n 'NAME'

# ...and confirm it actually runs:
opt -passes='NAME' ../../lab/ir/loop.ll -S -o /dev/null && echo OK
```

`--print-passes` has more sections than the chapter mentions: alongside
`Module/CGSCC/Function/Loop passes` there are `... passes with params` and
`... analyses` variants. A pass listed only under `... with params` is still a
normal pass; the suffix just means it accepts `<flags>`.

Answers, with the exact commands that find each one, are in `ANSWERS.md`. Read it
only after you have tried all seven — the commands are more useful than the names.
