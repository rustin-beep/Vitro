// teaching_annotation_diff.test.mts —— 对拍判定面纯函数（模板比对 / 提取器 / 三方对账）。
//
// 端到端（跑 serve 提取首现序列、catalog 双臂）需要 native 产物，本 job 无
// ——按前置缺失显式 skip 并打印原因；该路径的常规覆盖归 static-gates 的
// annotation 步。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import {
  compareCatalogs,
  extractBuildMatches,
  loadRules,
} from "./catalog.mts";
import { compareTemplate, filterMigrated, goJSONMarshalIndent, parseArgs, recordString } from "./main.mts";
import type { FirstOccurrence } from "./main.mts";
import { projectRoot } from "../internal/capi.mts";
import { GROUPS } from "../gen_demo_algorithms/main.mts";

const MAIN = path.join(import.meta.dirname, "main.mts");

function occ(phase: string, desc: string, extra: Partial<FirstOccurrence> = {}): FirstOccurrence {
  return { algorithm: "bubble", display_name: "冒泡", phase, desc, code_line: 3, src: "line3", ...extra };
}

test("parseArgs：五 flag 全收；未知参数报用法错", () => {
  const ok = parseArgs(["--only", "a,b", "--backend-wasm", "--freeze", "--catalog-check", "--catalog-selftest"]);
  assert.ok("args" in ok);
  if ("args" in ok) {
    assert.equal(ok.args.only, "a,b");
    assert.equal(ok.args.backendWasm, true);
    assert.equal(ok.args.freeze, true);
    assert.equal(ok.args.catalogCheck, true);
    assert.equal(ok.args.catalogSelftest, true);
  }
  assert.ok("usage" in parseArgs(["--nope"]));
  assert.ok("usage" in parseArgs(["--only"]));
  assert.deepEqual(parseArgs([]), {
    args: { only: "", backendWasm: false, catalogCheck: false, catalogSelftest: false, freeze: false },
  });
});

test("compareTemplate：同键同值 → 无记录；description 变 → diff", () => {
  assert.deepEqual(compareTemplate("t", [occ("p", "d")], [occ("p", "d")]), []);
  const recs = compareTemplate("t", [occ("p", "d")], [occ("p", "d", { display_name: "别的" })]);
  assert.equal(recs.length, 1);
  assert.equal(recs[0]?.kind, "diff");
});

test("compareTemplate：golden 多 → missing；actual 多 → extra（双指针顺序语义）", () => {
  const g = [occ("p1", "a"), occ("p2", "b")];
  const a = [occ("p1", "a"), occ("p3", "c")];
  const recs = compareTemplate("t", g, a);
  assert.deepEqual(recs.map((r) => r.kind), ["missing", "extra"]);
  assert.equal(recs[0]?.golden?.phase, "p2");
  assert.equal(recs[1]?.actual?.phase, "p3");
});

test("recordString：missing/extra 文案逐字（Go %q = JSON 双引号）", () => {
  const missing = recordString({ template: "tpl", kind: "missing", golden: occ("p", "d") });
  assert.equal(missing, "[tpl] missing: bubble/p/\"d\" (line 3)");
  const extra = recordString({ template: "tpl", kind: "extra", actual: occ("p", "d") });
  assert.equal(extra, "[tpl] extra:   bubble/p/\"d\" (line 3)");
  const diff = recordString({ template: "tpl", kind: "diff", golden: occ("p", "d"), actual: occ("q", "d2") });
  assert.match(diff, /^\[tpl\] diff: {4}golden \{Algorithm:bubble DisplayName:冒泡 Phase:p Desc:d CodeLine:3 Src:line3\} vs actual \{/);
});

test("filterMigrated：只留已迁移族", () => {
  const es = [occ("p", "d", { algorithm: "bubble" }), occ("p", "d", { algorithm: "quick" })];
  assert.deepEqual(
    filterMigrated(es, new Set(["bubble"])).map((e) => e.algorithm),
    ["bubble"],
  );
});

test("extractBuildMatches：真实仓库 43 条，族名/显示名非空且 vis 为布尔", () => {
  const root = projectRoot();
  const ms = extractBuildMatches(path.join(root, "moonbit/teaching/steps"));
  assert.equal(ms.length, 43);
  for (const m of ms) {
    assert.ok(m.family.length > 0, m.family);
    assert.ok(m.displayName.length > 0, m.family);
    assert.equal(typeof m.visEvents, "boolean");
  }
});

test("extractBuildMatches：evidence= 第 6 参合法；参数数错 / 未闭合必 fail loud", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-tad-"));
  const files = ["detect.mbt", "detect_search.mbt", "detect_graph.mbt", "detect_tree.mbt", "detect_structures.mbt", "detect_math.mbt"];
  // 只填 detect.mbt，其余空文件（提取器要求文件存在）
  for (const f of files) fs.writeFileSync(path.join(dir, f), "");
  fs.writeFileSync(
    path.join(dir, "detect.mbt"),
    [
      'fn detect() -> Unit {',
      '  build_match("fam_a", "甲", f, 1, [])',
      '  build_match("fam_b", "乙", f, 2, ["x"], evidence="e")',
      "}",
    ].join("\n"),
  );
  const ms = extractBuildMatches(dir);
  assert.deepEqual(ms, [
    { family: "fam_a", displayName: "甲", visEvents: false },
    { family: "fam_b", displayName: "乙", visEvents: true },
  ]);

  // 参数数 4（非 evidence 形态）→ 抛
  fs.writeFileSync(path.join(dir, "detect.mbt"), 'build_match("a", "b", f, 1)\n');
  assert.throws(() => extractBuildMatches(dir), /参数数 4 ≠ 5/);

  // 括号未闭合 → 抛
  fs.writeFileSync(path.join(dir, "detect.mbt"), 'build_match("a", "b", f, 1, []\n');
  assert.throws(() => extractBuildMatches(dir), /未闭合/);
});

