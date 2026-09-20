# Exercise 3: Encode an Instruction

The upstream `ch11/instr_info` exercise stops at the Machine layer: describe the
operands, print the opcode. This one carries it through to chapter 12 — the
assembly syntax and the bit encoding — because that is where describing an
instruction stops feeling abstract.

It also still runs, which upstream's does not. See [A note on the upstream
exercise](#a-note-on-the-upstream-exercise).

## The target

16-bit instruction word. Four 16-bit registers `r0`–`r3`, encoded as 0–3.
`common.td` already defines those, plus one encoding family:

```
 15      12 11  10 9   8 7   6 5           0
+----------+------+-----+-----+-------------+
|  opcode  | dst  |src0 |src1 |      0      |    class ALU
+----------+------+-----+-----+-------------+
```

with `ADD` (`0b0001`) and `SUB` (`0b0010`) already using it.

## The task

Three tasks in `your_turn/instrinfo.td`, in increasing order of interest:

1. **`AND`, opcode `0b0011`** — reuse the existing family. One line. This is
   the payoff for having put the encoding in a class.
2. **`MOVI`** — `movi r1, 42`. A register and a 10-bit immediate do not fit the
   ALU layout, so write a second encoding family:
   ```
    15      12 11  10 9                       0
   +----------+------+-------------------------+
   |   0b1000 | dst  |        imm (10 bits)    |    class IMM
   +----------+------+-------------------------+
   ```
3. **Mark `MOVI` cheap to rematerialise** — one property, which chapter 13's
   machine passes read.

```sh
./run.sh              # build both, compare
./run.sh --check      # and assert yours matches
./run.sh solution     # just look at the reference output
```

## What to look for

`run.sh` shows four things, and each one is a different TableGen backend reading
the *same* records:

| Shown | Comes from | Built from |
|---|---|---|
| base encodings (`InstBits`) | `-gen-emitter` | `Inst{15-12} = opc` |
| operand bit placement | `-gen-emitter` | `Inst{11-10} = dst`, … |
| mnemonics | `-gen-asm-writer` | `AsmString` |
| operand counts and flags | `-gen-instr-info` | `OutOperandList`/`InOperandList` |

The thing worth noticing is that you write **no C++**. `let Inst{11-10} = dst;`
becomes, in the generated encoder:

```c
// op: dst
Value |= (op & 0x3) << 10;
```

The declarative bit positions *are* the encoder. That is the whole argument for
TableGen, and it is visible in about five seconds.

## Two traps

**Bit order.** Write ranges high-to-low: `Inst{9-0}`, not `Inst{0-9}`. Both are
legal TableGen and they mean opposite things. ISA documents draw bits
high-to-low, so matching them keeps the description readable against the spec.
This is chapter 12's quiz 2.

**The opcode is already shifted.** `MOVI`'s base encoding is not `8`, it is
`0b1000 << 12` = `0x8000` = `32768`. If `run.sh` shows the right instruction
with the wrong number, this is why.

## Going further

Three one-record experiments. All three build; what differs is what comes out.

**A. An instruction with no encoding.** Append:

```tablegen
def NOP : Instruction<> {
  let Namespace = "Tiny";
  let isPseudo = true;
  let OutOperandList = (outs);
  let InOperandList  = (ins);
  let AsmString      = "nop";
}
```

It builds, and `NOP` appears in the `-gen-emitter` output exactly **zero**
times. That is chapter 12's quiz 3: only instructions that reach the MC layer
need encodings, which is why `PHI` and `COPY` live at the Machine layer with no
bits at all.

**B. A second spelling.** Append:

```tablegen
def : InstAlias<"mov $dst, $src", (ADD GPR16:$dst, GPR16:$src, R0)>;
```

Now `-gen-asm-writer` emits a `printAliasInstr` containing the pattern, its
guard conditions, and the format string:

```c
{Tiny::ADD, 0, 1 },
{AliasPatternCond::K_RegClass, Tiny::GPR16RegClassID},
{AliasPatternCond::K_Reg, Tiny::R0},
/* 0 */ "mov $\x01, $\x02\0"
```

This is the branch the lab's `printInst` snippet takes when `PrintAliases` is
set — printing `mov r1, r2` for what is really `add r1, r2, r0`.

**C. Overlapping bit fields.** In `IMM`, widen the immediate to 12 bits and
extend its range, changing nothing else:

```tablegen
bits<12> imm;
let Inst{11-0}  = imm;     // now overlaps Inst{11-10} = dst
```

Predict what happens, then look at the generated encoder. It is not what most
people guess:

```c
case Tiny::MOVI: {
  // op: imm
  Value |= (op & 0xfff);
  break;
}
```

`dst` is **gone**. Not merged, not OR-ed in — the later `Inst{11-0}` assignment
replaced the earlier `Inst{11-10}` one, so the destination register is simply
never encoded, and TableGen says nothing. Every `movi` would write to `r0`.
Nothing in the description language stops you from describing an instruction
that cannot work; the ISA document is the only specification, and the encoder
is only as correct as your transcription of it.

## A note on the upstream exercise

`LLVM-Code-Generation/ch11/instr_info` does not build on LLVM 22. It fails with:

```
error: missing target override for pseudoinstruction using PointerLikeRegClass
```

LLVM now requires every target to say which register class the generic
pseudo-instructions' pointer operands use. The fix is one line, which
`epilogue.td` here carries:

```tablegen
defm : RemapAllTargetPseudoPointerOperands<GPR16>;
```

Add that to `ch11/instr_info/mytarget.td` and the upstream exercise builds
again. The book targets LLVM 20.1.1, where the line is not needed.

## Answers

`solution/instrinfo.td`.
