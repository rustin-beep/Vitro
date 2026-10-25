// demo 纯函数锚（app.js 拆分批 2026-10-04，refs #28）——node --test 零构建。
// 锚位对历史 bug 窝点：buildCallTree 的 trie 增量语义（renderCallTree 参数
// 错位事故的函数层）、isArrayAnimCase 声明形态（下标访问不误标 + 紧凑声明
// 存量 bug 修复锁）、latin1ToUtf8 字节还原（delta 通道 mojibake 坑）、
// heapSpanOf 内存跨度、esc 转义。
// （F4 收尾 2026-10-17：tokenizeC/highlightLines 锚随旧栈编辑器退役删除——
//  新栈用 CM6，无该模块；js/editor.ts 一并退役。）
// 【锚驱动战果记录】首批锚抓到三真问题：editor 漏 import esc（拆分接线
// 遗漏）、calltree 漏 import esc、isArrayAnimCase 紧凑声明不命中（存量 bug）。
import { test } from "node:test";
import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { runInNewContext } from "node:vm";
import assert from "node:assert/strict";

import { latin1ToUtf8, esc, isArrayAnimCase, annotateGroups, coalesceStmt } from "../js/util.ts";
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
import { LessonParseError, parseLessonMd, type Block, type Scene } from "../src/lib/lessonMd.ts";
import {
  resolveAnchor,
  resolveScenes,
  sceneBand,
  sceneIndexAt,
  sceneKicker,
  sceneProgress,
  sceneRangeLabel,
  type AnchorFrame,
} from "../src/lib/scenes.ts";
import { sceneAnnotations, writesName, type StepLike } from "../src/lib/annotations.ts";
import { EXAMPLES, RELATED } from "../src/lib/catalogDetail.ts";

/** noUncheckedIndexedAccess 下的显式断言点（测试夹具已知在界内）。 */
function must<T>(v: T | undefined, msg = "预期值存在"): T {
  if (v === undefined) throw new Error(msg);
  return v;
}

/** 断言首块为 h2 并取其正文（Block 联合收窄）。 */
function h2Text(b: Block | undefined): string {
  if (b === undefined || b.type !== "h2") throw new Error("预期 h2 块");
  return b.text;
}

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
  const main = must(root.children[0]);
  assert.equal(main.name, "main");
  assert.equal(main.hitCount, 2); // hitCount=路径终点语义（帧 1/4）
  assert.equal(main.children.length, 2);
  assert.equal(must(main.children[0]).hitCount, 2);
  assert.equal(must(main.children[1]).hitCount, 1);
  assert.equal(frameNode[0], root);
  assert.equal(frameNode[3], must(main.children[0]));
  assert.equal(frameNode[5], must(main.children[1]));
  assert.equal(must(main.children[0]).parent, main);
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
  assert.equal(must(coalesceStmt(frames)[2]).code_line, 4); // {4,4,4} 组尾帧（第 4 行语句执行完的状态）
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

// ── lessonMd：scene metadata（2026-10-21 拍板：lesson.md 单源，不建 beats.ts）
test("lessonMd：scene 元数据解析 + 从 blocks 剥离（E-08 渲染面不变）", () => {
  const md = `---
id: fixture
kind: case
order: 1
title: 夹具
---

<!-- vitri-scenes v1
01 | 起点：数组与循环 | 0..4 | 3..4 | 数组初始化，i / j 还是 0。
02 | 交换不是瞬间完成的 | 5..20 | 8..10 | a[1] 刚被覆盖，旧值 5 还在 t 里。
-->

## 正文

段落。
`;
  const doc = parseLessonMd(md);
  assert.equal(doc.scenes.length, 2);
  assert.deepEqual(must(doc.scenes[0]), {
    id: "01",
    title: "起点：数组与循环",
    from: 0,
    to: 4,
    lines: [3, 4],
    note: "数组初始化，i / j 还是 0。",
  });
  assert.equal(must(doc.scenes[1]).note, "a[1] 刚被覆盖，旧值 5 还在 t 里。");
  // 注释块必须剥离：第一块仍是正文 h2，不能把 metadata 当段落渲染
  assert.equal(must(doc.blocks[0]).type, "h2");
  assert.equal(h2Text(doc.blocks[0]), "正文");
  assert.equal(doc.blocks.some((b) => b.type === "p" && b.text.includes("vitri-scenes")), false);
});

