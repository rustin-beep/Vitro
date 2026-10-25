// install_skills.test.mts —— 安装器自测件（#273 迁移批）：frontmatter 校验
// fail loud 三形态 + discover 排序 + diffOne 三态。Go 版无测试件，本件为
// .mts 四件套门（node:test）补口。
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { diffOne, discover, parseFrontmatterText } from "./install_skills.mts";

test("frontmatter：正常解析 name/description（CRLF 归一）", () => {
  const meta = parseFrontmatterText("---\r\nname: demo-skill\r\ndescription: 演示用\r\n---\n\n正文", "demo/SKILL.md");
  assert.equal(meta.get("name"), "demo-skill");
  assert.equal(meta.get("description"), "演示用");
});

test("frontmatter：缺包头 fail loud", () => {
  assert.throws(() => parseFrontmatterText("name: x\n", "x"), /缺少 YAML frontmatter/);
});

test("frontmatter：未闭合 fail loud", () => {
  assert.throws(() => parseFrontmatterText("---\nname: x\n", "x"), /未闭合/);
});

function mkSkill(root: string, name: string, desc: string, extraFile?: string): void {
  const dir = path.join(root, name);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "SKILL.md"), `---\nname: ${name}\ndescription: ${desc}\n---\n\n正文\n`);
  if (extraFile !== undefined) fs.writeFileSync(path.join(dir, extraFile), "x");
}

test("discover：按名排序 + 校验三形态 fail loud", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "iskills-"));
  mkSkill(root, "bbb", "B");
  mkSkill(root, "aaa", "A");
  const skills = discover(root);
  assert.deepEqual(skills.map((s) => s.name), ["aaa", "bbb"]);

  // name 与目录名不一致
  const bad = fs.mkdtempSync(path.join(os.tmpdir(), "iskills-bad-"));
  mkSkill(bad, "dir-name", "d");
  const md = path.join(bad, "dir-name", "SKILL.md");
  fs.writeFileSync(md, "---\nname: other\ndescription: d\n---\n");
  assert.throws(() => discover(bad), /与目录名不一致/);

  // 缺 description
  const bad2 = fs.mkdtempSync(path.join(os.tmpdir(), "iskills-bad2-"));
  fs.mkdirSync(path.join(bad2, "s1"), { recursive: true });
  fs.writeFileSync(path.join(bad2, "s1", "SKILL.md"), "---\nname: s1\n---\n");
  assert.throws(() => discover(bad2), /缺 name 或 description/);
});

test("diffOne：未安装/一致/源新增/仅副本所有 四态", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "iskills-diff-"));
  mkSkill(root, "s1", "S", "ref.md");
  const s = { name: "s1", dir: path.join(root, "s1"), desc: "S" };

  // 未安装
  const notInstalled = path.join(root, "dest-empty", "s1");
  assert.equal(diffOne(s, notInstalled), true);

  // 一致
  const same = path.join(root, "dest-same", "s1");
  fs.mkdirSync(same, { recursive: true });
  fs.writeFileSync(path.join(same, "SKILL.md"), fs.readFileSync(path.join(s.dir, "SKILL.md")));
  fs.writeFileSync(path.join(same, "ref.md"), "x");
  assert.equal(diffOne(s, same), false);

  // 源新增 + 仅副本所有
  const diverged = path.join(root, "dest-div", "s1");
  fs.mkdirSync(diverged, { recursive: true });
  fs.writeFileSync(path.join(diverged, "SKILL.md"), fs.readFileSync(path.join(s.dir, "SKILL.md")));
  fs.writeFileSync(path.join(diverged, "local.md"), "local");
  assert.equal(diffOne(s, diverged), true);
});
