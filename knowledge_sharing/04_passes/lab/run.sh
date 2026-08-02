#!/usr/bin/env bash
#
# 08_passes lab driver.
#
# Nothing here compiles. Every stage is a plain `opt` invocation, so this script
# only needs `opt` on PATH -- no CMake, no LLVM_DIR, no plugin.
#
#   ./run.sh                 run every stage, printing input/output diffs
#   ./run.sh <stage> ...     run only the named stage(s)
#   ./run.sh --check         run every stage and assert its key invariant
#   ./run.sh --list          list stage names
#
# Outputs land in out/.

set -u -o pipefail

cd "$(dirname "$0")"
mkdir -p out

OPT="${OPT:-opt}"
if ! command -v "$OPT" >/dev/null 2>&1; then
  echo "error: '$OPT' not found on PATH." >&2
  echo "hint:  export PATH=\"/opt/homebrew/opt/llvm/bin:\$PATH\"   (Homebrew LLVM on macOS)" >&2
  echo "hint:  or set OPT=/path/to/opt" >&2
  exit 1
fi

STAGES=(verify mem2reg analysis printers scope-trap lcssa-ephemeral pass-order)

# --- output helpers ---------------------------------------------------------

if [ -t 1 ]; then BOLD=$'\033[1m'; DIM=$'\033[2m'; GRN=$'\033[32m'; RED=$'\033[31m'; OFF=$'\033[0m'
else BOLD=""; DIM=""; GRN=""; RED=""; OFF=""; fi

CHECK=0
FAILED=0

banner() { printf '\n%s========== %s ==========%s\n' "$BOLD" "$1" "$OFF"; }
step()   { printf '\n%s$ %s%s\n' "$DIM" "$1" "$OFF"; }
say()    { printf '%s%s%s\n' "$DIM" "$1" "$OFF"; }

# assert <description> <test-command...>
assert() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf '  %sPASS%s %s\n' "$GRN" "$OFF" "$desc"
  else
    printf '  %sFAIL%s %s\n' "$RED" "$OFF" "$desc"
    FAILED=$((FAILED + 1))
  fi
}

# Strip the noise that varies between LLVM versions so diffs stay readable.
strip_noise() {
  grep -v '^; ModuleID\|^source_filename\|^target datalayout\|^; Function Attrs\|^attributes #\|^$' "$1"
}

# show_diff <input.ll> <output.ll>
show_diff() {
  strip_noise "$1" | grep -v '^;' > out/.a
  strip_noise "$2" > out/.b
  diff -U100 out/.a out/.b | tail -n +4 || true
  rm -f out/.a out/.b
}

# ---------------------------------------------------------------------------
# 1. verify -- the verifier catches a non-dominating use
# ---------------------------------------------------------------------------
stage_verify() {
  banner "verify"
  say "Chapter 8: 'Any time you encounter weird issues with some IR, make sure to"
  say "run the verifier on it.' Here the IR breaks SSA: %a is defined in %then,"
  say "which does not dominate %merge."

  step "$OPT -passes=verify ir/use_before_def.ll -disable-output"
  "$OPT" -passes=verify ir/use_before_def.ll -disable-output > out/verify.txt 2>&1
  local rc=$?
  cat out/verify.txt
  say "(exit status $rc -- a nonzero status is the point)"

  say ""
  say "Now the same check as it appears in a real pipeline: -verify-each inserts"
  say "the verifier after EVERY pass, so you learn which pass broke the IR."
  step "$OPT -passes='dce,instcombine' -verify-each ir/use_before_def.ll -disable-output"
  "$OPT" -passes='dce,instcombine' -verify-each ir/use_before_def.ll -disable-output 2>&1 | head -6

  if [ "$CHECK" = 1 ]; then
    assert "verifier reports the non-dominating use" \
      grep -q "does not dominate all uses" out/verify.txt
    assert "verifier exits nonzero on broken IR" test "$rc" -ne 0
  fi
}