test("lessonMd：无 scene 元数据 = 空数组（老课回退长文）", () => {
  const md = `---
id: old
kind: case
order: 1
title: 老课
---

## 正文
`;
  const doc = parseLessonMd(md);
  assert.deepEqual(doc.scenes, []);
  assert.equal(must(doc.blocks[0]).type, "h2");
});

test("lessonMd：scene 元数据格式错误 fail loud（先红后绿）", () => {
  const md = `---
id: bad
kind: case
order: 1
title: 坏课
---

<!-- vitri-scenes v1
01 | 起点 | 0..4 | 3..4
-->
`;
  assert.throws(() => parseLessonMd(md), LessonParseError);
});

// ── annotations：本幕逐行注记（#222 P1 第五片：08 t ← 5 / 09 a[1] ← 1）
test("annotations：只记本幕内的变化（局部量 + 数组元素），首帧无前态不猜", () => {
  const frames: StepLike[] = [
    { code_line: 5, func_name: "main", local_vars: [{ name: "i", value: "0" }, { name: "a", value: "{3, 1, 4, 2, 5}", ty_name: "int[5]" }], array_snapshots: [{ name: "a", elements: ["3", "1", "4", "2", "5"] }] },
    { code_line: 8, func_name: "main", local_vars: [{ name: "i", value: "0" }, { name: "t", value: "5" }, { name: "a", value: "{3, 1, 4, 2, 5}", ty_name: "int[5]" }], array_snapshots: [{ name: "a", elements: ["3", "1", "4", "2", "5"] }] },
    { code_line: 9, func_name: "main", local_vars: [{ name: "i", value: "0" }, { name: "t", value: "5" }, { name: "a", value: "{3, 1, 4, 2, 5}", ty_name: "int[5]" }], array_snapshots: [{ name: "a", elements: ["3", "3", "4", "2", "5"] }] },
  ];
  const a = sceneAnnotations(frames, 0, 2);
  assert.deepEqual(
    a.map((x) => [x.line, x.text]),
    [[8, "t ← 5"], [9, "a[1] ← 3"]],
  );
  // 第一帧（无前态）不产出注记；数组整体值（int[5]）不进 local 面
  assert.equal(a.some((x) => x.text.includes("{3, 1")), false);
});

test("annotations：每行取最近一次执行的差分（随帧更新，不叠整幕迭代）", () => {
  const frames: StepLike[] = [
    { code_line: 5, func_name: "main", local_vars: [{ name: "j", value: "0" }] },
    { code_line: 7, func_name: "main", local_vars: [{ name: "j", value: "1" }] },
    { code_line: 7, func_name: "main", local_vars: [{ name: "j", value: "2" }, { name: "t", value: "5" }] },
    { code_line: 7, func_name: "main", local_vars: [{ name: "j", value: "3" }, { name: "t", value: "5" }] },
    { code_line: 9, func_name: "swap", local_vars: [{ name: "j", value: "9" }] },
  ];
  // 截至第 2 帧：line 7 最近一次是 j ← 2（同帧 t 也新 → 两条，不被前一帧的 j ← 1 污染）
  const at2 = sceneAnnotations(frames, 0, 4, 2);
  assert.deepEqual(at2.map((x) => [x.line, x.text]), [[7, "j ← 2 · t ← 5"]]);
  // 截至第 3 帧：line 7 只留最近一次 j ← 3（旧注记被替换，不叠成 j ← 1 · j ← 2）
  const at3 = sceneAnnotations(frames, 0, 4, 3);
  assert.deepEqual(at3.map((x) => [x.line, x.text]), [[7, "j ← 3"]]);
  // 第 4 帧换函数（swap）：不与 main 的 j 比，不产出注记
  assert.equal(sceneAnnotations(frames, 0, 4, 4).some((x) => x.line === 9), false);
});

