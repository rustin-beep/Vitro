// @category: file_io
// P5 gap 审计（2026-09-18）：补漏掉的 stdio.h（此前 gap_extension 判定是
// 漏头文件伪装，非 VFS 扩展语义）。两侧 fopen 失败返 NULL 后 fread(NULL)
// 行为：clang 崩溃/UB，Vitro trap——具体分类以 shadow 实跑为准。
#include <stdio.h>
// 2026-10-22 改名：test.txt 与 VFS 预置文件（#95）撞名——Vitro 侧恒能打开，
// clang 侧看磁盘有无，两侧语义天然分叉（fuzz 基线曾在根残留 test.txt 的
// 污染环境采成 AGREE，干净环境暴露为 WRONG_VALUE）。改用不撞名文件恢复
// 本语料「两侧 fopen 不存在的文件同返 NULL」的原始意图。
int main() { FILE* f = fopen("gap_missing.txt", "r"); char buf[20]; buf[0] = 0; if (f) { fread(buf, 1, 5, f); buf[5] = 0; fclose(f); } printf("%s", buf); return 0; }
