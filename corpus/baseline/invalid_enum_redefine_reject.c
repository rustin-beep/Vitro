// @category: baseline
// #182 D-4 红锚：enum tag 重复定义（C11 6.7.2.3p3 约束）clang/gcc 双
// error "redefinition of 'E'"；vitro 修后 E3002（parser 层查重）。
// 对照组：不同名 enum 两次定义、typedef enum 单次定义合法。
#include <stdio.h>
enum E { A };
enum E { B };
enum F { C };
enum G { D };
int main(void) {
  printf("%d\n", A);
  return 0;
}
