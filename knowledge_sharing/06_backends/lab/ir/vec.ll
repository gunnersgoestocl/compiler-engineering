; A vectorizable loop with nothing target-specific in it. Every decision the
; vectorizer makes about it comes from TargetTransformInfo, so the SAME input
; produces different IR for every -mtriple / -mcpu / -mattr combination.
define void @saxpy(ptr noalias %a, ptr noalias %b, i64 %n) {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i.next, %loop ]
  %pa = getelementptr inbounds float, ptr %a, i64 %i
  %pb = getelementptr inbounds float, ptr %b, i64 %i
  %va = load float, ptr %pa, align 4
  %vb = load float, ptr %pb, align 4
  %sum = fadd float %va, %vb
  store float %sum, ptr %pa, align 4
  %i.next = add nuw nsw i64 %i, 1
  %done = icmp eq i64 %i.next, %n
  br i1 %done, label %exit, label %loop
exit:
  ret void
}
