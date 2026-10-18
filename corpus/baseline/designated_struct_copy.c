// designated init 的 struct 变量值元素（#143 红锚，2026-10-18）：
// `.box = my_rect` 应整体拷贝嵌套 struct（修复前只拷首个标量字段，
// 其余静默留 0）；位置序同形与 `.field = my_point` 标量字段对照。
#include <stdio.h>
struct Point { int x, y; };
struct Rect { struct Point tl, br; };
struct Poly { struct Rect box; int n; struct Point pts[2]; };
int main(void) {
    struct Rect my_rect = { .tl = {10, 20}, .br = {100, 200} };
    struct Point my_pt = {7, 8};
    struct Poly p = { .box = my_rect, .n = 4, .pts = { {0, 1}, my_pt } };
    struct Rect positional = { my_rect.tl, my_rect.br };
    printf("box tl=(%d,%d) br=(%d,%d)\n", p.box.tl.x, p.box.tl.y,
           p.box.br.x, p.box.br.y);
    printf("n=%d pts=(%d,%d)(%d,%d)\n", p.n, p.pts[0].x, p.pts[0].y,
           p.pts[1].x, p.pts[1].y);
    printf("pos tl=(%d,%d) br=(%d,%d)\n", positional.tl.x, positional.tl.y,
           positional.br.x, positional.br.y);
    return 0;
}
