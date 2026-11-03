// @category: chibicc_port
// source: chibicc test/macro.c（MIT, © 2019 Rui Ueyama）— 条件编译面重排
// topic: #if/#elif/#else 嵌套与常量表达式条件、#ifdef/#ifndef、跳过区内容错、宏定义条件
#include <stdio.h>
int main(void) {
  int m = 0;
#if 1
  m = 5;
#endif
  printf("%d\n", m);
#if 1
# if 0
  语法上无效的内容在跳过区
# endif
  m = 3;
#endif
  printf("%d\n", m);
#if 1-1
  m = 2;
#else
  m = 3;
#endif
  printf("%d\n", m);
#if 0
  m = 1;
#elif 0
  m = 2;
#elif 3+5
  m = 3;
#elif 1*5
  m = 4;
#endif
  printf("%d\n", m);
#if 0
  m = 1;
#elif 1
# if 1
  m = 2;
# else
  m = 3;
# endif
#else
  m = 5;
#endif
  printf("%d\n", m);
#define M 5
#if M
  m = 5;
#else
  m = 6;
#endif
  printf("%d\n", m);
#if M-5
  m = 6;
#elif M
  m = 5;
#endif
  printf("%d\n", m);
#ifdef M6
  m = 5;
#else
  m = 3;
#endif
  printf("%d\n", m);
#define M6
#ifdef M6
  m = 5;
#else
  m = 3;
#endif
  printf("%d\n", m);
#ifndef M7
  m = 3;
#else
  m = 5;
#endif
  printf("%d\n", m);
#define M7
#ifndef M7
  m = 3;
#else
  m = 5;
#endif
  printf("%d\n", m);
#if 0
#include "/no/such/file"
#ifdef NO_SUCH_MACRO
#endif
#endif
  printf("%d\n", m);   // 跳过区内坏 include/未配对 ifdef 不爆
  return 0;
}
