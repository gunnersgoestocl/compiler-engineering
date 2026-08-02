# <Human-readable pass name>

| | |
|---|---|
| **Class** | `XXXPass` (legacy: `XXXLegacyPass`, or `NA`) |
| **CLI name** | `xxx` |
| **Scope** | Module / CGSCC / Function / Loop |
| **Source** | `llvm/lib/Transforms/<dir>/<File>.cpp` |
| **Library** | ScalarOpts / IPO / Vectorize / TransformsUtils / ... |

## Description

<Two or three sentences. What does it do, and what is it *for*? State the goal, not
just the mechanism — "reduces branching overhead and exposes vectorization
opportunities" is more useful than "duplicates the loop body".>

## In / Out

```llvm
; In -- ir/<cli-name>.ll
```

```llvm
; Out
```

Reproduce with:

```sh
opt -passes='<pipeline>' ir/<cli-name>.ll -S
```

## Explanation of the example

<What happened between In and Out, referring to specific value names. If the pass
left something behind for another pass to clean up, say which pass — that is
usually the most useful sentence on the card.>

## Legality

<What must be true for this transformation to be valid? Which analysis establishes
it? If the pass declines to fire on a nearly-identical input, show that input —
the negative case is often more informative than the positive one.>

## Target-specific elements

<`TargetTransformInfo` / `TargetLibraryInfo` / `TargetLowering`, and what each is
consulted *for* — legality or profitability. Cite the source line you found it on.
"None" is a valid answer; say so explicitly rather than leaving the field blank.>

## Would this matter for a new target?

<The chapter's framing: optimization passes "may not even be relevant for your
target". So: would you put this in your pipeline on day one, later, or never?
One sentence of justification.>

## Notes / surprises

<Anything that cost you time. Scope requirements, a needed `target triple`, a
pass it must be paired with, an interaction that undoes its work. This section is
the one your future self will actually reread.>
