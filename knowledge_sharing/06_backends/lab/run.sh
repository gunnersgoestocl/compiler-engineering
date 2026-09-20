#!/usr/bin/env bash
#
# 09_13_backend lab driver.
#
# Nothing here compiles. Every stage is a plain invocation of a tool that ships
# with any LLVM install -- opt, llc, llvm-mc, llvm-tblgen, clang -- so this
# script needs no CMake, no LLVM_DIR, no plugin, and no LLVM source checkout.
#
#   ./run.sh                 run every stage
#   ./run.sh <stage> ...     run only the named stage(s)
#   ./run.sh --check         run every stage and assert its key invariant
#   ./run.sh --list          list stage names
#
# Outputs land in out/.

set -u -o pipefail

cd "$(dirname "$0")"
mkdir -p out

OPT="${OPT:-opt}"
LLC="${LLC:-llc}"
MC="${MC:-llvm-mc}"
TBLGEN="${TBLGEN:-llvm-tblgen}"
CLANG="${CLANG:-clang}"
CONFIG="${LLVM_CONFIG:-llvm-config}"

for t in "$OPT" "$LLC" "$MC" "$TBLGEN" "$CONFIG"; do
  command -v "$t" >/dev/null 2>&1 || {
    echo "error: '$t' not found on PATH." >&2
    echo "hint:  export PATH=\"/opt/homebrew/opt/llvm/bin:\$PATH\"   (Homebrew LLVM on macOS)" >&2
    exit 1
  }
done

# llvm-tblgen needs the include directory that holds llvm/Target/Target.td.
TD_INC="${TD_INC:-$("$CONFIG" --includedir)}"

STAGES=(bringup tti intrinsics inject mir operands registers encoding pipeline)

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

# Keep MIR dumps readable: from stdin, print just the instruction body.
mir_body() { sed -n '/body: *|/,$p' | grep -vE '^\s*$'; }

# ---------------------------------------------------------------------------
# 0. bringup -- what a backend physically is, and who calls its init functions
# ---------------------------------------------------------------------------
stage_bringup() {
  banner "bringup"
  say "Chapter 9 says a backend provides three extern \"C\" functions and that"
  say "the build system 'automatically populates InitializeAllTargets' with"
  say "calls to them. Both halves of that are checkable on an installed LLVM --"
  say "no source checkout needed."

  say ""
  say "1. A BACKEND IS A SET OF LIBRARIES, one per subdirectory."
  step "$CONFIG --components | tr ' ' '\\n' | grep '^aarch64'"
  "$CONFIG" --components | tr ' ' '\n' | grep '^aarch64' > out/components.txt
  paste -d'|' out/components.txt /dev/null | while read -r c; do
    case "$c" in
      aarch64)              d="(the component group -- an alias for all of them)" ;;
      aarch64info)          d="TargetInfo/        the Target singleton   [ch9]" ;;
      aarch64desc)          d="MCTargetDesc/      the MC layer           [ch9,12]" ;;
      aarch64codegen)       d="<root>/            TargetMachine, ISel    [ch9,11,13]" ;;
      aarch64asmparser)     d="AsmParser/         .s  -> MCInst          [ch12]" ;;
      aarch64disassembler)  d="Disassembler/      .o  -> MCInst          [not covered]" ;;
      aarch64utils)         d="Utils/             shared helpers" ;;
      *)                    d="" ;;
    esac
    printf '  %-22s %s\n' "$c" "$d"
  done
  say ""
  say "That is the directory layout of llvm/lib/Target/AArch64, one library per"
  say "directory. A new backend creates the same shape -- chapter 9 builds Info,"
  say "Desc and the root; chapter 12 adds AsmParser."

  say ""
  say "2. THE LIST OF BACKENDS IS GENERATED AT CONFIGURE TIME."
  step "head -n 30 \$(llvm-config --includedir)/llvm/Config/Targets.def | tail -6"
  sed -n '/^LLVM_TARGET/p' "$TD_INC/llvm/Config/Targets.def" > out/targets_def.txt
  head -6 out/targets_def.txt | sed 's/^/  /'
  say "  ... $(wc -l < out/targets_def.txt | tr -d ' ') backends in this build"

  say ""
  say "3. THAT LIST IS EXPANDED INTO DECLARATIONS AND CALLS."
  step "sed -n '/extern \"C\"/,/^}/p' \$(llvm-config --includedir)/llvm/Support/TargetSelect.h"
  sed -n '/^extern "C" {/,/^}/p' "$TD_INC/llvm/Support/TargetSelect.h" \
    > out/targetselect.txt
  sed -n '1,7p' out/targetselect.txt | sed 's/^/  /'
  say "  ..."
  step "sed -n '/inline void InitializeAllTargetInfos/,/^  }/p' .../TargetSelect.h"
  sed -n '/inline void InitializeAllTargetInfos/,/^  }/p' \
    "$TD_INC/llvm/Support/TargetSelect.h" | grep -vE '^\s*///' | sed 's/^/  /'

  say ""
  say "So the chapter's claim is literally a macro. Your three functions are"
  say "declared and called by name, once per entry in Targets.def -- which is why"
  say "they must be extern \"C\": these are generated call sites, not C++ lookups."

  say ""
  say "There are $(grep -c 'inline void InitializeAll' "$TD_INC/llvm/Support/TargetSelect.h") such entry points, and a tool opts in to what it needs:"
  grep -oE 'inline void InitializeAll[A-Za-z]+' "$TD_INC/llvm/Support/TargetSelect.h" \
    | sed 's/inline void /    /' | sed 's/$/()/'

  say ""
  say "4. THE RESULT IS OBSERVABLE."
  step "$LLC --version | sed -n '/Registered Targets/,\$p'"
  "$LLC" --version | sed -n '/Registered Targets/,$p' > out/registered.txt
  grep -E '^\s+(aarch64|arm64)' out/registered.txt | sed 's/^/  /'
  local backends names
  backends=$(wc -l < out/targets_def.txt | tr -d ' ')
  names=$(grep -cE '^\s+[a-z0-9_]+ +-' out/registered.txt)
  say ""
  say "  $backends backends  ->  $names registered target names"
  say ""
  say "AArch64 alone accounts for five of them. One backend is NOT one Target:"
  say "LLVMInitializeAArch64TargetInfo constructs a RegisterTarget for each"
  say "Triple::ArchType it serves. That is why chapter 9 has you add an ArchType"
  say "entry as a separate step from creating the Target singleton -- the two are"
  say "many-to-one."

  if [ "$CHECK" = 1 ]; then
    assert "a backend is several libraries, one per subdirectory" \
      test "$(wc -l < out/components.txt)" -ge 5
    assert "the Info / Desc / CodeGen split exists" \
      grep -q '^aarch64desc$' out/components.txt
    assert "Targets.def is generated and lists the enabled backends" \
      grep -q 'LLVM_TARGET(AArch64)' out/targets_def.txt
    assert "TargetSelect.h declares the init functions via a macro over that list" \
      grep -q 'LLVMInitialize##TargetName##TargetInfo' out/targetselect.txt
    assert "InitializeAllTargetInfos expands the same list into calls" \
      grep -q 'LLVMInitialize##TargetName##TargetInfo();' \
        "$TD_INC/llvm/Support/TargetSelect.h"
    assert "more target names are registered than there are backends" \
      test "$names" -gt "$backends"
    assert "aarch64 registers several Target instances" \
      test "$(grep -cE '^\s+(aarch64|arm64)' out/registered.txt)" -ge 3
  fi
}

