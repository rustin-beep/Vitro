// @category: chibicc_port
// source: chibicc test/macro.c（MIT, © 2019 Rui Ueyama）— 对象宏/函数宏面重排
// topic: 参数不求值展开、逗号实参成组、字符串化 #x、参数先展开再字符串化、函数宏带括号展开
// 注：chibicc 原文宏均在 main 体内 #define——Vitro 对函数体内 #define 的**函数宏**不生效
//（E3036 当作函数调用；对象宏体内生效，macro_conditional.c 已证）。函数宏统一移文件顶层，chibicc 原形态移 deferred。
// 注：以下形态移 deferred（Vitro 拒收，详见 ASSESSMENT）：宏名遮蔽变量/重定义族（int M1=5 与 #define M1 两轮、
//   #define M8 两轮重定义）、空实参 M8(,y)、宏体拼接 M2 3+4+ 后接 5、M4/M5/M6 自引用互引、
//   dbl/M10 未声明函数链接形态（clang 亦拒）
#include <stdio.h>
int ret3(void);
#define M3 3+4
#define M8(x,y) x+y
#define M9(x,y) x*y
#define M7f() 1
#define M7c ()
#define STR(x) #x
#define STR2(x) #x
#define WRAP(x) STR2(x)
int main(void) {
  printf("%d\n", M3*5);          // 23（无括号语义；对象宏体内定义生效）
  printf("%d\n", M8(3, 4));      // 7
  printf("%d\n", M9(3+4, 4+5));  // 24（不求值）
  printf("%d\n", M9((2,3), 4));  // 12（逗号实参成组）
  int M7v = 5;
  printf("%d %d\n", M7f(), M7v);  // 1 5（函数宏带括号才展开）
  printf("%d\n", ret3 M7c);      // 宏产调用括号
  printf("%s|%s\n", STR(a b), STR(  spaced  ));  // 字符串化（内空格折叠边界）
  printf("%s\n", WRAP(123));     // 参数先展开再字符串化
  return 0;
}
int ret3(void) { return 3; }
