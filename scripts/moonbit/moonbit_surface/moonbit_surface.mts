#!/usr/bin/env node
// moonbit_surface —— MoonBit 对外面审计（Go→.mts 重写，refs #273；原 622 行，S5 收尾批）。
//
// 用法（cd moonbit 或仓库根；本驱动内部 chdir 到 moonbit/）：
//
//	node scripts/moonbit/moonbit_surface/moonbit_surface.mts          # 列收面 + 白名单/边表双对账
//	node scripts/moonbit/moonbit_surface/moonbit_surface.mts -check   # 同上（两形态同强度；旗标仅兼容旧调用）
//
// 判定：一个 pub 符号是**对外面**当且仅当它被消费——**黑盒测试/doc 测试的
// 自引用 `@pkg.` 点名也算消费**，故 `@pkg.sym` 的 grep 结果须按文件归属包甄别，
// 不天然等于跨包消费。类型符号有消费则其方法/字段面跟随保留；类型无消费 →
// 类型本身进可收清单（成员随之隐没）。
//
// **口径**：consumer 与 provider 一律**包全名**（moon.mod 模块名 + 包目录）。
// `@别名.` 依据**消费文件所属包的 moon.pkg import 块**解析（别名 = import 路径
// 末段；全仓零显式别名，遇 `as` 等未知形态 fail loud）：
//   - 普通源码与 *_wbtest.mbt：main import 块；
//   - *_test.mbt 与包内 README*（doc 测试是黑盒）：main ∪ for "test" ∪ 自引用；
//   - 模块根 README*（无 moon.pkg）：别名按全仓工作区包末段解析，末段撞车
//     （如 `host`）或零命中均 fail loud。
//
// **判据盲区登记（文本 grep 的已知边界）**：① 注释/字符串内的 @pkg.sym 计为
// 消费（过宽方向）；② 点调用方法（obj.method()）不带前缀，经变量流动的方法
// 消费不计（类型符号消费已按类型名覆盖大部分场景）。
//
// 白名单 surface_allowlist.txt：一行一符号（`包全名 sym`）= 允许保持 pub 但当前
// 无消费的集合；双向对账（多出=漏收红 / 条目不在实际集合=过期红）。边清单
// surface_edges.txt：一行一边（`consumer provider sym`；根 README 记 `.`）。
//
// 迁移口径（#292 批）：
//   - 与 Go 版逐字对齐（默认模式与 `-check` 两模式进 parity 闸）；
//   - `os.Chdir("moonbit")` 原样保留（相对路径语义是判定面的一部分：白名单/边
//     清单用 `../scripts/...` 读）；`fatal` = exit 2，唯一例外是
//     `noConsecutiveBlankLines` 的 exit 1（与 Go 版一致）；
//   - 排序一律字节序（Go sort.Strings），沿用 internal/text 的 byteSort；
//   - `hasWord` 是**字节**词边界判定，按 ASCII 标识符字节实现（与 Go 等价）。
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { byteCompare, byteSort } from "../../internal/text.mts";

// ── mbti 行形态 → 符号 ────────────────────────────────────────
const RE_FN = /^pub fn ([A-Za-z_][A-Za-z0-9_]*)/;
const RE_METHOD = /^pub fn ([A-Za-z_][A-Za-z0-9_]*)::([A-Za-z_][A-Za-z0-9_]*)/;
const RE_TYPE = /^pub(?:\(all\))? (?:struct|enum) ([A-Za-z_][A-Za-z0-9_]*)/;
const RE_CONST = /^pub (?:const|let) ([A-Za-z_][A-Za-z0-9_]*)/;
// 消费形态：@pkg.sym / @pkg.Type::m / @pkg.Type::Ctor
const RE_USE = /@[a-z][a-z0-9_]*\.([A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)?)/g;