# ---------------------------------------------------------------------------
# 1. tti -- the same IR, eight answers, all from TargetTransformInfo
# ---------------------------------------------------------------------------
stage_tti() {
  banner "tti"
  say "Chapter 9's premise: generic middle-end passes ask the target for costs."
  say "ir/vec.ll is a plain float loop with nothing target-specific in it. Watch"
  say "what the vectorizer decides as we vary the three TargetMachine inputs the"
  say "chapter names -- the triple (TT), the CPU (CPU), and the feature string (FS)."

  : > out/tti.txt
  probe() {
    local label="$1"; shift
    local w
    w=$("$OPT" -passes=loop-vectorize "$@" ir/vec.ll -S -o - 2>/dev/null \
        | grep -oE '<[0-9]+ x float>|vscale x [0-9]+ x float' | sort -u | tr '\n' ' ')
    [ -z "$w" ] && w="(not vectorized)"
    printf '  %-38s %s\n' "$label" "$w" | tee -a out/tti.txt
  }

  step "$OPT -passes=loop-vectorize [flags] ir/vec.ll -S"
  printf '  %-38s %s\n' "FLAGS" "VECTOR TYPES PRODUCED"
  probe "(none)"
  probe "-mtriple=nvptx64"                        -mtriple=nvptx64
  probe "-mtriple=riscv64"                        -mtriple=riscv64
  probe "-mtriple=riscv64 -mattr=+v"              -mtriple=riscv64 -mattr=+v
  probe "-mtriple=x86_64"                         -mtriple=x86_64
  probe "-mtriple=x86_64 -mcpu=skylake-avx512"    -mtriple=x86_64 -mcpu=skylake-avx512
  probe "-mtriple=aarch64"                        -mtriple=aarch64
  probe "-mtriple=aarch64 -mattr=+sve"            -mtriple=aarch64 -mattr=+sve

  say ""
  say "Four distinct outcomes, from one input file:"
  say ""
  say "  no triple       nothing at all -- the default TTI reports no vector"
  say "                  registers, so vectorising is never profitable"
  say "  x86_64          <4 x float>  -- 128-bit SSE"
  say "  +avx512         <8 x float>  -- a wider register file, a wider factor"
  say "  +sve / +v       vscale x 4   -- SCALABLE vectors; the width is not even"
  say "                  a compile-time constant"
  say ""
  say "This is the whole argument for chapter 9. The pass is generic; the answer"
  say "is target-specific; TargetTransformInfo is the seam. And note the third"
  say "and fourth rows: triple alone is not enough -- CPU and feature string are"
  say "separate constructor arguments precisely because they change the answer."

  if [ "$CHECK" = 1 ]; then
    assert "no triple: TTI refuses to vectorize" \
      grep -q '(none).*(not vectorized)' out/tti.txt
    assert "x86_64 picks a 128-bit vector" \
      grep -q '^  -mtriple=x86_64  *<4 x float>' out/tti.txt
    assert "avx512 widens the vectorization factor" \
      grep -q 'skylake-avx512.*<8 x float>' out/tti.txt
    assert "sve produces a scalable vector instead" \
      grep -q '+sve.*vscale x 4 x float' out/tti.txt
    assert "a feature string alone changes the outcome on riscv64" \
      grep -q '+v.*vscale x 4 x float' out/tti.txt
  fi
}

