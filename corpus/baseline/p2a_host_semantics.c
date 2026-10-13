#include <stdio.h>
#include <string.h>
#include <time.h>

// @category: #71 台账批A·host 库语义六病锚（2026-10-13 修复批）——
// strcmp 族 unsigned char 差（病 45）/ strerror UCRT 对齐（47）/ time 写
// *tloc（48——deterministic 值域恒 0 为 #58 在案，本锚锁语义面：t 被写 0
// 而非残留初值）/ perror = strerror(0)（49）/ fgetc 二进制不折叠 CR LF
// （50）/ fread 乘 64 位防御（51）。病 26 未知转换符/28 round 边界同批。

int main() {
  // 病 45：三函数无符号字节差（clang 全 +1）
  printf("%d %d %d\n",
    strcmp("\x80", "\x7F") > 0 ? 1 : -1,
    strncmp("\x80", "\x7F", 1) > 0 ? 1 : -1,
    memcmp("\x80", "\x7F", 1) > 0 ? 1 : -1);
  // 病 47/49：strerror(1) UCRT 文案 + perror 前缀形态
  printf("%s\n", strerror(1));
  perror("px");
  // 病 48：time(&t) 写 *tloc（写成功即 t 离开初值 12345——deterministic
  // 域写 0、真实域写时间戳，布尔断言双侧同形；值域差是 #58 在案不锚）
  time_t t = 12345;
  time(&t);
  printf("written=%d\n", t != 12345);
  // 病 50：二进制读写往返 0D 0A（fgetc 不折叠）
  FILE* f = fopen("tmp_p2a.bin", "wb");
  fputc(0x0D, f);
  fputc(0x0A, f);
  fclose(f);
  FILE* r = fopen("tmp_p2a.bin", "rb");
  printf("%d %d %d\n", fgetc(r), fgetc(r), fgetc(r));
  fclose(r);
  remove("tmp_p2a.bin");
  // 病 26：未知转换符 q 原样不取参
  printf("A%qB|%d|\n", 42);
  // 病 28：round 0.5-1ulp 边界（加法舍入域陷阱）
  printf("%.1f %.1f %.1f %.1f\n",
    round(0.49999999999999994), round(0.5), round(2.5), round(-1.5));
  return 0;
}
