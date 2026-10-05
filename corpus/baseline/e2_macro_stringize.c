// @category: baseline
// E2：# 字符串化与间接展开双语义（教材经典：STR(VER)="VER"，XSTR(VER)="9"）
#include <stdio.h>
#define STR(x) #x
#define XSTR(x) STR(x)
#define VER 9
int main() {
    printf("%s %s\n", STR(VER), XSTR(VER));
    return 0;
}
