// cli_symmetry.test.mts —— 判据纯函数（内存注入）+ 真实仓库三臂判定（双分档）+ 子进程 rc
//
// 双分档（A1 S05-A1 / cli_smoke CLI 测试同形态，不静默 skip）：三臂产物在位 → 真跑
// 24 探针判定绿；产物缺失（Scripts TS gate job 不建 moonbit 产物）→ 断言 fail loud
// 契约（resolveArms 抛「前置产物缺失」+ 子进程 rc=2）——两档都是真断言。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { allCells, loadRules, resolveArms, verdict, type ArmResult } from "./main.mts";
import { projectRoot } from "../internal/capi.mts";

const MAIN = path.join(import.meta.dirname, "main.mts");

/** 三臂产物是否全部在位（分档开关——不是 skip 开关，两档都断言）。 */
function armsReady(rd: ReturnType<typeof loadRules>): boolean {
  return Object.values(rd.arms).every((a) => fs.existsSync(path.join(projectRoot(), a.path)));
}

/** 三臂同 rc 的假真值。 */
function fakeCells(rd: ReturnType<typeof loadRules>, rc: number, out = "用法错: 探针"): Record<string, ArmResult[]> {
  const out2: Record<string, ArmResult[]> = {};
  for (const cmd of rd.commands) {
    for (const p of Object.keys(rd.probes)) {
      out2[`${cmd}|${p}`] = Object.keys(rd.arms).map((arm) => ({ arm, rc, out }));
    }
  }
  return out2;
}

test("verdict：声明全绿形态过；声明 want 与真值分叉双向红；哑失败红；僵尸声明红", () => {
  const rd = loadRules();
  // 基线绿：rc4 cell 给 rc4+文案、rc0 cell 给 rc0
  const cells: Record<string, ArmResult[]> = {};
  for (const [k, cell] of Object.entries(rd.matrix)) {
    cells[k] = Object.keys(rd.arms).map((arm) => ({ arm, rc: cell.want, out: cell.want === 4 ? "用法错: 未知旗标" : "ok" }));
  }
  assert.equal(verdict(rd, cells).ok, true);
  // api F4 声明 rc0，真值 rc4（修复后忘改声明）→ 红
  cells["api|unknown_flag"] = Object.keys(rd.arms).map((arm) => ({ arm, rc: 4, out: "用法错" }));
  assert.equal(verdict(rd, cells).ok, false);
  // run 硬锁 rc4，真值 rc0（倒退）→ 红
  const cells2 = fakeCells(rd, 0);
  assert.equal(verdict(rd, cells2).ok, false);
  // rc=4 但无 fail loud 文案（哑失败）→ 红
  const cells3 = fakeCells(rd, 4, "静默输出");
  let sawDumb = false;
  for (const s of verdict(rd, cells3).issues) if (s.includes("哑失败")) sawDumb = true;
  assert.ok(sawDumb);
  // 臂间分叉 → 红
  const cells4 = fakeCells(rd, 4);
  cells4["compile|unknown_flag"]![0]!.rc = 0;
  assert.equal(verdict(rd, cells4).ok, false);
  // 僵尸声明格
  const rd2 = JSON.parse(JSON.stringify(rd)) as typeof rd;
  rd2.matrix["ghost|unknown_flag"] = { want: 4 };
  assert.equal(verdict(rd2, fakeCells(rd2, 4)).ok, false);
});

test("真实仓库双分档：产物在位→三臂 24 探针全绿（含 F4 现状 rc0）；缺失→fail loud 前置产物缺失", () => {
  const rd = loadRules();
  if (!armsReady(rd)) {
    // 缺失档：契约 = 不静默、不假绿——resolveArms 必抛带构建指引的 fatal
    assert.throws(() => resolveArms(rd), /前置产物缺失/);
    return;
  }
  const arms = resolveArms(rd);
  const cells = allCells(rd, arms);
  assert.equal(Object.keys(cells).length, rd.commands.length * Object.keys(rd.probes).length);
  const r = verdict(rd, cells);
  assert.equal(r.ok, true, r.issues.join("; "));
  // F4 现状锚：api 两探针 rc=0（known gap 声明在册）
  for (const k of ["api|unknown_flag", "api|extra_positional"]) {
    const rcs = new Set((cells[k] ?? []).map((x) => x.rc));
    assert.equal(rcs.size, 1);
    assert.equal([...rcs][0], 0, `${k} F4 现状应 rc=0`);
  }
});

test("子进程双分档：产物在位→-check/--selftest rc=0；缺失→rc=2 + 前置产物缺失文案；未知参数两档皆 rc=2", () => {
  const rd = loadRules();
  const run = (args: string[]): { rc: number; err: string } => {
    const r = spawnSync(process.execPath, [MAIN, ...args], { cwd: projectRoot() });
    return { rc: r.status ?? -1, err: r.stderr?.toString("utf8") ?? "" };
  };
  assert.equal(run(["--wat"]).rc, 2, "未知参数 rc=2（两档同）");
  if (armsReady(rd)) {
    assert.equal(run(["-check"]).rc, 0);
    assert.equal(run(["--selftest"]).rc, 0);
  } else {
    const c = run(["-check"]);
    assert.equal(c.rc, 2, "产物缺失须 fail loud rc=2 而非假绿/假红");
    assert.match(c.err, /前置产物缺失/);
  }
});
