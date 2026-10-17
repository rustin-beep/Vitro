// @category: baseline
// #137 缺陷 2 修复锚（2026-10-17）：typedef 别名在 struct/union 聚合
// 声明之后于文件作用域照常可用——真因是 parse_aggregate_trailing_
// globals 贪吃（trailing 声明器名单没排除 typedef 名，`ll` 被吞成
// struct P 的变量名）。union 同构、enum 无 trailing 不触发。
#include <stdio.h>
typedef long long ll;
struct P { int x; };
union Q { int a; double b; };
ll g = 3;
ll h(ll v) { return v * 2; }
int main(void) { printf("%lld %lld\n", g, h(g)); return (int)g; }
