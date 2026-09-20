#import "@preview/touying:0.6.1": *
#import themes.metropolis: *
#import "@preview/numbly:0.1.0": numbly
#import "@preview/cetz:0.4.2"

#show: metropolis-theme.with(
  aspect-ratio: "4-3",
  align: horizon,
  config-common(handout: true),
  config-info(
    title: [Into the Backend],
    subtitle: [Compiler Engineering \#5: Target constructs, Machine IR, and the machine pipeline],
    // author: [Gen Sakai],
    // date: [2026/09/11],
    // institution: [B4, Taura Laboratory, The University of Tokyo],
  ),
)

#set text(lang: "en", size: 21pt)
#show strong: set text(weight: "bold")
#let small(x) = text(size: 15pt, x)
#let note(x) = text(size: 15pt, style: "italic", fill: gray.darken(35%), x)

#show raw.where(block: true): it => block(
  fill: rgb("#1f2430"),
  inset: (x: 0.8em, y: 0.7em),
  radius: 4pt,
  width: 100%,
  text(fill: rgb("#e6edf3"), it),
)

#show raw.where(block: false): it => box(
  fill: rgb("#eef1f5"),
  inset: (x: 3pt, y: 1pt),
  radius: 3pt,
  text(fill: rgb("#b42318"), size: 16pt, it),
)

#set heading(numbering: (..nums) => {
  let level = nums.pos().len()
  if level <= 2 { numbly("{1}.", default: "1.1")(..nums) }
})

// --- Helpers ---------------------------------------------------------------

// A smaller code block, for MIR dumps that need the width.
#let code(body, size: 11pt) = [
  #show raw.where(block: true): it => block(
    fill: rgb("#1f2430"), inset: (x: 0.6em, y: 0.5em), radius: 4pt, width: 100%,
    text(fill: rgb("#e6edf3"), size: size, it),
  )
  #body
]

// Side-by-side before/after.
#let ba(lhs, rhs, lcap: "Before", rcap: "After") = [
  #show raw.where(block: true): it => block(
    fill: rgb("#1f2430"), inset: (x: 0.5em, y: 0.45em), radius: 3pt, width: 100%,
    text(fill: rgb("#e6edf3"), size: 9.5pt, it),
  )
  #table(
    columns: (1fr, 1fr), stroke: none, inset: 1.5pt, align: top,
    text(size: 12pt)[*#lcap*], text(size: 12pt)[*#rcap*],
    raw(lhs, block: true), raw(rhs, block: true),
  )
]

// A header table with the usual fill.
#let tbl(cols, ..rows) = table(
  columns: cols,
  stroke: 0.5pt,
  inset: 4pt,
  fill: (col, row) => if row == 0 { gray.lighten(40%) } else { white },
  ..rows,
)

// --- Diagram palette and figures -------------------------------------------
//
// Drawn with cetz rather than described in prose: these are the slides where a
// picture replaces a paragraph. Every number in them is produced by a lab
// stage, so the figures stay honest.

#let INK  = rgb("#1f2430")
#let IRC  = rgb("#dce7f5")   // LLVM IR blue
#let MIRC = rgb("#fbe0d6")   // Machine IR orange
#let MCC  = rgb("#dcf0e2")   // MC green
#let GREY = rgb("#e9ecf1")
#let HOT  = rgb("#b42318")

// Code labels inside a canvas. Deliberately NOT the raw element: the deck-wide
// inline-code show rule (red box, 16pt) would blow the labels apart, and a show
// rule does not reach inside a cetz canvas -- so the font is set directly.
#let m(body, size: 9.6pt, fill: INK, weight: "regular") = text(
  font: "DejaVu Sans Mono", size: size, fill: fill, weight: weight, body)

// The compilation pipeline. `highlight` boxes one stage; the dashed line is
// where LLVM IR ends and Machine IR begins.
#let fig-pipeline(highlight: none, len: 1.70cm) = align(center, cetz.canvas(length: len, {
  import cetz.draw: *
  for (label, col, x, w) in (
    ("input.c", GREY, 0.0, 1.5), ("LLVM IR", IRC, 1.8, 1.7),
    ("Machine IR", MIRC, 3.9, 2.1), ("MC", MCC, 6.4, 1.1), (".s / .o", GREY, 7.9, 1.4),
  ) {
    let sel = (highlight != none and label == highlight)
    rect((x, 0), (x + w, 0.72),
      fill: if sel { rgb("#fff3c4") } else { col },
      stroke: if sel { 1.2pt + HOT } else { 0.6pt + INK })
    content((x + w/2, 0.36), text(size: 10.2pt, weight: if sel { "bold" } else { "regular" }, label))
  }
  for (x0, x1) in ((1.5,1.8),(3.5,3.9),(6.0,6.4),(7.5,7.9)) {
    line((x0,0.36),(x1,0.36), mark: (end: ">", scale: 0.4), stroke: 0.6pt)
  }
  content((0.75, 1.08), text(size: 9.0pt, fill: gray.darken(30%))[frontend])
  content((2.65, 1.08), text(size: 9.0pt, fill: gray.darken(30%))[middle end])
  content((5.5, 1.08), text(size: 9.0pt, fill: gray.darken(30%))[backend])
  line((3.7,-0.5),(3.7,1.4), stroke: (paint: HOT, dash: "dashed", thickness: 0.9pt))
  content((3.7,-0.78), text(size: 9.6pt, fill: HOT, weight: "bold")[instruction selection])
}))

