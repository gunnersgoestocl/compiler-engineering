; Input for case D of exercise 2.
;
; Pretend a target-specific pass of yours produced this deliberately, because
; your target has add and negate instructions but no subtract. This is the
; chapter's own example of a *valid but non-canonical* representation:
;
;   canonical:      %a = sub i64 %b, %c
;   what we want:   %neg_c = sub i64 0, %c
;                   %a = add i64 %b, %neg_c
;
; Both mean `b - c`. LLVM's canonical form is the first one. Run instcombine and
; see what happens to your careful work.

define i64 @target_prefers_add_and_negate(i64 %b, i64 %c) {
  %neg_c = sub i64 0, %c
  %a = add i64 %b, %neg_c
  ret i64 %a
}
