// moonbit_fact.test.mts —— T6（2026-09-19）：MoonBit 测试真值解析器——绿路径
// + J9 埋雷（假输出 / 无 Total 行 / 失败计数非零时的字段语义），直译自
// moonbit_fact_test.go。
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import {
  collectAbiVersion, collectAll, collectCargoTestFromLog,
  collectMoonbitCheckWarningsFromOutput, collectMoonbitCoverageFromOutput, collectMoonbitFromOutput, collectMoonbitNativeFromOutput, collectMoonbitPackages, parseLexerDiffPass, parseParserDiffPass,
} from "./facts.mts";
import { RUN_KEYS } from "./facts.mts";
import type { Fact, FactsDoc } from "./facts.mts";

const factsOf = (): Record<string, Fact> => ({});

test("moonbit 解析绿路径", () => {
  const facts = factsOf();
  collectMoonbitFromOutput("Total tests: 58, passed: 58, failed: 0", 0, facts);
  const f = facts["moonbit_test_passed"];
  assert.ok(f !== undefined && f.status === "ok" && f.value === 58, `绿路径解析失败: ${JSON.stringify(f)}`);
});

// PR #457 审阅 P3 处置（2026-11-04，翻案 2026-10 旧裁「失败仍记 passed」）：
// 失败运行的 passed 不是计数真值——偶发一条失败曾被记成 ok 事实（value=真值-1），
// strict 对文档即 flaky 红（审阅实锤 1186/1187）。新语义：失败运行 = unavailable
// （真值只采绿运行），失败量与首败测试名进 note 供诊断。
test("moonbit 失败运行不产真值：unavailable + note 带失败量与首败（翻案锚）", () => {
  const facts = factsOf();
  const out = "[vitro/engine] test x/y_wbtest.mbt:12 (\"t_name\") failed: 断言不符\nTotal tests: 10, passed: 8, failed: 2";
  collectMoonbitFromOutput(out, 1, facts);
  const f = facts["moonbit_test_passed"]!;
  assert.ok(f.status === "unavailable", `失败运行应 unavailable: ${JSON.stringify(f)}`);
  assert.ok(f.value === null || f.value === undefined, "失败运行不得携带数值真值");
  assert.ok((f.note ?? "").includes("failed=2"), `note 应带失败量: ${f.note}`);
  assert.ok((f.note ?? "").includes("t_name") || (f.note ?? "").includes("failed:"), `note 应带首败线索: ${f.note}`);
});

test("moonbit 单条偶发失败同样 unavailable（flaky ±1 病根锚）", () => {
  const facts = factsOf();
  collectMoonbitFromOutput("Total tests: 1187, passed: 1186, failed: 1", 1, facts);
  const f = facts["moonbit_test_passed"]!;
  assert.ok(f.status === "unavailable", `passed=1186/failed=1 应 unavailable（防记成真值 1186 触发文档漂移假红）: ${JSON.stringify(f)}`);
});

test("moonbit 非零退出码零失败形态同样不产真值", () => {
  const facts = factsOf();
  collectMoonbitFromOutput("Total tests: 10, passed: 10, failed: 0", 1, facts);
  assert.equal(facts["moonbit_test_passed"]!.status, "unavailable", "exit=1 且 failed=0（崩尾形态）应 unavailable");
});

test("moonbit native 口径同语义（失败不产真值）", () => {
  const facts = factsOf();
  collectMoonbitNativeFromOutput("Total tests: 10, passed: 9, failed: 1", 1, facts);
  const f = facts["moonbit_test_passed_native"]!;
  assert.ok(f.status === "unavailable", `native 失败运行应 unavailable: ${JSON.stringify(f)}`);
});

test("moonbit J9 埋雷：无 Total 行 unavailable 禁兜底 0", () => {
  const facts = factsOf();
  collectMoonbitFromOutput("Error: [3002] parse error ...", 1, facts);
  const f = facts["moonbit_test_passed"];
  assert.ok(f !== undefined && f.status === "unavailable", `无 Total 行应 unavailable: ${JSON.stringify(f)}`);
});

test("moonbit J9 埋雷：空输出 unavailable", () => {
  const facts = factsOf();
  collectMoonbitFromOutput("", 0, facts);
  assert.equal(facts["moonbit_test_passed"]!.status, "unavailable", "空输出应 unavailable");
});

