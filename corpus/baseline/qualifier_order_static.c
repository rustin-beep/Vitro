/* #77（2026-10-13 报 / 2026-10-14 修）：C11 §6.7.1 声明说明符任意序——
 * 限定符与存储类交错书写（const static int / int const x）与正序等价，
 * clang 22.1.4 / gcc 16.2.0 双收。旧 parse_base_type 限定符循环只收前置
 * const、不识 static 文本词（lexer 无关键字表）→ 声明器把 static 当变量
 * 名在类型 token 处炸 E2005 级联（文件作用域 25/250 例 LLM 语料命中、
 * 5 模型桶分布一致）。修复：限定符循环 + 尾部循环吞 static 记入
 * pending_static，global/func/local 三声明入口收割合并 is_static；参数
 * 列表收割即诊断（C 禁止参数存储类）。尾部限定符循环同批覆盖类型说明
 * 符之后的 const（int const x ≡ const int x）。 */
#include <stdio.h>
static const int A = 11;              /* 正序对照（防回归锚） */
const static int B = 22;              /* 文件作用域反序 */
const static int f(void) { return 3; } /* 函数定义反序 */
typedef int myint;
static int g(const int x) { return x; } /* 参数正序对照 */
static int h(int const x) { return x; } /* 参数限定符后置 */
int main(void) {
    const static int y = 5;   /* 块内反序 */
    myint const z = 7;        /* typedef 名 + 限定符后置 */
    int c = 0;
    c += A + B + f();
    c += g(1) + h(2);
    c += y + z;
    printf("%d\n", c);
    return 0;
}
