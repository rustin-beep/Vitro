// freshness.test.mts —— 陈旧源判定（测试端口注入 moonbitRoot，hermetic）。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { findStaleSource } from "./freshness.mts";

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
