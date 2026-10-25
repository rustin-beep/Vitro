// corpus_fuzz.test.mts —— 生成保真（Go 金样本逐字节）+ 判定流水线 + 端到端（.mts 重写批）。
//
// 三层锚：
//   1. **生成保真**（两层，缺一不可）：
//      a. `testdata/variants/*.c`（21 个）：Go `-freeze` 实跑产物 ⇒ 锁「采样 + 派生种子 +
//         suite/路径长度参与 RNG」这条链；其中多数算子在抽样种子上本就是 no-op，
//         故**不能**单靠它证明每个算子都被改写过（#292 审阅 P2-1 实测：突变
//         static_inject 的实现后该层仍绿）；
//      b. `testdata/golden_mutators/*.c`（11 个）：`corpus/mutator_probe/seed_all.c`
//         专为「每个算子都实际改变字节」而写，`mutators_per_seed=11` 一次跑满全算子
//         ⇒ 另有断言「每个算子至少一个变体 != 源」，防覆盖静默退化；
//   2. **判定流水线**：codeMask / firstIntLit / latin1Fold / parseVitro / bucketOf
//      的单元口径；
//   3. **端到端不在这里**：全量/迷你真跑（clang × js × native）由 CI 的 corpus-fuzz
//      job 承担。本套件曾放了一条「迷你规则真跑」，两个问题使它撤下：
//      ① 它依赖**冻结的桶基线**，而桶随 clang/引擎版本漂移（审阅 P3 实测本机陈旧
//         产物即出假红）；② 为治陈旧又得内嵌 ensureFresh 重建（+40s），把单测变成
//         构建任务。产物相关的端到端留给有产物的 job，靠 skip 而非重建来隔离。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { projectRoot } from "../internal/capi.mts";
import {
  BUCKET_RANK,
  DetRand,
  bucketOf,
  codeMask,
  collectJudgeEpochInputs,
  firstIntLit,
  judgeCacheGet,
  judgeCachePut,
  judgeEntryName,
  judgeEpochKey,
  marshalBaselineText,
  isAllDigits,
  isSep,
  latin1Fold,
  norm,
  parseVitro,
  planVariants,
  pruneJudgeEpochs,
  replaceFirstBareType,
} from "./main.mts";
import type { Rules } from "./main.mts";

const MAIN = path.join(import.meta.dirname, "main.mts");
const FIX = path.join("scripts", "corpus_fuzz", "testdata");
const ROOT = projectRoot();

function rules(): Rules {
  return JSON.parse(fs.readFileSync(path.join(ROOT, FIX, "mini_rules.json"), "utf8")) as Rules;
}

/** corpus/baseline 全部种子（相对 path 用于 RNG 长度，absPath 用于读盘）。 */
function baselineSeeds(): Array<{ suite: string; name: string; path: string; absPath: string }> {
  const rel = path.join("corpus", "baseline");
  const abs = path.join(ROOT, rel);
  return fs
    .readdirSync(abs)
    .filter((n) => n.endsWith(".c"))
    .map((n) => ({ suite: "baseline", name: n, path: path.join(rel, n), absPath: path.join(abs, n) }));
}

test("生成保真：planVariants 重算的变体与 Go 金样本逐字节相同（21 个）", () => {
  const plan = planVariants(rules(), baselineSeeds());
  const byName = new Map(plan.map((v) => [v.filename, v.bytes]));
  const goldenDir = path.join(ROOT, FIX, "variants");
  const files = fs.readdirSync(goldenDir).filter((n) => n.endsWith(".c"));
  assert.equal(files.length, 21, "金样本集规模（Go -freeze 实跑产物）");
  for (const f of files) {
    const got = byName.get(f);
    assert.ok(got !== undefined, `planVariants 未产出 ${f}`);
    assert.ok((got as Buffer).equals(fs.readFileSync(path.join(goldenDir, f))), `${f} 字节不一致`);
  }
});

