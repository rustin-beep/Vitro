// skill_path_check.test.mts —— token 判定九路 / 临时树端到端 / 真实仓库计数面。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { checkToken, run } from "./main.mts";
import type { Rules } from "./main.mts";
import { projectRoot } from "../internal/capi.mts";

const MAIN = path.join(import.meta.dirname, "main.mts");

const RULES: Rules = {
  whitelist_prefixes: ["tmp/", "moonbit/_build/", "native/"],
  dead_paths: ["native/tests/cases"],
  skip_files: [],
  min_hits: 2,
};

const TOP = new Set(["scripts", "corpus", "tmp", "native", "AGENTS.md"]);

test("checkToken 九路：存在/不存在/变量截断/占位符/白名单/退役域/file:line/非根前缀/裸名", () => {
  const cases: Array<[string, string, boolean]> = [
    ["scripts/bin/vitro", "scripts/bin/vitro", false],
    ["scripts/nope/zzz", "scripts/nope/zzz", false],
    ["corpus/$d", "corpus", false],
    ["corpus/<suite>/x.c", "corpus", false],
    ["tmp/anything/here", "", true],
    ["native/tests/cases/$d", "", true],
    // Go 原行为：段内冒号即 break —— file:line 只 stat 到所在**目录**，文件名不进 pfx
    ["corpus/baseline/a.c:3", "corpus/baseline", false],
    ["cmd/run/run.exe", "", true],
    ["p.c", "", true],
  ];
  for (const [tok, wantPfx, wantSkip] of cases) {
    const got = checkToken(tok, TOP, RULES);
    assert.equal(got.pfx, wantPfx, tok);
    assert.equal(got.skipped, wantSkip, tok);
  }
});

test("checkToken：首尾 . , ; : 剥离；./ 前缀剥离；绝对/~/ 跳过", () => {
  // Go strings.Trim(tok,".,;:") 会连 ./ 的首点一起吃掉 → "/corpus/a.c" → 按绝对路径
  // 跳过。这是 Go 版既有行为（selftest 九路未覆盖 ./ 形态），重写照抄不"顺手修"。
  assert.deepEqual(checkToken("./corpus/a.c,", TOP, RULES), { pfx: "", skipped: true });
  assert.deepEqual(checkToken("/abs/path", TOP, RULES), { pfx: "", skipped: true });
  assert.deepEqual(checkToken("~/x", TOP, RULES), { pfx: "", skipped: true });
  assert.deepEqual(checkToken(".gitignore", TOP, RULES), { pfx: "", skipped: true });
  // 尾部标点剥离在无前导标点时生效
  assert.equal(checkToken("corpus/a.c,", TOP, RULES).pfx, "corpus/a.c");
  assert.equal(checkToken("corpus/a.c;", TOP, RULES).pfx, "corpus/a.c");
});

/** 造最小仓库：skills md + rules.json + 需被引用的文件。 */
function tmpRepo(opts: { md: string; rules?: Partial<Rules> }): string {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-spc-"));
  fs.mkdirSync(path.join(root, ".agents/skills/demo"), { recursive: true });
  fs.mkdirSync(path.join(root, "scripts/skill_path_check"), { recursive: true });
  fs.mkdirSync(path.join(root, "scripts/bin"), { recursive: true });
  fs.writeFileSync(path.join(root, "scripts/bin/vitro"), "x");
  fs.writeFileSync(path.join(root, "AGENTS.md"), "x");
  fs.writeFileSync(path.join(root, "AGENTS.md.bak"), "x");
  fs.writeFileSync(path.join(root, ".agents/skills/demo/SKILL.md"), opts.md);
  fs.writeFileSync(
    path.join(root, "scripts/skill_path_check/rules.json"),
    JSON.stringify({ whitelist_prefixes: [], dead_paths: [], skip_files: [], min_hits: 1, ...opts.rules }),
  );
  return root;
}

