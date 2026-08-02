#!/usr/bin/env bash
#
# Exercise 2: Order Matters.
#
#   ./run.sh            run all cases
#   ./run.sh A B        run only the named case(s)
#   ./run.sh --check    also assert the invariant each case demonstrates
#
# Predict each output before you look. Only `opt` is required.

set -u -o pipefail
cd "$(dirname "$0")"

OPT="${OPT:-opt}"
command -v "$OPT" >/dev/null 2>&1 || {
  echo "error: '$OPT' not on PATH (try: export PATH=\"/opt/homebrew/opt/llvm/bin:\$PATH\")" >&2
  exit 1
}

if [ -t 1 ]; then B=$'\033[1m'; D=$'\033[2m'; G=$'\033[32m'; R=$'\033[31m'; O=$'\033[0m'
else B=""; D=""; G=""; R=""; O=""; fi

CHECK=0; FAILED=0
mkdir -p out

case_hdr() { printf '\n%s===== Case %s =====%s\n' "$B" "$1" "$O"; }
say() { printf '%s%s%s\n' "$D" "$1" "$O"; }

# show <pipeline> <input> [function-name]
show() {
  local pipeline="$1" input="$2" fn="${3:-}"
  local tag; tag=$(echo "$pipeline" | tr -cd 'a-z0-9'),$(basename "$input" .ll)
  printf '\n%s$ opt -passes=%s %s -S%s\n' "$D" "'$pipeline'" "$input" "$O"
  if ! "$OPT" -passes="$pipeline" "$input" -S -o "out/$tag.ll" 2>"out/$tag.err"; then
    cat "out/$tag.err"; return 0
  fi
  if [ -n "$fn" ]; then
    sed -n "/^define .*@$fn(/,/^}/p" "out/$tag.ll" | sed 's/^/  /'
  else
    grep -vE '^; |^source_filename|^target |^$|^attributes ' "out/$tag.ll" | sed 's/^/  /'
  fi
}

assert() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then printf '  %sPASS%s %s\n' "$G" "$O" "$desc"
  else printf '  %sFAIL%s %s\n' "$R" "$O" "$desc"; FAILED=$((FAILED+1)); fi
}

# --- Case A: mem2reg before or after dce -----------------------------------
case_A() {
  case_hdr "A -- mem2reg before or after dce?"
  say "@dead_through_memory stores a computed value into a slot nobody reads."
  show 'dce,mem2reg' ir/order.ll dead_through_memory
  show 'mem2reg,dce' ir/order.ll dead_through_memory
  say ""
  say "dce cannot touch %v while the store still uses it, and cannot remove the"
  say "store because stores have side effects. Only after mem2reg deletes the"
  say "alloca and the store does %v become removable -- and dce has already run."
  say "This is why the chapter says to run mem2reg 'as soon as possible'."

  if [ "$CHECK" = 1 ]; then
    # order.ll holds three functions, so match the dead multiply exactly rather
    # than grepping the whole file (@cse_exposed has a live `mul` of its own).
    assert "dce,mem2reg leaves the dead multiply behind" \
      grep -q 'mul i64 %in, 3' out/dcemem2reg,order.ll
    assert "mem2reg,dce removes everything" \
      test "$(grep -c 'mul i64 %in, 3' out/mem2regdce,order.ll)" -eq 0
  fi
}

# --- Case B: lcssa then instcombine ----------------------------------------
case_B() {
  case_hdr "B -- lcssa, then instcombine"
  show 'lcssa' ir/loop.ll def_in_loop_use_outside
  show 'lcssa,instcombine' ir/loop.ll def_in_loop_use_outside
  say ""
  say "The .lcssa phi is gone. LCSSA form is ephemeral, so it belongs immediately"
  say "in front of whatever consumes it -- not 'early, once'. A loop pass never"
  say "has this problem: LoopAnalysisManager guarantees the form on entry."

  if [ "$CHECK" = 1 ]; then
    assert "lcssa alone inserts the phi" grep -q '\.lcssa' out/lcssa,loop.ll
    assert "instcombine afterwards removes it" \
      test "$(grep -c '\.lcssa' out/lcssainstcombine,loop.ll)" -eq 0
  fi
}

