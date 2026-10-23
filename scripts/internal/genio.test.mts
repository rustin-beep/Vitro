// genio.test.mts —— 错误出口 / flag 解析 / moon-fmt 幂等（含零副作用与漂移证红）。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { emitWithMoonFmt, makeFail, parseFlags, type GenFail } from "./genio.mts";
import { projectRoot } from "./capi.mts";

const boom: GenFail = (msg: string): never => {
  throw new Error(msg);
};

/** 真实仓库里一个由 moon fmt 管着的产物（-check 零副作用测试用）。 */
const REAL_PRODUCT = "vm/libc_data_gen.mbt";

test("makeFail：工厂返回可调用出口（真正的前缀/码语义走子进程验证）", () => {
  assert.equal(typeof makeFail("x: ", 1), "function");
  assert.equal(typeof makeFail("y: "), "function");
  for (const c of [
    { prefix: "gen_stubs: ", code: 1 },
    { prefix: "FATAL: ", code: 2 },
  ]) {
    const script = `import { makeFail } from ${JSON.stringify(
      new URL("./genio.mts", import.meta.url).href,
    )}; makeFail(${JSON.stringify(c.prefix)}, ${c.code})("炸了");`;
    const r = spawnSync(process.execPath, ["--input-type=module", "-e", script], { encoding: "utf8" });
    assert.equal(r.status, c.code);
    assert.equal(r.stderr, `${c.prefix}炸了\n`);
  }
});

test("parseFlags：-k / -k=v / -k v 三形态", () => {
  const p = parseFlags(["-check", "-src=a.json", "-out", "b", "extra"], {
    bool: ["-check", "--check"],
    value: ["-src", "-out"],
  }, boom);
  assert.equal(p.has("-check", "--check"), true);
  assert.equal(p.has("--check"), false);
  assert.equal(p.value("-src"), "a.json");
  assert.equal(p.value("-out"), "b");
  assert.deepEqual(p.rest, ["extra"]);
});

test("parseFlags：缺值 / 布尔带值 fail loud（不静默忽略）", () => {
  assert.throws(
    () => parseFlags(["-src"], { bool: [], value: ["-src"] }, boom),
    /-src 缺值/,
  );
  assert.throws(
    () => parseFlags(["-check=1"], { bool: ["-check"], value: [] }, boom),
    /布尔 flag -check 不接受值/,
  );
});

test("parseFlags：未知参数进 rest 而非静默丢弃", () => {
  const p = parseFlags(["-nope", "x"], { bool: [], value: [] }, boom);
  assert.deepEqual(p.rest, ["-nope", "x"]);
});

test("emitWithMoonFmt：内容与磁盘一致时 -check 通过且零副作用", () => {
  const root = projectRoot();
  const abs = path.join(root, "moonbit", REAL_PRODUCT);
  const before = fs.readFileSync(abs);
  emitWithMoonFmt({
    root,
    check: true,
    fail: boom,
    driftHint: "test",
    products: [{ rel: REAL_PRODUCT, content: before.toString("utf8") }],
  });
  assert.ok(fs.readFileSync(abs).equals(before), "check 模式必须逐字节还原");
});

test("emitWithMoonFmt：内容漂移即红，且磁盘复原（无副作用）", () => {
  const root = projectRoot();
  const abs = path.join(root, "moonbit", REAL_PRODUCT);
  const before = fs.readFileSync(abs);
  // 漂移判据 = **经 moon fmt 归一后**仍不同：所以纯空白差异会被 fmt 修掉，
  // 测试必须用 fmt 保留的差异（附注一行注释）。
  assert.throws(
    () =>
      emitWithMoonFmt({
        root,
        check: true,
        fail: boom,
        driftHint: "test",
        products: [{ rel: REAL_PRODUCT, content: before.toString("utf8") + "// __probe_drift\n" }],
      }),
    /产物漂移/,
  );
  assert.ok(fs.readFileSync(abs).equals(before), "漂移红之后也必须还原原产物");
});

test("emitWithMoonFmt：纯空白差异被 fmt 归一秒平（不算漂移）", () => {
  const root = projectRoot();
  const abs = path.join(root, "moonbit", REAL_PRODUCT);
  const before = fs.readFileSync(abs);
  emitWithMoonFmt({
    root,
    check: true,
    fail: boom,
    driftHint: "test",
    products: [{ rel: REAL_PRODUCT, content: before.toString("utf8").replace("pub fn", "pub  fn") }],
  });
  assert.ok(fs.readFileSync(abs).equals(before));
});

test("emitWithMoonFmt：-check 遇产物缺失即红，且不得把新产物留在盘上", () => {
  const root = projectRoot();
  const abs = path.join(root, "moonbit", REAL_PRODUCT);
  const before = fs.readFileSync(abs);
  fs.rmSync(abs);
  try {
    assert.throws(
      () =>
        emitWithMoonFmt({
          root,
          check: true,
          fail: boom,
          driftHint: "test",
          products: [{ rel: REAL_PRODUCT, content: before.toString("utf8") }],
        }),
      /产物漂移/,
    );
    assert.equal(fs.existsSync(abs), false, "check 零副作用：原本不存在的产物必须删掉");
  } finally {
    if (!fs.existsSync(abs)) fs.writeFileSync(abs, before);
  }
});

test("emitWithMoonFmt：CRLF 差异不算漂移（LF 归一后比对）", () => {
  const root = projectRoot();
  const abs = path.join(root, "moonbit", REAL_PRODUCT);
  const before = fs.readFileSync(abs);
  const crlf = before.toString("utf8").replace(/\n/g, "\r\n");
  emitWithMoonFmt({
    root,
    check: true,
    fail: boom,
    driftHint: "test",
    products: [{ rel: REAL_PRODUCT, content: crlf }],
  });
  assert.ok(fs.readFileSync(abs).equals(before));
});
