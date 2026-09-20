# Exercise 2: Register Units

This is the upstream `ch11/register_units` exercise, with the build step removed.
Upstream needs CMake, an installed LLVM, and a C++ compile to print the register
information. `llvm-tblgen` already prints everything we need, so this version
needs neither.

## The task

Fill in `your_turn/reginfo.td` so it describes the register hierarchy of
textbook Figure 11.2 — nine registers in three deliberately irregular layers.
The file carries the picture and the full instructions.

```sh
./run.sh              # build both descriptions, compare them
./run.sh --check      # and assert that yours matches
./run.sh solution     # just look at the reference output
```

## Predict first

Before running anything, answer these on paper:

1. **How many register units** does a nine-register, three-layer hierarchy need?
2. **Which** registers become units?
3. How many **register classes** will TableGen emit, given that you declare
   three?

Question 3 is the one nobody gets right, and it is the most interesting.

## What to look at in the output

`run.sh` reports three numbers per description.

| Number | Where it comes from |
|---|---|
| register descriptors | `InitMCRegisterInfo(Fig112RegDesc, N, ...)` |
| register classes | the `// XXX Register Class` comments |
| register units | the `Fig112RegUnitRoots[][2]` table |

The register-unit table is the payoff. The chapter's argument is that units let
you answer "do these two registers overlap?" in a bounded number of checks
instead of walking the hierarchy. You can see the bound directly: it is the
length of that table.

## Going further

Once `--check` passes, try each of these in `your_turn/reginfo.td` and re-run.
Each is a one-line edit, and each moves a different number. Predict all three
columns before running. The measured answers are at the bottom of this file —
the point is to be wrong first.

| Edit | regs | classes | units |
|---|---|---|---|
| baseline | 10 | 7 | 5 |
| **A.** delete `CoveredBySubRegs = true` from `d0` | ? | ? | ? |
| **B.** add an `s3`, make it `d1`'s high half | ? | ? | ? |
| **C.** add a 256-bit `q0_q1` tuple over `q0`+`q1` | ? | ? | ? |

For **C**, you are adding a register that *does not exist in the hardware* —
the chapter's pseudo-register:

```tablegen
def sub128_low  : SubRegIndex<128>;
def sub128_high : SubRegIndex<128, 128>;

def q0_q1 : Register<"q0_q1"> {
  let SubRegIndices = [sub128_low, sub128_high];
  let SubRegs = [q0, q1];
  let CoveredBySubRegs = true;
}
// ...and outside the namespace:
def QUADPAIRS : RegisterClass<"Fig112", [untyped], 256, (add q0_q1)>;
```

## Answers

`solution/reginfo.td` holds the reference hierarchy. Read it after `--check`
passes, not before — the interesting part is which registers do *not* get
`CoveredBySubRegs`, and you only notice that if you got it wrong first.

The three experiments, measured on LLVM 22.1.8:

| Edit | regs | classes | units |
|---|---|---|---|
| baseline | 10 | 7 | 5 |
| **A.** drop `CoveredBySubRegs` | 10 | 7 | **5** |
| **B.** add `s3` | 11 | **6** | **6** |
| **C.** add the `q0_q1` tuple | 11 | **8** | **5** |

- **A** moves nothing. Diff the generated files and the only change is one
  boolean in `...TargetDesc.inc`. `CoveredBySubRegs` says whether writing every
  sub-register fully defines the parent — a *liveness* question. Aliasing, and
  therefore the unit count, is decided entirely by `SubRegs`.
- **B** adds a unit (`s3` is a new leaf) and *removes* a register class. Giving
  `d1` a high half makes the hierarchy regular, and once every double has both
  halves, "a double" and "a double with an addressable low half" stop being
  different constraints. The synthesised classes were a symptom of the
  irregularity.
- **C** is the one that matters. A new register, a new class — and the unit
  count does not budge. Tuples multiply the number of addressable registers
  without adding leaves, so every interference check stays the same size. On a
  real target that is the difference between hundreds of registers and
  thousands, at no cost to the register allocator's inner loop. This is the
  entire argument for register units.
