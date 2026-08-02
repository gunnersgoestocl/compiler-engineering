; Inputs for cases A and C of exercise 2.

; --- Case A ----------------------------------------------------------------
; The multiply is dead, but only *through memory*: its result is stored into a
; slot that is never loaded.
;
;   dce     cannot remove %v      (the store uses it)
;   dce     cannot remove the store (stores have side effects)
;   mem2reg removes the alloca and the store, which leaves %v with no users
;
; So the order decides whether anything at all is cleaned up.
define void @dead_through_memory(i64 %in) {
entry:
  %slot = alloca i64
  %v = mul i64 %in, 3
  store i64 %v, ptr %slot
  ret void
}

; --- Case C1 ---------------------------------------------------------------
; A long add chain with constants scattered through it. instcombine's local
; pattern matching does not reach across this chain; reassociate's rank-based
; reordering collects 1+2+3+4+5 into a single constant.
define i64 @chain(i64 %a, i64 %b, i64 %c, i64 %d, i64 %e) {
  %t1 = add i64 %a, 1
  %t2 = add i64 %t1, %b
  %t3 = add i64 %t2, 2
  %t4 = add i64 %t3, %c
  %t5 = add i64 %t4, 3
  %t6 = add i64 %t5, %d
  %t7 = add i64 %t6, 4
  %t8 = add i64 %t7, %e
  %t9 = add i64 %t8, 5
  ret i64 %t9
}

; --- Case C2 ---------------------------------------------------------------
; (a+b)+c and (b+c)+a are the same value written two different ways. The
; chapter says reassociate works "by exposing common subexpression
; elimination". This function is where you can watch it do exactly that -- and
; watch it stop short of actually eliminating anything.
define i64 @cse_exposed(i64 %a, i64 %b, i64 %c) {
  %x1 = add i64 %a, %b
  %x2 = add i64 %x1, %c
  %y1 = add i64 %b, %c
  %y2 = add i64 %y1, %a
  %r  = mul i64 %x2, %y2
  ret i64 %r
}
