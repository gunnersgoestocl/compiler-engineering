; RUN: opt -load-pass-plugin=%shlibdir/IRAndSSALabPass%shlibext -passes="ir-ssa-lab" -disable-output %s 2>&1 | FileCheck %s --check-prefix=TRACE
; RUN: opt -load-pass-plugin=%shlibdir/IRAndSSALabPass%shlibext -passes="ir-ssa-lab" -S %s 2>/dev/null | FileCheck %s --check-prefix=IR

target triple = "x86_64-unknown-linux-gnu"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"

%struct.Point = type { i32, i32 }

declare void @someFct()

define i32 @branch_and_phi(i32 %x, i1 %flag) {
; TRACE-LABEL: [Function] @branch_and_phi args=2 blocks=4
; TRACE: [CFG-RPO] %entry
; TRACE-SAME: %merge
; TRACE: [Block] %merge preds=2 succs=0
; TRACE: opcode=phi type=i32
; TRACE: phi-incoming: [42 from %then] [16 from %else]
; TRACE: [Inst] %z opcode=add type=i32
; IR-LABEL: define i32 @branch_and_phi(
; IR: then:
; IR-NEXT: br label %merge
; IR: else:
; IR-NEXT: br label %merge
; IR: merge:
; IR-NEXT: %y = phi i32 [ 42, %then ], [ 16, %else ]
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

define i32 @layout_sensitive(ptr %p) {
; TRACE-LABEL: [Function] @layout_sensitive args=1 blocks=1
; TRACE: opcode=getelementptr
; IR-LABEL: define i32 @layout_sensitive(
; IR: getelementptr inbounds { i8, i64 }, ptr %p, i32 0, i32 1
entry:
  %field = getelementptr inbounds { i8, i64 }, ptr %p, i32 0, i32 1
  %loaded = load i64, ptr %field, align 8
  %trunc = trunc i64 %loaded to i32
  ret i32 %trunc
}

define i32 @keeps_poison_case() {
; TRACE-LABEL: [Function] @keeps_poison_case args=0 blocks=1
; IR-LABEL: define i32 @keeps_poison_case()
; IR: %bad = add nsw i32 2147483647, 1
entry:
  %bad = add nsw i32 2147483647, 1
  ret i32 %bad
}

; This is the IR shape clang produces for:
;   int irreducible_loop(int shouldSkip1stCall) {
;     int i = 0;
;     if (shouldSkip1stCall) goto skip;
;     do {
;       someFct();
;       skip:;
;     } while (++i < 6);
;     return 32;
;   }
;
; The cycle {do_body, skip} has two distinct entries from outside the
; cycle: entry->do_body and entry->skip. No single block dominates the
; whole loop, so neither block is a natural loop header: this CFG is
; irreducible.
define i32 @irreducible_loop(i32 %shouldSkip1stCall) {
; TRACE-LABEL: [Function] @irreducible_loop args=1 blocks=4
; TRACE: [CFG-RPO] %entry %do_body %skip %do_end
; TRACE: [Block] %do_body preds=2 succs=1 idom=%entry
; TRACE: [Block] %skip preds=2 succs=2 idom=%entry
; IR-LABEL: define i32 @irreducible_loop(
; IR: do_body:
; IR-NEXT: %i0 = phi i32 [ %inc, %skip ], [ 0, %entry ]
entry:
  %skip_first = icmp eq i32 %shouldSkip1stCall, 0
  br i1 %skip_first, label %do_body, label %skip

do_body:
  %i0 = phi i32 [ %inc, %skip ], [ 0, %entry ]
  call void @someFct()
  br label %skip

skip:
  %i1 = phi i32 [ 0, %entry ], [ %i0, %do_body ]
  %inc = add nsw i32 %i1, 1
  %cont = icmp slt i32 %i1, 6
  br i1 %cont, label %do_body, label %do_end

do_end:
  ret i32 32
}

; Named struct type plus array-typed alloca, contrasted with the
; anonymous struct type used in layout_sensitive above.
define i32 @named_struct_and_array(ptr %pts) {
; TRACE-LABEL: [Function] @named_struct_and_array args=1 blocks=1
; TRACE: [Inst] %slot opcode=getelementptr type=ptr
; TRACE: [Inst] %field opcode=getelementptr type=ptr
; IR-LABEL: define i32 @named_struct_and_array(
; IR: getelementptr inbounds [4 x i32], ptr %arr, i64 0, i64 2
; IR: getelementptr inbounds %struct.Point, ptr %pts, i64 1, i32 1
entry:
  %arr = alloca [4 x i32], align 16
  %slot = getelementptr inbounds [4 x i32], ptr %arr, i64 0, i64 2
  store i32 7, ptr %slot, align 4
  %field = getelementptr inbounds %struct.Point, ptr %pts, i64 1, i32 1
  %y = load i32, ptr %field, align 4
  %fromarray = load i32, ptr %slot, align 4
  %sum = add nsw i32 %y, %fromarray
  ret i32 %sum
}

; Vector type: a single instruction operates on all four lanes at once.
define <4 x i32> @vector_add(<4 x i32> %a, <4 x i32> %b) {
; TRACE-LABEL: [Function] @vector_add args=2 blocks=1
; TRACE: [Inst] %sum opcode=add type=<4 x i32>
; IR-LABEL: define <4 x i32> @vector_add(
; IR: %sum = add <4 x i32> %a, %b
entry:
  %sum = add <4 x i32> %a, %b
  ret <4 x i32> %sum
}
