// W4 第四臂对拍——纯函数库契约（#273 四件套：node:test）。
// 核心义务 = 对比器「先证会红」（J9）：注入字节差 / 单侧 trap / 行数不等
// 三形态都必须判红，恢复后判绿；其余为抽样确定性、include 键、帧序对齐。
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  STATIC_CASE,
  STATIC_METHODS,
  VERDICT_RANK,
  adversarialFrames,
  buildFrames,
  byteOrder,
  checkBaseline,
  classifyFrame,
  collectFiles,
  compareResponses,
  firstDiff,
  frameMethods,
  freezeBaseline,
  isTrapLine,
  mulberry32,
  sampleK,
  splitLines,
  staticFrames,
  stratifiedSample,
  synthCases,
  vfsKeyFor,
  type Manifest,
  type SynthBaseline,
} from "./lib.mts";

const B = (s: string): Buffer => Buffer.from(s, "utf8");

test("mulberry32/sampleK：同 seed 同序列，k≥n 回全量且保序", () => {
  const a = sampleK([1, 2, 3, 4, 5, 6, 7, 8], 3, mulberry32(42));
  const b = sampleK([1, 2, 3, 4, 5, 6, 7, 8], 3, mulberry32(42));
  assert.deepEqual(a, b);
  assert.equal(a.length, 3);
  assert.deepEqual(sampleK(["x", "y"], 5, mulberry32(1)), ["x", "y"]);
});

test("stratifiedSample：按 suite 配额抽样 + mustInclude 不占配额且去重，输出字节字典序", () => {
  const suites = [
    { suite: "a", files: ["a/1.c", "a/2.c", "a/3.c", "a/4.c"] },
    { suite: "b", files: ["b/1.c", "b/2.c"] },
  ];
  const out = stratifiedSample(suites, { quotas: { a: 2, b: 9 }, mustInclude: ["b/1.c", "zz/x.c"] }, 7);
  assert.equal(out.filter((f) => f.startsWith("a/")).length, 2);
  assert.equal(out.filter((f) => f.startsWith("b/")).length, 2);
  assert.ok(out.includes("zz/x.c"));
  assert.deepEqual(out, out.slice().sort(byteOrder));
  assert.equal(new Set(out).size, out.length);
});

test("collectFiles：quote-include 闭包按 vfs 键登记，环路/重复只收一次", () => {
  const fsys: Record<string, string> = {
    "dir/main.c": '#include "a.h"\n#include "sub/b.h"\nint main(){return 0;}',
    "dir/a.h": '#include "a.h"\nint a;',
    "dir/sub/b.h": '#include "../a.h"\nint b;',
  };
  const files = collectFiles("dir/main.c", fsys["dir/main.c"] as string, (p) => fsys[p] ?? null);
  assert.deepEqual(
    files.map((f) => f.filename),
    ["main.c", "a.h", "sub/b.h"],
  );
  assert.equal(vfsKeyFor("sub/b.h", "../a.h"), "a.h");
  assert.equal(vfsKeyFor("main.c", "./x/./y.h"), "x/y.h");
});

test("buildFrames × frameMethods：三 profile 帧数与标签一一对应，id 连续从 1 起", () => {
  const c = { name: "t.c", files: [{ filename: "t.c", source: "int main(){return 0;}" }], stdin: "1\n" };
  for (const p of ["run", "deep-nomem", "deep"] as const) {
    const frames = buildFrames(c, p);
    const methods = frameMethods(p);
    assert.equal(frames.length, methods.length, p);
    frames.forEach((line, i) => {
      const j = JSON.parse(line) as { id: number; method: string; params: Record<string, unknown> };
      assert.equal(j.id, i + 1);
      assert.equal(j.method, (methods[i] as string).split(":")[0]?.split("#")[0]);
    });
  }
  assert.equal(buildFrames(c, "run").length, 6);
  assert.equal(buildFrames(c, "deep").length, buildFrames(c, "deep-nomem").length + 1);
  const run = JSON.parse(buildFrames(c, "run")[2] as string) as { params: { input?: string } };
  assert.equal(run.params.input, "1\n");
});

test("staticFrames/adversarialFrames：与标签等长、全部单行、合法 JSON 或有意非法", () => {
  const sf = staticFrames();
  assert.equal(sf.length, STATIC_METHODS.length);
  for (const l of sf) assert.ok(!l.includes("\n"));
  const adv = adversarialFrames(sf.length + 1);
  assert.equal(adv.frames.length, adv.methods.length);
  for (const l of adv.frames) assert.ok(!l.includes("\n"), "请求行禁含换行");
  // 深 JSON 帧本身须是合法 JSON（压的是引擎 json_parse 深度限，不是跑器）
  const deep = adv.frames[adv.methods.indexOf("json_depth_1000")] as string;
  assert.doesNotThrow(() => JSON.parse(deep));
});

