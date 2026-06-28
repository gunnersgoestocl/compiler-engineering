#import "@preview/touying:0.6.1": *
#import themes.metropolis: *
#import "@preview/numbly:0.1.0": numbly
#import "@preview/fletcher:0.5.8" as fletcher: diagram, node, edge
#import "@preview/octique:0.1.1": *

#show: metropolis-theme.with(
  aspect-ratio: "16-9",
  align: horizon,
  config-common(handout: true),
  config-page(margin: (x: 1.5em, y: 2em)),
  config-colors(
    primary: rgb("#001fcc"),      // 強調色をブルーに変更
    secondary: rgb("#012d20"),    // セカンダリカラー
  ),
  config-info(
    title: [Introduction to LLVM with Compiler basics],
    subtitle: [Compiler Engineering \#1],
    author: [Yuri Takigawa],
    date: [2026/06/28],
    institution: [M1, Taura Laboratory, Creative Information, Graduate School of Information Science Technology, The University of Tokyo],
  ),
)

#show strong: set text(weight: "bold")
#set text(lang: "en")
#set text(size: 21pt)

#let ao(x) = text(blue, x)
#let small(x) = text(size: 14pt, x)
#let blink(x, y) = text(blue, link(x, y))

#let boxed(title, content) = block(
  fill: gray.lighten(95%),
  stroke: 1pt + gray.darken(20%),
  radius: 4pt,
  inset: 0pt,
  breakable: false,
)[
  #block(
    fill: gray.darken(20%),
    inset: 8pt,
    width: 100%,
  )[
    #text(fill: white, weight: "bold")[#title]
  ]
  #block(inset: 10pt, spacing: 0.5pt)[
    #text(size: 18pt)[#content]
  ]
]

#show cite: small
#set quote(block: true)

// configuration of code block
#show raw.where(block: true): it => {
  set text(size: 13pt)
  box(
    fill: rgb("#f5f5f5"),
    inset: (left: 0.2em, right: 0.2em, top: 0.2em, bottom: 0.2em),
    radius: 4pt,
    it
  )
}

// configuration of inline code
#show raw.where(block: false): it => text(rgb("#e65555"), size: 16pt, it)
#set heading(numbering: numbly("{1}.", default: "1.1"))

#show figure.caption: it => text(size: 14pt, it)

#set heading(numbering: (..nums) => {
  let level = nums.pos().len()
  if level <= 3 {
    numbly("{1}.", default: "1.1")(..nums)
  }
})

#let bent-edge(from, to, ..args) = {
  let midpoint = (from, 50%, to)
  let vertices = (
    from,
    (from, "|-", midpoint),
    (midpoint, "-|", to),
    to,
  )
  edge(..vertices, "-|>", ..args)
}

#set math.equation(numbering: "(1)")

#import "@preview/algorithmic:1.0.7"
#import algorithmic: style-algorithm, algorithm-figure
#show: style-algorithm

#title-slide()
#outline(depth: 1)

= LLVM setup

#slide(title: [Installation])[
1. Glance at #blink("https://releases.llvm.org/")[https://releases.llvm.org/]
2. Execute followings replacing `INSTALL_PREFIX` with the path where you want the tools to be installed.
```bash
$ git clone https://github.com/PacktPublishing/LLVM-Code-Generation.git
$ cd LLVM-Code-Generation/ch1
$ bash setup_env.sh ${INSTALL_PREFIX}
```
]

= Compiler recap
#slide(title: [Compiler Components])[
When building a C file, Clang acts as a _driver for a series of tools_.
#v(-0.5em)
#grid(
  columns: (2fr, 1fr),
  gutter: 1em,
  [
- invokes the frontend (Clang project in LLVM)
- passes down the result to the backend (LLVM backend)
  - that produces an object file
- those object file gets linked with the standard library (the `libc` project in LLVM) by the linker (the `lld` project in LLVM)

To build a properly functioning compiler, you will need to build at least *linker* and *standard library*.
 ],[
#figure(
  image("figures/compiler_components.png", width: 95%),
  caption: [The different components of a compiler ©Figure1.2 of the book]
)<compiler_components>  
  ]
)
]

#slide(title: [Building Clang to grasp the compiler tool chain])[
Building Clang (projects) always includes backend.

Assuming 
- `LLVM_SRC` is the path where you want to have the LLVM source code
- `CLANG_BUILD` is the path where you want the build of Clang to happen
please run the following:
```bash
$ git clone https://github.com/llvm/llvm/project.git ${LLVM_SRC}
$ mkdir -p ${CLANG_BUILD}
$ cd ${CLANG_BUILD}
$ cmake -DLLVM_ENABLE_PROJECTS=clang -GNinja -DCMAKE_BUILD_TYPE=Release ${LLVM_SRC}/llvm
$ ninja clang
``` 
]

