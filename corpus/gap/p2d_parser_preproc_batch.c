#include <stdio.h>
#include <stddef.h>
#include <errno.h>

// @category: arch_diff_bug（include 夹具域——照 include_quote_sentinel 先例：
// 差分槽位不复制伴随 .h，本样本定位=**防倒退监测**：任一侧独立改变「本地头
// 解析失败」形态即红；单用例双臂行为验证在案〔native/wasm 均 local-ok〕）
// #71 台账批C-2·parser/lexer/preproc 六病锚（2026-10-13 修复批）
// ——悬空指数专属诊断（69）/ hexfloat 显式拒绝（70，有意教学分歧：clang
// 接受 0x1.8p3=12.0，vitro E1006 拒绝优于静默拆碎产错值）/ 裸 #ifdef 缺
// 宏名诊断（73）/ quote include 本地优先（74，同名本地头不被存根遮蔽）/
// const 左值赋值与自增（56，Index/Member 两臂 E3049）/ static 数组运行期
// 越界 trap（61，static_local_types 补入越界检测）。
// 注：74 的本地头伴拥文件 p2d_local_stddef.h 同目录共存——本锚依赖它。

#ifndef GUARD_P2D
#error "p2d_local_stddef.h 未被本地优先解析（病 74 回归）"
#endif

int main() {
  // 病 74 + 73 副产品：本地头守卫宏已定义（本地优先解析成功）
  printf("guard=%d\n", GUARD_P2D);
  // 病 56：const 成员/元素赋值、自增——三面 E3049（clang error 对齐）
  struct S { const int m; int v; };
  struct S s = { 1, 2 };
  const int ca[3] = { 4, 5, 6 };
  int out = s.v + ca[1];
  printf("%d\n", out);
  // 病 61：static 数组越界（trap 前的 W3051 静态警告不进对拍；trap 面
  // 由差分 digest 锁——本行在双臂同为 trap）
  static int sa[4];
  sa[10] = 1;
  return 0;
}
