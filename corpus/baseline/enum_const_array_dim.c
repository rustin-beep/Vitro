/* #78（2026-10-13 报 / 2026-10-14 修）：enum 常量是 C11 §6.4.4.3 整型
 * 常量表达式——`t[N]`（N 为枚举成员）是普通数组非 VLA，clang/gcc 双收。
 * 旧 const_int_of 叶子只认 Literal/Unary/Binary，Ident 落 None 判 VLA →
 * codegen 报「全局作用域不支持变长数组(VLA)」E0 + 级联（文件作用域
 * const/非 const、块作用域、无初始化列表三形态全中；字面量尺寸正常）。
 * 修复：Parser 持枚举常量表（enum 声明注册，Rollback 与 typedef_names
 * 同款整表快照），const_int_of/array_dim_info/eval_enum_const 的 Ident
 * 叶子查表折叠；`B = A + 1` 引用前成员同批接通。 */
#include <stdio.h>
enum { A = 3, B = A + 2 };
static const int t[B] = { [0] = 1, [4] = 9 }; /* 4+2=6 尺寸 + designated */
static int u[A + 1];                          /* 二元表达式维度 */
int main(void) {
    int v[B] = { [0] = 7 }; /* 块作用域 enum 尺寸 + 初始化列表（块内 enum
                               定义体是另案缺口——parse_base_type Enum 臂
                               不解析定义体，本语料不覆盖该形态） */
    u[0] = 5;
    printf("%d %d %d %d\n", t[0], t[4], u[0], v[0]);
    return 0;
}
