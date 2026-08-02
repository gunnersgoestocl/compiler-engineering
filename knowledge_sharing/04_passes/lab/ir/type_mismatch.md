# Why the type-mismatch verifier example is not a `.ll` file

Chapter 8 gives two examples of what the verifier checks:

1. that a definition dominates all its uses (SSA form), and
2. that "the input arguments of a `fadd` instruction ... are both of the same
   type and that this type is of the floating-point family".

Only the first one is demonstrable from a `.ll` input. If you write

```llvm
define i64 @type_mismatch(i64 %x, i32 %y) {
  %bad = add i64 %x, %y
  ret i64 %bad
}
```

`opt` never reaches the verifier:

```text
opt: type_mismatch.ll:3:22: error: '%y' defined with type 'i32' but expected 'i64'
  %bad = add i64 %x, %y
                     ^
```

That is the **LLParser**, not the verifier. The textual parser type-checks on the
way in, so this module is not merely invalid — it is unconstructible from text.

## Which is the point

This is the clearest way to see what the verifier is *for*. It does not guard
against bad `.ll` files; the parser already does that. It guards against bad IR
built **in memory by a pass**, where nothing type-checks the construction:

```cpp
// Nothing here refuses to build the mismatched add.
Value *Bad = Builder.CreateAdd(XI64, YI32);   // types disagree
```

`IRBuilder` will happily assemble that (`CreateAdd` asserts only in a `+Asserts`
build), and a release-mode LLVM will carry the malformed instruction forward
until some later pass trips over it — a long way from the pass that caused it.

Hence the chapter's two operational recommendations, both of which the `verify`
stage of `run.sh` demonstrates:

- run the verifier on IR whenever something behaves strangely, and
- use `opt -verify-each` (or `VerifyEachPass=true`) so the failure is attributed
  to the pass that actually introduced it, rather than to whichever pass later
  choked on it.

And quiz 2's answer, restated: when an existing pass crashes on your custom
pass's output, the first suspect is your output, not their pass.

## If you want to see it fire

You need to build the malformed IR programmatically. Session 2's
`exercises/02_build_module_irbuilder/` already has the harness for this —
construct a mismatched `add` there, then call `verifyModule`:

```cpp
#include "llvm/IR/Verifier.h"
...
if (verifyModule(*M, &errs()))
  errs() << "module is broken\n";
```

That is left as an optional extension rather than wired in here, because it needs
a compiled C++ target and this lab deliberately requires nothing but `opt`.
