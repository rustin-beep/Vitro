// release_preflight 单测（#273 .mts 四件套义务：node:test）——纯函数面：
// parseDryRun / moonModVersion / parseZipListing / verdictFromListing；
// A8 批（refs #438）追加：zipRecords/unzipTo 解压器往返与 zip slip 红、tagNameOf/judgeTag 三路。
// 样本输出取自 2026-10-31 master 实测（Check passed + 409 双形态）。
import assert from "node:assert/strict";
import { test } from "node:test";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import zlib from "node:zlib";
import {
  TAG_PREFIX,
  ZIP_MIN_BYTES,
  ZIP_MIN_FILES,
  judgePackage,
  judgeTag,
  latestPublishedVersion,
  moonModVersion,
  parseDryRun,
  tagNameOf,
  unsafeEntryName,
  unzipTo,
  verdictFromListing,
  zipEntries,
  zipRecords,
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

// ── judgePackage 三档（审阅批 2026-10-31 P2-3：主流程判红分支曾零自动锚
//    ——M2 突变〔缺件判红 if(false)〕时 9 测全绿的盲区；本三档把
//    「zv → 判红/放行」的出口判定钉进纯函数层）──
test("judgePackage：绿（量过阈值 + 四件齐）放行", () => {
  const entries = ["LICENSE", "README.md", "README.mbt.md", "moon.mod"];
  for (let i = 0; i < 600; i++) entries.push(`pkg${i}/f${i}.mbt`);
  const zv = verdictFromListing(entries, 1_567_591);
  assert.equal(judgePackage(zv), null);
});

test("judgePackage：退化（量不过阈值）判红且附缺件定位（P3-4）", () => {
  // 审阅实测形态：3 条 / 374B 缺 LICENSE 小包——须报「退化」为根因，
  // 附缺根级件清单辅助定位（而非单报缺件误导治向）
  const zv = verdictFromListing(["a.mbt", "b.mbt", "c.mbt"], 374);
  const g = judgePackage(zv);
  assert.notEqual(g, null);
  assert.equal(g!.kind, "degenerate");
  assert.ok(g!.reason.includes("退化"), "根因须是退化");
  assert.ok(g!.reason.includes("LICENSE"), "须附缺件清单（P3-4 定位）");
  assert.ok(g!.reason.includes("README.md"), "缺件清单含 README.md");
});

test("judgePackage：量过阈值但缺根级件 → 独立缺件判红（不涉退化）", () => {
  const entries = ["LICENSE", "README.md", "README.mbt.md"];
  for (let i = 0; i < 600; i++) entries.push(`pkg${i}/f${i}.mbt`);
  const zv = verdictFromListing(entries, 1_567_591);
  const g = judgePackage(zv);
  assert.notEqual(g, null);
  assert.equal(g!.kind, "missing-root");
  assert.ok(g!.reason.includes("moon.mod"));
  assert.ok(!g!.reason.includes("退化"), "量过阈值不得再报退化");
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

// ── A8 批（refs #438）───────────────────────────────────────────────────────

/** 拼完整可解压 zip：local header（真数据）+ central directory + EOCD；method 可选 store/deflate。 */
function mkZipFull(entries: ReadonlyArray<{ name: string; data: Buffer; deflate?: boolean }>): Buffer {
  const parts: Buffer[] = [];
  const cds: Buffer[] = [];
  let offset = 0;
  for (const e of entries) {
    const name = Buffer.from(e.name, "utf8");
    const comp = e.deflate ? zlib.deflateRawSync(e.data) : e.data;
    const lh = Buffer.alloc(30);
    lh.writeUInt32LE(0x04034b50, 0);
    lh.writeUInt16LE(e.deflate ? 8 : 0, 8);
    lh.writeUInt32LE(comp.length, 18);
    lh.writeUInt32LE(e.data.length, 22);
    lh.writeUInt16LE(name.length, 26);
    parts.push(lh, name, comp);
    const cd = Buffer.alloc(46);
    cd.writeUInt32LE(0x02014b50, 0);
    cd.writeUInt16LE(e.deflate ? 8 : 0, 10);
    cd.writeUInt32LE(comp.length, 20);
    cd.writeUInt32LE(e.data.length, 24);
    cd.writeUInt16LE(name.length, 28);
    cd.writeUInt32LE(offset, 42);
    cds.push(cd, name);
    offset += 30 + name.length + comp.length;
  }
  const cdBuf = Buffer.concat(cds);
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(entries.length, 10);
  eocd.writeUInt32LE(cdBuf.length, 12);
  eocd.writeUInt32LE(offset, 16);
  return Buffer.concat([...parts, cdBuf, eocd]);
}

test("unzipTo：store/deflate 往返逐字节一致 + 目录条目建目录（件③解压器）", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-unzip-"));
  const payload = Buffer.from("fn main(){}\n// 中文内容 ✓\n".repeat(50), "utf8");
  const zip = mkZipFull([
    { name: "moon.mod", data: Buffer.from('version = "0.9.1"\n') },
    { name: "pkg/", data: Buffer.alloc(0) },
    { name: "pkg/a.mbt", data: payload },
    { name: "pkg/b.mbt", data: payload, deflate: true },
  ]);
  const n = unzipTo(zip, dir);
  assert.equal(n, 3, "目录条目不计文件数");
  assert.deepEqual(fs.readFileSync(path.join(dir, "pkg", "a.mbt")), payload);
  assert.deepEqual(fs.readFileSync(path.join(dir, "pkg", "b.mbt")), payload, "deflate 路径逐字节一致");
  assert.ok(fs.statSync(path.join(dir, "pkg")).isDirectory());
  // zipRecords：方法/尺寸/本地头偏移与拼装一致
  const recs = zipRecords(zip);
  assert.equal(recs.find((r) => r.name === "pkg/b.mbt")!.method, 8);
  fs.rmSync(dir, { recursive: true, force: true });
});

test("unzipTo：zip slip 三形态拒绝（../ 段 / 绝对路径 / 盘符 / 反斜杠）", () => {
  for (const name of ["../evil.mbt", "/etc/evil", "C:/evil.mbt", "a\\b.mbt", "pkg/../../evil.mbt"]) {
    assert.equal(unsafeEntryName(name), true, name);
    const zip = mkZipFull([{ name, data: Buffer.from("x") }]);
    assert.throws(() => unzipTo(zip, fs.mkdtempSync(path.join(os.tmpdir(), "vitro-slip-"))), /不安全/, name);
  }
  assert.equal(unsafeEntryName("pkg/ok.mbt"), false);
});

test("unzipTo：local header 签名错位 / 解压长度不符 fail loud", () => {
  const zip = mkZipFull([{ name: "a.mbt", data: Buffer.from("hello") }]);
  // 篡改 LFH 签名（local header 起点在 0）
  zip.writeUInt32LE(0xdeadbeef, 0);
  assert.throws(() => unzipTo(zip, fs.mkdtempSync(path.join(os.tmpdir(), "vitro-bad-"))), /local header/);
  // 篡改 CDE 的 uncompSize → 解压长度与声明不等
  const zip2 = mkZipFull([{ name: "a.mbt", data: Buffer.from("hello") }]);
  const cdOff = zip2.length - 22 - (46 + 5);
  zip2.writeUInt32LE(999, cdOff + 24);
  assert.throws(() => unzipTo(zip2, fs.mkdtempSync(path.join(os.tmpdir(), "vitro-bad-"))), /解压长度/);
});

test("tagNameOf + judgeTag：tag 名派生 / 三路判定（件② tag 防移动）", () => {
  assert.equal(tagNameOf("0.9.1"), TAG_PREFIX + "0.9.1");
  assert.equal(tagNameOf("0.10"), null, "非 semver 三段 → null（fatal 面）");
  assert.equal(tagNameOf("v0.9.1"), null);
  const H = "5233ad65926d80d542f9a49c6870b64f351904a5";
  const T = "249ba70bc43dc7b8c61c86283fdf438d7626c144";
  // tag 不存在 → 绿（playbook 人工打）
  const miss = judgeTag("vitro-engine-9.9.9", null, H);
  assert.equal(miss.ok, true);
  // 已存在且指向 HEAD → 绿（重跑彩排不动 tag）
  assert.equal(judgeTag("vitro-engine-0.9.1", H, H).ok, true);
  // 已存在指向别的 commit → 红（真值形态：0.9.1 tag 实指 249ba70b，当前 HEAD 前进）
  const moved = judgeTag("vitro-engine-0.9.1", T, H);
  assert.equal(moved.ok, false);
  assert.match((moved as { reason: string }).reason, /禁止移动/);
  assert.match((moved as { reason: string }).reason, /249ba70b/);
});