test("算子覆盖：11 个算子各有一个「实际改变字节」的金样本（#292 审阅 P2-1）", () => {
  const mr = JSON.parse(fs.readFileSync(path.join(ROOT, FIX, "mutator_rules.json"), "utf8")) as Rules;
  assert.equal(mr.mutators.length, 11, "规则须覆盖全部 11 算子");
  assert.equal(mr.mutators_per_seed, 11, "每种子跑满全部算子（否则抽样可能漏算子）");

  const seedPath = path.join("corpus", "mutator_probe", "seed_all.c");
  const seedAbs = path.join(ROOT, seedPath);
  const seedBytes = fs.readFileSync(seedAbs);
  const plan = planVariants(mr, [{ suite: "mutator_probe", name: "seed_all.c", path: seedPath, absPath: seedAbs }]);
  assert.equal(plan.length, 11, "单种子 × 11 算子");

  const goldenDir = path.join(ROOT, FIX, "golden_mutators");
  const goldens = fs.readdirSync(goldenDir).filter((n) => n.endsWith(".c"));
  assert.equal(goldens.length, 11);

  // ① 逐字节对拍 Go 金样本
  const byName = new Map(plan.map((v) => [v.filename, v.bytes]));
  for (const g of goldens) {
    const got = byName.get(g);
    assert.ok(got !== undefined, `planVariants 未产出 ${g}`);
    assert.ok((got as Buffer).equals(fs.readFileSync(path.join(goldenDir, g))), `${g} 字节不一致`);
  }
  // ② 每个算子都必须真的改动过字节（no-op 金样本不算覆盖）
  const noop = plan.filter((v) => v.bytes.equals(seedBytes)).map((v) => v.mutator);
  assert.deepEqual(noop, [], `以下算子的金样本与源相同（覆盖失效）：${noop.join(", ")}`);
  const covered = new Set(plan.map((v) => v.mutator));
  for (const name of mr.mutators) assert.ok(covered.has(name), `算子 ${name} 无金样本`);
});

test("DetRand：uint64 回绕 + 同种子可复现（BigInt 语义，非 double）", () => {
  const a = new DetRand(20261018n);
  const b = new DetRand(20261018n);
  const xs = [a.next(), a.next(), a.next()];
  assert.deepEqual(xs, [b.next(), b.next(), b.next()], "同种子序列一致");
  for (const x of xs) assert.ok(x >= 0n && x < 1n << 64n, "输出落在 uint64 域");
  // 大种子：乘加在 2^64 内回绕（number 会丢精度）
  const big = new DetRand(18446744073709551615n);
  assert.ok(big.next() >= 0n);
  assert.equal(new DetRand(5n).intn(0), 0, "n<=0 返 0");
  assert.deepEqual(new DetRand(5n).intn(1), 0, "n=1 恒 0");
});

test("codeMask：注释/字符串/字符字面量区域不可用（引号本体可用）", () => {
  const src = Buffer.from('int a = 1; // 注释 int b = 2;\nchar *s = "int c = 3;";\nchar q = \'x\';\n', "utf8");
  const m = codeMask(src);
  const at = (sub: string): number => src.indexOf(Buffer.from(sub, "utf8"));
  assert.equal(m[at("int a")], 1, "普通代码可用");
  assert.equal(m[at("b = 2")], 0, "行注释内不可用");
  assert.equal(m[at('"int c')], 1, "字符串开引号本体可用（codeMask 的保守口径）");
  assert.equal(m[at("int c")], 0, "字符串内容不可用");
  assert.equal(m[at("'x'")], 1, "字符字面量开引号本体可用（变异保守）");
  assert.equal(m[at("x")], 0, "字面量内容不可用");
});