test("synthCases：名字唯一、含栈梯度与 lone surrogate 样本、源码经 JSON.stringify 单行安全", () => {
  const cs = synthCases();
  assert.equal(new Set(cs.map((c) => c.name)).size, cs.length);
  assert.ok(cs.some((c) => c.name === "struct_nest_2000"));
  assert.ok(cs.some((c) => c.name === "struct_nest_12000"));
  assert.ok(cs.some((c) => c.name === "src_lone_surrogate_comment"));
  for (const c of cs) assert.ok(!JSON.stringify(c.src).includes("\n"));
});

test("classifyFrame/isTrapLine：四桶判定在 Buffer 层", () => {
  const ok = B('{"id":1,"ok":true}');
  const ok2 = B('{"id":1,"ok":true }');
  const tr = B('{"__host_trap__":"x","kind":"k"}');
  assert.equal(classifyFrame(ok, ok), "AGREE");
  assert.equal(classifyFrame(ok, ok2), "DIFF");
  assert.equal(classifyFrame(tr, tr), "TRAP_BOTH");
  assert.equal(classifyFrame(ok, tr), "TRAP_ONE");
  assert.equal(classifyFrame(tr, ok), "TRAP_ONE");
  assert.ok(isTrapLine(tr) && !isTrapLine(ok));
  assert.ok(VERDICT_RANK.TRAP_ONE > VERDICT_RANK.DIFF && VERDICT_RANK.DIFF > VERDICT_RANK.CASCADE && VERDICT_RANK.CASCADE > VERDICT_RANK.TRAP_BOTH);
});

test("firstDiff：字节偏移口径（多字节字符中段也按字节计）", () => {
  const a = B("abc你好def");
  const b = B("abc你坏def");
  const d = firstDiff(a, b);
  assert.ok(d);
  // "abc"=3 字节 + "你"=3 字节 → 首差在第 7 字节（"好"/"坏" 的首字节相同 0xE5，次字节不同）
  assert.equal(d.byte_offset, 7);
  assert.equal(firstDiff(a, a), null);
  const e = firstDiff(B("ab"), B("abc"));
  assert.equal(e?.byte_offset, 2);
});

function mkManifest(frameCounts: number[]): Manifest {
  const cases: Manifest["cases"] = [];
  let start = 0;
  frameCounts.forEach((n, i) => {
    cases.push({ name: `c${i}`, suite: "t", has_stdin: false, file_count: 1, frame_start: start, frame_count: n, methods: Array.from({ length: n }, (_, k) => `m${k}`) });
    start += n;
  });
  return { schema: "w4-manifest-v1", seed: 1, profile: "run", wasm_sha256: "", cases };
}

test("compareResponses 证红：逐位一致判绿；注入字节差/单侧 trap/行数不等三形态必红", () => {
  const m = mkManifest([2, 2]);
  const left = B('{"a":1}\n{"b":2}\n{"c":3}\n{"d":4}\n');
  const green = compareResponses(m, left, Buffer.from(left), { left: "L", right: "R" });
  assert.equal(green.identical, true);
  assert.deepEqual(green.summary, { AGREE: 2, TRAP_BOTH: 0, CASCADE: 0, DIFF: 0, TRAP_ONE: 0, cases: 2, frames: 4 });

  // ① 注入一字节差 → 第二语料 DIFF，首差偏移定位
  const r1 = compareResponses(m, left, B('{"a":1}\n{"b":2}\n{"c":3}\n{"d":5}\n'), { left: "L", right: "R" });
  assert.equal(r1.identical, false);
  assert.equal(r1.summary.DIFF, 1);
  assert.equal(r1.cases[1]?.verdict, "DIFF");
  assert.equal(r1.cases[1]?.frames[1]?.first_diff?.byte_offset, 5);

  // ② 单侧 trap → TRAP_ONE 压过同语料其他帧
  const r2 = compareResponses(m, left, B('{"a":1}\n{"__host_trap__":"boom","kind":"v8-RangeError"}\n{"c":3}\n{"d":4}\n'), { left: "L", right: "R" });
  assert.equal(r2.summary.TRAP_ONE, 1);
  assert.equal(r2.cases[0]?.frames[1]?.right_trap, "v8-RangeError: boom");

  // ③ 行数不等 → 缺行按 DIFF
  const r3 = compareResponses(m, left, B('{"a":1}\n{"b":2}\n{"c":3}\n'), { left: "L", right: "R" });
  assert.equal(r3.line_count.right, 3);
  assert.equal(r3.cases[1]?.verdict, "DIFF");

  // ④ 双侧同 trap → TRAP_BOTH（文案不同不比）
  const lt = B('{"a":1}\n{"__host_trap__":"wasm StackOverflow","kind":"wasm-trap"}\n{"c":3}\n{"d":4}\n');
  const rt = B('{"a":1}\n{"__host_trap__":"Maximum call stack","kind":"v8-RangeError"}\n{"c":3}\n{"d":4}\n');
  const r4 = compareResponses(m, lt, rt, { left: "L", right: "R" });
  assert.equal(r4.summary.TRAP_BOTH, 1);
  assert.equal(r4.summary.TRAP_ONE, 0);
});

