// serve_smoke.test.mts —— 断言计数/豁免口径 + 协议批端到端 + RSS 证红（.mts 重写批）。
//
// 覆盖三层：
//   1. 纯 helper（行切分 / rune 尾部截断 / 帧解析）；
//   2. 端到端：-moonbit 主跑（68 断言 + 2 豁免）+ 豁免审计轮（D19）；
//   3. **证红通道**：VITRO_RSS_BUDGET_MB=5 → RSS 护栏断言必须红（U0#2「先证会红」义务）。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { projectRoot } from "../internal/capi.mts";
import { nonEmptyLines, parseFrame, peakCommitMB, tailRunes } from "./main.mts";

const MAIN = path.join(import.meta.dirname, "main.mts");
const ROOT = projectRoot();
const SERVE = path.join(ROOT, "moonbit", "_build", "native", "debug", "build", "cmd", "serve", "serve.exe");
const serveReady = fs.existsSync(SERVE);

test("nonEmptyLines：只留非空行（保留原行文本，不 trim 内容）", () => {
  assert.deepEqual(nonEmptyLines("a\n\n  \nb\r\n"), ["a", "b\r"]);
  assert.deepEqual(nonEmptyLines(""), []);
});

test("tailRunes：按 rune 取尾（CJK/emoji 各算 1），短串原样", () => {
  assert.equal(tailRunes("中文😀abc", 3), "abc");
  assert.equal(tailRunes("中文😀", 2), "文😀", "按码点取尾（UTF-16 切片只会拿到半个 emoji）");
  assert.equal(tailRunes("abc", 10), "abc");
  assert.equal(tailRunes("", 3), "");
});

test("parseFrame：合法帧解析 / 非对象与非 JSON 抛错", () => {
  const f = parseFrame('{"id":1,"ok":true}');
  assert.equal(f["id"], 1);
  assert.throws(() => parseFrame("[1,2]"), /顶层不是对象/);
  assert.throws(() => parseFrame("{ this is not json"));
});

test("peakCommitMB：无效 pid 返回 -1（采样失败口径，触发「采样可用」红）", () => {
  assert.equal(peakCommitMB(-1), -1);
});

function cli(args: string[], env?: Record<string, string>): { out: string; err: string; rc: number } {
  const r = spawnSync(process.execPath, [MAIN, ...args], {
    cwd: ROOT,
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
    timeout: 300_000,
    env: { ...process.env, ...env },
  });
  return { out: r.stdout ?? "", err: r.stderr ?? "", rc: r.status ?? -1 };
}

test("e2e：未选臂 → exit 2 并打印现役两枝", () => {
  const r = cli([]);
  assert.equal(r.rc, 2);
  assert.match(r.out, /错误: 未选被测物臂——rust 臂已退役/);
  assert.match(r.out, /-moonbit {12}# native cmd\/serve exe/);
});

test("e2e：--audit-exemptions 未配臂 → exit 2（豁免面只作用于 MoonBit 产物臂）", () => {
  const r = cli(["--audit-exemptions"]);
  assert.equal(r.rc, 2);
  assert.match(r.out, /--audit-exemptions 须与 --moonbit\/--backend-wasm 同用/);
});

test("e2e：VITRO_CLI 指向不存在的产物 → exit 2（fail loud，不静默降级）", () => {
  const r = cli([], { VITRO_CLI: path.join(ROOT, "no_such_serve.exe") });
  assert.equal(r.rc, 2);
  assert.match(r.out, /VITRO_CLI 指定的 .* 不存在/);
});

test("e2e：-moonbit 主跑全绿（68 断言 2 豁免）", (t) => {
  if (!serveReady) {
    t.diagnostic("skip：cmd/serve 产物未构建");
    return;
  }
  const r = cli(["-moonbit"]);
  assert.equal(r.rc, 0, (r.out ?? "").slice(-3000) + r.err);
  assert.match(r.out, /MoonBit serve: .*（豁免 2 断言 \+ 0 整批）/);
  assert.match(r.out, /responses=25 \(requests=25\)/);
  assert.match(r.out, /MoonBit 臂断言数: 69 {2}\(PASS 67 \/ FAIL 0 \/ 豁免 2\)/);
  assert.match(r.out, /serve 冒烟全部通过/);
  assert.match(r.out, /PASS {2}RSS 护栏：提交峰值在预算内/);
});

test("e2e：豁免审计轮无僵尸（原豁免条目真跑即 FAIL = 合法证明）", (t) => {
  if (!serveReady) {
    t.diagnostic("skip：cmd/serve 产物未构建");
    return;
  }
  const r = cli(["-moonbit", "--audit-exemptions"]);
  assert.equal(r.rc, 0, r.out.slice(-2000) + r.err);
  assert.match(r.out, /LEGIT\(FAIL\) {5}ping 携带 ABI 版本/);
  assert.match(r.out, /豁免审计：无僵尸（全部豁免经真跑证伪为合法）/);
});

test("e2e 证红：VITRO_RSS_BUDGET_MB=5 → RSS 护栏断言必红（exit 1）", (t) => {
  if (!serveReady) {
    t.diagnostic("skip：cmd/serve 产物未构建");
    return;
  }
  const r = cli(["-moonbit"], { VITRO_RSS_BUDGET_MB: "5" });
  assert.equal(r.rc, 1, r.out.slice(-2000));
  assert.match(r.out, /FAIL {2}RSS 护栏：提交峰值在预算内 {2}peak=\d+MB budget=5MB/);
  assert.match(r.out, /FAILED: 1 项 -> \["RSS 护栏：提交峰值在预算内"\]/);
});