test("firstIntLit：跳预处理行与标识符中的数字", () => {
  const src1 = Buffer.from("#define N 42\nint a = 7;\n", "utf8");
  const r1 = firstIntLit(src1, codeMask(src1));
  assert.equal(src1.subarray(r1.start, r1.end).toString("utf8"), "7", "跳过 # 行里的 42");

  const src2 = Buffer.from("int a1 = 9;\n", "utf8");
  const r2 = firstIntLit(src2, codeMask(src2));
  assert.equal(src2.subarray(r2.start, r2.end).toString("utf8"), "9", "标识符 a1 里的 1 不算");

  const src3 = Buffer.from("int a = x;\n", "utf8");
  assert.equal(firstIntLit(src3, codeMask(src3)).start, -1, "无整数字面量返 -1");
});

test("isSep / isAllDigits / replaceFirstBareType：算子辅助口径", () => {
  assert.equal(isSep(0x20), true);
  assert.equal(isSep(0x2b), true, "'+' 是分隔符");
  assert.equal(isSep(0x61), false, "'a' 不是");
  assert.equal(isAllDigits("000"), true);
  assert.equal(isAllDigits(""), false);
  assert.equal(isAllDigits("1a"), false);

  const src = Buffer.from("unsigned int x = 1; int y = 2;", "utf8");
  assert.equal(
    replaceFirstBareType(src, "int", "long").toString("utf8"),
    "unsigned int x = 1; long y = 2;",
    "跳过 unsigned int 前缀语境",
  );
});

test("latin1Fold：C2/C3 双字节折回单字节，其余原样", () => {
  assert.equal(latin1Fold("a\u0085b"), Buffer.from([0x61, 0x85, 0x62]).toString("latin1"));
  assert.equal(latin1Fold("é"), Buffer.from([0xe9]).toString("latin1"), "C3 A9 → E9");
  assert.equal(latin1Fold("abc"), "abc");
});

test("parseVitro：diag reject → REJECT；缺 diag → CRASH；trap → TRAP；stdout 折叠", () => {
  const reject = JSON.stringify({ type: "diag", frame: { result: { ok: false } } });
  assert.deepEqual(parseVitro(reject + "\n"), { status: "REJECT", out: "" });

  assert.deepEqual(parseVitro('{"type":"run","frame":{"result":{"status":"finished"}}}\n'), {
    status: "CRASH",
    out: "",
  });

  const trap = JSON.stringify({ type: "diag", frame: { result: { ok: true } } }) + "\n" +
    JSON.stringify({ type: "run", frame: { result: { status: "trap", trap: "OOB" } } });
  assert.deepEqual(parseVitro(trap + "\n"), { status: "TRAP", out: "OOB" });

  const ok =
    JSON.stringify({ type: "diag", frame: { result: { ok: true } } }) + "\n" +
    JSON.stringify({ type: "stdout", frame: { result: { delta: "x\u0085y\n" } } }) + "\n" +
    JSON.stringify({ type: "run", frame: { result: { status: "finished" } } });
  const r = parseVitro(ok + "\n");
  assert.equal(r.status, "OK");
  assert.equal(r.out, "x" + Buffer.from([0x85]).toString("latin1") + "y\n");
  assert.deepEqual(parseVitro("不是 JSON"), parseVitro(""), "非法行静默跳过（与 Go continue 同）");
});

test("stdout 非 ASCII 三方同域：clang latin1 解码 ↔ 折回域对齐（col_utf8_units 假 WRONG_VALUE 根治锚）", () => {
  // 程序真实 stdout 字节（UTF-8 中文——corpus/baseline/col_utf8_units.c 实证形态：
  // printf("%s %d\n", "中文字符串", 7)。#301 merge 批前 clang 侧走 utf8 解码、
  // 折回域是 latin1，byteCompare 统一按 utf8 编码比较 ⇒ 字节相同的输出被判
  // WRONG_VALUE（本地 + CI run 40166369857 双份实证）。
  const bytes = Buffer.from("中文字符串 7\n", "utf8");
  // clang 侧（clangOutcome run 步口径）：latin1 解码 = 字节↔码点双射，无 U+FFFD 折叠
  // ——与 Go 版 bytes.Compare 的纯字节比较等价。
  const clangSide = bytes.toString("latin1");
  // vitro 侧：引擎 JSON 出口 delta 以 Latin-1 码点承载字节 → parseVitro 折回
  const vitroSide = latin1Fold(bytes.toString("latin1"));
  assert.equal(vitroSide, clangSide, "折回域须与 clang 解码域逐位一致");
  const ok = (out: string) => ({ status: "OK", out });
  assert.equal(bucketOf(ok(clangSide), ok(vitroSide), ok(vitroSide)), "AGREE");
  // 反向证锚：域失配（clang 误走 utf8 解码）须仍被判 WRONG_VALUE——防闸钝化
  assert.equal(
    bucketOf(ok(bytes.toString("utf8")), ok(vitroSide), ok(vitroSide)),
    "WRONG_VALUE",
    "域失配形态不得被吞（本缺陷的捕获依赖此分辨力）",
  );
});

