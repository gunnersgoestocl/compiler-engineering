; Input for the `pass-order` stage -- the same input as ch8/indvars.ll.
;
; `indvars` hoists the whole induction-variable chain out of the loop and leaves
; behind `br i1 false`. Quiz 4 of the chapter asks which pass cleans that up.
; The answer is `simplifycfg`, and chaining the two is where the new pass
; manager's scoping rule bites.

define i64 @foo(i64 %src, i64 %ub) {
entry:
  br label %loop

loop:
  %iv = phi i64 [0, %entry], [%iv1, %loop]
  %iv1 = add i64 %iv, 1
  %cond = icmp ult i64 %iv1, %ub
  br i1 %cond, label %loop, label %end

end:
  %tmp = add i64 %iv1, %src
  %res = add i64 %tmp, %iv1
  ret i64 %res
}
