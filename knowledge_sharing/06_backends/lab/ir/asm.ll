; Two inline assembly statements that differ in one character: "=&r" vs "=r".
; The & is the source-level spelling of the early-clobber constraint.
define i64 @early_clobber(i64 %b, i64 %c) {
  %r = call i64 asm "mov $0, $1\0Aadd $0, $0, $2", "=&r,r,r"(i64 %b, i64 %c)
  ret i64 %r
}

define i64 @no_early_clobber(i64 %b, i64 %c) {
  %r = call i64 asm "add $0, $1, $2", "=r,r,r"(i64 %b, i64 %c)
  ret i64 %r
}