# ---------------------------------------------------------------------------
# 2. intrinsics -- a target builtin, from C to LLVM IR
# ---------------------------------------------------------------------------
stage_intrinsics() {
  banner "intrinsics"
  if ! command -v "$CLANG" >/dev/null 2>&1; then
    say "skipped: '$CLANG' not on PATH (this is the only stage that needs clang)"
    return 0
  fi

  say "The chapter builds an intrinsic for its own backend. We cannot -- that"
  say "needs a rebuilt LLVM. But every step it describes is observable on a"
  say "target that already did it. AArch64's crc32b is the same shape as the"
  say "chapter's widening multiply: a TARGET_BUILTIN behind a feature string."

  say ""
  say "Step 1: the target has to be registered before clang will accept it."
  step "$CLANG --print-targets | grep aarch64"
  "$CLANG" --print-targets 2>&1 | grep -E '^\s+aarch64 ' | tee out/targets.txt

  say ""
  say "Step 2: TARGET_BUILTIN's FEATURE argument is enforced at the source level."
  step "$CLANG --target=aarch64-linux-gnu -O1 -S -emit-llvm c/builtin.c   # no +crc"
  "$CLANG" --target=aarch64-linux-gnu -O1 -S -emit-llvm c/builtin.c -o /dev/null \
    > out/nocrc.txt 2>&1
  grep -E "error:" out/nocrc.txt | head -2
  say "(that is the FEATURE string of TARGET_BUILTIN doing its job)"

  say ""
  say "Step 3: with the feature enabled, the builtin becomes an IR intrinsic."
  step "$CLANG --target=aarch64-linux-gnu -march=armv8-a+crc -O1 -S -emit-llvm c/builtin.c"
  "$CLANG" --target=aarch64-linux-gnu -march=armv8-a+crc -O1 -S -emit-llvm \
    c/builtin.c -o out/builtin.ll 2>/dev/null
  grep -E '^target (triple|datalayout)|^define|tail call|^declare' out/builtin.ll \
    | sed 's/^/  /'

  say ""
  say "Read that output against the chapter:"
  say ""
  say "  target datalayout / triple   what the clang::TargetInfo subclass"
  say "                               installed via resetDataLayout"
  say "  @widening_smul               no intrinsic -- plain C said it already."
  say "                               The chapter's own example of when NOT to"
  say "                               add one"
  say "  llvm.aarch64.crc32b          __builtin_arm_crc32b became an"
  say "                               IntrinsicInst, via the ClangBuiltin"
  say "                               TableGen class's one-to-one mapping"
  say "  declare ... memory(none)     the default intrinsic attributes"

  if [ "$CHECK" = 1 ]; then
    assert "aarch64 is a registered clang target" \
      grep -q 'aarch64' out/targets.txt
    assert "the builtin is rejected without its target feature" \
      grep -q "needs target feature crc" out/nocrc.txt
    assert "with the feature, the builtin lowers to an intrinsic call" \
      grep -q 'call i32 @llvm.aarch64.crc32b' out/builtin.ll
    assert "the widening multiply needed no intrinsic at all" \
      test "$(grep -c 'llvm\..*mul' out/builtin.ll)" -eq 0
  fi
}

# ---------------------------------------------------------------------------
# 3. inject -- a target-injected middle-end pass, and quiz 5
# ---------------------------------------------------------------------------
stage_inject() {
  banner "inject"
  say "Chapter 9 ends by injecting a target pass into the DEFAULT pipeline via"
  say "TargetMachine::registerPassBuilderCallbacks. AArch64 already does this,"
  say "so we can watch it happen -- and walk straight into quiz 5."

  step "$OPT -O1 -debug-pass-manager ir/vec.ll   # no -mtriple"
  "$OPT" -O1 -debug-pass-manager ir/vec.ll -S -o /dev/null 2>&1 \
    | grep -o 'Running pass: [A-Za-z0-9_<>]*' | sort -u > out/pipe_generic.txt
  say "  $(wc -l < out/pipe_generic.txt | tr -d ' ') distinct passes"

  step "$OPT -O1 -mtriple=aarch64 -debug-pass-manager ir/vec.ll"
  "$OPT" -O1 -mtriple=aarch64 -debug-pass-manager ir/vec.ll -S -o /dev/null 2>&1 \
    | grep -o 'Running pass: [A-Za-z0-9_<>]*' | sort -u > out/pipe_aarch64.txt
  say "  $(wc -l < out/pipe_aarch64.txt | tr -d ' ') distinct passes"

  say ""
  say "The difference:"
  diff out/pipe_generic.txt out/pipe_aarch64.txt | sed 's/^/  /' | tee out/pipe_diff.txt

  say ""
  say "That pass is not in any generic pipeline. It is registered by AArch64's"
  say "registerPassBuilderCallbacks and injected at an extension point, and it"
  say "appears ONLY because we passed -mtriple."
  say ""
  say "Which is quiz 5, verbatim: 'you injected a custom pass into the default"
  say "pipeline for your target, but it is not invoked with opt -O1. Why?'"
  say "Answer: opt builds the generic pipeline unless a triple sends it to"
  say "yours -- either -mtriple on the command line, or a target triple in the"
  say "input IR itself."

  if [ "$CHECK" = 1 ]; then
    assert "the generic -O1 pipeline runs a nonzero number of passes" \
      test "$(wc -l < out/pipe_generic.txt)" -gt 50
    assert "-mtriple=aarch64 injects a pass the generic pipeline lacks" \
      test -s out/pipe_diff.txt
    assert "the injected pass is AArch64's LoopIdiomVectorize" \
      grep -q 'LoopIdiomVectorizePass' out/pipe_diff.txt
    assert "it is absent without -mtriple" \
      test "$(grep -c 'LoopIdiomVectorizePass' out/pipe_generic.txt)" -eq 0
  fi
}

