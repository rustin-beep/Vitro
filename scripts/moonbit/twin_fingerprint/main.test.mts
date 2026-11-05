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

test("真实仓库：cast_mbt 孪生集已注销（#471 单源化）；dump 四家现存差 2 条（F5 已随 PR #450 销案，余 F9 排序两面）", () => {
  const rd = loadRules();
  const fps = allFingerprints(rd);
  // #471（2026-11-05）：gen_cast_expr / gen_expr_with_cast 两链合一为 emit_conversion
  // 单源——孪生本体消亡，cast_mbt 集注销（防复活锚：集不得回归）
  assert.equal(rd.twin_sets.some((s) => s.name === "cast_mbt"), false);
  assert.equal(fps["cast_mbt"], undefined);
  // dump：F5 两门禁差异已随 PR #450（M36b 四家连坐 + P2-3 归一比较）销案——现存仅
  // F9 排序分叉的两面（三家 builtin sort 独有 sort:builtin 项 / compile 独有 sort:lexical 项）
  const dumpFps = fps["dump_four"] ?? [];
  assert.equal(dumpFps.length, 4);
  const diffs = diffOf(rd.twin_sets[0]!, dumpFps);
  assert.equal(diffs.length, 2);
  assert.deepEqual(
    diffs.map((x) => x.item).sort(),
    ["sort:builtin", "sort:lexical"],
  );
  assert.ok(diffs.every((x) => x.only_in === "dump_compile"), "两条不一致方均为 dump_compile（F9 排序分叉——统一 sort_files_lex 后销案）");
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
    const rd2 = JSON.parse(JSON.stringify(rd)) as typeof rd;
    rd2.twin_sets[0]!.divergences.pop();
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

test("dumpGuardsFingerprint 谓词面：文件名长度检查不误命中 upper_bound；注释提及不命中 sort:lexical", () => {
  // 回归锚①：谓词曾误把 `name.length() > 2`（.c 后缀判断）当参数上界门禁
  const rd = loadRules();
  const ast = dumpGuardsFingerprint(rd.twin_sets[0]!.members[1]!);
  // PR #450（B3/M36b）后 dump_ast 已有参数上界门禁（args.length() > 3）——F5 销案翻转锚；
  // 仍须防文件名长度检查（name.length() > 2）误命中：谓词限 positional/args 前缀
  assert.ok(ast.items.includes("guard:upper_bound"), "dump_ast 有参数上界门禁（F5 已销案翻转）");
  assert.ok(ast.items.includes("guard:lower_bound") && ast.items.includes("rc:usage_4"));
  // 回归锚②（2026-11-03 rebase 实锤）：A7' 批把 dump_tokens 注释改成提及 sort_files_lex
  // （行为仍 files.sort()）——谓词须剥注释后匹配，否则假红
  const tokensSrc = fs.readFileSync(path.join(projectRoot(), "moonbit/cmd/dump_tokens/main.mbt"), "utf8");
  if (/\/\/.*sort_files_lex/.test(tokensSrc)) {
    const tokens = dumpGuardsFingerprint(rd.twin_sets[0]!.members[2]!);
    assert.ok(!tokens.items.includes("sort:lexical"), "dump_tokens 注释提及 sort_files_lex 不得算字典序谓词命中");
    assert.ok(tokens.items.includes("sort:builtin"));
  }
});
