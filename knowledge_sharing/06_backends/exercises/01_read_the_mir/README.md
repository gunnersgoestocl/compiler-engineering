# Exercise 1: Read the MIR

Chapter 11 spends thirty pages teaching you to read one text format. This
exercise is the reading comprehension test. There is nothing to write and
nothing to build — six questions, pencil and paper, then `llc` to check.

Answers, with the commands that confirm each one, are in `ANSWERS.md`. Four of
the six are the chapter's own quiz questions.

---

## Q1 — Operand anatomy

This is real AArch64 output (`mir/sum4.mir`, from `mir/sum4.ll`):

```
BL @sink, csr_aarch64_aapcs, implicit-def dead $lr, implicit $sp,
   implicit $x0, implicit-def $sp
```

1. How many **explicit** operands does this instruction have, and what are they?
2. `$x0` holds the argument. Why is it *implicit* when the C source passed an
   argument explicitly?
3. What kind of operand is `csr_aarch64_aapcs`, and what does it assert?
4. `$lr` is marked `implicit-def dead`. A branch-with-link writes the return
   address to `$lr` — so why is that definition dead?

---

## Q2 — Is this SSA?

Assume the `dsub_x` sub-register indices describe non-overlapping quarters of a
128-bit register.

```
undef %4.dsub_0:dquad = COPY %0
      %4.dsub_1:dquad = COPY %1
      %4.dsub_2:dquad = COPY %2
      %4.dsub_3:dquad = COPY %3
```

1. Is this Machine IR in SSA form? Justify it with the *definition* of SSA at
   the Machine level, not with intuition.
2. What is `undef` doing on the first line, and why only the first?
3. Write the equivalent in SSA form. (Hint: one opcode does this, and it is
   named after what it builds.)

---

## Q3 — Block order is semantics

```
bb.1:
  successors: %bb.2

bb.2:
  ...

bb.3:
  ...
```

You move `bb.3` between `bb.1` and `bb.2` and change nothing else.

1. What breaks?
2. What would you have to add to make the move legal?
3. `successors:` is listed here. If you deleted that line, would the program's
   behaviour change? Would anything at all change?

---

## Q4 — A simpler command

```sh
llc --start-before=peephole-opt --stop-after=peephole-opt in.mir -o out.mir
```

1. Write a shorter command with the same effect.
2. Name one case where the two forms genuinely differ. (Chapter 11 has a note
   about this; it is about what `.mir` does *not* serialise.)

---

## Q5 — Shrink it yourself

Take the full dump and reduce it as far as you can:

```sh
export PATH="/opt/homebrew/opt/llvm/bin:$PATH"
llc -mtriple=aarch64 -stop-after=finalize-isel mir/sum4.ll -o /tmp/sum4-full.mir
wc -l /tmp/sum4-full.mir
```

Goal: the smallest file for which this still succeeds —

```sh
llc -mtriple=aarch64 -run-pass=peephole-opt /tmp/my-shrunk.mir -o -
```

1. Which **two** fields are mandatory?
2. You delete the LLVM IR section. What must now appear on the command line,
   and why? (Then: check whether omitting it actually fails *on your machine*,
   and explain the result — it is a trap.)
3. The function calls `@sink`. Delete the LLVM IR section entirely and the file
   no longer parses. What is the error, and what is the smallest IR section
   that fixes it? Chapter 11 gives the trick in one sentence; getting it to
   work takes one more line than the book implies.
4. `liveins` appears twice in the file, at two different nesting levels. One is
   safe to delete and one is not. Which, and why?

`mir/shrunk.mir` is a worked example for a different input — read its header
comment for the checklist, but do this one yourself first.

---

## Q6 — Name the stage

Three MIR headers from the same function at three points in the pipeline:

| | `isSSA` | `noPhis` | `noVRegs` |
|---|---|---|---|
| **A** | `false` | `true` | `true` |
| **B** | `true` | `false` | `false` |
| **C** | `false` | `true` | `false` |

1. Put A, B, C in pipeline order.
2. Name the pass that causes each transition.
3. `MachineCSE` requires SSA; `MachineCopyPropagation` requires no virtual
   registers. Which of A/B/C can each run on?
4. What happens if you run `MachineCopyPropagation` on the wrong one? Guess
   before you check — then check, because the answer is worth knowing.

---

## Self-check

```sh
export PATH="/opt/homebrew/opt/llvm/bin:$PATH"

# Q1: the real thing, with everything the dump knows
llc -mtriple=aarch64 -stop-after=finalize-isel mir/sum4.ll -o - | grep BL

# Q4: do the two commands produce identical output?
llc -mtriple=aarch64 -start-before=peephole-opt -stop-after=peephole-opt \
    mir/sum4.mir -o /tmp/a.mir
llc -mtriple=aarch64 -run-pass=peephole-opt mir/sum4.mir -o /tmp/b.mir
diff /tmp/a.mir /tmp/b.mir && echo identical

# Q6: produce all three stages and read their headers.
# Use the loop input -- sum4 has no PHI, so PHI elimination has nothing to
# show you even though it still flips the properties.
for p in finalize-isel phi-node-elimination virtregmap; do
  llc -mtriple=aarch64 -stop-after=$p ../../lab/ir/loop.ll -o /tmp/$p.mir
  printf '%-22s ' "$p"
  grep -hoE '(isSSA|noPhis|noVRegs): *[a-z]+' /tmp/$p.mir | tr -s ' ' | tr '\n' ' '
  echo
done

# ...and watch the PHI actually disappear
grep -c '= PHI ' /tmp/finalize-isel.mir /tmp/phi-node-elimination.mir
```

The lab's `pipeline` and `operands` stages cover the same ground with
commentary, if you would rather be walked through it:

```sh
../../lab/run.sh operands pipeline
```