// A backend's directories, the library each becomes, and which chapter builds it.
#let fig-dirs = align(center, cetz.canvas(length: 1.22cm, {
  import cetz.draw: *
  content((1.3, 0.95), text(size: 10.2pt, weight: "bold")[directory])
  content((5.15, 0.95), text(size: 10.2pt, weight: "bold")[library])
  content((8.6, 0.95), text(size: 10.2pt, weight: "bold")[holds])
  content((12.2, 0.95), text(size: 10.2pt, weight: "bold")[ch.])
  let y = 0
  for (d, lib, what, ch) in (
    ("TargetInfo/",   "LLVMAArch64Info",         "the Target singleton",      "9"),
    ("MCTargetDesc/", "LLVMAArch64Desc",         "the MC layer",              "9, 12"),
    ("<root>/",       "LLVMAArch64CodeGen",      "TargetMachine, ISel, .td",  "9, 11, 13"),
    ("AsmParser/",    "LLVMAArch64AsmParser",    ".s → MCInst",               "12"),
    ("Disassembler/", "LLVMAArch64Disassembler", ".o → MCInst",               "—"),
    ("Utils/",        "LLVMAArch64Utils",        "shared helpers",            "—"),
  ) {
    rect((0, y), (2.6, y + 0.52), fill: GREY, stroke: 0.5pt)
    content((1.3, y + 0.26), m(d, size: 9.6pt))
    line((2.6, y + 0.26), (3.0, y + 0.26), mark: (end: ">", scale: 0.35), stroke: 0.5pt)
    rect((3.0, y), (7.1, y + 0.52), fill: IRC, stroke: 0.5pt)
    content((5.15, y + 0.26), m(lib, size: 9.6pt))
    content((8.6, y + 0.26), text(size: 9.6pt, what))
    content((12.2, y + 0.26), text(size: 9.6pt, fill: HOT, ch))
    y -= 0.62
  }
}))

// Who actually calls LLVMInitialize*.
#let fig-callchain = align(center, cetz.canvas(length: 1.22cm, {
  import cetz.draw: *
  let node(x, y, w, label, col, sz: 7.5pt) = {
    rect((x, y), (x + w, y + 0.62), fill: col, stroke: 0.55pt)
    content((x + w/2, y + 0.31), text(size: sz, label))
  }
  node(0, 0, 3.9, m("llvm/Config/Targets.def"), GREY)
  content((1.8, -0.32), text(size: 8.3pt, fill: gray.darken(30%))[generated at configure time])
  line((3.9, 0.31), (4.4, 0.31), mark: (end: ">", scale: 0.4), stroke: 0.55pt)
  node(4.4, 0, 4.2, m("TargetSelect.h") + text(size: 8.3pt)[ (macro)], IRC)
  line((6.5, 0), (6.5, -1.0), mark: (end: ">", scale: 0.4), stroke: 0.55pt)
  node(3.6, -1.62, 5.8, m("LLVMInitializeAArch64TargetInfo()"), MIRC, sz: 7pt)
  content((10.9, -1.31), text(size: 9.0pt)[× 20 backends])
  line((6.5, -1.62), (6.5, -2.6), mark: (end: ">", scale: 0.4), stroke: 0.55pt)
  node(4.4, -3.22, 4.2, m("TargetRegistry"), MCC)
  line((8.6, -2.91), (9.6, -2.91), mark: (end: ">", scale: 0.4), stroke: 0.55pt)
  node(9.6, -3.22, 3.6, m("lookupTarget(triple)"), GREY)
  content((6.5, -3.72), text(size: 8.3pt, fill: gray.darken(30%))[46 registered names])
}))

// Textbook Figure 11.2, with the register units TableGen computes underneath.
#let fig-regunits = align(center, cetz.canvas(length: 1.10cm, {
  import cetz.draw: *
  let cell(x, w, y, label, col) = {
    rect((x, y), (x + w, y + 0.55), fill: col, stroke: 0.55pt)
    content((x + w/2, y + 0.275), m(label, size: 10.2pt))
  }
  cell(0,4,2.0,"q0",rgb("#d7e3f4")); cell(4,4,2.0,"q1",rgb("#d7e3f4")); cell(8,4,2.0,"q2",rgb("#d7e3f4"))
  cell(0,2,1.25,"d0",rgb("#e3eef8")); cell(2,2,1.25,"d1",rgb("#e3eef8")); cell(4,2,1.25,"d2",rgb("#e3eef8"))
  cell(0,1,0.5,"s0",rgb("#eff5fb")); cell(1,1,0.5,"s1",rgb("#eff5fb")); cell(2,1,0.5,"s2",rgb("#eff5fb"))
  content((-0.95, 2.275), text(size: 9.6pt)[128-bit])
  content((-0.95, 1.525), text(size: 9.6pt)[64-bit])
  content((-0.95, 0.775), text(size: 9.6pt)[32-bit])
  for (x, w, lbl) in ((0,1,"u0"),(1,1,"u1"),(2,1,"u2"),(4,2,"u3"),(8,4,"u4")) {
    rect((x,-0.6),(x + w,-0.05), fill: rgb("#ffe9c9"), stroke: (paint: HOT, thickness: 0.7pt))
    content((x + w/2,-0.325), m(lbl, size: 10.2pt, fill: HOT, weight: "bold"))
  }
  content((-0.95,-0.325), text(size: 9.6pt, fill: HOT, weight: "bold")[units])
  content((13.3, 2.275), text(size: 10.2pt)[9 registers])
  content((13.3,-0.325), text(size: 10.2pt, fill: HOT, weight: "bold")[5 units])
}))

