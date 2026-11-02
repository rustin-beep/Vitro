// twin_fingerprint.test.mts —— 链块抽取 / 德摩根归一 / dump 谓词 / 差集 + 真实仓库判定 + J9 内存红路
import { test } from "node:test";
import assert from "node:assert/strict";
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

test("真实仓库：cast 两链指纹含 F1 相关臂；dump 四家门禁差 3 条（F5/F9）", () => {
  const rd = loadRules();
  const fps = allFingerprints(rd);
  const cast = fps["cast_mbt"] ?? [];
  assert.equal(cast.length, 2);
  // 两份共有臂（孪生本体）：D←F 臂两侧都在
  for (const f of cast) assert.ok(f.items.some((it) => it.includes("T is TK_Double && S is TK_Float")), f.member);
  // dump：compile 独有三谓词（F5 两门禁 + F9 排序）
  const dumpFps = fps["dump_four"] ?? [];
  assert.equal(dumpFps.length, 4);
  const diffs = diffOf(rd.twin_sets[1]!, dumpFps);
  assert.equal(diffs.length, 3);
  assert.deepEqual(
    diffs.map((x) => x.item).sort(),
    ["guard:target_eq_out", "guard:upper_bound", "sort:lexical"],
  );
  assert.equal(verdict(rd, fps), true);
});

test("J9 红：单边加指纹项 / 删登记 / 加僵尸（内存注入）", () => {
  const rd = loadRules();
  const fps = allFingerprints(rd);
  {
    const f2 = { ...fps, cast_mbt: fps["cast_mbt"]!.map((f) => ({ ...f, items: [...f.items] })) };
    f2["cast_mbt"]![1]!.items.push("T is TK_Zombie => CastZ9Z9");
    assert.equal(verdict(rd, f2), false);
  }
  {
    const rd2 = JSON.parse(JSON.stringify(rd)) as typeof rd;
    rd2.twin_sets[1]!.divergences.pop();
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

test("dumpGuardsFingerprint 谓词面：文件名长度检查不误命中 upper_bound", () => {
  // 回归锚：谓词曾误把 `name.length() > 2`（.c 后缀判断）当参数上界门禁
  const member = loadRules().twin_sets[1]!.members[1]!;
  const fp = dumpGuardsFingerprint(member);
  assert.ok(!fp.items.includes("guard:upper_bound"), "dump_ast 无参数上界门禁（F5 现状）——不得被文件名检查误报");
  assert.ok(fp.items.includes("guard:lower_bound") && fp.items.includes("rc:usage_4"));
});