interface PkgInfo {
  /** 工作区相对目录，如 lexer/internal/host */
  relDir: string;
  /** 包全名，如 vitro/engine/lexer/internal/host */
  fullName: string;
  /** 别名 → provider 全名（main import 块） */
  mainAliases: Map<string, string>;
  /** 别名 → provider 全名（for "test" 块） */
  testAliases: Map<string, string>;
}

class ExitErr extends Error {
  readonly code: number;
  constructor(code: number) {
    super("exit");
    this.name = "ExitErr";
    this.code = code;
  }
}

export function fatal(msg: string): never {
  process.stderr.write("moonbit_surface: " + msg + "\n");
  throw new ExitErr(2);
}

const errText = (e: unknown): string => (e instanceof Error ? e.message : String(e));

const toSlash = (p: string): string => p.split(path.sep).join("/");

/** 逐字节判连续空行（Go：连续 3 个 '\n' 即「>= 2 连续空行」；退出码 1 非 2）。 */
export function noConsecutiveBlankLines(p: string): void {
  let data: Buffer;
  try {
    data = fs.readFileSync(p);
  } catch (e) {
    process.stderr.write(`moonbit_surface: read ${p}: ${errText(e)}\n`);
    throw new ExitErr(1);
  }
  let run = 0;
  for (const b of data) {
    if (b === 0x0a) {
      run++;
      if (run >= 3) {
        process.stderr.write(`moonbit_surface: ${p} has >= 2 consecutive blank lines\n`);
        throw new ExitErr(1);
      }
    } else {
      run = 0;
    }
  }
}

/** 字节词边界匹配（避免 `Severity` 命中 `SeverityX`）。 */
export function hasWord(s: string, w: string): boolean {
  const isIdent = (c: number): boolean =>
    c === 0x5f || (c >= 0x61 && c <= 0x7a) || (c >= 0x41 && c <= 0x5a) || (c >= 0x30 && c <= 0x39);
  const buf = Buffer.from(s, "utf8");
  const wb = Buffer.from(w, "utf8");
  let idx = 0;
  for (;;) {
    const at = buf.indexOf(wb, idx);
    if (at < 0) return false;
    const beforeOK = at === 0 || !isIdent(buf[at - 1] as number);
    const afterOK = at + wb.length >= buf.length || !isIdent(buf[at + wb.length] as number);
    if (beforeOK && afterOK) return true;
    idx = at + 1;
  }
}

/** Walk 口径：跳过 _build/.mooncakes/scripts 目录（Go filepath.Walk 的 SkipDir）。 */
function walkRepo(root: string, onFile: (full: string, base: string) => void): void {
  const visit = (dir: string): void => {
    const ents = fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => byteCompare(a.name, b.name));
    for (const e of ents) {
      const full = path.join(dir, e.name);
      if (e.isDirectory()) {
        if (e.name === "_build" || e.name === ".mooncakes" || e.name === "scripts") continue;
        visit(full);
        continue;
      }
      onFile(full, e.name);
    }
  };
  visit(root);
}

/** moon.mod 的 name 字段（包全名前缀的唯一真相源）。 */
export function readModuleName(): string {
  let data: string;
  try {
    data = fs.readFileSync("moon.mod", "utf8");
  } catch (e) {
    fatal(`读 moon.mod 失败：${errText(e)}`);
  }
  for (const line of data.split("\n")) {
    const t = line.trim();
    if (t.startsWith("name")) {
      const q0 = t.indexOf('"');
      const q1 = t.lastIndexOf('"');
      if (q0 < 0 || q1 <= q0) fatal(`moon.mod name 行形态未知：${t}`);
      return t.slice(q0 + 1, q1);
    }
  }
  fatal("moon.mod 无 name 字段");
}

/**
 * 全仓 moon.pkg → 包全名 + 两级 import 别名表。
 * 语法面（本仓实测形态，超出即红）：`import { "path", }` / `… } for "test"`；
 * 别名 = 路径末段，块内重名、main/for-test 同别名不同 provider、非 "test" scope、
 * 显式别名一律红。
 */