# ---------------------------------------------------------------------------
# 2. mem2reg -- the canonicalization pass upstream ch8/ has no input for
# ---------------------------------------------------------------------------
stage_mem2reg() {
  banner "mem2reg"
  say "Promotes memory to SSA values. @straight_line is trivial; @needs_phi"
  say "requires INSERTING a phi; @escapes cannot be promoted at all because the"
  say "alloca's address is passed to another function."

  step "$OPT -passes=mem2reg ir/mem2reg.ll -S"
  "$OPT" -passes=mem2reg ir/mem2reg.ll -S -o out/mem2reg.out.ll 2>&1 || return 1
  show_diff ir/mem2reg.ll out/mem2reg.out.ll

  if [ "$CHECK" = 1 ]; then
    assert "@needs_phi gained a phi node" \
      grep -q 'phi i64' out/mem2reg.out.ll
    assert "@straight_line's alloca is gone" \
      test "$(grep -c 'alloca' out/mem2reg.out.ll)" -eq 1
    assert "@escapes kept its alloca (address escaped)" \
      grep -q 'call void @sink' out/mem2reg.out.ll
  fi
}

# ---------------------------------------------------------------------------
# 3. analysis -- analyses you can actually see
# ---------------------------------------------------------------------------
stage_analysis() {
  banner "analysis"
  say "Most analyses have no observable effect: require<target-ir> computes"
  say "TargetTransformInfo, but if nothing consumes it you see nothing. A few"
  say "support print<...>, which is the only cheap way to inspect them."

  step "$OPT -passes='print<loops>' ir/loop.ll -disable-output"
  "$OPT" -passes='print<loops>' ir/loop.ll -disable-output > out/loops.txt 2>&1
  cat out/loops.txt

  step "$OPT -passes='print<domtree>' ir/loop.ll -disable-output"
  "$OPT" -passes='print<domtree>' ir/loop.ll -disable-output > out/domtree.txt 2>&1
  cat out/domtree.txt

  say ""
  say "Contrast: an analysis with no printer produces no output at all."
  step "$OPT -passes='require<target-ir>' ir/loop.ll -disable-output"
  "$OPT" -passes='require<target-ir>' ir/loop.ll -disable-output 2>&1
  say "(nothing above -- the analysis ran, but nothing consumed it)"

  if [ "$CHECK" = 1 ]; then
    assert "loop printer identifies the header/latch/exiting block" \
      grep -q 'header' out/loops.txt
    assert "domtree printer shows entry dominating the tree" \
      grep -q '%entry' out/domtree.txt
  fi
}

# ---------------------------------------------------------------------------
# 4. printers -- one registered name, three passes, chosen by scope
# ---------------------------------------------------------------------------
stage_printers() {
  banner "printers"
  say "'print' is registered once for all three scopes. Which pass actually runs"
  say "depends on the enclosing pipeline scope -- so a nested pipeline gives you"
  say "PrintFunctionPass and PrintLoopPass from the same spelling."

  step "$OPT --passes='function(print,loop(print))' ir/loop.ll -disable-output"
  "$OPT" --passes='function(print,loop(print))' ir/loop.ll -disable-output > out/printers.txt 2>&1
  cat out/printers.txt

  say ""
  say "Two things to notice."
  say ""
  say "1. The loop printer is not the function printer restricted: it labels loop"
  say "   structure (Preheader / Loop / Exit blocks) that only makes sense"
  say "   per-loop."
  say ""
  say "2. Compare the two %end blocks above. The FUNCTION printer shows no"
  say "   .lcssa value; the LOOP printer shows %iv_plus_1.lcssa -- and we never"
  say "   asked for lcssa anywhere in this pipeline. Entering the loop scope"
  say "   materialised LCSSA form, because LoopAnalysisManager guarantees loop"
  say "   passes receive loops in that form. The scope keyword did not just"
  say "   choose which printer runs; it changed the IR the printer saw."

  if [ "$CHECK" = 1 ]; then
    assert "loop printer labelled the preheader" \
      grep -q 'Preheader' out/printers.txt
    assert "function printer emitted the whole define" \
      grep -q 'define i64 @def_in_loop_use_outside' out/printers.txt
    # The .lcssa phi appears only after the loop scope is entered, i.e. strictly
    # later in the output than the function printer's copy of %end.
    assert "entering loop scope introduced LCSSA form unrequested" \
      grep -q '\.lcssa' out/printers.txt
  fi
}

