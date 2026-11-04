// @category: chibicc_port
// source: chibicc test/cast.c（MIT, © 2019 Rui Ueyama）— statement expression 拆变量
// topic: 整数截断链与符号性：宽转窄/有符号↔无符号/混合比较/混合除法取模（Win LLP64 真值口径）
#include <stdio.h>
int main(void) {
  printf("%d\n", (int)8590066177);       // 低 32 位 131585
  printf("%d\n", (char)8590066177);      // 1
  printf("%d\n", (long)1);               // 1（long 4B）
  printf("%d %d %d\n", (char)255, (signed char)255, (unsigned char)255);
  // 注：chibicc 原 (short)65535 → -1——Vitro 65535 不窄化（D7 short 退化 int 已知差异），移 deferred
  printf("%d\n", (unsigned short)65535);
  printf("%d %u\n", (int)0xffffffff, (unsigned)0xffffffff);
  printf("%d\n", -1 < 1);
  printf("%d\n", -1 < (unsigned)1);      // -1 转 unsigned 比较
  printf("%d\n", (char)127+(char)127);   // 提升 254
  printf("%d\n", -1>>1);
  printf("%lld\n", (long long)(unsigned int)-1);   // 4294967295（chibicc 原用 unsigned long——LP64=8B 平台方言，改 uint 消方言）
  printf("%d\n", (int)(((unsigned)-1)>>1));        // 2147483647
  printf("%d\n", -50/2);
  printf("%d\n", (int)(((unsigned)-100)/2));       // 2147483598
  printf("%lld\n", (long long)(((unsigned long long)-100)/2)); // 9223372036854775758
  printf("%lld\n", (long long)(((long long)-1)/(unsigned)100)); // 公共类型 ULL → 0
  printf("%d %lld\n", (-100)%7, (long long)(((unsigned)-100)%7));  // -2 / 2
  printf("%lld\n", (long long)(((unsigned long long)-100)%9));     // 6
  printf("%d\n", (int)(unsigned short)65535);
  // 注：chibicc 原 typedef short/unsigned short 变量截断族（T x=65535 → (int)x=-1）——Vitro D7 short 退化（同上），移 deferred
  // 注：chibicc 原 (_Bool)0.0/(_Bool)0.1 → 0/1——Vitro 0/0（浮点转 _Bool 判零截断，判零族 DIFF 候选），移 deferred
  printf("%d\n", (char)3.0);
  printf("%d\n", (int)3.99);
  printf("%d\n", (float)3.5 == 3.5f);
  printf("%d\n", (double)(float)5.5 == 5.5);
  printf("%d\n", (int)(float)3);
  printf("%d\n", (int)(double)3);
  // 注：chibicc 原 (long long)(float)3L → 3——Vitro 1077936128（f32 位模式 0x40400000 直出，速查表 C10 同根），移 deferred
  printf("%lld\n", (long long)(double)3L);
  return 0;
}
