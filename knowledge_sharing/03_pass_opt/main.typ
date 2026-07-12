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
    subtitle: [Compiler Engineering \#3],
    author: [Yuri Takigawa],
    date: [2026/07/11],
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

= Session Bridge

#slide(title: [Where We Are])[
By using a general *IR*, your compiler can use the same optimizations and infra for a large variety of languages, targets, and OSs; _*Reusability*_.

*Previous session*: 
- Structure of IR Object (Module, Function, Basic Block, Instruction)
- Key concept about _CFG_ (backedge, critical edge, irreducible CFG)
- LLVM IR syntax (type, `getelementptr` instr, target triple & data layout)
- format for optimization; _SSA_ (phi instruction for explicit CFG handling, dominance and def-use relationship)

*Today*: 
]

#slide(title: [Optimization overview])[
A lot of work of a backend compiler engineer is about improving the performance of generated code; write _optimizations_.

The ultimate goal of the optimization is 
#align(center)[
  _to balance the *legality* and the *profitability*_
] 
]

#slide(title: [Legality])[
*Legality* is a concept about whether the optimization preserve the semantics of the program.
- No Unsigned Wrap (NUW) / No Signed Wrap (NSW) for the behavior hint on integer overflow/underflow. 
- Fast-math flags (FMF) hints on specific instructions.

More generally, optimizations must consider their _side effects_.

_Example_: In the following sequence, is it legal to replace `val3` directly with `val1`?
#grid(
  columns: (1fr, 4fr),
  gutter: 1em,
  [

```cpp
val1 = A[0];
B[1] = val2;
val3 = A[0];
```
  ],[
- The answer depends on which memory location `B[1]` points to.
- If `B[1]` and `A[0]` alias, this is not legal.
  ]
)
]

#slide(title: [Profitability])[
No silver bullet to decide whether something is profitable, it depends on what you are trying to achieve. It is important to understand both _pros_ and _cons_ of the optimization.

For the example of *inlining optimization*, replacing calls to functions with the content of their body
- removes the overhead of executing the call, and exposes more optimization opportunities by breaking the boundaries of the call, and so on.; *pros*
- may increase the code size of your final executable and thrash your instruction cache, or end up oversubscribing thte physical registers, and so on.; *cons*

See _Table 4.2_ for the example.
]

= Pass

#slide(title: [What is a pass?])[
#v(-0.3em)
A *pass* is a class that does the followings for the specifiable _scope_.
- Encapsulates a *transformation* (e.g., an analysis, an optimization).
- Describes the dependencies of this transformation.
  - E.g., transformation A needs to have access to the dominator tree analysis B
- Returns the _effect_ of this transformation on the IR (e.g., modify the CFG)

The available scopes are
- *Module*: The full IR of the current module.
- *CGSCC*: Call-graph strongly connected component is a strongly connected subset of the functions#footnote[強連結成分 of a directed graph, where the nodes are the functions, and the edges are the possible function calls from the caller and the callee. "Strongly connected" means that each function within this subset can reach all the other ones in this subset by traversing the call graph.] within a module.
- *Function*: The IR representing a single function
- *Loop*: The IR representing a single loop
]

#slide(title: [What is a pass manager?])[
A *pass manager* is a driver for the set of passes that you want to run.

It fulfills three major functionalities:
- It provides a structure to run passes in a specific order.
- It makes sure that the dependencies of a pass are properly executed before the pass itself.
- It decides whether it preserves or invalidates the various analyses base on the passes' _effects_.
#align(center)[
#figure(
  image("figures/passes.png", width: 60%),
  caption: [Structure of passes, pass manager (PM), IR]
)<llvm_ir_api_cheat>
]
]

#slide(title: [The guarantees on the order in which the IR is visited])[
When a pass manager invokes a pass, it also provides specific guarantees on the order in which the IR is visited.

The policy is simple: a children-to-parents traversal.
- For loop-scoped passes, loops are visited from innermost one to outermost ones.
- For CGSCC-scoped passes, a pass manager invokes the pass on the leaf _SCC_ regions first then moves up in the call graph.
]

#slide(title: [Inner workings of pass managers])[
This will help you 
- understand why certain analysis passes need to be (re)run
- fix compile-time issues by making and informed decision on whether you should preserve some analysis or adjust your pass pipeline.

1. Before running a pass, they check if the analyses that this pass relies on are available:

  a. If yes, nothing needs to be done.

  b. If no, they run these analyses beforehand.

2. They run the pass.
3. If the pass modified the IR, they check what kind of informantion the pass affects and not preserved.
]

#slide(title: [The legacy and new pass manager])[
The LLVM infrastructure is in the middle of a transition from the previous pass manager to the new one.
]

= Implementation of a pass

#slide(title: [Overview])[
The implementation template differs between *legacy pass manager* and new *pass manager*, but they have common information that you must provide
- What is the scope of a pass?
- What analyses does this pass depend on?
- What effect does this pass have on the input IR?
]

