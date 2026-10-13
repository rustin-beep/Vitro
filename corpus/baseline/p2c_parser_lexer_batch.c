#include <stdio.h>

// @category: #71 台账批C·parser/lexer 组六病锚（2026-10-13 修复批）——
// long long int 三连拼写（64）/ typedef 多声明器（65，链表教学高频）/
// enum 三元与 cast 初始化（66）/ # 字符串化保引号转义（68）/ hex 转义按
// 值域判（71，'\x004' 合法）/ null 普通标识符（72，NULL 宏与 nullptr C23
// 保留）。余 69/70/73/74/56/61 批C-2。

typedef struct Node { int v; struct Node* next; } Node, *NodePtr;

enum E { A = 1 ? 2 : 3, B = (int)4.0 };

#define STR(x) #x

int main() {
  long long int x = 5;
  Node n;
  NodePtr p = &n;
  n.v = 7;
  printf("%lld %d\n", x, p->v);
  printf("%d %d\n", A, B);
  printf("%s\n", STR("hi"));
  char h = '\x004';
  int null = 5;
  printf("%d %d\n", h, null);
  return 0;
}
