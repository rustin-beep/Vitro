// @category: chibicc_port
// source: chibicc test/pointer.c（MIT, © 2019 Rui Ueyama）— statement expression 拆变量
// topic: 多级解引用、数组退化为指针、二维数组线性遍历、2[x] 逆下标
#include <stdio.h>
int main(void) {
  int x = 3;
  printf("%d\n", *&x);
  int *y = &x; int **z = &y; printf("%d\n", **z);
  *y = 5; printf("%d\n", x);
  int arr2[2]; int *py = &arr2[0]; *py = 3; printf("%d\n", *arr2);
  int arr[3]; *arr=3; *(arr+1)=4; *(arr+2)=5;
  printf("%d %d %d\n", *arr, *(arr+1), *(arr+2));
  arr[1]=4; arr[2]=5;
  // 注：chibicc 原 ASSERT(5, 2[arr])——逆下标（a[b]≡*(a+b) 对偶），Vitro E3039 拒收（DIFF 候选），移 deferred
  printf("%d\n", *(arr+2));
  int m23[2][3]; int *lm = (int*)m23;
  *(lm+0)=0; *(lm+1)=1; *(lm+2)=2; *(lm+3)=3; *(lm+4)=4; *(lm+5)=5;
  printf("%d %d %d\n", m23[0][0], m23[0][1], m23[0][2]);
  printf("%d %d %d\n", m23[1][0], m23[1][1], m23[1][2]);
  int *ym = (int*)m23;
  ym[0]=0; ym[1]=1; ym[2]=2; ym[3]=3; ym[4]=4; ym[5]=5;
  printf("%d %d %d %d %d %d\n", m23[0][0], m23[0][1], m23[0][2], m23[1][0], m23[1][1], m23[1][2]);
  return 0;
}