// #308（2026-10-26）：native 口径全量键——绿路径 + J9（无 Total 行禁兜底）
// + RUN_KEYS 登记（CI cached 沿用语义须在册）。
test("moonbit native 口径绿路径（#308）", () => {
  const facts = factsOf();
  collectMoonbitNativeFromOutput("Total tests: 1053, passed: 1053, failed: 0", 0, facts);
  const f = facts["moonbit_test_passed_native"];
  assert.ok(f !== undefined && f.status === "ok" && f.value === 1053, `native 绿路径解析失败: ${JSON.stringify(f)}`);
});

test("moonbit native J9 埋雷：无 Total 行 unavailable（#308）", () => {
  const facts = factsOf();
  collectMoonbitNativeFromOutput("link-core failed", 1, facts);
  const f = facts["moonbit_test_passed_native"];
  assert.ok(f !== undefined && f.status === "unavailable", `native 无 Total 行应 unavailable: ${JSON.stringify(f)}`);
});

test("moonbit native 口径键在 RUN_KEYS 在册（#308）", () => {
  assert.ok(RUN_KEYS.includes("moonbit_test_passed_native"), "moonbit_test_passed_native 须登记 RUN_KEYS（cached 沿用语义）");
});

// #338（2026-10-27）：coverage 记账键——绿路径（report 末行 Total: c/t，
// 值 = total−covered）+ J9 双埋雷（analyze 展示层口径「N uncovered」单数字
// 形态不得匹配 / 无 Total 行 unavailable）+ RUN_KEYS 在册。
test("moonbit coverage 绿路径（#338）", () => {
  const facts = factsOf();
  collectMoonbitCoverageFromOutput("util\\util.mbt: 146/160\nTotal: 18171/30657", facts);
  const f = facts["moonbit_coverage_uncovered_lines"];
  assert.ok(f !== undefined && f.status === "ok" && f.value === 12486,
    `coverage 绿路径解析失败: ${JSON.stringify(f)}`);
  assert.ok(f.note!.includes("18171/30657"), "note 须带 covered/total 三件（对账锚）");
});

test("moonbit coverage J9 埋雷：analyze 展示层口径不得采（#338）", () => {
  const facts = factsOf();
  // analyze caret 末行是「Total: N uncovered line(s)」单数字形态——
  // 与 report 的 x/y 形态口径不同（实测 4827 vs 12486），混采即毒数字
  collectMoonbitCoverageFromOutput("244\t_ => return None\t<-- UNCOVERED\nTotal: 4827 uncovered line(s) in 135 file(s)", facts);
  assert.equal(facts["moonbit_coverage_uncovered_lines"]!.status, "unavailable",
    "「N uncovered」展示层口径不应被匹配为真值");
});

test("moonbit coverage 口径键在 RUN_KEYS 在册（#338）", () => {
  assert.ok(RUN_KEYS.includes("moonbit_coverage_uncovered_lines"),
    "moonbit_coverage_uncovered_lines 须登记 RUN_KEYS（cached 沿用语义）");
});

// S2：词法差分真值解析——绿路径 + J9 埋雷（FAIL 输出禁兜底）。
test("lexer_diff PASS 行解析绿路径", () => {
  // 2026-10-25 #307 P2-1 连坐翻锚：样本改用真实生产者行（diff_gate 五族统一
  // 形态「N 个 case hash 与冻结基线一致」——此前直译 Go 版旧样本致锚幽灵形态）
  const r = parseLexerDiffPass("lexer_diff[golden]: PASS——1002 个 case hash 与冻结基线一致（语料 baseline）");
  assert.ok(r.ok && r.n === 1002, `绿路径解析失败: n=${r.n} ok=${r.ok}`);
  // 旧形态（TSV 时代）不匹配（防倒退）
  assert.ok(!parseLexerDiffPass("lexer_diff: PASS——4800 个 TSV 逐字节一致（语料 x）").ok, "旧 TSV 形态不应再匹配");
});

test("lexer_diff J9 埋雷：FAIL 输出不可采", () => {
  const r = parseLexerDiffPass("lexer_diff: FAIL——3 处差异（语料 x）");
  assert.ok(!r.ok && r.n === 0, `FAIL 输出必须不可采：n=${r.n} ok=${r.ok}`);
});

