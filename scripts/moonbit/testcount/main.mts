#!/usr/bin/env node
// testcount：MoonBit 测试数三向对账闸（v3；#308 计数 facts 化配套）。
//
// 真值 = 本闸自跑 `moon test` 解析 Total tests（facts 制品只作参考打印，
// 不参与判定——v1 的「复述」缺陷来源）。v3（2026-10-26）：双口径实跑——
// 裸口径（`moon test`）+ native 全量口径（`MOON_CC=clang moon test
// --target native`，纪律 11）各自对账两 README 的声明行；README 计数行
// 已是「裸数 + facts 键标注」形态（#308——巨型批注链/分解式退场），分解
// 式算术自洽检查随之条件化：锚行在则查（旧形态兼容）、不在则跳过；
// native 全量声明行两形态都有，保留强约束（唯一 + 对实跑真值）。
// 对账四方：moonbit/README.md ↔ README.mbt.md ↔ moon test 裸实跑 ↔
// moon test native 实跑。
//
//   node scripts/moonbit/testcount/main.mts
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../../internal/capi.mts";

const DECL_RE = /#\s*(\d+)\s*测试（/g;
// native 全量声明：兼容两形态——新「moon test --target native 全量 N」
// 与旧「`--target native` 全量 N」（反引号 + 空白任选）
const DECL_NATIVE_RE = /--target native[`\s]*全量 (\d+)/g;

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

// getIntsOpt：条件化锚提取（#308 v3）——分解式退场后锚行允许缺席：
// 0 行返回 null（调用方跳过算术检查），1 行返回数字，>1 行仍红
// （多锚=形态回潮或复制事故，不是合法缺席）。
function getIntsOpt(s: string, re: RegExp, p: string, name: string): number[] | null {
  const ms = [...s.matchAll(new RegExp(re.source, "g"))];
  if (ms.length === 0) return null;
  if (ms.length > 1) throw new Error(`${p}「${name}」锚行数=${ms.length}（须唯一）`);
  const m = ms[0] ?? [];
  const out: number[] = [];
  for (let i = 1; i < m.length; i++) {
    const n = Number.parseInt(m[i] ?? "", 10);
    if (Number.isNaN(n)) throw new Error(`${p}「${name}」数字解析失败`);
    out.push(n);
  }
  return out;
}

export function readDeclaredNative(p: string): number {
  let data: string;
  try {
    data = fs.readFileSync(p, "utf8");
  } catch (e) {
    throw new Error(`读 ${p}: ${e instanceof Error ? e.message : String(e)}`);
  }
  const matches = [...data.matchAll(DECL_NATIVE_RE)];
  if (matches.length === 0) throw new Error(`${p} 未找到「--target native 全量 N」声明行`);
  if (matches.length > 1) throw new Error(`${p} native 全量声明行不唯一（${matches.length} 处）`);
  const n = Number.parseInt(matches[0]?.[1] ?? "", 10);
  if (Number.isNaN(n)) throw new Error(`${p} native 全量声明数字解析失败`);
  return n;
}

export function checkArithmetic(p: string, declared: number): void {
  let s: string;
  try {
    s = fs.readFileSync(p, "utf8");
  } catch (e) {
    throw new Error(`读 ${p}: ${e instanceof Error ? e.message : String(e)}`);
  }
  // 分解式锚条件化（#308 v3：裸分解/裸 native-only 分解已退场，在则查）
  const yz = getIntsOpt(s, /分解和 (\d+) \+ 根 README doc test (\d+)/, p, "裸分解");
  if (yz !== null) {
    const y = yz[0] ?? 0;
    const z = yz[1] ?? 0;
    if (y + z !== declared) {
      throw new Error(`${p} 分解不自洽: 分解和 ${y} + doc test ${z} = ${y + z} != 裸声明 ${declared}`);
    }
  }
  const ab = getIntsOpt(s, /native-only 包测试 (\d+) 个（fs (\d+) \/ gateway (\d+) \/ cli (\d+)/, p, "native-only 分解");
  let total = 0;
  if (ab !== null) {
    const [t, fsN, gwN, cliN] = [ab[0] ?? 0, ab[1] ?? 0, ab[2] ?? 0, ab[3] ?? 0];
    if (fsN + gwN + cliN !== t) {
      throw new Error(`${p} native-only 不自洽: fs ${fsN} + gateway ${gwN} + cli ${cliN} = ${fsN + gwN + cliN} != 总数 ${t}`);
    }
    total = t;
  }
  // native 全量锚：两形态都有——唯一性强约束保留；算术链（裸+native-only
  // ==全量）仅在 native-only 分解锚在场时检查（新形态该锚退场，全量正确
  // 性由 main 流程的「声明 == 实跑 native 真值」对账锁定——比算术自洽更强）
  const qs = getInts(s, /--target native[`\s]*全量 (\d+)/, p, "native 全量");
  const q = qs[0] ?? 0;
  if (ab !== null && declared + total !== q) {
    throw new Error(`${p} 全量不自洽: 裸 ${declared} + native-only ${total} = ${declared + total} != 全量 ${q}`);
  }
}

function tailN(s: string, n: number): string {
  const lines = s.replace(/\n+$/, "").split("\n");
  return (lines.length > n ? lines.slice(-n) : lines).join("\n");
}

export function runMoonTest(target: "bare" | "native" = "bare"): number {
  const args = target === "native" ? ["test", "--target", "native"] : ["test"];
  const env = target === "native" ? { ...process.env, MOON_CC: "clang" } : process.env;
  const r = spawnSync("moon", args, {
    cwd: path.join(projectRoot(), "moonbit"),
    encoding: "utf8",
    env,
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
  let truthNative: number;
  try {
    truth = runMoonTest();
    truthNative = runMoonTest("native");
  } catch (e) {
    console.error("testcount: " + (e instanceof Error ? e.message : String(e)));
    process.exit(1);
  }
  let fail = false;
  for (const p of ["moonbit/README.md", "moonbit/README.mbt.md"]) {
    let n: number;
    let nn: number;
    try {
      n = readDeclared(path.join(projectRoot(), p));
      nn = readDeclaredNative(path.join(projectRoot(), p));
    } catch (e) {
      console.error("testcount: " + (e instanceof Error ? e.message : String(e)));
      process.exit(1);
    }
    if (n !== truth) {
      console.error(`testcount: ${p} 声明 ${n} != moon test 实跑 ${truth}`);
      fail = true;
    }
    if (nn !== truthNative) {
      console.error(`testcount: ${p} native 全量声明 ${nn} != moon test --target native 实跑 ${truthNative}`);
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
    console.log(`testcount: PASS——两文档双口径声明与实跑真值一致（裸 ${truth} / native 全量 ${truthNative}）`);
  }
}
