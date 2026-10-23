// vm.test.mts —— 三通道提取口径（stdout 剥标记 / 映像 argv 脱敏 / 整例指纹）
// + 清单键形态 + 真实仓库小规模对拍。
import { test } from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import {
  extractMoonBitStdout,
  mbWholeDigest,
  memorySHA,
  relOf,
  sampleN,
  stdinFor,
} from "./vm.mts";
import { projectRoot } from "../../internal/capi.mts";

const sha16 = (s: string | Buffer): string => crypto.createHash("sha256").update(s).digest("hex").slice(0, 16);

test("extractMoonBitStdout：剥精确前缀标记行 + 末行 EXIT + 不加尾换行", () => {
  const raw = "0\n// NOTE 程序运行完成，返回值：0\n// EXIT 0\n";
  assert.equal(extractMoonBitStdout(raw), "0");
  // 程序自己打印 `// hi` 不得误伤（只剥协议前缀）
  assert.equal(extractMoonBitStdout("// hi\n// EXIT 0\n"), "// hi");
  // 尾换行产生的空串元素不得阻碍 EXIT 剥离（探针实锤过的坑）
  assert.equal(extractMoonBitStdout("abc\n// EXIT 2\n\n"), "abc");
  // 全标记行 → 空串
  assert.equal(extractMoonBitStdout("// COMPILE-ERROR E2005 1:1 x\n"), "");
});

test("memorySHA：argv 区 0xF000..0x10000 脱敏后再算，且不改原文件", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vm-mem-"));
  try {
    const p = path.join(dir, "m.bin");
    const buf = Buffer.alloc(1024 * 1024, 0);
    buf[0xf800] = 7; // 窗内 → 应被 mask
    buf[0x20000] = 9; // 窗外 → 应保留
    fs.writeFileSync(p, buf);
    const h = memorySHA(p);

    const masked = Buffer.from(buf);
    masked.fill(0, 0xf000, 0x10000);
    assert.equal(h, sha16(masked));

    // 窗内差异不影响 hash，窗外差异影响
    const buf2 = Buffer.from(buf);
    buf2[0xf801] = 1;
    fs.writeFileSync(p, buf2);
    assert.equal(memorySHA(p), h);
    buf2[0x20001] = 1;
    fs.writeFileSync(p, buf2);
    assert.notEqual(memorySHA(p), h);

    // 原文件未被改写（脱敏只发生在内存副本）
    assert.equal(fs.readFileSync(p)[0xf800], 7);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("mbWholeDigest：exit|stdout|mem|cf 联合指纹（cf 参与）", () => {
  const a = mbWholeDigest(0, "aa", "bb", false);
  const b = mbWholeDigest(0, "aa", "bb", true);
  assert.notEqual(a, b);
  assert.equal(a, mbWholeDigest(0, "aa", "bb", false));
});

test("relOf：语料内 = corpus/name.c；外部路径 = basename", () => {
  assert.equal(relOf("corpus/gap/x.c"), "gap/x.c");
  assert.equal(relOf("tmp/other/x.c"), "x.c");
});

test("stdinFor：同名 .in 存在才返回；sampleN 均匀覆盖首尾", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vm-stdin-"));
  try {
    const c = path.join(dir, "a.c");
    fs.writeFileSync(c, "int main(){return 0;}");
    assert.equal(stdinFor(c), "");
    const inp = path.join(dir, "a.in");
    fs.writeFileSync(inp, "1\n");
    assert.equal(stdinFor(c), inp);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }

  const all = Array.from({ length: 100 }, (_, i) => `f${i}.c`);
  const s = sampleN(all, 5);
  assert.equal(s.length, 5);
  assert.equal(s[0], "f0.c");
  assert.equal(s[4], "f80.c");
});

test("真实仓库：vm 在 gap 上全 SAME（exe 缺失时断言 fail loud 契约）", () => {
  // CI 的 scripts-ts job **不构建 native exe**（只装 moon 工具链 + go + npm ci），
  // 而三通道对拍需要预编译 run.exe。故本用例双环境自适配：
  //   exe 在  → 完整三通道对拍（本地实测 733/733 与 Go 版一致）
  //   exe 不在 → 断言 fail loud 契约（exe 缺失不得静默跳过或假绿）
  // 真实对拍的 CI 覆盖由 gates-diff 的 Go 版承担（双轨期），终局切 TS 时
  // 再给 scripts-ts 补 build 步骤。
  const exe = path.join(projectRoot(), "moonbit/_build/native/release/build/cmd/run/run.exe");
  const r = spawnSync(
    process.execPath,
    [path.join(projectRoot(), "scripts/diff_gate/main.mts"), "vm", "--corpus", "gap"],
    { cwd: projectRoot(), encoding: "utf8", timeout: 600_000 },
  );
  if (!fs.existsSync(exe)) {
    assert.equal(r.status, 1, `exe 缺失时应 fail loud，实际 exit=${String(r.status)}`);
    assert.match(r.stderr, /run\.exe 不存在/);
    return;
  }
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /vm_diff\[golden\]: SAME=20 DIFF-KNOWN=0 DIFF=0 SKIP=0（共 20）/);
});

test("真实仓库：--backend wasm 缺产物时 fail loud（退出码 1）", () => {
  const shell = path.join(projectRoot(), "moonbit/_build/js/release/build/cmd/vitro_wasm/vitro_wasm.js");
  if (fs.existsSync(shell)) {
    // 本机已有 wasm 产物则跳过该负向用例（不伪造失败）
    return;
  }
  const r = spawnSync(
    process.execPath,
    [path.join(projectRoot(), "scripts/diff_gate/main.mts"), "vm", "--backend", "wasm", "--corpus", "gap", "--sample", "1"],
    { cwd: projectRoot(), encoding: "utf8", timeout: 60_000 },
  );
  assert.equal(r.status, 1);
  assert.match(r.stderr, /vitro_wasm\.js 不存在/);
});
