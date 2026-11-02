// @category: baseline
// #424 B1 (review v2 M12-A4 probe p07): nested struct assignment inside a
// call argument. gen_struct_copy stored the outer dst address in the fixed
// temp slot 1 *before* evaluating the right side; the inner `b = c` reused
// the same slot and the outer copy wrote into b instead of a. Truth `7 8 7`,
// old output `1 2 7` (a untouched).
#include <stdio.h>
struct S { int x; int y; };
struct S id(struct S v) { return v; }
int main() {
    struct S a, b, c;
    c.x = 7; c.y = 8;
    a.x = 1; a.y = 2;
    a = id(b = c);
    printf("%d %d %d\n", a.x, a.y, b.x);
    return 0;
}
