// @category: baseline
// DIFF-LIB-PUTCHAR-01 / DIFF-EXIT-STDOUT-ENCODE-01 语料级差异锚（2026-10-04
// 转正，S8 收官清单 #7）：≥0x80 字节在 cmd/run 出口层双重 UTF-8 编码——
// 三防线 known 白名单锁定（修复转绿即红逼移除，双向监控）；<0x80 正常对照组。
#include <stdio.h>
int main() {
    putchar('A');
    putchar(128);
    putchar(200);
    putchar(255);
    putchar('Z');
    return 0;
}
