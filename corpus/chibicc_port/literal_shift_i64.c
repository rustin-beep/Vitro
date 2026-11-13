// @category: chibicc_port
// source: chibicc test/literal.c:39-47（MIT, © 2019 Rui Ueyama）
// topic: 64 位移位族（ULL/LL 后缀域，移位量 >31 的全宽右移）。原行 -1Ul>>62 系 LP64 口径
// （Win LLP64 long=4B，同式 >>62 得 0 非 3）——按 Win clang 22.1.4（LLP64）口径改写为
// ULL/LL 形态重采。首批 port 时 Vitro LShr 移位量上限 31 触发教学 trap 整族剔除，
// 修复后翻面回收（i437 增量批实测：js+native 双臂 == clang 逐位）。
#include <stdio.h>
int main(void) {
  printf("%llu %llu\n",
         (unsigned long long)(-1ULL >> 62),                    // clang: 3
         (unsigned long long)(0xffffffffffffffffULL >> 63));   // clang: 1
  printf("%lld\n", (long long)(18446744073709551615ULL >> 63)); // clang: 1
  return 0;
}