test("bucketOf：六桶分类 + 恶化序", () => {
  const ok = (out: string) => ({ status: "OK", out });
  const rej = { status: "REJECT", out: "" };
  assert.equal(bucketOf(ok("1"), ok("1"), ok("1")), "AGREE");
  assert.equal(bucketOf(rej, rej, rej), "AGREE", "双拒也 AGREE");
  assert.equal(bucketOf(ok("1"), ok("1"), ok("2")), "ARM_DIVERGENCE", "两臂不一致最高优先");
  assert.equal(bucketOf(rej, ok("1"), ok("1")), "CLANG_REJECT", "clang 拒而 vitro 收");
  assert.equal(bucketOf(ok("1"), rej, rej), "VITRO_REJECT");
  assert.equal(bucketOf(ok("1"), { status: "TRAP", out: "t" }, { status: "TRAP", out: "t" }), "VITRO_TRAP");
  assert.equal(bucketOf(ok("1"), ok("2"), ok("2")), "WRONG_VALUE");
  // CRASH 单臂：vt 被 na(OK) 替换 ⇒ 与 clang 同值即 AGREE（Go 口径如实登记）
  assert.equal(bucketOf(ok("1"), { status: "CRASH", out: "" }, ok("1")), "AGREE");
  // 两臂都非 OK 且含 CRASH ⇒ vt 保持 CRASH ⇒ ARM_DIVERGENCE
  assert.equal(bucketOf(ok("1"), { status: "CRASH", out: "" }, { status: "TRAP", out: "t" }), "ARM_DIVERGENCE");
  assert.ok((BUCKET_RANK["ARM_DIVERGENCE"] as number) > (BUCKET_RANK["WRONG_VALUE"] as number));
});

test("norm：CRLF / 裸 CR 归一", () => {
  assert.equal(norm("a\r\nb\rc"), "a\nbc");
});

test("e2e：未知算子名 fail loud（exit 2，规则与实现失配不静默）", () => {
  const dir = fs.mkdtempSync(path.join(process.env["TEMP"] ?? ".", "cf-bad-"));
  const bad = path.join(dir, "rules.json");
  const r0 = rules();
  fs.writeFileSync(bad, JSON.stringify({ ...r0, mutators: ["no_such_mutator"] }), "utf8");
  const r = spawnSync(process.execPath, [MAIN, "-rules", bad, "-baseline", path.join(dir, "b.json")], {
    cwd: ROOT,
    encoding: "utf8",
  });
  assert.equal(r.status, 2);
  assert.match(r.stderr, /未知算子名 "no_such_mutator"/);
});

test("marshalBaselineText 转义口径对齐 Go SetEscapeHTML（#289 P2-1 迁移丢失回补）", () => {
  const text = marshalBaselineText({
    "suite/a.c|brace_strip": {
      bucket: "AGREE",
      note: "putchar 高位字节(>=0x80) <&> 序列",
    },
  });
  assert.ok(text.includes("\\u003e=0x80"), `> 须转义为 \u003e：${text}`);
  assert.ok(!text.includes(">=0x80"), "裸 > 不得残留");
  assert.ok(text.includes("\\u0026"), "& 须转义为 \u0026");
  assert.ok(!text.includes(" <&> "), "值内 < & > 不得裸存");
  // 往返：转义形态 JSON.parse 回读等值
  const back = JSON.parse(text) as { entries: Record<string, { note: string }> };
  const entry = back.entries["suite/a.c|brace_strip"];
  assert.ok(entry !== undefined, "往返键在位");
  assert.equal(entry.note, "putchar 高位字节(>=0x80) <&> 序列");
});

