#ifndef CALC_H
#define CALC_H

int calc_add(int a, int b);
int calc_sub(int a, int b);
int calc_mul(int a, int b);
int calc_div(int a, int b);
int calc_safe_div(int a, int b, int *out);
int calc_clamp(int value, int low, int high);
int calc_sum_to(int n);

#endif /* CALC_H */
