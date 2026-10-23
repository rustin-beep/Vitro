// diffgate.test.mts —— 骨架口径（语料归一 / digest 序列化 / argv / J9）+ lexer target。
//
// 真实仓库用例需要 moon 在 PATH（dump 走 `moon run cmd/dump_tokens`），
// 与 CI 同门径；缺 moon 时 fail loud，不静默跳过。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { corpusSHAs, normalizeCorpusTo, parseGateArgs, sha16, sha8, type Fail } from "./diffgate.mts";
import {
  loadLexDigest,
  makeLexGolden,
  saveLexDigest,
  serializeLexDigest,
} from "../diff_gate/targets/lexer.mts";
import { projectRoot } from "./capi.mts";

const boom: Fail = (msg: string): never => {
  throw new Error(msg);
};

test("sha8 / sha16：长度与已知向量", () => {
  assert.equal(sha8(Buffer.from("")), "e3b0c442");
  assert.equal(sha16(Buffer.from("")), "e3b0c44298fc1c14");
});

test("parseGateArgs：语料位置参数 + 三模式 + 互斥", () => {
  const base = parseGateArgs(["corpus/x"], "u", boom);
  assert.equal(base.corpus, "corpus/x");
  assert.equal(base.modes.golden, false);
  assert.equal(base.modes.freezeMB, false);
  assert.equal(base.modes.selftest, false);
  assert.equal(parseGateArgs(["corpus/x", "--selftest"], "u", boom).modes.selftest, true);
  assert.equal(parseGateArgs(["corpus/x", "--freeze-mb"], "u", boom).modes.freezeMB, true);
  assert.throws(() => parseGateArgs(["corpus/x", "--golden", "--freeze-mb"], "u", boom), /互斥/);
  assert.throws(() => parseGateArgs([], "用法…", boom), /用法/);
  assert.throws(() => parseGateArgs(["a", "b"], "u", boom), /未知\/重复参数/);
});

test("parseGateArgs：extraFlags 白名单识别，未列出的仍 fail loud", () => {
  const r = parseGateArgs(["corpus/x", "--baseline"], "u", boom, ["--baseline"]);
  assert.equal(r.modes.extra.has("--baseline"), true);
  assert.throws(() => parseGateArgs(["corpus/x", "--baseline"], "u", boom), /未知\/重复参数/);
});

test("parseGateArgs：--freeze / --refresh 退役提示（不静默接受）", () => {
  assert.throws(() => parseGateArgs(["c", "--freeze"], "u", boom), /工序④.*退役/);
  assert.throws(() => parseGateArgs(["c", "--refresh"], "u", boom), /--refresh 已删除/);
});