test("CASCADE：单侧 trap 后实例历史不对称期间的字节差降级为 CASCADE，另一侧也 trap 后恢复为 DIFF", () => {
  const m = mkManifest([2, 2, 2]);
  // 左侧第 1 帧 trap（重建）→ 第 2、3 帧字节差 = CASCADE；右侧第 4 帧 trap 后计数相等 → 第 5 帧字节差 = DIFF
  const left = B('{"a":1}\n{"__host_trap__":"so","kind":"wasm-trap"}\n{"c":"fresh"}\n{"d":"fresh"}\n{"e":1}\n{"f":1}\n');
  const right = B('{"a":1}\n{"b":2}\n{"c":"stale"}\n{"d":"stale"}\n{"__host_trap__":"x","kind":"v8"}\n{"f":2}\n');
  const r = compareResponses(m, left, right, { left: "L", right: "R" });
  assert.equal(r.cases[0]?.verdict, "TRAP_ONE");
  assert.equal(r.cases[1]?.verdict, "CASCADE");
  assert.deepEqual(r.cases[1]?.frames[0]?.epoch, { left: 1, right: 0 });
  assert.equal(r.cases[2]?.frames[0]?.verdict, "TRAP_ONE");
  assert.equal(r.cases[2]?.frames[1]?.verdict, "DIFF");
  assert.deepEqual(r.cases[2]?.frames[1]?.epoch, { left: 1, right: 1 });
  assert.equal(r.summary.CASCADE, 1);
  assert.equal(r.summary.TRAP_ONE, 2);
});

test("splitLines：无尾换行最后一行也计入；空行保留", () => {
  assert.deepEqual(splitLines(B("a\n\nb")).map((x) => x.toString()), ["a", "", "b"]);
  assert.deepEqual(splitLines(B("a\n")).map((x) => x.toString()), ["a"]);
  assert.equal(STATIC_CASE, "__static__");
});

test("基线证红：DIFF/恶化/改善/未登记/僵尸 五类各自判出；全匹配零问题；冻结拒 DIFF", () => {
  // 四例：c0 AGREE / c1 TRAP_BOTH（双侧 trap，epoch 同步）/ c2 DIFF（须在任何单侧 trap 之前，否则按设计判 CASCADE）/ c3 TRAP_ONE
  const m = mkManifest([1, 1, 1, 1]);
  const left = B('{"a":1}\n{"__host_trap__":"x","kind":"w"}\n{"c":1}\n{"__host_trap__":"y","kind":"w"}\n');
  const right = B('{"a":1}\n{"__host_trap__":"x","kind":"v"}\n{"c":2}\n{"d":2}\n');
  const report = compareResponses(m, left, right, { left: "L", right: "R" });
  assert.deepEqual(report.cases.map((c) => c.verdict), ["AGREE", "TRAP_BOTH", "DIFF", "TRAP_ONE"]);
  // 冻结拒 DIFF
  assert.throws(() => freezeBaseline(report, "run", "t"), /拒绝冻结.*c2.*DIFF/);
  // 无 DIFF 的三例（AGREE / TRAP_BOTH / TRAP_ONE）可冻结，且自检零问题
  const m3 = mkManifest([1, 1, 1]);
  const r3 = compareResponses(m3, B('{"a":1}\n{"__host_trap__":"x","kind":"w"}\n{"__host_trap__":"y","kind":"w"}\n'), B('{"a":1}\n{"__host_trap__":"x","kind":"v"}\n{"d":2}\n'), { left: "L", right: "R" });
  assert.deepEqual(r3.cases.map((c) => c.verdict), ["AGREE", "TRAP_BOTH", "TRAP_ONE"]);
  const base = freezeBaseline(r3, "run", "t");
  assert.deepEqual(base.cases, { c0: "AGREE", c1: "TRAP_BOTH", c2: "TRAP_ONE" });
  assert.deepEqual(checkBaseline(r3, base), []);
  // 改善：基线 c0=TRAP_BOTH 本轮 AGREE；恶化：基线 c1=AGREE 本轮 TRAP_BOTH；僵尸：zz
  const tampered: SynthBaseline = { ...base, cases: { c0: "TRAP_BOTH", c1: "AGREE", c2: "TRAP_ONE", zz: "AGREE" } };
  const probs = checkBaseline(r3, tampered);
  assert.deepEqual(probs.map((p) => `${p.kind}:${p.name}`), ["improved:c0", "worsened:c1", "zombie:zz"]);
  // 未登记：基线缺 c2
  const missing: SynthBaseline = { ...base, cases: { c0: "AGREE", c1: "TRAP_BOTH" } };
  assert.deepEqual(checkBaseline(r3, missing).map((p) => p.kind), ["unregistered"]);
  // DIFF 恒红（即使基线写了 DIFF）
  const withDiff: SynthBaseline = { ...base, cases: { c0: "AGREE", c1: "TRAP_BOTH", c2: "DIFF", c3: "TRAP_ONE" } };
  assert.deepEqual(checkBaseline(report, withDiff).map((p) => p.kind), ["diff"]);
});
