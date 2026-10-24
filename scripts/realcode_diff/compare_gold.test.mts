// compare_gold 对账判据单测（四件套之三：node:test）——红锚形态用注入的
// 假 result/gold（对账逻辑是纯函数化 CLI，篡改矩阵在 fixture 内完成）。
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync, mkdirSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const script = path.join(here, "compare_gold.mts");

interface Case {
  name: string;
  gold: Record<string, unknown>;
  result: Array<Record<string, unknown>>;
  expect: "OK" | "DRIFT";
  needle?: string;
}

const goldMeta = (files: Record<string, unknown>) => ({
  _meta: { source_fork: "x", source_commit: "y", total: Object.keys(files).length, buckets: {} },
  files,
});

const cases: Case[] = [
  {
    name: "一致（全字段同）",
    gold: goldMeta({
      "a.c": { clang_ok: false, gcc_ok: true, vitro_errs: 2, vitro_warns: 1, layer: "parse", run: "skip_net", codes: { E2005: 2, W1019: 1 } },
    }),
    result: [
      { path: "a.c", clang_ok: false, gcc_ok: true, vitro_errors: 2, vitro_warnings: 1, vitro_layer: "parse", run_compare: "skip_net", vitro_diags: [{ code: "E2005", severity: "error" }, { code: "E2005", severity: "error" }, { code: "W1019", severity: "warning" }] },
    ],
    expect: "OK",
  },
  {
    name: "码计数漂移",
    gold: goldMeta({ "a.c": { clang_ok: true, vitro_errs: 1, vitro_warns: 0, layer: "ok", run: "match", codes: { E2005: 1 } } }),
    result: [
      { path: "a.c", clang_ok: true, vitro_errors: 2, vitro_warnings: 0, vitro_layer: "ok", run_compare: "match", vitro_diags: [{ code: "E2005", severity: "error" }, { code: "E2005", severity: "error" }] },
    ],
    expect: "DRIFT",
    needle: "码 E2005 计数 1 → 2",
  },
  {
    name: "本轮缺条（语料被删）",
    gold: goldMeta({ "a.c": { clang_ok: true, vitro_errs: 0, vitro_warns: 0, layer: "ok", run: "match", codes: {} }, "b.c": { clang_ok: true, vitro_errs: 0, vitro_warns: 0, layer: "ok", run: "match", codes: {} } }),
    result: [{ path: "a.c", clang_ok: true, vitro_errors: 0, vitro_warnings: 0, vitro_layer: "ok", run_compare: "match" }],
    expect: "DRIFT",
    needle: "本轮结果缺失",
  },
  {
    name: "gold 缺条（新语料未冻）",
    gold: goldMeta({ "a.c": { clang_ok: true, vitro_errs: 0, vitro_warns: 0, layer: "ok", run: "match", codes: {} } }),
    result: [
      { path: "a.c", clang_ok: true, vitro_errors: 0, vitro_warnings: 0, vitro_layer: "ok", run_compare: "match" },
      { path: "new.c", clang_ok: true, vitro_errors: 0, vitro_warnings: 0, vitro_layer: "ok", run_compare: "match" },
    ],
    expect: "DRIFT",
    needle: "gold 缺该条",
  },
  {
    name: "layer/run/errs 多字段漂移",
    gold: goldMeta({ "a.c": { clang_ok: true, vitro_errs: 69, vitro_warns: 0, layer: "typeck", run: "", codes: { E3023: 46, E3054: 23 } } }),
    result: [{ path: "a.c", clang_ok: true, vitro_errors: 0, vitro_warnings: 0, vitro_layer: "ok" }],
    expect: "DRIFT",
    needle: 'layer "typeck" → "ok"',
  },
];

test("compare_gold 判据矩阵（一致/漂移五形态）", async (t) => {
  // fixture：临时仓形目录（corpora.json 缺 gold 键→走缺省名，fixture 不受
  // 真仓登记影响——临时目录内自建 scripts/realcode_diff/ 结构）
  for (const c of cases) {
    await t.test(c.name, () => {
      const root = mkdtempSync(path.join(tmpdir(), "cg-"));
      const rd = path.join(root, "scripts", "realcode_diff");
      mkdirSync(rd, { recursive: true });
      writeFileSync(path.join(rd, "corpora.json"), JSON.stringify({ corpora: {} }));
      writeFileSync(path.join(rd, "gold_fixture.json"), JSON.stringify(c.gold));
      const rp = path.join(root, "result.json");
      writeFileSync(rp, JSON.stringify(c.result));
      let out = "";
      let errOut = "";
      let rc = 0;
      const proc = spawnSync(
        process.execPath,
        ["--experimental-strip-types", script, "fixture", rp],
        { encoding: "utf8", cwd: root },
      );
      out = proc.stdout ?? "";
      errOut = proc.stderr ?? "";
      rc = proc.status ?? 0;
      if (c.expect === "OK") {
        assert.equal(rc, 0, `应一致，实得漂移：${errOut}`);
        assert.match(out, /对拍 OK：1 条逐字段一致/);
      } else {
        assert.equal(rc, 1, "漂移应 exit 1");
        const needle = c.needle ?? ".";
        assert.match(errOut, new RegExp(needle.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
      }
    });
  }
});

test("gold 不可读 fail loud（exit 2）", () => {
  const root = mkdtempSync(path.join(tmpdir(), "cg2-"));
  const rd = path.join(root, "scripts", "realcode_diff");
  mkdirSync(rd, { recursive: true });
  writeFileSync(path.join(rd, "corpora.json"), JSON.stringify({ corpora: {} }));
  const rp = path.join(root, "result.json");
  writeFileSync(rp, "[]");
  const miss = spawnSync(
    process.execPath,
    ["--experimental-strip-types", script, "missing", rp],
    { encoding: "utf8", cwd: root },
  );
  assert.equal(miss.status, 2, "gold 缺失应 exit 2");
  assert.match(miss.stderr ?? "", /金样本不可读/);
});

test("与在库 gold 契约面（chibicc 键集含 union.c——防 fixture 与真仓漂移）", () => {
  const g = JSON.parse(readFileSync(path.join(here, "gold_chibicc.json"), "utf8"));
  assert.ok("union.c" in g.files, "chibicc gold 应含 union.c（A 线 #278 重冻锚）");
});
