// lexer.test.mts —— lexer target 的族内单测（2026-10-23 审阅 P3-3 补：
// 同族 typeck/parser/vm/codegen 各有 82–130 行测试，唯 lexer 零族内文件，
// 其测试此前散在 internal/diffgate.test.mts 里——本文件归位并补 target 分发锚）。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import {
  checkLineColInvariant,
  lexerTarget,
  loadLexDigest,
  makeLexGolden,
  serializeLexDigest,
} from "./lexer.mts";
import { projectRoot } from "../../internal/capi.mts";
import type { Fail } from "../../internal/diffgate.mts";

const boom: Fail = (msg: string): never => {
  throw new Error(msg);
};

const GATE = path.join(projectRoot(), "scripts/diff_gate/main.mts");
const run = (args: string[]) =>
  spawnSync(process.execPath, [GATE, ...args], { cwd: projectRoot(), encoding: "utf8", timeout: 600_000 });

test("lexer 的语料口径：.c/.h/.in 全量伴生（与 typeck 只吃 .c 不同）", () => {
  assert.deepEqual(lexerTarget.corpusExts, undefined, "未声明 = 用骨架默认三后缀");
  assert.deepEqual(lexerTarget.knownForks, undefined, "lexer 无 known-fork");
});

test("makeLexGolden：load 只取本语料段 cases，save 后回读一致（临时根）", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-lx-"));
  try {
    fs.mkdirSync(path.join(dir, "scripts/lexer_diff"), { recursive: true });
    fs.writeFileSync(
      path.join(dir, "scripts/lexer_diff/golden_digest.json"),
      JSON.stringify({
        version: 1,
        sources: { alpha: { "a.c": "aaaaaaaa" }, beta: { "b.c": "bbbbbbbb" } },
        tsvs: { "alpha/x.tsv": "1111", "beta/y.tsv": "2222" },
      }),
    );
    const store = makeLexGolden(dir);
    const sec = store.load("alpha");
    assert.ok(sec !== null);
    assert.deepEqual(sec.sources, { "a.c": "aaaaaaaa" });
    assert.deepEqual(sec.cases, { "x.tsv": "1111" });
    assert.equal(store.load("nope"), null);

    store.save("alpha", { sources: { "a.c": "aaaaaaaa", "new.c": "cccccccc" }, cases: { "z.tsv": "9999" } });
    const back = loadLexDigest(dir, boom);
    assert.equal(back.tsvs["beta/y.tsv"], "2222", "不得动其它段");
    assert.equal(back.tsvs["alpha/x.tsv"], undefined);
    assert.equal(back.tsvs["alpha/z.tsv"], "9999");
    assert.equal(back.sources.alpha?.["new.c"], "cccccccc");
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("真实仓库：serializeLexDigest 与入库 golden_digest.json 逐字节一致", () => {
  const rel = "scripts/lexer_diff/golden_digest.json";
  const doc = loadLexDigest(projectRoot(), boom);
  const original = fs.readFileSync(path.join(projectRoot(), rel), "utf8");
  assert.equal(serializeLexDigest(doc), original);
});

test("真实仓库：lexer 在 baseline 全量 PASS（条数取自冻结基线，不写死）", () => {
  // #292 审阅 P3 连带修：此处原写死 976，master 语料增长后（实测 990）该断言会恒红——
  // 而本文件曾长期**不在 npm test 清单**里，所以没人发现。现改为以 golden_digest 的
  // baseline/ 条目数为唯一真值（同一份冻结产物），语料扩容后自动跟随、删条目才会红。
  const digest = JSON.parse(
    fs.readFileSync(path.join(projectRoot(), "scripts", "lexer_diff", "golden_digest.json"), "utf8"),
  ) as { tsvs: Record<string, unknown> };
  const expected = Object.keys(digest.tsvs).filter((k) => k.startsWith("baseline/")).length;
  assert.ok(expected > 0, "冻结基线里没有 baseline 条目（golden 缺失或结构漂移）");
  const r = run(["lexer", "corpus/baseline"]);
  assert.equal(r.status, 0, r.stderr);
  assert.match(
    r.stdout,
    new RegExp(`lexer_diff\\[golden\\]: PASS——${expected} 个 case hash 与冻结基线一致（语料 baseline）`),
  );
});

test("真实仓库：lexer --selftest 必红（J9，退出码 1）", () => {
  const r = run(["lexer", "corpus/baseline", "--selftest"]);
  assert.equal(r.status, 1, r.stderr);
  assert.match(r.stdout, /已篡改清单条目/);
  assert.match(r.stdout, /FAIL/);
});

test("target 分发：五个 target 名都进各自入口（审阅 P3-3 的 main 分发锚）", (t) => {
  // 未知名 → exit 2 且措辞为「未知 target」
  const unknown = run(["nosuch"]);
  assert.equal(unknown.status, 2);
  assert.match(unknown.stderr, /未知 target/);

  // 四个 hash 表型：缺语料位置参数 → exit 2，且用法行带各自 name（证明已分发）
  for (const t of ["lexer", "typeck", "parser", "codegen"]) {
    const r = run([t]);
    assert.equal(r.status, 2, `${t} 缺语料位置参数应 exit 2`);
    assert.ok(!/未知 target/.test(r.stderr), `${t} 必须已被 TARGETS 分发`);
    assert.match(r.stderr, new RegExp(`diff_gate/main\\.mts ${t}_diff <corpus_dir>`));
  }

  // vm 是 override 型：无位置参数是**设计行为**（默认遍历五语料），故用
  // --corpus gap 小规模验证分发可达（不把 733 例全量跑进测试）
  //
  // 产物依赖（#292 终局批补）：vm 臂消费 `cmd/run` release exe + wasm 壳——在无
  // `_build` 的 job（如 scripts-ts / Demo front-end）里跑必红。本文件此前**不在
  // npm test 清单**，故这层依赖一直没人撞上；补登记后必须显式 skip。
  const runExe = path.join(projectRoot(), "moonbit/_build/native/release/build/cmd/run/run.exe");
  if (!fs.existsSync(runExe)) {
    t.diagnostic("skip：vm 臂产物缺失（cmd/run release exe）——分发锚的其余四 target 已覆盖");
    return;
  }
  const r = run(["vm", "--corpus", "gap"]);
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /vm_diff\[golden\]: SAME=20/);
});

test("checkLineColInvariant：同行 byte_off−col 恒等（#297 处方②）", () => {
  // 正例：同行 token 自洽（int@1:1+0 / x@1:5+4 / 42@1:9+8——base 恒 0）
  const ok =
    "0\tInt\tint\t1\t1\t0\n" +
    "1\tIdentifier\tx\t1\t5\t4\n" +
    "2\tNumber\t42\t1\t9\t8\n" +
    "count=2\terrors=0\twarnings=0\n";
  assert.deepEqual(checkLineColInvariant("ok.c", ok), []);

  // 负例：旧回推缺陷形态——0x1F 起始列 7（byte_off=6），旧回推 col 偏 +2 报 9
  //（base = 6-(9-1) = -2 ≠ 同行基准 0）
  const bad =
    "0\tIdentifier\ta\t1\t5\t4\n" +
    "1\tNumber\t31\t1\t9\t6\n" +
    "count=1\terrors=0\twarnings=0\n";
  const errs = checkLineColInvariant("bad.c", bad);
  assert.ok(errs.length === 1, `应报一处失洽：${JSON.stringify(errs)}`);
  const first = errs[0];
  assert.ok(first !== undefined && first.includes("line 1"), "报错定位行号");

  // 跨行 token：独占起始行分组，天然通过
  const ml =
    "0\tString\tab\t1\t11\t10\n" +
    "1\tSemicolon\t;\t2\t4\t13\n" +
    "count=1\terrors=0\twarnings=0\n";
  assert.deepEqual(checkLineColInvariant("ml.c", ml), []);
});
