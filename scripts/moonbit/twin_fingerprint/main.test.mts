// twin_fingerprint.test.mts —— 链块抽取 / 德摩根归一 / dump 谓词 / 差集 + 真实仓库判定 + J9 内存红路
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import {
  allFingerprints,
  castChainFingerprint,
  demorganNorm,
  diffOf,
  extractChainBlocks,
  loadRules,
  verdict,
  dumpGuardsFingerprint,
} from "./main.mts";
import { projectRoot } from "../../internal/capi.mts";

const MAIN = path.join(import.meta.dirname, "main.mts");

test("demorganNorm：双 is 析取整体否定 → 两段否定合取", () => {
  assert.equal(demorganNorm("!(T is TK_Float || T is TK_Double)"), "!(T is TK_Float) && !(T is TK_Double)");
  assert.equal(demorganNorm("!(S is TK_LongLong) && S is TK_Double"), "!(S is TK_LongLong) && S is TK_Double"); // 无析取不动
});

test("extractChainBlocks：臂体归属（嵌套指令归臂、下一臂起始前截断）", () => {
  const body = [
    "  if a {",
    "    emit A",
    "    if nested {",
    "      emit N",
    "    }",
    "  } else if b {",
    "    emit B",
    "  }",
  ].join("\n");
  const { conds, bodies } = extractChainBlocks(body);
  assert.equal(conds.length, 2);
  assert.ok((bodies[0] ?? "").includes("emit A") && (bodies[0] ?? "").includes("emit N"));
  assert.ok((bodies[1] ?? "").includes("emit B") && !(bodies[1] ?? "").includes("emit A"));
});

test("diffOf：只在单成员出现的项算差；共享项不算", () => {
  const set = {
    name: "x",
    extractor: "cast_chain" as const,
    members: [{ name: "A", file: "f", anchor_start: "a" }, { name: "B", file: "f", anchor_start: "b" }],
    divergences: [],
  };
  const d = diffOf(set, [
    { member: "A", items: ["p", "q"] },
    { member: "B", items: ["p", "r"] },
  ]);
  assert.deepEqual(
    d.map((x) => `${x.only_in}:${x.item}`).sort(),
    ["A:q", "B:r"],
  );
});

test("diffOf 缺项向（审阅 P1 回归锚）：四成员 2 有 2 无 → 缺项方两条、有项方零条（旧判据零报告）", () => {
  const set = {
    name: "four",
    extractor: "dump_arg_guards" as const,
    members: ["m1", "m2", "m3", "m4"].map((n) => ({ name: n, file: "f", anchor_start: "a" })),
    divergences: [],
  };
  const d = diffOf(set, [
    { member: "m1", items: ["g", "base"] },
    { member: "m2", items: ["g", "base"] },
    { member: "m3", items: ["base"] },
    { member: "m4", items: ["base"] },
  ]);
  assert.deepEqual(
    d.map((x) => `${x.only_in}:${x.item}`).sort(),
    ["m3:g", "m4:g"],
    "g 两家有两家缺 → 缺项方 m3/m4 各一条；base 四家全有零条；有项方 m1/m2 不算独有",
  );
});

test("真实仓库：cast_mbt 孪生集已注销（#471 单源化）；dump 四家 diff 0（F5 随 PR #450、F9 随 SWEEP1 #445 B2 先后销案）", () => {
  const rd = loadRules();
  const fps = allFingerprints(rd);
  // #471（2026-11-05，SWEEP2）：gen_cast_expr / gen_expr_with_cast 两链合一为
  // emit_conversion 单源——孪生本体消亡，cast_mbt 集注销（防复活锚：集不得回归）。
  // 边界（PR #485 审阅 P3-4）：本断言是**配置级**（twin_sets 无该集），
  // 不检测「cast 链重新长出复制件」——链级复活检测归 --discover 人工
  // 重立（rules.json _doc 已登记该口径）
  assert.equal(rd.twin_sets.some((s) => s.name === "cast_mbt"), false);
  assert.equal(fps["cast_mbt"], undefined);
  // dump：F5 两门禁差异随 PR #450（M36b 四家连坐 + P2-3 归一比较）销案；F9 排序
  // 分叉随 SWEEP1 #445 B2 销案（探针实锤内置 sort 长度优先序 ASCII 域亦分叉——
  // corpus 1176 文件名逐位全异，ast/typeck/tokens 三家连坐迁 sort_files_lex）——
  // 四家指纹全一致、divergences 登记清空（登记残留即 verdict 红）
  const dumpFps = fps["dump_four"] ?? [];
  assert.equal(dumpFps.length, 4);
  const diffs = diffOf(rd.twin_sets[0]!, dumpFps);
  assert.equal(diffs.length, 0, `dump 四家须零分叉（实测 ${JSON.stringify(diffs)}）`);
  for (const f of dumpFps) {
    assert.ok(f.items.includes("sort:lexical"), `${f.member} 四家均持 sort:lexical（F9 销案面）`);
    assert.ok(!f.items.includes("sort:builtin"), `${f.member} 内置 sort 谓词须绝迹`);
  }
  assert.equal(verdict(rd, fps), true);
});

