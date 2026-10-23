/*
 * @category: predefined_macro
 * __FILE__/__LINE__ 预定义宏（#221 修复锚，2026-10-22；2026-10-23 CI
 * 三臂修正）：C99 §6.10.8——直接使用/宏体内使用（取展开点）/断言惯
 * 用法。旧形态 E3023「未声明的变量」误拒。__FILE__ 的原始值是调用方
 * 传入的路径拼写（CLI 全路径/gateway basename，C 语义即如此）——锚
 * 输出经 strrchr 剥离归一为 basename，三臂同判不依赖通道。
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
