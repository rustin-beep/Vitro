// typeck.test.mts —— digest 形态（version/note/modes）+ store 往返 + 真实仓库对拍。
//
// typeck 与 lexer 的三处差异是本文件的锚：digest 分节、判红码 2、语料只吃 .c。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import {
  loadTypeckDigest,
  makeTypeckGolden,
  saveTypeckDigest,
  serializeTypeckDigest,
  type TypeckDigest,
} from "./typeck.mts";
import { projectRoot } from "../../internal/capi.mts";
import type { Fail } from "../../internal/diffgate.mts";

const boom: Fail = (msg: string): never => {
  throw new Error(msg);
};

const SAMPLE: TypeckDigest = {
  version: 1,
  note: "n",
  modes: {
    "corpus-beta": { sources: { "b.c": "bbbbbbbb" }, resp_hashes: { "b.c": "1111222233334444" } },
    "corpus-alpha": { sources: { "a.c": "aaaaaaaa" }, resp_hashes: { "a.c": "5555666677778888" } },
  },
};

test("serializeTypeckDigest：顶层 struct 序（version→note→modes）+ 节名排序 + 节内 struct 序", () => {
  const raw = serializeTypeckDigest(SAMPLE);
  assert.match(raw, /^\{\n {2}"version": 1,\n {2}"note": "n",\n {2}"modes": \{/);
  // modes 是 map → 键字节序：corpus-alpha 在 corpus-beta 前
  assert.ok(raw.indexOf('"corpus-alpha"') < raw.indexOf('"corpus-beta"'));
  // 节内 struct 字段序：sources 在 resp_hashes 前
  assert.ok(raw.indexOf('"sources"') < raw.indexOf('"resp_hashes"'));
  assert.ok(raw.endsWith("}\n"));
});

test("真实仓库：serializeTypeckDigest 与入库 golden_digest.json 逐字节一致", () => {
  const rel = "scripts/typeck_diff/golden_digest.json";
  const doc = loadTypeckDigest(projectRoot(), boom);
  const original = fs.readFileSync(path.join(projectRoot(), rel), "utf8");
  assert.equal(serializeTypeckDigest(doc), original);
});

test("makeTypeckGolden：节名带 corpus- 前缀，load/save 往返（临时根）", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-tc-"));
  try {
    saveTypeckDigest(
      dir,
      {
        version: 1,
        note: "n",
        modes: { "corpus-alpha": { sources: { "a.c": "aaaa" }, resp_hashes: { "a.c": "1111" } } },
      },
      boom,
    );
    const store = makeTypeckGolden(dir);
    const sec = store.load("alpha");
    assert.ok(sec !== null);
    assert.deepEqual(sec.sources, { "a.c": "aaaa" });
    assert.deepEqual(sec.cases, { "a.c": "1111" });
    assert.equal(store.load("beta"), null);

    store.save("alpha", { sources: { "a.c": "aaaa", "new.c": "cccc" }, cases: { "a.c": "2222" } });
    const back = loadTypeckDigest(dir, boom);
    assert.equal(back.modes["corpus-alpha"]?.resp_hashes["a.c"], "2222");
    assert.equal(back.modes["corpus-alpha"]?.sources["new.c"], "cccc");
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("loadTypeckDigest：坏 JSON / 版本不符 fail loud", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-tc2-"));
  try {
    assert.deepEqual(loadTypeckDigest(dir, boom).modes, {});
    const target = path.join(dir, "scripts/typeck_diff/golden_digest.json");
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, "{oops");
    assert.throws(() => loadTypeckDigest(dir, boom), /坏或版本不识/);
    fs.writeFileSync(target, '{"version":2,"note":"","modes":{}}');
    assert.throws(() => loadTypeckDigest(dir, boom), /坏或版本不识/);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("真实仓库：typeck 在 baseline 上 PASS 且 fork 例单列（与 Go 版同判据）", () => {
  const r = spawnSync(
    process.execPath,
    [path.join(projectRoot(), "scripts/diff_gate/main.mts"), "typeck", "corpus/baseline"],
    { cwd: projectRoot(), encoding: "utf8" },
  );
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /FORK\(known-golden-skip\) function_pointer_return_ptr\.c/);
  assert.match(r.stdout, /typeck_diff\[golden\]: PASS——\d+ 个 case hash 与冻结基线一致（语料 baseline，1 例 known-fork 跳过）/);
});

test("真实仓库：typeck --selftest 必红（J9；判红码 2 → 由 compareGolden 返 1）", () => {
  const r = spawnSync(
    process.execPath,
    [path.join(projectRoot(), "scripts/diff_gate/main.mts"), "typeck", "corpus/baseline", "--selftest"],
    { cwd: projectRoot(), encoding: "utf8" },
  );
  assert.equal(r.status, 1, r.stderr);
  assert.match(r.stdout, /已篡改清单条目/);
  assert.match(r.stdout, /FAIL/);
});
