/* widening_smul: the chapter 9 motivating example. The multiply is expressible
   in plain C -- both inputs promote to int -- so it needs no intrinsic at all.
   That is the chapter's own point about when NOT to add one.

   crc: a real target-specific builtin from an upstream backend, gated behind a
   target feature. Compiling without +crc is an error; with it, the builtin
   becomes an LLVM IR intrinsic. */
int widening_smul(short a, short b) { return a * b; }

unsigned crc(unsigned c, unsigned char b) { return __builtin_arm_crc32b(c, b); }
