// @category: baseline
// #424 B1 boundary matrix: global/static char initialisation must write
// exactly the declared width. Each line is either a shape the old 4-byte
// store got WRONG (L1/L2/L3/L6 — negative byte sign-extends to 0xFFFFFFFF and
// spills into neighbours that have no init record to overwrite it) or an
// INVARIANT lock (L4/L5/L7 — a non-char neighbour with an init that shares the
// merged word must still win, i.e. the merged char word is loaded first and
// later 32/64-bit init records overlay it).
#include <stdio.h>
/* L1: char scalar -1 followed by an uninitialised char. */
char c1 = -1;
char c1n;
/* L2: designated char array at [0] = -1 -> elements 1..3 must stay 0. */
char d2[4] = {[0] = -1};
/* L3: struct with two leading char members, only the first initialised;
   the trailing int gets no element either (static zero). */
struct Q { char b; char c; int a; };
struct Q q3 = {-1};
/* L4: invariant — char then packed int sharing the same 4-byte word. */
char c4 = 5;
int i4 = 287454020; /* 0x11223344 */
/* L5: invariant — string whose tail word straddles into a packed int. */
char s5[6] = "Hello";
int s5n = 168496141; /* 0x0A0B0C0D */
int main(void) {
  printf("L1 %d %d\n", c1, c1n);
  printf("L2 %d %d %d %d\n", d2[0], d2[1], d2[2], d2[3]);
  printf("L3 %d %d %d\n", q3.b, q3.c, q3.a);
  printf("L4 %d %d\n", c4, i4);
  printf("L5 %s %d\n", s5, s5n);
  /* L6: static locals — scalar -2 then uninitialised, designated [0] = -1. */
  static char sc = -2;
  static char scn;
  static char sa[3] = {[0] = -1};
  printf("L6 %d %d %d %d %d\n", sc, scn, sa[0], sa[1], sa[2]);
  /* L7: invariant — static string then packed static int. */
  static char ss[5] = "ab";
  static int si = 84281096; /* 0x05060708 */
  printf("L7 %s %d\n", ss, si);
  return 0;
}
