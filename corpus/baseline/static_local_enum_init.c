/*
 * @category: static_init
 * 函数内 static + 枚举常量初始化（P1-1 审阅批修复锚，2026-10-18）：
 * 旧 fold_enum_in_static_init 只接 parse_var_decl_from_base（聚合定义
 * 带声明器形态），局部声明主路径不折 → `static int s = K;` 的枚举叶
 * 被 typeck 按 Ident 报 E3075 误拒（clang 放行）。本例覆盖主路径单
 * 声明符/多声明符/数组/表达式叶/遮蔽不折五形态。
 */
#include <stdio.h>

enum { K = 3, EB = 10 };

int v_enum = EB + 1; /* 文件作用域对照（既有覆盖形态） */

int main(void) {
    static int s = K;                    /* 主路径单声明符（旧 E3075） */
    static int a = K, b = K + 1;         /* 主路径多声明符（旧 extra 漏折） */
    static int arr[3] = {K, K + 1, 2 * K}; /* 数组聚合 */
    int local_shadow = 5;
    static int normal = 2 * 3;           /* 无枚举叶对照 */

    printf("s=%d a=%d b=%d\n", s, a, b);
    printf("arr=%d,%d,%d\n", arr[0], arr[1], arr[2]);
    printf("normal=%d v_enum=%d shadow=%d\n", normal, v_enum, local_shadow);
    return 0;
}
