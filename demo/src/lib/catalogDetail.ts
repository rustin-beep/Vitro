// 诊断手册/运行期诊断共用的 catalog 附属内容（2026-10-18 前端改造批）。
//
// 这里只放**手册层**的手工对照（关联课 / 教学示例 / 码别名）；错误标题、
// 说明、常见原因仍以 error_catalog 为唯一真源，不在页面里手写第二份。
// 运行期 trap 面板与参考态详情页共用本文件，避免两处漂移。
"use strict";

/** 码 → 关联课（无关联不发明链接）。⚠️ 以 error_catalog 标题为准：
 *  E3061 是 Double-Free；E3083 才是 NULL 解引用（#178 后 trap 带码，
 *  关联 cases 的 e3061 课——该课 id 是历史名，勿改）；
 *  E3027 是 free 参数类型错误，不是「堆耗尽」。
 *
 *  ⚠️ 键名 = error_catalog 的 **code_str 原样**（E/W/H 前缀随引擎登记，
 *  不是「一律 E」）：1019→W1019、3051/3052→W3051/W3052、
 *  3062/3063/3064/3068→W3062/W3063/W3064/W3068、3069→H3069。
 *  页面按 card.code_str 取键（RefScreen），写 E 前缀的键永远命中不到。
 *
 *  关联课 id 取自 demo 课表真源（cases.js / algorithms.js）；没有对应课
 *  就留空——不发明链接。 */
export const RELATED: Record<string, string> = {
  E3021: "pointer",
  E3023: "hello",
  E3024: "malloc_free",
  E3025: "malloc_free",
  E3060: "uaf",
  E3067: "pointer",
  E3070: "e3070",
  E3072: "global_struct",
  E3083: "e3061",
  H3069: "bubble",
  W1019: "macro",
  W3051: "bubble",
  W3052: "bubble_sort",
  W3062: "double_avg",
  W3063: "scanf",
  W3068: "stderr_prog",
};

// 宏副作用只在 catalog 以 W1019 登记（与引擎诊断码同形）。
const MACRO_EXAMPLE = {
  bad: "#define BAD(x) ((x) + (x))\nint i = 1;\nint r = BAD(i++);   /* i++ 执行两次 */",
  fix: "int t = i++;\nint r = BAD(t);   /* 或改用内联函数避免宏副作用 */",
};

/** 示例代码（教学插图，不是引擎输出）。键名同 RELATED：必须是 error_catalog
 *  的 code_str 原样（W/H 前缀随引擎登记）。
 *
 *  新增 19 条 BAD 都**实测触发**该码（vitro compile/run --json，取 code_str），
 *  每条 FIX 都实测不再报该码且零诊断零 trap（2026-10-23 js/native/wasm
 *  三臂对拍一致）；这 19 条 BAD/FIX 是 3–8 行可独立编译的完整 C 程序。
 *  既有 6 条保留教学片段形态（E3023/E3027 的 fix 是一行片段），未按完整
 *  程序重写，只保证运行时字符串零回归。
 *  未覆盖的码不硬凑——没有可靠 BAD 就留空（页面走 catalog 说明兜底）。 */
