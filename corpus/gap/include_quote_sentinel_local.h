// quote-include 哨兵配套头（include_quote_sentinel.c 消费）。
// 两侧 vfs 注入当前结构性不命中（见同目录 include_quote_sentinel.c 头注释），
// 本头的实际内容不影响哨兵判定（两侧都读不到）；保留宏定义以备 vfs
// 修复后语义生效。
#define SENTINEL_VALUE 42
