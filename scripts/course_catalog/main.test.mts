// course_catalog.test.mts —— 对账判据 / 帧字节还原 / 真实仓库端到端。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { collectFrames, collectNotes, latin1ToBytes, normLF, readKeys, reconcile } from "./main.mts";
import type { SrcNote } from "./main.mts";
import { projectRoot } from "../internal/capi.mts";

const MAIN = path.join(import.meta.dirname, "main.mts");

/**
 * demo/algorithms.js 是发射产物（gitignored，CI 由 demo job 现场发射）。
 * scripts-ts job 不做发射——测试自己补，否则读真源即 ENOENT（假红）。
 * #36 收编批（2026-10-31）起生成器数据源 = 引擎 algorithms.catalog 出口
 * （需 vitro_js 产物）——产物缺失的环境发射必失败，改走 prereq 形态：
 * 调用方据 {ok,why} 显式 skip（lessonPrereq 同款先例），不再硬 assert。
 */
function algoEmitPrereq(root: string): { ok: boolean; why: string } {
  const p = path.join(root, "demo/algorithms.js");
  if (fs.existsSync(p)) return { ok: true, why: "" };
  const jsArm = path.join(root, "moonbit/_build/js/release/build/cmd/vitro_js/vitro_js.js");
  if (!fs.existsSync(jsArm)) {
    return {
      ok: false,
      why: "vitro js 臂产物缺（cd moonbit && moon build --release --target js cmd/vitro_js）——gen_demo_algorithms 引擎出口拉取前置",
    };
  }
  const r = spawnSync(process.execPath, [path.join(root, "scripts/gen_demo_algorithms/main.mts")], {
    cwd: root,
    encoding: "utf8",
  });
  if (r.status !== 0) {
    return { ok: false, why: "发射失败：" + (r.stdout ?? "") + (r.stderr ?? "") };
  }
  return { ok: true, why: "" };
}

/** lesson.c 双臂对拍的前置：vitro js 臂产物 + clang。 */
function lessonPrereq(root: string): { ok: boolean; why: string } {
  const jsArm = path.join(root, "moonbit/_build/js/release/build/cmd/vitro_js/vitro_js.js");
  const clang = spawnSync("clang", ["--version"], { encoding: "utf8" });
  const missing: string[] = [];
  if (!fs.existsSync(jsArm)) missing.push("vitro js 臂产物缺（cd moonbit && moon build --release --target js cmd/vitro_js）");
  if (clang.status !== 0) missing.push("clang 不在 PATH");
  return { ok: missing.length === 0, why: missing.join("；") };
}

test("latin1ToBytes：<=0xFF 折单字节；>0xFF 走 UTF-8", () => {
  assert.deepEqual([...latin1ToBytes("\u00e4\u00ff")], [0xe4, 0xff]);
  assert.deepEqual([...latin1ToBytes("中")], [...Buffer.from("中", "utf8")]);
});

test("normLF：只吃 CRLF，孤立 CR/LF 原样", () => {
  assert.deepEqual([...normLF(Buffer.from("a\r\nb\rc\nd"))], [...Buffer.from("a\nb\rc\nd")]);
});

test("collectFrames：按 type 分流，delta 逐帧拼接", () => {
  const lines = [
    JSON.stringify({ type: "stdout", frame: { result: { delta: "a\u00e4" } } }),
    JSON.stringify({ type: "stderr", frame: { result: { delta: "\u00ff" } } }),
    "noise",
    JSON.stringify({ type: "stdout", frame: { result: { delta: "b" } } }),
  ].join("\n");
  const { stdout, stderr } = collectFrames(lines);
  assert.deepEqual([...stdout], [0x61, 0xe4, 0x62]);
  assert.deepEqual([...stderr], [0xff]);
});

test("readKeys：并集去重（多正则命中同一文件）", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-course-"));
  const p = path.join(dir, "x.js");
  fs.writeFileSync(p, ['  id: "bubble"', '{ id: "kruskal", name: "K"', 'tpl: "kruskal"'].join("\n"));
  const keys = readKeys(p, [/^\s*id: "([a-z_0-9]+)"/gm, /\{\s*id: "([A-Za-z_0-9]+)", name:/g, /tpl: "([A-Za-z_0-9]+)"/g]);
  assert.deepEqual([...keys].sort(), ["bubble", "kruskal"]);
});

test("真实仓库：collectNotes 解析 8 课 frontmatter（id/kind 齐、目录升序）", () => {
  const notes = collectNotes();
  assert.equal(notes.length, 8);
  const dirs = notes.map((n) => n.dir);
  assert.deepEqual(dirs, [...dirs].sort((a, b) => Buffer.compare(Buffer.from(a), Buffer.from(b))));
  for (const n of notes) {
    assert.match(n.id, /^[A-Za-z_0-9-]+$/, n.dir);
    assert.match(n.kind, /^[a-z]+$/, n.dir);
  }
});

