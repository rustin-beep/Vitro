// printf/putchar/fprintf 返回值语义（批四 N3 销案的 E2E 语料锚——C 标准：
// 返回写出的字符数 / 被写的字符；引擎旧形态照搬 oracle 返回 void）。
// 预期（Clang 对拍真值）：stdout = "hello\n42-x\nZe!\na=6 b=5 c=90 d=3\n"，
// 退出码 104（6+5+90+3）。注意 d 走 fprintf(**stdout**) 而非 stderr——
// 管道下 clang 的 stderr 无缓冲恒先于缓冲 stdout 刷出、引擎按写入序，
// 交错序是 C 标准未定义的实现差异（clang_direct 捕获合并流），语料侧
// 避开两流混排（stderr 返回值锚由 host_io_surface wbtest 承担）。
#include <stdio.h>

int main() {
    int a = printf("hello\n");
    int b = printf("%d-%s\n", 42, "x");
    int c = putchar('Z');
    int d = fprintf(stdout, "e!\n");
    printf("a=%d b=%d c=%d d=%d\n", a, b, c, d);
    return a + b + c + d;
}
