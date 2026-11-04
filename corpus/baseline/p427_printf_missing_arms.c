// #427 批 B4 语料锚：printf 缺臂族修复边界（vm_diff/clang golden 域——
// 全形态与 Win clang 22.1.4 / WSL gcc 逐位一致，tmp/b4probes/truth_*.txt
// 留档）。%a/%A（UCRT 13 位 vs glibc 最短——实现定义域分叉）与 %n
//（UCRT 整程禁）平台方言域**不入本语料**——wbtest 直锚（host_b4_printf_
// wbtest.mbt）。
#include <stdio.h>
#include <stdarg.h>

void t1(const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  vprintf(fmt, ap);
  va_end(ap);
}

int main(void) {
  // 缺臂错位三联（%F 执行臂；实参对位）
  printf("%F|%d\n", 2.5, 43);
  // 精度在场 0 旗标忽略（C11 7.21.6.1——旧三臂进程崩溃 + 00000 错值）
  printf("[%05.0d][%05.0u][%08.0x][%05.0o]\n", 0, 0u, 0u, 0u);
  printf("[%08.3d]\n", 42);
  // 未知转换符与实参个数无关（clang 恒丢 % 输出字母）
  printf("[%d%q|%d][%q][%d%q][%5q][%hq]\n", 1, 2, 1, 1);
  // 长度修饰截断
  printf("%hhd|%hd|%hhu|%hu|%hhd|%hd|%hhx|%hx\n", 300, 70000, 70000, 70000,
         -1, -1, 0x1234u, 0x12345u);
  // # 前缀位置（前缀属数值部分）+ # 对 g 保尾零
  printf("%#08x|%#05X|%#05o|%#8x|%-#8x\n", 255u, 255u, 8u, 255u, 255u);
  printf("%#.3g|%#g|%#.17g\n", 0.0001, 0.0001, 0.1);
  // %.17g/%.17e 高精度段精确路径（A2 表 G1-G7 + t_prec#9-14）
  printf("%.17g\n", 1e23);
  printf("%.17g\n", 1.5e126);
  printf("%.17g\n", 8.8817841970012523e-320);
  printf("%.17g\n", 4.9406564584124654e-324);
  printf("%g\n", 4.9406564584124654e-324);
  printf("%.17e\n", 1e23);
  printf("%.17e\n", 0.1);
  printf("%.17e\n", 4.9406564584124654e-324);
  // vprintf 变参 len>=4 字符串实参（codegen CallVar word 计数数组退化
  // 修复——旧 VM 栈下溢三臂进程崩溃；M21 A2）
  t1("%s|", "abc");
  t1("%s|", "abcd");
  t1("%d|", 7);
  {
    char b[8];
    b[0] = 'a';
    b[1] = 'b';
    b[2] = 'c';
    b[3] = 'd';
    b[4] = 0;
    t1("%s|", b);
  }
  // host printf 家族 float 实参提升（PR #462 审阅 P1：sprintf/snprintf
  // 旧落 CastF2D 白名单外——float 位模式当 double 位模式直传静默错值）
  {
    float f = 3.25f;
    double d = 3.25;
    char b[64];
    sprintf(b, "%f", f);
    printf("A[%s]\n", b);
    sprintf(b, "%g|%e", f, f);
    printf("B[%s]\n", b);
    snprintf(b, 40, "%f", f);
    printf("C[%s]\n", b);
    sprintf(b, "%f", d);
    printf("D[%s]\n", b);
  }
  return 0;
}
