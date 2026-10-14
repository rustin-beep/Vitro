/* #83（2026-10-13 报 / 2026-10-14 修）：块作用域 static 声明 + typedef
 * 类型名（static size_t 计数 / static bool 标志 / 自定义 typedef / struct
 * typedef 全在内）——旧 stmt「标识符 标识符」未定义类型名诊断（issue #12
 * 通道）把存储类文本词 static 误作类型名报 E2003 拒绝；换内置类型
 * （static unsigned int）则正常。修复：static 后随已注册 typedef 名时排除
 * 该诊断、放行声明分支。static 局部语义（跨调用保值）一并验证。 */
#include <stdio.h>
#include <stdbool.h>
typedef int myint;
typedef struct { int a; } S;
static myint bump(void) {
    static myint count = 0; /* 块作用域 static + 自定义 typedef */
    count += 2;
    return count;
}
int main(void) {
    static S s;                 /* struct typedef */
    static bool flag = true;    /* stdbool 的 bool（typedef 注册） */
    static unsigned int u = 0;  /* 内置类型对照（现有绿防回归） */
    const static int y = 40;    /* 块内反序限定符（#77 同批） */
    s.a = 4;
    u = 1;
    bump();
    bump();
    printf("%d %d %d %d %d\n", s.a, flag, u, y, bump());
    return 0;
}
