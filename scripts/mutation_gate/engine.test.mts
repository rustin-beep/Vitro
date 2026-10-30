// engine.mts 单测（四件套 node:test 面）——算子枚举/字符串与注释遮蔽/整数字面
// 量/应用与还原/白名单匹配/diff 解析。端到端 J9（#369/#370/M4/M6 重放四向）
// 是人工流程（须真跑 moon test + digest），记录见 #368。
import test from "node:test";
import assert from "node:assert/strict";
import {
  findTokenOccurrences,
  codePart,
  isInsideString,
  findIntLiteralMutants,
  generateMutants,
  applyMutant,
  isWhitelisted,
  parseEngineDiff,
  type Mutant,
  type EquivEntry,
} from "./engine.mts";

test("codePart：字符串内的 // 不剥、字符串外 // 起剥（不改前缀长度）", () => {
  assert.equal(codePart('let s = "http://x"; let a = 1; // tail'), 'let s = "http://x"; let a = 1; ');
  assert.equal(codePart('let s = "a\\"b"; f()'), 'let s = "a\\"b"; f()');
  assert.equal(codePart("// 全注释行"), "");
});

test("isInsideString：引号内 true、转义引号不闭合", () => {
  assert.equal(isInsideString('f("ab', 3), true);
  assert.equal(isInsideString('f("a") ', 6), false);
  assert.equal(isInsideString('"a\\"b"', 4), true); // 转义引号仍在串内
});

test("findTokenOccurrences：==/</&& 的裸 token 位置（跳过字符串、<=/<</<=/标识符粘连）", () => {
  assert.deepEqual(findTokenOccurrences("if a == b && c < d {", "=="), [6]);
  assert.deepEqual(findTokenOccurrences("if a == b && c < d {", "&&"), [11]);
  assert.deepEqual(findTokenOccurrences("if a == b && c < d {", "<"), [16]);
  assert.deepEqual(findTokenOccurrences("x <<= 2; y <= 3; z < 4;", "<"), [20]); // 只命中裸 <
  assert.deepEqual(findTokenOccurrences('f(a, "== &&") x == y', "=="), [17]);
  assert.deepEqual(findTokenOccurrences("identifier_true_x", "true"), []);
});

test("findIntLiteralMutants：±1、跳过字符串与 0x 与小数", () => {
  const got = findIntLiteralMutants('let n = 3001; let s = "99"; let h = 0xFF; let f = 1.5;');
  assert.deepEqual(got.map((g) => g.from + ">" + g.to), ["3001>3002", "1>2"]); // 1.5 的整部突变是合法算子
});

test("generateMutants+applyMutant：确定性生成与单点应用还原", () => {
  const lines = ["fn f() -> Bool {", "  return a == 1 && flag;", "}"];
  const mutants = generateMutants(lines, new Set([2]), "pkg/x.mbt");
  // 第 2 行：== 、&& 、true/false 无、整数 1 → 至少 3 个
  assert.ok(mutants.length >= 3, "mutants=" + mutants.length);
  const eq = mutants.find((m) => m.op === "EQ_TO_NEQ");
  assert.ok(eq !== undefined);
  const mutated = applyMutant(lines, eq as Mutant);
  assert.equal((mutated[1] ?? "").includes("!="), true);
  assert.equal((lines[1] ?? "").includes("=="), true); // 原数组不动
  // 应用 &&→|| 的可还原性
  const and = mutants.find((m) => m.op === "AND_TO_OR");
  if (and !== undefined) {
    const m2 = applyMutant(lines, and);
    assert.equal((m2[1] ?? "").includes("||"), true);
  }
});

test("isWhitelisted：file+op+行号±2 匹配、pair 字段保留", () => {
  const wl: EquivEntry[] = [
    { file: "typeck/expr.mbt", op: "OR_TO_AND", line: 249, reason: "双保险守卫侧（耦合对：建表侧 LT_TO_LE 见 pair）", pair: "typeck/typeck.mbt:382 建表侧同删才变行为" },
  ];
  const mu: Mutant = { file: "typeck/expr.mbt", line: 250, col: 10, from: "&&", to: "||", op: "OR_TO_AND" };
  assert.ok(isWhitelisted(mu, wl) !== null);
  const far: Mutant = { ...mu, line: 260 };
  assert.equal(isWhitelisted(far, wl), null);
  const otherFile: Mutant = { ...mu, file: "typeck/decl.mbt" };
  assert.equal(isWhitelisted(otherFile, wl), null);
});

test("parseEngineDiff：moonbit/<pkg>/ 路径重定基 + wbtest 剔除由上层、行号集含端点", () => {
  const diff = [
    "diff --git a/moonbit/typeck/expr.mbt b/moonbit/typeck/expr.mbt",
    "--- a/moonbit/typeck/expr.mbt",
    "+++ b/moonbit/typeck/expr.mbt",
    "@@ -240,2 +249,3 @@",
    "+new line",
    "+another",
    "+third",
    "diff --git a/moonbit/typeck/const_fold_wbtest.mbt b/moonbit/typeck/const_fold_wbtest.mbt",
    "--- a/moonbit/typeck/const_fold_wbtest.mbt",
    "+++ b/moonbit/typeck/const_fold_wbtest.mbt",
    "@@ -1 +2 @@",
    "+t",
  ].join("\n");
  const got = parseEngineDiff(diff);
  assert.equal(got.length, 1); // wbtest 在 parse 层剔除、路径剥 moonbit/ 前缀（防 join 双层）
  const expr = got.find((g) => g.file === "typeck/expr.mbt");
  assert.deepEqual([...(expr?.changed ?? [])].sort((a, b) => a - b), [249, 250, 251]);
});