test("annotations：归行校验——不写该变量的行不贴注记（for 自增并进末行实锤）", () => {
  const frames: StepLike[] = [
    { code_line: 8, func_name: "main", local_vars: [{ name: "j", value: "0" }, { name: "t", value: "5" }], array_snapshots: [{ name: "a", elements: ["5", "3", "1"] }] },
    { code_line: 10, func_name: "main", local_vars: [{ name: "j", value: "1" }, { name: "t", value: "5" }], array_snapshots: [{ name: "a", elements: ["3", "5", "1"] }] },
  ];
  const src = ["", "", "", "", "", "", "", "", "  int t = a[j];", "  a[j] = a[j + 1];", "  a[j + 1] = t;"];
  const a = sceneAnnotations(frames, 0, 1, 1, src);
  // line 10 帧：j 确实变了（语句边界把 j++ 并进末行），但该行源码不写 j → 只留数组注记
  assert.deepEqual(a.map((x) => [x.line, x.text]), [[10, "a[0] ← 3 · a[1] ← 5"]]);
  // 写入判定：a[j] = v 不算写 a；j++ / j = / --j 算；j == 0 不算
  assert.equal(writesName("  a[j] = a[j + 1];", "j"), false);
  assert.equal(writesName("  a[j] = a[j + 1];", "a"), false);
  assert.equal(writesName("  for (int j = 0; j < 4; j++)", "j"), true);
  assert.equal(writesName("  --j;", "j"), true);
  assert.equal(writesName("  if (j == 0) {", "j"), false);
});
test("annotations：at 在幕前 = 空表（未走到本幕不出旧注记）", () => {
  const frames: StepLike[] = [
    { code_line: 5, func_name: "main", local_vars: [{ name: "j", value: "0" }] },
    { code_line: 7, func_name: "main", local_vars: [{ name: "j", value: "1" }] },
  ];
  assert.deepEqual(sceneAnnotations(frames, 1, 1, 0), []);
});

// ── scenes：帧 → 幕定位（时间轴分幕 / 分镜条共用单点，P1 第二片）
test("scenes：sceneIndexAt 边界（首帧/幕尾/幕缝/幕外/空表），先红后绿", () => {
  const scenes: Scene[] = [
    { id: "01", title: "甲", from: 0, to: 4, lines: [3, 4], note: "" },
    { id: "02", title: "乙", from: 5, to: 20, lines: [8, 10], note: "" },
    { id: "03", title: "丙", from: 21, to: 29, lines: [6, 10], note: "" },
  ];
  assert.equal(sceneIndexAt([], 0), -1); // 无 scene 老课：回退长文，无幕
  assert.equal(sceneIndexAt(scenes, 0), 0); // 首帧 = 第一幕 from
  assert.equal(sceneIndexAt(scenes, 4), 0); // 幕尾含（闭区间）
  assert.equal(sceneIndexAt(scenes, 5), 1); // 幕缝 = 下一幕 from
  assert.equal(sceneIndexAt(scenes, 20), 1);
  assert.equal(sceneIndexAt(scenes, 29), 2);
  assert.equal(sceneIndexAt(scenes, -1), -1); // 未采集（idx 负数）
  assert.equal(sceneIndexAt(scenes, 30), -1); // 超出末幕（帧数变化/旧存档帧号）
});

test("scenes：sceneProgress 幕内进度与单帧幕（0/0 不得 NaN），先红后绿", () => {
  const s: Scene = { id: "02", title: "乙", from: 5, to: 20, lines: [8, 10], note: "" };
  assert.equal(sceneProgress(s, 5), 0);
  assert.equal(sceneProgress(s, 20), 1);
  assert.ok(Math.abs(sceneProgress(s, 12) - 7 / 15) < 1e-9);
  const one: Scene = { ...s, from: 7, to: 7 };
  assert.equal(sceneProgress(one, 7), 1); // 单帧幕：到即满
  assert.equal(sceneProgress(one, 6), 0); // 幕外钳制
});