test("normalizeCorpusTo / corpusSHAs：LF 归一 + 只收 .c/.h/.in", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-dg-"));
  try {
    fs.writeFileSync(path.join(dir, "a.c"), "int a;\r\nint b;\r\n");
    fs.writeFileSync(path.join(dir, "b.h"), "x\r\n");
    fs.writeFileSync(path.join(dir, "c.in"), "1\r\n");
    fs.writeFileSync(path.join(dir, "skip.txt"), "nope\r\n");

    const dst = path.join(dir, "norm");
    normalizeCorpusTo(dir, dst);
    assert.deepEqual(fs.readdirSync(dst).sort(), ["a.c", "b.h", "c.in"]);
    assert.equal(fs.readFileSync(path.join(dst, "a.c"), "utf8"), "int a;\nint b;\n");

    const shas = corpusSHAs(dir);
    assert.deepEqual(Object.keys(shas).sort(), ["a.c", "b.h", "c.in"]);
    // CRLF 与 LF 同 sha（归一后口径）
    assert.equal(shas["a.c"], sha8(Buffer.from("int a;\nint b;\n")));
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("serializeLexDigest：顶层按 Go struct 字段声明序（version→sources→tsvs）", () => {
  const raw = serializeLexDigest({
    version: 1,
    sources: { zeta: { "b.c": "bbbbbbbb", "a.c": "aaaaaaaa" } },
    tsvs: { "zeta/b.tsv": "1111", "zeta/a.tsv": "2222" },
  });
  // 顶层键序 = Go struct 字段序（不是字典序！字典序会是 sources/tsvs/version）
  assert.match(raw, /^\{\n {2}"version": 1,\n {2}"sources": \{/);
  // 内层 map 键 = 字节字典序
  assert.ok(raw.indexOf('"a.c"') < raw.indexOf('"b.c"'));
  assert.ok(raw.indexOf('"zeta/a.tsv"') < raw.indexOf('"zeta/b.tsv"'));
  assert.ok(raw.endsWith("}\n"));
});

test("makeLexGolden：load 只取本语料段的 cases，save 后回读一致（临时根）", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-dg4-"));
  try {
    saveLexDigest(
      dir,
      {
        version: 1,
        sources: { alpha: { "a.c": "aaaaaaaa" }, beta: { "b.c": "bbbbbbbb" } },
        tsvs: { "alpha/x.tsv": "1111", "beta/y.tsv": "2222" },
      },
      boom,
    );
    const store = makeLexGolden(dir);
    const sec = store.load("alpha");
    assert.ok(sec !== null);
    assert.deepEqual(sec.sources, { "a.c": "aaaaaaaa" });
    assert.deepEqual(sec.cases, { "x.tsv": "1111" }); // 不带语料前缀
    assert.equal(store.load("nope"), null);

    // save 只替换本段 cases，不碰其它段
    store.save("alpha", { sources: { "a.c": "aaaaaaaa", "new.c": "cccccccc" }, cases: { "z.tsv": "9999" } });
    const d = loadLexDigest(dir, boom);
    assert.deepEqual(d.tsvs["beta/y.tsv"], "2222");
    assert.equal(d.tsvs["alpha/x.tsv"], undefined);
    assert.equal(d.tsvs["alpha/z.tsv"], "9999");
    assert.equal(d.sources.alpha?.["new.c"], "cccccccc");
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("真实仓库：serializeLexDigest 与入库 golden_digest.json 逐字节一致", () => {
  // 最强对拍：把入库清单读进来再序列化回去，必须与原文件字节相同。
  // 覆盖「顶层字段序 + 内层键序 + 缩进 + 尾换行」四项口径。
  const rel = "scripts/lexer_diff/golden_digest.json";
  const doc = loadLexDigest(projectRoot(), boom);
  const original = fs.readFileSync(path.join(projectRoot(), rel), "utf8");
  assert.equal(serializeLexDigest(doc), original);
});

test("loadLexDigest：文件缺失返回空骨架；坏 JSON / 版本不符 fail loud", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-dg3-"));
  try {
    // GOLDEN_REL 固定，故用「目录里没有该文件」表达缺失
    assert.deepEqual(loadLexDigest(dir, boom), { version: 1, sources: {}, tsvs: {} });
    const target = path.join(dir, "scripts/lexer_diff/golden_digest.json");
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, "{oops");
    assert.throws(() => loadLexDigest(dir, boom), /坏或版本不识/);
    fs.writeFileSync(target, '{"version":2,"sources":{},"tsvs":{}}');
    assert.throws(() => loadLexDigest(dir, boom), /坏或版本不识/);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

// lexer 的族内测试（含真实仓库对拍 / selftest 证红）已归位到
// diff_gate/targets/lexer.test.mts（2026-10-23 审阅 P3-3：同族各一个测试文件）。

test("未知 target / 缺参数 fail loud（退出码 2）", () => {
  const base = [path.join(projectRoot(), "scripts/diff_gate/main.mts")];
  const r1 = spawnSync(process.execPath, [...base, "nope", "corpus/baseline"], {
    cwd: projectRoot(),
    encoding: "utf8",
  });
  assert.equal(r1.status, 2);
  assert.match(r1.stderr, /未知 target/);

  const r2 = spawnSync(process.execPath, base, { cwd: projectRoot(), encoding: "utf8" });
  assert.equal(r2.status, 2);
  assert.match(r2.stderr, /用法/);
});
