// protocol_frames.test.mts —— 帧管线 / 基线判定 / 真实端到端（需 native serve 产物）
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { diffAgainstBase, loadRules, readBaseline, requestTable, writeBaseline } from "./main.mts";
import { projectRoot } from "../internal/capi.mts";

const MAIN = path.join(import.meta.dirname, "main.mts");
const HAS_SERVE = ((): boolean => {
  const exe = path.join(projectRoot(), "moonbit/_build/native/debug/build/cmd/serve", process.platform === "win32" ? "serve.exe" : "serve");
  return fs.existsSync(exe);
})();

test("requestTable：48 帧、id 连续且方法族覆盖 compile/run/step/dump/leak/icons", () => {
  const t = requestTable();
  assert.equal(t.length, 48);
  t.forEach((r, i) => assert.equal(r.id, i + 1, `帧 ${i + 1} id 不连续`));
  const methods = new Set(t.map((r) => r.method));
  for (const m of ["compile", "run", "step.next", "ast.dump", "output.delta", "icons.get", "session.reset"]) {
    assert.ok(methods.has(m), `缺方法 ${m}`);
  }
});

test("diffAgainstBase：篡改必 DRIFT / 一致零产出 / 帧数不等即一条", () => {
  const tbl = requestTable().slice(0, 3);
  assert.equal(diffAgainstBase("selftest", [`{"a":1}`, `{"b":2}`], [`{"a":1}`, `{"b":2}`], tbl).length, 0);
  const d = diffAgainstBase("selftest", [`{"a":1}`, `{"b":2}`], [`{"a":1}`, `{"b":9}`], tbl);
  assert.equal(d.length, 1);
  assert.match(d[0]!, /\[DRIFT\] selftest 帧 2/);
  assert.equal(diffAgainstBase("selftest", [], [`{"a":1}`], tbl).length, 1);
});

test("基线读写往返（临时目录）", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-pf-"));
  const root = dir;
  fs.mkdirSync(path.join(root, "scripts/protocol_frames"), { recursive: true });
  writeBaseline(root, [`{"a":1}`, `{"b":2}`, "", `{"c":3}`]);
  assert.deepEqual(readBaseline(root), [`{"a":1}`, `{"b":2}`, `{"c":3}`]);
});

test("真实仓库端到端：默认与 --selftest 全绿（缺 serve 产物则显式 skip）", (t) => {
  if (!HAS_SERVE) {
    t.skip("缺 moonbit/_build/native/debug/build/cmd/serve/serve.exe——该路径覆盖归 CI 的 serve 产物链");
    return;
  }
  const root = projectRoot();
  for (const args of [[], ["--selftest"]]) {
    const r = spawnSync(process.execPath, [MAIN, ...args], { cwd: root, encoding: "utf8", timeout: 200_000 });
    assert.equal(r.status, 0, `${args.join(" ") || "(默认)"}: ${r.stdout}${r.stderr}`);
  }
  assert.equal(spawnSync(process.execPath, [MAIN, "--nope"], { cwd: root, encoding: "utf8" }).status, 2);
});
