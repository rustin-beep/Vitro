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
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
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
import { LessonParseError, parseLessonMd, type Scene } from "../src/lib/lessonMd.ts";
import { sceneBand, sceneIndexAt, sceneKicker, sceneProgress, sceneRangeLabel } from "../src/lib/scenes.ts";
import { sceneAnnotations, writesName, type StepLike } from "../src/lib/annotations.ts";

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
  assert.deepEqual(doc.scenes[0], {
    id: "01",
    title: "起点：数组与循环",
    from: 0,
    to: 4,
    lines: [3, 4],
    note: "数组初始化，i / j 还是 0。",
  });
  assert.equal(doc.scenes[1].note, "a[1] 刚被覆盖，旧值 5 还在 t 里。");
  // 注释块必须剥离：第一块仍是正文 h2，不能把 metadata 当段落渲染
  assert.equal(doc.blocks[0].type, "h2");
  assert.equal(doc.blocks[0].text, "正文");
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
  assert.equal(doc.blocks[0].type, "h2");
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

test("lessonMd：bubble scene 覆盖 0..41（内容锚，先红后绿）", () => {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const src = readFileSync(path.resolve(here, "../../course/basic/bubble/lesson.md"), "utf8");
  const doc = parseLessonMd(src);
  assert.equal(doc.scenes.length, 4);
  assert.equal(doc.scenes[0].from, 0);
  assert.equal(doc.scenes[doc.scenes.length - 1].to, 41);
  for (let i = 1; i < doc.scenes.length; i += 1) {
    assert.equal(doc.scenes[i].from, doc.scenes[i - 1].to + 1, `scene ${doc.scenes[i].id} 与上一幕之间有空洞/重叠`);
  }
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
    assert.equal(doc.scenes[i].from, doc.scenes[i - 1].to + 1, `scene ${doc.scenes[i].id} 与上一幕之间有空洞/重叠`);
  }
  // 注释块剥离：正文首块仍是 h2（与本片 E-08/课文渲染口径一致）
  assert.equal(doc.blocks[0].type, "h2");
});

// 第三门旗舰课（#222 P1 内容扩面）：bubble_sort 冒泡——65 帧、6 幕。
// 帧数是实机口径：demo 的 viewFrames = 引擎 insn 帧经 annotateGroups 取组尾
// （语句级），本锚用同一条链对 templates/bubble/source.c 的 lesson 源码实测
// 65 帧（2026-10-22：js 臂 step 流 914 条指令帧 → 65 条语句帧）。
test("lessonMd：bubble_sort scene 覆盖 0..64（内容锚：六幕收敛）", () => {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const src = readFileSync(path.resolve(here, "../../course/sorting/bubble_sort/lesson.md"), "utf8");
  const doc = parseLessonMd(src);
  assert.equal(doc.scenes.length, 6);
  assert.deepEqual(
    doc.scenes.map((s) => [s.id, s.from, s.to, s.lines.join("..")]),
    [
      ["01", 0, 4, "15..18"],
      ["02", 5, 23, "4..9"],
      ["03", 24, 36, "4..9"],
      ["04", 37, 47, "4..9"],
      ["05", 48, 50, "4..6"],
      ["06", 51, 64, "18..23"],
    ],
  );
  for (let i = 1; i < doc.scenes.length; i += 1) {
    assert.equal(doc.scenes[i].from, doc.scenes[i - 1].to + 1, `scene ${doc.scenes[i].id} 与上一幕之间有空洞/重叠`);
  }
  // 末幕必须落在最后一帧（65 帧 = 0..64；帧数变化要连坐改幕，不许静默越界）
  assert.equal(doc.scenes[doc.scenes.length - 1].to, 64);
  // 元数据剥离 + 课文仍在：首块 h2，且六幕讲解不是正文段落
  assert.equal(doc.blocks[0].type, "h2");
  assert.equal(doc.blocks.some((b) => b.type === "p" && b.text.includes("vitri-scenes")), false);
});

// token 单源 ↔ 主题清单一致性（#222 P0）：新加主题若只改了 persisted 的
// THEME_KEYS、没在 tokens.json 里登记色板，style_contract 只覆盖硬编码五主题、
// 该主题会静默无样式——这里把两边钉死。
test("tokens：五主题集合 = THEME_KEYS，且每主题都有 token", () => {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const tokens = JSON.parse(readFileSync(path.resolve(here, "../tokens.json"), "utf8"));
  const persisted = readFileSync(path.resolve(here, "../src/persisted.svelte.ts"), "utf8");
  const m = persisted.match(/THEME_KEYS\s*=\s*\[([^\]]+)\]/);
  assert.ok(m, "persisted.svelte.ts 里找不到 THEME_KEYS");
  const keys = m[1]
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