# ---------------------------------------------------------------------------
# 5. scope-trap -- the two pipeline strings that fail, and why
# ---------------------------------------------------------------------------
stage_scope_trap() {
  banner "scope-trap"
  say "dce is a Function pass; globaldce is a Module pass. Naming dce first fixes"
  say "the inferred scope to function -- and then globaldce is not a valid name."

  step "$OPT -passes='dce,globaldce' ir/scope.ll -S"
  "$OPT" -passes='dce,globaldce' ir/scope.ll -S -o /dev/null > out/scope_bad.txt 2>&1
  cat out/scope_bad.txt
  say "(read the error carefully: 'unknown FUNCTION pass' names the inferred scope)"

  say ""
  say "Naming the scopes explicitly works:"
  step "$OPT -passes='function(dce),globaldce' ir/scope.ll -S"
  "$OPT" -passes='function(dce),globaldce' ir/scope.ll -S -o out/scope_good.ll 2>&1 || return 1
  show_diff ir/scope.ll out/scope_good.ll

  say ""
  say "There is a second, nastier version of this trap. The book mentions three"
  say "scope keywords (module/function/loop); there are actually two LOOP scopes."
  step "$OPT -passes='licm' ir/licm.ll -S            # bare: scope inferred"
  "$OPT" -passes='licm' ir/licm.ll -S -o /dev/null 2>&1 && say "  -> works"
  step "$OPT -passes='loop(licm)' ir/licm.ll -S      # explicit 'loop'"
  "$OPT" -passes='loop(licm)' ir/licm.ll -S -o /dev/null > out/licm_bad.txt 2>&1
  cat out/licm_bad.txt
  step "$OPT -passes='loop-mssa(licm)' ir/licm.ll -S"
  "$OPT" -passes='loop-mssa(licm)' ir/licm.ll -S -o out/licm_good.ll 2>&1 && say "  -> works"

  say ""
  say "  loop(...)       LCSSA form, innermost-first order"
  say "  loop-mssa(...)  the same, PLUS a maintained MemorySSA"
  say ""
  say "licm's legality argument is entirely about memory, so it needs MemorySSA."
  say "Note what this means: BEING EXPLICIT is what broke it -- the inferred scope"
  say "was already loop-mssa. And it fails at run time, not parse time: opt"
  say "accepts the pipeline string and only aborts once a loop actually reaches"
  say "licm, so on input without loops it passes silently."

  if [ "$CHECK" = 1 ]; then
    assert "unscoped pipeline is rejected" \
      grep -q "unknown function pass 'globaldce'" out/scope_bad.txt
    assert "scoped pipeline removed the dead instruction" \
      test "$(grep -c '%dead' out/scope_good.ll)" -eq 0
    assert "scoped pipeline removed the uncalled internal function" \
      test "$(grep -c 'never_called' out/scope_good.ll)" -eq 0
    assert "loop(licm) is rejected for lack of MemorySSA" \
      grep -q 'requires MemorySSA' out/licm_bad.txt
    assert "loop-mssa(licm) hoists the invariant load" \
      grep -q 'load i64, ptr %addr' out/licm_good.ll
  fi
}

