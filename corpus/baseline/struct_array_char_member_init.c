// @category: baseline
// #136 缺陷 1 修复锚（2026-10-17）：struct 数组嵌套聚合初始化中的
// char[] 成员——字节直写（#137 gen_nested_init StringLiteral 臂顺带
// 治愈：旧 `_ =>` 臂把字符串池址当行数据 StoreMem）。int 成员正确、
// char 成员垃圾字节的探针实锤形态。
#include <stdio.h>
typedef struct { int id; char c[4]; } S;
int main(void) {
    S s[2] = { {1,"AA"}, {2,"BB"} };
    printf("%d:[%s] %d:[%s]\n", s[0].id, s[0].c, s[1].id, s[1].c);
    return 0;
}
