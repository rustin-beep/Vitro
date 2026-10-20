// @category: baseline
// #172 定案锚：stdout 直出通道对 C1 控制字节（0x80-0x9F 段）逐字节保真——
// 与 clang 一致（表观「输出整段消失」系探针判据 splitlines 把 U+0085 当
// 行界拆碎 NDJSON 帧，引擎无罪；0x0b/0x0c 亦同保真）。文件通道（fprintf
// 落盘回读）的高位字节重编码是 #66 已拍板差异面，另案在 gap。
#include <stdio.h>
int main(void) {
  printf("A");
  putchar(0x85);
  putchar(0x0b);
  putchar(0x0c);
  printf("B\n");
  return 0;
}
