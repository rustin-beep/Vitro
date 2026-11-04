// @category: chibicc_port
// source: chibicc test/function.c（MIT, © 2019 Rui Ueyama）— statement expression 拆变量
// topic: struct 按值传参/按值返回（小/中/大 struct、复合字面量返回）
#include <stdio.h>
typedef struct { int a,b; short c; char d; } Ty4;
typedef struct { int a; float b; double c; } Ty5;
typedef struct { unsigned char a[3]; } Ty6;
typedef struct { long a, b, c; } Ty7;
typedef struct { unsigned char a[10]; } Ty20;
typedef struct { unsigned char a[20]; } Ty21;
int struct_test4(Ty4 x, int n) { switch (n) { case 0: return x.a; case 1: return x.b; case 2: return (int)x.c; default: return (int)x.d; } }
int struct_test5(Ty5 x, int n) { switch (n) { case 0: return x.a; case 1: return (int)x.b; default: return (int)x.c; } }
int struct_test6(Ty6 x, int n) { return x.a[n]; }
int struct_test7(Ty7 x, int n) {
  if (n == 0) return (int)x.a; if (n == 1) return (int)x.b; return (int)x.c;
}
Ty4 mk4(void) { Ty4 r; r.a=10; r.b=20; r.c=30; r.d=40; return r; }
Ty5 mk5(void) { Ty5 r; r.a=10; r.b=20; r.c=30; return r; }
Ty6 mk6(void) { Ty6 r; r.a[0]=10; r.a[1]=20; r.a[2]=30; return r; }
Ty20 mk7(void) { Ty20 r; for (int i=0;i<10;i++) r.a[i]=(unsigned char)((i+1)*10); return r; }
Ty21 mk8(void) { Ty21 r; for (int i=0;i<20;i++) r.a[i]=(unsigned char)(i+1); return r; }
int main(void) {
  Ty4 x4 = {10,20,30,40};
  printf("%d %d %d %d\n", struct_test4(x4,0), struct_test4(x4,1), struct_test4(x4,2), struct_test4(x4,3));
  Ty5 x5 = {10,20,30};
  printf("%d %d %d\n", struct_test5(x5,0), struct_test5(x5,1), struct_test5(x5,2));
  Ty6 x6 = {10,20,30};
  printf("%d %d %d\n", struct_test6(x6,0), struct_test6(x6,1), struct_test6(x6,2));
  Ty7 x7 = {10,20,30};
  printf("%d %d %d\n", struct_test7(x7,0), struct_test7(x7,1), struct_test7(x7,2));
  printf("%d %d %d %d\n", mk4().a, mk4().b, (int)mk4().c, (int)mk4().d);
  printf("%d %d %d\n", mk5().a, (int)mk5().b, (int)mk5().c);
  printf("%d %d %d\n", mk6().a[0], mk6().a[1], mk6().a[2]);
  printf("%d %d %d\n", mk7().a[0], mk7().a[5], mk7().a[9]);
  printf("%d %d %d %d %d\n", mk8().a[0], mk8().a[4], mk8().a[9], mk8().a[14], mk8().a[19]);
  return 0;
}
