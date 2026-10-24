#!/usr/bin/env node
// catalog_closure.mts —— 诊断码 ↔ 教学卡双向闭合闸（#256 建议 3 / #261 建议 5，
// 2026-10-24 建）。两套清单（error_codes.json 臂 + catalog.json 卡）各自演进的
// 结构性缺口由此闸机判拦截——正向（引擎可产码无卡，下游按码查卡落空）与
// 反向（卡永不触发，下游预渲染错误清单混入死码）任一即红。
//
// 规则外置 rules.json（prod_no_card_whitelist / card_no_prod_whitelist——
// 条目必须带 reason，白名单是债不是自由门）。
//
// 生产点扫描口径（两类形态并集，2026-10-24 摸底实测收敛）：
//   - 形态 A（诊断面）：`[EWH]\d{4}_VariantName` 枚举变体引用——引擎产诊断
//     走枚举构造器，变体名内嵌码号；
//   - 形态 B（trap 面）：`"E\d{4}"` 字符串字面量——#261 起 trap 文案首段与
//     trap_code 赋值均为带码字面量。
// 扫描面：moonbit/**/*.mbt + *.mbt.md，排除 _build/、*_gen.mbt（码表/卡片
// 数据定义自身）、*_wbtest.mbt / *_test.mbt（测试面非生产点）。
//
// 四规则：
//   R1 forward：P ⊆ C ∪ prod_no_card_whitelist
//   R2 reverse：C ⊆ P ∪ card_no_prod_whitelist
//   R3 prefix：catalog 卡码前缀（臂名派生）须与同号臂一致，同号异前缀双臂即红
//   R4 arm：catalog 卡码须有对应码臂（幽灵卡即红）
//
// fail loud：任何规则违例 exit 1 逐条列出（码 + 定位 + 白名单建议）；
// 白名单条目零命中（僵尸条目）同样红——白名单是待清偿的债，源码清了条目没删即红。
//
// 用法：node scripts/catalog_closure/main.mts
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../internal/capi.mts";

interface ArmEntry {
  name: string;
  code: number;
}
interface CodesFile {
  arms: ArmEntry[];
}
interface CatalogEntry {
  code: number;
}
interface CatalogFile {
  entries: CatalogEntry[];
}
interface Rules {
  prod_no_card_whitelist: Record<string, string>;
  card_no_prod_whitelist: Record<string, string>;
}

/** 生产点：码 → 定位列表（file:line 形态，供红讯直指） */
type ProdMap = Map<string, string[]>;

function readJson<T>(rel: string): T {
  const p = path.join(projectRoot(), rel);
  return JSON.parse(fs.readFileSync(p, "utf8")) as T;
}

/** 扫描 moonbit/ 源码收集生产码（两类形态）。
 *
 * 审阅 P3-3（2026-10-24）：**注释不算生产点**——匹配前剥行注释与块注释
 * （跨行状态机，行号保持）；`.mbt.md` 只扫代码围栏内（markdown 正文叙述
 * 不算）。已知限制：字符串字面量含 `//` 的行尾会被误剥（URL 等——收紧
 * 方向的漏报，R1 少抓优于注释假绿）。
 */
export function scanProduction(root: string): ProdMap {
  const variantPat = /\b([EWH])(\d{4})_[A-Za-z]\w*/g;
  const literalPat = /"([EWH])(\d{4})"/g;
  const out: ProdMap = new Map();
  const add = (key: string, loc: string): void => {
    const list = out.get(key) ?? [];
    list.push(loc);
    out.set(key, list);
  };
  const scanLines = (rel: string, lines: string[]): void => {
    let inBlock = false;
    for (let i = 0; i < lines.length; i++) {
      let line = lines[i] ?? "";
      if (inBlock) {
        const end = line.indexOf("*/");
        if (end < 0) continue;
        line = line.slice(end + 2);
        inBlock = false;
      }
      const blockStart = line.indexOf("/*");
      const lineStart = line.indexOf("//");
      if (blockStart >= 0 && (lineStart < 0 || blockStart < lineStart)) {
        const head = line.slice(0, blockStart);
        const rest = line.slice(blockStart + 2);
        const end = rest.indexOf("*/");
        line = end >= 0 ? head + rest.slice(end + 2) : head;
        if (end < 0) inBlock = true;
      } else if (lineStart >= 0) {
        line = line.slice(0, lineStart);
      }
      for (const m of line.matchAll(variantPat)) {
        add(`${m[1]}${m[2]}`, `${rel}:${i + 1}`);
      }
      for (const m of line.matchAll(literalPat)) {
        add(`${m[1]}${m[2]}`, `${rel}:${i + 1}`);
      }
    }
  };
  const walk = (dir: string): void => {
    for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, ent.name);
      if (ent.isDirectory()) {
        if (ent.name === "_build") continue;
        walk(p);
        continue;
      }
      const isMbt = ent.name.endsWith(".mbt");
      const isMbtMd = ent.name.endsWith(".mbt.md");
      if (!isMbt && !isMbtMd) continue;
      if (isMbt && ent.name.endsWith("_gen.mbt")) continue;
      if (ent.name.endsWith("_wbtest.mbt") || ent.name.endsWith("_test.mbt")) {
        continue;
      }
      const text = fs.readFileSync(p, "utf8");
      const rel = path.relative(root, p);
      if (isMbt) {
        scanLines(rel, text.split("\n"));
        continue;
      }
      // .mbt.md：只扫 ``` 代码围栏内（markdown 正文叙述不算生产点）
      const all = text.split("\n");
      const fenced: string[] = [];
      let inFence = false;
      for (const l of all) {
        if (l.trimStart().startsWith("```")) {
          inFence = !inFence;
          continue;
        }
        if (inFence) fenced.push(l);
      }
      // 围栏行号已失真（压缩后重排）——定位标注为文件级（正讯以此为准）
      scanLines(`${rel}（代码围栏）`, fenced);
    }
  };
  walk(path.join(root, "moonbit"));
  return out;
}