// A 16-bit instruction word, partitioned the way the .td file declares it.
#let fig-bits = align(center, cetz.canvas(length: 1.32cm, {
  import cetz.draw: *
  let total = 12.0
  let x = 0.0
  let hi = 15
  for (name, w, col) in (("opcode",4,MIRC), ("dst",2,IRC), ("src0",2,IRC), ("src1",2,IRC), ("0",6,GREY)) {
    let ww = total * w / 16
    rect((x, 0), (x + ww, 0.72), fill: col, stroke: 0.55pt)
    content((x + ww/2, 0.36), text(size: 10.2pt, name))
    content((x, 1.0), text(size: 9.0pt, fill: gray.darken(30%), str(hi)))
    x += ww
    hi -= w
  }
  content((total, 1.0), text(size: 9.0pt, fill: gray.darken(30%))[0])
}))

// A MachineInstr's operand array, and where the MCInstrDesc contract stops.
#let fig-operands = align(center, cetz.canvas(length: 1.60cm, {
  import cetz.draw: *
  let x = 0.0
  for (v, kind, col, w) in (
    ("%3","def",MIRC,1.5), ("%0","arg",IRC,1.5), ("%1","arg",IRC,1.5),
    ("$eflags","implicit-def",rgb("#ffe9c9"),2.7),
  ) {
    rect((x, 0), (x + w, 0.72), fill: col, stroke: 0.55pt)
    content((x + w/2, 0.36), m(v, size: 11.5pt))
    content((x + w/2, -0.3), text(size: 9.0pt, fill: gray.darken(30%), kind))
    x += w
  }
  line((0,1.05),(4.5,1.05), stroke: 0.6pt)
  line((0,0.88),(0,1.05), stroke: 0.6pt); line((4.5,0.88),(4.5,1.05), stroke: 0.6pt)
  content((2.25,1.36), text(size: 9.2pt)[explicit — count and types fixed by "MCInstrDesc"])
  line((4.5,1.05),(7.2,1.05), stroke: (paint: HOT, thickness: 0.6pt, dash: "dashed"))
  line((7.2,0.88),(7.2,1.05), stroke: 0.6pt + HOT)
  content((5.85,1.36), text(size: 9.6pt, fill: HOT)[implicit — appendable])
  content((8.6,0.36), m("SUB32rr", size: 10.2pt))
}))

// The three lowering stages as property bands.
#let fig-stages = align(center, cetz.canvas(length: 1.14cm, {
  import cetz.draw: *
  for (p, x) in (("aarch64-isel",0.0), ("phi-node-elimination",4.2), ("greedy / virtregrewriter",8.6)) {
    line((x,0),(x,2.55), stroke: (paint: HOT, thickness: 0.9pt, dash: "dashed"))
    content((x,2.85), m(p, size: 9.6pt, fill: HOT))
  }
  line((12.6,0),(12.6,2.55), stroke: (paint: HOT, thickness: 0.9pt, dash: "dashed"))
  content((12.6,2.85), m("asm-printer", size: 9.6pt, fill: HOT))
  let band(y, label, spans) = {
    content((-1.55, y + 0.22), m(label, size: 9.6pt))
    for (x0, x1, on) in spans {
      rect((x0,y),(x1,y + 0.44), fill: if on { rgb("#cfe8d6") } else { rgb("#f3d7d3") }, stroke: 0.4pt)
      content(((x0+x1)/2, y + 0.22), text(size: 9.0pt, if on { "true" } else { "false" }))
    }
  }
  band(1.7, "isSSA",   ((0,4.2,true),(4.2,8.6,false),(8.6,12.6,false)))
  band(1.0, "noPhis",  ((0,4.2,false),(4.2,8.6,true),(8.6,12.6,true)))
  band(0.3, "noVRegs", ((0,4.2,false),(4.2,8.6,false),(8.6,12.6,true)))
  content((2.1,-0.38), text(size: 9.6pt)[SSA + vreg])
  content((6.4,-0.38), text(size: 9.6pt)[vreg only])
  content((10.6,-0.38), text(size: 9.6pt)[physreg only])
}))

