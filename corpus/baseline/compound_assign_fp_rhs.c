// @category: baseline
// #425 B2 (review v2 M12-A1 probes p01/p02): compound assignment must not
// pre-collapse the rhs to the left type. C11 6.5.16.2p3: E1 op= E2 is
// E1 = (T)(E1 op E2) with usual arithmetic conversions INSIDE the op.
// Old shape collapsed rhs first: x *= 0.5 == x *= (int)0.5 == 0, and
// x /= 0.5 hit a FALSE divide-by-zero teaching trap. Truth: `3 2 12 6`.
#include <stdio.h>
int main() {
    int a = 7;  a *= 0.5;     /* C: 3  (7*0.5=3.5 -> 3) */
    int c = 5;  c -= 2.5;     /* C: 2  (5-2.5=2.5 -> 2) */
    unsigned u = 5; u *= 2.5; /* C: 12 (5*2.5=12.5 -> 12) */
    int x = 3;
    x /= 0.5;                 /* C: 6  (3/0.5=6.0 -> 6) */
    printf("%d %d %u %d\n", a, c, u, x);
    return 0;
}