#slide(title: [Experimenting with Clang: Frontend])[
*Frontend* validates that the input file is syntactically and semantically correct and produces the LLVM IR.
- *Preprocessor* expands macros (e.g., `#include`)
- *Sema* validates the syntax and semantics of the program.
- *Codegen* produces the LLVM IR.

#table(
  // columns: (auto, 1fr, 2fr),   // 列幅
  columns: 2,
  stroke: 0.5pt,                // 罫線の太さ
  fill: (col, row) => if row == 0 { gray.lighten(50%) } else { white }, // 行の背景色

  [*To stop*], [*Command*],
  [After the preprocessor],    [`clang -E`],
  [After syntax checking],    [`clang -fsyntax-only`],
  [After LLVM IR code generation],    [`clang -O0 -emit-llvm -S`],
)
]

#slide(title: [Experimenting with Clang: Backend & Assembler])[
*Backend* translates the LLVM IR to target specific instructions.
- *Middle-end optimization*: LLVM IR to LLVM IR optimizations.
- *Assembly generation*: Target-specific IR to assembly code.
*Assembler* translates assembly code to an object file.

#table(
  // columns: (auto, 1fr, 2fr),   // 列幅
  columns: 2,
  // align: (left, center, right), // 各列の揃え
  stroke: 0.5pt,                // 罫線の太さ
  fill: (col, row) => if row == 0 { gray.lighten(50%) } else { white }, // 行の背景色

  [*To stop*], [*Command*],
  [After the middle-end optimizaiton],    [`clang -O<1|2|3|s|z> -emit-llvm -S`],
  [After assembly generation],    [`clang -S`],
  [After the assembler],    [`clang -c`],
)
]

#slide(title: [Understanding compiler jargon#footnote[specialized/industory terminologies]])[
- *Target* is the hardware architecture that a program will run on. "_Targetting_ of instruction selection" means that we will modify the instruction selection transformation so that it supports a _spefici target_.
- *Host* is the device that runs the compiler. In _cross-compilation_, you can run a compiler that produces code for an AArch64 (used in iPhone) on an x86 host (windows laptop).
- *Lowering* is the notion that as your input program is being compiled, it goes through various stages that progressively lower its level of abstraction all the way down to the final assembly of the target machine.
- *Canonical form* is about the recommended way of representing something, which is ultimately useful to make an agreement across different stages of compilation. Let's learn by example of expressions `a = b + 2` and `a = 2 + b`:
  - computes the same results but offer different ways to represent their computations.
  - For instance, a rule could be to put the constants on the right-hand side of binops.
  - LLVM offers APIs to canonicalize your IR.
]

#slide(title: [Understanding compiler jargon])[
==== Time
- *Build time*: The time it takes to build the compiler; for example, the time it takes for Ninja to complete the build of LLVM.
- *Comile time*:The time it takes for the compiler to process a file; for example the time it takes for Clang to produce an object file from the source file.
- *Runtime*: The time it takes for the final binary to execute; for example, the time it takes to run the binary produced by Clang.
]

#slide(title: [Understanding compiler jargon])[
==== Application binary interface (ABI)
*ABI* formalize how the handshake happens between the caller function and the callee function at a low level. 

- Specifically, ABI defines how and where the _arguments_ of a fuction are set on the caller side so that they can be retrieved on the callee side.
- the ABI can harm the whole compiler stack because it affects the function signature, which is typically determined by the frontend, all the way down to the backend, which must set the right stack alignment, reserve dedicated registers, and so on.
- As long as compilers follow the rules of the ABI, a function compiled with a compiler can talk to a function compiled with a different compiler.

If you are writing your own backend, you must define your own ABI, but should use an existing one and derive yours from that.
]

// #slide(title: [Module])[
// ==== A module at the LLVM IR level

// ==== A module at the Machine IR level

// ]

// #slide(title: [Function])[
// ==== A function at the LLVM IR

// ==== A function at the Machine IR

// ]

// #slide(title: [Basic block])[
// ==== A basic block at the LLVM IR

// ==== A basic block at the Machine IR

// ]

// #slide(title: [Instruction])[
// ==== A instruction in the LLVM IR

// ==== A instruction in the Machine IR

// ]

#slide(title: [CFG & RPO])[

]

#slide(title: [Backedge and Critical edge of CFG])[

]

= Building LLVM

#slide(title: [Configuring the build system])[
Official build system is CMake.
==== CMake variables
CMake comes with some built-in variables that can be used to customize some key aspects of the build process, which are recognized with their name starting with `CMAKE_`.
==== CMake command-line options
CMake also supports command-line options, but for all intent and purposes, we will mention only three here
- `-D<var>=<value>`: This defines the value of a CMake variable.
- `-G<generatorName>`: This generates a build system for the specified generator.
- `-C<pathToCacheFile>`: This preloads a cache file that pre-set some CMake variables#footnote[cache files are useful for sharing specific configurations and avoiding setting all the variables manually.]

