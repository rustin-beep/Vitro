// @category: baseline
// E3：[[属性]] 前缀——解析并忽略（教学子集不实现属性语义，
// 与 Clang 默认模式"未知属性警告后忽略"可见行为一致）
#include <stdio.h>
[[maybe_unused]] int u = 5;
int main() {
    [[maybe_unused]] int v = 6;
    printf("%d %d\n", u, v);
    return 0;
}
