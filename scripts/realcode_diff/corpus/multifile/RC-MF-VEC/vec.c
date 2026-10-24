#include "vec.h"
#include <math.h>

Vec2 vec_add(Vec2 a, Vec2 b)
{
    Vec2 r;
    r.x = a.x + b.x;
    r.y = a.y + b.y;
    return r;
}

Vec2 vec_sub(Vec2 a, Vec2 b)
{
    Vec2 r;
    r.x = a.x - b.x;
    r.y = a.y - b.y;
    return r;
}

Vec2 vec_scale(Vec2 a, double k)
{
    Vec2 r;
    r.x = a.x * k;
    r.y = a.y * k;
    return r;
}

double vec_dot(Vec2 a, Vec2 b)
{
    return a.x * b.x + a.y * b.y;
}

double vec_cross(Vec2 a, Vec2 b)
{
    return a.x * b.y - a.y * b.x;
}

double vec_len(Vec2 a)
{
    return sqrt(a.x * a.x + a.y * a.y);
}

double vec_distance(Vec2 a, Vec2 b)
{
    double dx = a.x - b.x;
    double dy = a.y - b.y;
    return sqrt(dx * dx + dy * dy);
}

Vec2 vec_normalize(Vec2 a)
{
    Vec2 r;
    double len = vec_len(a);
    if (len < 1e-12) {
        r.x = 0.0;
        r.y = 0.0;
        return r;
    }
    r.x = a.x / len;
    r.y = a.y / len;
    return r;
}

Vec2 vec_rotate(Vec2 a, int q)
{
    Vec2 r;
    int k = ((q % 4) + 4) % 4;
    r.x = a.x;
    r.y = a.y;
    for (int i = 0; i < k; i++) {
        double nx = -r.y;
        double ny = r.x;
        r.x = nx;
        r.y = ny;
    }
    return r;
}

Vec2 vec_lerp(Vec2 a, Vec2 b, double t)
{
    Vec2 r;
    r.x = a.x + (b.x - a.x) * t;
    r.y = a.y + (b.y - a.y) * t;
    return r;
}