test("scenes：sceneRangeLabel 单帧/多帧形态", () => {
  const s: Scene = { id: "01", title: "", from: 0, to: 4, lines: [1, 2], note: "" };
  assert.equal(sceneRangeLabel(s), "帧 0–4");
  assert.equal(sceneRangeLabel({ ...s, from: 7, to: 7 }), "帧 7");
});

test("scenes：sceneKicker 幕号/帧范围文案（幕头用），先红后绿", () => {
  const s: Scene = { id: "02", title: "乙", from: 5, to: 20, lines: [8, 10], note: "" };
  assert.equal(sceneKicker(s, 1, 4), "第 2 幕 / 共 4 幕 · 帧 5–20");
  assert.equal(sceneKicker({ ...s, from: 7, to: 7 }, 0, 1), "第 1 幕 / 共 1 幕 · 帧 7");
});

test("scenes：sceneBand 百分比几何（帧数变化/末幕越界/未采集），先红后绿", () => {
  const near = (a: number, b: number) => Math.abs(a - b) < 1e-9;
  const s: Scene = { id: "02", title: "", from: 5, to: 20, lines: [1, 2], note: "" };
  const b = sceneBand(s, 42);
  assert.ok(near(b.left, (5 / 42) * 100));
  assert.ok(near(b.width, (16 / 42) * 100));
  // 末幕越界（旧存档 frame 41，但当前只采到 30 帧）→ 宽度按现存帧钳制，不溢出轴
  const tail = sceneBand({ ...s, from: 21, to: 41 }, 30);
  assert.ok(near(tail.left, (21 / 30) * 100));
  assert.ok(near(tail.width, (9 / 30) * 100));
  // 未采集（n=0）→ 零宽，绝不出 NaN（NaN% 会让整条轴静默消失）
  assert.deepEqual(sceneBand(s, 0), { left: 0, width: 0 });
  // 单帧幕 = 一格宽
  assert.ok(near(sceneBand({ ...s, from: 7, to: 7 }, 10).width, 10));
});

test("lessonMd：bubble scene 为 v2 锚点形态（#238——写死下标结构性必错）", () => {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const src = readFileSync(path.resolve(here, "../../course/basic/bubble/lesson.md"), "utf8");
  const doc = parseLessonMd(src);
  assert.equal(doc.scenes.length, 4);
  // v2：解析期 from/to=-1 占位 + 锚点原文留存；区间无缝性由 resolveScenes
  // 求值后保证（真源帧流验证见 tmp 校准——本锚锁「全部锚点化、不回退写死」）
  for (const s of doc.scenes) {
    assert.equal(s.from, -1, `幕 ${s.id} 应为锚点形态`);
    assert.ok(s.fromAnchor && s.toAnchor, `幕 ${s.id} 缺锚点表达式`);
  }
  assert.equal(must(doc.scenes[0]).fromAnchor, "@0");
  assert.equal(must(doc.scenes[doc.scenes.length - 1]).toAnchor, "@last");
});

// 第二门旗舰课（#222 P1 内容扩面）：uaf 释放后读——6 帧、3 幕；帧数来自
// 2026-10-21 实机采集（`node tmp/iss222/measure-lesson.mjs uaf` → n=6）。
test("lessonMd：uaf scene 覆盖 0..5（内容锚：悬垂指针三幕）", () => {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const src = readFileSync(path.resolve(here, "../../course/basic/uaf/lesson.md"), "utf8");
  const doc = parseLessonMd(src);
  assert.equal(doc.scenes.length, 3);
  assert.deepEqual(
    doc.scenes.map((s) => [s.id, s.from, s.to, s.lines.join("..")]),
    [
      ["01", 0, 2, "4..5"],
      ["02", 3, 3, "6..6"],
      ["03", 4, 5, "7..8"],
    ],
  );
  for (let i = 1; i < doc.scenes.length; i += 1) {
    assert.equal(must(doc.scenes[i]).from, must(doc.scenes[i - 1]).to + 1, `scene ${must(doc.scenes[i]).id} 与上一幕之间有空洞/重叠`);
  }
  // 注释块剥离：正文首块仍是 h2（与本片 E-08/课文渲染口径一致）
  assert.equal(must(doc.blocks[0]).type, "h2");
});