test("J9 红：单边加指纹项 / 删登记 / 加僵尸（内存注入，dump_four 集）", () => {
  const rd = loadRules();
  const fps = allFingerprints(rd);
  {
    const f2 = { ...fps, dump_four: fps["dump_four"]!.map((f) => ({ ...f, items: [...f.items] })) };
    f2["dump_four"]![1]!.items.push("guard:zombie_probe");
    assert.equal(verdict(rd, f2), false);
  }
  {
    // SWEEP1 #445 B2 连坐：F9 销案后 dump_four 的 divergences 已空——「删登记」
    // 注入无从删，翻新为「空表 push 假登记」（登记与实际指纹不符即红，语义同源）
    const rd2 = JSON.parse(JSON.stringify(rd)) as typeof rd;
    rd2.twin_sets[0]!.divergences.push({ item: "zz", only_in: "dump_compile", reason: "僵尸探针" });
    assert.equal(verdict(rd2, fps), false);
  }
  {
    const rd2 = JSON.parse(JSON.stringify(rd)) as typeof rd;
    rd2.twin_sets[0]!.divergences.push({ item: "zz", only_in: "zz", reason: "僵尸探针" });
    assert.equal(verdict(rd2, fps), false);
  }
});

test("castChainFingerprint / dumpGuardsFingerprint：锚点错 fail loud（exit 2）", () => {
  const bad = { name: "x", file: "moonbit/codegen/cast.mbt", anchor_start: "fn 不存在(" };
  assert.throws(() => castChainFingerprint(bad), /锚点未命中/);
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

test("dumpGuardsFingerprint 谓词面：文件名长度检查不误命中 upper_bound；注释提及不误命中排序谓词", () => {
  // 回归锚①：谓词曾误把 `name.length() > 2`（.c 后缀判断）当参数上界门禁
  const rd = loadRules();
  const ast = dumpGuardsFingerprint(rd.twin_sets[0]!.members[1]!);
  // PR #450（B3/M36b）后 dump_ast 已有参数上界门禁（args.length() > 3）——F5 销案翻转锚；
  // 仍须防文件名长度检查（name.length() > 2）误命中：谓词限 positional/args 前缀
  assert.ok(ast.items.includes("guard:upper_bound"), "dump_ast 有参数上界门禁（F5 已销案翻转）");
  assert.ok(ast.items.includes("guard:lower_bound") && ast.items.includes("rc:usage_4"));
  // 回归锚②（SWEEP1 #445 B2 翻新）：原场景「注释提及 sort_files_lex 而行为
  // files.sort()」（A7' 批 2026-11-03 rebase 实锤）随 F9 销案消失——四家行为
  // 本体现在就是 sort_files_lex。剥注释语义（2026-11-03 防假红）由谓词实现
  // 「剥行注释后的函数体上匹配」承担；此处锁行为面：注释含 sort_files_lex
  // 字样（新注释提及先例口径）而谓词命中来自行为本体（builtin 绝迹）
  const tokensSrc = fs.readFileSync(path.join(projectRoot(), "moonbit/cmd/dump_tokens/main.mbt"), "utf8");
  if (/\/\/.*sort_files_lex/.test(tokensSrc)) {
    const tokens = dumpGuardsFingerprint(rd.twin_sets[0]!.members[2]!);
    assert.ok(tokens.items.includes("sort:lexical"), "dump_tokens 行为本体 sort_files_lex（F9 销案后注释与行为一致）");
    assert.ok(!tokens.items.includes("sort:builtin"), "内置 sort 谓词须绝迹（F9 销案）");
  }
});
