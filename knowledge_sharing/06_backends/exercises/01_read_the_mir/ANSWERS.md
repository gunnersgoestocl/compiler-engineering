# Answers — Read the MIR

Verified on **LLVM 22.1.8** (Homebrew), host `arm64-apple-darwin`.

The commands matter more than the answers. Where the observed behaviour differs
from what the book leads you to expect, that is called out.

---

## Q1 — Operand anatomy

```
BL @sink, csr_aarch64_aapcs, implicit-def dead $lr, implicit $sp,
   implicit $x0, implicit-def $sp
```

**1. Two explicit operands:** the symbol `@sink` and the register mask
`csr_aarch64_aapcs`. Everything after them is implicit, as the `implicit` /
`implicit-def` keywords say. Note there is nothing left of the `=`: this
instruction has **no explicit definitions at all**.

That ordering is not incidental. `MCInstrDesc` guarantees it:

1. explicit definitions (registers only)
2. explicit arguments, in the order the instruction description lists them
3. implicit operands, defs and uses mixed, in no specified order

The third group has no guaranteed order precisely because you may append to it
at will.

**2. `$x0` is implicit because the ABI is not part of the instruction.** A
branch-with-link takes one operand — where to branch. That the callee reads its
first argument from `$x0` is a convention the *compiler* enforces, not something
encoded in the instruction. The final assembly is just `bl sink`; none of these
registers appear in it.

