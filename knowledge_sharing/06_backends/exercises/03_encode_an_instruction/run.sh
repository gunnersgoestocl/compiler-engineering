#!/usr/bin/env bash
#
# Exercise 3: Encode an Instruction.
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
step() { printf '\n%s$ %s%s\n' "$D" "$1" "$O"; }
assert() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then printf '  %sPASS%s %s\n' "$G" "$O" "$desc"
  else printf '  %sFAIL%s %s\n' "$R" "$O" "$desc"; FAILED=$((FAILED+1)); fi
}

# build <which> <backend> <suffix>
build() {
  local which="$1" backend="$2" suffix="$3"
  if ! "$TBLGEN" "-$backend" -I "$TD_INC" -I . "$which/target.td" \
        -o "out/$which.$suffix.inc" 2>"out/$which.$suffix.err"; then
    printf '  %sTableGen failed (-%s):%s\n' "$R" "$backend" "$O"
    sed 's/^/    /' "out/$which.$suffix.err"
    return 1
  fi
  return 0
}

# report <which>: the three things that say whether the description is right
report() {
  local which="$1"

  say "opcodes and their base encodings (the opcode field, already shifted):"
  sed -n '/static const uint64_t InstBits/,/^  };/p' "out/$which.emit.inc" \
    | grep 'UINT64_C' | sed 's/^  */    /'

  say ""
  say "the operand encodings TableGen derived from the Inst{...} assignments:"
  awk '/^  const unsigned opcode/ {f=1} f' "out/$which.emit.inc" \
    | awk '/^    case Tiny::/ {print} /^      \/\/ op:/ {print} /Value \|=/ {print} /^  default:/ {exit}' \
    | sed 's/^ */    /'

  say ""
  say "the mnemonics that reached the assembly writer (from AsmString):"
  grep -oE '"[a-z]+ \\000"' "out/$which.asm.inc" \
    | tr -d '"\\' | sed 's/000$//' | sort -u | sed 's/^/    /'

  say ""
  say "the MCInstrDesc contract -- opcode, NumOperands, NumDefs, flags:"
  desc_table "$which" | sed 's/^/    /'

  # Machine-comparable summary: base encodings, operand shifts, and the
  # per-opcode descriptor contract.
  {
    sed -n '/static const uint64_t InstBits/,/^  };/p' "out/$which.emit.inc" \
      | grep -oE 'UINT64_C\([0-9]+\).*// [A-Z]+' | sed 's/UINT64_C(//; s/).*\/\/ / /'
    awk '/^  const unsigned opcode/ {f=1} f && (/^      \/\/ op:/ || /Value \|=/) {print}' \
      "out/$which.emit.inc" | tr -s ' '
    desc_table "$which"
  } > "out/$which.summary"
}

# case_block <which> <OPCODE>: the emitter's switch arm for one opcode, so an
# assertion about MOVI's bit placement cannot be satisfied by ADD's.
case_block() {
  awk -v want="^ *case Tiny::$2:" '
    $0 ~ want {f=1}
    f {print}
    f && /break;/ {exit}
  ' "out/$1.emit.inc"
}

# desc_table <which>: one line per instruction --
#   NAME numOperands numDefs FLAG,FLAG,...
# Only our own instructions; the generic pseudo-instructions are skipped.
desc_table() {
  local which="$1"
  grep -E '^\s*\{ [0-9]+,.*\}, +// (ADD|SUB|AND|MOVI)$' "out/$which.instr.inc" \
  | while IFS= read -r line; do
      local name ops defs flags
      name=${line##*// }
      ops=$(printf '%s' "$line" | awk -F'[{,]' '{gsub(/[ \t]/,"",$3); print $3}')
      defs=$(printf '%s' "$line" | awk -F'[{,]' '{gsub(/[ \t]/,"",$4); print $4}')
      flags=$(printf '%s' "$line" | grep -oE 'MCID::[A-Za-z]+' \
              | sed 's/MCID:://' | sort | paste -sd, -)
      printf '%-6s operands=%-3s defs=%-3s %s\n' "$name" "$ops" "$defs" "$flags"
    done | sort
}

# --- solution --------------------------------------------------------------
hdr "solution"
for b in "gen-emitter:emit" "gen-asm-writer:asm" "gen-instr-info:instr"; do
  build solution "${b%%:*}" "${b##*:}" || exit 1
done
step "llvm-tblgen -gen-emitter -gen-asm-writer -gen-instr-info solution/target.td"
report solution

[ "$ONLY" = "solution" ] && exit 0

# --- your turn -------------------------------------------------------------
hdr "your_turn"
for b in "gen-emitter:emit" "gen-asm-writer:asm" "gen-instr-info:instr"; do
  build your_turn "${b%%:*}" "${b##*:}" || {
    say ""
    say "Fix the TableGen errors above, then run again."
    exit 1
  }
done
report your_turn

# --- compare ---------------------------------------------------------------
hdr "comparison"
if diff -u out/solution.summary out/your_turn.summary > out/diff.txt; then
  printf '  %smatch -- your instructions encode identically to the solution%s\n' "$G" "$O"
else
  printf '  %sdifferent:%s\n' "$R" "$O"
  sed -n '4,$p' out/diff.txt | sed 's/^/    /'
  say ""
  say "Reading the diff:"
  say ""
  say "  a missing 'NNNN // AND' line      task 1 is not done"
  say "  a missing 'NNNNN // MOVI' line    task 2 is not done"
  say "  the right opcode, wrong number    check the SHIFT. 0b1000 in"
  say "                                    Inst{15-12} is 0x8000 = 32768"
  say "  a 'Value |= ... << N' mismatch    your Inst{...} ranges differ."
  say "                                    Write them high-to-low: Inst{9-0},"
  say "                                    not Inst{0-9}"
  say "  MOVI's flags lack CheapAsAMove    task 3 is not done"
fi

if [ "$CHECK" = 1 ]; then
  printf '\n'
  assert "task 1: AND exists, opcode 0b0011 at bit 12 (= 12288)" \
    grep -q 'UINT64_C(12288).*// AND' out/your_turn.emit.inc
  assert "task 1: AND reuses the ALU family's three-operand shape" \
    grep -qE '^AND +operands=3 +defs=1' out/your_turn.summary
  assert "task 2: MOVI exists, opcode 0b1000 at bit 12 (= 32768)" \
    grep -q 'UINT64_C(32768).*// MOVI' out/your_turn.emit.inc
  assert "task 2: MOVI takes 2 operands and defines 1" \
    grep -qE '^MOVI +operands=2 +defs=1' out/your_turn.summary
  assert "task 2: MOVI's dst lands in Inst{11-10}" \
    grep -q 'Value |= (op & 0x3) << 10' <(case_block your_turn MOVI)
  assert "task 2: MOVI's imm is 10 bits at offset 0" \
    grep -q 'Value |= (op & 0x3ff);' <(case_block your_turn MOVI)
  assert "task 2: 'movi' reached the assembly writer" \
    grep -q '"movi ' out/your_turn.asm.inc
  assert "task 3: MOVI is marked isAsCheapAsAMove" \
    grep -qE '^MOVI .*CheapAsAMove' out/your_turn.summary
  assert "the whole description matches the solution" \
    diff -q out/solution.summary out/your_turn.summary
  printf '\n'
  if [ "$FAILED" -eq 0 ]; then printf '%sall checks passed%s\n' "$G" "$O"
  else printf '%s%d check(s) failed%s\n' "$R" "$FAILED" "$O"; exit 1; fi
fi
