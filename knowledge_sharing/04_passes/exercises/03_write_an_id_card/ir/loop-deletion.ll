; Input for the worked example card, cards/loop-deletion.md.
;
;   opt -passes='loop-deletion' ir/loop-deletion.ll -S

; No side effects, nothing live-out, provably finite -> deleted.
define void @dead_loop(i64 %ub) {
entry:
  br label %loop

loop:
  %iv  = phi i64 [ 0, %entry ], [ %iv1, %loop ]
  %iv1 = add nuw nsw i64 %iv, 1
  %c   = icmp ult i64 %iv1, %ub
  br i1 %c, label %loop, label %end

end:
  ret void
}

; Identical, except for the store. Stores are observable -> kept.
define void @has_side_effect(i64 %ub, ptr %p) mustprogress {
entry:
  br label %loop

loop:
  %iv  = phi i64 [ 0, %entry ], [ %iv1, %loop ]
  %iv1 = add i64 %iv, 1
  store i64 %iv, ptr %p
  %c   = icmp ult i64 %iv1, %ub
  br i1 %c, label %loop, label %end

end:
  ret void
}
