// wasmopt.test.mts —— 解包口径 + 参数面 + 优化/-check 端到端（.mts 重写批）。
//
// 对拍口径：-check 路径与 Go 版逐字同形（parity 覆盖）；优化路径的收尾行含耗时，
// 不进对拍——其等价性由「同输入两侧各优化一次、产物 digest 与字节逐位相同」
// 的一次性证据背书（1MB gateway 产物与 8B 极小 wasm 各一组，均 digest 相同）。
// gzip 列走 zlib 口径（Go 用 compress/flate），数值可能差一两字节——报告面非判定面。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import zlib from "node:zlib";
import crypto from "node:crypto";
import { spawnSync } from "node:child_process";
import { projectRoot } from "../internal/capi.mts";
import { extractTarGz, gzipSize, parseArgs } from "./main.mts";

const MAIN = path.join(import.meta.dirname, "main.mts");
const CACHE_ENTRY = path.join(projectRoot(), "tools", "cache", "binaryen-132.0.0", "package", "index.js");
const supplyReady = fs.existsSync(CACHE_ENTRY);

/** 手搓 tar 头（512B）——只填解包器读的字段。 */
function tarHeader(name: string, size: number, typeflag: string): Buffer {
  const h = Buffer.alloc(512, 0);
  h.write(name, 0, 100, "utf8");
  h.write(size.toString(8).padStart(11, "0") + "\0", 124, 12, "utf8");
  h.write(typeflag, 156, 1, "utf8");
  h.write("ustar\0", 257, 6, "utf8");
  return h;
}

function tarEntry(name: string, body: Buffer, typeflag = "0"): Buffer {
  const padded = Buffer.alloc(Math.ceil(body.length / 512) * 512, 0);
  body.copy(padded);
  return Buffer.concat([tarHeader(name, body.length, typeflag), padded]);
}

test("extractTarGz：目录 + 普通文件按名落盘（等价 Go archive/tar 子集）", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "wo-tar-"));
  const body = Buffer.from("console.log(1)\n");
  const tgz = zlib.gzipSync(
    Buffer.concat([
      tarHeader("package", 0, "5"),
      tarEntry("package/index.js", body),
      tarEntry("package/bin/cli.js", Buffer.from("#!/usr/bin/env node\n")),
      Buffer.alloc(1024, 0),
    ]),
  );
  extractTarGz(tgz, dir);
  assert.equal(fs.readFileSync(path.join(dir, "package", "index.js"), "utf8"), body.toString("utf8"));
  assert.ok(fs.existsSync(path.join(dir, "package", "bin", "cli.js")), "子目录自动建");
});

test("extractTarGz：路径穿越条目即拒（fail loud，不写出 dest 之外）", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "wo-tar2-"));
  const evil = zlib.gzipSync(Buffer.concat([tarEntry("package/../../evil.txt", Buffer.from("x")), Buffer.alloc(1024, 0)]));
  assert.throws(() => extractTarGz(evil, dir), /路径越界/);
  assert.ok(!fs.existsSync(path.join(dir, "..", "evil.txt")), "不得逃逸到 dest 之外");
});

test("extractTarGz：GNU long name（'L'）覆盖下一条目录名", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "wo-tar3-"));
  const longName = "package/" + "a".repeat(120) + ".js";
  const tgz = zlib.gzipSync(
    Buffer.concat([tarEntry("././@LongLink", Buffer.from(longName + "\0"), "L"), tarEntry("package/short.js", Buffer.from("ok")), Buffer.alloc(1024, 0)]),
  );
  extractTarGz(tgz, dir);
  assert.ok(fs.existsSync(path.join(dir, longName.split("/").join(path.sep))), "长名条目落在 L 记录的名字上");
});

test("gzipSize：zlib level 9 口径（与自身实现同源，非 Go compress/flate）", () => {
  const b = Buffer.from("hello world hello world");
  assert.equal(gzipSize(b), zlib.gzipSync(b, { level: 9 }).length);
  assert.ok(gzipSize(Buffer.alloc(0)) > 0, "空输入仍有 gzip 头尾");
});

test("parseArgs：缺位置参数 / 未知旗标 → die（exit 1 语义）", () => {
  assert.throws(() => parseArgs([]), (e: unknown) => (e as { code?: number }).code === 1);
  assert.throws(() => parseArgs(["-nope", "x.wasm"]), (e: unknown) => (e as { code?: number }).code === 1);
  assert.deepEqual(parseArgs(["-check", "a.wasm"]), { check: true, target: "a.wasm" });
  assert.deepEqual(parseArgs(["a.wasm"]), { check: false, target: "a.wasm" });
});

function cli(args: string[]): { out: string; err: string; rc: number } {
  const r = spawnSync(process.execPath, [MAIN, ...args], { cwd: projectRoot(), encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  return { out: r.stdout ?? "", err: r.stderr ?? "", rc: r.status ?? -1 };
}

test("e2e：无 sidecar 的 -check 报红 exit 1（产物从未经本驱动优化）", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "wo-e2e-"));
  const wasm = path.join(dir, "plain.wasm");
  fs.writeFileSync(wasm, Buffer.from([0x00, 0x61, 0x73, 0x6d, 1, 0, 0, 0]));
  if (!supplyReady) {
    // 冷缓存会先下载（联网）——本用例只在缓存就绪时验文案
    return;
  }
  const r = cli(["-check", wasm]);
  assert.equal(r.rc, 1);
  assert.match(r.err, /\[wasmopt\] FAIL: -check 无 sidecar（.+plain\.wasm\.wasmopt\.sha256）——产物从未经本驱动优化/);
});

test("e2e：极小 wasm 优化两跑确定 → sidecar 落盘 → -check 转绿（缺 binaryen 缓存显式 skip）", (t) => {
  if (!supplyReady) {
    t.diagnostic("skip：tools/cache 缺 binaryen-132.0.0（冷缓存需联网下载 23MB）");
    return;
  }
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "wo-opt-"));
  const wasm = path.join(dir, "mini.wasm");
  const bytes = Buffer.from([0x00, 0x61, 0x73, 0x6d, 1, 0, 0, 0]);
  fs.writeFileSync(wasm, bytes);

  const opt = cli([wasm]);
  assert.equal(opt.rc, 0, opt.out + opt.err);
  assert.match(opt.out, /\[wasmopt\] mini\.wasm: 8 -> 8 B（gzip \d+ -> \d+ B，-0\.0%）耗时 /);

  const digest = crypto.createHash("sha256").update(fs.readFileSync(wasm)).digest("hex");
  assert.equal(fs.readFileSync(wasm + ".wasmopt.sha256", "utf8").trim(), digest, "sidecar = 落盘产物 digest");
  assert.ok(!fs.existsSync(wasm + ".opt1.tmp") && !fs.existsSync(wasm + ".opt2.tmp"), "临时产物已清");

  const chk = cli(["-check", wasm]);
  assert.equal(chk.rc, 0, chk.err);
  assert.match(chk.out, new RegExp(`\\[wasmopt\\] check OK：产物为优化终态（${digest.slice(0, 12)}）`));

  // 二次优化：命中 sidecar → 跳过（幂等，不重跑 binaryen）
  const again = cli([wasm]);
  assert.equal(again.rc, 0);
  assert.match(again.out, /产物已是优化终态（.+），跳过/);
});
