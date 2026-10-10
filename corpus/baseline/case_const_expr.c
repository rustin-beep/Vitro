// @category: diagnostics
// #50 审阅 P1-1 修复锚：case 标签的常量表达式形态全族——负数字面量（一元
// Neg）、二元算术（1+2）、按位取反——结构层均为常量表达式，零 E3047
//（Clang 同判零诊断；原 Literal 单形态判据对前两者假阳性）。
int main() {
  int n = 1;
  switch (n) {
    case -1:
      break;
    case 1 + 2:
      break;
    case ~1:  // = -2（~0 == -1 会与首个 case 撞值——Clang 查 duplicate case）
      break;
    default:
      break;
  }
  return 0;
}
