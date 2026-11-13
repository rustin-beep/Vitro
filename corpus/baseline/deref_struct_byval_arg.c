// @category: baseline
// #147: *指针 直接作 struct 按值实参——Deref(TK_Struct) 须地址直通
//(修前双重解引用:拷贝源=首字段值,必 TRAP E3083;fp->y 成员路径作回归对照)
#include <stdio.h>
typedef struct Point { int x; int y; } Point;
static int take(Point p) { return p.x * 10 + p.y; }
int main(void) {
  Point pt = {7, 9};
  Point *fp = &pt;
  printf("byval=%d member=%d\n", take(*fp), fp->y);
  return 0;
}
