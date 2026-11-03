// @category: chibicc_port
// source: chibicc test/function.c（MIT, © 2019 Rui Ueyama）
// topic: 函数调用基础：多参数/嵌套调用/递归 fib/char 参数截断/布尔参数/静态函数/形参数组退化
#include <stdio.h>
static int static_fn(void) { return 3; }
int ret3(void) { return 3; return 5; }   // 首 return 生效
int add2(int x, int y) { return x + y; }
int add6(int a, int b, int c, int d, int e, int f) { return a+b+c+d+e+f; }
int fib(int x) { if (x<=1) return 1; return fib(x-1) + fib(x-2); }
int sub_char(char a, char b, char c) { return a - b - c; }
int sub_long(long a, long b, long c) { return a - b - c; }
// 注：chibicc 原 _Bool 参数/返回族（bool_fn_add/sub：clang 1 0 1 0 1 1 vs Vitro 4 2 -2 -4 1 -1）
//——_Bool 实参不归一到 0/1（DIFF 候选，同 sizeof_types_llp64 的 _Bool 初始化面），移 deferred
char int_to_char(int x) { return x; }
int param_decay(int x[]) { return x[0]; }
void ret_none() { return; }
int counter() { static int i; static int j = 1+1; return i++ + j++; }
int g1;
int *g1_ptr(void) { return &g1; }
int main(void) {
  printf("%d %d %d\n", ret3(), add2(3, 5), add2(5, 3)-1);
  printf("%d\n", add6(1,2,3,4,5,6));
  printf("%d\n", add6(1,2,add6(3,4,5,6,7,8),9,10,11));
  printf("%d\n", add6(1,2,add6(3,add6(4,5,6,7,8,9),10,11,12,13),14,15,16));
  printf("%d\n", fib(9));
  printf("%d %d\n", sub_char(7, 3, 3), sub_char(7,3,2));
  printf("%d\n", sub_long(7, 3, 3));
  g1 = 3; printf("%d\n", *g1_ptr());
  // 注：chibicc 原 ASSERT(5, int_to_char(261))——char 返回值应窄化到 5，Vitro 返回 261（函数返回窄化缺失，DIFF 候选），移 deferred
  printf("%d\n", static_fn());
  int x2[2]; x2[0]=3; printf("%d\n", param_decay(x2));
  // 注：chibicc 原文同表达式三连 counter()——求值序 UB（Win clang 左到右 / WSL gcc 右到左），拆三行定序
  printf("%d\n", counter());
  printf("%d\n", counter());
  printf("%d\n", counter());
  ret_none();
  printf("%d\n", (add2)(2,3));          // 括号函数名
  printf("%d\n", (&add2)(2,3));         // 取址调用
  int (*fn)(int,int) = add2; printf("%d\n", fn(2,5));
  // 注：chibicc 原 ASSERT(5, (***add2)(2,3))——函数名多级解引用，Vitro E3021 拒收（gap 候选），移 deferred
  return 0;
}