# ---------------------------------------------------------------------------
# 4. mir -- producing, shrinking, and re-running a .mir file
# ---------------------------------------------------------------------------
stage_mir() {
  banner "mir"
  say "Chapter 11's practical half: .mir is the textual Machine IR, it exists"
  say "for developers only, and the skill is keeping it small."

  step "$LLC -mtriple=aarch64 -stop-before=peephole-opt ir/loop.ll -o out/full.mir"
  "$LLC" -mtriple=aarch64 -stop-before=peephole-opt ir/loop.ll -o out/full.mir 2>&1
  say "  $(wc -l < out/full.mir | tr -d ' ') lines"

  step "$LLC -mtriple=aarch64 -stop-before=peephole-opt ir/loop.ll -simplify-mir -o out/simple.mir"
  "$LLC" -mtriple=aarch64 -stop-before=peephole-opt ir/loop.ll -simplify-mir \
    -o out/simple.mir 2>&1
  say "  $(wc -l < out/simple.mir | tr -d ' ') lines -- one flag, and the fields that"
  say "  hold default values or can be recomputed are gone"

  say ""
  say "The hand-shrunk version in ../exercises/01_read_the_mir/mir/shrunk.mir goes"
  say "further: no LLVM IR section, no registers/frameInfo/liveins fields, no"
  say "%ir- references. Only name and tracksRegLiveness are mandatory."
  local shrunk=../exercises/01_read_the_mir/mir/shrunk.mir
  grep -v '^#' "$shrunk" > out/shrunk_nocomment.mir
  say "  $(wc -l < out/shrunk_nocomment.mir | tr -d ' ') lines, not counting its explanatory header"

  say ""
  say "It still runs -- which is the test of whether the shrinking was legal:"
  step "$LLC -mtriple=aarch64 -run-pass=peephole-opt $shrunk -o out/roundtrip.mir"
  if "$LLC" -mtriple=aarch64 -run-pass=peephole-opt "$shrunk" \
       -o out/roundtrip.mir 2>out/roundtrip.err; then
    say "  ok -- $(wc -l < out/roundtrip.mir | tr -d ' ') lines back out"
  else
    head -3 out/roundtrip.err
  fi

  say ""
  say "Note what came back: the parser re-synthesised the LLVM IR section with"
  say "an empty function body. It only ever needed the symbol to parse, not the"
  say "semantics -- which is exactly the trick the chapter recommends when you"
  say "must keep a call but want the IR section gone."
  step "sed -n '1,6p' out/roundtrip.mir"
  sed -n '1,6p' out/roundtrip.mir | sed 's/^/  /'

  if [ "$CHECK" = 1 ]; then
    assert "-simplify-mir shrinks the dump substantially" \
      test "$(wc -l < out/simple.mir)" -lt "$(wc -l < out/full.mir)"
    assert "the hand-shrunk file is smaller still" \
      test "$(wc -l < out/shrunk_nocomment.mir)" -lt "$(wc -l < out/simple.mir)"
    assert "the hand-shrunk file has no LLVM IR section" \
      test "$(grep -c '^--- |' "$shrunk")" -eq 0
    assert "it still parses and runs a pass" \
      test -s out/roundtrip.mir
    assert "the parser re-synthesised an LLVM IR section" \
      grep -q '^--- |' out/roundtrip.mir
  fi
}

