// capi.test.mts —— 仓库根定位与按码点截断契约。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { projectRoot, truncateRunes } from "./capi.mts";

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
