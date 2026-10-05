// @category: baseline
// strtol 前缀语义锚（2026-10-05 批二-a 修语义；2026-10-06 新病批解封编译层
// 后补入——const char* 形参收字面量/数组的 E3038 假阳性即 issue #3 本体，
// check_array_pointer_assignable 补 const 安全方向兼容）：base=0 前缀探测
//（0x→16/0 前缀→8/否则 10）+ base=16 剥 0x
#include <stdio.h>
#include <stdlib.h>
int main() {
    char s1[] = "0x1f";
    char s2[] = "017";
    printf("%ld %ld %ld %ld\n", strtol("0x1f", 0, 0), strtol(s1, 0, 0), strtol(s2, 0, 0), strtol("0x10", 0, 16));
    return 0;
}
