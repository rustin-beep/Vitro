// wasmopt 执行器 CLI 契约（#273 四件套：node:test）——缺参 fail loud rc=4。
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import path from "node:path";

const script = path.join(import.meta.dirname, "wasmopt.mts");

test("缺参 → rc=4 且打印用法（禁静默 default）", () => {
  const r = spawnSync(process.execPath, [script], { encoding: "utf8" });
  assert.equal(r.status, 4);
  assert.match(r.stderr, /用法: node wasmopt\.mts/);
});
