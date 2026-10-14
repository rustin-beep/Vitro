/* #82（2026-10-13 报 / 2026-10-14 修）：printf 的 %% 折叠不消耗实参、
 * 与参数组无关（C11 §7.21.6.1 转换 %% 展开单个 %）——clang/gcc 零参与
 * 参数耗尽位均折叠。旧输出侧主循环 `used < args.length() && ch == 37`
 * 把 %% 折叠一并门住：printf("%%") 输出 "%%"、printf("%d %%",50) 输出
 * "50 %%"。根因系 Rust oracle 既有偏差（2026-09-23 实测照搬并加锚固化）
 * ——issue #82（LLM 语料探针 NDJSON 实测）定责后翻面：门条件放行「%
 * 后跟 %」形态；%d 参数耗尽（原样透出）与行尾孤立 % 的既有行为不变
 *（wbtest 旧锚 printf_percent_percent_semantics 已同步翻转）。 */
#include <stdio.h>
int main(void) {
    printf("%%");          /* 零参：折叠 % */
    printf("|");
    printf("%d %%", 50);   /* 参数耗尽位：50 % */
    printf("|");
    printf("%d %% %d", 1, 2); /* 中段对照（旧绿防回归）：1 % 2 */
    printf("|");
    printf("%%%%");        /* 零参多组：%% */
    printf("\n");
    return 0;
}
