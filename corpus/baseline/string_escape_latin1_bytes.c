/* B6（#429，审阅 v2）：\xNN/\NNN 转义字节口径锚——hex/八进制转义产
 * **单字节**（值=字节值），源字符按 UTF-8 字节拆装，两面同对齐三方
 * 编译器（Win clang 22.1.4 / WSL gcc 15.2 / WSL clang 21.1.8，M22 A-1
 * 三列对拍 + M07 A6 / M09 D1）。
 * 修前形态（StringLiteral 按码点承载 + 消费侧 UTF-8 再编码）：
 * \xE4 落 C3 A4 双字节、strlen("\xE4\xBD\xA0zz")=8、sizeof("\xE4")=3、
 * strspn=6——字节口径函数（strlen/strcmp/strspn）连带错值；对照组
 * 「你」源字符路径 #66 起即对，本例同锁防两面回归。 */
#include <stdio.h>
#include <string.h>
int main(void) {
  const char *p = "\xE4";
  printf("b1=%02X %02X\n", (unsigned char)p[0], (unsigned char)p[1]);
  const char *q = "\xE4\xBD\xA0zz";
  printf("len=%d\n", (int)strlen(q));
  const char *h = "你";
  printf("h=");
  for (int i = 0; i < (int)strlen(h); i++) printf("%02X ", (unsigned char)h[i]);
  printf("\n");
  const char *o = "\204";
  printf("o=%02X %02X\n", (unsigned char)o[0], (unsigned char)o[1]);
  printf("spn=%d\n", (int)strspn("\xE4\xBD\xA0zz", "\xE4\xBD\xA0"));
  printf("sz1=%d sz2=%d\n", (int)sizeof("\xE4"), (int)sizeof("\xE4\xBD\xA0zz"));
  printf("s=[%s]\n", "\xE4\xBD\xA0zz");
  char g[] = "\xff";
  printf("g0=%02X gs=%d\n", (unsigned char)g[0], (int)sizeof(g));
  return 0;
}
