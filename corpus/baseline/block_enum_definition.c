/* #93（2026-10-14 报/修）：块作用域 enum 定义体——`enum { M = 3 };` /
 * `enum Tag { ... } x;` 形态旧在 parse_base_type 的 Enum 臂不解析 { 体
 *（只处理「已声明类型引用」形态）→ E2005 级联炸穿到顶层（文件作用域正常
 * ——顶层 parse_enum_decl 专用路径独享；stash 实证既有病，LLM 语料批
 * 编写语料时发现）。修复：Enum 臂识别定义体（Identifier 后跟 LBrace 或
 * 裸 LBrace）→ 成员解析对齐顶层循环（eval_enum_const 求值 +
 * enum_const_values 注册 + 经 program_sink 落全局）；无名声明器
 *（`enum {M};` 纯定义）在 parse_var_decl_stmt 占位收尾（struct 同款）。 */
#include <stdio.h>
int main(void) {
    enum { A = 5, B = A + 2 };
    enum Tag { X, Y = 9 } z;
    z = Y;
    printf("%d %d %d\n", B, (int)z, A);
    return 0;
}
