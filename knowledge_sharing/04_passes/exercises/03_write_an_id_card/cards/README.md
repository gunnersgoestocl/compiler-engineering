# Cards

One file per pass, named `<cli-name>.md`. Add a row when you write one.

| Pass | CLI name | Scope | Target-specific | Author |
|---|---|---|---|---|
| Loop deletion | `loop-deletion` | Loop | none | worked example |

## Extending the chapter's catalog

Chapter 8 covers 13 passes with identity cards (3 IPO, 7 Scalar, 3 Vectorize) plus
3 canonicalization passes, out of the several hundred in `opt --print-passes`. The
chapter is explicit that this is a sample, not a survey:

> "LLVM is a huge code base, so we cannot realistically cover all of the passes.
> This is why we again strongly recommend applying what you learned in the *How to
> find the unknown* section."

So this directory is the chapter's own suggestion taken literally. If the table
above gets long enough to be useful as a reference, the exercise worked.

## Verify before you commit

A card whose `Out` was not produced by running the command is worse than no card —
it will be trusted. Check yours:

```sh
export PATH="/opt/homebrew/opt/llvm/bin:$PATH"
opt -passes='<your pipeline>' ir/<your input>.ll -S
```

and paste what you actually got, including the parts you did not expect.
