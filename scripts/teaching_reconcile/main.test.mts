// teaching_reconcile.test.mts —— 三向对账判定面（真实仓库 + 合成 fixture 红路径）。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { byteSort } from "./main.mts";
import { projectRoot } from "../internal/capi.mts";

const MAIN = path.join(import.meta.dirname, "main.mts");

function write(p: string, s: string): void {
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, s);
}

interface Fixture {
  root: string;
  /** 改 fixture 内容（红路径注入用） */
  edit(rel: string, fn: (s: string) => string): void;
}

/**
 * 合成仓库根：pairs() 的 base 是硬编码（45/43/12），故 fixture 按同规模造。
 * 绿路径 = 三表键集 ≡ 装配点字面量 ≡ 消费域字面量。
 */
function makeFixture(): Fixture {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-reconcile-"));
  // projectRoot 的识别标记
  fs.mkdirSync(path.join(root, "corpus"), { recursive: true });
  fs.mkdirSync(path.join(root, "scripts"), { recursive: true });

  const trap = Array.from({ length: 45 }, (_, i) => `t${String(i).padStart(2, "0")}`);
  const sugg = Array.from({ length: 43 }, (_, i) => `s${String(i).padStart(2, "0")}`);
  const builtin = Array.from({ length: 12 }, (_, i) => `b${String(i).padStart(2, "0")}`);

  write(path.join(root, "moonbit/teaching/content/trap_messages.md"), trap.map((k) => `## ${k}\n`).join("\n"));
  write(path.join(root, "moonbit/teaching/content/suggestions.md"), sugg.map((k) => `## ${k}\n`).join("\n"));
  write(path.join(root, "moonbit/teaching/content/builtin_notes.md"), builtin.map((k) => `## ${k}\n`).join("\n"));

  write(
    path.join(root, "moonbit/host/host_memory.mbt"),
    trap.map((k) => `  trap_messages.get("${k}")\n`).join(""),
  );
  // consumerDirs 需存在（stat 不得失败）
  fs.mkdirSync(path.join(root, "moonbit/vm"), { recursive: true });
  fs.mkdirSync(path.join(root, "moonbit/time_travel"), { recursive: true });
  write(
    path.join(root, "moonbit/teaching/content_data/map_install.mbt"),
    sugg.map((k) => `  m.set("${k}",\n`).join(""),
  );
  write(
    path.join(root, "moonbit/typeck/notes.mbt"),
    builtin.map((k) => `  note_count("${k}"\n`).join(""),
  );

  return {
    root,
    edit(rel, fn) {
      const p = path.join(root, rel);
      fs.writeFileSync(p, fn(fs.readFileSync(p, "utf8")));
    },
  };
}

function runIn(root: string, args: string[] = []): { status: number | null; out: string } {
  const r = spawnSync(process.execPath, [MAIN, ...args], { cwd: root, encoding: "utf8" });
  return { status: r.status, out: (r.stdout ?? "") + (r.stderr ?? "") };
}

test("byteSort：ASCII 字节序（Go sort.Strings 口径）", () => {
  assert.deepEqual(byteSort(["b", "A", "a_", "a"]), ["A", "a", "a_", "b"]);
});

test("fixture 绿：三表键集 ≡ 装配点 ≡ 消费域，exit 0", () => {
  const f = makeFixture();
  const r = runIn(f.root);
  assert.equal(r.status, 0, r.out);
  assert.match(r.out, /全部通过：trap\/suggestions\/builtin_notes 内容键 ≡ 装配点字面量/);
});

test("J9 红①装配缺键：装配点有、真源无", () => {
  const f = makeFixture();
  f.edit("moonbit/host/host_memory.mbt", (s) => s + '  trap_messages.get("typo_key")\n');
  const r = runIn(f.root);
  assert.equal(r.status, 1);
  assert.match(r.out, /装配缺键 "typo_key"/);
});

test("J9 红②孤儿内容键：真源有、消费域无字面量", () => {
  const f = makeFixture();
  // 从消费域删掉一条键的字面量（md 与装配点仍保留）
  f.edit("moonbit/host/host_memory.mbt", (s) => s.replace('trap_messages.get("t00")', "trap_messages.get(k)"));
  const r = runIn(f.root);
  assert.equal(r.status, 1);
  assert.match(r.out, /孤儿内容键 "t00"/);
});

test("J9 红③内容条数漂移（整表基线）", () => {
  const f = makeFixture();
  f.edit("moonbit/teaching/content/builtin_notes.md", (s) => s + "\n## b99\n");
  const r = runIn(f.root);
  assert.equal(r.status, 1);
  assert.match(r.out, /builtin_notes: 内容条数 13 ≠ 基线 12/);
});

test("J9 红④节键重复 / 空集不得绿", () => {
  const f = makeFixture();
  f.edit("moonbit/teaching/content/builtin_notes.md", (s) => s + "\n## b00\n");
  const dup = runIn(f.root);
  assert.equal(dup.status, 1);
  assert.match(dup.out, /节键 "b00" 重复/);

  const g = makeFixture();
  fs.writeFileSync(path.join(g.root, "moonbit/teaching/content/suggestions.md"), "# 无节标题\n");
  const empty = runIn(g.root);
  assert.equal(empty.status, 1);
  assert.match(empty.out, /未解析到任何节键（空集不得绿）/);
});

test("真实仓库：绿 + -v 逐键 100 条 + selftest exit 0", () => {
  const root = projectRoot();
  const green = runIn(root);
  assert.equal(green.status, 0, green.out);

  const verbose = runIn(root, ["-v"]);
  assert.equal(verbose.status, 0, verbose.out);
  const keys = verbose.out.split("\n").filter((l) => l.includes("✓"));
  assert.equal(keys.length, 45 + 43 + 12);

  const self = runIn(root, ["-selftest"]);
  assert.equal(self.status, 0, self.out);
  assert.match(self.out, /J9 自检 OK：假装配键注入被捕获/);
});

test("未知参数 exit 2（与判定红的 1 分流）", () => {
  const r = runIn(projectRoot(), ["--nope"]);
  assert.equal(r.status, 2);
  assert.match(r.out, /未知参数/);
});
