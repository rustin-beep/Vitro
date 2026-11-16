/*
 * @category: predefined_macro
 * __FILE__/__LINE__ 预定义宏（#221 修复锚，2026-10-22；2026-10-23 CI
 * 三臂修正）：C99 §6.10.8——直接使用/宏体内使用（取展开点）/断言惯
 * 用法。旧形态 E3023「未声明的变量」误拒。__FILE__ 的 C99 语义是实现
 * 定义；本沙盒在 pp 展开层统一取 basename（2026-10-23 跨臂修正）——
 * 否则 CLI 全路径 / gateway basename 会让 native/wasm 的字符串内存映像
 * 分叉（vm_diff 实锤）。输出侧的 BASE 仍保留，作显示归一与兼容。
 * clang 真值对拍。
 */
#include <string.h>
#include <stdio.h>

#define ASSERT_TRUE(expr) \
    do { if (!(expr)) unit_fail(BASE(__FILE__), __LINE__, #expr); } while (0)
#define LOG_POS() printf("at %s:%d\n", BASE(__FILE__), __LINE__)
#define BASE(f) ((strrchr(f, '/') ? strrchr(f, '/') + 1 : (strrchr(f, '\\') ? strrchr(f, '\\') + 1 : f)))

static void unit_fail(const char *file, int line, const char *expr) {
    printf("FAIL %s:%d (%s)\n", file, line, expr);
}

int main(void) {
    printf("file=%s\n", BASE(__FILE__));
    printf("here=%d\n", __LINE__);
    LOG_POS();
    ASSERT_TRUE(1 == 2);
    int ln = __LINE__;
    printf("stmt-line=%d\n", ln);
    return 0;
}
