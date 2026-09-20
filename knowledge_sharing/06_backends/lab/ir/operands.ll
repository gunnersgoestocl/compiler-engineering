; @sel lowers to a compare + conditional move, which on x86 communicates
; through the eflags register -- an operand the source never mentions.
; @caller lowers to a call, which carries the ABI as implicit operands
; plus a register mask.
declare i32 @bar(i32)

define i32 @sel(i32 %a, i32 %b, i32 %c) {
  %cmp = icmp sgt i32 %a, %b
  %s = select i1 %cmp, i32 %a, i32 %b
  %r = add i32 %s, %c
  ret i32 %r
}

define i32 @caller(i32 %x) {
  %r = call i32 @bar(i32 %x)
  ret i32 %r
}
