/*
 * @category: func_safety
 * 非 void 缺 return 与隐式函数声明两教学点（#214 修复锚，2026-10-22）：
 * W3084（所有出口路径缺 return——返回值未定义，clang -Wreturn-type 同
 * 点）+ W3085（无原型前向调用——C99 起隐式声明废弃，clang 默认 error、
 * 教学口径 warning）。对照组：双臂 return / 原型先行不误报。运行行为
 * 与 clang 对拍（警告不进 stdout）。clang 真值对拍。
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
int late_def(int v) { return v + 1; }       /* 定义晚于 main：W3085 */

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
