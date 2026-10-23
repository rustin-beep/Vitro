// testcount.test.mts —— 声明解析与分解式算术自洽（不跑 moon test）。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { checkArithmetic, readDeclared } from "./main.mts";

function write(content: string): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-testcount-"));
  const p = path.join(dir, "README.md");
  fs.writeFileSync(p, content);
  return p;
}

const GOOD = [
  "# 857 测试（白盒 + 黑盒）",
  "分解和 800 + 根 README doc test 57",
  "native-only 包测试 100 个（fs 60 / gateway 20 / cli 20）",
  "`--target native` 全量 957",
].join("\n");

test("readDeclared：唯一声明解析；缺失/多行 fail loud", () => {
  assert.equal(readDeclared(write(GOOD)), 857);
  assert.throws(() => readDeclared(write("no declaration")), /未找到/);
  assert.throws(() => readDeclared(write("# 1 测试（\n# 2 测试（\n")), /不唯一/);
});

test("checkArithmetic：三组加法自洽", () => {
  assert.doesNotThrow(() => checkArithmetic(write(GOOD), 857));
});

test("checkArithmetic：任一处漏改即红（J9 三类）", () => {
  assert.throws(() => checkArithmetic(write(GOOD.replace("800 + 根", "799 + 根")), 857), /分解不自洽/);
  assert.throws(() => checkArithmetic(write(GOOD.replace("fs 60", "fs 59")), 857), /native-only 不自洽/);
  assert.throws(() => checkArithmetic(write(GOOD.replace("全量 957", "全量 956")), 857), /全量不自洽/);
});

test("checkArithmetic：锚行缺失/重复 fail loud", () => {
  assert.throws(() => checkArithmetic(write("# 857 测试（\n"), 857), /锚行数=0/);
  assert.throws(
    () => checkArithmetic(write(GOOD + "\n分解和 800 + 根 README doc test 57\n"), 857),
    /锚行数=2/
  );
});