test("端到端：围栏/行内两种命中面；不存在的路径判红（exit 1）", () => {
  const root = tmpRepo({
    md: [
      "# demo",
      "行内引用 `scripts/bin/vitro` 与 `scripts/ghost/zzz`。",
      "```bash",
      "node scripts/ghost2/a.mts",
      "```",
      "删除线 ~~scripts/ghost3/x~~ 不计。",
      "",
    ].join("\n"),
  });
  // run 走 fail() → process.exit；用子进程形态断言
  const r = spawnSync(process.execPath, [MAIN, "-root", root], { cwd: root, encoding: "utf8" });
  assert.equal(r.status, 1, r.stdout + r.stderr);
  const out = (r.stdout ?? "") + (r.stderr ?? "");
  assert.match(out, /MISSING .*SKILL\.md:2 {2}scripts\/ghost\/zzz/);
  assert.match(out, /MISSING .*SKILL\.md:4 {2}scripts\/ghost2\/a\.mts/);
  assert.ok(!out.includes("ghost3"), "删除线内容必须整体剥除");
});

test("端到端：全绿树 → exit 0，min_hits 塌缩 → 红", () => {
  const green = tmpRepo({ md: "`scripts/bin/vitro`\n`AGENTS.md`\n", rules: { min_hits: 2 } });
  const ok = spawnSync(process.execPath, [MAIN, "-root", green], { cwd: green, encoding: "utf8" });
  assert.equal(ok.status, 0, ok.stdout + ok.stderr);
  assert.match(ok.stdout, /files=1 repo_path_refs=2 \(min_hits=2\) missing=0/);
  assert.match(ok.stdout, /ok all referenced repo paths exist/);

  const collapsed = tmpRepo({ md: "`scripts/bin/vitro`\n", rules: { min_hits: 5 } });
  const red = spawnSync(process.execPath, [MAIN, "-root", collapsed], { cwd: collapsed, encoding: "utf8" });
  assert.equal(red.status, 1);
  assert.match(red.stderr, /低于下限 5——抽取面塌缩/);
});

test("端到端：skills 目录缺失 / 0 个 md → fail loud", () => {
  const noSkills = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-spc-empty-"));
  fs.mkdirSync(path.join(noSkills, "scripts/skill_path_check"), { recursive: true });
  fs.writeFileSync(
    path.join(noSkills, "scripts/skill_path_check/rules.json"),
    JSON.stringify({ whitelist_prefixes: [], dead_paths: [], skip_files: [], min_hits: 1 }),
  );
  const a = spawnSync(process.execPath, [MAIN, "-root", noSkills], { cwd: noSkills, encoding: "utf8" });
  assert.equal(a.status, 1);
  assert.match(a.stderr, /skills 目录不存在/);

  fs.mkdirSync(path.join(noSkills, ".agents/skills"), { recursive: true });
  const b = spawnSync(process.execPath, [MAIN, "-root", noSkills], { cwd: noSkills, encoding: "utf8" });
  assert.equal(b.status, 1);
  assert.match(b.stderr, /0 个 md 文件——扫描面塌缩/);
});

test("真实仓库：19 文件 / 151 引用 / 0 缺失（与 Go 版同计数）", () => {
  const r = run(projectRoot());
  assert.equal(r, 0);
});

test("真实仓库端到端：默认 exit 0 + selftest 9 路 + 未知参数 exit 2", () => {
  const root = projectRoot();
  const def = spawnSync(process.execPath, [MAIN], { cwd: root, encoding: "utf8" });
  assert.equal(def.status, 0, def.stderr);
  assert.match(def.stdout, /skill_path_check: files=\d+ repo_path_refs=\d+ \(min_hits=\d+\) missing=0/);
  assert.match(def.stdout, /ok all referenced repo paths exist/);

  const self = spawnSync(process.execPath, [MAIN, "-selftest"], { cwd: root, encoding: "utf8" });
  assert.equal(self.status, 0, self.stderr);
  assert.match(self.stdout, /selftest ok: 9 路判定 \+ min_hits 守卫在案/);

  const bad = spawnSync(process.execPath, [MAIN, "--nope"], { cwd: root, encoding: "utf8" });
  assert.equal(bad.status, 2);
});
