/*
 * @category: baseline
 * union 返回 + 变参消费（#515 审阅 P2 补牙，2026-11-15）：`U mkv(int, ...)`
 * 变参函数按值返回 union——锁定 gen_call_ptr 变参臂 user_named_count 的
 * union 返回减一判定（隐藏 __ret_ptr 占一参）。缺陷版（该臂只判
 * TK_Struct）va_arg 读位偏移一个 word：v=3（应 7）。此前语料全域无
 * 「变参 + union 返回」形状，反向突变零红（审阅 M3 实证）。clang 真值对拍。
 */
#include <stdio.h>
#include <stdarg.h>

typedef union { int i; double d; } U;

U mkv(int a, ...) {
  va_list ap; va_start(ap, a);
  int y = va_arg(ap, int);
  U u; u.i = a + y; return u;
}

int main(void) {
  U v = mkv(3, 4);
  printf("v=%d\n", v.i);      /* 7 */
  return 0;
}
