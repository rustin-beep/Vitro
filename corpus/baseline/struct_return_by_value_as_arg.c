// @category: baseline
struct Vec { int x; int y; }; int area(struct Vec v) { return v.x * v.y; } struct Vec make_vec(int a, int b) { struct Vec v; v.x = a; v.y = b; return v; } int main() { printf("%d", area(make_vec(3,4))); return 0; }
