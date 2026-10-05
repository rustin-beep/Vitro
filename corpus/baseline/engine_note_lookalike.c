/* E-P1-5 回归：程序自己打印与「引擎附注」逐字相同的文本。
 *
 * 背景：引擎此前把程序 stdout 与引擎附注（运行完成提示、内存泄漏报告）追加进同一条
 * 字节流，Shadow Verification 驱动只能靠文本正则清洗：
 *     re.sub(r'程序运行完成，返回值：-?\d+\n?', '', out)
 *     re.sub(r'===== 内存泄漏检测报告 =====.*?={30,}', '', out, flags=DOTALL)
 * 程序自己打印这类文本时（学生打印自定义调试信息，教学上完全合理），真实输出会被整段
 * 删除 → 与 Clang golden 不一致 → 一条本来正确的用例被记成 output_gap（假阳性）。
 *
 * 现在引擎按通道分离输出（stdout / stderr / note），本用例验证：
 *   1. 程序打印的每一行都原样出现在 stdout（不得被"清洗"掉）；
 *   2. 引擎附注（malloc(0) 教学警告、运行完成提示）走 note 通道，不得混入 stdout；
 *   3. stderr 与 stdout 分流；
 *   4. stdout 无尾换行收尾时，引擎附注不得粘到最后一行上。
 */
#include <stdio.h>
#include <stdlib.h>

int main(void) {
    printf("程序运行完成，返回值：7\n");
    printf("===== 内存泄漏检测报告 =====\n");
    printf("发现 1 处未释放的堆内存，共 4 字节：\n");
    printf("  - 第 12 行的 malloc 分配了 4 字节 (addr=0x1000)，未被 free\n");
    printf("==============================\n");

    /* 触发引擎附注（malloc(0) 教学警告）：必须走 note 通道。 */
    void *p = malloc(0);
    (void)p;
    printf("malloc(0) call done\n");

    /* stderr 与 stdout 分流：此行不得进入 stdout。 */
    fprintf(stderr, "[stderr] 不属于 stdout\n");

    /* 无尾换行收尾：旧实现会把引擎提示粘到最后一行上。 */
    fputs("tail-no-newline", stdout);
    return 0;
}
