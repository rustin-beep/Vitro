// @category: chibicc_port
// source: chibicc test/cast.c:54-55（MIT, © 2019 Rui Ueyama）
// topic: long long → float → long long 往返转换（(long long)(float)3L）：首批 port 时
// Vitro f32 位模式直出（1077936128）剔除；#471 批 F2D+CastD2Q 双跳修复后翻面回收。
// 真值按 Win clang 22.1.4（LLP64）实跑重采。
#include <stdio.h>
int main(void) {
  printf("%lld %lld\n", (long long)(float)3L, (long long)(float)-3L);   // clang: 3 -3
  return 0;
}