#slide(title: [Legacy pass manager: Using the proper base class])[
#v(-1em)
Creating a pass for a specific scope implies *_inheriting form the related scoped pass class nad implementing the `runOnXXX`#footnote[The Boolean returned by `runOnXXX` method tells the pass manager whether the related pass made any changes to the IR fed to this method.] method_*.
#v(-0.5em)
#table(
  // columns: (auto, 1fr, 2fr),   // 列幅
  columns: 3,
  stroke: 0.5pt,                // 罫線の太さ
  fill: (col, row) => if row == 0 { gray.lighten(50%) } else { white }, // 行の背景色

  [*Scope*], [*Inherit from*], [*Method to override*],
  [Module],    [`ModulePass`], [`runOnModule(Module&)`],
  [CGSCC],    [`CallGraphSCCPass`], [`runOnSCC(CallGraphSCC&)`],
  [Function],    [`FunctionPass`], [`runOnFunction(Function&)`],
  [Loop], [`LoopPass`], [`runOnLoop`],
  [Region], [`RegionPass`], [`runOnRegion(Region*, GPassManager&)`],
  [`MachineFunction`], [`MachineFunctionPass`], [`runOnMachineFunction(MachineFunction&`]
)
#v(-0.5em)
#grid(
  columns: (2fr, 3fr),
  gutter: 0.2em,
  [
The skeleton of your pass looks like:
  ],[
```cpp
class MyPass * public XXXPass {
public:
  bool runOnXXX(/*Proper IR arguments*/) override;
};
```
#v(-0.5em)
  ]
)
]

#slide(title: [Legacy pass manager: overview])[
#v(-0.5em)
Users define a top-level pipeline using Pass Manager as shown below. In the `PM.run()`, 
1. PM calls `getAnalysisUsage(AU)` for every registered pass.
2. PM collects dependencies from `AU.addRequired` called in `getAnalysisUsage()`
3. PM run all the required Analysis Passes in advance.
4. PM calls `runOnXXX`(s) following the specific order.
#v(-0.5em)
#grid(
  columns: (2fr, 5fr),
  gutter: 0em,
  [
```cpp
// instantiate PM
legacy::PassManager PM;

// register pass to PM
PM.add(new MyPass());

PM.run(Module);
```
  ],[
#v(-0.2em)
```cpp
struct MyPass : public FunctionPass {
  static char ID;
  MyPass() : FunctionPass(ID) {}

  void getAnalysisUsage(AnalysisUsage &AU) const override {
    AU.addRequired<DominatorTreeWrapperPass>();
    AU.setPreservesCFG();
  }

  bool runOnFunction(Function &F) override {
    auto &DT = getAnalysis<DominatorTreeWrapperPass>().getDomTree();
  }
};
```
  ]
)
]

#slide(title: [Legacy pass manager: Expressing the dependencies of a pass])[
To describe the dependencies of a pass (and of an analysis), you must describe two elements
#boxed([Which analyses the pass depends on])[
All you need to do is to *_override the_* `Pass::getAnalysisUsage(AnalysisUsage &AU)` *_method_*, which will be called by pass manager at the beginning of `PM.run()` for pass scheduling.
- You can add dependencies to provided `AnalysisUsage` object by calling `AnalysisUsage::addRequired</*PassClass*/>()` for each analysis.
- You will be able to use the result of the analysis in the `runOnXXX` by calling `Pass::getAnalysis</*PassClass*/>()`
]
#boxed([How this pass and its analyses are initialized])[
- You need to provide a specific ID to register your pass by adding a `static char ID` field to your class and initializing this field to any value outside of the class (like `char MyPass::ID = 0;`)
]
]

#slide(title: [Legacy pass manager: preserving analyses])[
Make sure the boolean status returned by `runOnXXX` accurately captures whether you made changes to the IR.

The implication of this boolean is:

// #align(center)[
    If a pass returns `true`, PM assumes that each analysis previously performed is invalidated, meaning that if a later pass needs one of them. Thus, PM will have to reschedule them to recompute them.
// ]


]

#slide(title: [New pass manager])[
Sorry, I was running out of time.
I will upload next week (off on schedule)...
]

// #slide(title: [New pass manager: Implementing the right method])[
// aa
// ]

// #slide(title: [New pass manager: Registering an analysis])[
// aa
// ]

// #slide(title: [New pass manager: Describing the effects of your pass])[
// aa
// ]

#slide(title: [LLVM IR API corresponding to each component])[
#v(-0.5em)
#grid(
  columns: (2fr, 1fr),
  gutter: 1em,
  [
#figure(
  image("figures/llvm_ir_api_cheat.png"),
  //  caption: [interleave linear and full, DWD]
)<llvm_ir_api_cheat>
  ],[
Every component at every level has corresponding API to read/write IR.
  ]
)
]

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

#slide(title: [Implementation Tasks])[
Work on *Your turn* of Chapter 5.
- Writing your own pass, one for legacy pass manager, and one for the new pass manager.
- Writing your own pass pipeline.
]