export function discoverPackages(moduleName: string): Map<string, PkgInfo> {
  const pkgs = new Map<string, PkgInfo>();
  const mps: string[] = [];
  walkRepo(".", (full, base) => {
    if (base === "moon.pkg") mps.push(toSlash(full));
  });
  if (mps.length === 0) fatal("未发现任何 moon.pkg（须在 moonbit/ 下运行）");
  for (const p of mps) {
    const relDir = toSlash(path.dirname(p));
    const pi: PkgInfo = {
      relDir,
      fullName: moduleName + "/" + relDir,
      mainAliases: new Map(),
      testAliases: new Map(),
    };
    const data = fs.readFileSync(p, "utf8");
    let scope = "";
    let inImport = false;
    for (const raw of data.split("\n")) {
      let line = raw.trim();
      const ci = line.indexOf("//");
      if (ci >= 0) line = line.slice(0, ci).trim();
      if (line === "") continue;
      if (!inImport) {
        if (line === "import {") {
          inImport = true;
          scope = "";
          continue;
        }
        // 非 import 行（supported_targets / pkgtype / warnings 等）忽略
        if (line.startsWith("import")) fatal(`${p}: 未知 import 形态（本闸只认 \`import {\` 块）：${line}`);
        continue;
      }
      if (line.startsWith("}")) {
        inImport = false;
        const rest = line.slice(1).trim();
        if (rest !== "") {
          if (!rest.startsWith('for "test"')) fatal(`${p}: 未知 import scope（本闸只认 for "test"）：${rest}`);
          scope = "test";
        }
        continue;
      }
      let entry = line.endsWith(",") ? line.slice(0, -1) : line;
      entry = entry.trim();
      if (entry.length < 2 || !entry.startsWith('"') || !entry.endsWith('"')) {
        fatal(`${p}: import 条目形态未知（显式别名 as / 多行等须先扩闸）：${entry}`);
      }
      const impPath = entry.slice(1, -1);
      const alias = impPath.slice(impPath.lastIndexOf("/") + 1);
      const target = scope === "test" ? pi.testAliases : pi.mainAliases;
      const prev = target.get(alias);
      if (prev !== undefined && prev !== impPath) fatal(`${p}: 块内别名冲突 @${alias}. → ${prev} 与 ${impPath}`);
      target.set(alias, impPath);
    }
    if (inImport) fatal(`${p}: import 块未闭合`);
    // main 与 for-test 同别名不同 provider：黑盒/doc 测试可见集是两者并集
    for (const [a, tp] of pi.testAliases) {
      const mp2 = pi.mainAliases.get(a);
      if (mp2 !== undefined && mp2 !== tp) fatal(`${p}: main 与 for "test" 别名冲突 @${a}. → ${mp2} 与 ${tp}`);
    }
    if (pkgs.has(relDir)) fatal(`包目录重复登记：${relDir}`);
    pkgs.set(relDir, pi);
  }
  return pkgs;
}

const lastSeg = (s: string): string => s.slice(s.lastIndexOf("/") + 1);

/**
 * 语料文件 → (别名→provider 全名 可见集, 歧义别名集, consumer 全名)。
 * 模块根 README* 的 consumer 记 "."（无包上下文；发布面文档承诺按全仓工作区
 * 包末段解析）——末段撞车的别名入歧义集，引用即红，不静默择一。
 */
