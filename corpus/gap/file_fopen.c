// @category: file_io
// P5 gap 审计（2026-09-18）：此前漏 #include <stdio.h>，clang 报 undeclared
// FILE 而 shadow 判 gap_extension——是"漏头文件"伪装的扩展，非 VFS 语义差异。
// 补头转真对照：两侧 fopen 不存在的文件同返 NULL，预期 match。
#include <stdio.h>
// 2026-10-22 改名：test.txt 与 VFS 预置文件（#95）撞名——Vitro 侧恒能打开，
// clang 侧看磁盘有无，两侧语义天然分叉（fuzz 基线曾在根残留 test.txt 的
// 污染环境采成 AGREE，干净环境暴露为 WRONG_VALUE）。改用不撞名文件恢复
// 本语料「两侧 fopen 不存在的文件同返 NULL」的原始意图。
int main() { FILE* f = fopen("gap_missing.txt", "r"); if (f) { printf("ok"); fclose(f); } return 0; }
