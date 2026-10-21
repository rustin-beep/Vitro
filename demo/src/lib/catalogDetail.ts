// 诊断手册/运行期诊断共用的 catalog 附属内容（2026-10-18 前端改造批）。
//
// 这里只放**手册层**的手工对照（关联课 / 教学示例 / 码别名）；错误标题、
// 说明、常见原因仍以 error_catalog 为唯一真源，不在页面里手写第二份。
// 运行期 trap 面板与参考态详情页共用本文件，避免两处漂移。
"use strict";

/** 码 → 关联课（无关联不发明链接）。⚠️ 以 error_catalog 标题为准：
 *  E3061 是 Double-Free；E3083 才是 NULL 解引用（#178 后 trap 带码，
 *  关联 cases 的 e3061 课——该课 id 是历史名，勿改）；
 *  E3027 是 free 参数类型错误，不是「堆耗尽」。 */
export const RELATED: Record<string, string> = {
  E3023: "hello",
  E3060: "uaf",
  E3070: "e3070",
  E3083: "e3061",
  W1019: "macro",
  E1019: "macro",
};

// 宏副作用只在 catalog 以 W1019 登记（与引擎诊断码同形）；E1019 留同体兜底。
const MACRO_EXAMPLE = {
  bad: "#define BAD(x) ((x) + (x))\nint i = 1;\nint r = BAD(i++);   /* i++ 执行两次 */",
  fix: "int t = i++;\nint r = BAD(t);   /* 或改用内联函数避免宏副作用 */",
};

/** 示例代码（教学插图，不是引擎输出）。覆盖设计稿码表点名的 6 个高频条目；
 *  其余条目只呈现 catalog 真字段。E3060 另有 trap 三幕图。 */
export const EXAMPLES: Record<string, { bad: string; fix?: string }> = {
  E3060: {
    bad: "int *p = malloc(sizeof(int) * 4);\nfree(p);\np[0] = 1;   /* E3060：p 仍指向已释放块 */",
    fix: "free(p);\np = NULL;   /* 释放后立即断开别名 */",
  },
  E3023: {
    bad: "int main(void) {\n  int y = 5;\n  return y + z;   /* z 从未声明 */\n}",
    fix: "int z = 0;   /* 或检查拼写 / 作用域 / 头文件 */",
  },
  E3070: {
    bad: 'char buf[4] = {0};\nstrcpy(buf, "0123456789");   /* 写 11 字节进 4 字节缓冲 */',
    fix: 'char buf[16] = {0};\nsnprintf(buf, sizeof buf, "%s", "0123456789");   /* 先算容量，再截断写入 */',
  },
  E3061: {
    bad: "int *p = malloc(sizeof(int) * 4);\nfree(p);\nfree(p);   /* E3061：同一块释放两次 */",
    fix: "free(p);\np = NULL;   /* 第二次 free(NULL) 是安全的 no-op */",
  },
  E3027: {
    bad: "int x = 5;\nfree(42);   /* free 的参数必须是指针 */\nfree(&x);   /* 且必须是 malloc 族返回的地址 */",
    fix: "void *p = malloc(16);\nfree(p);\np = NULL;   /* p 只能来自 malloc/calloc/realloc */",
  },
  W1019: MACRO_EXAMPLE,
  E1019: MACRO_EXAMPLE,
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