test("GROUPS 直连：7 组，组内族非空（终局批删 Go 后不再文本解析）", () => {
  assert.equal(GROUPS.length, 7);
  for (const g of GROUPS) {
    assert.ok(g.id.length > 0);
    assert.ok(g.label.length > 0);
    assert.ok(g.algos.length > 0, g.id);
  }
});

test("loadRules：真实 rules.json 43 族 / budget>0；空 migrated 与非法 kind 必抛", () => {
  const root = projectRoot();
  const r = loadRules(path.join(root, "scripts/teaching_annotation_diff/rules.json"));
  assert.equal(r.migrated_algorithms.length, 43);
  assert.ok(r.step_budget > 0);

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-tad-r-"));
  const p = path.join(dir, "rules.json");
  fs.writeFileSync(p, JSON.stringify({ as_of: "x", migrated_algorithms: [], step_budget: 4000, exemptions: [] }));
  assert.throws(() => loadRules(p), /migrated_algorithms 为空/);
  fs.writeFileSync(
    p,
    JSON.stringify({ as_of: "x", migrated_algorithms: ["a"], step_budget: 4000, exemptions: [{ template: "t", kind: "bogus", reason: "r" }] }),
  );
  assert.throws(() => loadRules(p), /豁免 kind 非法/);
});

test("compareCatalogs：绿集零错；六类红各自成条（条数/display/vis/rules/demo 幽灵/归属分叉）", () => {
  const b = {
    schema: "v1",
    total: 2,
    groups: [
      { id: "g1", label: "组一" },
      { id: "g2", label: "组二" },
    ],
    algorithms: [
      { family: "f1", display_name: "一", group: "g1", vis_events: true },
      { family: "f2", display_name: "二", group: "g2", vis_events: false },
    ],
  };
  const a = [
    { family: "f1", displayName: "一", visEvents: true },
    { family: "f2", displayName: "二", visEvents: false },
  ];
  const migrated = new Set(["f1", "f2"]);
  const demo = [
    { id: "g1", label: "组一", algos: ["f1"] },
    { id: "g2", label: "组二", algos: ["f2"] },
  ];
  assert.deepEqual(compareCatalogs(a, b, migrated, demo), []);

  // 条数
  assert.match(compareCatalogs(a.slice(0, 1), b, migrated, demo).join("\n"), /条数：判据提取物 1 ≠ 引擎导出 2/);
  // display_name
  const badDisp = a.map((x) => ({ ...x }));
  badDisp[0]!.displayName = "改";
  assert.match(compareCatalogs(badDisp, b, migrated, demo).join("\n"), /f1 display_name：判据 "改" ≠ 引擎 "一"/);
  // vis_events
  const badVis = a.map((x) => ({ ...x }));
  badVis[1]!.visEvents = true;
  assert.match(compareCatalogs(badVis, b, migrated, demo).join("\n"), /f2 vis_events：判据第 5 参恒空=false ≠ 引擎 false/);
  // rules 缺键
  assert.match(compareCatalogs(a, b, new Set(["f1"]), demo).join("\n"), /族数：rules.json 1 ≠ 引擎导出 2/);
  // demo 幽灵族
  const ghost = demo.map((g) => ({ ...g, algos: [...g.algos] }));
  ghost[0]!.algos.push("phantom");
  assert.match(compareCatalogs(a, b, migrated, ghost).join("\n"), /列族 "phantom" 不在引擎导出/);
  // demo 归属分叉
  const misfile = demo.map((g) => ({ ...g, algos: [...g.algos] }));
  misfile[1]!.algos.push("f1");
  assert.match(compareCatalogs(a, b, migrated, misfile).join("\n"), /列族 "f1" 引擎归组为 "g1"（归属分叉）/);
});