// S3 审阅补线（2026-09-20，F7）：解析差分真值解析器——绿路径 + J9 埋雷。
test("parser_diff PASS 行解析绿路径（含旧形态防倒退）", () => {
  // 2026-10-25 #307 P2-1 连坐翻锚：现役形态 = diff_gate 五族统一「N 个 case
  // hash 与冻结基线一致」（4e86d368 的「N hash 一致」亦成旧形态）
  const r = parseParserDiffPass("parser_diff[golden]: PASS——500 个 case hash 与冻结基线一致（语料 baseline，1 例 known-fork 跳过）");
  assert.ok(r.ok && r.n === 500, `绿路径解析失败: n=${r.n} ok=${r.ok}`);
  // 旧两形态均不匹配（防倒退）
  assert.ok(!parseParserDiffPass("parser_diff[golden:corpus-x]: PASS——597 hash 一致（fork 跳过 1）").ok, "「N hash 一致」旧形态不应再匹配");
  assert.ok(!parseParserDiffPass("PASS——597 个样本").ok, "「N 个样本」旧形态不应再匹配");
  // 旧形态不匹配（防倒退）
  assert.ok(!parseParserDiffPass("PASS——597 个样本").ok, "旧形态不应再匹配");
});

test("parser_diff J9 埋雷：FAIL 与崩溃输出不可采", () => {
  for (const out of [
    "parser_diff: FAIL——3 处差异（语料 x）",
    "parser_diff: moon run cmd/dump_ast 失败: exit status 0xc00000fd",
  ]) {
    const r = parseParserDiffPass(out);
    assert.ok(!r.ok && r.n === 0, `假输出必须不可采（${out}）: n=${r.n} ok=${r.ok}`);
  }
});

// ── 建包状态采集（2026-09-28 包图防漂移批）────────────────────────────────

test("moonbit 包扫描绿路径（排除 _build/.mooncakes）", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "facts-pkgs-"));
  for (const d of [
    "moonbit/ast", "moonbit/vm", "moonbit/protocol",
    "moonbit/cmd/run", "moonbit/lexer/internal/scanner",
    "moonbit/_build/pkg", "moonbit/.mooncakes/moonbitlang/x/fs", // 必须排除
  ]) {
    fs.mkdirSync(path.join(root, ...d.split("/")), { recursive: true });
    fs.writeFileSync(path.join(root, ...d.split("/"), "moon.pkg"), "{}");
  }
  fs.writeFileSync(path.join(root, "moonbit", "moon.mod"), 'name = "vitro/engine"\n\nversion = "0.6.0"\n');
  const facts = factsOf();
  collectMoonbitPackages(root, facts);

  const f = facts["moonbit_built_packages"];
  assert.ok(f !== undefined && f.status === "ok" && f.svalue !== undefined && f.svalue !== "",
    `built_packages 绿路径失败: ${JSON.stringify(f)}`);
  const got = new Set(f.svalue!.split(/\s+/).filter((x) => x !== ""));
  for (const want of ["moonbit/ast", "moonbit/vm", "moonbit/protocol", "moonbit/cmd/run", "moonbit/lexer/internal/scanner"]) {
    assert.ok(got.has(want), `缺包 ${want}: ${f.svalue}`);
  }
  for (const banned of ["moonbit/_build/pkg", "moonbit/.mooncakes/moonbitlang/x/fs"]) {
    assert.ok(!got.has(banned), `排除目录漏网: ${f.svalue}`);
  }

  const v = facts["moonbit_engine_version"];
  assert.ok(v !== undefined && v.status === "ok" && v.svalue === "0.6.0",
    `engine_version 绿路径失败: ${JSON.stringify(v)}`);
});

test("moonbit J9 埋雷：moon.mod 缺 version 字段 unavailable", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "facts-pkgs2-"));
  fs.mkdirSync(path.join(root, "moonbit", "ast"), { recursive: true });
  fs.writeFileSync(path.join(root, "moonbit", "ast", "moon.pkg"), "{}");
  fs.writeFileSync(path.join(root, "moonbit", "moon.mod"), 'name = "vitro/engine"\n');
  const facts = factsOf();
  collectMoonbitPackages(root, facts);
  assert.equal(facts["moonbit_engine_version"]!.status, "unavailable", "缺 version 字段必须 unavailable");
  const f = facts["moonbit_built_packages"]!;
  assert.ok(f.status === "ok" && f.svalue!.includes("moonbit/ast"), `包扫描不受 moon.mod 影响: ${JSON.stringify(f)}`);
});

