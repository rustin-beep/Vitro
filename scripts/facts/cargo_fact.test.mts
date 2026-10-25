// cargo_fact.test.mts —— cargo test 真值解析器（collectCargoTestFromOutput）
// 的绿路径 + J9 埋雷。直译自 cargo_fact_test.go。
//
// 背景（2026-09-22 修复）：suites 解析失败时曾**不写任何键**——沿用逻辑
// （collectAll 只对"键存在且 unavailable"的条目生效）因此跳过，CI 形态
// （--cargo-log）采到的套件数真值会在下一次日常运行落盘时被无声丢弃，
// 本地永远"待采集"、无法预演 CI 的漂移判定。修复 = 与 passed 对称地写
// unavailable。本文件的埋雷测试在修复前会红（键缺失 ≠ unavailable）。
import assert from "node:assert/strict";
import { test } from "node:test";
import { collectCargoTestFromOutput } from "./facts.mts";
import type { Fact } from "./facts.mts";

const cargoLogSample = `     Running tests\\vitro_e2e.rs (target\\debug\\deps\\vitro_e2e-a1.exe)

running 3 tests
test a ... ok
test result: ok. 3 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out

     Running tests\\typeck_unit_test.rs (target\\debug\\deps\\typeck_unit_test-b2.exe)

running 5 tests
test result: ok. 5 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out
`;

test("cargo 解析绿路径（3+5=8 passed / 2 suites）", () => {
  const facts: Record<string, Fact> = {};
  collectCargoTestFromOutput(cargoLogSample, 0, "native/cargo_test_ci.log", "parse_ci_log", facts);
  const p = facts["cargo_test_passed"]!;
  assert.ok(p.status === "ok" && p.value === 8, `passed 绿路径（3+5=8）解析失败: ${JSON.stringify(p)}`);
  const s = facts["cargo_test_suites"]!;
  assert.ok(s.status === "ok" && s.value === 2, `suites 绿路径（2 个 Running 行）解析失败: ${JSON.stringify(s)}`);
});

test("cargo J9 埋雷①：有 test result 无 Running 行 → suites 显式 unavailable", () => {
  const facts: Record<string, Fact> = {};
  collectCargoTestFromOutput("test result: ok. 3 passed; 0 failed", 0, "log", "parse_ci_log", facts);
  const s = facts["cargo_test_suites"];
  assert.ok(s !== undefined && s.status === "unavailable",
    `无 Running 行应显式 unavailable（键缺失会绕过沿用）: ${JSON.stringify(s)}`);
});

test("cargo J9 埋雷②：空/损坏日志两键均 unavailable", () => {
  const facts: Record<string, Fact> = {};
  collectCargoTestFromOutput("", 0, "log", "parse_ci_log", facts);
  for (const k of ["cargo_test_passed", "cargo_test_suites"]) {
    const f = facts[k];
    assert.ok(f !== undefined && f.status === "unavailable", `${k} 空输出应显式 unavailable: ${JSON.stringify(f)}`);
  }
});

test("cargo J9 埋雷③：构建失败（0 套件/0 passed）unavailable 而非 0", () => {
  const facts: Record<string, Fact> = {};
  collectCargoTestFromOutput("Compiling vitro_native v0.1.0\nerror: build failed", 101, "log", "parse_ci_log", facts);
  assert.equal(facts["cargo_test_suites"]!.status, "unavailable", "构建失败（0 套件）应 unavailable 而非 0");
  assert.equal(facts["cargo_test_passed"]!.status, "unavailable", "构建失败（0 passed）应 unavailable");
});
