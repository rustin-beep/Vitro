// broken_refs.test.mts —— 坏引用扫描扩面形态的证红锚（J9：#307 审阅 P1-1
// 抓出抽取面塌缩——.mts/.mjs/node 形态全在闸外。本锚锁扩面后的抽取/豁免/
// 包路径判定，腐坏即红）。
//
// 红证据（2026-10-25 亲跑）：扩面前注入 `node scripts/pr307_probe_missing.mts`
// → 坏引用 0 / RC=0（漏）；扩面后同注入 → 坏引用 +1。曾用 .json 误报形态
// （`rules.json` 被贪婪匹配成 `rules.js`）——负向前视 (?![A-Za-z0-9]) 修。
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { _internal } from "./audit.mts";

const { scanBrokenRefs, scriptRefAlive } = _internal;

function mkTree(files: Record<string, string>): string {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "facts-brokenrefs-"));
  for (const [rel, body] of Object.entries(files)) {
    const p = path.join(root, ...rel.split("/"));
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(p, body);
  }
  return root;
}

test("扩面抽取：.mts 死路径在 node 命令语境被抓（迁移后主形态）", () => {
  const root = mkTree({
    "docs/current/a.md": "见 node scripts/pr307_probe_missing.mts --flag 命令\n",
  });
  const out = scanBrokenRefs(root, ["docs/current/a.md"]);
  assert.equal(out.length, 1, `应抓 1 处 .mts 死引用，实得 ${out.length}`);
  assert.equal(out[0]!.path, "scripts/pr307_probe_missing.mts");
  fs.rmSync(root, { recursive: true, force: true });
});

test("扩面抽取：非命令语境的反引号 .mts 死路径同样被抓（CURRENT 层）", () => {
  const root = mkTree({
    "docs/current/a.md": "详见 `scripts/ghost_probe.mts` 的用法。\n",
  });
  const out = scanBrokenRefs(root, ["docs/current/a.md"]);
  assert.equal(out.length, 1, "CURRENT 层非命令语境死路径应抓");
  fs.rmSync(root, { recursive: true, force: true });
});

test("豁免词：行内「已退役」放行历史叙述", () => {
  const root = mkTree({
    "docs/current/a.md": "旧命令 `node scripts/ghost_probe.mts`（脚本已退役删除）。\n",
  });
  const out = scanBrokenRefs(root, ["docs/current/a.md"]);
  assert.equal(out.length, 0, "豁免词行应放行");
  fs.rmSync(root, { recursive: true, force: true });
});

test(".json 不再被贪婪匹配成 .js（负向前视）", () => {
  const root = mkTree({
    "docs/current/a.md": "规则表 `scripts/skill_path_check/rules.json` 外置。\n",
  });
  const out = scanBrokenRefs(root, ["docs/current/a.md"]);
  assert.equal(out.length, 0, `.json 引用不得截断成 .js 误报（实得 ${JSON.stringify(out)}）`);
  fs.rmSync(root, { recursive: true, force: true });
});

test("包路径判定：xxx.mts 不存在但 xxx/ 含 .mts 视为活", () => {
  const root = mkTree({ "scripts/facts/main.mts": "// x\n" });
  assert.ok(scriptRefAlive(root, "scripts/facts.mts"), "目录含 .mts 应判活");
  assert.ok(!scriptRefAlive(root, "scripts/ghost_pkg.mts"), "不存在的包路径应判死");
  fs.rmSync(root, { recursive: true, force: true });
});

test("bare 形态：go run + 无扩展名包路径（命令语境）被抓", () => {
  const root = mkTree({
    "docs/current/a.md": "1. 运行 `go run ./scripts/shadow_verify` 取数。\n",
  });
  const out = scanBrokenRefs(root, ["docs/current/a.md"]);
  assert.equal(out.length, 1, "bare 死路径（命令语境）应抓");
  assert.equal(out[0]!.path, "scripts/shadow_verify");
  fs.rmSync(root, { recursive: true, force: true });
});

test("bare 活路径：node scripts/bin/vitro（存在文件）放行", () => {
  const root = mkTree({
    "scripts/bin/vitro": "#!/bin/sh\n",
    "docs/current/a.md": "入口：`node scripts/bin/vitro run f.c`。\n",
  });
  const out = scanBrokenRefs(root, ["docs/current/a.md"]);
  assert.equal(out.length, 0, "存在的 bare 路径应放行");
  fs.rmSync(root, { recursive: true, force: true });
});

test(".agents 域：install_skills.mts 引用参与判定", () => {
  const root = mkTree({
    ".agents/install_skills.mts": "// x\n",
    "docs/current/a.md": "安装器 `node .agents/install_skills_ghost.mts --all`。\n",
  });
  const out = scanBrokenRefs(root, ["docs/current/a.md"]);
  assert.equal(out.length, 1, ".agents 死路径应抓");
  fs.rmSync(root, { recursive: true, force: true });
});

// PR #339 审阅 P2（2026-10-27）：.md 相对链接存在性闸。J9 双锚：
// ①假链红（含中文文件名 decodeURI 面）；②外部 URL/锚点/绝对路径豁免不红。
const { scanMarkdownLinks } = _internal;

test("markdown 链接：坏链红 + 中文目标名 decodeURI", () => {
  const root = mkTree({
    "docs/current/05-x/nav.md": "见 [真文档](../07-y/已知限制.md) 与 [假链](../07-y/不存在.md)。\n",
    "docs/current/07-y/已知限制.md": "# t\n",
  });
  const out = scanMarkdownLinks(root, ["docs/current/05-x/nav.md", "docs/current/07-y/已知限制.md"]);
  assert.equal(out.length, 1, "只有假链红");
  assert.equal(out[0]!.path, "../07-y/不存在.md");
  fs.rmSync(root, { recursive: true, force: true });
});

test("markdown 链接：外部 URL / 锚点 / 绝对路径 / 归档豁免", () => {
  const root = mkTree({
    "docs/current/a.md": "[外](https://x/y.md) [锚](#sec) [绝对](/x/y.md) [盘符](C:/x.md) [邮](mailto:a@b)\n",
    "docs/archive/b.md": "[死链](../nope.md)\n",
  });
  const out = scanMarkdownLinks(root, ["docs/current/a.md", "docs/archive/b.md"]);
  assert.equal(out.length, 0, "豁免面全放行 + archive 跳过");
  fs.rmSync(root, { recursive: true, force: true });
});
