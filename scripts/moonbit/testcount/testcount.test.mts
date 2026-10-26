// testcount.test.mts —— 声明解析与分解式算术自洽（不跑 moon test）。
// #308 v3（2026-10-26）：双形态锚——旧分解式（GOOD_OLD）与新「裸数 +
// facts 键标注」（GOOD_NEW，巨型批注链退场形态）；分解式锚条件化
// （缺席跳过、在场算术自洽、多锚红）+ native 全量声明行强约束。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { checkArithmetic, readDeclared, readDeclaredNative } from "./main.mts";

function write(content: string): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-testcount-"));
  const p = path.join(dir, "README.md");
  fs.writeFileSync(p, content);
  return p;
}

const GOOD_OLD = [
  "# 857 测试（白盒 + 黑盒）",
  "分解和 800 + 根 README doc test 57",
  "native-only 包测试 100 个（fs 60 / gateway 20 / cli 20）",
  "`--target native` 全量 957",
].join("\n");

// #308 新形态（现行 README 行文——分解式退场，双键标注）
const GOOD_NEW = [
  "moon check && moon test    # 857 测试（裸口径，facts 键 moonbit_test_passed 机判，漂移即 CI 红；批注明细单源 CHANGELOG——#308）",
  "                           # moon test --target native 全量 957（CI 门禁口径，facts 键 moonbit_test_passed_native 机判；native-only 包〔fs/gateway/cli〕逐包分解以 moon test -p 为准）",
].join("\n");

test("readDeclared：唯一声明解析；缺失/多行 fail loud", () => {
  assert.equal(readDeclared(write(GOOD_OLD)), 857);
  assert.equal(readDeclared(write(GOOD_NEW)), 857);
  assert.throws(() => readDeclared(write("no declaration")), /未找到/);
  assert.throws(() => readDeclared(write("# 1 测试（\n# 2 测试（\n")), /不唯一/);
});

test("readDeclaredNative：两形态解析；缺失/多行 fail loud（#308 v3）", () => {
  assert.equal(readDeclaredNative(write(GOOD_OLD)), 957);
  assert.equal(readDeclaredNative(write(GOOD_NEW)), 957);
  assert.throws(() => readDeclaredNative(write("no decl")), /未找到/);
  assert.throws(
    () => readDeclaredNative(write(GOOD_NEW + "\n--target native 全量 1\n")),
    /不唯一/
  );
});

test("checkArithmetic：旧形态三组加法自洽", () => {
  assert.doesNotThrow(() => checkArithmetic(write(GOOD_OLD), 857));
});

test("checkArithmetic：新形态分解式缺席全跳过（#308 v3）", () => {
  assert.doesNotThrow(() => checkArithmetic(write(GOOD_NEW), 857));
});

test("checkArithmetic：任一处漏改即红（J9 三类，旧形态）", () => {
  assert.throws(() => checkArithmetic(write(GOOD_OLD.replace("800 + 根", "799 + 根")), 857), /分解不自洽/);
  assert.throws(() => checkArithmetic(write(GOOD_OLD.replace("fs 60", "fs 59")), 857), /native-only 不自洽/);
  assert.throws(() => checkArithmetic(write(GOOD_OLD.replace("全量 957", "全量 956")), 857), /全量不自洽/);
});

test("checkArithmetic：native 全量锚缺失/重复仍 fail loud（两形态共有强约束）", () => {
  assert.throws(() => checkArithmetic(write("# 857 测试（\n"), 857), /锚行数=0/);
  assert.throws(
    () => checkArithmetic(write(GOOD_OLD + "\n分解和 800 + 根 README doc test 57\n"), 857),
    /锚行数=2/
  );
  assert.throws(
    () => checkArithmetic(write(GOOD_NEW + "\n--target native 全量 957\n"), 857),
    /锚行数=2/
  );
});

test("checkArithmetic：分解式锚在场即查——错值红（非合法缺席——形态回潮/复制事故）", () => {
  // 新形态文档混入错值分解行：0 锚 + 1 行 = 锚在场，值不自洽即红
  assert.throws(
    () => checkArithmetic(write(GOOD_NEW + "\n分解和 800 + 根 README doc test 58\n"), 857),
    /分解不自洽/
  );
});
