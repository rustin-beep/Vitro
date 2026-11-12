// @category: chibicc_port
// source: chibicc test/float.c:83-86（MIT, © 2019 Rui Ueyama）
// topic: 浮点操作数的逻辑非判零——!3./!0./!3.f/!0.f 数值判零（非位模式）。首批 port 时
// Vitro ! 浮点判零错（1 1 0 1）整族剔除；B2 批（#425）Not 判零修数值 != 0 后翻面回收。
// 真值按 Win clang 22.1.4（LLP64）实跑重采。
#include <stdio.h>
int main(void) {
  printf("%d %d %d %d\n", !3., !0., !3.f, !0.f);   // clang: 0 1 0 1
  return 0;
}
