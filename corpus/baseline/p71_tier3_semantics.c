#include <stdio.h>

// @category: #71 第三梯队语义锚（printf %e/%g + struct 拷贝尾 + 遮蔽序 +
// 全局 struct 定义带声明器 + 一元 + + realloc 负 size——2026-10-11 修复批）
// 病 21/22/35/37/38/39 六形态（scanf 宽度/%f 另见 p71_tier3_scanf.c）。

struct Point { int x, y; } origin;          // 病 38：定义带声明器
struct S1 { char c; };                       // 病 35：size<4
struct S5 { int a; char b; };                // 病 35：size%4≠0

int shadow_probe(void);
int shadow_static(void);

int main() {
    // 病 21：%e/%E（修复前输出字面 "%e"）
    printf("%e %E\n", 1.5, 1.5);
    printf("%e\n", -0.000025);
    // 病 22：%g/%G 负零保符号（修复前 "0"）
    printf("%g %G\n", -0.0, -0.0);
    // 病 39：一元 +（修复前 E2003）
    int x = +5;
    double d = +1.5;
    printf("%d %f\n", x, d);
    // 病 38：origin 可用（修复前 E2005 级联）
    origin.x = 1;
    origin.y = 2;
    printf("%d %d\n", origin.x, origin.y);
    // 病 35：struct 拷贝尾（修复前 size=1 零拷、size=5 丢尾字节）
    struct S1 a = {7}, b;
    b = a;
    struct S5 m = {1, 9}, n;
    n = m;
    printf("%d %d %d\n", b.c, n.a, n.b);
    // 病 29（realloc 负 size）不在此语料：含 malloc/realloc/free 的 exe
    // 在本地被 Defender 实时拦截（rc=127 非瞬态——批五同型），行为面由
    // host_memory_wbtest realloc_negative_size_preserves_block 锚锁。
    // 病 37：块内局部遮蔽 static（修复前读值/赋值/增减写穿 static）
    printf("shadow=%d %d %d\n", shadow_probe(), shadow_probe(), shadow_static());
    return 0;
}

static int sx = 5;

int shadow_probe(void) {
    {
        int sx = 10;
        sx = 20;
        sx++;
        return sx;
    }
}

int shadow_static(void) {
    return sx;
}
