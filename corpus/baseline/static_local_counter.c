// @category: baseline
int count() { static int c = 0; c++; return c; }
int main() { printf("%d %d %d", count(), count(), count()); return 0; }
