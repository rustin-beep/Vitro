// @category: printf_scanf_type_mismatch
// W3062/W3063 格式-参数类型错配的**诊断面**语料（2026-10-03 审阅 P2-2 补；
// SEVERITY-FORMAT 销案批四 2026-10-07 降级翻转）：
// 合法语料全绿程序盖不到消息文案（含参数序号）——单靠 wbtest 锚是单点兜底，
// 同族文案漂移（如序号算式再动）语料面不可见。本用例经 typeck_diff 的
// 诊断序列对拍锁文案。**批四起 3062/3063 降 warning 编译放行（Clang
// -Wformat 口径，原 error 系 oracle 照搬）**——降级后 Clang 侧因无 include
// 的 scanf 隐式声明在 Windows/MSVC 链接域 undefined symbol（clang_direct
// known_direct 登记在案），运行期输出为 UB 域无对拍意义，仍以诊断面为锚。
int main() {
    int a = 1;
    double d = 1.0;
    printf("%f", a);   // E3062：第 2 个参数类型 'int' 不匹配 %f
    printf("%d", d);   // E3062：第 2 个参数类型 'double' 不匹配 %d
    scanf("%d", &d);   // E3063：第 2 个参数 pointee double 不匹配 %d
    return 0;
}
