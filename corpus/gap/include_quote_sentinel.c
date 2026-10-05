// @category: include
// quote-include 哨兵（T5-c，2026-09-20）：本地头解析面的**偶然对齐**暴露
// 用例——两侧 dump 出口（dump_ast / dump_typeck / Rust serve 同名方法）
// 的目录级 vfs 注入与 tokenize base_dir 结构性不命中（候选键 "./x.h" vs
// vfs 绝对路径键），两侧同无法解析本地头 → 同 ok=false / 同空诊断序列。
// 本样本入语料后该"两侧同失败"受 parser_diff + typeck_diff 常驻监测：
// 任一侧独立修好或改坏 vfs 解析，对拍即红——防偶然一致掩盖真实分叉。
// （单文件请求模式下 quote-include 同样无法解析——候选基目录不存在，
// 与目录模式殊途同归；两侧一致即绿。）
#include "include_quote_sentinel_local.h"
int main() { return SENTINEL_VALUE; }
