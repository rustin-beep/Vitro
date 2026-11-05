// cast_matrix.test.mts —— 条件求值器 / 链抽取 / 对偶抽取纯函数 + 真实仓库判定 + J9 内存红路
import { test } from "node:test";
import assert from "node:assert/strict";
import path from "node:path";
import { spawnSync } from "node:child_process";
import {
  extractCastInstrs,
  extractChain,
  instrPair,
  loadRules,
  mustChain,
  normalizeCond,
  parsePred,
  verdict,
  zeroEmitOf,
  type Bindings,
} from "./main.mts";
import { projectRoot } from "../../internal/capi.mts";

const MAIN = path.join(import.meta.dirname, "main.mts");

const b = (T: string, S: string, S_u = false, T_u = false): Bindings => ({ T, S, S_u, T_u });

test("normalizeCond：孪生变量名差异归一（ik/ek→S、tk→T、u 旗标、target_is_fp 展开）", () => {
  assert.equal(normalizeCond("tk is TK_Double && ik is TK_Float"), "T is TK_Double && S is TK_Float");
  assert.equal(normalizeCond("tk is TK_Double && ek is TK_LongLong"), "T is TK_Double && S is TK_LongLong");
  assert.equal(normalizeCond("inner_u"), "SRC_U");
  assert.equal(normalizeCond("expr_u"), "SRC_U");
  assert.equal(normalizeCond("target_type.is_unsigned()"), "TGT_U");
  assert.equal(normalizeCond("target_ty.is_unsigned()"), "TGT_U");
  assert.equal(normalizeCond("!target_is_fp"), "!(T is TK_Float || T is TK_Double)");
});

test("parsePred：is / 否定 / 与或 / 旗标求值", () => {
  const p1 = parsePred("T is TK_LongLong && !(S is TK_LongLong) && !(S is TK_Float)");
  assert.equal(p1(b("LongLong", "Double")), true);
  assert.equal(p1(b("LongLong", "Float")), false); // F1 根源：Float 源被显式排除
  assert.equal(p1(b("LongLong", "Int")), true);
  const p2 = parsePred("SRC_U && (S is TK_Int || S is TK_Char)");
  assert.equal(p2(b("Double", "Int", true)), true);
  assert.equal(p2(b("Double", "Int", false)), false);
  const p3 = parsePred("!(T is TK_Float) && !(T is TK_Double) && S is TK_Double");
  assert.equal(p3(b("Int", "Double")), true);
  assert.equal(p3(b("Double", "Double")), false);
});

test("parsePred：未知语法零容忍（fail loud 而非静默跳过）", () => {
  assert.throws(() => parsePred("target_type.is_wide()"), /token 不认识|提前|主语/);
  assert.throws(() => parsePred("T matches TK_Int"), /token 不认识/);
});

test("extractChain：单行臂 / else-if 续臂 / 多行 && 续行", () => {
  const body = [
    "  if tk is TK_Void {",
    "    return",
    "  } else if tk is TK_Double && ik is TK_Float {",
    "    emit",
    "  } else if !(tk is TK_Float) &&",
    "    !(tk is TK_Double) &&",
    "    ik is TK_LongLong {",
    "    emit",
    "  }",
    "",
  ].join("\n");
  const { conds, error } = extractChain(body);
  assert.equal(error, undefined);
  assert.equal(conds.length, 3);
  assert.equal(conds[2], "!(tk is TK_Float) && !(tk is TK_Double) && ik is TK_LongLong"); // 多行 && 续行全拼
  const empty = extractChain("no if here");
  assert.match(empty.error ?? "", /未找到顶层 if/);
});

test("extractCastInstrs / instrPair", () => {
  const out = extractCastInstrs("  CastI2F\n  TruncByte\n  CastUQ2F\n  NotACast2X\n  CastQ2D => 96");
  assert.deepEqual(out, ["CastI2F", "CastUQ2F"]);
  assert.deepEqual(instrPair("CastUQ2F"), { from: "UQ", to: "F" });
  assert.equal(instrPair("TruncByte"), undefined);
});

test("真实仓库：单源链抽取非空、零发射全部在册、对偶无未登记缺口（verdict 绿）", () => {
  const rd = loadRules();
  const chains = rd.chain_sources.map((s) => mustChain(s));
  for (const c of chains) assert.ok(c.preds.length >= 10, `${c.name} 臂数 ${c.preds.length}`);
  // F1 已修锚（#471 2026-11-05）：LongLong|Float|s 经 CastF2D+CastD2Q/D2UQ 双跳发射，
  // 不再零发射；known_gaps 条目随清账删除
  for (const c of chains) {
    const zs = zeroEmitOf(c, rd.kinds).map((z) => z.key);
    assert.ok(!zs.includes("LongLong|Float|s"), `${c.name} F1 已修——LongLong|Float|s 应发射双跳`);
    assert.ok(rd.zero_emit_known_gaps[`${c.name}::LongLong|Float|s`] === undefined);
  }
  assert.equal(verdict(rd, chains), true);
});

test("J9 红：链删臂产生新零发射 / 白名单僵尸 / 对偶表删除（内存注入）", () => {
  const rd = loadRules();
  const chains = rd.chain_sources.map((s) => mustChain(s));
  // 删 LL←D/LL←F/LL←other 三臂 → emit_conversion 的 (LL,Int/Char/Pointer/D/F,s/u) 零发射未登记
  {
    const c2 = chains.map((c) => ({ ...c, preds: [...c.preds] }));
    const idx = c2[0]!.condTexts.findIndex((t) => t.includes("T is TK_LongLong"));
    c2[0]!.preds.splice(idx, 3); // LL 三臂同删（D/F/other——单源链 #471 起三分支）
    assert.equal(verdict(rd, c2), false);
  }
  // 白名单加实际已发射组合（僵尸）
  {
    const rd2 = JSON.parse(JSON.stringify(rd)) as typeof rd;
    rd2.zero_emit_allowed["emit_conversion::Double|LongLong|s"] = { reason: "僵尸探针" };
    assert.equal(verdict(rd2, chains), false);
  }
});

test("子进程：-check rc=0 / --selftest rc=0 / --discover rc=0 / 未知参数 rc=2", () => {
  const run = (args: string[]): number => {
    const r = spawnSync(process.execPath, [MAIN, ...args], { cwd: projectRoot() });
    return r.status ?? -1;
  };
  assert.equal(run(["-check"]), 0);
  assert.equal(run(["--selftest"]), 0);
  assert.equal(run(["--discover"]), 0);
  assert.equal(run(["--wat"]), 2);
});