test("moonbit J9 埋雷：空树 unavailable 禁空串冒充真值", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "facts-pkgs3-"));
  const facts = factsOf();
  collectMoonbitPackages(root, facts);
  assert.equal(facts["moonbit_built_packages"]!.status, "unavailable", "空树必须 unavailable");
});

// runKeys 沿用名单完整性锚（2026-09-29）：无 --run 运行时 collectAll 走 else
// 占位的键，若采集器新增了占位而漏登 runKeys，已采真值会在下一次日常
// check 写盘时被静默覆盖丢弃。行为锚：占位产生的 unavail 键必须全部落在
// runKeys 内，漏登即红。
test("runKeys 覆盖全部 --run 占位键", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "facts-runkeys-"));
  fs.mkdirSync(path.join(root, "moonbit"));
  const doc: FactsDoc = collectAll(root, false, false, "", null);
  const inRunKeys = new Set(RUN_KEYS);
  for (const [k, f] of Object.entries(doc.facts)) {
    if (f.status !== "unavailable") continue;
    if (!f.note.includes("--run") && !f.how_to_get.includes("--run")) {
      continue; // 只管「--run 才执行」占位形态，非采集类 unavail 不在管辖
    }
    assert.ok(inRunKeys.has(k), `占位键 ${k} 漏登 runKeys——--run 采集的真值会在下次日常运行被覆盖丢弃`);
  }
});

// #308（2026-10-26）：反向完整性锚——「--run 才执行」采集族键在非 --run
// 的 else 占位**必须在场**：沿用逻辑只接「键在且 unavailable」形态，占位
// 缺失 = 沿用跳过 ⇒ 落盘丢键 ⇒ 已采真值静默蒸发 + 文档引用进「待采集」
// 假绿面（#298 病族第三例实锤：moonbit_test_passed_native --run 采到
// 1053、下一次日常 check 键消失、毒数字 1077 无判定）。与上锚方向互补：
// 上锚抓「占位漏登 runKeys」，本锚抓「runKeys 族漏占位」。
test("RUN_KEYS 采集族键非 --run 时对称占位（#308 防落盘丢键）", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "facts-runkeys2-"));
  fs.mkdirSync(path.join(root, "moonbit"));
  const doc: FactsDoc = collectAll(root, false, false, "", null);
  for (const k of [
    "replay_assertions", "serve_smoke_assertions", "moonbit_test_passed",
    "moonbit_test_passed_native", "moonbit_lexer_diff_tsv", "moonbit_parser_diff_samples",
    "moonbit_coverage_uncovered_lines",
  ]) {
    const f = doc.facts[k];
    assert.ok(f !== undefined && f.status === "unavailable",
      `键 ${k} 须在非 --run 时对称占位 unavailable（缺失=沿用跳过→落盘丢键）`);
  }
});

// collectAbiVersion 退役契约锚（工序④删区 2026-10-05）。
test("abi_version 采集器退役形态", () => {
  const facts = factsOf();
  collectAbiVersion("/nonexistent", facts);
  const f = facts["abi_version"];
  assert.ok(f !== undefined, "abi_version 键必须仍存在（退役形态）");
  assert.ok(f.status === "unavailable" && f.value === null && f.source === "native/（已删除）",
    `退役形态失约: ${JSON.stringify(f)}`);
  assert.ok(f.how_to_get !== "", "退役键必须带 how_to_get 指引（历史值取回路径）");
});

// cargo --cargo-log 采集（M15 接线）：绿路径 + 日志缺失 unavailable。
test("cargo 日志解析绿路径与缺失形态", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "facts-cargolog-"));
  // 夹具对齐真实 cargo test 输出形态：套件行以 Running 开头且含
  // target\debug\deps\ 路径。
  const log = "Running unittests src\\lib.rs (target\\debug\\deps\\foo-abc123.exe)\n" +
    "test result: ok. 900 passed; 0 failed\n" +
    "Running tests\\fuzz_stress_test.rs (target\\debug\\deps\\bar-def456.exe)\n" +
    "test result: ok. 25 passed; 0 failed\n";
  fs.mkdirSync(path.join(root, "native"));
  fs.writeFileSync(path.join(root, "native", "cargo_test_ci.log"), log);
  let facts = factsOf();
  collectCargoTestFromLog(root, "native/cargo_test_ci.log", facts);
  assert.equal(facts["cargo_test_passed"]!.value, 925, `日志解析 900+25=925 失败: ${JSON.stringify(facts["cargo_test_passed"])}`);
  assert.equal(facts["cargo_test_suites"]!.value, 2, "套件计数解析失败");

  // 日志缺失必须 unavailable，禁止兜底
  facts = factsOf();
  collectCargoTestFromLog(root, "native/不存在的日志.log", facts);
  assert.equal(facts["cargo_test_passed"]!.status, "unavailable", "日志缺失必须 unavailable");
});

