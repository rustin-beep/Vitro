// demo 纯函数锚（app.js 拆分批 2026-10-04，refs #28）——node --test 零构建。
// 锚位对历史 bug 窝点：buildCallTree 的 trie 增量语义（renderCallTree 参数
// 错位事故的函数层）、isArrayAnimCase 声明形态（下标访问不误标 + 紧凑声明
// 存量 bug 修复锁）、latin1ToUtf8 字节还原（delta 通道 mojibake 坑）、
// tokenizeC/highlightLines 编辑器双层、heapSpanOf 内存跨度、esc 转义。
// 【锚驱动战果记录】首批锚抓到三真问题：editor 漏 import esc（拆分接线
// 遗漏）、calltree 漏 import esc、isArrayAnimCase 紧凑声明不命中（存量 bug）。
import { test } from "node:test";
import assert from "node:assert/strict";

import { latin1ToUtf8, esc, isArrayAnimCase } from "../js/util.ts";
import { tokenizeC, highlightLines } from "../js/editor.ts";
import { buildCallTree } from "../js/calltree.ts";
import { heapSpanOf } from "../js/memory.ts";
import { toPosix, isSourceFile, shouldSkipDir, orderForCompile } from "../js/workspace.ts";

// ── buildCallTree：路径序列 → trie（窝点：循环迭代同节点累 hit；返回后再
// 调 = 新兄弟节点；空栈帧挂根）——renderCallTree 参数错位事故的函数层锚
test("buildCallTree：fib 形路径的增量 trie 语义", () => {
  const frames = [
    { step_index: 0, call_stack: [] },
    { step_index: 1, call_stack: [{ func_name: "main" }] },
    { step_index: 2, call_stack: [{ func_name: "main" }, { func_name: "fib" }] },
    { step_index: 3, call_stack: [{ func_name: "main" }, { func_name: "fib" }] },
    { step_index: 4, call_stack: [{ func_name: "main" }] },
    { step_index: 5, call_stack: [{ func_name: "main" }, { func_name: "fib" }] },
  ];
  const { root, frameNode } = buildCallTree(frames);
  assert.equal(root.name, "prog");
  assert.equal(root.children.length, 1);
  const main = root.children[0];
  assert.equal(main.name, "main");
  assert.equal(main.hitCount, 2); // hitCount=路径终点语义（帧 1/4）
  assert.equal(main.children.length, 2);
  assert.equal(main.children[0].hitCount, 2);
  assert.equal(main.children[1].hitCount, 1);
  assert.equal(frameNode[0], root);
  assert.equal(frameNode[3], main.children[0]);
  assert.equal(frameNode[5], main.children[1]);
  assert.equal(main.children[0].parent, main);
});

// ── isArrayAnimCase：声明命中（含紧凑形态——存量 bug 修复锁）/ 访问不误标
test("isArrayAnimCase：声明命中 / 访问不误标", () => {
  assert.equal(isArrayAnimCase("int main() { int a[8]; a[0] = 1; return 0; }"), true);
  assert.equal(isArrayAnimCase("int main() { int a [8]; }"), true);
  assert.equal(isArrayAnimCase("int main() { int x = a[0]; return x; }"), false);
  assert.equal(isArrayAnimCase("int main() { char buf[64]; return 0; }"), true);
  assert.equal(isArrayAnimCase("int main() { return 0; }"), false);
  assert.equal(isArrayAnimCase("unsigned long big[10];"), true);
  assert.equal(isArrayAnimCase("int* p[4];"), true);
  assert.equal(isArrayAnimCase("int **m[2];"), true);
  assert.equal(isArrayAnimCase("int p;"), false);
  assert.equal(isArrayAnimCase("integer arr[3];"), false);
});

// ── latin1ToUtf8：每字符一字节的 mojibake 还原（delta 通道坑正身）
test("latin1ToUtf8：中文 UTF-8 折回还原", () => {
  const text = "你好";
  const bytes = new TextEncoder().encode(text);
  let folded = "";
  for (const b of bytes) folded += String.fromCharCode(b);
  assert.equal(latin1ToUtf8(folded), text);
  assert.equal(latin1ToUtf8("plain ascii"), "plain ascii");
  assert.equal(latin1ToUtf8(""), "");
});

