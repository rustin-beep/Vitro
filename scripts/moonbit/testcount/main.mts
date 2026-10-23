#!/usr/bin/env node
// testcount：MoonBit 测试数三向对账闸（v2；#273 存量 Go 重写批）。
//
// 真值 = 本闸自跑 `moon test` 解析 Total tests（facts 制品只作参考打印，
// 不参与判定——v1 的「复述」缺陷来源）。对账三方：
// moonbit/README.md ↔ moonbit/README.mbt.md ↔ moon test 实跑值。
// 另做分解式算术自洽（分解和 + doc test == 裸声明；fs+gateway+cli ==
// native-only；裸 + native-only == native 全量）。
//
//   node scripts/moonbit/testcount/main.mts
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../../internal/capi.mts";

const DECL_RE = /#\s*(\d+)\s*测试（/g;

export function readDeclared(p: string): number {
  let data: string;
  try {
    data = fs.readFileSync(p, "utf8");
  } catch (e) {
    throw new Error(`读 ${p}: ${e instanceof Error ? e.message : String(e)}`);
  }
  const matches = [...data.matchAll(DECL_RE)];
  if (matches.length === 0) throw new Error(`${p} 未找到「# N 测试（」声明行`);
  if (matches.length > 1) throw new Error(`${p} 声明行不唯一（${matches.length} 处）`);
  const n = Number.parseInt(matches[0]?.[1] ?? "", 10);
  if (Number.isNaN(n)) throw new Error(`${p} 声明数字解析失败`);
  return n;
}

function getInts(s: string, re: RegExp, p: string, name: string): number[] {
  const ms = [...s.matchAll(new RegExp(re.source, "g"))];
  if (ms.length !== 1) throw new Error(`${p}「${name}」锚行数=${ms.length}（须唯一）`);
  const m = ms[0] ?? [];
  const out: number[] = [];
  for (let i = 1; i < m.length; i++) {
    const n = Number.parseInt(m[i] ?? "", 10);
    if (Number.isNaN(n)) throw new Error(`${p}「${name}」数字解析失败`);
    out.push(n);
  }
  return out;
}

export function checkArithmetic(p: string, declared: number): void {
  let s: string;
  try {
    s = fs.readFileSync(p, "utf8");
  } catch (e) {
    throw new Error(`读 ${p}: ${e instanceof Error ? e.message : String(e)}`);
  }
  const yz = getInts(s, /分解和 (\d+) \+ 根 README doc test (\d+)/, p, "裸分解");
  const y = yz[0] ?? 0;
  const z = yz[1] ?? 0;
  if (y + z !== declared) {
    throw new Error(`${p} 分解不自洽: 分解和 ${y} + doc test ${z} = ${y + z} != 裸声明 ${declared}`);
  }
  const ab = getInts(s, /native-only 包测试 (\d+) 个（fs (\d+) \/ gateway (\d+) \/ cli (\d+)/, p, "native-only 分解");
  const [total, fsN, gwN, cliN] = [ab[0] ?? 0, ab[1] ?? 0, ab[2] ?? 0, ab[3] ?? 0];
  if (fsN + gwN + cliN !== total) {
    throw new Error(`${p} native-only 不自洽: fs ${fsN} + gateway ${gwN} + cli ${cliN} = ${fsN + gwN + cliN} != 总数 ${total}`);
  }
  const qs = getInts(s, /--target native` 全量 (\d+)/, p, "native 全量");
  const q = qs[0] ?? 0;
  if (declared + total !== q) {
    throw new Error(`${p} 全量不自洽: 裸 ${declared} + native-only ${total} = ${declared + total} != 全量 ${q}`);
  }
}

function tailN(s: string, n: number): string {
  const lines = s.replace(/\n+$/, "").split("\n");
  return (lines.length > n ? lines.slice(-n) : lines).join("\n");
}

export function runMoonTest(): number {
  const r = spawnSync("moon", ["test"], {
    cwd: path.join(projectRoot(), "moonbit"),
    encoding: "utf8",
  });
  if (r.status !== 0) {
    throw new Error(`moon test 失败: exit ${r.status}\n${tailN((r.stdout ?? "") + (r.stderr ?? ""), 20)}`);
  }
  const out = (r.stdout ?? "") + (r.stderr ?? "");
  const re = /Total tests:\s*(\d+),\s*passed:\s*(\d+),\s*failed:\s*(\d+)/g;
  const ms = [...out.matchAll(re)];
  if (ms.length === 0) throw new Error(`moon test 输出未找到 Total tests 行\n${tailN(out, 10)}`);
  const m = ms[ms.length - 1] ?? [];
  const total = Number.parseInt(m[1] ?? "", 10);
  const failed = Number.parseInt(m[3] ?? "", 10);
  if (failed !== 0) throw new Error(`moon test 本身有失败（${failed} failed）——先修测试再对账`);
  return total;
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  let truth: number;
  try {
    truth = runMoonTest();
  } catch (e) {
    console.error("testcount: " + (e instanceof Error ? e.message : String(e)));
    process.exit(1);
  }
  let fail = false;
  for (const p of ["moonbit/README.md", "moonbit/README.mbt.md"]) {
    let n: number;
    try {
      n = readDeclared(path.join(projectRoot(), p));
    } catch (e) {
      console.error("testcount: " + (e instanceof Error ? e.message : String(e)));
      process.exit(1);
    }
    if (n !== truth) {
      console.error(`testcount: ${p} 声明 ${n} != moon test 实跑 ${truth}`);
      fail = true;
    }
    try {
      checkArithmetic(path.join(projectRoot(), p), n);
    } catch (e) {
      console.error("testcount: " + (e instanceof Error ? e.message : String(e)));
      fail = true;
    }
  }
  try {
    const facts = fs.readFileSync(path.join(projectRoot(), "reports/facts.json"), "utf8");
    const i = facts.indexOf('"moonbit_test_passed"');
    if (i >= 0) {
      const seg = facts.slice(i, i + 300);
      const j = seg.indexOf('"as_of"');
      if (j >= 0) console.log(`testcount: 参考 facts.as_of ${seg.slice(j).split("\n", 1)[0]?.trim() ?? ""}（制品不参与判定）`);
    }
  } catch {
    // 参考制品缺失不判定
  }
  if (fail) {
    console.error("testcount: 对账不符——文档声明须等于 moon test 实跑真值（同步后提交）");
    process.exitCode = 1;
  } else {
    console.log(`testcount: PASS——两文档声明与 moon test 实跑真值一致（${truth}）`);
  }
}
