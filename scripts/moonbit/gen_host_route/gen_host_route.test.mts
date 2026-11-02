// gen_host_route.test.mts —— 三抽取面解析/基线/渲染形态 + 真实 -check。
import { test } from "node:test";
import assert from "node:assert/strict";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { parseSource, renderAnchor, renderImpl } from "./main.mts";
import type { Baselines } from "./main.mts";
import { projectRoot } from "../../internal/capi.mts";

const BASE: Baselines = { expected_consts: 2, expected_pairs: 3, expected_pure: 2 };

const SRC = [
  "pub const FOO: u32 = 7;",
  "pub const BAR: u32 = 9;",
  "match name {",
  '  "a" | "b" => Some(FOO),',
  '  "c" => Some(BAR),',
  "  _ => None,",
  "}",
  'const BYTECODE_LIBC_PURE_FUNCS: &[&str] = &["a", "c"];',
].join("\n");

test("parseSource：常量/名对/PURE 三面计数与引用校验", () => {
  const p = parseSource(SRC, BASE);
  assert.deepEqual(p.consts, [["FOO", "7"], ["BAR", "9"]]);
  assert.deepEqual(p.pairs, [["a", "FOO"], ["b", "FOO"], ["c", "BAR"]]);
  assert.deepEqual(p.pure, ["a", "c"]);
  assert.throws(() => parseSource(SRC, { ...BASE, expected_consts: 3 }), /常量数/);
  assert.throws(() => parseSource(SRC, { ...BASE, expected_pairs: 4 }), /名→常量对数/);
  assert.throws(() => parseSource(SRC, { ...BASE, expected_pure: 3 }), /PURE 名数/);
  assert.throws(() => parseSource(SRC.replace("Some(BAR)", "Some(BAZ)"), BASE), /引用未定义常量 BAZ/);
});

test("renderImpl/renderAnchor：常量/对/纯名/锚排除 PURE 的形态", () => {
  const p = parseSource(SRC, BASE);
  const impl = renderImpl(p, "deadbeef");
  assert.match(impl, /sha256\/deadbeef/);
  assert.match(impl, /const HOST_FOO : Int = 7\nconst HOST_BAR : Int = 9/);
  assert.match(impl, /    \("a", HOST_FOO\),\n    \("b", HOST_FOO\),\n    \("c", HOST_BAR\),/);
  assert.match(impl, /let bytecode_libc_pure_funcs : Array\[String\] = \[\n    "a", "c"\n\]/);
  // 审阅 v2 批 A2 / M15 B-1：PURE 计数改动态（夹具 2 名），实现头注同步
  assert.match(impl, /对 2 个 PURE 名\*\*短路返回 None\*\*/);
  const anchor = renderAnchor(p, "deadbeef");
  // 锚头注措辞：全表 N 对 = (N−PURE) 非 PURE 断 Some(id) + PURE 断 None（原「N 对逐条断言 Some(id)」与锚体 101/13 分断不符）
  assert.match(anchor, /全表 3 = 1 非 PURE 名断 Some\(id\) \+ 2 PURE 名断 None（两组循环：/);
  // PR #415 审阅处置 C8：Go 版再生成命令已退役（#273 ts 迁移），头注须指 node 直跑
  assert.match(anchor, /再生成：仓库根 node scripts\/moonbit\/gen_host_route\/main\.mts）/);
  assert.doesNotMatch(anchor, /go run/);
  assert.match(anchor, /        \("b", 7\),/);
  assert.doesNotMatch(anchor, /        \("a", 7\),/);
});

test("真实仓库：-check 通过（与 CI 同门径）", () => {
  const r = spawnSync(process.execPath, [path.join(import.meta.dirname, "main.mts"), "-check"], {
    cwd: projectRoot(),
    encoding: "utf8",
  });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /gen_host_route: check OK/);
});
