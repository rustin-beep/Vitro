// @category: baseline
// #432 A4 防过剥守卫（H01 动机形态）：裸 {…} 宏在 if-else 中展开为
// {…}; 空语句 + 悬空 else——标准 C 本就编译错误（clang expected
// expression / gcc else without a previous if，stdout 空）。Vitro 修复后
// E2003 同拒（双侧编译失败判 match）；修复前 do-while 包装静默改写为
// 可编译（标准报错形态被静默放行 + break/continue 反转）。
#define SWAP(t,a,b) {t tmp=a;a=b;b=tmp;}
int main() {
  int x = 1, y = 2;
  if (x > y) SWAP(int,x,y); else x = 0;
  return x + y;
}
