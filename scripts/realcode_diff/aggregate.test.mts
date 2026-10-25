// aggregate 聚合口径单测：分桶/键序/渗漏面/尾随换行。
import { test } from "node:test";
import assert from "node:assert/strict";
import { aggregateResults, DEFAULT_GOLD_NOTE } from "./aggregate.mts";
import type { FileResult } from "./types.mts";

const opts = {
  goldOut: "gold_fx.json",
  aggRepo: "fixture",
  sourceFork: "https://example.invalid/fork",
  sourceCommit: "abc123",
};

function entry(over: Partial<FileResult> & { path: string }): FileResult {
  return {
    clang_ok: true,
    gcc_ok: true,
    clang_errors: 0,
    clang_warnings: 0,
    vitro_errors: 0,
    vitro_warnings: 0,
    stripped_try: false,
    ...over,
  };
}

test("aggregateResults：分桶/码计数/键序/尾随换行", () => {
  const results: FileResult[] = [
    entry({ path: "a.c" }),
    entry({ path: "b.c", clang_ok: false }),
    entry({
      path: "c.c",
      gcc_ok: false,
      vitro_errors: 2,
      vitro_warnings: 1,
      vitro_layer: "parse",
      run_compare: "match",
      vitro_diags: [
        { severity: "error", code: "W1018", line: 1, column: 1, message: "leak-w" },
        { severity: "error", code: "E2005", line: 2, column: 2, message: "leak-e" },
        { severity: "warning", code: "H3057", line: 3, column: 3, message: "h" },
        { severity: "error", code: "E2005", line: 4, column: 4, message: "leak-e2" },
      ],
    }),
    entry({ path: "d.c", clang_ok: false, gcc_ok: false }),
  ];
  const out = aggregateResults(results, opts);
  assert.ok(out.endsWith("\n"), "金样本应有尾随换行");
  const g = JSON.parse(out) as {
    _meta: { total: number; buckets: Record<string, number>; gcc_buckets: Record<string, number>; note: string };
    files: Record<string, { codes: Record<string, number>; layer: string; run: string }>;
  };
  assert.equal(g._meta.total, 4);
  assert.deepEqual(g._meta.buckets, { clang_red: 2, both_green: 1, vitro_red: 1 });
  assert.deepEqual(g._meta.gcc_buckets, { both_green: 1, rescued: 1, divergence: 1, both_red: 1 });
  assert.equal(g._meta.note, DEFAULT_GOLD_NOTE);
  assert.deepEqual(g.files["c.c"]?.codes, { E2005: 2, H3057: 1, W1018: 1 });
  assert.equal(g.files["c.c"]?.layer, "parse");
  assert.equal(g.files["c.c"]?.run, "match");

  // Go map 序列化口径：码键字节序（E < H < W）
  const codesAt = out.indexOf('"codes": {');
  assert.ok(out.indexOf('"E2005"', codesAt) < out.indexOf('"H3057"', codesAt));
  assert.ok(out.indexOf('"H3057"', codesAt) < out.indexOf('"W1018"', codesAt));
  // 协议红线：诊断 message 绝不入库
  assert.equal(out.includes("leak-e"), false);
  assert.equal(out.includes('"message"'), false);
});

test("aggregateResults：缺字段按 Go 零值兜底（不产 undefined 键）", () => {
  const out = aggregateResults([{ path: "x.c" } as FileResult], opts);
  const g = JSON.parse(out) as { files: Record<string, Record<string, unknown>> };
  assert.deepEqual(g.files["x.c"], {
    clang_ok: false,
    gcc_ok: false,
    vitro_errs: 0,
    vitro_warns: 0,
    codes: {},
    layer: "",
    run: "",
  });
});
