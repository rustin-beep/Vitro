// @category: baseline
// 绿锚（#437 即可入库批）：审阅 v2 M22 p01「strncpy/strncat 边界矩阵 30 断言」无发现面——截断不补 NUL/
// 源短补零/零长/空源/strncat 追加族/返回值三方一致。来源：tmp/review_v2_M22/probes/p01_strncpy.c
#include <stdio.h>
#include <string.h>
void dump(const char*tag, char*b, int n){printf("%s:",tag);for(int i=0;i<n;i++)printf(" %02X",(unsigned char)b[i]);printf("\n");}
int main(void){
  char b[8];
  memset(b,'X',8); strncpy(b,"abcdef",3); dump("t1",b,8);   // 源更长：截到 n 不补 NUL
  memset(b,'X',8); strncpy(b,"abc",3); dump("t2",b,8);      // 源==n
  memset(b,'X',8); strncpy(b,"ab",6); dump("t3",b,8);       // 源更短：补零到 n
  memset(b,'X',8); strncpy(b,"abc",0); dump("t4",b,8);      // n=0
  memset(b,'X',8); strncpy(b,"abcde",4); dump("t5",b,8);    // 源恰好 n-1
  memset(b,'X',8); strncpy(b,"",3); dump("t6",b,8);         // 空源
  memset(b,0,8); strcpy(b,"ab"); strncat(b,"cdef",2); dump("t7",b,5);  // n < srclen
  memset(b,0,8); strcpy(b,"ab"); strncat(b,"cd",5); dump("t8",b,5);    // n > srclen（到 NUL 止）
  memset(b,'X',8); b[2]=0; strcpy(b,"ab"); strncat(b,"cd",0); dump("t9",b,3); // n=0 只补终止符
  printf("t10 %d\n", strncpy(b,"q",1)==b);                   // 返回值 = dest
  return 0;
}
