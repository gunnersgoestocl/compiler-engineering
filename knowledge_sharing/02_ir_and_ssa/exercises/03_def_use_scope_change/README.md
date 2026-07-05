# Demo: Def-Use Chains Cross Function Boundaries

This is a demo to run and read, not a fill-in exercise.

The "Def-Use in LLVM" section explains `Value`/`User`/`Use`, but it is easy
to assume def-use chains stay "local" the way a variable's uses stay inside
one function in a typical language. They do not: a `GlobalVariable` is a
`Value` like any other, and any instruction in any function can be one of
its `User`s.

## Build and Run

```sh
cd 02_ir_and_ssa
cmake -S . -B build -DLLVM_DIR="$(llvm-config --cmakedir)"
cmake --build build --target def_use_scope_change
./build/exercises/03_def_use_scope_change/def_use_scope_change
```

## What to Look For

The program builds a module where `@read_in_foo` and `@read_in_bar` both
load the same global `@counter`. It then takes the load instruction inside
`@read_in_bar`, gets the global it reads (`Load.getOperand(0)`), and walks
`Global->users()`. One of those users is the load inside `@read_in_foo` --
following a def-use edge landed in a different function than the one you
started in.

## Question for the Audience

If you replaced the global with an `alloca` inside `@read_in_bar` instead
(a purely local variable), could `@read_in_foo` ever show up in its
use-list? Why not, and what does that say about why globals and constants
need special care when a pass reasons about "local" transformations?
