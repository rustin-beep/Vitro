/*
 * @category: func_safety
 * 非 void 缺 return 与隐式函数声明两教学点（#214 修复锚，2026-10-22；
 * 审阅 P1-1/P2-1 批 2026-10-23 补强——W3084 四反例形态与锚位勘误）：
 * W3084（所有出口路径缺 return——返回值未定义，clang -Wreturn-type
 * 同点判据矩阵：main 豁免/for(;;)/do-while 体必返/switch 全臂+default）
 * + W3085（无原型前向调用——C99 起隐式声明废弃，教学宽容 warning，
 * 与 clang error 的编译状态分歧不入锚、由 wbtest 锁）。clang 对拍。
 */
#include <stdio.h>

int add(int a, int b) { return a + b; }     /* 定义先行：调用点合法 */
int proto_first(int v);                     /* 原型先行：前向调用合法 */
int both_paths(int x) {
    if (x >= 0) { return 1; } else { return -1; }   /* 双臂覆盖不误报 */
}
int fallthrough(int x) {                    /* W3084：if 单臂落空 */
    if (x > 0) { return 1; }
}
int no_return(int x) {                      /* W3084：全缺 */
    printf("side=%d\n", x);
}
/* W3084 四反例（clang -Wreturn-type 零告警形态）——审阅 P1-1 补强 */
int spin_forever(void) { for (;;) {} }      /* for(;;) 永不退出 */
int do_once(void) { do { return 1; } while (0); }  /* 体必返 */
int pick(int x) {                           /* switch 全臂 + default */
    switch (x) {
    case 1: return 10;
    case 2: return 20;
    default: return 0;
    }
}
int late_def(int v) { return v + 1; }       /* 值对照（定义先行） */

int main(void) {
    printf("add=%d\n", add(2, 3));
    printf("proto=%d\n", proto_first(4));
    printf("both=%d\n", both_paths(0));
    fallthrough(3);            /* 返回值未定义（W3084 文案本义）：不消费 */
    no_return(7);
    printf("late=%d\n", late_def(9));
    return 0;
}

int proto_first(int v) { return v * 10; }
