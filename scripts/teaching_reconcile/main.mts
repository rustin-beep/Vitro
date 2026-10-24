#!/usr/bin/env node
// teaching_reconcile —— 教学资产码表对账闸（Go→.mts 重写，refs #273）。
//
// 原 Go 版（scripts/teaching_reconcile/main.go，273 行）判定面逐条保留：
// 三向对账的批 A 最小形态（两向 + J9 自检；第三腿「协议码表」待 #128
// 替代裁定的双模式协议增量落地后接入，缺席不红）：
//
//   ① 内容键集：moonbit/teaching/content/*.md 的 `## ` 节标题
//   ② 引擎装配点字面量：
//        trap      moonbit/host/host_memory.mbt     trap_messages.get("KEY")
//        sugg      moonbit/teaching/assets/map.mbt  m.set("KEY",
//        builtin   moonbit/typeck/**.mbt            builtin_notes.get("KEY")
//
// 判据：① ≡ ②（双向：孤儿内容 / 装配缺键都红——装配缺键即运行期
// get().unwrap() panic 的 CI 前置化）。suggestions 另有编译期闸
// （map.mbt 43 臂穷尽 match 对生成枚举），本闸仍查其字面量防双源漂移。
// 基线计数（45/43/12）一并校验，整表漂移 fail loud。
//
// 用法（仓库根）：
//   node scripts/teaching_reconcile/main.mts            # 校验
//   node scripts/teaching_reconcile/main.mts -v         # 逐键打印
//   node scripts/teaching_reconcile/main.mts -selftest  # J9 注入证红
//
// 扫描深度口径（与 Go 版一致，勿"顺手"改成递归）：装配点 / 覆盖域的目录
// 只扫**一层** .mbt（不含 .mbti），子目录不进——Go 版 walk 对目录只列条目、
// 对子目录不递归，改动即扩面。
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../internal/capi.mts";

