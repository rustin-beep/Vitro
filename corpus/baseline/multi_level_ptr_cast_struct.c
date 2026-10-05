// @category: baseline
struct Node { int x; }; int main() { struct Node n; n.x = 42; struct Node* p = &n; struct Node** pp = &p; void* vp = pp; struct Node** pp2 = (struct Node**)vp; printf("%d", (*pp2)->x); return 0; }
