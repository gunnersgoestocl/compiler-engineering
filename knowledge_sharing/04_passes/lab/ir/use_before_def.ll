; Input for the `verify` stage.
;
; `%a` is defined in %then, but used in %merge. %then does NOT dominate %merge
; (the entry -> merge edge never visits %then), so this violates the SSA
; property that a definition must dominate all of its uses.
;
; This is the exact rule session 2 introduced on the "Dominance" slide. Here we
; see what the verifier says when it is broken.

define i64 @use_before_def(i1 %flag) {
entry:
  br i1 %flag, label %then, label %merge

then:
  %a = add i64 1, 2
  br label %merge

merge:
  %res = add i64 %a, 3
  ret i64 %res
}

; Note on what is NOT in this file.
;
; The chapter's other verifier example is "the input arguments of a fadd are
; both of the same type". You cannot demonstrate that from a .ll file:
;
;   %bad = add i64 %x, %y     ; with %y declared i32
;
; is rejected by the *parser* ("'%y' defined with type 'i32' but expected
; 'i64'") before the verifier ever runs. The textual parser enforces typing on
; the way in.
;
; That is the useful distinction: the verifier exists to catch what a *pass*
; can construct in memory, not what you can type in a file. Type mismatches are
; unrepresentable in text but perfectly constructible with IRBuilder -- which is
; exactly the situation the verifier is for. See ir/type_mismatch.md.
