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

// PR #518 审阅 P3-1 hermetic 回归锚：gitignored 豁免的 cwd 锚定——
// loadGitIgnored 的 git ls-files 输出相对 cwd 的路径，无 cwd 锚定时（修复前）
// 继承进程 cwd（CI 的 npm test 在 scripts/ 下跑），输出的是**本仓库**清单，
// 与 checkTree(base) 的 rel 前缀失配 → base 的 gitignored 面静默不豁免。
// 本锚 git init 独立 fixture：ignored/ 下放违规文件（缺末行换行）——修复前
// 红（fixture 的 gitignored 面漏豁免）、修复后绿（cwd 锚定 base，ls-files
// 输出 fixture 自己的清单）。干净 CI 检出无 cargo target 时旧缺陷不显红，
// 此锚是该修复的唯一回归防线。
test("gitignored 豁免须按 base 锚定（cwd≠base 不失配，PR #518 审阅 P3-1）", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-editorconfig-cwd-"));
  const gitInit = spawnSync("git", ["init", "-q"], { cwd: dir, encoding: "utf8" });
  if (gitInit.status !== 0) {
    // git 不可用环境（理论不存在——本仓闸全部依赖 git）：跳过即假绿，须红
    assert.fail("git init 失败，hermetic 锚无法成立: " + gitInit.stderr);
  }
  fs.writeFileSync(path.join(dir, ".gitignore"), "ignored/\n");
  fs.mkdirSync(path.join(dir, "ignored"), { recursive: true });
  fs.writeFileSync(path.join(dir, "ignored", "bad.txt"), "no final newline");
  fs.writeFileSync(path.join(dir, "ok.txt"), "ok\n");
  // 测试进程 cwd = scripts/（npm test 形态）≠ base（fixture）——正是失配形态
  assert.deepEqual(checkTree(dir), [], "fixture 的 gitignored 面须豁免（cwd 锚定 base）");
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