# ---------------------------------------------------------------------------
# 5. operands -- MachineOperand concepts, on real targets
# ---------------------------------------------------------------------------
stage_operands() {
  banner "operands"
  say "Chapter 11's conceptual half. A MachineInstr is a flat array of operands"
  say "plus an MCInstrDesc that says what that array must contain. The four"
  say "concepts hardest to picture are all visible in one x86 function."

  step "$LLC -mtriple=x86_64 -stop-after=finalize-isel ir/operands.ll -simplify-mir -o out/ops.mir"
  "$LLC" -mtriple=x86_64 -stop-after=finalize-isel ir/operands.ll -simplify-mir \
    -o out/ops.mir 2>&1
  sed -n '/^name: *sel/,/^\.\.\./p' out/ops.mir | mir_body | sed 's/^/  /'

  say ""
  say "  implicit-def \$eflags   SUB32rr writes the flags. The C source never"
  say "                         mentioned them; the hardware has no choice."
  say "  implicit \$eflags       CMOV32rr reads them back. This is the chapter's"
  say "                         own example, one register width down."
  say "  implicit-def dead      ADD32rr also writes flags -- and nobody reads"
  say "                         them, so they are marked dead."
  say ""
  say "Explicit definitions come first and print left of the '='. Implicit"
  say "operands come last and are spelled out. That ordering is guaranteed by"
  say "MCInstrDesc, which is why you can index the array at all."

  say ""
  say "The call is the other use of implicit operands -- not hardware, but ABI:"
  step "grep CALL64 out/ops.mir"
  grep 'CALL64' out/ops.mir | sed 's/^/  /' | fold -w 100 -s | sed 's/^\([^ ]\)/    \1/'
  say ""
  say "Two explicit operands (the symbol, and csr_64 -- a REGISTER MASK, the"
  say "compact 'these must survive the call' list). Everything else, including"
  say "the return value in \$eax, is implicit. The chapter's AArch64 BL example,"
  say "in x86 dialect."

  say ""
  say "TIED OPERANDS need a later pass. x86 arithmetic is two-address, and the"
  say "two-address pass is what introduces the constraint:"
  step "$LLC -mtriple=x86_64 -stop-after=twoaddressinstruction ir/operands.ll -simplify-mir"
  "$LLC" -mtriple=x86_64 -stop-after=twoaddressinstruction ir/operands.ll \
    -simplify-mir -o out/twoaddr.mir 2>&1
  sed -n '/^name: *sel/,/^\.\.\./p' out/twoaddr.mir | mir_body | grep -E 'CMOV|COPY killed %1' \
    | sed 's/^/  /'
  say ""
  say "  %4 = CMOV32rr %4, ...   the same register is operand 0 (def) and"
  say "                          operand 1 (use). That models 'a = cond ? a : b'."
  say ""
  say "And notice the cost: %4 is now defined TWICE in this function -- once by"
  say "the COPY, once by the CMOV. Tied operands are incompatible with SSA, which"
  say "is why this pass runs where it does in the pipeline, after PHI elimination."

  say ""
  say "EARLY-CLOBBER, finally, is one character of inline asm -- '=&r' vs '=r':"
  step "$LLC -mtriple=aarch64 -stop-after=finalize-isel ir/asm.ll -simplify-mir"
  "$LLC" -mtriple=aarch64 -stop-after=finalize-isel ir/asm.ll -simplify-mir \
    -o out/asm.mir 2>&1
  grep -oE 'regdef(-ec)?:GPR64common.*?, def (early-clobber )?%[0-9]+' out/asm.mir \
    | sed 's/^/  /'
  say ""
  say "'def early-clobber %2' tells the register allocator that %2 is written"
  say "before the inputs are read, so it must not share a register with them."
  say "Without it, the second instruction of that asm block would read a"
  say "clobbered operand."

  if [ "$CHECK" = 1 ]; then
    assert "the compare implicitly defines eflags" \
      grep -q 'SUB32rr.*implicit-def \$eflags' out/ops.mir
    assert "the conditional move implicitly uses eflags" \
      grep -q 'CMOV32rr.*implicit \$eflags' out/ops.mir
    assert "an unread flag definition is marked dead" \
      grep -q 'implicit-def dead \$eflags' out/ops.mir
    assert "the call carries a register mask" \
      grep -q 'CALL64pcrel32.*csr_64' out/ops.mir
    assert "the call's return register is an implicit def" \
      grep -q 'CALL64pcrel32.*implicit-def \$eax' out/ops.mir
    assert "two-address form ties the destination to an input" \
      grep -qE '%4:gr32 = CMOV32rr %4' out/twoaddr.mir
    assert "which breaks SSA: %4 is defined twice" \
      test "$(grep -cE '%4:gr32 = ' out/twoaddr.mir)" -eq 2
    assert "=&r produces an early-clobber definition" \
      grep -q 'def early-clobber' out/asm.mir
    assert "=r does not" \
      test "$(grep -c 'regdef:GPR64common' out/asm.mir)" -ge 1
  fi
}

