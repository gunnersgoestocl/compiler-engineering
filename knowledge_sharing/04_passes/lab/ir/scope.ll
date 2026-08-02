; Input for the `scope-trap` stage.
;
; Deliberately boring: one dead instruction, one unused internal function. The
; point of this stage is not the transformation, it is which PIPELINE STRINGS
; opt accepts.
;
;   dce        -> Function pass
;   globaldce  -> Module pass
;
; So `-passes='dce,globaldce'` fails: naming `dce` first fixes the scope to
; function, and there is no function pass called `globaldce`.

define i64 @foo(i64 %in) {
  %dead = add i64 %in, %in
  %res = mul i64 %in, 2
  ret i64 %res
}

define internal i64 @never_called(i64 %in) {
  %res = add i64 %in, 1
  ret i64 %res
}
