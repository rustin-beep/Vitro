// single_source.test.mts —— scanDefs / judgeEntry 红路（fixture）+ 真实仓库端到端
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { canon, judgeEntry, loadRules, scanDefs } from "./main.mts";
import type { Entry, RulesDoc } from "./main.mts";
import { projectRoot } from "../../internal/capi.mts";

const MAIN = path.join(import.meta.dirname, "main.mts");

test("canon：反斜杠与 ./ 归一", () => {
  const bs = String.fromCharCode(92);
  assert.equal(canon(`a${bs}b` + `${bs}c.mbt`), "a/b/c.mbt");
  assert.equal(canon("./a/./b.mbt"), "a/b.mbt");
  // #392 审阅 P3-1（2026-10-31）：反斜杠段必须参与 .. 折叠——首版
  // replace-only 形态下 posix 得 "a/../b.mbt" / win 得 "b.mbt"（平台分叉，
  // 「双平台同语义」证伪锚）；path.posix.normalize 形态双平台恒 "b.mbt"
  assert.equal(canon(`a${bs}..${bs}b.mbt`), "b.mbt");
  assert.equal(canon(`a${bs}b/.${bs}${bs}c${bs}${bs}..${bs}d`), "a/b/d");
  assert.equal(canon(`a/b/../c//../d`), "a/d", "正斜杠段同样折叠（posix 语义恒定）");
});

function tmpTree(files: Record<string, string>): string {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-ss-"));
  for (const [rel, body] of Object.entries(files)) {
    fs.mkdirSync(path.dirname(path.join(root, rel)), { recursive: true });
    fs.writeFileSync(path.join(root, rel), body);
  }
  return root;
}

function rules(over: Partial<RulesDoc> = {}): RulesDoc {
  return { schema: 1, search_roots: [], search_exclude_dirs: [], entries: [], ...over };
}

test("scanDefs：注释跳过 / exclude_line / exclude dirs / 只扫 .rs 与 .mbt", () => {
  const root = tmpTree({
    "a/impl.mbt": "fn target() -> Unit {\n}\n",
    "a/usage.mbt": "let x = target\n",
    "b/comment.mbt": "// fn target() -> Unit\nfn other() -> Unit { }\n",
    "b/method.mbt": "fn (self : T) target() -> Unit { }\n",
    "skipdir/c.mbt": "fn target() -> Unit { }\n",
    "c/notes.md": "fn target() -> Unit\n",
  });
  const rd = rules({ search_roots: [path.join(root, "a"), path.join(root, "b"), path.join(root, "skipdir"), path.join(root, "c")], search_exclude_dirs: ["skipdir"] });
  const hits = scanDefs(rd, "fn target", "fn \\(self");
  assert.equal(hits.length, 1, "只应命中 a/impl.mbt：" + JSON.stringify(hits));
  assert.ok(hits[0]!.endsWith("a/impl.mbt"));
});

test("judgeEntry enforced：extra（第二份实现）与 missing（单源缺失）", () => {
  const root = tmpTree({ "a/impl.mbt": "fn target() -> Unit { }\n", "a/second.mbt": "fn target() -> Unit { }\n" });
  const rd = rules({ search_roots: [path.join(root, "a")] });
  const base: Entry = {
    id: "X", concept: "c", kind: "enforced", def_pattern: "fn target", exclude_line_pattern: "",
    allowed_def_files: [], copies_must_match: [], rust_source: "", moonbit_source: "", sync: "", consumers: [], anchor: "", upstream_ref: "",
  };
  const hits = scanDefs(rd, base.def_pattern, "");
  const allowed = hits.slice(0, 1).map((h) => h);
  const okEntry = { ...base, allowed_def_files: allowed };
  assert.equal(judgeEntry(rd, okEntry).ok, false, "命中 2 处但只允许 1 → 应红（extra）");
  assert.equal(judgeEntry(rd, okEntry).extra.length, 1);
  const missing = judgeEntry(rd, { ...base, allowed_def_files: [...allowed, "a/ghost.mbt"] });
  assert.equal(missing.ok, false);
  assert.ok(missing.missing.some((m) => m.endsWith("a/ghost.mbt")));
});

test("judgeEntry copies：<2 份 / 副本漂移 / 缺失 三路红", () => {
  const root = tmpTree({ "x/a.c": "same\n", "x/b.c": "same\n", "x/c.c": "diff\n" });
  const rd = rules();
  const base: Entry = {
    id: "C", concept: "c", kind: "copies", def_pattern: "", exclude_line_pattern: "", allowed_def_files: [],
    copies_must_match: [], rust_source: "", moonbit_source: "", sync: "", consumers: [], anchor: "", upstream_ref: "",
  };
  assert.match(judgeEntry(rd, { ...base, copies_must_match: [path.join(root, "x/a.c")] }).msg, /须声明 ≥2 份路径/);
  assert.match(judgeEntry(rd, { ...base, copies_must_match: [path.join(root, "x/a.c"), path.join(root, "x/c.c")] }).msg, /副本漂移/);
  assert.match(judgeEntry(rd, { ...base, copies_must_match: [path.join(root, "x/a.c"), path.join(root, "x/nope.c")] }).msg, /副本缺失/);
  assert.equal(judgeEntry(rd, { ...base, copies_must_match: [path.join(root, "x/a.c"), path.join(root, "x/b.c")] }).ok, true);
});

test("judgeEntry：未知 kind / 声明源路径不存在 → 红", () => {
  const rd = rules();
  const base: Entry = {
    id: "Z", concept: "c", kind: "weird", def_pattern: "", exclude_line_pattern: "", allowed_def_files: [],
    copies_must_match: [], rust_source: "", moonbit_source: "", sync: "", consumers: [], anchor: "", upstream_ref: "",
  };
  assert.match(judgeEntry(rd, base).msg, /未知 kind: weird/);
  assert.match(judgeEntry(rd, { ...base, kind: "registered", rust_source: "no/such/file.rs" }).msg, /声明的源路径不存在/);
});

test("真实仓库：三模式全绿（默认报告 / -check / --selftest）", () => {
  const root = projectRoot();
  const rd = loadRules();
  assert.ok(rd.entries.length > 0);
  const bad = rd.entries.filter((e) => !judgeEntry(rd, e).ok);
  assert.deepEqual(bad.map((e) => e.id), [], "真实清单应全绿");

  for (const args of [[], ["-check"], ["--selftest"]]) {
    const r = spawnSync(process.execPath, [MAIN, ...args], { cwd: root, encoding: "utf8" });
    assert.equal(r.status, 0, `${args.join(" ") || "(默认)"}: ${r.stdout}${r.stderr}`);
  }
  const bad2 = spawnSync(process.execPath, [MAIN, "--nope"], { cwd: root, encoding: "utf8" });
  assert.equal(bad2.status, 2);
});
