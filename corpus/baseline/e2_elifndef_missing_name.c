// @category: baseline
// #432 A1 / M01 a2：#elifndef 缺宏名——error: macro name missing 且假分支
// 不激活（Win/WSL gcc+clang 四编译器 -E 一致：$$$$ 不进输出流）。
// Vitro 修复后：E1006 编译失败（stdout 空）——双侧编译失败判 match。
// 修复前：read_ident("") 空串 → contains("") 恒假 → #elifndef 取非激活
// 假分支（E1001×7 进流）、零缺名诊断（静默选错分支）。
#if 0
#error should not fire
#elifndef
$$$$$$$
#endif
int main(void){ return 0; }
