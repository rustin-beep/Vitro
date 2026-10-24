// vitro_cli_smoke.test.mts —— 通道口径 + fail loud 前置 + CLI 端到端（.mts 重写批）。
//
// 覆盖面：
//   - 三个纯函数口径：stripBackendLine（唯一允许差异的剥离面）/ firstDiff（映像首差）
//     / runOut 的「stdout + \n--stderr--\n + stderr」合并与 CRLF 归一；
//   - 子进程 rc 透传与通道分离（spawn 语义——比 rc 会被 go run 折码骗，这里用 node -e）；
//   - CLI：缺产物 fail loud（rc 1 + 构建指引）、flag 用法错 rc 2；
//   - e2e：四臂产物就绪时跑真闸（缺产物显式 skip，不静默）。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { projectRoot } from "../internal/capi.mts";
import { firstDiff, runOut, runSplit, stripBackendLine } from "./main.mts";

const MAIN = path.join(import.meta.dirname, "main.mts");
const NODE = process.execPath;

const ARTIFACTS = [
  "moonbit/_build/js/release/build/cmd/vitro_wasm/vitro_wasm.js",
  "moonbit/_build/native/release/build/cmd/vitro/vitro.exe",
  "moonbit/_build/wasm-gc/release/build/gateway/wasm/wasm.wasm",
  "moonbit/_build/js/release/build/cmd/vitro_js/vitro_js.js",
];
const artifactsReady = ARTIFACTS.every((p) => fs.existsSync(path.join(projectRoot(), p)));

test("stripBackendLine：只剥 [vitro] backend= 行，其余逐字保留", () => {
  const s = "out\n[vitro] backend=wasm (node 22.22.2)\n// NOTE x\n";
  assert.equal(stripBackendLine(s), "out\n// NOTE x\n");
  assert.equal(stripBackendLine("[vitro] backend=js\n"), "");
  assert.equal(stripBackendLine("no backend line"), "no backend line");
});

test("firstDiff：返首差偏移，等长前缀相同返 len", () => {
  assert.equal(firstDiff(Buffer.from([1, 2, 3]), Buffer.from([1, 9, 3])), 1);
  assert.equal(firstDiff(Buffer.from([1, 2]), Buffer.from([1, 2])), 2);
  assert.equal(firstDiff(Buffer.from([1, 2, 3]), Buffer.from([1, 2])), 2, "较短者长度封顶");
});

test("runOut：合并通道口径 = stdout + \\n--stderr--\\n + stderr，且 CRLF 归一", () => {
  const r = runOut(NODE, ["-e", 'process.stdout.write("o\\r\\n"); process.stderr.write("e\\n");']);
  assert.equal(r.out, "o\n\n--stderr--\ne\n");
  assert.equal(r.rc, 0);
});

test("runOut：真实退出码透传（不被折成 1）", () => {
  assert.equal(runOut(NODE, ["-e", "process.exit(3)"]).rc, 3);
  assert.equal(runOut(NODE, ["-e", "process.exit(0)"]).rc, 0);
});

test("runSplit：分离捕获，stdout 不含 stderr 文案（#215 通道归属判据面）", () => {
  const r = runSplit(NODE, ["-e", 'process.stdout.write("OUT"); process.stderr.write("ERR"); process.exit(4);']);
  assert.equal(r.out, "OUT");
  assert.equal(r.err, "ERR");
  assert.equal(r.rc, 4);
});

test("CLI：缺四臂产物 → rc 1 + 前置产物缺失 + 构建指引（fail loud，不静默跳过）", () => {
  const empty = fs.mkdtempSync(path.join(os.tmpdir(), "vcs-empty-"));
  const r = spawnSync(NODE, [MAIN], { cwd: empty, encoding: "utf8" });
  assert.equal(r.status, 1);
  // 路径分隔符随平台（Go filepath.Join 同形：Windows 反斜杠）；grep 口径双兼容
  assert.match(r.stdout, /vitro_cli_smoke: 前置产物缺失 moonbit[\\/]_build[\\/]/);
  assert.match(r.stdout, /先构建：moon build --release --target wasm-gc gateway\/wasm/);
});

test("CLI：flag 用法错 rc 2（--corpus 缺值 / 未知旗标）", () => {
  const missing = spawnSync(NODE, [MAIN, "--corpus"], { encoding: "utf8" });
  assert.equal(missing.status, 2);
  assert.match(missing.stdout, /flag needs an argument: -corpus/);

  const bogus = spawnSync(NODE, [MAIN, "--no-such-flag"], { encoding: "utf8" });
  assert.equal(bogus.status, 2);
  assert.match(bogus.stdout, /flag provided but not defined: --no-such-flag/);
});

test("e2e：四臂产物就绪时默认模式全绿（缺产物显式 skip）", (t) => {
  if (!artifactsReady) {
    t.diagnostic("skip：四臂产物未构建（MOON_CC=clang moon build --release --target {native,js,wasm-gc} …）");
    return;
  }
  const r = spawnSync(NODE, [MAIN], { cwd: projectRoot(), encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  assert.equal(r.status, 0, r.stdout.slice(-2000));
  assert.match(r.stdout, /ok {2}A\[壳 rc\] run 正常 rc=0/);
  assert.match(r.stdout, /ok {2}B\[三臂对拍\] 普通用例（rc=0 同形）/);
  assert.match(r.stdout, /ok {2}B\[rc=4 stdout 空\] 8 路径 × 三臂/);
  assert.match(r.stdout, /vitro_cli_smoke: 全绿/);
  assert.equal((r.stdout.match(/^FAIL/gm) ?? []).length, 0, "全绿跑不应有 FAIL 行");
});
