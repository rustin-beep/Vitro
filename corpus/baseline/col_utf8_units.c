/* issue #242（2026-10-24 报/修）：token 列量纲统一 UTF-8 字节列——
 * 中文注释在前（pp 剥离为字节等宽空格，历史即字节列）与中文字符串
 * 在前（旧按字符计列 + make_token 字节反推 ⇒ 列基线左移）两类行的
 * 后续 token 列号统一为「行内 UTF-8 字节偏移 + 1」（source 包
 * SourceLoc 契约）。运行期输出不含量纲信息——本例的量纲行为面由
 * 词法 digest 的 TSV 列锁定（l1/l2），诊断列定位由锚测试承载。 */
#include <stdio.h>
int main(void) {
    const char *s = "中文字符串"; /* 行内中文字符串字面量 */
    /* 中文注释在前 */ int v = 7;
    printf("%s %d\n", s, v); /* 混合格：字符串实参 + 中文注释 */
    return 0;
}
