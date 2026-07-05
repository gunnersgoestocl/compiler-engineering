; Example of the kind of unoptimized IR produced by:
; clang -S -emit-llvm -O0 -Xclang -disable-O0-optnone tests/test.c -o tests/test_o0.ll
;
; This file is intentionally not the main FileCheck test. At plain -O0, clang
; keeps source variables in allocas, so a scalar SSA lab is easiest to observe
; after mem2reg/SROA or on the reduced SSA test in test.ll.

target triple = "x86_64-unknown-linux-gnu"

%struct.Pair = type { i8, i64 }

define i32 @branch_and_phi(i32 %x, i32 %flag) {
entry:
  %x.addr = alloca i32, align 4
  %flag.addr = alloca i32, align 4
  %y = alloca i32, align 4
  store i32 %x, ptr %x.addr, align 4
  store i32 %flag, ptr %flag.addr, align 4
  %0 = load i32, ptr %flag.addr, align 4
  %tobool = icmp ne i32 %0, 0
  br i1 %tobool, label %if.then, label %if.else

if.then:
  store i32 42, ptr %y, align 4
  br label %if.end

if.else:
  store i32 16, ptr %y, align 4
  br label %if.end

if.end:
  %1 = load i32, ptr %y, align 4
  %2 = load i32, ptr %x.addr, align 4
  %add = add nsw i32 %1, %2
  ret i32 %add
}

define i32 @layout_sensitive(ptr %p) {
entry:
  %p.addr = alloca ptr, align 8
  store ptr %p, ptr %p.addr, align 8
  %0 = load ptr, ptr %p.addr, align 8
  %value = getelementptr inbounds %struct.Pair, ptr %0, i32 0, i32 1
  %1 = load i64, ptr %value, align 8
  %conv = trunc i64 %1 to i32
  ret i32 %conv
}