// MC as the hub every binary tool passes through.
#let fig-mchub = align(center, cetz.canvas(length: 1.12cm, {
  import cetz.draw: *
  let node(x, y, w, h, label, col, sz: 8.5pt, bold: false) = {
    rect((x,y),(x + w, y + h), fill: col, stroke: if bold { 0.9pt + INK } else { 0.55pt })
    content((x + w/2, y + h/2), text(size: sz, weight: if bold { "bold" } else { "regular" }, label))
  }
  node(4.3, 2.0, 2.6, 0.75, [Machine IR], MIRC)
  node(4.3, 0.0, 2.6, 0.8, [MC], MCC, sz: 10pt, bold: true)
  content((5.6, -0.42), m("MCInst", size: 9.0pt, fill: gray.darken(30%)))
  line((5.6, 2.0), (5.6, 0.82), mark: (end: ">", scale: 0.4), stroke: 0.6pt)
  node(0.0, 0.05, 2.0, 0.7, m(".s"), GREY)
  node(9.2, 0.05, 2.0, 0.7, m(".o"), GREY)
  // .s -> MC (parse), MC -> .s (print)
  line((2.0, 0.58), (4.3, 0.58), mark: (end: ">", scale: 0.4), stroke: 0.9pt + HOT)
  content((3.15, 0.82), text(size: 9.0pt, fill: HOT, weight: "bold")[parse])
  line((4.3, 0.22), (2.0, 0.22), mark: (end: ">", scale: 0.4), stroke: 0.6pt)
  content((3.15, -0.02), text(size: 9.0pt)[print])
  // MC -> .o (assemble), .o -> MC (disassemble)
  line((6.9, 0.58), (9.2, 0.58), mark: (end: ">", scale: 0.4), stroke: 0.6pt)
  content((8.05, 0.82), text(size: 9.0pt)[assemble])
  line((9.2, 0.22), (6.9, 0.22), mark: (end: ">", scale: 0.4), stroke: (paint: gray, thickness: 0.6pt, dash: "dashed"))
  content((8.05, -0.02), text(size: 9.0pt, fill: gray.darken(20%))[disassemble])
  content((13.2, 0.75), text(size: 9.6pt)[print + assemble:])
  content((13.2, 0.42), text(size: 9.6pt)[TableGen])
  content((13.2, 0.0), text(size: 9.6pt, fill: HOT, weight: "bold")[parse: you])
}))

// Marks a slide whose content is produced by a lab stage. The stage name has
// to go through raw() rather than a literal backtick span, because raw content
// is verbatim and would print "#name".
#let lab(name) = align(right)[
  #text(size: 13pt, fill: rgb("#0a6c3d"))[#raw("$ lab/run.sh " + name)]
]

#title-slide()
#outline(depth: 1)

= Session Bridge

