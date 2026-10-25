// main CLI 参数面与报告格式单测（Go flag 语义：-x v / -x=v / --x / 遇位置参数即止）。
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { parseArgs, writeReport } from "./main.mts";
import type { FileResult } from "./types.mts";

const here = path.dirname(fileURLToPath(import.meta.url));
const script = path.join(here, "main.mts");
const repoRoot = path.resolve(here, "..", "..");

function base(over: Partial<FileResult> & { path: string }): FileResult {
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

test("parseArgs：默认值与全旗标", () => {
  const d = parseArgs([], "/repo");
  assert.equal(d.repo, "");
  assert.equal(d.out, "_diff_out");
  assert.equal(d.batch, 25);
  assert.equal(d.vitro, "/repo");
  assert.equal(d.goldOut, "gold_signatures.json");
  assert.equal(d.aggSourceCommit, "e5dad3f");

  const o = parseArgs(
    [
      "-repo", "r", "-out", "o", "-filter", "f", "-limit", "3", "-batch", "5",
      "-vitro", "v", "-corpus", "c", "-gold-out", "g", "-agg-repo", "a",
      "-agg-source-fork", "sf", "-agg-source-commit", "sc", "-gcc", "gcc",
      "-check", "-gcc-only", "-probe",
    ],
    "/repo",
  );
  assert.equal(o.repo, "r");
  assert.equal(o.out, "o");
  assert.equal(o.limit, 3);
  assert.equal(o.batch, 5);
  assert.equal(o.vitro, "v");
  assert.equal(o.goldOut, "g");
  assert.equal(o.aggSourceCommit, "sc");
  assert.equal(o.check, true);
  assert.equal(o.gccOnly, true);
  assert.equal(o.probe, true);
});

test("parseArgs：布尔 =value / 双横线 / 遇位置参数即止 / -- 终止", () => {
  assert.equal(parseArgs(["-check=false"], "/r").check, false);
  assert.equal(parseArgs(["--probe=1"], "/r").probe, true);
  assert.equal(parseArgs(["-probe", "false"], "/r").probe, true); // Go 布尔不吃下一个 token
  assert.equal(parseArgs(["-repo", "x", "pos", "-check"], "/r").check, false);
  assert.equal(parseArgs(["-check", "--", "-probe"], "/r").probe, false);
});

test("parseArgs 错误面：未知旗标 / 缺值 / 非法整数 → exit 2", () => {
  const cases: Array<[string[], RegExp]> = [
    [["-nope"], /flag provided but not defined/],
    [["-repo"], /flag needs an argument/],
    [["-limit", "x"], /invalid value/],
  ];
  for (const [args, needle] of cases) {
    const p = spawnSync(process.execPath, ["--experimental-strip-types", script, ...args], {
      encoding: "utf8",
      cwd: repoRoot,
      env: { ...process.env, VITRO_ROOT: repoRoot },
    });
    assert.equal(p.status, 2, `args=${args.join(" ")}`);
    assert.match(p.stderr ?? "", needle);
  }
});

test("parseArgs -h：usage 走 stderr、exit 0", () => {
  const p = spawnSync(process.execPath, ["--experimental-strip-types", script, "-h"], {
    encoding: "utf8",
    cwd: repoRoot,
    env: { ...process.env, VITRO_ROOT: repoRoot },
  });
  assert.equal(p.status, 0);
  assert.match(p.stderr ?? "", /用法: node scripts\/realcode_diff\/main\.mts/);
});

test("writeReport：分桶/码 top/层分布/明细格式", () => {
  const out = mkdtempSync(path.join(tmpdir(), "rc-report-"));
  const results: FileResult[] = [
    base({ path: "red.c", clang_ok: false, clang_errors: 1, clang_first_error: "red.c:1:1: error: boom" }),
    base({
      path: "vr.c",
      vitro_errors: 2,
      vitro_layer: "parse",
      vitro_diags: [
        { severity: "error", code: "E2005", line: 1, column: 2, message: "m1" },
        { severity: "error", code: "E2005", line: 2, column: 3, message: "m2" },
        { severity: "warning", code: "W1018", line: 3, column: 4, message: "w" },
      ],
      stripped_try: true,
      strip_layer: "typeck",
      strip_errors: 1,
      run_compare: "mismatch",
      run_detail: "输出不一致: V 3B / C 4B",
    }),
  ];
  writeReport(out, results);
  const md = readFileSync(path.join(out, "report.md"), "utf8");
  assert.match(md, /## 分桶\n\n\| 桶 \| 数量 \|\n\|---\|---\|\n\| 总文件 \| 2 \|/);
  assert.match(md, /\| Clang 红\(平台差异\/真错\/链接需求\) \| 1 \|/);
  assert.match(md, /\| Vitro 红\(Clang 绿\) \| 1 \|/);
  assert.match(md, /\| E2005 \| 2 \|/);
  assert.match(md, /\| parse \| 1 \|/);
  assert.match(md, /- mismatch: 1/);
  assert.match(md, /- `vr\.c`: mismatch — 输出不一致: V 3B \/ C 4B/);
  assert.match(md, /- `red\.c`: red\.c:1:1: error: boom/);
  assert.match(md, /剥壳层=typeck\/1: E2005 1:2 m1/);
  rmSync(out, { recursive: true, force: true });
});
