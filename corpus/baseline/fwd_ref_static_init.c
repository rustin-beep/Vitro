// @category: static_addr_const
// #331（2026-10-27）：文件作用域初始化器前向引用——C11 6.2.1p4 声明点语义，
// clang 对三形态均报 use of undeclared identifier（编译失败，stdout 空）；
// Vitro 修复前零诊断静默接受（codegen pending 回填成合法地址），修复后
// E3023 编译失败——双侧编译失败判 match。
// 注：本用例是「双侧都拒」的诊断对拍锚；合法面（extern 先行声明 / 后向
// 引用 / 函数内 static 链）负锚见 extern_predecl_addr_init.c。
struct S { int f; };
int *p = &s;    /* 前向引用裸 &s：s 声明在后 */
int s = 1;
int *q = arr;   /* 前向引用数组名：arr 声明在后 */
int arr[3] = {1, 2, 3};
int *r = &st.f; /* 前向引用链形态 base：st 声明在后 */
struct S st = {7};
int main(void) { return 0; }
