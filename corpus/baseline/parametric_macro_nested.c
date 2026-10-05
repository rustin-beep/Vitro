// @category: baseline
#define MAX(a,b) ((a)>(b)?(a):(b))
#define MIN(a,b) ((a)<(b)?(a):(b))
int main() { printf("%d", MAX(1, MIN(2,3))); return 0; }
