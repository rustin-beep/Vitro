/*
 * @category: predefined_macro
 * __FILE__/__LINE__ 预定义宏（#221 修复锚，2026-10-22）：C99 §6.10.8
 * ——直接使用/宏体内使用（取展开点，C99 §6.10.8.1）/断言惯用法全形态。
 * 旧形态 E3023「未声明的变量 '__FILE__'」误拒（带断言的测试框架全灭）。
 * include 段的 __FILE__ 拼写差（clang Windows 带 .\ 前缀）是平台相关
 * 形态不入锚。clang 真值对拍。
 */
#include <stdio.h>

#define ASSERT_TRUE(expr) \
    do { if (!(expr)) unit_fail(__FILE__, __LINE__, #expr); } while (0)
#define LOG_POS() printf("at %s:%d\n", __FILE__, __LINE__)

static void unit_fail(const char *file, int line, const char *expr) {
    printf("FAIL %s:%d (%s)\n", file, line, expr);
}

int main(void) {
    printf("file=%s\n", __FILE__);
    printf("here=%d\n", __LINE__);
    LOG_POS();
    ASSERT_TRUE(1 == 2);
    int ln = __LINE__;
    printf("stmt-line=%d\n", ln);
    return 0;
}
