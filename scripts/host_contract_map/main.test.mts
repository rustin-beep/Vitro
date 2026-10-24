// host_contract_map.test.mts —— 三态对账判定面（内存注入 + 真实仓库）。
import { test } from "node:test";
import assert from "node:assert/strict";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { judge, loadRules, mbAnchorNames, rustHostTestNames, selfTest } from "./main.mts";
import type { Mapping } from "./main.mts";
import { projectRoot } from "../internal/capi.mts";

const MAIN = path.join(import.meta.dirname, "main.mts");

function ok(rust: string[], mb: string[], maps: Mapping[]): { exit: number; text: string } {
  const r = judge(new Set(rust), new Set(mb), maps, false);
  return { exit: r.exit, text: r.lines.join("\n") };
}

test("绿：完整映射 + 侧自增锚（提示不判红）", () => {
  const r = ok(
    ["t1", "t2"],
    ["t1", "a2", "self_extra"],
    [
      { rust_test: "t1", state: "anchored", mb_anchors: ["t1"] },
      { rust_test: "t2", state: "merged", mb_anchors: ["a2"] },
    ],
  );
  assert.equal(r.exit, 0);
  assert.match(r.text, /oracle 契约 2 条：anchored\+merged 2 \/ missing 0；mb 锚 3 个（被引用 2 \/ 侧自增 1/);
  assert.match(r.text, /对账一致/);
});

test("J9 [HOLE]：oracle 有、表里无", () => {
  const r = ok(["t1", "t2"], ["t1"], [{ rust_test: "t1", state: "anchored", mb_anchors: ["t1"] }]);
  assert.equal(r.exit, 1);
  assert.match(r.text, /\[HOLE\] oracle 契约测试 1 条无映射：\[t2\]/);
});

test("J9 [GHOST]：表里有、oracle 无", () => {
  const r = ok(["t1"], ["t1", "x"], [
    { rust_test: "t1", state: "anchored", mb_anchors: ["t1"] },
    { rust_test: "gone", state: "merged", mb_anchors: ["x"] },
  ]);
  assert.equal(r.exit, 1);
  assert.match(r.text, /\[GHOST\] 表内条目指向不存在的 oracle 测试：\[gone\]/);
});

test("J9 [STALE]/[BAD]：陈旧锚与空锚列表", () => {
  const stale = ok(["t1"], [], [{ rust_test: "t1", state: "merged", mb_anchors: ["ghost"] }]);
  assert.equal(stale.exit, 1);
  assert.match(stale.text, /\[STALE\] t1 指向不存在的锚 "ghost"/);

  const empty = ok(["t1"], ["t1"], [{ rust_test: "t1", state: "merged", mb_anchors: [] }]);
  assert.equal(empty.exit, 1);
  assert.match(empty.text, /\[BAD\] t1 state=merged 但 mb_anchors 为空/);
});

test("J9 [CROSS]/[REUSE]/[DUP]：语义保险丝三路", () => {
  const cross = ok(["t1"], ["other"], [{ rust_test: "t1", state: "anchored", mb_anchors: ["other"] }]);
  assert.equal(cross.exit, 1);
  assert.match(cross.text, /\[CROSS\] t1 state=anchored 但锚名不对齐 \[other\]/);

  const reuse = ok(
    ["t1", "t2"],
    ["same"],
    [
      { rust_test: "t1", state: "merged", mb_anchors: ["same"] },
      // anchored 必须同名，才能走到 REUSE 计数；用 t1 的同名锚造复用
      { rust_test: "same", state: "anchored", mb_anchors: ["same"] },
      { rust_test: "same2", state: "anchored", mb_anchors: ["same"] },
    ],
  );
  assert.equal(reuse.exit, 1);
  assert.match(reuse.text, /\[REUSE\] 锚 "same" 被 2 条 anchored 复用/);

  const dup = ok(["t1"], ["t1"], [
    { rust_test: "t1", state: "anchored", mb_anchors: ["t1"] },
    { rust_test: "t1", state: "anchored", mb_anchors: ["t1"] },
  ]);
  assert.equal(dup.exit, 1);
  assert.match(dup.text, /\[DUP\] 表内重复条目 t1/);
});

test("missing：默认非红只打印；strict 判红（收官门）", () => {
  const maps: Mapping[] = [
    { rust_test: "t1", state: "anchored", mb_anchors: ["t1"] },
    { rust_test: "t2", state: "missing", mb_anchors: [] },
  ];
  const lenient = judge(new Set(["t1", "t2"]), new Set(["t1"]), maps, false);
  assert.equal(lenient.exit, 0);
  assert.match(lenient.lines.join("\n"), /\[TODO\] 缺失 1 条/);

  const strict = judge(new Set(["t1", "t2"]), new Set(["t1"]), maps, true);
  assert.equal(strict.exit, 1);
  assert.match(strict.lines.join("\n"), /strict：missing 非空判红（收官门）/);
});

test("真实仓库：名册 103 条 / 锚名非空 / 规则表合法（空集与非法 state 均 fail loud）", () => {
  assert.equal(rustHostTestNames().size, 103);
  assert.ok(mbAnchorNames().size > 100);
  const maps = loadRules();
  assert.equal(maps.length, 103);
  for (const m of maps) assert.ok(["anchored", "merged", "missing"].includes(m.state), m.rust_test);
});

test("真实仓库端到端：默认/strict/selftest 全绿；未知参数 exit 2", () => {
  const root = projectRoot();
  const run = (args: string[]): { status: number | null; out: string } => {
    const r = spawnSync(process.execPath, [MAIN, ...args], { cwd: root, encoding: "utf8" });
    return { status: r.status, out: (r.stdout ?? "") + (r.stderr ?? "") };
  };
  for (const args of [[], ["-strict"]]) {
    const r = run(args);
    assert.equal(r.status, 0, `${args.join(" ")}: ${r.out}`);
    assert.match(r.out, /对账一致（映射无洞 \/ 锚引用无陈旧）/);
  }
  assert.equal(selfTest(), 0);
  const self = run(["-selftest"]);
  assert.equal(self.status, 0, self.out);
  const bad = run(["--nope"]);
  assert.equal(bad.status, 2);
});