# ---------------------------------------------------------------------------
# 6. registers -- register units, computed rather than described
# ---------------------------------------------------------------------------
stage_registers() {
  banner "registers"
  say "Chapter 11's register hierarchy (Figure 11.2) is in td/regunits.td: nine"
  say "registers in three irregular layers. The chapter claims five register"
  say "units suffice to describe all nine. That is checkable with no compiler."

  step "$TBLGEN -gen-register-info -I \$(llvm-config --includedir) td/regunits.td -o out/reg.inc"
  "$TBLGEN" -gen-register-info -I "$TD_INC" td/regunits.td -o out/reg.inc 2>&1 || return 1

  say ""
  say "The register units TableGen computed:"
  sed -n '/RegUnitRoots\[\]\[2\]/,/^};/p' out/regMCDesc.inc | sed 's/^/  /'

  say ""
  say "Five roots for nine registers -- the chapter's u0..u4. The saving is in"
  say "the overlap check: asking 'is q0 free?' means checking three units, not"
  say "walking d0, d1, s0, s1, s2. With register tuples and deeper hierarchies"
  say "that ratio is what keeps the register allocator's compile time sane."

  say ""
  say "The generated initialiser counts everything up:"
  grep -oE "InitMCRegisterInfo\([A-Za-z0-9]*RegDesc, [0-9]+.*RegUnitRoots, [0-9]+" \
    out/regMCDesc.inc | sed 's/, RA.*MCRegisterClasses/  ... classes/' | sed 's/^/  /'
  say ""
  say "  10 registers   our nine, plus the NoRegister sentinel at index 0"
  say "  7  classes     but we only DECLARED three"
  say "  5  units"

  say ""
  say "Those four extra register classes are the interesting part:"
  grep -oE "^  // [A-Za-z0-9_]+ Register Class" out/regMCDesc.inc \
    | sed 's|  // ||; s| Register Class||' | sed 's/^/    /'
  say ""
  say "TableGen synthesised DOUBLES_with_sub32_low and friends. Because the"
  say "hierarchy is irregular -- d2 has no singles under it -- 'a double' and"
  say "'a double you can take the low half of' are different constraints, and"
  say "instruction operands need to be able to say which one they mean. You did"
  say "not ask for these classes; the shape of your register file demanded them."

  if [ "$CHECK" = 1 ]; then
    assert "TableGen computed exactly 5 register units for 9 registers" \
      test "$(sed -n '/RegUnitRoots\[\]\[2\]/,/^};/p' out/regMCDesc.inc | grep -c 'Fig112::')" -eq 5
    assert "the units are the leaves s0,s1,s2 plus the uncovered d2,q2" \
      grep -q 'Fig112::d2' out/regMCDesc.inc
    assert "10 register descriptors (9 + NoRegister)" \
      grep -q 'InitMCRegisterInfo(Fig112RegDesc, 10,' out/regMCDesc.inc
    assert "more register classes exist than were declared" \
      test "$(grep -c '^  // [A-Za-z0-9_]* Register Class' out/regMCDesc.inc)" -gt 3
    assert "one of them is a synthesised sub-register-constrained class" \
      grep -q 'DOUBLES_with_sub32_low' out/regMCDesc.inc
  fi
}

