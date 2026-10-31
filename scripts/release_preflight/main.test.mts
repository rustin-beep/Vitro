// release_preflight 单测（#273 .mts 四件套义务：node:test）——纯函数面：
// parseDryRun / moonModVersion / parseZipListing / verdictFromListing。
// 样本输出取自 2026-10-31 master 实测（Check passed + 409 双形态）。
import assert from "node:assert/strict";
import { test } from "node:test";
import {
  ZIP_MIN_BYTES,
  ZIP_MIN_FILES,
  latestPublishedVersion,
  moonModVersion,
  parseDryRun,
  verdictFromListing,
  zipEntries,
} from "./main.mts";

/** 拼最小合法 zip：local header 省略，central directory + EOCD（解析只读 CD）。 */
function mkZip(names: readonly string[]): Buffer {
  const cdParts: Buffer[] = [];
  for (const n of names) {
    const name = Buffer.from(n, "utf8");
    const e = Buffer.alloc(46);
    e.writeUInt32LE(0x02014b50, 0);
    e.writeUInt16LE(name.length, 28);
    cdParts.push(e, name);
  }
  const cd = Buffer.concat(cdParts);
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(names.length, 8); // 盘内条目数
  eocd.writeUInt16LE(names.length, 10); // 总条目数
  eocd.writeUInt32LE(cd.length, 12); // cd 尺寸
  eocd.writeUInt32LE(0, 16); // cd 偏移（CD 紧贴 EOCD 前 = 0 起）
  // 注：偏移语义 = CD 起点绝对偏移；此拼法 CD 在(假想的)文件头——用
  // Buffer.concat([cd, eocd]) 时 CD 偏移 0 正确
  return Buffer.concat([cd, eocd]);
}

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

test("zipEntries：central directory 逐条读名（含目录条目/中文/空清单）", () => {
  assert.deepEqual(zipEntries(mkZip(["LICENSE", "moon.mod", "vm/vm.mbt"])), [
    "LICENSE",
    "moon.mod",
    "vm/vm.mbt",
  ]);
  // 目录条目（尾 /）与非 ASCII 名照常读出（UTF-8 名段）
  assert.deepEqual(zipEntries(mkZip(["dir/", "说明.md"])), ["dir/", "说明.md"]);
  assert.deepEqual(zipEntries(mkZip([])), []);
  // 非 zip 字节 → throw（EOCD 未找到）
  assert.throws(() => zipEntries(Buffer.from("not a zip at all........")));
});

test("zipEntries：EOCD 前有数据体（模拟真实布局：files…+CD+EOCD）", () => {
  const fakeBody = Buffer.alloc(300, 0x41); // 假 local 段
  const cd = (() => {
    const name = Buffer.from("moon.mod", "utf8");
    const e = Buffer.alloc(46);
    e.writeUInt32LE(0x02014b50, 0);
    e.writeUInt16LE(name.length, 28);
    return Buffer.concat([e, name]);
  })();
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(1, 10);
  eocd.writeUInt32LE(cd.length, 12);
  eocd.writeUInt32LE(fakeBody.length, 16);
  assert.deepEqual(zipEntries(Buffer.concat([fakeBody, cd, eocd])), ["moon.mod"]);
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

test("latestPublishedVersion：JSONL 尾行版本（CRLF/空行容忍·坏行 null）", () => {
  const good = '{"version":"0.8.0","deps":[]}\r\n{"version":"0.9.0","deps":[]}\r\n';
  assert.equal(latestPublishedVersion(good), "0.9.0");
  assert.equal(latestPublishedVersion('{"version":"0.8.0"}\n{"version":"0.9.0"}\n'), "0.9.0");
  assert.equal(latestPublishedVersion(""), null);
  assert.equal(latestPublishedVersion("\r\n\n"), null);
  assert.equal(latestPublishedVersion("not-json"), null);
  // 尾行 version 非字符串（形态异常）→ null
  assert.equal(latestPublishedVersion('{"version":123}'), null);
});