// ── 判定缓存（#309 P0）──────────────────────────────────────────────
//
// 缓存命中的正确性完全依赖键设计：bucket = (变体源, clang, js 引擎, native 引擎,
// 壳, 判定口径, node 宿主) 的确定性函数——epoch 七组件敏感性就是这套设计的 J9
// 锚：漏掉任何一个组件（实现退化）此测试必红。

test("判定缓存 epoch：七组件敏感性——任一变化 ⇒ 整体失效（#309 P0 J9 锚）", () => {
  const base = {
    clang: "clang version 19.1.1",
    native: "aa",
    jsEngine: "bb",
    shell: "cc",
    rules: "dd",
    script: "ee",
    node: "v26.12.1",
  };
  const e0 = judgeEpochKey(base);
  assert.equal(judgeEpochKey({ ...base }), e0, "同输入同键（确定性——否则缓存永不命中）");
  const comps = ["clang", "native", "jsEngine", "shell", "rules", "script", "node"] as const;
  for (const k of comps) {
    const mutated = { ...base, [k]: (base[k] as string) + "!" };
    assert.notEqual(judgeEpochKey(mutated), e0, `组件 ${k} 变化必须换 epoch（漏 hash = 缓存腐化面）`);
  }
});

test("判定缓存条目键：fp 与源字节双敏感（语料批单条失效面）", () => {
  const src = Buffer.from("int main(void){return 0;}\n");
  const a = judgeEntryName("s/a.c|brace_wrap", src);
  assert.equal(judgeEntryName("s/a.c|brace_wrap", Buffer.from(src)), a, "同 fp 同源同键");
  assert.notEqual(judgeEntryName("s/a.c|cast_strip", src), a, "fp 变 ⇒ 键变");
  assert.notEqual(judgeEntryName("s/a.c|brace_wrap", Buffer.concat([src, Buffer.from("// x\n")])), a, "源变 ⇒ 键变");
});

test("判定缓存 get/put：命中 / 窜条拒收 / 损坏与非桶值按 miss（fail open 到真跑）", () => {
  const dir = fs.mkdtempSync(path.join(process.env["TEMP"] ?? ".", "cf-judge-"));
  const v = { fp: "s/a.c|brace_wrap", bytes: Buffer.from("int x = 1;\n") };
  assert.equal(judgeCacheGet(dir, v), null, "无条目 ⇒ miss");
  judgeCachePut(dir, v, "VITRO_TRAP");
  assert.equal(judgeCacheGet(dir, v), "VITRO_TRAP", "put 后命中");
  const f = path.join(dir, judgeEntryName(v.fp, v.bytes));
  fs.writeFileSync(f, JSON.stringify({ fp: "other", bucket: "AGREE" }) + "\n");
  assert.equal(judgeCacheGet(dir, v), null, "fp 窜条（手挪/撞名）须拒收");
  fs.writeFileSync(f, "{broken");
  assert.equal(judgeCacheGet(dir, v), null, "损坏 JSON 按 miss");
  fs.writeFileSync(f, JSON.stringify({ fp: v.fp, bucket: "NOT_A_BUCKET" }) + "\n");
  assert.equal(judgeCacheGet(dir, v), null, "非法桶名按 miss（防污染值直入判红）");
  fs.writeFileSync(f, JSON.stringify({ fp: v.fp, bucket: "__proto__" }) + "\n");
  assert.equal(judgeCacheGet(dir, v), null, "原型链名按 miss");
  // 合法 JSON 但非对象（PR #310 审阅 P3-1）：null 原实现抛 TypeError 打死整轮，
  // 违背 fail open 契约——四个形态必须全部按 miss 走真跑
  for (const bad of ["null", "42", '"x"', "[]"]) {
    fs.writeFileSync(f, bad);
    assert.equal(judgeCacheGet(dir, v), null, `合法 JSON 非对象 ${bad} 按 miss`);
  }
});

