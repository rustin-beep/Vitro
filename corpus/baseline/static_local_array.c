// @category: baseline
int accum(int x) { static int arr[3] = {0,0,0}; static int idx = 0; arr[idx] += x; int sum = arr[0]+arr[1]+arr[2]; idx = (idx+1)%3; return sum; }
int main() { printf("%d %d %d", accum(1), accum(2), accum(3)); return 0; }
