// @category: decl_point_semantics
// #337（2026-10-28，PR #339 审阅 P3-2 挂账）：函数名**作值**前向引用——
// clang 对 `int (*fp)(void) = f;`（f 后文声明）报 use of undeclared
// identifier（作值面无隐式声明回退；调用面是 C99 隐式声明废弃 warning，
// 不同通道）。Vitro 修复前 funcs 表 Pass 2 全量登记直接放行，修复后
// E3023 编译失败——双侧编译失败判 match。含全局初始化器与函数体内
// 两形态（static 函数同族连坐）。
int (*fp)(void) = f;                  /* 形态一：全局初始化器作值前向 */
int f(void) { return 1; }
static int h(void) { return 2; }
int main(void) {
    int (*hp)(void) = h;              /* 形态二：函数体内 static 函数名作值前向 */
    return fp() + hp();
}
