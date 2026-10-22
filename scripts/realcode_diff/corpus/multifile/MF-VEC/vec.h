#ifndef VEC_H
#define VEC_H

typedef struct {
    double x;
    double y;
} Vec2;

Vec2 vec_add(Vec2 a, Vec2 b);
Vec2 vec_sub(Vec2 a, Vec2 b);
Vec2 vec_scale(Vec2 a, double k);
double vec_dot(Vec2 a, Vec2 b);
double vec_cross(Vec2 a, Vec2 b);
double vec_len(Vec2 a);
double vec_distance(Vec2 a, Vec2 b);
Vec2 vec_normalize(Vec2 a);
/* rotate by q quarter turns (90 degrees each, counter-clockwise); exact math, no trig */
Vec2 vec_rotate(Vec2 a, int q);
Vec2 vec_lerp(Vec2 a, Vec2 b, double t);

#endif /* VEC_H */
