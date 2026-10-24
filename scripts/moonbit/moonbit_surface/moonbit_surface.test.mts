// moonbit_surface.test.mts —— 词边界/空行硬性项 + 双模式端到端（.mts 重写批）。
//
// 判定面的重型部分（包发现/别名解析/边表对账）由端到端覆盖：本闸对全仓
// moonbit/ 现场对账，粗粒度 e2e 比碎单位测试更能抓住口径漂移。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { projectRoot } from "../../internal/capi.mts";
import { hasWord, noConsecutiveBlankLines } from "./moonbit_surface.mts";

const MAIN = path.join(import.meta.dirname, "moonbit_surface.mts");

test("hasWord：词边界判定（Severity 不命中 SeverityX / XSeverity / Severity_1）", () => {
  assert.equal(hasWord("pub struct Severity", "Severity"), true);
  assert.equal(hasWord("SeverityX", "Severity"), false);
  assert.equal(hasWord("XSeverity", "Severity"), false);
  assert.equal(hasWord("Severity_1", "Severity"), false);
  assert.equal(hasWord("a Severity b", "Severity"), true);
  assert.equal(hasWord("Severity,Other", "Severity"), true);
  assert.equal(hasWord("nothing here", "Severity"), false);
});

test("noConsecutiveBlankLines：≥2 连续空行即红（退出码 1，与 Go 版一致）", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "ms-blank-"));
  const ok = path.join(dir, "ok.txt");
  fs.writeFileSync(ok, "a\n\nb\n");
  assert.doesNotThrow(() => noConsecutiveBlankLines(ok));

  const bad = path.join(dir, "bad.txt");
  fs.writeFileSync(bad, "a\n\n\nb\n");
  assert.throws(
    () => noConsecutiveBlankLines(bad),
    (e: unknown) => (e as { code?: number }).code === 1,
    "两条以上连续空行必须 exit 1",
  );

  const missing = path.join(dir, "nope.txt");
  assert.throws(() => noConsecutiveBlankLines(missing), (e: unknown) => (e as { code?: number }).code === 1);
});

function cli(args: string[]): { out: string; err: string; rc: number } {
  const r = spawnSync(process.execPath, [MAIN, ...args], { cwd: projectRoot(), encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  return { out: r.stdout ?? "", err: r.stderr ?? "", rc: r.status ?? -1 };
}

test("e2e：-check 与白名单/边表双向对账一致（真实全仓）", () => {
  const r = cli(["-check"]);
  assert.equal(r.rc, 0, r.err + r.out);
  assert.match(r.out, /moonbit_surface: check OK（可收清单与白名单一致 \+ 消费边与边清单一致）/);
});

test("e2e：默认模式同强度（列收面 + 同一 OK 行），且不因缺 -check 而放松", () => {
  const r = cli([]);
  assert.equal(r.rc, 0, r.err + r.out);
  assert.match(r.out, /个无跨包消费 pub 符号（收面对象；对账 surface_allowlist\.txt）/);
  assert.match(r.out, /个 pub 类型为签名闭包（保持 pub，不计入收面）/);
  assert.match(r.out, /check OK/);
});

test("e2e：白名单缺失时 fail loud（exit 2，不静默放过）", () => {
  // 在临时目录里造一个最小 moonbit/（有 moon.mod + 一个包），但没有白名单——
  // 脚本 chdir 到 moonbit/ 后读 ../scripts/moonbit/surface_allowlist.txt 必失败。
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "ms-e2e-"));
  const mb = path.join(root, "moonbit");
  fs.mkdirSync(path.join(mb, "app"), { recursive: true });
  fs.writeFileSync(path.join(mb, "moon.mod"), 'name = "vitro/engine"\n');
  fs.writeFileSync(path.join(mb, "app", "moon.pkg"), "");
  fs.writeFileSync(path.join(mb, "app", "a.mbt"), "pub fn helper() -> Int { 1 }\n");
  fs.writeFileSync(path.join(mb, "app", "pkg.generated.mbti"), "pub fn helper() -> Int\n");
  fs.mkdirSync(path.join(root, "scripts", "moonbit"), { recursive: true });
  // 边清单在位（否则先炸边清单缺失），白名单故意缺
  fs.writeFileSync(path.join(root, "scripts", "moonbit", "surface_edges.txt"), "");
  const r = spawnSync(process.execPath, [MAIN, "-check"], { cwd: root, encoding: "utf8" });
  assert.equal(r.status, 2, r.stdout + r.stderr);
  assert.match(r.stderr, /白名单缺失/);
});
