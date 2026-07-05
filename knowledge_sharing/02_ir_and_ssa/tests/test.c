#include <stdint.h>

struct Pair {
  char tag;
  int64_t value;
};

int branch_and_phi(int x, int flag) {
  int y;
  if (flag) {
    y = 40 + 2;
  } else {
    y = 8 * 2;
  }
  return y + x;
}

int layout_sensitive(struct Pair *p) {
  return (int)p->value;
}

int keeps_poison_case(void) {
  volatile int max = 2147483647;
  return max + 1;
}

extern void someFct(void);

/* The cycle between the loop body and the "skip" label has two entries
 * from outside the loop (the fallthrough into the body, and the goto).
 * No single block dominates the whole loop, so this CFG is irreducible;
 * see @irreducible_loop in tests/test.ll for the corresponding IR. */
int irreducible_loop(int shouldSkip1stCall) {
  int i = 0;
  if (shouldSkip1stCall)
    goto skip;
  do {
    someFct();
  skip:;
  } while (++i < 6);
  return 32;
}

struct Point {
  int32_t x;
  int32_t y;
};

int named_struct_and_array(struct Point *pts) {
  int arr[4];
  arr[2] = 7;
  return pts[1].y + arr[2];
}

typedef int v4si __attribute__((vector_size(16)));

v4si vector_add(v4si a, v4si b) { return a + b; }
