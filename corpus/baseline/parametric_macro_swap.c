// @category: baseline
#define SWAP(t,a,b) { t temp=a; a=b; b=temp; }
int main() { int x=1; int y=2; SWAP(int,x,y)
printf("%d %d", x, y); return 0; }
