#!/bin/bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: ./mk_progress.sh <dir_name>"
  echo "Example: ./mk_progress.sh 250609_abstraction_proposal"
  exit 1
fi

dir="$1"
out="$dir/main.typ"

if [ -e "$out" ]; then
  echo "Error: $out already exists."
  exit 1
fi

mkdir -p "$dir"

# Optional: derive subtitle from directory name after first underscore.
subtitle="${dir#*_}"
subtitle="${subtitle//_/ }"

today="$(date +%Y/%m/%d)"

cat > "$dir/typst.toml" <<EOF
[project]
root = "../.."
EOF

cat > "$out" <<EOF
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

= Topic 1

#slide(title: [Status and Tasks on XXXX])[
// #octique-inline("check-circle-fill", color: green)
// #octique-inline("alert-fill", color: yellow)
// #octique-inline("sync", color: orange)
// #octique-inline("x-circle-fill", color: red)
// #octique-inline("stop", color: red)
// #octique-inline("question", color: black)
// #octique-inline("skip")
// #octique-inline("no-entry")
==== #octique-inline("checklist") Original plan and Status
1. 
5. PR CI test (pre-q) #octique-inline("x-circle-fill", color: red) (3/48794 fails; )
    - #text(size: 18pt)[ws/inference/test_e2e.py::test_spec_decode_pytorch_compile[glm-4.5-SDR]]
    - #text(size: 16pt)[ws/inference/test_pytorch_compile.py::test_pytorch_compile[model=llama3.1-8b-quantize_weights=False-SDR]]
    - #text(size: 16pt)[ws/inference/test_pytorch_compile.py::test_pytorch_compile[model=llama3.1-8b-quantize_weights=True-SDR]]
// 6. PR review #octique-inline("code-review", color: black) #octique-inline("blocked", color: red)

==== Issue

]

#slide(title: [Next step])[
==== Note
- 

==== TODO
- 
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

#slide(title: [Open Questions])[
1. Question A
2. Question B
]
EOF

echo "Created: $out"