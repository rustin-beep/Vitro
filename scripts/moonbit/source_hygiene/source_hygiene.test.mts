// source_hygiene.test.mts —— NUL 判定 + 真实/临时 git 仓库两端。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { findNul, scanRepo } from "./main.mts";
import { projectRoot } from "../../internal/capi.mts";

test("findNul：无 NUL / 单 NUL / 多 NUL 偏移与计数", () => {
  assert.equal(findNul(Buffer.from("abc")), null);
  assert.deepEqual(findNul(Buffer.from([0x61, 0x00, 0x62])), { offset: 1, count: 1 });
  assert.deepEqual(findNul(Buffer.from([0x00, 0x61, 0x00])), { offset: 0, count: 2 });
});

test("真实仓库扫描：零真 NUL（与 CI 同门径）", () => {
  const r = spawnSync(process.execPath, [path.join(import.meta.dirname, "main.mts")], {
    cwd: projectRoot(),
    encoding: "utf8",
  });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /source_hygiene: OK（\d+ 个被跟踪文件零真 NUL）/);
});

test("J9：临时 git 仓库含 NUL 必红；allowlist 可豁免", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-hygiene-"));
  const git = (args: string[]): void => {
    const r = spawnSync("git", args, { cwd: dir, encoding: "utf8" });
    assert.equal(r.status, 0, r.stderr);
  };
  git(["init", "-q"]);
  fs.writeFileSync(path.join(dir, "ok.mbt"), "ok\n");
  fs.writeFileSync(path.join(dir, "bad.bin"), Buffer.from([0x61, 0x00, 0x62]));
  git(["add", "-A"]);
  const sc = scanRepo(dir);
  assert.equal(sc.hits.length, 1);
  assert.equal(sc.hits[0]?.p, "bad.bin");

  fs.mkdirSync(path.join(dir, "scripts/moonbit"), { recursive: true });
  fs.writeFileSync(path.join(dir, "scripts/moonbit/source_hygiene_allowlist.txt"), "bad.bin\n");
  git(["add", "-A"]);
  assert.equal(scanRepo(dir).hits.length, 0);
});
