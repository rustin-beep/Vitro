// mbti_sync.test.mts —— 快照 diff / 完备性断言（fixture）+ 真实三模式
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { MBTI_EXEMPT, diffSnapshots, isEmpty, mbtiCompleteness, total } from "./main.mts";
import { projectRoot } from "../../internal/capi.mts";

const MAIN = path.join(import.meta.dirname, "main.mts");

test("diffSnapshots：added / removed / changed 三类 + 排序", () => {
  const before = new Map([["a", "1"], ["b", "2"], ["z", "9"]]);
  const after = new Map([["a", "1"], ["b", "3"], ["c", "4"]]);
  const d = diffSnapshots(before, after);
  assert.deepEqual(d.added, ["c"]);
  assert.deepEqual(d.removed, ["z"]);
  assert.deepEqual(d.changed, ["b"]);
  assert.equal(total(d), 3);
  assert.equal(isEmpty(d), false);
  assert.equal(isEmpty(diffSnapshots(before, before)), true);
});

function tmpTree(files: Record<string, string>): string {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-mbti-"));
  for (const [rel, body] of Object.entries(files)) {
    fs.mkdirSync(path.dirname(path.join(root, rel)), { recursive: true });
    fs.writeFileSync(path.join(root, rel), body);
  }
  return root;
}

test("mbtiCompleteness：缺 .mbti 必报；executable / foreign_library / 豁免表放行", () => {
  const root = tmpTree({
    "moonbit/ok/moon.pkg": 'pkgtype(kind: "library")\n',
    "moonbit/ok/pkg.generated.mbti": "x\n",
    "moonbit/missing/moon.pkg": 'pkgtype(kind: "library")\n',
    "moonbit/exec/moon.pkg": 'pkgtype(kind: "executable")\n',
    "moonbit/foreign/moon.pkg": 'pkgtype(kind: "foreign_library")\n',
    "moonbit/gateway/moon.pkg": 'pkgtype(kind: "library")\n',
  });
  const exempt = new Map<string, string>([["vitro/engine/gateway", "test exempt"]]);
  const missing = mbtiCompleteness(root, exempt);
  assert.deepEqual(missing, ["vitro/engine/missing（moon.pkg 无 .mbti 且不在豁免表）"]);
});

test("MBTI_EXEMPT：三条 #43 豁免且理由非空", () => {
  assert.equal(MBTI_EXEMPT.size, 3);
  for (const [k, v] of MBTI_EXEMPT) {
    assert.match(k, /^vitro\/engine\//);
    assert.ok(v.length > 20, `${k} 理由过短`);
  }
});

test("真实仓库端到端：默认 / -check / --selftest 全绿且不污染工作区；未知参数 exit 2", () => {
  const root = projectRoot();
  const dirty0 = spawnSync("git", ["status", "--porcelain", "moonbit/"], { cwd: root, encoding: "utf8" }).stdout ?? "";
  for (const args of [[], ["-check"], ["--selftest"]]) {
    const r = spawnSync(process.execPath, [MAIN, ...args], { cwd: root, encoding: "utf8" });
    assert.equal(r.status, 0, `${args.join(" ") || "(默认)"}: ${r.stdout}${r.stderr}`);
  }
  const dirty1 = spawnSync("git", ["status", "--porcelain", "moonbit/"], { cwd: root, encoding: "utf8" }).stdout ?? "";
  assert.equal(dirty1, dirty0, "跑完不得留下 .mbti 改动（自愈型脚本的恢复义务）");
  assert.equal(spawnSync(process.execPath, [MAIN, "--nope"], { cwd: root, encoding: "utf8" }).status, 2);
});
