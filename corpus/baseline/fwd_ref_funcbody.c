// @category: decl_point_semantics
// #337（2026-10-28）：函数体前向引用后文全局——C11 6.2.1p4 声明点语义，
// clang 报 use of undeclared identifier（编译失败，stdout 空）；Vitro
// 修复前零诊断静默通过（Pass 2.5 全量登记后 lookup_var 直接命中），
// 修复后 E3023 编译失败——双侧编译失败判 match。
// 注：合法面（extern/tentative 先行、原型先行、局部遮蔽）负锚见
// fwd_ref_funcbody_legal.c；#331 的初始化器地址常量族见
// fwd_ref_static_init.c。
int use_late(void) { return s; } /* 前向引用后文普通全局 */
int s = 3;
int main(void) { return 0; }
