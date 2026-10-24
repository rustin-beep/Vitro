// capi.test.mts —— 仓库根定位、按码点截断、目录遍历口径契约。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { projectRoot, truncateRunes, walkDirSorted } from "./capi.mts";

test("projectRoot 从 scripts/ 上溯定位仓库根", () => {
  const root = projectRoot();
  assert.ok(fs.statSync(path.join(root, "corpus")).isDirectory());
  assert.ok(fs.statSync(path.join(root, "scripts")).isDirectory());
});

test("truncateRunes 按码点截断（CJK/emoji 各算 1 字符）", () => {
  assert.equal(truncateRunes("中文😀abc", 3), "中文😀");
  assert.equal(truncateRunes("中文😀abc", 10), "中文😀abc");
  assert.equal(truncateRunes("", 3), "");
});

test("walkDirSorted：同层按字节序（不是 UTF-16 序），目录先下钻由 visit 决定", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "capi-walk-"));
  fs.mkdirSync(path.join(dir, "sub"), { recursive: true });
  // 一对能区分两种口径的文件名：U+FF5E（UTF-8 EF BD 9E）vs U+10000（UTF-8 F0 90 80 80,
  // UTF-16 却在 D800 代理区）——字节序 FF5E 先，UTF-16 序 astral 先（Go 是前者）。
  for (const name of ["b.txt", "a.txt", "sub/c.txt", "\uFF5E.txt", "\u{10000}.txt"]) {
    fs.writeFileSync(path.join(dir, name), "");
  }
  const seen: string[] = [];
  walkDirSorted(dir, (_full, name, isDir) => {
    seen.push(isDir ? name + "/" : name);
  });
  assert.deepEqual(seen, ["a.txt", "b.txt", "sub/", "c.txt", "\uFF5E.txt", "\u{10000}.txt"]);
});

test("walkDirSorted：visit 返回 skip 即不下钻", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "capi-walk2-"));
  fs.mkdirSync(path.join(dir, "data"), { recursive: true });
  fs.mkdirSync(path.join(dir, "src"), { recursive: true });
  fs.writeFileSync(path.join(dir, "data", "gen.ts"), "");
  fs.writeFileSync(path.join(dir, "src", "keep.ts"), "");
  const seen: string[] = [];
  walkDirSorted(dir, (full, name, isDir) => {
    if (isDir) return name === "data" ? "skip" : undefined;
    seen.push(name);
    return undefined;
  });
  assert.deepEqual(seen, ["keep.ts"]);
});