// B3（2026-11-13，issue #510 同期台账机制批）：moon check warning 台账键
// ——手册「余额 34 条」硬数字失真（master 实测 98，两轮评审各时点 80/98）
// 后的止涨机制：warning 计数入 facts，台账文档裸数字声明对账（涨=漂移红
// =须归因清点入台账）。
test("moonbit check warnings 绿路径（B3 台账机制）", () => {
  const facts = factsOf();
  // 真实形态样例：码行 + 块（块内助记行）+ Finished 尾
  collectMoonbitCheckWarningsFromOutput(
    "Warning: [0002]\n" +
      "     ╭─[ moonbit/wasmenc/assemble.mbt:12:3 ]\n" +
      "     │  ╰──── Warning (unused_value): Unused function 'f'\n" +
      "─────╯\n" +
      "Warning: [0020]\n" +
      "     ╭─[ moonbit/parser/expr.mbt:8:1 ]\n" +
      "     │  ╰──── Warning (deprecated): x is deprecated\n" +
      "─────╯\n" +
      "Finished. moon: ran 68 tasks (0 errors)",
    0, facts);
  const f = facts["moonbit_check_warnings"];
  assert.ok(f !== undefined && f.status === "ok" && f.value === 2,
    `warning 计数应为 2: ${JSON.stringify(f)}`);
});

test("moonbit check warnings J9 埋雷①：数字码行 Warning: [NNNN] 不双计", () => {
  // 实测踩坑：同一 warning 两行呈现（码行 + 块内助记行）——裸 grep 'Warning'
  // 双计（196 vs 真值 98）；计数只认助记形 `Warning (name)`
  const facts = factsOf();
  collectMoonbitCheckWarningsFromOutput(
    "Warning: [0002]\n" +
      "     ╭─[ moonbit/a.mbt:1:1 ]\n" +
      "     │  ╰──── Warning (unused_value): Unused variable 'v'\n" +
      "─────╯\n" +
      "Finished. moon: ran 1 tasks (0 errors)",
    0, facts);
  assert.ok(facts["moonbit_check_warnings"]?.value === 1,
    `码行+助记行 = 1 条非 2 条: ${JSON.stringify(facts["moonbit_check_warnings"])}`);
});

test("moonbit check warnings J9 埋雷②：无 Finished 行 unavailable（管道截断防护）", () => {
  // 工具陷阱 9 同族：SIGPIPE/截断杀输出——数出一半的计数是毒数字，不采
  const facts = factsOf();
  collectMoonbitCheckWarningsFromOutput(
    "Warning: [0002]\n     ╭─[ moonbit/a.mbt:1:1 ]\n     │  ╰──── Warning (unused_value): x\n─────╯",
    0, facts);
  assert.equal(facts["moonbit_check_warnings"]?.status, "unavailable",
    `无 Finished 行（截断形态）应 unavailable: ${JSON.stringify(facts["moonbit_check_warnings"])}`);
});

test("moonbit check warnings J9 埋雷③：check 失败（code≠0）不产真值", () => {
  const facts = factsOf();
  collectMoonbitCheckWarningsFromOutput(
    "Warning (unused_value): x\nFinished. moon: ran 1 tasks (1 errors)",
    1, facts);
  assert.equal(facts["moonbit_check_warnings"]?.status, "unavailable",
    "类型红的 check 输出计数不可比（非同口径面），须 unavailable");
});

test("moonbit check warnings 口径键在 RUN_KEYS 在册（B3）", () => {
  assert.ok(RUN_KEYS.includes("moonbit_check_warnings"),
    "moonbit_check_warnings 须登记 RUN_KEYS（cached 沿用语义）");
});
