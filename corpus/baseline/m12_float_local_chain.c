// @category: baseline
// 绿锚（#437 即可入库批）：审阅 v2 M12 p13「float 全链」无发现面——局部/全局/数组/struct 成员的
// float 复合算术三方一致。来源：tmp/review_v2_M12/probes/p13_float_local.c
#include <stdio.h>
float gf = 1.5f;
int main(void) {
    float f = 1.5f; f += 2.25f;   /* 3.75 */
    float g = f * 2.0f;           /* 7.5 */
    gf += 1.0f;                   /* 2.5 */
    float arr[2] = {1.5f, 2.5f};
    arr[0] += 0.25f;              /* 1.75 */
    struct FS { float m; } s = {0.5f};
    s.m *= 4.0f;                  /* 2.0 */
    printf("%.3f %.3f %.3f %.3f %.3f\n", f, g, gf, arr[0], s.m);
    return 0;
}