export const EXAMPLES: Record<string, { bad: string; fix?: string }> = {
  E3021: {
    bad: `int main(void) {
  int x = 1;
  int y = *x;   /* E3021：x 不是指针，不能用 * 解引用 */
  return y;
}`,
    fix: `int main(void) {
  int x = 1;
  int *p = &x;   /* 取地址得到指针，再解引用 */
  int y = *p;
  return y;
}`,
  },
  E3023: {
    bad: "int main(void) {\n  int y = 5;\n  return y + z;   /* z 从未声明 */\n}",
    fix: "int z = 0;   /* 或检查拼写 / 作用域 / 头文件 */",
  },
  E3024: {
    bad: `#include <stdlib.h>
int main(void) {
  int *p = malloc(sizeof(int), 4);   /* E3024：malloc 只接受一个字节数参数 */
  return p ? 0 : 1;
}`,
    fix: `#include <stdlib.h>
int main(void) {
  int *p = (int *)malloc(sizeof(int) * 4);   /* 字节数一次算清，只传一个参数 */
  if (p == NULL) return 1;
  free(p);
  return 0;
}`,
  },
  E3025: {
    bad: `#include <stdlib.h>
int main(void) {
  int *p = malloc("abcd");   /* E3025：malloc 的参数必须是字节数（整数） */
  return p ? 0 : 1;
}`,
    fix: `#include <stdlib.h>
int main(void) {
  int *p = (int *)malloc(4 * sizeof(int));   /* 传字节数，不传字符串 */
  if (p == NULL) return 1;
  free(p);
  return 0;
}`,
  },
  E3027: {
    bad: "int x = 5;\nfree(42);   /* free 的参数必须是指针 */\nfree(&x);   /* 且必须是 malloc 族返回的地址 */",
    fix: "void *p = malloc(16);\nfree(p);\np = NULL;   /* p 只能来自 malloc/calloc/realloc */",
  },
  E3049: {
    bad: `int main(void) {
  const int v = 1;
  v = 2;   /* E3049：const 变量初始化后不能再赋值 */
  return v;
}`,
    fix: `int main(void) {
  int v = 1;
  v = 2;   /* 需要改值就别声明成 const */
  return v;
}`,
  },
  E3054: {
    bad: `int main(void) {
  int *p = 1234;   /* E3054：整数被隐式转换成指针 */
  return p == 0 ? 1 : 0;
}`,
    fix: `#include <stdlib.h>
int main(void) {
  int *p = (int *)malloc(sizeof(int));   /* 用分配得到的真实地址 */
  if (p == NULL) return 1;
  *p = 1;
  free(p);
  return 0;
}`,
  },
  E3060: {
    bad: "int *p = malloc(sizeof(int) * 4);\nfree(p);\np[0] = 1;   /* E3060：p 仍指向已释放块 */",
    fix: "free(p);\np = NULL;   /* 释放后立即断开别名 */",
  },
  E3061: {
    bad: "int *p = malloc(sizeof(int) * 4);\nfree(p);\nfree(p);   /* E3061：同一块释放两次 */",
    fix: "free(p);\np = NULL;   /* 第二次 free(NULL) 是安全的 no-op */",
  },
  E3065: {
    bad: `int main(void) {
  const int v = 1;
  const int *p = &v;
  *p = 2;   /* E3065：不能通过 const 指针修改 const 数据 */
  return 0;
}`,
    fix: `int main(void) {
  int v = 1;
  int *p = &v;   /* 要修改就别把数据声明成 const */
  *p = 2;
  return v;
}`,
  },
  E3066: {
    bad: `int main(void) {
  int x = 1;
  x();   /* E3066：x 不是函数，不能被调用 */
  return 0;
}`,
    fix: `int main(void) {
  int x = 1;
  return x;   /* x 是 int，返回它的值即可 */
}`,
  },
  E3067: {
    bad: `int main(void) {
  double d = 1.0;
  int *p = &d;   /* E3067：double* 与 int* 不是兼容指针类型 */
  return 0;
}`,
    fix: `int main(void) {
  double d = 1.0;
  double *p = &d;   /* 同基类型的指针才能直接赋值 */
  return *p > 0.0 ? 0 : 1;
}`,
  },
  E3070: {
    bad: 'char buf[4] = {0};\nstrcpy(buf, "0123456789");   /* 写 11 字节进 4 字节缓冲 */',
    fix: 'char buf[16] = {0};\nsnprintf(buf, sizeof buf, "%s", "0123456789");   /* 先算容量，再截断写入 */',
  },
  E3071: {
    bad: `int main(void) {
  goto done;   /* E3071：done 标签在函数内不存在 */
  return 0;
}`,
    fix: `int main(void) {
  goto done;   /* 跳转目标必须在同一函数内定义 */
done:
  return 0;
}`,
  },
  E3072: {
    bad: `struct Node {
  int value;
  struct Node next;   /* E3072：结构体按值包含自身，大小无法计算 */
};
int main(void) {
  return 0;
}`,
    fix: `struct Node {
  int value;
  struct Node *next;   /* 改用指针成员，自包含才可计算大小 */
};
int main(void) {
  return 0;
}`,
  },
  E3073: {
    bad: `#include <stdlib.h>
int main(void) {
  char *t = strtok("a,b", ",");   /* E3073：strtok 不在教学子集支持面内 */
  return t ? 0 : 1;
}`,
    fix: `#include <string.h>
int main(void) {
  const char *s = "a,b";
  const char *p = strchr(s, ',');   /* 用支持面内的 strchr 替代 */
  return p ? 0 : 1;
}`,
  },
  E3083: {
    bad: `int main(void) {
  int *p = NULL;
  *p = 1;   /* E3083：向 NULL 指针写入 */
  return 0;
}`,
    fix: `#include <stdlib.h>
int main(void) {
  int *p = (int *)malloc(sizeof(int));
  if (p == NULL) return 1;   /* 分配失败先返回，不解引用 */
  *p = 1;
  free(p);
  return 0;
}`,
  },
  H3069: {
    bad: `#include <stdio.h>
int main(void) {
  int a[4] = {1, 2, 3, 4};
  int *p = a;
  for (; p <= a + 4; p++)   /* H3069：a+4 是尾后地址，<= 会多跑一次 */
    printf("%d\\n", *p);
  return 0;
}`,
    fix: `#include <stdio.h>
int main(void) {
  int a[4] = {1, 2, 3, 4};
  int *p = a;
  for (; p < a + 4; p++)   /* 4 个元素用 <（有效范围 a[0]~a[3]） */
    printf("%d\\n", *p);
  return 0;
}`,
  },
  W1019: MACRO_EXAMPLE,
  W3051: {
    bad: `int main(void) {
  int a[4] = {0};
  a[4] = 1;   /* W3051：a 只有 4 个元素，有效下标是 0~3 */
  return a[0];
}`,
    fix: `int main(void) {
  int a[4] = {0};
  a[3] = 1;   /* 有效下标是 0~3 */
  return a[0];
}`,
  },
  W3052: {
    bad: `int first(int a[]) {
  return (int)sizeof(a);   /* W3052：形参里的数组已退化为指针 */
}
int main(void) {
  int arr[4] = {0};
  return first(arr) == 0 ? 1 : 0;
}`,
    fix: `int first(int *a, int n) {
  return n * (int)sizeof(int);   /* 显式传长度，不依赖 sizeof(a) */
}
int main(void) {
  int arr[4] = {0};
  return first(arr, 4) == 0 ? 1 : 0;
}`,
  },
  W3062: {
    bad: `#include <stdio.h>
int main(void) {
  printf("%d\\n", "hello");   /* W3062：%d 对应 int，这里传了字符串 */
  return 0;
}`,
    fix: `#include <stdio.h>
int main(void) {
  printf("%s\\n", "hello");   /* %s 对应字符串指针 */
  return 0;
}`,
  },
  W3063: {
    bad: `#include <stdio.h>
int main(void) {
  double n = 0.0;
  scanf("%d", &n);   /* W3063：%d 读 int，却给了 double* */
  return 0;
}`,
    fix: `#include <stdio.h>
int main(void) {
  double n = 0.0;
  scanf("%lf", &n);   /* %lf 对应 double */
  return 0;
}`,
  },
  // ⚠️ catalog 3064 当前标题仍写「双重指针转换」，与本条「指针 ↔ 浮点」语义
  // 不符；示例按引擎真实发射点保留，待 catalog 数据批修标题（2026-10-23 审阅登记）。
  W3064: {
    bad: `int main(void) {
  double d = 1.0;
  int *p = (int *)d;   /* W3064：指针 ↔ 浮点 强制转换是实现定义行为 */
  return p == 0 ? 1 : 0;
}`,
    fix: `int main(void) {
  double d = 1.0;
  int n = (int)d;   /* 浮点转整数是良定义的，别把浮点当地址 */
  return n > 0 ? 0 : 1;
}`,
  },
  W3068: {
    bad: `#include <stdio.h>
int main(void) {
  fseek(1, 0, SEEK_SET);   /* W3068：文件指针位不能传普通整数 */
  return 0;
}`,
    fix: `#include <stdio.h>
int main(void) {
  fseek(stdin, 0, SEEK_SET);   /* 文件指针位传标准流 */
  return 0;
}`,
  },
};

/** 诊断码 ↔ 码表码兜底（当前 catalog 用 W1019；W/E 互为别名防归一化漂移）。 */
export function canonicalCode(code: string, has: (c: string) => boolean): string {
  if (has(code)) return code;
  const alt = code.startsWith("W") ? "E" + code.slice(1) : code.startsWith("E") ? "W" + code.slice(1) : "";
  return alt && has(alt) ? alt : code;
}

/** 运行期 trap 的示意图形别（纯教学示意，不是引擎输出）。 */
export type TrapKind = "uaf" | "overflow" | "double-free" | "free-type" | "null";
export function trapKind(code: string): TrapKind {
  if (code === "E3060") return "uaf";
  if (code === "E3070") return "overflow";
  if (code === "E3061") return "double-free";
  if (code === "E3027") return "free-type";
  return "null";
}
