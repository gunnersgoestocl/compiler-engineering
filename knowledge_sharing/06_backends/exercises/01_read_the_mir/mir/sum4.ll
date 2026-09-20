declare void @sink(i64)
define i64 @sum4(i64 %a, i64 %b, i64 %c, i64 %d) {
  %x = add i64 %a, %b
  %y = add i64 %c, %d
  %z = add i64 %x, %y
  call void @sink(i64 %z)
  ret i64 %z
}