This is the second use of implicit operands, and the one the chapter is careful
about: they model hardware constraints (x86's `eflags`) *and* compiler-imposed
facts like this. Only the first kind is statically known — which is why you can
add implicit operands dynamically, while the explicit ones are fixed by
`MCInstrDesc`.

**3. `csr_aarch64_aapcs` is a register mask** (`MachineOperand::isRegMask`). It
asserts that every register in it is **preserved** — unmodified — across this
instruction. These are the callee-saved registers of the AAPCS calling
convention. A mask is a compact bitvector standing in for a list that would
otherwise be dozens of `implicit` operands.

Note the direction of the encoding: the mask lists what *survives*, so
everything absent from it is implicitly clobbered.

**4. `$lr` is `dead` because nobody reads the return address.** `BL` does write
it, so the definition must be modelled — but `@sink` returns normally and
control comes back by the ordinary path. Nothing in this function ever reads
`$lr`, so liveness marks the definition dead. `dead` is an assertion about the
*uses*, not about whether the write happens.

```sh
llc -mtriple=aarch64 -stop-after=finalize-isel mir/sum4.ll -o - | grep BL
```

---

## Q2 — Is this SSA?

```
undef %4.dsub_0:dquad = COPY %0
      %4.dsub_1:dquad = COPY %1
      %4.dsub_2:dquad = COPY %2
      %4.dsub_3:dquad = COPY %3
```

**1. No.** This is chapter 11's quiz 1, and it is a trick question.

At the Machine level the rule is exactly: *the IR is in SSA form so long as
every virtual register is defined at most once.* The unit of that rule is the
**virtual register**, not the sub-register lane. `%4` appears on the left of `=`
four times, so `%4` has four definitions, so this is not SSA — and it does not
matter at all that the four `dsub_x` indices are disjoint.

The intuition that says "but they write different bits, so it is fine" is
reasoning about *liveness*, which is a different question from SSA-ness.

**2. `undef` marks the first definition as a whole-register definition of an
undefined value.** Lines 2–4 are partial writes: they modify part of `%4` and
leave the rest alone, which means they *read* the register they write, and a
read needs a prior definition. `undef` on the first one says "there is no
meaningful prior value; do not treat this as a use." Without it the first line
would read an undefined register and the verifier would object. Only the first
needs it — after that, `%4` has a definition to build on.

**3. The SSA form uses `REG_SEQUENCE`**, which builds a wide register from
pieces in one definition:

```
%sub0:... = COPY %0
%sub1:... = COPY %1
%sub2:... = COPY %2
%sub3:... = COPY %3
%4:dquad = REG_SEQUENCE %sub0, %subreg.dsub_0, %sub1, %subreg.dsub_1,
                        %sub2, %subreg.dsub_2, %sub3, %subreg.dsub_3
```

One definition of `%4`, so SSA holds. The operands alternate value and
sub-register index. `REG_SEQUENCE` is a pseudo-instruction — it carries no
encoding and must be eliminated before the MC layer.

This is also why `PeepholeOptimizer` wants `isRegSequenceLike` and
`getRegSequenceInputs` from your `TargetInstrInfo` (chapter 13): pulling these
sequences apart is how it makes register allocation cheaper.

---

## Q3 — Block order is semantics

**1. The program breaks, because `bb.1` has no terminator.**

`bb.1` is empty and ends without a branch, so control *falls through* to
whatever block is printed next. The `body` field lists blocks in the order they
will be emitted into the final assembly — the linear order is semantics, not
presentation. Move `bb.3` in between and `bb.1` now falls through to `bb.3`.

The `successors: %bb.2` line does not save you. It is metadata describing the
CFG; it emits no instruction.

**2. Give `bb.1` an explicit terminator** — an unconditional branch to `bb.2`
(`B %bb.2` on AArch64). Then the block's exit no longer depends on what is
printed after it and the move is safe.

**3. Deleting `successors:` changes nothing about behaviour, but it does change
something.** The parser rebuilds the successor list from the terminators, so
the CFG survives. What is lost is the branch **probabilities**: the rebuilt list
is uniform, so a block with two successors becomes 50/50.

That is invisible for most passes and fatal for a few — anything driven by
profile weight, such as block placement. Chapter 11's advice is the useful
compromise: keep `successors:` *without* the `(0x...)` probabilities. You keep a
readable summary of the control flow and drop the fragile numbers.

---

## Q4 — A simpler command

**1.**

```sh
llc -mtriple=aarch64 -run-pass=peephole-opt mir/sum4.mir -o out.mir
```

`--start-before=X --stop-after=X` means "run the pipeline from just before X
until just after X" — i.e. only X. `-run-pass=X` says that directly, and it
bypasses the target's pipeline instead of slicing it.

Verified identical here:

```sh
llc -mtriple=aarch64 -start-before=peephole-opt -stop-after=peephole-opt \
    mir/sum4.mir -o /tmp/a.mir
llc -mtriple=aarch64 -run-pass=peephole-opt mir/sum4.mir -o /tmp/b.mir
diff /tmp/a.mir /tmp/b.mir && echo identical      # -> identical
```

**2. They differ when the pipeline slice includes more than the named pass.**
`-run-pass` builds a fresh pipeline containing only what you list; the
`start/stop` pair runs the *target's* pipeline with the ends cut off, so
anything the backend injected adjacent to `peephole-opt` still runs.

The deeper difference is the one chapter 11 warns about, and it applies whenever
you chain `llc` invocations through `.mir`: **the format does not serialise
analysis state.** Run `-run-pass=opt1`, then `-start-after=opt1` on the output,
and any analysis `opt1` failed to invalidate is silently recomputed from scratch
between the two invocations. A single `-start-before=opt1` would have exposed
the stale data to `opt2`. If a bug reproduces in one form and not the other,
suspect this first.

---

## Q5 — Shrink it yourself

**1. `name` and `tracksRegLiveness`.** Everything else is either recomputed or
defaulted. A 21-line body-only file is enough:

```
---
name:            sum4
tracksRegLiveness: true
body:             |
  bb.0:
    liveins: $x0, $x1, $x2, $x3
    ...
...
```

**2. `-mtriple=aarch64` must go on the command line.** The triple lived in the
LLVM IR section's `target triple`; deleting the section deletes it.

**The trap:** on an Apple-silicon Mac, omitting `-mtriple` *works anyway* —

```sh
llc --version | grep 'Default target'      # -> arm64-apple-darwin25.6.0
llc -run-pass=peephole-opt mir/shrunk.mir -o /dev/null   # succeeds
```

because `llc` falls back to the host triple, and the host is already AArch64.
The same file on an x86 host fails, and you can see the failure mode here by
forcing the wrong triple:

```sh
llc -mtriple=x86_64 -run-pass=peephole-opt mir/shrunk.mir -o /dev/null
# error: unknown register name 'x0'
```

So "it worked without `-mtriple`" is not evidence that the triple is
unnecessary — only that you got lucky on this machine. Chapter 11's note about
re-supplying `mtriple` (and `mattr`) is right; the accident of a matching host
is what makes it easy to forget.

**3. The error is a parse failure on the callee symbol:**

```
error: use of undefined global value '@sink'
```

The chapter's sentence is: "you can shrink the LLVM IR section manually: just
define empty functions! The parser for the `.mir` file will succeed if it finds
the symbols in the LLVM IR section." True — but once you provide an IR section
at all, the automatic synthesis stops, and the `MachineFunction` needs a
matching `Function` too. Declaring only `@sink` gets you:

```
error: function 'sum4' isn't defined in the provided LLVM IR
```

So the smallest IR section is **two** lines, not one:

```
--- |
  declare void @sink(i64)
  define i64 @sum4(i64 %a, i64 %b, i64 %c, i64 %d) { unreachable }
...
```

25 lines total, and it runs. Note that the stub body is `unreachable` and the
argument list is pure decoration — the parser only checks that it parses, never
that it is semantically related to the Machine IR. That is the real content of
the chapter's claim.

It is all-or-nothing: **no** IR section (and then no symbol references anywhere
in the body), or an IR section that accounts for every symbol *and* every
function. If you only need to lose the bulk, the other route is to replace the
symbol — `BL @sink` becomes `BL 0` — which changes the semantics but usually
preserves the behaviour you are chasing.

**4. The top-level `liveins:` can go; the one inside `body:` cannot.**

- The **top-level** field maps physical registers to the virtual registers they
  enter in, which matters almost only for instruction-selection issues.
- The one **inside the body**, under `bb.0:`, states which physical registers
  hold live values on entry to that block. Delete it and the incoming arguments
  are assumed dead, so any pass that trusts liveness may reuse `$x0`–`$x3`
  freely and quietly destroy the function.

They are spelled the same and nest at different levels, which is the whole trap.
Check the indentation before deleting.

---

## Q6 — Name the stage

**1. Order: B → C → A.**

**2 & 3.**

| | `isSSA` | `noPhis` | `noVRegs` | Stage | Reached by | `MachineCSE`? | `MachineCopyPropagation`? |
|---|---|---|---|---|---|---|---|
| **B** | `true` | `false` | `false` | SSA, virtual regs | instruction selection | yes | no |
| **C** | `false` | `true` | `false` | non-SSA, virtual regs | `phi-node-elimination` | no | no |
| **A** | `false` | `true` | `true` | physical regs | register allocation (`greedy` + `virtregrewriter`) | no | yes |

Reproduce:

```sh
for p in finalize-isel phi-node-elimination virtregmap; do
  llc -mtriple=aarch64 -stop-after=$p ../../lab/ir/loop.ll -o /tmp/$p.mir
  printf '%-22s ' "$p"
  grep -hoE '(isSSA|noPhis|noVRegs): *[a-z]+' /tmp/$p.mir | tr -s ' ' | tr '\n' ' '
  echo
done
```

PHI elimination is what ends SSA, and the mechanism is worth seeing: the PHI
becomes `COPY` instructions in the predecessor blocks, and because one copy
lands in each predecessor, the destination virtual register gets **two**
definitions. Same values, same dataflow, no longer SSA.

A pass declares its requirement by overriding
`MachineFunctionPass::getRequiredProperties`. If it does not override it, the
pass runs anywhere — though it may still behave differently per stage.

**4. It crashes.** Not a diagnostic, not a graceful skip:

```sh
llc -mtriple=aarch64 -stop-after=virtregmap ../../lab/ir/loop.ll -o /tmp/ok.mir
llc -mtriple=aarch64 -run-pass=machine-cp /tmp/ok.mir -o /dev/null   # fine

llc -mtriple=aarch64 -stop-before=peephole-opt ../../lab/ir/loop.ll -o /tmp/ssa.mir
llc -mtriple=aarch64 -run-pass=machine-cp /tmp/ssa.mir -o /dev/null
# Stack dump: Running pass 'Machine Copy Propagation Pass'
# exit status 138  (SIGBUS)
```

A release build does not check required properties; the assertion that would
have caught this is compiled out. So the property system **documents** the
pipeline without defending it, and a pass injected at the wrong stage fails as
a crash — or, worse, as quietly wrong code.

Practical consequence for chapter 13: when you pick a `TargetPassConfig::addXXX`
hook, the properties table is the thing to check first, and `-verify-machineinstrs`
is worth turning on while you are still deciding.
