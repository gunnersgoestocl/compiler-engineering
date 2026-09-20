#!/usr/bin/env bash
#
# Exercise 2: Register Units.
#
#   ./run.sh            build both descriptions and compare
#   ./run.sh --check    also assert that your_turn matches the solution
#   ./run.sh solution   show the solution's output only
#
# Only `llvm-tblgen` and `llvm-config` are required. Nothing compiles.

set -u -o pipefail
cd "$(dirname "$0")"

TBLGEN="${TBLGEN:-llvm-tblgen}"
CONFIG="${LLVM_CONFIG:-llvm-config}"
for t in "$TBLGEN" "$CONFIG"; do
  command -v "$t" >/dev/null 2>&1 || {
    echo "error: '$t' not on PATH (try: export PATH=\"/opt/homebrew/opt/llvm/bin:\$PATH\")" >&2
    exit 1
  }
done
TD_INC="${TD_INC:-$("$CONFIG" --includedir)}"

if [ -t 1 ]; then B=$'\033[1m'; D=$'\033[2m'; G=$'\033[32m'; R=$'\033[31m'; O=$'\033[0m'
else B=""; D=""; G=""; R=""; O=""; fi

CHECK=0; FAILED=0
[ "${1:-}" = "--check" ] && { CHECK=1; shift; }
ONLY="${1:-}"

mkdir -p out

say()  { printf '%s%s%s\n' "$D" "$1" "$O"; }
hdr()  { printf '\n%s===== %s =====%s\n' "$B" "$1" "$O"; }
assert() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then printf '  %sPASS%s %s\n' "$G" "$O" "$desc"
  else printf '  %sFAIL%s %s\n' "$R" "$O" "$desc"; FAILED=$((FAILED+1)); fi
}

# build <which> -> out/<which>{Enums,MCDesc,Header,TargetDesc}.inc
build() {
  local which="$1"
  if ! "$TBLGEN" -gen-register-info -I "$TD_INC" "$which/reginfo.td" \
        -o "out/$which.inc" 2>"out/$which.err"; then
    printf '  %sTableGen failed:%s\n' "$R" "$O"
    sed 's/^/    /' "out/$which.err"
    return 1
  fi
  return 0
}

# report <which>: the three numbers that describe a register file
report() {
  local which="$1" mc="out/${1}MCDesc.inc"
  local units regs classes
  units=$(sed -n '/RegUnitRoots\[\]\[2\]/,/^};/p' "$mc" | grep -c 'Fig112::')
  regs=$(grep -oE 'InitMCRegisterInfo\(Fig112RegDesc, [0-9]+' "$mc" \
         | grep -oE '[0-9]+$')
  classes=$(grep -c '^  // [A-Za-z0-9_]* Register Class' "$mc")
  printf '  %-24s %s\n' "register descriptors" \
    "${regs:-?}  (should be 10: 9 registers + the NoRegister sentinel)"
  printf '  %-24s %s\n' "register classes" "${classes:-?}"
  printf '  %-24s %s\n' "REGISTER UNITS" "${units:-?}"
  say ""
  say "  units, in order:"
  sed -n '/RegUnitRoots\[\]\[2\]/,/^};/p' "$mc" | grep -oE 'Fig112::[a-z0-9]+' \
    | sed 's/Fig112::/    /'
  say ""
  say "  register classes TableGen emitted:"
  grep -oE '^  // [A-Za-z0-9_]+ Register Class' "$mc" \
    | sed 's|  // ||; s| Register Class||' | sed 's/^/    /'
  # Leave a machine-comparable summary behind for --check.
  {
    echo "units=$units"
    echo "regs=$regs"
    echo "classes=$classes"
    sed -n '/RegUnitRoots\[\]\[2\]/,/^};/p' "$mc" | grep -oE 'Fig112::[a-z0-9]+'
  } > "out/$which.summary"
}

# --- solution --------------------------------------------------------------
hdr "solution"
build solution || exit 1
report solution
SOL_UNITS=$(grep '^units=' out/solution.summary | cut -d= -f2)
say ""
say "Five units for nine registers. The units are the LEAVES of the hierarchy:"
say "s0, s1, s2 (real leaves), plus d2 and q2, which have no addressable"
say "sub-registers and therefore need units of their own."

[ "$ONLY" = "solution" ] && exit 0

# --- your turn -------------------------------------------------------------
hdr "your_turn"
if ! build your_turn; then
  say ""
  say "Fix the TableGen errors above, then run again."
  exit 1
fi
report your_turn

# --- compare ---------------------------------------------------------------
hdr "comparison"
if diff -u out/solution.summary out/your_turn.summary > out/diff.txt; then
  printf '  %smatch -- your register file has the same shape as the solution%s\n' "$G" "$O"
else
  printf '  %sdifferent:%s\n' "$R" "$O"
  sed -n '4,$p' out/diff.txt | sed 's/^/    /'
  say ""
  say "Read the diff as a description of the shape you built."
  say ""
  say "  fewer registers    you have not declared them all yet"
  say "  MORE units than 5  a register is missing its SubRegs/SubRegIndices,"
  say "                     so TableGen believes it overlaps nothing and gives"
  say "                     it a unit of its own"
  say "  fewer classes      the register classes do not list all their members"
  say "                     (try the (sequence \"s%u\", 0, 2) form)"
fi

if [ "$CHECK" = 1 ]; then
  printf '\n'
  YT_UNITS=$(grep '^units=' out/your_turn.summary | cut -d= -f2)
  assert "your_turn describes 9 registers" \
    grep -q '^regs=10$' out/your_turn.summary
  assert "your_turn needs exactly $SOL_UNITS register units" \
    test "$YT_UNITS" = "$SOL_UNITS"
  assert "the units are the same registers, in the same order" \
    diff -q <(grep 'Fig112::' out/solution.summary) \
            <(grep 'Fig112::' out/your_turn.summary)
  assert "the synthesised register classes match too" \
    diff -q <(grep '^classes=' out/solution.summary) \
            <(grep '^classes=' out/your_turn.summary)
  printf '\n'
  if [ "$FAILED" -eq 0 ]; then printf '%sall checks passed%s\n' "$G" "$O"
  else printf '%s%d check(s) failed%s\n' "$R" "$FAILED" "$O"; exit 1; fi
fi