// 第三门旗舰课（#222 P1 内容扩面）：bubble_sort 冒泡——65 帧、6 幕。
// 帧数是实机口径：demo 的 viewFrames = 引擎 insn 帧经 annotateGroups 取组尾
// （语句级），本锚用同一条链对 templates/bubble/source.c 的 lesson 源码实测
// 65 帧（2026-10-22：js 臂 step 流 914 条指令帧 → 65 条语句帧）。
test("lessonMd：bubble_sort scene 为 v2 锚点形态（六幕全锚点化，#238）", () => {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const src = readFileSync(path.resolve(here, "../../course/sorting/bubble_sort/lesson.md"), "utf8");
  const doc = parseLessonMd(src);
  assert.equal(doc.scenes.length, 6);
  // v2 锚点化（2026-10-23 #238）：帧区间随语句级帧流动态求值（旧 0..64
  // 写死数字退役）；六幕的轮边界 = arr_change 序数（每轮交换次数恒等式）
  for (const s of doc.scenes) {
    assert.equal(s.from, -1);
    assert.ok(s.fromAnchor && s.toAnchor, `幕 ${s.id} 缺锚点表达式`);
  }
  assert.deepEqual(
    doc.scenes.map((s) => [s.id, s.fromAnchor, s.toAnchor, s.lines.join("..")]),
    [
      ["01", "@0", "@arr_change:2", "15..18"],
      ["02", "@arr_change:2+1", "@arr_change:8", "4..9"],
      ["03", "@arr_change:8+1", "@arr_change:13", "4..9"],
      ["04", "@arr_change:13+1", "@arr_change:17", "4..9"],
      ["05", "@arr_change:17+1", "@arr_change:19", "4..6"],
      ["06", "@arr_change:19+1", "@last", "18..23"],
    ],
  );
  // 元数据剥离 + 课文仍在：首块 h2，且六幕讲解不是正文段落
  assert.equal(must(doc.blocks[0]).type, "h2");
  assert.equal(doc.blocks.some((b) => b.type === "p" && b.text.includes("vitri-scenes")), false);
});