# ---------------------------------------------------------------------------
# 7. encoding -- chapter 12, lightly: .td in, assembler out
# ---------------------------------------------------------------------------
stage_encoding() {
  banner "encoding"
  say "Chapter 12 adds two fields to the instruction records of chapter 11:"
  say "AsmString (the syntax) and Inst (the bits). td/tiny.td is a complete"
  say "16-bit target in 40 lines. Watch what TableGen does with it."

  step "$TBLGEN -gen-instr-info -I \$(llvm-config --includedir) td/tiny.td -o out/tiny_instr.inc"
  "$TBLGEN" -gen-instr-info -I "$TD_INC" td/tiny.td -o out/tiny_instr.inc 2>&1 || return 1
  say ""
  say "The MCInstrDesc table -- the 'contract' the chapter describes:"
  grep -E '// (ADD|SUB)$' out/tiny_instr.inc \
    | sed 's/(1ULL<<MCID::[A-Za-z]*)|*//g; s/  */ /g' | sed 's/^/  /'
  say "(fields 2 and 3 are NumOperands and NumDefs: 3 operands, 1 definition)"

  step "$TBLGEN -gen-emitter -I \$(llvm-config --includedir) td/tiny.td -o out/tiny_emitter.inc"
  "$TBLGEN" -gen-emitter -I "$TD_INC" td/tiny.td -o out/tiny_emitter.inc 2>&1 || return 1
  say ""
  say "And the encoder, written for us:"
  sed -n '/static const uint64_t InstBits/,/^  };/p' out/tiny_emitter.inc | sed 's/^/  /'
  # Two switches match 'case Tiny::ADD:' -- the encoder and getOperandBitOffset.
  # Only the first one is the encoder.
  awk '/case Tiny::ADD:/ {f=1} f {print} f && /break;/ {exit}' out/tiny_emitter.inc \
    | sed 's/^/  /'

  say ""
  say "Read that against the .td file:"
  say ""
  say "  let Inst{15-12} = opc;   ADD's opcode 0b0001 at bit 12  ->  4096"
  say "  let Inst{11-10} = dst;   becomes  Value |= (op & 0x3) << 10"
  say "  let Inst{9-8}   = src0;  becomes  Value |= (op & 0x3) << 8"
  say ""
  say "No C++ was written. The declarative bit positions ARE the encoder."

  say ""
  say "Now the same round trip on a real ISA, where the bits are verifiable:"
  step "$MC -triple=aarch64 --show-encoding --show-inst asm/add.s"
  "$MC" -triple=aarch64 --show-encoding --show-inst asm/add.s > out/mc.txt 2>&1
  sed 's/^/  /' out/mc.txt

  say ""
  say "Two things worth stopping on."
  say ""
  say "1. The MCInst has FOUR operands; the assembly wrote three. ADDWrs is the"
  say "   shifted-register form, and the shift amount is an operand with the"
  say "   value 0. The mnemonic hides it; MCInstrDesc does not."
  say ""
  say "2. The encoding decomposes exactly as the .td file says it should."
  say "   [0x20,0x00,0x02,0x0b] little-endian is the word 0x0b020020:"
  say ""
  python3 - <<'PY' | tee out/decode.txt
v = int.from_bytes(bytes([0x20, 0x00, 0x02, 0x0b]), 'little')
print(f"      0x{v:08x} = 0b{v:032b}")
for name, hi, lo, note in [
    ("sf",    31, 31, "0 = 32-bit operands, hence the W registers"),
    ("opcode", 30, 24, "ADD (shifted register)"),
    ("shift", 23, 22, "LSL"),
    ("Rm",    20, 16, "-> w2"),
    ("imm6",  15, 10, "shift amount = 0"),
    ("Rn",     9,  5, "-> w1"),
    ("Rd",     4,  0, "-> w0"),
]:
    x = (v >> lo) & ((1 << (hi - lo + 1)) - 1)
    print(f"      {name:7s}[{hi:2d}:{lo:2d}] = {x:<3d} 0b{x:0{hi-lo+1}b}".ljust(44) + note)
PY
  say ""
  say "Rd=0, Rn=1, Rm=2 -- exactly 'add w0, w1, w2'. AArch64's own .td file"
  say "wrote those bit ranges the same way tiny.td does."

  say ""
  say "The parser is the piece TableGen does NOT write for you, and you can"
  say "feel it: the diagnostics are hand-written, and they know the register"
  say "classes."
  step "$MC -triple=aarch64 asm/bad.s"
  "$MC" -triple=aarch64 asm/bad.s > out/mc_bad.txt 2>&1
  sed 's/^/  /' out/mc_bad.txt

  if [ "$CHECK" = 1 ]; then
    assert "gen-instr-info reports 3 operands and 1 def for ADD" \
      grep -qE '\{ [0-9]+,\s*3,\s*1,' out/tiny_instr.inc
    assert "gen-emitter placed ADD's opcode at bit 12 (0b0001 << 12 = 4096)" \
      grep -q 'UINT64_C(4096).*// ADD' out/tiny_emitter.inc
    assert "gen-emitter turned Inst{11-10} into a shift by 10" \
      grep -q 'Value |= (op & 0x3) << 10' out/tiny_emitter.inc
    assert "llvm-mc encoded add w0,w1,w2" \
      grep -q '0x20,0x00,0x02,0x0b' out/mc.txt
    assert "the MCInst carries a fourth, implicit-in-syntax operand" \
      grep -q 'MCOperand Imm:0' out/mc.txt
    assert "the decoded Rm field is register 2" \
      grep -qE 'Rm *\[20:16\] = 2' out/decode.txt
    assert "the parser rejects a wrong-width register" \
      grep -q 'error:' out/mc_bad.txt
  fi
}

