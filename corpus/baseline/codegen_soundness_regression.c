#include <stdio.h>

/* T-P0-1/T-P0-2: 全局标量/数组初始化按目标类型编码位模式 */
double gd = 1;
float gf = 2;
long long ga[2] = {1, 2};
double gda[2] = {3, 4.5};
double gneg = -2;
static double gsd = 5;

/* T-P0-7: 不同函数的同名 static 局部变量 */
int f_static() { static int x = 1; x++; return x; }
int g_static() { static int x = 100; return x; }

/* F-P0-3: enum 初始化器常量折叠 */
enum { NEG = -1, ZERO, BIG = 1 + 2, SHIFT = 1 << 4 };

/* T-P0-4: struct char 成员赋值不越界 */
struct Q { int x; char c; };
struct Q gq = {111, 'A'};
int gnext = 777777;

int main(void) {
    /* T-P0-1/T-P0-2 */
    printf("1: gd=%f gf=%f ga=%lld,%lld gda=%f,%f gneg=%f gsd=%f\n",
           gd, gf, ga[0], ga[1], gda[0], gda[1], gneg, gsd);

    /* T-P0-3: 浮点与 long long 自增自减 */
    double d = 1.5; d++;
    float ff = 2.5f; ff--;
    long long q = 41; q++;
    double da[2] = {1.5, 2.5}; da[0]++; da[1]--;
    printf("2: d=%f ff=%f q=%lld da=%f,%f\n", d, ff, q, da[0], da[1]);

    /* T-P0-5: char 数组元素自增不进位污染 */
    char cs[2] = {55, 5}; cs[0]++;
    char c2[2] = {127, 9}; c2[0]++;
    printf("3: cs=%d,%d c2=%d,%d\n", cs[0], cs[1], c2[0], c2[1]);

    /* T-P0-6: 复合赋值内嵌套赋值 */
    int a[2] = {1, 2}, b[2] = {3, 4};
    a[0] += (b[0] = 5);
    printf("4: a0=%d b0=%d\n", a[0], b[0]);
    int x = 1, y = 2, z = 3;
    x = (y = (z = 9)) + 1;
    printf("5: x=%d y=%d z=%d\n", x, y, z);

    /* T-P0-7 */
    f_static(); f_static();
    printf("6: g_static=%d\n", g_static());

    /* F-P0-2: unsigned long long 修饰与值域 */
    unsigned long long ulla = 4000000000ULL;
    unsigned long long ullb = 8000000000ULL;
    printf("7: ulla=%lld ullb=%lld\n", ulla, ullb);

    /* F-P0-3 */
    printf("8: %d %d %d %d\n", NEG, ZERO, BIG, SHIFT);

    /* T-P0-4 */
    gq.c = 'B';
    printf("9: x=%d c=%c gnext=%d\n", gq.x, gq.c, gnext);

    /* T-P1-1: && / || 规范化为 0/1 */
    printf("10: %d %d %d %d\n", 5 && 3, 0 || 7, 2 && 2, 0 || 0);

    return 0;
}
