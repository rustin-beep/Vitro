// demo 预置用例（second cut：协议面尽量全展示；文案以探针实跑响应为准）。
// referenceOutput / referenceTrap 口径：Clang golden 为 CI shadow 防线的
// 对拍真值，此处预置（浏览器内无 Clang，不做实时交叉编译——诚实边界）。
// configHint：运行该用例前先 config.set（如步数上限演示）。
// 源码排版为常规 C 风格（2026-10-01 用户拍板：编辑器里要像正常写的代码）；
// 排版不改 token 流语义，stdout golden 与 VM 步数不受影响（demo_smoke 复验）。
"use strict";
const DEMO_CASES = [
  {
    id: "hello",
    label: "Hello World",
    blurb: "最小程序：stdout + 返回码",
    source: `#include <stdio.h>

int main() {
  printf("Hello\\n");
  return 0;
}
`,
    referenceOutput: "Hello\n",
    referenceKind: "stdout",
  },
  {
    id: "bubble",
    label: "冒泡排序",
    blurb: "数组 + 循环 + 函数级语义（1012 步 VM 指令）",
    source: `#include <stdio.h>

int main() {
  int a[5] = {5, 3, 1, 4, 2};
  for (int i = 0; i < 4; i++)
    for (int j = 0; j < 4 - i; j++)
      if (a[j] > a[j + 1]) {
        int t = a[j];
        a[j] = a[j + 1];
        a[j + 1] = t;
      }
  for (int i = 0; i < 5; i++)
    printf("%d ", a[i]);
  printf("\\n");
  return 0;
}
`,
    referenceOutput: "1 2 3 4 5 \n",
    referenceKind: "stdout",
  },
  {
    id: "global_struct",
    label: "全局变量 · struct · 递归",
    blurb: "全局数组/结构体亮相内存地图 global 段（类型名 int[4] / struct Point），fib(10) 递归 2356 步",
    source: `#include <stdio.h>

struct Point {
  int x;
  int y;
};

int g_table[4] = {1, 2, 3, 4};
struct Point g_origin;

int fib(int n) {
  if (n < 2) return n;
  return fib(n - 1) + fib(n - 2);
}

int main() {
  struct Point p;
  p.x = g_table[3];
  p.y = fib(10);
  printf("%d %d\\n", p.x, p.y);
  return 0;
}
`,
    referenceOutput: "4 55\n",
    referenceKind: "stdout",
  },
  {
    id: "macro",
    label: "宏展开（preprocessor_trace）",
    blurb: "#define SQUARE(x)/N —— 编译期展开轨迹：SQUARE(N + 1) ⇒ ((3+1)*(3+1))",
    source: `#include <stdio.h>
#define SQUARE(x) ((x)*(x))
#define N 3

int main() {
  int s = SQUARE(N + 1);
  printf("%d\\n", s);
  return 0;
}
`,
    referenceOutput: "16\n",
    referenceKind: "stdout",
  },
  {
    id: "malloc_free",
    label: "malloc / free 生命周期",
    blurb: "堆分配 → 写入 → 释放进隔离区（看内存地图的 freed 块与 quarantine）",
    source: `#include <stdio.h>
#include <stdlib.h>

int main() {
  int* p = (int*)malloc(4 * sizeof(int));
  p[0] = 42;
  printf("p0=%d\\n", p[0]);
  free(p);
  printf("freed\\n");
  return 0;
}
`,
    referenceOutput: "p0=42\nfreed\n",
    referenceKind: "stdout",
  },
  {
    id: "uaf",
    label: "Use-After-Free（白箱死因报告）",
    blurb: "free 后继续读取——引擎给出时间轴 + 原因 + 解法的诊断（E3060）",
    source: `#include <stdio.h>
#include <stdlib.h>

int main() {
  int* p = (int*)malloc(sizeof(int));
  *p = 7;
  free(p);
  printf("%d\\n", *p);
  return 0;
}
`,
    referenceTrap: "E3060",
    referenceKind: "trap",
  },
  {
    id: "e3070",
    label: "栈缓冲区越界（E3070）",
    blurb: "strcpy 写 12 字节进 4 字节缓冲——受检写入拦截",
    source: `#include <string.h>

int main() {
  char buf[4];
  strcpy(buf, "hello world");
  return 0;
}
`,
    referenceTrap: "E3070",
    referenceKind: "trap",
  },
  {
    id: "e3061",
    label: "NULL 解引用（E3061）",
    blurb: "编译期 W3054 警告 + 运行期受检 trap",
    source: `#include <stdlib.h>

int main() {
  int* p = NULL;
  *p = 1;
  return 0;
}
`,
    referenceTrap: "NULL",
    referenceKind: "trap",
  },
  {
    id: "infinite",
    label: "死循环（步数上限演示）",
    blurb: "config.set 把步数上限压到 20000 → 引擎受检终止并解释「可能包含无限循环」",
    source: `#include <stdio.h>

int main() {
  long i = 0;
  while (1) {
    i = i + 1;
  }
  return 0;
}
`,
    configHint: { max_steps: 20000 },
    referenceTrap: "步数超过限制",
    referenceKind: "trap",
  },
  {
    id: "leak",
    label: "返回值附注（note 审计流）",
    blurb: "malloc 不 free——note 通道输出引擎附注「程序运行完成，返回值：5」（与 stdout 分流的审计流）",
    source: `#include <stdio.h>
#include <stdlib.h>

int main() {
  int* p = (int*)malloc(sizeof(int) * 4);
  p[0] = 1;
  printf("done\\n");
  return 5;
}
`,
    referenceOutput: "done\n",
    referenceKind: "stdout",
  },
  {
    id: "stderr_prog",
    label: "stderr 双流分流",
    blurb: "fprintf(stderr) 与 printf 分流入不同通道——页面分色展示（perror/assert 同走此流）",
    source: `#include <stdio.h>

int main() {
  fprintf(stderr, "to-stderr\\n");
  printf("out\\n");
  return 0;
}
`,
    referenceOutput: "out\n",
    referenceKind: "stdout",
  },
  {
    id: "argv_prog",
    label: "命令行参数（argv）",
    blurb: "run{argv:[…]}——argc/argv 直达程序；下方 argv 框可改参数再跑",
    source: `#include <stdio.h>

int main(int argc, char** argv) {
  printf("n=%d a1=%s\\n", argc, argv[1]);
  return 0;
}
`,
    argv: ["prog", "hello-arg"],
    referenceOutput: "n=2 a1=hello-arg\n",
    referenceKind: "stdout",
  },
  {
    id: "multi_file",
    label: "多文件编译（compile.files）",
    blurb: "两个编译单元（main.c 调用 utils.c 的 add）——编辑器内容即 main.c；跨文件链接跑通",
    source: `#include <stdio.h>

int add(int a, int b);

int main() {
  printf("sum=%d\\n", add(2, 40));
  return 0;
}
`,
    files: [
      {
        filename: "main.c",
        source: `#include <stdio.h>

int add(int a, int b);

int main() {
  printf("sum=%d\\n", add(2, 40));
  return 0;
}
`,
      },
      {
        filename: "utils.c",
        source: `int add(int a, int b) {
  return a + b;
}
`,
      },
    ],
    referenceOutput: "sum=42\n",
    referenceKind: "stdout",
  },
  {
    id: "scanf",
    label: "scanf 交互（waiting_input）",
    blurb: "运行等待输入 → 页面喂入 → 续跑到结束",
    source: `#include <stdio.h>

int main() {
  int n;
  scanf("%d", &n);
  printf("got %d", n);
  return 0;
}
`,
    referenceOutput: "got 42",
    referenceKind: "stdout",
  },
];
