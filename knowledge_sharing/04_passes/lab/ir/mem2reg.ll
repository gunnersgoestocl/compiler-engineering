; Input for the `mem2reg` stage.
;
; Chapter 8 discusses mem2reg as one of its three canonicalization passes, but
; the upstream ch8/ directory has no input for it -- this fills that gap.
;
; @straight_line is the trivial case: one alloca, one store, one load.
;
; @needs_phi is the interesting one. The C-level variable `v` is assigned in two
; different blocks, so promoting it requires INSERTING A PHI -- which is exactly
; the "SSA values are not source variables: mem2reg can split one C local
; variable into several SSA values" point from session 2.

define i64 @straight_line(i64 %in) {
entry:
  %slot = alloca i64
  store i64 %in, ptr %slot
  %v = load i64, ptr %slot
  %res = add i64 %v, 2
  ret i64 %res
}

define i64 @needs_phi(i1 %flag, i64 %x) {
entry:
  %slot = alloca i64
  br i1 %flag, label %then, label %else

then:
  store i64 %x, ptr %slot
  br label %merge

else:
  store i64 0, ptr %slot
  br label %merge

merge:
  %v = load i64, ptr %slot
  %res = add i64 %v, 1
  ret i64 %res
}

; An alloca whose ADDRESS escapes cannot be promoted: @sink may store it
; somewhere, so the memory location has to stay real. mem2reg leaves this alone.
declare void @sink(ptr)

define i64 @escapes(i64 %in) {
entry:
  %slot = alloca i64
  store i64 %in, ptr %slot
  call void @sink(ptr %slot)
  %v = load i64, ptr %slot
  ret i64 %v
}
