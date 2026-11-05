// @category: baseline
// #432 A1 / M01 a4：#elifdef 缺宏名——error: macro name missing 且块不激活
//（四编译器一致）。Vitro 修复后：E1006 编译失败——双侧判 match。
// 修复前：COMPILE-OK 零诊断静默吞块。
#ifdef NOT_DEFINED_EVER
int a;
#elifdef
int x;
#endif
int main(void){ return 0; }