/** 端到端前置：debug serve exe（主对拍）/ release vitro + vivo_js（catalog）。 */
function prereq(root: string, which: "serve" | "catalog"): { ok: boolean; why: string } {
  const win = process.platform === "win32";
  const serveExe = path.join(root, "moonbit/_build/native/debug/build/cmd/serve", win ? "serve.exe" : "serve");
  const vitroExe = path.join(root, "moonbit/_build/native/release/build/cmd/vitro", win ? "vitro.exe" : "vitro");
  const jsEntry = path.join(root, "moonbit/_build/js/release/build/cmd/vitro_js/vitro_js.js");
  const need = which === "serve" ? [serveExe] : [vitroExe, jsEntry];
  const missing = need.filter((p) => !fs.existsSync(p));
  return {
    ok: missing.length === 0,
    why:
      missing.length === 0
        ? ""
        : `缺产物 ${missing.length} 件（先跑 cd moonbit && MOON_CC=clang moon build --target native cmd/serve / --release --target native cmd/vitro）`,
  };
}

test("端到端 --only bubble：首现序列与 golden 一致（缺产物显式 skip）", (t) => {
  const root = projectRoot();
  const pre = prereq(root, "serve");
  if (!pre.ok) {
    t.skip(`前置缺失：${pre.why}（该路径覆盖归 static-gates 的 annotation 步）`);
    return;
  }
  const r = spawnSync(process.execPath, [MAIN, "--only", "bubble"], { cwd: root, encoding: "utf8" });
  assert.equal(r.status, 0, (r.stdout ?? "") + (r.stderr ?? ""));
  assert.match(r.stdout, /1 模板 × 已迁移族 43 算法（budget 4000；豁免 0）/);
  assert.match(r.stdout, /OK: 已迁移族首现序列与 golden 逐条一致/);
});

test("端到端 --catalog-check：判据 43 ↔ 双臂 ↔ rules 43（缺产物显式 skip）", (t) => {
  const root = projectRoot();
  const pre = prereq(root, "catalog");
  if (!pre.ok) {
    t.skip(`前置缺失：${pre.why}（该路径覆盖归 static-gates 的 annotation 步）`);
    return;
  }
  const r = spawnSync(process.execPath, [MAIN, "--catalog-check"], { cwd: root, encoding: "utf8" });
  assert.equal(r.status, 0, (r.stdout ?? "") + (r.stderr ?? ""));
  assert.match(r.stdout, /绿（判据 43 条 ↔ 双臂导出一致 ↔ rules 43 ↔ demo 分组表）/);
});

test("用法错 exit 2", () => {
  const r = spawnSync(process.execPath, [MAIN, "--nope"], { cwd: projectRoot(), encoding: "utf8" });
  assert.equal(r.status, 2);
});

test("P2-1：goJSONMarshalIndent 复刻 Go SetEscapeHTML（< > & 与 U+2028/2029）", () => {
  const out = goJSONMarshalIndent({ s: "<a>&</a>", u: "\u2028\u2029" });
  assert.ok(!out.includes("<") && !out.includes(">") && !out.includes("&"), "不得出现裸字符：" + out);
  assert.match(out, /\\u003c/);
  assert.match(out, /\\u003e/);
  assert.match(out, /\\u0026/);
  assert.match(out, /\\u2028/);
  assert.match(out, /\\u2029/);
  // 键序/缩进/尾换行不变（不含转义字符时与 JSON.stringify 一致）
  assert.equal(goJSONMarshalIndent({ a: 1, b: 2 }), JSON.stringify({ a: 1, b: 2 }, null, 2));
});

test("P3-1：布尔 flag 带 = 值显式拒绝（rc=2，不静默当 true）", () => {
  const root = projectRoot();
  for (const args of [["--freeze=false", "--only", "bubble"], ["--backend-wasm=false"], ["--catalog-check=false"]]) {
    const r = spawnSync(process.execPath, [MAIN, ...args], { cwd: root, encoding: "utf8" });
    assert.equal(r.status, 2, args.join(" "));
    assert.match(r.stderr, /布尔 flag .* 不接受值/);
  }
});
