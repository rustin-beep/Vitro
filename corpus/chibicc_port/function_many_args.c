// @category: chibicc_port
// source: chibicc test/function.c（MIT, © 2019 Rui Ueyama）
// topic: 多参数函数（10 参/16 参混型）与 __func__/__FUNCTION__
// 注：chibicc 原文 __FUNCTION__ 宏与返回 __func__ 的 func_fn 面——Vitro 未收录 __FUNCTION__（E3023），
// 该两行移 deferred；__func__ 本体面由 function_call_basic 族覆盖
#include <stdio.h>
#include <string.h>
int add10_int(int x1,int x2,int x3,int x4,int x5,int x6,int x7,int x8,int x9,int x10) {
  return x1+x2+x3+x4+x5+x6+x7+x8+x9+x10;
}
int many_args1(int a,int b,int c,int d,int e,int f,int g,int h) { return g / h; }
double many_args2(double a,double b,double c,double d,double e,double f,double g,double h,double i,double j) {
  return i / j;
}
int many_args3(int a,double b,int c,int d,double e,int f,double g,int h,double i,double j,double k,double l,double m,int n,int o,double p) {
  return o / p;
}
int main(void) {
  printf("%d\n", add10_int(1,2,3,4,5,6,7,8,9,10));
  printf("%d\n", many_args1(1,2,3,4,5,6,40,10));
  printf("%.1f\n", many_args2(1,2,3,4,5,6,7,8,40,10));
  printf("%d\n", many_args3(1,2,3,4,5,6,7,8,9,10,11,12,13,14,80,10));
  printf("%d\n", strcmp(__func__, "main") == 0);
  return 0;
}