# ---------------------------------------------------------------------------
# 6. lcssa-ephemeral -- LCSSA form does not survive instcombine
# ---------------------------------------------------------------------------
stage_lcssa_ephemeral() {
  banner "lcssa-ephemeral"
  say "The chapter says LCSSA form 'is ephemeral in the sense that it can be"
  say "easily reverted by other optimizations. For instance, instcombine will get"
  say "rid of the additional phi'. Here is that happening."

  step "$OPT -passes='lcssa' ir/loop.ll -S"
  "$OPT" -passes='lcssa' ir/loop.ll -S -o out/lcssa.out.ll 2>&1 || return 1
  strip_noise out/lcssa.out.ll | grep -A3 '^end:'

  step "$OPT -passes='lcssa,instcombine' ir/loop.ll -S"
  "$OPT" -passes='lcssa,instcombine' ir/loop.ll -S -o out/lcssa_undone.out.ll 2>&1 || return 1
  strip_noise out/lcssa_undone.out.ll | grep -A3 '^end:'

  say ""
  say "No .lcssa value survives. Consequence: put lcssa immediately in front of"
  say "the pass that needs it. (Loop passes get the form guaranteed for free --"
  say "which is why the licm output in the slides has an .lcssa phi nobody asked"
  say "for.)"

  if [ "$CHECK" = 1 ]; then
    assert "lcssa alone inserts an .lcssa phi" \
      grep -q '\.lcssa' out/lcssa.out.ll
    assert "instcombine afterwards removes it" \
      test "$(grep -c '\.lcssa' out/lcssa_undone.out.ll)" -eq 0
  fi
}

# ---------------------------------------------------------------------------
# 7. pass-order -- quiz 4, and the scoping trap it walks into
# ---------------------------------------------------------------------------
stage_pass_order() {
  banner "pass-order"
  say "indvars leaves 'br i1 false' behind. Quiz 4: which pass removes it?"

  step "$OPT -passes='indvars' ir/indvars.ll -S"
  "$OPT" -passes='indvars' ir/indvars.ll -S -o out/indvars.out.ll 2>&1 || return 1
  strip_noise out/indvars.out.ll

  say ""
  say "Answer: simplifycfg. But chaining them naively hits the scope trap --"
  say "indvars is a Loop pass, simplifycfg is a Function pass."
  step "$OPT -passes='indvars,simplifycfg' ir/indvars.ll -S"
  "$OPT" -passes='indvars,simplifycfg' ir/indvars.ll -S -o /dev/null > out/order_bad.txt 2>&1
  cat out/order_bad.txt

  say ""
  step "$OPT -passes='loop(indvars),simplifycfg' ir/indvars.ll -S"
  "$OPT" -passes='loop(indvars),simplifycfg' ir/indvars.ll -S -o out/order_good.ll 2>&1 || return 1
  strip_noise out/order_good.ll

  say ""
  say "Four basic blocks became one, and the loop is gone entirely -- neither"
  say "pass could have done that alone."

  if [ "$CHECK" = 1 ]; then
    assert "indvars alone leaves a constant-condition branch" \
      grep -q 'br i1 false' out/indvars.out.ll
    assert "unscoped chain is rejected as a loop pipeline" \
      grep -q "unknown loop pass 'simplifycfg'" out/order_bad.txt
    assert "scoped chain eliminates the loop" \
      test "$(grep -c 'br i1 false' out/order_good.ll)" -eq 0
  fi
}

# --- dispatch --------------------------------------------------------------

run_stage() {
  case "$1" in
    verify)           stage_verify ;;
    mem2reg)          stage_mem2reg ;;
    analysis)         stage_analysis ;;
    printers)         stage_printers ;;
    scope-trap)       stage_scope_trap ;;
    lcssa-ephemeral)  stage_lcssa_ephemeral ;;
    pass-order)       stage_pass_order ;;
    *) echo "error: unknown stage '$1'. Try --list." >&2; exit 2 ;;
  esac
}

case "${1:-}" in
  --list) printf '%s\n' "${STAGES[@]}"; exit 0 ;;
  --help|-h) sed -n '3,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  --check) CHECK=1; shift ;;
esac

say "using $(command -v "$OPT")  -- $("$OPT" --version | sed -n '1p' | sed 's/^ *//')"

if [ "$#" -gt 0 ]; then
  for s in "$@"; do run_stage "$s"; done
else
  for s in "${STAGES[@]}"; do run_stage "$s"; done
fi

if [ "$CHECK" = 1 ]; then
  printf '\n'
  if [ "$FAILED" -eq 0 ]; then
    printf '%sall checks passed%s\n' "$GRN" "$OFF"
  else
    printf '%s%d check(s) failed%s\n' "$RED" "$FAILED" "$OFF"
    exit 1
  fi
fi
