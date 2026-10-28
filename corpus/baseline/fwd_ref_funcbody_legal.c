// @category: decl_point_semantics
// #337（2026-10-28）负例：C11 6.2.1p4 声明点语义的合法面——extern 先行
// 声明（use 引用 e 时首声明在外置 extern 条目，定义在后文）/ tentative
// 先行（tent 首声明在前、实定义在后文——#343 修复前 declare_var 误报
// E3001）/ 函数原型先行（proto 作值 fpp 与调用两通道）/ 局部遮蔽
//（main 的 s 遮蔽后文全局 s）。双侧零诊断、输出一致。
// 注：tentative 数组（`int arr[];` 后文 `int arr[2]={...}` 补全）仍被
// E3081 拒（涉尺寸推断 + §6.9.2p3 size-1 完成语义）——残留面挂 #343。
#include <stdio.h>
extern int e;
int tent;
int proto(int);
int (*fpp)(int) = proto;

int use(void) { return e + proto(2) + fpp(3); }

int proto(int x) { return x * 10; }
int e = 5;
int main(void) {
    int s = 100;
    printf("%d %d %d %d %d\n", e, use(), fpp(4), s, tent);
    return 0;
}
int tent = 7;
int s = 3; /* 后文全局：无人前向引用（合法面锚） */