export function visibilityFor(
  f: string,
  pkgs: Map<string, PkgInfo>,
): { vis: Map<string, string>; ambiguous: Set<string> | null; consumer: string } {
  let d = toSlash(path.dirname(f));
  for (;;) {
    const pi = pkgs.get(d);
    if (pi !== undefined) {
      const base = path.basename(f);
      const vis = new Map<string, string>();
      for (const [a, p] of pi.mainAliases) vis.set(a, p);
      const self = lastSeg(pi.fullName);
      if (base.endsWith("_test.mbt") || base.startsWith("README")) {
        // 黑盒测试 / doc 测试：main ∪ for-test ∪ 自引用
        for (const [a, p] of pi.testAliases) vis.set(a, p);
        vis.set(self, pi.fullName);
        vis.set("self", pi.fullName);
        return { vis, ambiguous: null, consumer: pi.fullName };
      }
      // 普通源码 / wbtest：main import 块 + 自引用（与 main import 撞名则红）
      const prev = vis.get(self);
      if (prev !== undefined && prev !== pi.fullName) {
        fatal(`包 ${pi.fullName} 的 main import 含与自身末段撞名的别名 @${self}. → ${prev}（MoonBit 亦不允许）`);
      }
      vis.set(self, pi.fullName);
      vis.set("self", pi.fullName);
      return { vis, ambiguous: null, consumer: pi.fullName };
    }
    if (d === "." || d === "/") break;
    d = toSlash(path.dirname(d));
  }
  // 模块根（无 moon.pkg）：只允许 README*（doc/发布面）
  const base = path.basename(f);
  if (!base.startsWith("README")) fatal(`语料文件 ${f} 不属于任何包（模块根只认 README*）——散置 .mbt 须入包后过闸`);
  const vis = new Map<string, string>();
  const ambiguous = new Set<string>();
  const byAlias = new Map<string, string[]>();
  for (const pi of pkgs.values()) {
    const last = lastSeg(pi.fullName);
    const cur = byAlias.get(last);
    if (cur === undefined) byAlias.set(last, [pi.fullName]);
    else cur.push(pi.fullName);
  }
  for (const [a, cands] of byAlias) {
    if (cands.length === 1) vis.set(a, cands[0] as string);
    else ambiguous.add(a);
  }
  return { vis, ambiguous, consumer: "." };
}

/** 实际边集 ↔ ../scripts/moonbit/surface_edges.txt 双向对账。 */
export function checkEdges(actual: Set<string>): number {
  let text: string;
  try {
    text = fs.readFileSync("../scripts/moonbit/surface_edges.txt", "utf8");
  } catch {
    fatal("边清单缺失（../scripts/moonbit/surface_edges.txt）——先生成基准");
  }
  const allowed = new Set<string>();
  for (const raw of text.split("\n")) {
    const line = raw.trim();
    if (line !== "" && !line.startsWith("#")) allowed.add(line);
  }
  let bad = 0;
  for (const e of byteSort([...actual])) {
    if (!allowed.has(e)) {
      process.stdout.write("新消费边（对外面扩张，须人工登记）: " + e + "\n");
      bad++;
    }
  }
  for (const e of byteSort([...allowed])) {
    if (!actual.has(e)) {
      process.stdout.write("过期边（已无此消费，须清理）: " + e + "\n");
      bad++;
    }
  }
  return bad;
}

const readLines = (p: string): string[] => {
  try {
    return fs.readFileSync(p, "utf8").split("\n");
  } catch (e) {
    fatal(`读 ${p}: ${errText(e)}`);
  }
};

export function runMain(argv: readonly string[]): number {
  try {
    return mainFlow(argv);
  } catch (e) {
    if (e instanceof ExitErr) return e.code;
    throw e;
  }
}