test("pruneJudgeEpochs：只留当前 epoch 子目录，其余清除（防膨胀）", () => {
  const base = fs.mkdtempSync(path.join(process.env["TEMP"] ?? ".", "cf-judge-prune-"));
  fs.mkdirSync(path.join(base, "keep0001"), { recursive: true });
  fs.mkdirSync(path.join(base, "old0002", "nested"), { recursive: true });
  fs.writeFileSync(path.join(base, "old0002", "nested", "x.json"), "{}");
  fs.writeFileSync(path.join(base, "stray.txt"), "非目录不动");
  pruneJudgeEpochs("keep0001", base);
  assert.ok(fs.existsSync(path.join(base, "keep0001")), "keep 目录留存");
  assert.ok(!fs.existsSync(path.join(base, "old0002")), "旧 epoch 递归清除");
  assert.ok(fs.existsSync(path.join(base, "stray.txt")), "非目录文件不动");
  assert.doesNotThrow(() => pruneJudgeEpochs("any", path.join(base, "no-such-dir")), "base 不存在不炸");
});

test("collectJudgeEpochInputs：产物缺失不炸（hash 记 missing，判定轮自然红）", () => {
  const x = collectJudgeEpochInputs(Buffer.from("{}"));
  assert.ok(x.rules.length > 0);
  assert.ok(x.script.length > 0, "本脚本自身 hash 在位");
  // 本测试运行环境不保证引擎产物已构建——两条都只断言「不炸 + 值形态」
  assert.ok(x.native.startsWith("<missing:") || x.native.length === 32);
  assert.ok(x.jsEngine.startsWith("<missing:") || x.jsEngine.length === 32);
  assert.equal(judgeEpochKey(collectJudgeEpochInputs(Buffer.from("{}"))), judgeEpochKey(collectJudgeEpochInputs(Buffer.from("{}"))), "同环境两次收集同 epoch");
});

test("collectJudgeEpochInputs：采集面断言——shell/script 缺失 die（PR #310 审阅 P2-2/M2 锚）", () => {
  // M2 突变实证：原实现把 shell 组件改成常量后单测仍 18/18 全绿——J9 锚只锁
  // judgeEpochKey 纯函数、不锁采集接线。本锚锁采集侧：<missing:> 常量对必然
  // 在场的组件是静默降敏（路径拼错/重命名），必须 fail loud。
  const bytes = Buffer.from("{}");
  const x = collectJudgeEpochInputs(bytes);
  assert.match(x.shell, /^[0-9a-f]{32}$/, "sh 壳 hash 须为 32-hex 实测值");
  assert.match(x.script, /^[0-9a-f]{32}$/, "驱动脚本 hash 须为 32-hex 实测值");
  // 注入缺失路径 → die（ExitErr，exit 2）
  assert.throws(
    () => collectJudgeEpochInputs(bytes, { shell: "no/such/file.sh" }),
    (e: unknown) => e instanceof Error && e.name === "ExitErr" && /sh 壳/.test(e.message),
    "shell 缺失须 die 不静默降敏",
  );
  assert.throws(
    () => collectJudgeEpochInputs(bytes, { script: "no/such/file.mts" }),
    (e: unknown) => e instanceof Error && e.name === "ExitErr" && /驱动脚本/.test(e.message),
    "script 缺失须 die 不静默降敏",
  );
  // 引擎双产物允许缺失（构建前置场景合法——scripts-ts job 无产物）
  const y = collectJudgeEpochInputs(bytes, { native: "no/such/exe", jsEngine: "no/such/js" });
  assert.ok(y.native.startsWith("<missing:") && y.jsEngine.startsWith("<missing:"));
});
