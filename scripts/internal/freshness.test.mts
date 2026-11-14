// freshness.test.mts —— 陈旧源判定（测试端口注入 moonbitRoot，hermetic）。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { ensureFresh, ENSURE_FRESH_FAIL_MARKS, findStaleSource } from "./freshness.mts";

function fixture(): { dir: string; mb: string; artifact: string } {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-fresh-"));
  const mb = path.join(dir, "moonbit");
  fs.mkdirSync(mb);
  const artifact = path.join(dir, "art.exe");
  fs.writeFileSync(artifact, "");
  const past = new Date(Date.now() - 60000);
  fs.utimesSync(artifact, past, past);
  return { dir, mb, artifact };
}

function touch(p: string, offsetMs: number): void {
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, "");
  const t = new Date(Date.now() + offsetMs);
  fs.utimesSync(p, t, t);
}

test("任一 moonbit 源新于产物即陈旧（字典序首个）", () => {
  const { mb, artifact } = fixture();
  touch(path.join(mb, "a.mbt"), -120000);
  touch(path.join(mb, "b.mbt"), 60000);
  touch(path.join(mb, "c.pkg"), 60000);
  assert.equal(findStaleSource(artifact, mb), path.join(mb, "b.mbt"));
});

test("测试文件与 _build/.mooncakes 不参与判定", () => {
  const { mb, artifact } = fixture();
  touch(path.join(mb, "x_test.mbt"), 60000);
  touch(path.join(mb, "y_wbtest.mbt"), 60000);
  touch(path.join(mb, "_build", "z.mbt"), 60000);
  touch(path.join(mb, ".mooncakes", "w.mbt"), 60000);
  assert.equal(findStaleSource(artifact, mb), "");
});

// PR #518 审阅 P2-2：*_gen.mbt 排除回搬——被删的 warnStaleExe 曾排除
// @generated 产物（「均实测误报过」），批 3/追加批双臂统一走 findStaleSource
// 时丢掉该语义——实测触发源正是 moonbit/vm/libc_data_gen.mbt（构建刷新
// mtime），每次构建后多一轮重建。J9：修复前本锚红（现状返回该路径非空）。
test("*_gen.mbt 不参与判定（@generated 产物——warnStaleExe 语义回搬，PR #518 审阅 P2-2）", () => {
  const { mb, artifact } = fixture();
  touch(path.join(mb, "libc_data_gen.mbt"), 60000);
  touch(path.join(mb, "diag", "error_code_gen.mbt"), 60000);
  assert.equal(findStaleSource(artifact, mb), "");
});

test(".mod/.pkg 参与判定；旧源不报", () => {
  const { mb, artifact } = fixture();
  // 明显早于产物（产物在 fixture() 里设为 -60000；同量级会因毫秒抖动假红）
  touch(path.join(mb, "moon.mod"), -120000);
  touch(path.join(mb, "moon.pkg"), -120000);
  assert.equal(findStaleSource(artifact, mb), "");
  touch(path.join(mb, "moon.pkg"), 60000);
  assert.equal(findStaleSource(artifact, mb), path.join(mb, "moon.pkg"));
});

test("产物缺失 → 返回产物路径（触发 fail loud 路径）", () => {
  const { dir, mb } = fixture();
  const missing = path.join(dir, "missing.exe");
  assert.equal(findStaleSource(missing, mb), missing);
});

// ── 构建后置钩子（PR #518 追加批：vm_diff wasm 臂硬门禁前置——产物链含
// wasmopt 后置覆盖，自动重建必须带上后置链，否则以裸产物覆盖优化产物。
// J9 义务：本节两锚在实现前必红——旧 ensureFresh 无 opts 端口，postBuild
// 永不被调（锚 1 断言失败）/不 die（锚 2 exit 0 无标记），实现后绿。──
test("后置钩子链：陈旧触发复核构建 → postBuild 被调且接收产物路径；新鲜不触发", () => {
  const { mb, artifact } = fixture();
  const calls: string[] = [];
  // 陈旧源：b.mbt 新于产物 → 触发复核
  touch(path.join(mb, "b.mbt"), 60000);
  ensureFresh("j9post", artifact, ["build", "--target", "native", "cmd/fake"], {
    moonbitRoot: mb,
    rebuildRunner: (args) => {
      calls.push("rebuild:" + args.join(","));
      return true;
    },
    postBuild: (art) => {
      calls.push("postBuild:" + art);
      return true;
    },
  });
  assert.deepEqual(calls, [
    "rebuild:build,--target,native,cmd/fake",
    "postBuild:" + artifact,
  ]);
  // 新鲜场景：无陈旧源 → 复核构建与 postBuild 均不触发（CI build-artifacts
  // 每轮重建后的常态路径——零行为变化）
  const fresh2 = fixture();
  const idle: string[] = [];
  ensureFresh("j9post", fresh2.artifact, ["build", "--target", "native", "cmd/fake"], {
    moonbitRoot: fresh2.mb,
    rebuildRunner: () => {
      idle.push("rebuild");
      return true;
    },
    postBuild: (art) => {
      idle.push("postBuild:" + art);
      return true;
    },
  });
  assert.deepEqual(idle, []);
});

// J9 锚 2（真源锚，prelude_fail.test.mts realDieLine 同款手法）：postBuild
// 失败 → die（构建链失败口径）。子进程形态——die 走 process.exit(1)，进程内
// 不可 catch；临时入口写盘（假 runner + postBuild 恒 false + fixture 根），
// spawn node 直跑，断言 exit 1 + stderr 含 ENSURE_FRESH_FAIL_MARKS[3]。
test("后置钩子失败 → die exit 1（构建链失败口径，标记单源锚）", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-fresh-post-"));
  const mb = path.join(dir, "moonbit");
  fs.mkdirSync(mb);
  const artifact = path.join(dir, "art.wasm");
  fs.writeFileSync(artifact, "");
  const past = new Date(Date.now() - 60000);
  fs.utimesSync(artifact, past, past);
  touch(path.join(mb, "src.mbt"), 60000);
  const entry = path.join(dir, "entry.mts");
  const freshnessURL = pathToFileURL(path.join(import.meta.dirname, "freshness.mts")).href;
  fs.writeFileSync(
    entry,
    `import { ensureFresh } from "${freshnessURL}";\n` +
      `ensureFresh("j9postfail", ${JSON.stringify(artifact)}, ["build", "--target", "native", "cmd/fake"], {\n` +
      `  moonbitRoot: ${JSON.stringify(mb)},\n` +
      `  rebuildRunner: () => true,\n` +
      `  postBuild: () => false,\n` +
      `});\n` +
      `process.stdout.write("NOT_REACHED\\n");\n`,
  );
  const r = spawnSync(process.execPath, [entry], { encoding: "utf8" });
  assert.equal(r.status, 1, "postBuild 失败须 exit 1（实得 stdout=" + r.stdout + "）");
  assert.ok(
    (r.stderr ?? "").includes(ENSURE_FRESH_FAIL_MARKS[3] ?? ""),
    "die 行须含标记单源 ENSURE_FRESH_FAIL_MARKS[3]（实得 stderr=" + r.stderr + "）",
  );
  assert.ok(!(r.stdout ?? "").includes("NOT_REACHED"), "die 后不得继续执行");
});