// ── tokenizeC：对象数组 {cls, text}，五类 cls 覆盖
test("tokenizeC：关键字/数字/注释/字符串边界", () => {
  const toks = tokenizeC('int x = 1; // 注释\n"str"');
  const clsSet = new Set(toks.filter((t) => t.cls).map((t) => t.cls));
  assert.ok(clsSet.has("syn-key"), "int → syn-key");
  assert.ok(clsSet.has("syn-num"), "1 → syn-num");
  assert.ok(clsSet.has("syn-com"), "// 注释 → syn-com");
  assert.ok(clsSet.has("syn-str"), '"str" → syn-str');
  assert.equal(toks.map((t) => t.text).join(""), 'int x = 1; // 注释\n"str"');
});

// ── highlightLines：返回 HTML 行盒串（.cl div 计数 = 行数；含行号 span）
test("highlightLines：行盒 HTML 产出", () => {
  const html = highlightLines("int a;\nint b;");
  const lineCount = (html.match(/class="cl"/g) || []).length;
  assert.equal(lineCount, 2);
  assert.ok(html.includes('class="ln">1</span>'), "行号 1 存在");
  assert.ok(html.includes("syn-key"), "关键字着色存在");
});

// ── heapSpanOf：堆跨度（heap_base → heap_end 的正跨度）
test("heapSpanOf：堆跨度计算", () => {
  const { heapBase, heapEnd, span } = heapSpanOf({
    heap_base: 4096,
    heap_offset: 8192,
    regions: [{ is_heap: true, addr: 8192, size: 256 }],
  });
  assert.equal(heapBase, 4096);
  assert.equal(heapEnd, 8448); // max(offset 8192, 块尾 8448, base+64)
  assert.equal(span, 4352);
});

// ── esc：HTML 转义（实现口径：只转 < >&——引号直出）
test("esc：HTML 转义三件", () => {
  assert.equal(esc("<a>&</a>"), "&lt;a&gt;&amp;&lt;/a&gt;");
  assert.equal(esc('"x"'), '"x"');
});

// ── workspace 纯函数（打开本地文件夹批 2026-10-05）：路径归一/文件过滤/
//    目录剪枝/编译单元排序（active 居首——引擎 base_dir 锚在首个 unit 目录）
test("workspace：toPosix 反斜杠归一与 ./ 前缀剥除", () => {
  assert.equal(toPosix("src\\util.h"), "src/util.h");
  assert.equal(toPosix(".\\main.c"), "main.c");
  assert.equal(toPosix("a/b.c"), "a/b.c");
});

test("workspace：isSourceFile 大小写与扩展名边界", () => {
  assert.equal(isSourceFile("main.c"), true);
  assert.equal(isSourceFile("UTIL.H"), true);
  assert.equal(isSourceFile("x.cpp"), false);
  assert.equal(isSourceFile("x.cc"), false);
  assert.equal(isSourceFile("ch"), false); // 无点不命中
});

test("workspace：shouldSkipDir 隐藏目录与大目录剪枝", () => {
  assert.equal(shouldSkipDir(".git"), true);
  assert.equal(shouldSkipDir("node_modules"), true);
  assert.equal(shouldSkipDir("_build"), true);
  assert.equal(shouldSkipDir("__pycache__"), true);
  assert.equal(shouldSkipDir("BUILD"), true); // 大小写不敏感
  assert.equal(shouldSkipDir("src"), false);
  assert.equal(shouldSkipDir("include"), false);
});

test("workspace：orderForCompile active 居首 + 其余字典序", () => {
  assert.deepEqual(
    orderForCompile(["a/main.c", "z.c", "m/util.h"], "z.c"),
    ["z.c", "a/main.c", "m/util.h"],
  );
  // active 不在集合 → 纯字典序（空串形态）
  assert.deepEqual(orderForCompile(["b.c", "a.c"], ""), ["a.c", "b.c"]);
  // active 首位形态（引擎 base_dir 取首 unit 目录段——子目录 include 候选链锚）
  assert.deepEqual(
    orderForCompile(["main.c", "sub/x.c"], "sub/x.c"),
    ["sub/x.c", "main.c"],
  );
});