#slide(title: "Where We Are")[
  So far, we stayed in the middle end: how to build LLVM, what IR *is*, how to write a pass, and what passes already exist.

  #v(0.3em)
  Session 4 ended on a cliff-hanger. Every interesting pass asked the *target* something:

  #code(```text
  LoopVectorize      -> TargetTransformInfo::getRegisterBitWidth
  SimplifyLibCalls   -> TargetLibraryInfo
  CodeGenPrepare     -> TargetLowering::isLegalAddressingMode
  ```)

  #v(0.2em)
  #fig-pipeline()

  #v(0.2em)
  #align(center)[#small[*Today*: we cross the red line.]]

]

#slide(title: "Textbook Map")[
  #tbl((auto, 1fr),
    [*Chapter*], [*What we take from it*],
    [9], [Connecting a target: intrinsics, `TargetTransformInfo`, injecting passes],
    [11], [Machine IR: the `.mir` format, operands, registers, SSA-ness],
    [12], [The MC layer --- assembly syntax and encodings #text(fill: gray)[(lightly)]],
    [13], [The machine pass pipeline: three stages, and where to inject],
  )
]

= Chapter 9: Connecting a Target

#slide(title: "A Backend Is Six Directories")[
  #v(0.2em)
  #fig-dirs

  #v(0.4em)
  #small[
  Each directory becomes *one library*. `llvm-config --components` lists them, so you can read a real backend's shape without a source checkout.
  ]

]

#slide(title: "Who Calls LLVMInitialize*?")[
  #v(0.2em)
  #fig-callchain

  #v(0.4em)
  #small[
  The chapter says the build system "automatically populates `InitializeAllTargets`". It is literally a macro over a generated list --- `Targets.def` is written at configure time, and `TargetSelect.h` expands it once to *declare* your three functions and once to *call* them.
  ]

  #v(0.2em)
  #small[
  That is why they must be `extern "C"`: these are generated call sites resolved by *symbol name*. C++ mangling breaks the link.
  ]

]

#slide(title: "Intrinsics: The Case Against")[
  The chapter's own example intrinsic --- a widening #box[16×16→32] multiply --- *does not need to be an intrinsic*:

  #code(```c
  int widening_smul(short a, short b) { return a * b; }
  ```)

  C promotes both operands to `int`. Plain C already said it. Therefore, this intrinsic is not useful. (But it is the best for intro)

]

#slide(title: "TTI")[
  #align(center)[#text(size: 19pt, style: "italic")[
    With no target, the vectorizer does *nothing at all*.
  ]]

  #v(0.4em)
  The default `TargetTransformInfo` reports no vector registers, so vectorising is never profitable.

  #v(0.3em)
  *A backend that has not implemented TTI is not "using sensible defaults".* It is telling every cost-driven pass in the middle end that everything is equally cheap.

]

= Chapter 11: Machine IR

#slide(title: "Why a Second IR")[
  #align(center)[#text(size: 19pt, style: "italic")[
    "the LLVM IR isn't flexible enough"
  ]]

  #v(0.4em)
  Specifically: *SSA*. Real architectures are not in SSA form, and SSA is so deep in LLVM IR's design that abandoning it would mean redesigning the Core library's API.

  #v(0.4em)
  Machine IR gives it up on purpose:

  #small[
  - supports SSA *and* non-SSA
  - very few structural rules --- a `MachineBasicBlock` may have *zero or several* terminators, where an LLVM IR block needs exactly one
  - extends through TableGen
  ]

  #v(0.3em)
  *The price*: an API that is hard to approach, because almost nothing is checked for you.

  #v(0.2em)
  #fig-pipeline(highlight: "Machine IR", len: 1.55cm)
]

#slide(title: "The .mir Format")[
  YAML. One LLVM IR section, then one section per `MachineFunction`.

  #code(```yaml
  --- |
    ; textual LLVM IR
  ...
  ---
  name:            funcName
  tracksRegLiveness: true
  body:             |
    bb.0 (%ir-block.entry):
      successors: %bb.1(0x80000000)
      liveins: $x0, $x1
      %0:gpr64 = COPY $x0
  ...
  ```, size: 12pt)

  #v(0.2em)
  #small[
  One instruction per line: `def0, def1 = opcode arg0, arg1 :: mem ops`, with
  `%` virtual, `$` physical, `@` symbol, bare number immediate.
  ]

]

#slide(title: "Shrinking Is The Skill")[
  #small[
  #tbl((1fr, auto),
    [*Step*], [*Lines*],
    [`llc -stop-before=peephole-opt`], [114],
    [`+ -simplify-mir` --- drops defaulted and recomputable fields], [75],
    [by hand --- no IR section, no `registers`/`frameInfo`/`liveins`/`successors`], [*27*],
  )
  ]

  #v(0.3em)
  Only *`name`* and *`tracksRegLiveness`* are mandatory.

  #v(0.3em)
  The test of whether you shrank it legally is that it still runs:

  #code(```console
  $ llc -mtriple=aarch64 -run-pass=peephole-opt shrunk.mir -o -
  --- |
    define void @def_in_loop_use_outside() {
    entry:
      unreachable        # <- the parser re-synthesised this
  ```)

]

#slide(title: "Four Traps When Shrinking")[
  #small[
  #tbl((auto, 1fr),
    [*Delete*], [*What actually happens*],
    [`successors:`], [edges survive (rebuilt from terminators), *probabilities do not* --- they become uniform. Fatal only for profile-driven passes. Best compromise: keep it *without* the `(0x...)` weights],
    [`liveins:`], [it appears at *two* nesting levels. Top-level: near-useless. Inside `body:`: real dataflow --- delete it and incoming arguments look dead],
    [the IR section], [the *triple* went with it. `-mtriple` must come back... and on a matching host, omitting it silently works],
    [...with a call in it], [`error: use of undefined global value '@sink'`. The book's one-line fix needs *two*],
  )
  ]

  #v(0.2em)
  #note[Plus the one that is not about shrinking: `.mir` does not serialise *analysis state*. Chaining `-run-pass=opt1` then `-start-after=opt1` recomputes everything in between, so a stale-analysis bug vanishes.]
]

#slide(title: "MachineInstr: One Class, All Targets")[
  No subclass hierarchy. *Every* instruction on *every* target is a `MachineInstr`. Identity comes from the opcode.

  #v(0.3em)
  #fig-operands

  #v(0.5em)
  #small[
  One `MCInstrDesc` per opcode, immutable: the properties (`mayLoad`, `isCommutable`), the *statically expected* operand count, their types and constraints. Violate it and `MachineVerifier` rejects the instruction.
  ]

  #v(0.3em)
  Consequence: *"is this an `add`?" is not a target-independent question.* To ask it generically you must expose a property and implement the hook --- the model is `isRegSequenceLike` + `TargetInstrInfo::getRegSequenceInputs`.

  // #note[The properties exist for the target-*independent* code generator. Your own backend knows its opcodes and does not need them.]
]

#slide(title: "Implicit Operands, Flavour 1: Hardware")[
  `@sel` in C is a compare and a select. On x86:

  #code(```text
  %3:gr32 = SUB32rr  %0, %1,      implicit-def $eflags
  %4:gr32 = CMOV32rr %1, %0, 15,  implicit     $eflags
  %5:gr32 = ADD32rr  %4, %2,      implicit-def dead $eflags
  ```, size: 12pt)

  #v(0.3em)
  #small[
  The compare *writes* the flags; the conditional move *reads* them. Neither is expressible in the C source --- the hardware gives you no choice about the destination. `dead` on the third says nobody reads that write.
  ]

  #v(0.3em)
  `MCInstrDesc` guarantees the order, which is why indexing works at all:

  #small[
  1. explicit *definitions* (registers only) --- printed left of the `=`
  2. explicit *arguments*, in description order
  3. *implicit* operands, defs and uses mixed, *unordered*
  ]

]

#slide(title: "Implicit Operands, Flavour 2: The ABI")[
  #code(```text
  CALL64pcrel32 @bar, csr_64, implicit $rsp, implicit $edi,
                implicit-def $rsp, implicit-def $eax
  ```, size: 12pt)

  #v(0.3em)
  *Two* explicit operands. This instruction defines nothing explicitly.

  #small[
  #tbl((auto, 1fr),
    [`@bar`], [the symbol --- the only thing the instruction really takes],
    [`csr_64`], [a *register mask*: every register in it is *preserved* across the call. The callee-saved set, compactly. Absence from the mask means clobbered],
    [`implicit $edi`], [the argument. Implicit because the *compiler* imposes it, not the hardware],
    [`implicit-def $eax`], [the return value],
  )
  ]

  #v(0.3em)
  #small[The final assembly is `call bar`. None of the rest appears.]

  #note[This is why implicit operands are not all statically known: `MCInstrDesc` fixes the explicit ones, but you may *append* implicit operands. Beware --- a `COPY` is expected to have exactly two operands, and adding more makes the copy optimiser give up.]
]

#slide(title: "Tied Operands Break SSA — On Purpose")[
  x86 arithmetic is two-address, and the `twoaddressinstruction` pass is what introduces the constraint:

  #ba(
    "%4:gr32 = CMOV32rr %1, %0, 15
              (three distinct regs)",
    "%4:gr32 = COPY killed %1
%4:gr32 = CMOV32rr %4, killed %0, 15",
    lcap: "after isel", rcap: "after two-address",
  )

  #v(0.2em)
  #small[
  `%4` is operand 0 (a *def*) and operand 1 (a *use*) --- the model for `a = cond ? a : b`. It tells the register allocator both must get the same physical register.
  ]

  #v(0.3em)
  And look at the cost: *`%4` now has two definitions.*

  #v(0.2em)
  #align(center)[Tied operands are *incompatible with SSA*.]

  #v(0.2em)
  #small[Which is exactly why this pass runs where it does --- after PHI elimination.]
]

#slide(title: "Early Clobber Is One Character")[
  #code(```text
  "=&r"  ->  regdef-ec:GPR64common, def early-clobber %2
  "=r"   ->  regdef:GPR64common,    def %2
  ```, size: 12pt)

  #v(0.4em)
  `early-clobber` says the definition is produced *before* the arguments are read --- so it must not share a register with them.

  #v(0.4em)
  Necessary whenever one "instruction" is really several:

  #code(```c
  asm("mov $0, $1\n add $0, $0, $2", "=&r,r,r"(b, c));
  ```)

  #small[
  To the register allocator this whole block is *one* instruction. Without `&`, `$0` could be assigned `$1`'s register --- and the `add` would read a value the `mov` already destroyed.
  ]

  #note[The default expectation is the opposite: definitions are produced *after* all arguments are read. Early clobber is how you say otherwise.]
]

#slide(title: "Registers: Four Concepts")[
  #small[
  #tbl((auto, 1fr),
    [*Register class*], [a set sharing a property (32-bit, FP-capable). A register belongs to zero or more],
    [*Sub-registers*], [*real* hierarchy. x86 `ax` contains `al`, `ah`; writing one writes the parent. Register *aliasing*. Exposed as `%1.sub_32`],
    [*Register tuples*], [*logical* super-registers. Hardware has only 32-bit regs, but you want pairs `(r0,r1)`, `(r1,r2)` #sym.arrow model `r0_r1`. The API does not distinguish logical from real],
    [*Register units*], [the abstraction that keeps the above affordable],
  )
  ]

  #v(0.3em)
  #small[
  Naming convention worth internalising: *`Machine*` is per-function and dynamic; `Target*` is per-subtarget and static.* `MachineRegisterInfo` is about the function being compiled; `TargetRegisterInfo` about the architecture.
  ]
]

#slide(title: "Register Units, Measured")[
  Figure 11.2 --- nine registers, three *irregular* layers. Empty cells are not addressable:

  #v(0.3em)
  #fig-regunits

  #v(0.5em)
  #small[
  The bottom row is what `llvm-tblgen -gen-register-info` computes. *Five units cover nine registers.* "Is `q0` free?" becomes 3 unit checks instead of walking `d0, d1, s0, s1, s2`.
  ]

  #lab("registers")
]

#slide(title: "...And A Number The Book Does Not Mention")[
  We declared *three* register classes. TableGen emitted *seven*:

  #code(```text
  SINGLES  DOUBLES  DOUBLES_with_sub32_low  DOUBLES_with_sub32_high
  QUADS    QUADS_with_sub64_low    QUADS_with_sub32_high
  ```, size: 12pt)

  Because the hierarchy is *irregular* --- `d2` has no singles beneath it --- "a double" and "a double whose low half is addressable" are genuinely different operand constraints.

  #v(0.3em)
  #align(center)[#small[Nobody asked for these. The *shape of the register file* demanded them.]]

  #v(0.4em)
  Exercise 2 measures three follow-ups:

  #small[
  #tbl((auto, auto, auto, auto),
    [*Edit*], [*regs*], [*classes*], [*units*],
    [baseline], [10], [7], [5],
    [drop `CoveredBySubRegs`], [10], [7], [5],
    [regularise (add `s3`)], [11], [*6*], [6],
    [add a *tuple*], [11], [8], [*5*],
  )
  ]

  #v(0.2em)
  #small[The last row is the entire argument for register units: a new register, a new class, *zero* new units.]
]

#slide(title: "SSA at the Machine Level — Quiz 1")[
  The rule, exactly: *the Machine IR is in SSA form so long as every virtual register is defined at most once.*

  #v(0.3em)
  Assume `dsub_x` are *non-overlapping* quarters. Is this SSA?

  #code(```text
  undef %4.dsub_0:dquad = COPY %0
        %4.dsub_1:dquad = COPY %1
        %4.dsub_2:dquad = COPY %2
        %4.dsub_3:dquad = COPY %3
  ```, size: 12pt)

  #v(0.3em)
  *No.* The unit of the rule is the *virtual register*, not the lane. `%4` is on the left of `=` four times.

  #v(0.2em)
  #small["But they write different bits" is a *liveness* argument. Different question.]

  #v(0.3em)
  #small[The SSA form is `REG_SEQUENCE`, which builds the whole register in *one* definition --- and carries no encoding, so it must die before MC.]
]

#slide(title: "Two Conventions To Respect")[
  While in SSA form, the code generator maintains:

  #v(0.3em)
  *1. PHI instructions exist only in SSA form.*

  #v(0.3em)
  *2. Physical registers have the shortest live range possible.*

  #ba(
    "$r0 = opc1 ...
...
... = opcN $r0",
    "%v0 = opc1 ...
...
$r0 = COPY %v0
... = opcN $r0",
    lcap: "Don't", rcap: "Do",
  )

  #v(0.2em)
  #small[
  On the left, `$r0` is live across the whole region: the allocator cannot use it for anything else, and `opc1` is pinned to a physical register so optimisations give up on it. On the right, both problems are one `COPY` wide.
  ]

  #note[Generic passes *assume* both. Break them and the failures look like the optimiser being mysteriously bad.]
]

= Chapter 12: The MC Layer

#slide(title: "Why Now, Not Later")[
  MC is the *last* stage of the backend --- `MCInst` on the way to assembly or an object file. The book visits it early for one reason:

  #v(0.3em)
  #align(center)[#text(size: 18pt, style: "italic")[
    ISAs group instructions into *encoding families*,\ and your TableGen classes should mirror that grouping.
  ]]

  #v(0.3em)
  Discover it late and you rewrite every instruction record.

  #v(0.4em)
  Chapter 11 gave records their operand lists. Chapter 12 adds two fields:

  #small[
  #tbl((auto, 1fr),
    [`AsmString`], [the syntax, binding `$name` operands. A `printf` format whose slots are filled by each operand type's `PrintMethod`],
    [`Inst`], [the encoding, as `bits<N>` assigned range by range. *Not declared in the `Instruction` class* --- the generator just looks for it],
  )
  ]
]

#slide(title: "40 Lines of .td, and the Encoder Is Written")[
  #fig-bits

  #v(0.3em)
  #ba(
    "class ALU<bits<4> opc, string m>
    : Instruction<> {
  bits<16> Inst;
  bits<2> dst;
  let Inst{15-12} = opc;
  let Inst{11-10} = dst;
  let Inst{9-8}   = src0;
  let Inst{7-6}   = src1;
  let AsmString = m # \" $dst, ...\";
}
def ADD : ALU<0b0001, \"add\">;",
    "static const uint64_t InstBits[] = {
  UINT64_C(4096),  // ADD
  UINT64_C(8192),  // SUB
};
case Tiny::ADD:
  // op: dst
  Value |= (op & 0x3) << 10;
  // op: src0
  Value |= (op & 0x3) << 8;
  // op: src1
  Value |= (op & 0x3) << 6;",
    lcap: "tiny.td", rcap: "gen-emitter output",
  )

  #v(0.2em)
  #align(center)[No C++ was written. *The declarative bit positions are the encoder.*]

  #v(0.2em)
  #small[`4096` = `0b0001 << 12`. The opcode arrives pre-shifted.]

  #lab("encoding")
]

#slide(title: "The Same Round Trip, On A Real ISA")[
  #code(```console
  $ llvm-mc -triple=aarch64 --show-encoding --show-inst add.s
    add w0, w1, w2    // encoding: [0x20,0x00,0x02,0x0b]
                      // <MCInst #1729 ADDWrs
                      //  <MCOperand Reg:W0> <MCOperand Reg:W1>
                      //  <MCOperand Reg:W2> <MCOperand Imm:0>>
  ```, size: 11.5pt)

  #v(0.2em)
  *Four* operands where the assembly wrote three. `ADDWrs` is the shifted-register form; the shift amount is a real operand holding 0. The mnemonic hides it; `MCInstrDesc` does not.

  #v(0.2em)
  #code(```text
  0x0b020020 = 0b00001011000000100000000000100000
    sf  [31]     = 0   32-bit operands -> the W registers
    Rm  [20:16]  = 2   -> w2
    Rn  [ 9: 5]  = 1   -> w1
    Rd  [ 4: 0]  = 0   -> w0
  ```, size: 11pt)

  #small[AArch64's own `.td` wrote those ranges the same way `tiny.td` does.]
]

#slide(title: "Three Components, Unequally Generated")[
  #fig-mchub

  #v(0.4em)
  #small[
  Every binary tool is a path through MC. An assembler is *parse* then *assemble*; a disassembler is the reverse. `MCInstPrinter` and `MCCodeEmitter` come from TableGen --- `MCTargetAsmParser` is mostly yours.
  ]

  #v(0.3em)
  The asymmetry is visible in the diagnostics: hand-written, and they know the register classes.

  #code(```console
  $ llvm-mc -triple=aarch64 bad.s        # add w0, w1, x2
  bad.s:1:13: error: expected compatible register, symbol
              or integer in range [0, 4095]
  ```, size: 11.5pt)

  #v(0.3em)
  #small[
  *Bit order is the trap* (quiz 2): write ranges high-to-low, `Inst{3-0}`, as ISA documents draw them. `Inst{0-3}` is legal TableGen and *reversed*.
  ]

  #note[Not every instruction needs an encoding --- only those reaching MC. `PHI` and `COPY` carry `isPseudo` and have none. That is quiz 3.]
]

= Chapter 13: The Machine Pass Pipeline

#slide(title: "Three Stages")[
  #fig-stages

  #v(0.5em)
  #code(```text
  %1:gpr64sp = PHI %6, %bb.0, %2, %bb.1              (1)
  %8:gpr64common = ADDXri %1, 1, 0

  %1:gpr64sp  = COPY killed %12                      (2)
  %12:gpr64sp = COPY killed %2     <- %12 also def'd in bb.0

  renamable $x8 = ADDXri killed renamable $x8, 1, 0  (3)
  ```, size: 11pt)

  #v(0.2em)
  #small[
  *How SSA ends*: PHI elimination puts a `COPY` in each predecessor. One copy per predecessor #sym.arrow the destination gets *two* definitions. Same dataflow, no longer SSA.
  ]

  #lab("pipeline")
]

#slide(title: "Where To Inject")[
  `TargetPassConfig::addMachinePasses` builds the default pipeline.

  #v(0.3em)
  #align(center)[*Do not override it.*]

  #v(0.3em)
  Its hooks --- `addPreISel`, `addPreRegAlloc`, `addPreEmitPass`, ... --- *are* the injection mechanism. Override the parent and you lose all of them, plus every generic optimisation it installs.

  #v(0.4em)
  #small[
  One correction chapter 13 makes to chapter 9: to inject *LLVM IR* passes, prefer `addPreISel` over `addIRPasses`. Overriding `addIRPasses` drops the default IR passes --- chapter 9's example only works because it calls the parent first.
  ]

  #v(0.3em)
  #code(```console
  $ llc -mtriple=aarch64 -O1 -debug-pass=Structure loop.ll
  aarch64-isel  finalize-isel  phi-node-elimination
  twoaddressinstruction  register-coalescer  machine-scheduler
  virtregmap  greedy  virtregrewriter  prologepilog
  postrapseudos  aarch64-asm-printer
  ```, size: 11pt)

  #small[*30 distinct `aarch64-*` passes* appear in that listing. The default pipeline is a backbone; the target fills it in.]
]

#slide(title: "Reusing a Generic Pass: The Recipe")[
  Chapter 13 does not survey the Machine passes --- most are the Machine-level twin of an LLVM IR pass you know (`MachineLICM` #sym.arrow `LICMPass`). It teaches a *procedure* instead:

  #v(0.3em)
  #small[
  1. *Find it.* `llvm/include/llvm/CodeGen/Passes.h` lists every `createXXXPass` and `XXXPassID`. (Dead code elimination = `DeadMachineInstructionElimID`.)
  2. *Place it.* Pick the `addXXX` hook, call `addPass` with the ID.
  3. *Does nothing?* Reduce a `.mir`, iterate with `-run-pass`, read the debug log.
  4. *Log not enough?* Read the pass. Look for `TRI` / `TII` / `TLI` uses, and for `MachineInstr::isXXX` calls (grep `->is` and `.is` near a variable named `MI`).
  ]

  #v(0.3em)
  #align(center)[
    Step 4 is the transferable skill:\
    #small[a generic Machine pass is a *template with target-shaped holes*,\ and reading it tells you which holes are load-bearing.]
  ]
]
