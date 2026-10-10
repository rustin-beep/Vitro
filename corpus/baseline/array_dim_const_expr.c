/* #64（2026-10-11 修）：宏+二元表达式的数组维度是 C11 §6.6 整型常量
 * 表达式、非 VLA——旧 array_dim_info 对 Binary 一律判 VLA，致全局/静态
 * 局部一维与二维、首维表达式、括号包裹各形态在 compile_and_report 管线
 * 报「不支持 VLA」+级联（CLI 文本模式 native/exe 走该管线；gateway 帧链
 * 同判但出口吞诊断为 ok=false——backend 恰好代理壳/exe 双入口，非后端
 * 差）。const_int_of 常量求值（字面/一元负·位非/二元算术·位·移位）接入
 * 维度折叠。v6（真未定义宏维度）非常量仍判 VLA——其「未定义标识符」
 * 诊断缺位与 gateway 空诊断出口病另案（#64 尾巴）。 */
#define W 21
#define H 15
static char grid[H][W + 1];
static char buf[W + 1];
int main(void) {
    static char g2[H][W + 1];
    char g3[H][W + 1];
    grid[0][0] = 'x';
    buf[0] = 'y';
    g2[0][0] = g3[0][0] = 'z';
    printf("%c%c%c%c\n", grid[0][0], buf[0], g2[0][0], g3[0][0]);
    return 0;
}
