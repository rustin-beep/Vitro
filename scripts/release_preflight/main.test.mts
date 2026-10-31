// release_preflight 单测（#273 .mts 四件套义务：node:test）——纯函数面：
// parseDryRun / moonModVersion / parseZipListing / verdictFromListing。
// 样本输出取自 2026-10-31 master 实测（Check passed + 409 双形态）。
import assert from "node:assert/strict";
import { test } from "node:test";
import {
  ZIP_MIN_BYTES,
  ZIP_MIN_FILES,
  moonModVersion,
  parseDryRun,
  parseZipListing,
  verdictFromListing,
} from "./main.mts";

test("parseDryRun：健康 + 版本重复 409（master 0.9.0 实测样本）", () => {
  const out = [
    "Finished. moon: ran 83 tasks, now up to date (39 warnings, 0 errors)",
    "Check passed",
    "Server status: 409 Conflict, detail: Version Error: The version you are attempting to upload (0.9.0) is duplicated with an existing version (0.9.0). Please select a different version to publish.",
    "Error: `moon publish` failed",
  ].join("\n");
  const v = parseDryRun(out);
  assert.equal(v.checkPassed, true);
  assert.equal(v.versionConflict, "0.9.0");
  assert.equal(v.version, "0.9.0");
});

test("parseDryRun：健康 + 已 bump（无 409）", () => {
  const out = "Finished. moon: ran 83 tasks, now up to date\nCheck passed\n";
  const v = parseDryRun(out);
  assert.equal(v.checkPassed, true);
  assert.equal(v.versionConflict, null);
  assert.equal(v.version, null);
});

test("parseDryRun：断供形态（无 Check passed——0.9.0 型 core/abort）日常档将红", () => {
  const out = [
    "Error: failed to run build for target Native",
    "Caused by:",
    "    1: Cannot find import 'moonbitlang/core/abort' in vitro/engine/time_travel@0.9.0",
  ].join("\n");
  const v = parseDryRun(out);
  assert.equal(v.checkPassed, false);
  assert.equal(v.versionConflict, null);
});

test("moonModVersion：TOML 裸键提取（容忍注释与字段序）", () => {
  const mod = [
    'module = "vitro/engine"',
    'author = "vitro"',
    '# version = "0.0.0-comment"',
    'version = "0.10.0"',
    'description = "..."',
  ].join("\n");
  assert.equal(moonModVersion(mod), "0.10.0");
  assert.equal(moonModVersion("module = \"x\"\n"), null);
});

test("parseZipListing：CRLF 归一 + 空行剔除", () => {
  const text = "LICENSE\r\nmoon.mod\r\n\r\nvm/vm.mbt\n\ndiag/diag.mbt\r\n";
  assert.deepEqual(parseZipListing(text), ["LICENSE", "moon.mod", "vm/vm.mbt", "diag/diag.mbt"]);
});

test("verdictFromListing：根级四件缺位检出 + 非空阈值常量在场", () => {
  const entries = ["LICENSE", "moon.mod", "vm/vm.mbt", "diag/diag.mbt"];
  const zv = verdictFromListing(entries, 1_567_591);
  assert.deepEqual(zv.missingRoot, ["README.md", "README.mbt.md"]);
  assert.equal(zv.fileCount, 4);
  // 阈值形态锚（阈值调整须连坐本断言）：git 管理面实测 520 条/~1.5MB
  assert.ok(ZIP_MIN_FILES >= 400 && ZIP_MIN_FILES < 520);
  assert.ok(ZIP_MIN_BYTES >= 100 * 1024 && ZIP_MIN_BYTES < 1_500_000);
});

test("verdictFromListing：四件齐备零缺位", () => {
  const entries = ["LICENSE", "README.md", "README.mbt.md", "moon.mod", "vm/vm.mbt"];
  const zv = verdictFromListing(entries, 1_567_591);
  assert.deepEqual(zv.missingRoot, []);
});
