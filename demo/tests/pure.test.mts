// demo 纯函数锚（app.js 拆分批 2026-10-04，refs #28）——node --test 零构建。
// 锚位对历史 bug 窝点：buildCallTree 的 trie 增量语义（renderCallTree 参数
// 错位事故的函数层）、isArrayAnimCase 声明形态（下标访问不误标 + 紧凑声明
// 存量 bug 修复锁）、latin1ToUtf8 字节还原（delta 通道 mojibake 坑）、
// tokenizeC/highlightLines 编辑器双层、heapSpanOf 内存跨度、esc 转义。
// 【锚驱动战果记录】首批锚抓到三真问题：editor 漏 import esc（拆分接线
// 遗漏）、calltree 漏 import esc、isArrayAnimCase 紧凑声明不命中（存量 bug）。
import { test } from "node:test";
import assert from "node:assert/strict";

import { latin1ToUtf8, esc, isArrayAnimCase, annotateGroups, coalesceStmt } from "../js/util.ts";
import { tokenizeC, highlightLines } from "../js/editor.ts";
import { buildCallTree } from "../js/calltree.ts";
import { heapSpanOf } from "../js/memory.ts";
import { toPosix, isSourceFile, shouldSkipDir, orderForCompile } from "../js/workspace.ts";
import {
  bytesToB64url,
  b64urlToBytes,
  parseFragment,
  shareUrlFrom,
  packSource,
  unpackSource,
  urlLenWarning,
  SHARE_URL_WARN,
  SHARE_VERSION,
} from "../js/share.ts";

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

// ── 链接分享纯函数（2026-10-09 批）：base64url 往返 / fail loud 三形态 /
//    片段解析三态 / deflate-raw 往返与「截断必被解压失败兜住」（载荷不花
//    校验和的唯一依据——该锚就是它的回归防线）
test("share：base64url 往返（含多字节与全 0xFF 字节面）", () => {
  // 空字节 → 空串（合法输出，但空载荷不是合法片段——反解侧见下一锚）
  assert.equal(bytesToB64url(new Uint8Array([])), "");
  const cases = [
    new TextEncoder().encode("Hello\n"),
    new TextEncoder().encode("int main(){/* 中文注释 */return 0;}"),
    new Uint8Array([0, 1, 254, 255, 251, 250, 62, 63]),
  ];
  for (const bytes of cases) {
    assert.deepEqual(b64urlToBytes(bytesToB64url(bytes)), bytes);
  }
  // 无 padding、URL 安全字符集（+ / = 不得出现）
  assert.equal(/[+/=]/.test(bytesToB64url(new Uint8Array([251, 255, 190]))), false);
});

test("share：b64urlToBytes 三形态 fail loud（空 / 非法字符 / 长度 %4==1）", () => {
  assert.throws(() => b64urlToBytes(""), /空/);
  assert.throws(() => b64urlToBytes("ab+cd"), /之外的字符/);
  assert.throws(() => b64urlToBytes("abcde"), /长度非法/);
  // 合法长度三种余数都要能过（0/2/3）
  assert.equal(b64urlToBytes("YWJj").length, 3);
  assert.equal(b64urlToBytes("YWI").length, 2);
  assert.equal(b64urlToBytes("YQ").length, 1);
});

test("share：parseFragment 三态（无片段=首访 / 有片段但不认识=截断 / 正常）", () => {
  assert.deepEqual(parseFragment(""), { kind: "none" });
  // 有 # 但版本前缀被截断 —— 必须报 bad，绝不能静默当首访
  assert.equal(parseFragment("z1").kind, "bad");
  assert.equal(parseFragment("bogus").kind, "bad");
  assert.equal(parseFragment("z9.AAAA").kind, "bad");
  const ok = parseFragment("z1.AAAA");
  assert.deepEqual(ok, { kind: "payload", payload: "AAAA" });
  // 版本前缀在、载荷空 → bad
  assert.equal(parseFragment("z1.").kind, "bad");
});

test("share：shareUrlFrom 剥已有 # 片段（连点分享不叠加）", () => {
  assert.equal(shareUrlFrom("https://x/Vitro/", "z1.abc"), "https://x/Vitro/#z1.abc");
  assert.equal(shareUrlFrom("https://x/Vitro/#z1.old", "z1.new"), "https://x/Vitro/#z1.new");
  assert.equal(shareUrlFrom("https://x/Vitro/?a=1#z1.old", "z1.new"), "https://x/Vitro/?a=1#z1.new");
});

test("share：源码压缩往返（deflate-raw，原样还原缩进与中文）", async () => {
  const src = '#include <stdio.h>\n\nint main() {\n  // 中文注释\n  printf("Hello\\n");\n  return 0;\n}\n';
  const fragment = await packSource(src);
  assert.ok(fragment.startsWith(SHARE_VERSION + "."), "片段带版本前缀");
  const parsed = parseFragment(fragment);
  assert.equal(parsed.kind, "payload");
  assert.equal(await unpackSource(parsed.payload), src);
});

test("share：截断载荷必被解压失败兜住（载荷零校验和的依据）", async () => {
  const src = "int main(){int a[5]={5,3,1,4,2};for(int i=0;i<4;i++)for(int j=0;j<4-i;j++)if(a[j]>a[j+1]){int t=a[j];a[j]=a[j+1];a[j+1]=t;}return 0;}";
  const fragment = await packSource(src);
  const payload = fragment.slice(SHARE_VERSION.length + 1);
  // 尾部削 6 字符（≥1 字节）——DEFLATE 流缺尾即解压失败，不静默放行
  await assert.rejects(() => unpackSource(payload.slice(0, payload.length - 6)));
  // 中部截断同样必红
  await assert.rejects(() => unpackSource(payload.slice(0, Math.floor(payload.length / 2))));
});

test("share：链接过长告警（阈值边界含等号侧）", () => {
  assert.equal(urlLenWarning(SHARE_URL_WARN), "");
  assert.equal(urlLenWarning(SHARE_URL_WARN + 1).length > 0, true);
  assert.equal(urlLenWarning(200), "");
});

// ── 回放粒度分组（2026-10-09 语句级批）：按 code_line 连续同组合并——
// 实测锚点：冒泡排序 1018 帧 → 42 帧（播放时长与 VM 指令密度解耦）
test("粒度分组：连续同行合并计数（headLines 实测形态 [0,0,3,4,4,4,4,...]）", () => {
  const frames = [0, 0, 3, 4, 4, 4, 7, 8, 9, 7].map((code_line, i) => ({ code_line, step_index: i }));
  // 组：{0,0}{3}{4,4,4}{7}{8}{9}{7} = 7 组
  assert.equal(coalesceStmt(frames).length, 7);
  assert.equal(coalesceStmt(frames)[2].code_line, 4); // {4,4,4} 组尾帧（第 4 行语句执行完的状态）
  assert.equal(annotateGroups(frames).length, frames.length); // 标注不丢帧
  const grp4 = annotateGroups(frames).filter((g) => g.f.code_line === 4);
  assert.deepEqual(grp4.map((g) => [g.m, g.k]), [[1, 3], [2, 3], [3, 3]]); // 组内序号/大小
});
test("粒度分组：空数组 / 单帧 / 全同行边界", () => {
  assert.deepEqual(coalesceStmt([]), []);
  const one = [{ code_line: 5, step_index: 0 }];
  assert.equal(coalesceStmt(one).length, 1);
  const same = [1, 1, 1, 1].map((code_line, i) => ({ code_line, step_index: i }));
  assert.equal(coalesceStmt(same).length, 1); // 全同行压成 1 帧
  assert.equal(annotateGroups(same).length, 4);
});