// token 单源 ↔ 主题清单一致性（#222 P0）：新加主题若只改了 persisted 的
// THEME_KEYS、没在 tokens.json 里登记色板，该主题会静默无样式——这里把
// persisted 与 tokens 两端钉死；style_contract 的主题清单也读 tokens.themeOrder
// （同一单源，不再手抄），故三者不会各错一次。
test("tokens：五主题集合 = THEME_KEYS，且每主题都有 token", () => {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const tokens = JSON.parse(readFileSync(path.resolve(here, "../tokens.json"), "utf8"));
  const persisted = readFileSync(path.resolve(here, "../src/persisted.svelte.ts"), "utf8");
  const m = persisted.match(/THEME_KEYS\s*=\s*\[([^\]]+)\]/);
  assert.ok(m, "persisted.svelte.ts 里找不到 THEME_KEYS");
  const keys = must(m[1])
    .split(",")
    .map((s) => s.trim().replace(/^["']|["']$/g, ""))
    .filter(Boolean);
  assert.ok(keys.length >= 5, `THEME_KEYS 只解析出 ${keys.length} 个（抽取面塌缩）`);
  assert.deepEqual([...tokens.themeOrder].sort(), [...keys].sort());
  for (const k of keys) {
    const t = tokens.themes[k]?.tokens ?? {};
    assert.ok(Object.keys(t).length > 0, `主题 ${k} 在 tokens.json 里没有 token`);
    assert.ok(["--vr-bg", "--vr-panel", "--vr-ink", "--vr-rule", "--vr-amber"].every((v) => t[v]), `主题 ${k} 缺核心 token`);
  }
});

// ── 内容批回归闸（2026-10-23 审阅 P2）：课程 scene 与码表附属内容此前只有
// tmp/ 探针，没有任何 CI 锚——scene 帧号改坏、catalog 键写错都能全绿。
// 这里补两个纯函数闸：不依赖浏览器/引擎，只锁结构面（帧号连续/行界/键命中/
// 关联课存在）；引擎帧数锚另由各课的 N 常量显式钉住，帧流变化会先红。

test("lessonMd：全量 course 叙述 scene 连续、行界/注记非空（P2-1 闸）", () => {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const root = path.resolve(here, "../../course");
  const files: string[] = [];
  const walk = (dir: string): void => {
    for (const ent of readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, ent.name);
      if (ent.isDirectory()) walk(p);
      else if (ent.isFile() && ent.name === "lesson.md") files.push(p);
    }
  };
  walk(root);
  assert.ok(files.length >= 8, `course 叙述文件只找到 ${files.length} 份（抽取面塌缩）`);
  for (const file of files) {
    const doc = parseLessonMd(readFileSync(file, "utf8"));
    const rel = path.relative(root, file);
    assert.ok(doc.scenes.length >= 1, `${rel}: 无 scene`);
    // v1 数字课：首幕 0 起 + 逐幕无缝；v2 锚点课（#238）：锚点表达式齐全、
    // 覆盖校验移交 resolveScenes（帧流上动态求值——写死下标结构性必错）
    if (must(doc.scenes[0]).fromAnchor !== undefined) {
      for (const s of doc.scenes) {
        assert.ok(s.fromAnchor && s.toAnchor, `${rel}: v2 幕 ${s.id} 缺锚点表达式`);
        assert.equal(s.from, -1, `${rel}: v2 幕 ${s.id} from 应为 -1 占位`);
      }
      continue;
    }
    assert.equal(must(doc.scenes[0]).from, 0, `${rel}: 首幕不从 0 起`);
    let prev = -1;
    for (const s of doc.scenes) {
      assert.ok(s.to >= s.from, `${rel}: scene ${s.id} to < from`);
      assert.equal(s.from, prev + 1, `${rel}: scene ${s.id} 与上一幕不连续`);
      assert.ok(must(s.lines[0]) >= 1 && must(s.lines[1]) >= must(s.lines[0]), `${rel}: scene ${s.id} 行界非法`);
      assert.ok(s.title.trim() && s.note.trim(), `${rel}: scene ${s.id} 标题/注记为空`);
      prev = s.to;
    }
  }
});

test("lessonMd：第〇章新 5 门 scene 帧数/四节（内容批锚）", () => {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const expectN: Record<string, number> = { hello: 5, double_avg: 9, global_struct: 540, macro: 6, malloc_free: 9 };
  const need = ["这门课在做什么", "先跑一遍，看三个东西", "一个常见错误，先放在这里", "试着改"];
  for (const [id, n] of Object.entries(expectN)) {
    const doc = parseLessonMd(readFileSync(path.resolve(here, `../../course/basic/${id}/lesson.md`), "utf8"));
    assert.ok(doc.scenes.length >= 3 && doc.scenes.length <= 6, `${id}: 幕数 ${doc.scenes.length} 不在 3..6`);
    assert.equal(must(doc.scenes[doc.scenes.length - 1]).to, n - 1, `${id}: 末幕 to ≠ N-1`);
    assert.equal(doc.scenes.reduce((s, x) => s + (x.to - x.from + 1), 0), n, `${id}: scene 覆盖帧数 ≠ ${n}`);
    const h2 = doc.blocks.flatMap((b) => (b.type === "h2" ? [b.text] : []));
    for (const h of need) assert.ok(h2.includes(h), `${id}: 缺小节「${h}」`);
  }
});

test("catalogDetail：示例/关联课键命中 catalog，关联课存在（P2-2 闸）", () => {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const cat = JSON.parse(readFileSync(path.resolve(here, "../../scripts/moonbit/diagnostics_data/catalog.json"), "utf8")) as {
    entries: Array<{ code: number }>;
  };
  const arms = JSON.parse(readFileSync(path.resolve(here, "../../scripts/moonbit/diagnostics_data/error_codes.json"), "utf8")) as {
    arms: Array<{ name: string; code: number }>;
  };
  const prefix = new Map(arms.arms.map((a) => [a.code, a.name.split("_")[0]]));
  const codes = new Set(cat.entries.map((e) => prefix.get(e.code)).filter((s): s is string => !!s));
  assert.ok(Object.keys(EXAMPLES).length >= 25, `EXAMPLES 只剩 ${Object.keys(EXAMPLES).length} 条`);
  for (const [code, ex] of Object.entries(EXAMPLES)) {
    assert.ok(codes.has(code), `EXAMPLES 键 ${code} 不在 catalog.code_str`);
    assert.ok(ex.bad.trim().length > 0, `${code}: bad 为空`);
    if (ex.fix !== undefined) assert.ok(ex.fix.trim().length > 0, `${code}: fix 为空`);
  }

  const cases = runInNewContext(readFileSync(path.resolve(here, "../cases.js"), "utf8") + "\n;DEMO_CASES;", {}) as Array<{ id: string }>;
  const algos = runInNewContext(readFileSync(path.resolve(here, "../algorithms.js"), "utf8") + "\n;DEMO_ALGORITHMS;", {}) as {
    groups?: Array<{ id: string; items?: Array<{ id: string; variants?: Array<{ tpl: string }> }>; xitems?: Array<{ id: string }> }>;
  };
  const lessonIds = new Set<string>(cases.map((c) => c.id));
  for (const g of algos.groups ?? []) {
    if (g.id === "xlab") for (const x of g.xitems ?? []) lessonIds.add(x.id);
    else for (const it of g.items ?? []) {
      lessonIds.add(it.id);
      for (const v of it.variants ?? []) lessonIds.add(v.tpl);
    }
  }
  assert.ok(Object.keys(RELATED).length >= 16, `RELATED 只剩 ${Object.keys(RELATED).length} 条`);
  for (const [code, id] of Object.entries(RELATED)) {
    assert.ok(codes.has(code), `RELATED 键 ${code} 不在 catalog.code_str`);
    assert.ok(lessonIds.has(id), `RELATED[${code}] 的课 id「${id}」不在课表`);
  }
});

// ── #238：v2 锚点分镜（lessonMd 解析 + resolveAnchor/resolveScenes 求值）──

test("lessonMd：v2 锚点幕解析（from/to=-1 占位 + 原文留存；纯数字幕直存）", () => {
  const md = `---
id: anchorfx
kind: case
order: 1
---

<!-- vitri-scenes v2
01 | 起点 | @0..@func:bubbleSort-1 | 1..2 | 初始化段。
02 | 交换 | @first_swap-1..@first_swap+6 | 3..4 | 半完成中间态。
03 | 收尾 | 40..50 | 5..6 | 数字幕在 v2 同样合法。
-->
`;
  const doc = parseLessonMd(md);
  assert.equal(doc.scenes.length, 3);
  assert.equal(must(doc.scenes[0]).from, -1);
  assert.equal(must(doc.scenes[0]).to, -1);
  assert.equal(must(doc.scenes[0]).fromAnchor, "@0");
  assert.equal(must(doc.scenes[0]).toAnchor, "@func:bubbleSort-1");
  assert.equal(must(doc.scenes[1]).fromAnchor, "@first_swap-1");
  assert.equal(must(doc.scenes[1]).toAnchor, "@first_swap+6");
  assert.equal(must(doc.scenes[2]).from, 40);
  assert.equal(must(doc.scenes[2]).to, 50);
  assert.equal(must(doc.scenes[2]).fromAnchor, undefined);
});

test("lessonMd：v2 混排（数字+锚点两端）fail loud", () => {
  const md = `---
id: badmix
kind: case
order: 1
---

<!-- vitri-scenes v2
01 | 起点 | 0..@last | 1..2 | 两端不同形。
-->
`;
  assert.throws(() => parseLessonMd(md), /两端须同为数字或同为锚点/);
});

test("resolveAnchor：swap 序 / compare 序 / func / last / 偏移 clamp", () => {
  // code_line 逐帧递增：resolveAnchor 在语句级归一域求值（同行组合并），
  // 合成帧须各自独立成组否则序数全塌成一组
  const mk = (i: number, over: Partial<AnchorFrame>): AnchorFrame => ({
    code_line: i + 1,
    func_name: "main",
    semantic_label: "",
    algorithm_step: null,
    ...over,
  });
  const frames: AnchorFrame[] = [];
  for (let i = 0; i < 10; i += 1) frames.push(mk(i, {}));
  // 帧 2/5/8 = swap（一条走 phase、一条走 label 兜底）；帧 3/6 = compare
  frames[2] = mk(2, { algorithm_step: { phase: "swap" } });
  frames[5] = mk(5, { semantic_label: "交换 arr[0]↔arr[1]" });
  frames[8] = mk(8, { algorithm_step: { phase: "swap" } });
  frames[3] = mk(3, { algorithm_step: { phase: "compare" } });
  frames[6] = mk(6, { algorithm_step: { phase: "compare" } });
  frames[7] = mk(7, { func_name: "bubbleSort" });
  assert.equal(resolveAnchor("@first_swap", frames), 2);
  assert.equal(resolveAnchor("@swap:2", frames), 5); // label 兜底命中
  assert.equal(resolveAnchor("@swap:3", frames), 8);
  assert.equal(resolveAnchor("@swap:4", frames), -1); // 不存在 → 不猜
  assert.equal(resolveAnchor("@compare:1", frames), 3);
  assert.equal(resolveAnchor("@compare:2", frames), 6);
  assert.equal(resolveAnchor("@compare:9", frames), -1);
  assert.equal(resolveAnchor("@func:bubbleSort", frames), 7);
  assert.equal(resolveAnchor("@func:quickSort", frames), -1);
  assert.equal(resolveAnchor("@last", frames), 9);
  assert.equal(resolveAnchor("@first_swap-1", frames), 1);
  assert.equal(resolveAnchor("@first_swap+99", frames), 9); // clamp 末帧
  assert.equal(resolveAnchor("@first_swap-99", frames), 0); // clamp 首帧
  assert.equal(resolveAnchor("@nosuch", frames), -1); // 未登记词汇
});

test("resolveScenes：v1 数字幂等直通 / v2 求值 / 未命中 -1 保持", () => {
  const v1: Scene[] = [{ id: "01", title: "t", from: 2, to: 5, lines: [1, 2], note: "n" }];
  // code_line 逐帧独立（resolveAnchor 语句级归一域求值——同线并组）
  const frames: AnchorFrame[] = [
    { code_line: 1, func_name: "main", semantic_label: "", algorithm_step: null },
    { code_line: 2, func_name: "main", semantic_label: "", algorithm_step: { phase: "swap" } },
    { code_line: 3, func_name: "main", semantic_label: "", algorithm_step: null },
  ];
  assert.equal(resolveScenes(v1, frames), v1); // 无锚点 = 原引用直通
  const v2: Scene[] = [
    { id: "01", title: "交换", from: -1, to: -1, fromAnchor: "@first_swap-1", toAnchor: "@first_swap+1", lines: [1, 2], note: "n" },
    { id: "02", title: "幽灵", from: -1, to: -1, fromAnchor: "@swap:9", toAnchor: "@last", lines: [1, 2], note: "n" },
  ];
  const got = resolveScenes(v2, frames);
  assert.deepEqual([must(got[0]).from, must(got[0]).to], [0, 2]); // 1-1=0、1+1=2
  assert.deepEqual([must(got[1]).from, must(got[1]).to], [-1, -1]); // 未命中不猜
  assert.deepEqual(resolveScenes(v2, []), v2.map((s) => ({ ...s }))); // 空帧流原样（未采集）
});

test("lessonMd：bubble 两课真源均为 v2 锚点（防回退写死下标）", () => {
  const root = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
  for (const rel of ["course/basic/bubble/lesson.md", "course/sorting/bubble_sort/lesson.md"]) {
    const doc = parseLessonMd(readFileSync(path.join(root, rel), "utf-8"));
    assert.ok(doc.scenes.length > 0, `${rel} 应带分镜`);
    for (const s of doc.scenes) {
      assert.ok(s.fromAnchor && s.toAnchor, `${rel} 幕 ${s.id} 应为锚点形态（#238——写死下标结构性必错）`);
      assert.equal(s.from, -1);
      assert.equal(s.to, -1);
    }
  }
});