const RE_HEADING = /^## ([A-Za-z_0-9]+)\s*$/;
const RE_TRAP_GET = /trap_messages\.get\("([A-Za-z_0-9]+)"\)/g;
const RE_SUGG_SET = /m\.set\("([a-z_0-9]+)",/g;
// #130 批③a：typeck 消费面 graceful 化后形态 = note_count("KEY"/
// note_param("KEY"（原 @assets.builtin_notes.get("KEY").unwrap() 直查
// 不再在场——提取器随装配形态同步，键集判据不变）
const RE_BUILTIN = /(?:builtin_notes\.get|note_count|note_param)\("([A-Za-z_0-9]+)"/g;
const RE_RENDER_VAR = /render_var_section\("([A-Za-z_0-9]+)"/g;
const RE_TPL = /\btpl\("([A-Za-z_0-9]+)"/g;
const RE_RND = /\brnd\("([A-Za-z_0-9]+)"/g;

export interface Site {
  paths: string[];
  res: RegExp[];
}

export interface Pair {
  md: string;
  sites: Site[];
  consumerDirs: string[];
  base: number;
  label: string;
}

/** 装配点矩阵：trap 分散三目录、四种调用形态（get / render_var_section /
 *  tpl / rnd——字面量经包装函数流入 get(key)）。出现第 5 种形态时未知键会以
 *  「孤儿内容键」红牌自曝，逼本矩阵扩形（fail loud）。 */
export function pairs(): Pair[] {
  const trapSite: Site = {
    paths: ["moonbit/host", "moonbit/vm", "moonbit/time_travel"],
    res: [RE_TRAP_GET, RE_RENDER_VAR, RE_TPL, RE_RND],
  };
  return [
    {
      md: "moonbit/teaching/content/trap_messages.md",
      label: "trap",
      base: 45,
      sites: [trapSite],
      consumerDirs: ["moonbit/host", "moonbit/vm", "moonbit/time_travel"],
    },
    {
      md: "moonbit/teaching/content/suggestions.md",
      label: "suggestions",
      base: 43,
      sites: [{ paths: ["moonbit/teaching/content_data/map_install.mbt"], res: [RE_SUGG_SET] }],
      consumerDirs: [],
    },
    {
      md: "moonbit/teaching/content/builtin_notes.md",
      label: "builtin_notes",
      base: 12,
      sites: [{ paths: ["moonbit/typeck"], res: [RE_BUILTIN] }],
      consumerDirs: ["moonbit/typeck"],
    },
  ];
}

/** 相对路径按仓库根解析（不 chdir——避免库函数被 import 时污染进程 cwd）。 */
function abs(p: string): string {
  return path.isAbsolute(p) ? p : path.join(projectRoot(), p);
}

function die(msg: string): never {
  process.stderr.write("[teaching_reconcile] FAIL: " + msg + "\n");
  process.exit(1);
}

/** 字节序排序（Go sort.Strings 口径；键集全为 ASCII，与默认序等价但显式声明）。 */
export function byteSort(keys: Iterable<string>): string[] {
  return [...keys].sort((a, b) => Buffer.compare(Buffer.from(a, "utf8"), Buffer.from(b, "utf8")));
}

/** 读真源的 `## ` 节标题键集（含重复检查）。 */
export function contentKeys(md: string): Set<string> {
  let raw: string;
  try {
    raw = fs.readFileSync(abs(md), "utf8");
  } catch (e) {
    die(`读真源失败 ${md}: ${e instanceof Error ? e.message : String(e)}`);
  }
  const out = new Set<string>();
  for (const line of raw.split(/\r?\n/)) {
    const m = RE_HEADING.exec(line);
    if (m !== null) {
      const k = m[1] ?? "";
      if (out.has(k)) die(`${md}: 节键 "${k}" 重复`);
      out.add(k);
    }
  }
  if (out.size === 0) die(`${md}: 未解析到任何节键（空集不得绿）`);
  return out;
}

/** 目录或文件 → .mbt 内容清单（目录只扫一层，见头注）。 */
function mbtFiles(p: string): string[] {
  let st: fs.Stats;
  try {
    st = fs.statSync(abs(p));
  } catch (e) {
    die(`读装配点失败 ${p}: ${e instanceof Error ? e.message : String(e)}`);
  }
  if (!st.isDirectory()) return [p];
  const out: string[] = [];
  for (const name of fs.readdirSync(abs(p)).sort()) {
    if (name.endsWith(".mbt") && !name.endsWith(".mbti")) out.push(path.join(p, name));
  }
  return out;
}

/** 收装配点字面量（目录则扫一层 .mbt；目录×正则全组合取并）。 */
export function siteKeys(s: Site): Set<string> {
  const out = new Set<string>();
  for (const p of s.paths) {
    for (const re of s.res) {
      for (const file of mbtFiles(p)) {
        let data: string;
        try {
          data = fs.readFileSync(abs(file), "utf8");
        } catch (e) {
          die(`读装配点失败 ${file}: ${e instanceof Error ? e.message : String(e)}`);
        }
        for (const m of data.matchAll(re)) out.add(m[1] ?? "");
      }
    }
  }
  if (out.size === 0) die(`装配点 [${s.paths.join(" ")}] 未提取到任何字面量（提取器失效或装配点漂移）`);
  return out;
}

/** 单组对账：返回失败明细（空数组 = 通过）。 */
export function reconcile(p: Pair, verbose: boolean): string[] {
  const fails: string[] = [];
  const content = contentKeys(p.md);
  const siteSet = new Set<string>();
  for (const s of p.sites) for (const k of siteKeys(s)) siteSet.add(k);
  if (content.size !== p.base) {
    fails.push(`${p.label}: 内容条数 ${content.size} ≠ 基线 ${p.base}（整表漂移须人工核对）`);
  }
  // 装配缺键：装配点有、真源无
  for (const k of byteSort(siteSet)) {
    if (!content.has(k)) {
      fails.push(`${p.label}: 装配缺键 "${k}"（装配点有、真源无——运行期 get().unwrap() 必 panic）`);
    }
  }
  // 覆盖判据：内容键须以 "K" 字面量出现在消费域（排版无关——多行调用/
  // 拼接碎片化都会以孤儿红牌自曝，逼新形态登记进本闸）。
  if (p.consumerDirs.length > 0) {
    const chunks: string[] = [];
    for (const d of p.consumerDirs) {
      for (const file of mbtFiles(d)) {
        try {
          chunks.push(fs.readFileSync(abs(file), "utf8"));
        } catch (e) {
          die(`读覆盖域失败 ${file}: ${e instanceof Error ? e.message : String(e)}`);
        }
      }
    }
    const blob = chunks.join("");
    for (const k of byteSort(content)) {
      if (!blob.includes(`"${k}"`)) {
        fails.push(
          `${p.label}: 孤儿内容键 "${k}"（真源有、消费域无字面量——死内容或新键构造形态未登记）`,
        );
      }
    }
  }
  if (verbose) {
    for (const k of byteSort(content)) process.stdout.write(`[teaching_reconcile] ✓ ${p.label} ${k}\n`);
  }
  return fails;
}

/** J9：注入假装配键，断言双向判据必红（闸自身体检）。 */
export function selftest(): void {
  const p = pairs()[0]!;
  const content = contentKeys(p.md);
  const siteSet = new Set<string>(siteKeys(p.sites[0]!));
  siteSet.add("strng-typo-j9"); // 注入假装配键
  let red = false;
  for (const k of siteSet) if (!content.has(k)) red = true;
  if (!red) die("J9 自检失败：假装配键未被捕获——双向判据已失效");
  process.stdout.write("[teaching_reconcile] J9 自检 OK：假装配键注入被捕获\n");
}

export function main(argv: string[]): number {
  let verbose = false;
  let self = false;
  for (const a of argv) {
    if (a === "-v") verbose = true;
    else if (a === "-selftest" || a === "--selftest") self = true;
    else {
      // 用法错 = exit 2（Go flag 包同口径）
      process.stderr.write(`[teaching_reconcile] 未知参数 ${JSON.stringify(a)}（用法: teaching_reconcile [-v] [-selftest]）\n`);
      return 2;
    }
  }
  // 前置：必须在仓库内跑（projectRoot 找不到即 exit 2）——不 chdir，路径按 root 解析。
  projectRoot();
  if (self) {
    selftest();
    return 0;
  }
  const fails: string[] = [];
  for (const p of pairs()) fails.push(...reconcile(p, verbose));
  if (fails.length > 0) {
    for (const f of fails) process.stderr.write("[teaching_reconcile] ✗ " + f + "\n");
    die(`${fails.length} 项判据未过`);
  }
  process.stdout.write(
    "[teaching_reconcile] 全部通过：trap/suggestions/builtin_notes 内容键 ≡ 装配点字面量\n",
  );
  return 0;
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  process.exit(main(process.argv.slice(2)));
}
