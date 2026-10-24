// vendor_drift.test.mts —— 纯函数与基线校验面（不触网：网络面属 exit 2 分支，靠 CI 实跑）
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { TRACKED_MODULE, TRACKED_REF, loadBaseline, parseVersion, sha256Hex } from "./main.mts";
import { projectRoot } from "../../internal/capi.mts";

test("parseVersion：取 moon.mod 的 version 行（多行/缺行）", () => {
  assert.equal(parseVersion('name = "x"\nversion = "0.5.6"\n'), "0.5.6");
  assert.equal(parseVersion('name = "x"\n'), "");
});

test("sha256Hex：已知向量（NIST abc）", () => {
  assert.equal(sha256Hex(Buffer.from("abc")), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
});

test("loadBaseline：repo / ref / 空 files / 缺字段 四路 fail loud", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-vd-"));
  const ok = {
    _generated_by: "x",
    as_of: "2026-10-24",
    repo: TRACKED_MODULE,
    ref: TRACKED_REF,
    upstream_version: "0.5.5",
    version_note: "",
    files: [{ path: "a", sha256: "b", vendored: "c" }],
  };
  const p = path.join(dir, "b.json");
  fs.writeFileSync(p, JSON.stringify(ok));
  assert.equal(loadBaseline(p).files.length, 1);

  fs.writeFileSync(p, JSON.stringify({ ...ok, repo: "other/x" }));
  assert.throws(() => loadBaseline(p), /repo=.* 与探针跟踪对象/);
  fs.writeFileSync(p, JSON.stringify({ ...ok, ref: "v1" }));
  assert.throws(() => loadBaseline(p), /ref=.* 与探针跟踪引用/);
  fs.writeFileSync(p, JSON.stringify({ ...ok, files: [] }));
  assert.throws(() => loadBaseline(p), /基线 files 为空/);
  fs.writeFileSync(p, JSON.stringify({ ...ok, files: [{ path: "", sha256: "b" }] }));
  assert.throws(() => loadBaseline(p), /缺 path\/sha256/);
  fs.writeFileSync(p, "{bad json");
  assert.throws(() => loadBaseline(p), /基线 JSON 损坏/);
  // 缺文件
  assert.throws(() => loadBaseline(path.join(dir, "nope.json")), /基线缺失\/不可读/);
});

test("真实基线：repo/ref 口径一致且文件非空", () => {
  const bl = loadBaseline(path.join(projectRoot(), "scripts/moonbit/vendor_baseline.json"));
  assert.ok(bl.files.length >= 4);
  assert.equal(bl.repo, TRACKED_MODULE);
  assert.equal(bl.ref, TRACKED_REF);
  for (const f of bl.files) assert.match(f.sha256, /^[0-9a-f]{64}$/);
});
