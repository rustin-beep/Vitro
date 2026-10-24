// toolchain_probe.test.mts —— 基线判定口径 + ICE 特征 + 端到端（.mts 重写批）。
//
// 判定面全是纯函数（基线行归一 / 匹配 / ICE 特征）+ 一条真跑；版本漂移的
// 证红已在批内实测（改基线 moon 0.1.→0.9.：双侧 rc=1 且输出逐字同）。
import { test } from "node:test";
import assert from "node:assert/strict";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { projectRoot } from "../internal/capi.mts";
import { baselineLines, baselineMatches, isKnownICE } from "./toolchain_probe.mts";

const MAIN = path.join(import.meta.dirname, "toolchain_probe.mts");

test("baselineLines：CRLF 归一 + 剔注释/空行 + 逐行 trim", () => {
  const raw = "# 注释\r\n\r\nmoon 1.2.3 (abc 2026-01-01)\r\n  moonc v0.10.15  \r\n";
  assert.deepEqual(baselineLines(raw), ["moon 1.2.3 (abc 2026-01-01)", "moonc v0.10.15"]);
  assert.deepEqual(baselineLines(""), []);
});

test("baselineMatches：行尾 \r 残留不致假红（CI 2026-09-22 实锤面）", () => {
  const crlf = "# x\r\nmoon 1.2.3 (a b)\r\nmoonc v1\r\n";
  const lf = "# x\nmoon 1.2.3 (a b)\nmoonc v1\n";
  assert.equal(baselineMatches(crlf, lf), true);
  assert.equal(baselineMatches(crlf, "moon 1.2.4 (a b)\nmoonc v1"), false);
});

test("isKnownICE：core 符号 / link-core / segfault+pub let 三特征", () => {
  assert.equal(isKnownICE("undefined reference to `_ZN4moon7core...'"), true);
  assert.equal(isKnownICE("error: link-core failed"), true);
  assert.equal(isKnownICE("segfault: cross-file pub let"), true, "小写 segfault + 小写 pub let");
  assert.equal(isKnownICE("Segmentation fault while building PUB LET"), false, "Go 版特征串是字面 \"segfault\"——大小写敏感，此处如实登记");
  assert.equal(isKnownICE("error: expected token"), false);
});

test("e2e：四项检查全绿（缺 moon 工具链显式 skip）", (t) => {
  const ver = spawnSync("moon", ["version"], { encoding: "utf8" });
  if (ver.status !== 0) {
    t.diagnostic("skip：moon 不在 PATH");
    return;
  }
  const r = spawnSync(process.execPath, [MAIN], { cwd: projectRoot(), encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.match(r.stdout, /\[绿\] 版本锁定: moon \S+ \/ moonc \S+/);
  assert.match(r.stdout, /\[绿\] registry 索引: moon update 行为通过（\d+ 顶层条目）/);
  assert.match(r.stdout, /\[绿\] 探针编译: F8 形状（跨文件顶层 pub let）在当前工具链下存活/);
  assert.match(r.stdout, /toolchain_probe: PASS（版本锁定 \+ 索引预检 \+ ICE 特征 \+ 退出码四项绿）/);
});
