/* B10 #434 / M22 A-3..A-12：strtol/strtod 扫描器族（饱和/endptr=nptr/
 * 指数并点/上溢 inf/INF·NAN/atol·atoi 饱和）。非法 base 域不入本例
 * （UCRT invalid parameter handler 杀进程采不到 clang 值——glibc 判据
 * EINVAL 由白盒锚 strtol_invalid_base_einval_b10 锁定）。真值 = Win
 * clang 22.1.4 UCRT tmp/b10probe 实测。 */
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
int main(){
  char *e; long v; double d;
  errno = 0; v = strtol("18446744073709551616", &e, 10);
  printf("A v=%ld errno=%d off=%d\n", v, errno, (int)(e - (char*)"18446744073709551616"));
  errno = 0; v = strtol("  -abc", &e, 10);
  printf("B v=%ld errno=%d off=%d\n", v, errno, (int)(e - (char*)"  -abc"));
  errno = 0; v = strtol("-", &e, 10);
  printf("B2 v=%ld errno=%d off=%d\n", v, errno, (int)(e - (char*)"-"));
  errno = 0; v = strtol("9223372036854775808", &e, 10);
  printf("B3 v=%ld errno=%d\n", v, errno);
  errno = 0; d = strtod("1e5.3", &e);
  printf("D d=%.1f off=%d\n", d, (int)(e - (char*)"1e5.3"));
  errno = 0; d = strtod("1e400", NULL);
  printf("E d=%.1f errno=%d\n", d, errno);
  errno = 0; d = strtod("1e-400", NULL);
  printf("E2 d=%.1f errno=%d\n", d, errno);
  errno = 0; d = strtod("inf", &e);
  printf("F d=%.1f off=%d errno=%d\n", d, (int)(e - (char*)"inf"), errno);
  errno = 0; d = strtod("infinity", &e);
  printf("F2 d=%.1f off=%d\n", d, (int)(e - (char*)"infinity"));
  errno = 0; d = strtod("-INF", &e);
  printf("F3 d=%.1f off=%d\n", d, (int)(e - (char*)"-INF"));
  errno = 0; d = strtod("nan", &e);
  printf("F4 d=%.1f off=%d errno=%d\n", d, (int)(e - (char*)"nan"), errno);
  errno = 0; d = strtod("NAN(123)", &e);
  printf("F5 d=%.1f off=%d\n", d, (int)(e - (char*)"NAN(123)"));
  errno = 0; d = strtod("0x1.", &e);
  printf("F6 d=%.1f off=%d\n", d, (int)(e - (char*)"0x1."));
  errno = 0; d = strtod("0x1p1025", &e);
  printf("F7 d=%.1f errno=%d off=%d\n", d, errno, (int)(e - (char*)"0x1p1025"));
  errno = 0; d = strtod("0x1p-1075", &e);
  printf("F8 d=%.1f errno=%d off=%d\n", d, errno, (int)(e - (char*)"0x1p-1075"));
  printf("G atol=%ld\n", atol("3000000000"));
  int v2 = atoi("2147483648");
  printf("H a=%d\n", v2);
  return 0;
}
