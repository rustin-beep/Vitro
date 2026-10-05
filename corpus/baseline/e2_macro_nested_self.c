// @category: baseline
// E2：同宏嵌套（实参先行展开——原引擎实参不展开，此写法曾失败）
#include <stdio.h>
#define MAX(a, b) ((a) > (b) ? (a) : (b))
#define QUAD(x) ((x) * 4)
int main() {
    printf("%d %d\n", MAX(MAX(1, 5), 3), QUAD(QUAD(2)));
    return 0;
}