# --- Case C: reassociate as an enabler -------------------------------------
case_C() {
  case_hdr "C -- who enables whom?"
  say "C1: a 9-instruction add chain with constants scattered through it."
  show 'instcombine' ir/order.ll chain
  show 'reassociate' ir/order.ll chain
  say ""
  say "instcombine changes NOTHING here. reassociate collects 1+2+3+4+5 into 15"
  say "and drops the chain to 5 instructions. Passes are not ordered by strength;"
  say "they have different reach."

  say ""
  say "C2: (a+b)+c and (b+c)+a -- the same value, spelled two ways."
  show 'instcombine,early-cse' ir/order.ll cse_exposed
  show 'reassociate' ir/order.ll cse_exposed
  show 'reassociate,early-cse' ir/order.ll cse_exposed
  say ""
  say "This is the chapter's claim, literally: reassociate works partly 'by"
  say "exposing common subexpression elimination'. Alone, it rewrites both chains"
  say "into the SAME form and then stops -- you still have two copies. It is"
  say "early-cse that collapses them, and early-cse could not have done it"
  say "without reassociate first. Neither pass alone gets %r = mul %x2, %x2."

  if [ "$CHECK" = 1 ]; then
    assert "C1: instcombine alone does not fold the chain" \
      grep -q 'add i64 %t1, %b' out/instcombine,order.ll
    assert "C1: reassociate folds the constants to 15" \
      grep -q 'add i64 %a, 15' out/reassociate,order.ll
    assert "C2: instcombine+early-cse leaves both chains" \
      grep -q '%y1 = add' out/instcombineearlycse,order.ll
    assert "C2: reassociate alone leaves a duplicate chain" \
      grep -q '%y1 = add' out/reassociate,order.ll
    assert "C2: reassociate+early-cse collapses it" \
      grep -q 'mul i64 %x2, %x2' out/reassociateearlycse,order.ll
  fi
}

# --- Case D: instcombine undoes your target-specific form ------------------
case_D() {
  case_hdr "D -- the trap in the other direction"
  say "Your imaginary target has add and negate but no subtract, so your pass"
  say "deliberately produced the non-canonical form."
  show 'instcombine' ir/target_form.ll target_prefers_add_and_negate
  say ""
  say "instcombine restored the canonical 'sub' and your work is gone. The"
  say "chapter offers two ways out:"
  say "  1. stop running instcombine once target-specific constructs appear"
  say "     (the typical pipeline shape), or"
  say "  2. use the simplifyXXXInst helpers from the Analysis library, which give"
  say "     you the folds without the canonicalization."

  if [ "$CHECK" = 1 ]; then
    assert "instcombine reverted the form to a single sub" \
      grep -q 'sub i64 %b, %c' out/instcombine,target_form.ll
    assert "the negate is gone" \
      test "$(grep -c 'sub i64 0, %c' out/instcombine,target_form.ll)" -eq 0
  fi
}

case "${1:-}" in --check) CHECK=1; shift ;; esac

say "using $(command -v "$OPT")  -- $("$OPT" --version | sed -n '1p' | sed 's/^ *//')"

if [ "$#" -gt 0 ]; then
  for c in "$@"; do
    case "$c" in
      A|a) case_A ;; B|b) case_B ;; C|c) case_C ;; D|d) case_D ;;
      *) echo "error: unknown case '$c' (use A, B, C, or D)" >&2; exit 2 ;;
    esac
  done
else
  case_A; case_B; case_C; case_D
fi

if [ "$CHECK" = 1 ]; then
  printf '\n'
  if [ "$FAILED" -eq 0 ]; then printf '%sall checks passed%s\n' "$G" "$O"
  else printf '%s%d check(s) failed%s\n' "$R" "$FAILED" "$O"; exit 1; fi
fi
