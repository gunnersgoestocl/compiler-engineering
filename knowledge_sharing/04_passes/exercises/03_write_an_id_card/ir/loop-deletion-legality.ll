; The legality half of cards/loop-deletion.md.
;
;   opt -passes='loop-deletion' ir/loop-deletion-legality.ll -S
;
; Both functions have IDENTICAL bodies. The only difference is the mustprogress
; attribute on the second one, and that difference decides whether the loop may
; be deleted.
;
; %iv starts at 0 and %iv1 = %iv * 3 keeps it at 0, so if 0 < %n this loop never
; exits. ScalarEvolution cannot bound the trip count, and non-termination is
; observable behaviour -- so deleting it would change what the program does.
;
; `mustprogress` is the promise C and C++ make that a side-effect-free loop
; terminates. With it, looping forever is undefined behaviour, so the pass is
; free to assume it does not happen.

define void @unprovable(i64 %n) {
entry:
  br label %loop

loop:
  %iv  = phi i64 [ 0, %entry ], [ %iv1, %loop ]
  %iv1 = mul i64 %iv, 3
  %c   = icmp ult i64 %iv1, %n
  br i1 %c, label %loop, label %end

end:
  ret void
}

define void @unprovable_mp(i64 %n) mustprogress {
entry:
  br label %loop

loop:
  %iv  = phi i64 [ 0, %entry ], [ %iv1, %loop ]
  %iv1 = mul i64 %iv, 3
  %c   = icmp ult i64 %iv1, %n
  br i1 %c, label %loop, label %end

end:
  ret void
}
