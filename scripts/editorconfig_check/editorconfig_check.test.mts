// editorconfig_check.test.mts —— 真实仓库 PASS + J9 注入五类违规。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { checkTree, jsonIndentCheck } from "./main.mts";
import { projectRoot } from "../internal/capi.mts";

test("真实仓库：全仓合规（与 pre-commit/CI 同门径）", () => {
  assert.deepEqual(checkTree(projectRoot()), []);
});

test("jsonIndentCheck：2 空格倍数合规，奇数缩进点名行号", () => {
  assert.equal(jsonIndentCheck(Buffer.from('{\n  "a": 1\n}\n')), "");
  assert.equal(jsonIndentCheck(Buffer.from('{\n "a": 1\n}\n')), "第 2 行缩进 1（非 2 的倍数）");
});

test("J9：非 UTF-8 / lone CR / 缺末行换行 / JSON 缩进 逐类命中；豁免面不误报", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-editorconfig-"));
  const w = (rel: string, data: Buffer | string): void => {
    const p = path.join(dir, rel);
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(p, data);
  };
  w("bad-utf8.txt", Buffer.from([0xff, 0x0a]));
  w("lone-cr.txt", Buffer.from("a\rb\n"));
  w("no-final.txt", "abc");
  w("odd.json", '{\n "a": 1\n}\n');
  w("ok-crlf.txt", "a\r\nb\r\n");
  w("ok.json", '{\n  "a": 1\n}\n');
  w("gen.txt", "@generated\nno final newline");
  w("bin.dat", Buffer.from([0x61, 0x00, 0x62]));
  w("dist/skip.txt", "no newline");
  w("sub/ok.txt", "ok\n");

  const offenders = checkTree(dir);
  assert.ok(offenders.some((o) => o.includes("bad-utf8.txt") && o.includes("非 UTF-8")));
  assert.ok(offenders.some((o) => o.includes("lone-cr.txt") && o.includes("lone CR")));
  assert.ok(offenders.some((o) => o.includes("no-final.txt") && o.includes("缺末行换行")));
  assert.ok(offenders.some((o) => o.includes("odd.json") && o.includes("第 2 行缩进 1")));
  assert.equal(offenders.length, 4, offenders.join("\n"));
});

test("嵌套 git worktree 整树跳过（独立仓库不入本仓扫描域）", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-editorconfig-wt-"));
  const w = (rel: string, data: string): void => {
    const p = path.join(dir, rel);
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(p, data);
  };
  w("ok.txt", "ok\n");
  w("nested/.git", "gitdir: /somewhere/else\n");
  w("nested/bad.txt", "no final newline");
  assert.deepEqual(checkTree(dir), [], "嵌套 worktree 内的违规不应计入本仓");
});

test("CLI -root：违规 exit 1 且打印 FAIL", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-editorconfig-cli-"));
  fs.writeFileSync(path.join(dir, "x.txt"), "abc");
  const r = spawnSync(process.execPath, [path.join(import.meta.dirname, "main.mts"), "-root", dir], {
    encoding: "utf8",
  });
  assert.equal(r.status, 1);
  assert.match(r.stdout, /editorconfig_check: FAIL——1 处违反/);
});
