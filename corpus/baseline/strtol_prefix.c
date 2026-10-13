// @category: baseline
// strtol 前缀语义锚（2026-10-05 批二-a 修语义；2026-10-06 新病批解封编译层
// 后补入——const char* 形参收字面量/数组的 E3038 假阳性即 issue #3 本体，
// check_array_pointer_assignable 补 const 安全方向兼容）：base=0 前缀探测
//（0x→16/0 前缀→8/否则 10）+ base=16 剥 0x
// 病 20 残余面（2026-10-13）：值域外饱和——C11 §7.22.1.4p8 LONG_MAX/
// LONG_MIN + ERANGE（LLP64 long=32 位；旧 i64 位截断 999999999999999999
// → -1486618625 回绕）；endptr 面已修（64 位全宽写回，end-str 差值可负形态）
#include <stdio.h>
#include <stdlib.h>
int main() {
    char s1[] = "0x1f";
    char s2[] = "017";
    printf("%ld %ld %ld %ld\n", strtol("0x1f", 0, 0), strtol(s1, 0, 0), strtol(s2, 0, 0), strtol("0x10", 0, 16));
    char *end;
    char big[] = "999999999999999999xyz";
    long ov = strtol(big, &end, 10);
    long uv = strtol("-99999999999999999", 0, 10);
    long lim = strtol("2147483647", 0, 10);
    long lim2 = strtol("-2147483648", 0, 10);
    printf("%ld %ld %ld %ld %d\n", ov, uv, lim, lim2, (int)(end - big));
    return 0;
}