# ---------------------------------------------------------------------------
# 8. pipeline -- chapter 13's three stages, and what enforces them
# ---------------------------------------------------------------------------
stage_pipeline() {
  banner "pipeline"
  say "Chapter 13: the Machine IR passes through three forms. Table 13.1 shows"
  say "them side by side. Here they are, produced rather than transcribed."

  local -a stops=(
    "peephole-opt:ssa:-stop-before"
    "phi-node-elimination:nophi:-stop-after"
    "virtregmap:physreg:-stop-after"
  )
  for s in "${stops[@]}"; do
    local pass="${s%%:*}" rest="${s#*:}"
    local tag="${rest%%:*}" flag="${rest#*:}"
    step "$LLC -mtriple=aarch64 $flag=$pass ir/loop.ll -simplify-mir -o out/$tag.mir"
    "$LLC" -mtriple=aarch64 "$flag=$pass" ir/loop.ll -simplify-mir \
      -o "out/$tag.mir" 2>&1 || return 1
  done

  say ""
  say "--- 1. SSA form, virtual registers (after instruction selection) ---"
  sed -n '/bb.1.loop/,/^  bb.2/p' out/ssa.mir | sed 's/^/  /'
  say ""
  say "--- 2. after PHI elimination: no PHI, still virtual registers ---"
  sed -n '/bb.1.loop/,/^  bb.2/p' out/nophi.mir | sed 's/^/  /'
  say ""
  say "--- 3. after register allocation: physical registers only ---"
  sed -n '/bb.1.loop/,/^  bb.2/p' out/physreg.mir | sed 's/^/  /'

  say ""
  say "The PHI became COPY instructions -- and those copies redefine the same"
  say "virtual register in two different blocks, so SSA is gone. The MIR header"
  say "records all three transitions as MachineFunctionProperties:"
  printf '\n  %-12s %-8s %-8s %s\n' "FILE" "isSSA" "noPhis" "noVRegs"
  for f in ssa nophi physreg; do
    printf '  %-12s %-8s %-8s %s\n' "$f.mir" \
      "$(grep -oE 'isSSA: *[a-z]+' out/$f.mir | awk '{print $2}')" \
      "$(grep -oE 'noPhis: *[a-z]+' out/$f.mir | awk '{print $2}')" \
      "$(grep -oE 'noVRegs: *[a-z]+' out/$f.mir | awk '{print $2}')"
  done

  say ""
  say "A pass declares which of these it needs via getRequiredProperties. The"
  say "chapter presents that as the way to find out where a pass may run. It is"
  say "worth knowing what happens if you get it wrong: machine-cp requires"
  say "NoVRegs, and a release build does not check."
  step "$LLC -mtriple=aarch64 -run-pass=machine-cp out/physreg.mir   # right stage"
  if "$LLC" -mtriple=aarch64 -run-pass=machine-cp out/physreg.mir -o /dev/null 2>&1; then
    say "  ok"
  fi
  step "$LLC -mtriple=aarch64 -run-pass=machine-cp out/ssa.mir       # wrong stage"
  # The crash is the point. Run it through a child shell so that shell, not
  # ours, prints the "Bus error" notice -- and send that notice to /dev/null.
  local rc=0
  bash -c "'$LLC' -mtriple=aarch64 -run-pass=machine-cp out/ssa.mir \
             -o /dev/null > out/wrongstage.txt 2>&1" 2>/dev/null || rc=$?
  grep -E "Stack dump|Running pass '|PLEASE submit" out/wrongstage.txt \
    | head -3 | sed 's/^/  /'
  say "  (exit status $rc -- a segfault, not a diagnostic)"
  say ""
  say "So the property system documents the pipeline; it does not defend it."
  say "Asserts would catch this in a debug build. In a release build, injecting"
  say "a pass at the wrong stage is a crash at best."

  say ""
  say "Finally, the whole pipeline of Figure 13.1, as the backend actually built"
  say "it -- generic and target passes interleaved:"
  step "$LLC -mtriple=aarch64 -O1 -debug-pass=Structure ir/loop.ll -o /dev/null"
  "$LLC" -mtriple=aarch64 -O1 -debug-pass=Structure ir/loop.ll -o /dev/null \
    > out/structure.txt 2>&1
  say ""
  say "The lowering backbone, in order, filtered out of that listing:"
  sed -n '/^Pass Arguments:/p' out/structure.txt | tr ' ' '\n' | grep -E \
    '^-(aarch64-isel|finalize-isel|phi-node-elimination|twoaddressinstruction|register-coalescer|machine-scheduler|virtregmap|greedy|virtregrewriter|prologepilog|postrapseudos|aarch64-asm-printer)$' \
    | sed 's/^-/    /' | tee out/backbone.txt
  say ""
  say "  aarch64-isel ......... LLVM IR ends here, Machine IR begins"
  say "  phi-node-elimination . SSA ends here"
  say "  greedy/virtregrewriter register allocation: virtual registers end here"
  say "  prologepilog ......... the stack frame appears"
  say "  aarch64-asm-printer .. Machine IR ends, MC begins"
  say ""
  say "$(grep -c 'aarch64' out/structure.txt >/dev/null && grep -o 'aarch64-[a-z0-9-]*' out/structure.txt | sort -u | wc -l | tr -d ' ') distinct aarch64-* passes appear in that listing. The default"
  say "pipeline is a backbone; the target fills it in through TargetPassConfig's"
  say "addXXX hooks -- which is why the chapter says not to override"
  say "addMachinePasses and lose them all."

  if [ "$CHECK" = 1 ]; then
    assert "stage 1 is in SSA form" grep -q 'isSSA: *true' out/ssa.mir
    assert "stage 1 still has a PHI" grep -q '= PHI ' out/ssa.mir
    assert "stage 2 has no PHI left" \
      test "$(grep -c '= PHI ' out/nophi.mir)" -eq 0
    assert "stage 2 is no longer SSA" grep -q 'isSSA: *false' out/nophi.mir
    assert "stage 2 still uses virtual registers" \
      grep -q 'noVRegs: *false' out/nophi.mir
    assert "stage 3 has no virtual registers" \
      grep -q 'noVRegs: *true' out/physreg.mir
    assert "stage 3 uses physical registers" \
      grep -q 'renamable \$x' out/physreg.mir
    assert "machine-cp crashes when run before register allocation" \
      test "$rc" -ne 0
    assert "the codegen pipeline listing shows PHI elimination before regalloc" \
      grep -q 'phi-node-elimination.*virtregmap' out/structure.txt
  fi
}

# --- dispatch --------------------------------------------------------------

run_stage() {
  case "$1" in
    bringup)    stage_bringup ;;
    tti)        stage_tti ;;
    intrinsics) stage_intrinsics ;;
    inject)     stage_inject ;;
    mir)        stage_mir ;;
    operands)   stage_operands ;;
    registers)  stage_registers ;;
    encoding)   stage_encoding ;;
    pipeline)   stage_pipeline ;;
    *) echo "error: unknown stage '$1'. Try --list." >&2; exit 2 ;;
  esac
}

case "${1:-}" in
  --list) printf '%s\n' "${STAGES[@]}"; exit 0 ;;
  --help|-h) sed -n '3,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  --check) CHECK=1; shift ;;
esac

say "using $(command -v "$OPT")  -- $("$OPT" --version | sed -n '2p' | sed 's/^ *//')"

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
