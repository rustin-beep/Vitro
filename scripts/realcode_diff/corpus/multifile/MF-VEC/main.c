#include <stdio.h>
#include <math.h>
#include "vec.h"

static void show(const char *label, Vec2 v)
{
    printf("%-16s = (%9.4f, %9.4f)\n", label, v.x, v.y);
}

int main(void)
{
    Vec2 a;
    Vec2 b;
    Vec2 zero;
    Vec2 n;
    Vec2 r;
    Vec2 p;
    Vec2 q;
    double err_len;
    double err_perp;
    double err_dot;

    a.x = 3.0;
    a.y = 4.0;
    b.x = 1.0;
    b.y = 2.0;
    zero.x = 0.0;
    zero.y = 0.0;

    printf("=== demo ===\n");
    show("add", vec_add(a, b));
    show("sub", vec_sub(a, b));
    show("scale(2.5)", vec_scale(a, 2.5));
    printf("%-16s = %9.4f\n", "dot", vec_dot(a, b));
    printf("%-16s = %9.4f\n", "cross", vec_cross(a, b));
    printf("%-16s = %9.4f\n", "len", vec_len(a));
    printf("%-16s = %9.4f\n", "distance", vec_distance(a, b));
    show("normalize", vec_normalize(a));
    show("normalize(zero)", vec_normalize(zero));
    show("rotate(1)", vec_rotate(a, 1));
    show("rotate(2)", vec_rotate(a, 2));
    show("rotate(-1)", vec_rotate(a, -1));
    show("lerp(0.25)", vec_lerp(a, b, 0.25));

    printf("=== checks ===\n");
    n = vec_normalize(a);
    err_len = fabs(vec_len(n) - 1.0);
    r = vec_rotate(a, 1);
    err_perp = fabs(vec_dot(r, a));

    p.x = 2.0;
    p.y = 0.0;
    q.x = 0.0;
    q.y = 3.0;
    err_dot = fabs(vec_dot(p, q));

    printf("normalize_is_unit   = %s\n", (err_len < 1e-9) ? "yes" : "no");
    printf("rotate90_perp       = %s\n", (err_perp < 1e-9) ? "yes" : "no");
    printf("orthogonal_dot_zero = %s\n", (err_dot < 1e-9) ? "yes" : "no");

    printf("=== 5 error values ===\n");
    printf("e1 = %.8f\n", err_len);
    printf("e2 = %.8f\n", err_perp);
    printf("e3 = %.8f\n", err_dot);
    printf("e4 = %.8f\n", fabs(vec_len(vec_normalize(zero)) - 0.0));
    printf("e5 = %.8f\n", fabs(vec_len(vec_lerp(a, b, 0.5)) - vec_len(vec_scale(vec_add(a, b), 0.5))));
    return 0;
}
