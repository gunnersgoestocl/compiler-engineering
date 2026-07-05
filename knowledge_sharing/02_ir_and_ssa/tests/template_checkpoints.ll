; Staged checkpoints for filling in template/IRAndSSALabPass.cpp.
;
; Do exercises/01_const_fold_standalone FIRST. It isolates the constant-fold
; -with-legality problem (Step 4 below) with no RPO/dominance/printing to
; worry about, so by the time you get here that part is a port, not new
; material.
;
; These checkpoints assume you are implementing printFunctionIRFacts one
; piece at a time while foldConstantBinaryOperators is still a TODO stub
; (returns false, does not touch the IR). That is why %a/%b below are still
; real add/mul instructions, not folded constants -- folding is Step 4.
;
; STEP1 (function/block enumeration only -- name, arg count, block count;
; no RPO, no per-block dominance, no per-instruction detail yet):
;   opt -load-pass-plugin=build/IRAndSSALabPassTemplate.dylib \
;     -passes="ir-ssa-lab" -disable-output tests/template_checkpoints.ll 2>&1 \
;     | FileCheck tests/template_checkpoints.ll --check-prefix=STEP1
;
; STEP2 (add the RPO walk and per-block preds/succs/idom):
;   opt -load-pass-plugin=build/IRAndSSALabPassTemplate.dylib \
;     -passes="ir-ssa-lab" -disable-output tests/template_checkpoints.ll 2>&1 \
;     | FileCheck tests/template_checkpoints.ll --check-prefix=STEP2
;
; STEP3 (add per-instruction opcode/type/operands/users/phi-incoming --
; this completes printFunctionIRFacts):
;   opt -load-pass-plugin=build/IRAndSSALabPassTemplate.dylib \
;     -passes="ir-ssa-lab" -disable-output tests/template_checkpoints.ll 2>&1 \
;     | FileCheck tests/template_checkpoints.ll --check-prefix=STEP3
;
; Step 4 (evaluateConstantBinaryOp + foldConstantBinaryOperators) has no
; checkpoint in this file, because once folding works %a/%b stop being real
; instructions and the checks above would need to describe a different IR.
; Once Step 3 passes, move on to Step 4 and switch to the real acceptance
; test, tests/test.ll (the TRACE/IR check-prefixes), which describes the
; POST-fold behavior:
;   opt -load-pass-plugin=build/IRAndSSALabPassTemplate.dylib \
;     -passes="ir-ssa-lab" -disable-output tests/test.ll 2>&1 \
;     | FileCheck tests/test.ll --check-prefix=TRACE
;   opt -load-pass-plugin=build/IRAndSSALabPassTemplate.dylib \
;     -passes="ir-ssa-lab" -S tests/test.ll 2>/dev/null \
;     | FileCheck tests/test.ll --check-prefix=IR

target triple = "x86_64-unknown-linux-gnu"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"

define i32 @branch_and_phi(i32 %x, i1 %flag) {
; STEP1-LABEL: [Function] @branch_and_phi args=2 blocks=4

; STEP2: [CFG-RPO] %entry
; STEP2-SAME: %merge
; STEP2: [Block] %merge preds=2 succs=0 idom=%entry

; STEP3-LABEL: [Function] @branch_and_phi args=2 blocks=4
; STEP3: [CFG-RPO] %entry
; STEP3-SAME: %merge
; STEP3: [Block] %merge preds=2 succs=0 idom=%entry
; STEP3: [Inst] %y opcode=phi type=i32
; STEP3: phi-incoming: [%a from %then] [%b from %else]
; STEP3: [Inst] %z opcode=add type=i32
entry:
  br i1 %flag, label %then, label %else

then:
  %a = add nsw i32 40, 2
  br label %merge

else:
  %b = mul nsw i32 8, 2
  br label %merge

merge:
  %y = phi i32 [ %a, %then ], [ %b, %else ]
  %z = add nsw i32 %y, %x
  ret i32 %z
}