Simplest commands you can run from your build directory to configure the LLVM's build system:
```bash
$ cmake -GNinja –DCMAKE_BUILD_TYPE=Debug ${LLVM_SRC}/llvm
```
]

#slide(title: [Commonly used CMake variables])[
// #table(
//   // columns: (auto, 1fr, 2fr),   // 列幅
//   columns: 3,
//   // align: (left, center, right), // 各列の揃え
//   stroke: 0.5pt,                // 罫線の太さ
//   fill: (col, row) => if row == 0 { gray.lighten(50%) } else { white }, // 行の背景色

//   [*Variable*], [*Value*], [*Meaning*],

//   table.cell(colspan:3, fill: gray.lighten(80%))[*Standard options*],
//   table.cell(rowspan:2)[`CMAKE_BUILD_TYPE`], [`Debug`], [Build for a smooth debug experience, *Assertions* and *Debug info* enabled, *Optimization* disabled], [`Release`], [The opposite, produces a smaller and faster compiler],
//   [], [`clang -S`], [],
//   table.cell(colspan:3, fill: gray.lighten(80%))[*Faster build time*],
//   [`LLVM_TARGETS_TO_BUILD`], [], [],
//   table.cell(colspan:3, fill: gray.lighten(80%))[*Notably *],
//   [After the assembler], [`clang -c`], [],
// )
#v(-0.5em)
#align(center)[
#v(-0.5em)
#figure(
  image("figures/cmake_variables.png"),
  // caption: [The different components of a compiler ©Figure1.2 of the book]
)<cmake_variables>  
]
#v(-0.5em)
Here is recommended one for a faster build time that still features a debuggable compiler:
#v(-0.5em)
```bash
$ cmake -GNinja -DCMAKE_BUILD_TYPE=Debug -DLLVM_TARGETS_TO_BUILD="X86;AArch64" -DLLVM_OPTIMIZED_TABLEGEN=1 ${LLVM_SRC}/llvm
```
]

#slide(title: [Ninja])[
*Ninja* is a tool that drives a build system, especially making sure that artifacts are built following the order of the dependencies described in this build system.
]

#slide(title: [Building the core LLVM project and try a series of things])[
To build LLVM, RUN
```bash
$ ninja
```
Then, follow the instructions for *testing a compiler*
]

#slide(title: [Understanding the directory structure])[
From the highest level of repository,
- LLVM code base is organized into projects: Clang, MLIR, the *LLVM debugger (LLDB)*, etc.
- You need to use these directory names (like `clang`, `mlir`, `lldb` and so on) in the `LLVM_ENABLE_PROJECTS` CMake variable to build the related projects.

The core of LLVM `llvm` is primarily composed of several interesting pieces
- `include`: public headers
- `lib`: different libraries
- `tools`: developer-facing tools
- `unittests` and `test`: tests for all the tools and libraries
- `utils`: various utility tools such as `FileCheck` and `llvm-lit`
]

#slide(title: [When you implement something, follow the unwritten "rule"])[
List the content of the `llvm/lib/` directory, then see `llvm/include/llvm/` and 
]

#slide(title: [Overview of the LLVM components])[
==== Generic LLVM goodness
LLVM provides a lot of well-optimized data structures and utilities that can be reused as is.
- In `ADT` directory, you can find _containers_ like link lists, maps etc., as well as portable implementations for _arbitrary-sized integer types_.
- In `Support`, wrappers for string and file system manipulations, error handling etc.

==== Working with the LLVM IR
LLVM IR is the main _exchange format_ for everything built around LLVM. It lives in the IR directories (both `include/llvm/IR`, and `lib/IR`).
- Optimizaitons transforming/analyzing the IR live in `Analysis` and `Transforms`.
- The binary and textual representation of the IR is handled in `Bitcode`, `IRReader`, and `IRWriter`.

==== Generic backend infrastructure

]

// #slide(title: [Next step])[
// ==== Note
// - 

// ==== TODO
// - 
// ]

// #slide(title: [])[
// #v(-0.5em)
// #grid(
//   columns: (2fr, 1fr),
//   gutter: 1em,
//   [
// #figure(
//    image("../figures/floorplan/core-placement-interleave-linear-and-full.png", width: 95%),
//    caption: [interleave linear and full, DWD]
//  )<interleave-linear-and-full>
//  ],[
  
//   ]
// )
// ]

// #slide(title: [Open Questions])[
// 1. Question A
// 2. Question B
// ]