test("真实仓库：对账全绿（叙述 → cases.js/algorithms.js）", (t) => {
  const pre = algoEmitPrereq(projectRoot());
  if (!pre.ok) {
    t.skip(`前置缺失：${pre.why}（发射面常规覆盖归 demo job 的发射步 + demo_smoke）`);
    return;
  }
  assert.deepEqual(reconcile(collectNotes(), false), []);
});

/**
 * lesson.c 双臂对拍（vitro ≡ clang）——这条路径在仓库里**长期零实例**
 * （现无 lesson.c），此前只有手验。本用例自造临时课目录补覆盖：
 *   ① 正常 lesson.c → 闸绿且计数 +1；
 *   ② 坏 lesson.c（vitro 编译失败）→ 闸红（证明不是空转）。
 * 前置缺（无 vitro js 臂 / 无 clang）时**显式 skip 并打印原因**——不静默绿。
 */
test("lesson.c 双臂对拍：临时课绿 + 坏 lesson.c 红", (t) => {
  const root = projectRoot();
  const pre = lessonPrereq(root);
  if (!pre.ok) {
    t.skip(`前置缺失：${pre.why}（该路径的常规覆盖归 static-gates/demo job）`);
    return;
  }
  const emit = algoEmitPrereq(root);
  if (!emit.ok) {
    t.skip(`前置缺失：${emit.why}（发射面常规覆盖归 demo job 的发射步 + demo_smoke）`);
    return;
  }
  const dir = path.join(root, "course", "__j9_lesson__", "extra");
  const run = (): { status: number | null; out: string } => {
    const r = spawnSync(process.execPath, [MAIN], { cwd: root, encoding: "utf8" });
    return { status: r.status, out: (r.stdout ?? "") + (r.stderr ?? "") };
  };
  try {
    fs.mkdirSync(dir, { recursive: true });
    // kind=case + id=bubble（复用真实课目键，避免撞上对账判据）
    fs.writeFileSync(path.join(dir, "lesson.md"), "---\nid: bubble\nkind: case\n---\n\n# j9 lesson\n");
    fs.writeFileSync(path.join(dir, "lesson.c"), '#include <stdio.h>\nint main(void) { printf("j9 lesson\\n"); return 0; }\n');

    const green = run();
    assert.equal(green.status, 0, green.out);
    assert.match(green.out, /全部通过：9 课叙述对账 \+ 1 个 lesson\.c 对拍/);

    // 坏 lesson.c：vitro 臂编译失败 → 判红（闸有牙，非空转）
    fs.writeFileSync(path.join(dir, "lesson.c"), "int main(void) { return this_is_not_c; }\n");
    const red = run();
    assert.equal(red.status, 1, red.out);
    assert.match(red.out, /\[对拍\].*vitro 臂失败/);
  } finally {
    fs.rmSync(path.join(root, "course", "__j9_lesson__"), { recursive: true, force: true });
  }
  // 清理可验证：课目数回到 8
  assert.equal(collectNotes().length, 8);
});

test("J9 红：未知 id / 未知 kind 各自成条，且文案带定位", () => {
  const bad: SrcNote[] = [
    { id: "strng-typo", kind: "algo", dir: "course/x/y", stdin: "", hasC: false },
    { id: "bubble", kind: "weird", dir: "course/x/z", stdin: "", hasC: false },
  ];
  // 键集注入（纯函数化）：J9 锚不依赖发射产物在场——CI scripts-ts job
  // 干净检出也咬（strng-typo 不在注入集 = 「不命中」形态可判）
  const fails = reconcile(bad, false, {
    cases: new Set(["demo_case"]),
    algo: new Set(["bubble_sort"]),
  });
  assert.equal(fails.length, 2);
  assert.equal(fails[0]?.judge, "对账");
  assert.match(fails[0]?.msg ?? "", /course\/x\/y: 叙述 \(kind=algo, id=strng-typo\) 不命中任何课目/);
  assert.match(fails[1]?.msg ?? "", /course\/x\/z: 未知 kind "weird"/);
});

test("真实仓库端到端：默认绿 / selftest 绿 / 未知参数 exit 2", (t) => {
  const root = projectRoot();
  const emit = algoEmitPrereq(root);
  if (!emit.ok) {
    t.skip(`前置缺失：${emit.why}（CLI 全链需发射产物——常规覆盖归 demo job 发射步 + demo_smoke）`);
    return;
  }
  const run = (args: string[]): { status: number | null; out: string } => {
    const r = spawnSync(process.execPath, [MAIN, ...args], { cwd: root, encoding: "utf8" });
    return { status: r.status, out: (r.stdout ?? "") + (r.stderr ?? "") };
  };
  const green = run([]);
  assert.equal(green.status, 0, green.out);
  assert.match(green.out, /全部通过：8 课叙述对账 \+ 0 个 lesson\.c 对拍/);

  const self = run(["-selftest"]);
  assert.equal(self.status, 0, self.out);
  assert.match(self.out, /J9 自检 OK：假课注入被对账判据捕获/);

  const bad = run(["--nope"]);
  assert.equal(bad.status, 2);
});