function mainFlow(argv: readonly string[]): number {
  noConsecutiveBlankLines("scripts/moonbit/surface_edges.txt");
  try {
    process.chdir("moonbit");
  } catch (e) {
    process.stderr.write(`chdir moonbit failed: ${errText(e)}\n`);
    throw new ExitErr(2);
  }

  let check = false;
  for (const a of argv) if (a === "-check") check = true;

  const moduleName = readModuleName();
  const pkgs = discoverPackages(moduleName);

  // provider 侧**全递归**：一级包 + 子包同入「无主判定」
  const pkgsMbti: string[] = [];
  // 等价 filepath.Glob("*/pkg.generated.mbti") + "*/*/pkg.generated.mbti"
  for (const e of fs.readdirSync(".", { withFileTypes: true })) {
    if (!e.isDirectory()) continue;
    const one = toSlash(path.join(e.name, "pkg.generated.mbti"));
    if (fs.existsSync(one)) pkgsMbti.push(one);
    for (const e2 of fs.readdirSync(e.name, { withFileTypes: true })) {
      if (!e2.isDirectory()) continue;
      const two = toSlash(path.join(e.name, e2.name, "pkg.generated.mbti"));
      if (fs.existsSync(two)) pkgsMbti.push(two);
    }
  }
  if (pkgsMbti.length === 0) fatal("未找到包接口面（须在 moonbit/ 下运行）");

  // 消费语料：所有 .mbt + README*.md
  const corpus: string[] = [];
  walkRepo(".", (full, base) => {
    if (base.endsWith(".mbt") || base.startsWith("README")) corpus.push(toSlash(full));
  });
  if (corpus.length === 0) fatal("消费语料为空");

  // 消费索引：provider 全名 → set(sym-path)；边集 consumer provider sym
  const used = new Map<string, Set<string>>();
  const usedEdges = new Set<string>();
  for (const f of corpus) {
    const data = fs.readFileSync(f, "utf8");
    const { vis, ambiguous, consumer } = visibilityFor(f, pkgs);
    for (const m of data.matchAll(RE_USE)) {
      const full = m[0];
      const sym = m[1] ?? "";
      // m[1] 形如 sym 或 Type::member——类型消费记 `T`，成员消费记 `T::m`
      const parts = sym.split("::", 2);
      const alias = full.slice(1, full.indexOf("."));
      if (ambiguous !== null && ambiguous.has(alias)) {
        fatal(`歧义别名 @${alias}.（${f}）——末段撞车的工作区包不止一个（如 L7 host 与 lexer/internal/host）；根 README 引用须消歧后过闸`);
      }
      const provider = vis.get(alias);
      if (provider === undefined) {
        fatal(`未知别名 @${alias}.（${f}，consumer=${consumer}）——不在所属包 moon.pkg 的可见 import 集；若属新形态（显式别名/新 scope）须先扩本闸`);
      }
      const set = used.get(provider) ?? new Set<string>();
      set.add(parts[0] as string);
      set.add(sym);
      used.set(provider, set);
      if (consumer !== provider) usedEdges.add(consumer + " " + provider + " " + (parts[0] as string));
    }
  }

  // 各包符号 → 可收判定；closureSig = 因 pub 签名引用而必须保持 pub 的类型
  const collectable = new Map<string, string[]>();
  const closureSig = new Map<string, string[]>();
  for (const mbti of pkgsMbti) {
    const pkg = moduleName + "/" + toSlash(path.dirname(mbti));
    const lines = readLines(mbti);

    // 第一遍：本包 pub 类型名
    const pubTypes = new Set<string>();
    for (const line of lines) {
      const m = RE_TYPE.exec(line);
      if (m !== null) pubTypes.add(m[1] ?? "");
    }
    // 第二遍：**引用计数**——pub 类型在本包 mbti 里除定义行外还有出现 ⇒ 签名闭包
    const occur = new Map<string, number>();
    for (const line of lines) {
      for (const t of pubTypes) {
        if (hasWord(line, t)) occur.set(t, (occur.get(t) ?? 0) + 1);
      }
    }
    // 第三遍：逐符号判定
    const pkgCollect: string[] = [];
    const pkgClosure: string[] = [];
    const usedPkg = used.get(pkg);
    for (const line of lines) {
      let name = "";
      let kind = "";
      const mm = RE_METHOD.exec(line);
      if (mm !== null) {
        name = mm[1] ?? "";
        kind = "type"; // 方法归属类型判定
      } else {
        const mf = RE_FN.exec(line);
        if (mf !== null) {
          name = mf[1] ?? "";
          kind = "fn";
        } else {
          const mt = RE_TYPE.exec(line);
          if (mt !== null) {
            name = mt[1] ?? "";
            kind = "type";
          } else {
            const mc = RE_CONST.exec(line);
            if (mc !== null) {
              name = mc[1] ?? "";
              kind = "const";
            } else continue;
          }
        }
      }
      if (usedPkg !== undefined && usedPkg.has(name)) continue;
      if (kind === "type" && (occur.get(name) ?? 0) > 1) {
        pkgClosure.push(name);
        continue;
      }
      pkgCollect.push(name);
    }
    collectable.set(pkg, dedupSorted(pkgCollect));
    closureSig.set(pkg, dedupSorted(pkgClosure));
  }

  if (!check) {
    // 默认模式与 -check 同强度（2026-10-04 假绿修正后单一真值）
    let total = 0;
    for (const pkg of sortedKeys(collectable)) {
      const syms = collectable.get(pkg) ?? [];
      if (syms.length === 0) continue;
      process.stdout.write(`${pkg}: ${syms.join(", ")}\n`);
      total += syms.length;
    }
    process.stdout.write(`moonbit_surface: ${total} 个无跨包消费 pub 符号（收面对象；对账 surface_allowlist.txt）\n`);
    let csTotal = 0;
    for (const pkg of sortedKeys(closureSig)) {
      const syms = closureSig.get(pkg) ?? [];
      if (syms.length === 0) continue;
      process.stdout.write(`[签名闭包·非收面] ${pkg}: ${syms.join(", ")}\n`);
      csTotal += syms.length;
    }
    process.stdout.write(`moonbit_surface: 另 ${csTotal} 个 pub 类型为签名闭包（保持 pub，不计入收面）\n`);
  }

  // 白名单双向对账
  const allow = new Set<string>();
  let allowText: string;
  try {
    allowText = fs.readFileSync("../scripts/moonbit/surface_allowlist.txt", "utf8");
  } catch {
    fatal("白名单缺失（../scripts/moonbit/surface_allowlist.txt）——先建白名单再 -check");
  }
  for (const raw of allowText.split("\n")) {
    const line = raw.trim();
    if (line !== "" && !line.startsWith("#")) allow.add(line);
  }
  let bad = 0;
  for (const pkg of sortedKeys(collectable)) {
    for (const sym of collectable.get(pkg) ?? []) {
      const key = pkg + " " + sym;
      if (!allow.has(key)) {
        process.stdout.write(`漏收: ${key}\n`);
        bad++;
      }
    }
  }
  for (const k of byteSort([...allow])) {
    const sp = k.indexOf(" ");
    if (sp >= 0) {
      const pkg = k.slice(0, sp);
      const sym = k.slice(sp + 1);
      const syms = collectable.get(pkg);
      if (syms === undefined || !syms.includes(sym)) {
        process.stdout.write(`过期白名单: ${k}（已消费或已收，须清理）\n`);
        bad++;
      }
    }
  }
  // 第二面闸：跨包消费边对账（两面证据全收集后统一红）
  const edgeBad = checkEdges(usedEdges);
  if (bad > 0 || edgeBad > 0) fatal(`对账不符（无主 ${bad} + 边 ${edgeBad}）`);
  process.stdout.write("moonbit_surface: check OK（可收清单与白名单一致 + 消费边与边清单一致）\n");
  return 0;
}

/** sort.Strings + 去连续重复（Go 版 `[:0]` 原地去重等价）。 */
function dedupSorted(xs: string[]): string[] {
  const sorted = byteSort(xs);
  const out: string[] = [];
  let prev = "";
  for (const s of sorted) {
    if (s !== prev) {
      out.push(s);
      prev = s;
    }
  }
  return out;
}

function sortedKeys(m: Map<string, string[]>): string[] {
  return byteSort([...m.keys()]);
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  process.exit(runMain(process.argv.slice(2)));
}