/** 码 → 展示前缀（"E0"/"W1018" 形态；E0 = Unknown 兜底特判）。 */
function codeKey(prefix: string, code: number): string {
  return `${prefix}${code}`;
}

export interface Violation {
  rule: string;
  message: string;
}

/** 主判定：返回违例列表（空 = 绿）。导出供测试注入突变。 */
export function checkClosure(
  codes: CodesFile,
  catalog: CatalogFile,
  rules: Rules,
  prod: ProdMap,
): Violation[] {
  const viol: Violation[] = [];
  const armsByCode = new Map<number, ArmEntry[]>();
  for (const a of codes.arms) {
    const list = armsByCode.get(a.code) ?? [];
    list.push(a);
    armsByCode.set(a.code, list);
  }
  // catalog 码键（前缀从同号唯一臂派生；E0 特判）
  const cardKeys = new Map<string, number>();
  for (const e of catalog.entries) {
    if (e.code === 0) {
      cardKeys.set("E0", 0);
      continue;
    }
    const sameCode = armsByCode.get(e.code) ?? [];
    if (sameCode.length === 0) {
      viol.push({
        rule: "R4-arm",
        message: `卡 ${e.code} 无对应码臂（幽灵卡）——catalog.json 与 error_codes.json 失配`,
      });
      continue;
    }
    if (sameCode.length > 1) {
      viol.push({
        rule: "R3-prefix",
        message: `码 ${e.code} 存在同号异前缀双臂（${sameCode.map((a) => a.name).join(" / ")}）——catalog 数字键撞键`,
      });
      continue;
    }
    const arm = sameCode[0];
    if (arm === undefined) continue;
    cardKeys.set(codeKey(arm.name.slice(0, 1), e.code), e.code);
  }
  // R1 forward
  for (const [key, locs] of [...prod.entries()].sort(([a], [b]) => (a < b ? -1 : 1))) {
    if (cardKeys.has(key)) continue;
    if (key in rules.prod_no_card_whitelist) continue;
    viol.push({
      rule: "R1-forward",
      message: `引擎生产码 ${key} 无教学卡——下游按码查卡落空；定位 ${locs.slice(0, 3).join(" ")}；补卡或白名单登记理由`,
    });
  }
  // R2 reverse
  for (const key of [...cardKeys.keys()].sort()) {
    if (prod.has(key)) continue;
    if (key in rules.card_no_prod_whitelist) continue;
    viol.push({
      rule: "R2-reverse",
      message: `卡 ${key} 引擎零生产点（永不触发）——下游预渲染错误清单混入死码；退役或白名单登记理由`,
    });
  }
  // 白名单僵尸条目（零命中即红——白名单是债）
  for (const key of Object.keys(rules.prod_no_card_whitelist)) {
    if (!prod.has(key)) {
      viol.push({
        rule: "R5-stale-whitelist",
        message: `prod_no_card_whitelist 条目 ${key} 已零命中（生产点消失）——源码已清，条目应删`,
      });
    }
  }
  for (const key of Object.keys(rules.card_no_prod_whitelist)) {
    if (!cardKeys.has(key)) {
      viol.push({
        rule: "R5-stale-whitelist",
        message: `card_no_prod_whitelist 条目 ${key} 已零命中（卡不存在）——条目应删`,
      });
    }
  }
  return viol;
}

function main(): void {
  const root = projectRoot();
  const codes = readJson<CodesFile>(
    path.join("scripts", "moonbit", "diagnostics_data", "error_codes.json"),
  );
  const catalog = readJson<CatalogFile>(
    path.join("scripts", "moonbit", "diagnostics_data", "catalog.json"),
  );
  const rules = readJson<Rules>(path.join("scripts", "catalog_closure", "rules.json"));
  const prod = scanProduction(root);
  const viol = checkClosure(codes, catalog, rules, prod);
  const staleProdWl = Object.keys(rules.prod_no_card_whitelist).filter(
    (k) => !prod.has(k),
  ).length;
  console.log(
    `[catalog_closure] 生产码 ${prod.size} / 卡 ${catalog.entries.length} 臂 ${codes.arms.length}；白名单 prod=${Object.keys(rules.prod_no_card_whitelist).length}（僵尸 ${staleProdWl}） card=${Object.keys(rules.card_no_prod_whitelist).length}`,
  );
  if (viol.length > 0) {
    for (const v of viol) {
      console.error(`[catalog_closure][${v.rule}] ${v.message}`);
    }
    process.exit(1);
  }
  console.log("[catalog_closure] 双向闭合 + 撞键防全绿");
}

const invokedDirectly =
  process.argv[1] !== undefined &&
  pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  main();
}
