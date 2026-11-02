// source_hygiene.test.mts —— NUL 判定 + 真实/临时 git 仓库两端。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { findNul, findOrphanMbt, scanRepo } from "./main.mts";
import { projectRoot } from "../../internal/capi.mts";

test("findNul：无 NUL / 单 NUL / 多 NUL 偏移与计数", () => {
  assert.equal(findNul(Buffer.from("abc")), null);
  assert.deepEqual(findNul(Buffer.from([0x61, 0x00, 0x62])), { offset: 1, count: 1 });
  assert.deepEqual(findNul(Buffer.from([0x00, 0x61, 0x00])), { offset: 0, count: 2 });
});

test("真实仓库扫描：零真 NUL + 零包外散 .mbt（与 CI 同门径）", () => {
  const r = spawnSync(process.execPath, [path.join(import.meta.dirname, "main.mts")], {
    cwd: projectRoot(),
    encoding: "utf8",
  });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /source_hygiene: OK（\d+ 个被跟踪文件零真 NUL；moonbit\/ 下 \.mbt 零包外散件）/);
});

test("J9 ②包外散 .mbt（S13b-P10 2026-11-01）：无 moon.pkg 祖先的 .mbt 必红；包内/嵌套包内/非 moonbit 下不红", () => {
  // 探针 E 实锤形态：moonbit/zz_probe_pkgless/loose.mbt（无 moon.pkg、烂格式）staged
  // 后 pre-commit 的 moon fmt 与 CI hygiene fmt 闸同盲零检出——纪律在人不在闸。
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-orphan-"));
  const w = (rel: string, s: string): void => {
    fs.mkdirSync(path.dirname(path.join(dir, rel)), { recursive: true });
    fs.writeFileSync(path.join(dir, rel), s);
  };
  w("moonbit/moon.mod", "{}\n");
  w("moonbit/pkg_ok/moon.pkg", "{}\n");
  w("moonbit/pkg_ok/a.mbt", "fn a() -> Int { 1 }\n");
  w("moonbit/pkg_ok/sub/deep.mbt", "fn d() -> Int { 1 }\n"); // 嵌套目录：向上命中父包的 moon.pkg
  w("moonbit/zz_loose/loose.mbt", "fn  loose( )->Int{1}\n"); // 包外：红
  w("scripts/x/y.mbt", "not moonbit tree\n"); // 非 moonbit/ 下：不在检查面
  const tracked = ["moonbit/moon.mod", "moonbit/pkg_ok/moon.pkg", "moonbit/pkg_ok/a.mbt", "moonbit/pkg_ok/sub/deep.mbt", "moonbit/zz_loose/loose.mbt", "scripts/x/y.mbt"];
  assert.deepEqual(findOrphanMbt(dir, tracked), ["moonbit/zz_loose/loose.mbt"]);
  // 补上 moon.pkg 即绿（修复路径 = 落进包）
  w("moonbit/zz_loose/moon.pkg", "{}\n");
  assert.deepEqual(findOrphanMbt(dir, tracked), []);
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
