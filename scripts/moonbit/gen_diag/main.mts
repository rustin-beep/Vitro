#!/usr/bin/env node
// gen_diag.mts —— 生成 vitro/engine/diag 包的机器单源部分（#273 存量 Go 重写批；
// 原 scripts/moonbit/gen_diag/gen_diag.go）。
//
// #39 真值源迁移（2026-10-05）：输入已从 Rust 冻结区 .rs 翻转为
// scripts/moonbit/diagnostics_data/{error_codes,catalog}.json 单源。
//
// **不迁范围（452 行，2026-10-23 裁定）**：原 Go 版的 legacy 对账臂
//（legacyReconcileDiag / parseArms / parseWhitelists / crossCheckWhitelists /
// parseCatalog / parseEntryBlocks / mustIntField / scanRustString / safeHead /
// mustStrField / mustStrArrayField / cmpCodeSets / entryCodes / equalInts /
// catalogSourceHash）与 -export-json 同步工具，全部依赖 `../native/…` 的 Rust
// 冻结区 .rs——该区已于 2026-10-05 工序④物理删除，Go 版每次运行只会走到
// 「legacy 源已删区（工序④），对账臂豁免」这一条 return。迁移植死代码无收益，
// 故整块不迁；证据 = gen_diag.go:257-272 的 nonePresent 分支 + 本仓无任何断言
// 依赖该行输出（CI 只看退出码）。
//
// 纪律（第一阶段计划 T2）：
//   - ErrorCode 枚举禁手抄——本脚本是唯一产出口；
//   - fail loud：任何解析失配 / 卡片数异常立即 exit 1，禁静默 default；
//   - 幂等：同源重复运行产物字节一致（无时间戳；源 JSON sha256 前 8 位随产物
//     落款——源变则产物变，配合 -check 构成漂移防线）；
//   - -check：产物经 moon fmt 定形后与现存文件逐字节比对，不一致 exit 1。
//
// 产物（moonbit 相对）：diag/error_code_gen.mbt +
// teaching/content_data/catalog_data_gen.mbt
//
// 用法：node scripts/moonbit/gen_diag/main.mts [-check] [-json D] [-out D]
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../../internal/capi.mts";
import { emitWithMoonFmt, makeFail, parseFlags } from "../../internal/genio.mts";

/** T2 基线：137→…→152（#214 W3084/W3085——缺 return 路径/隐式函数声明两教学点）→153（#212 W1023——#pragma/#line 忽略类指令降警告） */
const EXPECTED_ARMS = 153;
/** T2 基线：…→106（#178 E3083）→108（#214 W3084/W3085）→109（PR #284 审阅 P3：W1023 卡——#pragma/#line 忽略类指令学生高频，查卡不落空） */
const EXPECTED_CATALOG = 109;

interface Arm {
  name: string;
  code: number;
}
interface Entry {
  code: number;
  icon: string;
  title: string;
  explanation: string;
  common_causes: string[];
}

const fatal = makeFail("gen_diag: FAIL: ", 1);

/** 行尾归一（latin1 往返，字节保真）。 */
function toLF(b: Buffer): Buffer {
  return Buffer.from(b.toString("latin1").replace(/\r\n/g, "\n"), "latin1");
}

function sha8(b: Buffer): string {
  return crypto.createHash("sha256").update(b).digest("hex").slice(0, 8);
}

function validVariantName(name: string): boolean {
  if (name === "Unknown") return true;
  if (name.length < 7 || name[5] !== "_") return false;
  const h = name[0];
  if (h !== "E" && h !== "W" && h !== "H") return false;
  for (let i = 1; i <= 4; i++) {
    const c = name[i];
    if (c === undefined || c < "0" || c > "9") return false;
  }
  return name[6] !== "_";
}

function loadArms(raw: Buffer): Arm[] {
  let doc: { arms?: Arm[] };
  try {
    doc = JSON.parse(raw.toString("utf8")) as { arms?: Arm[] };
  } catch (e) {
    return fatal(`error_codes.json 解析失败: ${(e as Error).message}`);
  }
  const arms = doc.arms ?? [];
  const seen = new Map<number, string>();
  for (const a of arms) {
    const prev = seen.get(a.code);
    if (prev !== undefined) fatal(`编号 ${a.code} 重复：${prev} 与 ${a.name}`);
    if (!validVariantName(a.name)) {
      fatal(`臂名 "${a.name}" 不符 E/W/H 前缀规范——JSON 真源形态可疑`);
    }
    seen.set(a.code, a.name);
  }
  return arms;
}

function loadEntries(raw: Buffer): Entry[] {
  let doc: { entries?: Entry[] };
  try {
    doc = JSON.parse(raw.toString("utf8")) as { entries?: Entry[] };
  } catch (e) {
    return fatal(`catalog.json 解析失败: ${(e as Error).message}`);
  }
  const entries = doc.entries ?? [];
  const seen = new Set<number>();
  for (const e of entries) {
    if (seen.has(e.code)) fatal(`卡片码 ${e.code} 重复`);
    seen.add(e.code);
  }
  return entries;
}

/** 按 W/H 变体名前缀派生白名单（Unknown 哨兵除外）。 */
function deriveWhitelists(arms: Arm[]): { w: number[]; h: number[] } {
  const w: number[] = [];
  const h: number[] = [];
  for (const a of arms) {
    if (a.name === "Unknown") continue;
    const head = a.name[0];
    if (head === "W") w.push(a.code);
    else if (head === "H") h.push(a.code);
  }
  return { w, h };
}

function crossCheckCatalog(entries: Entry[], armCodes: Set<number>): void {
  for (const e of entries) {
    if (!armCodes.has(e.code)) {
      fatal(`卡片码 ${e.code} 不在 ErrorCode 枚举内——卡片源与枚举源失配`);
    }
  }
}

/** 按 MoonBit 字符串字面量规则转义。 */
export function escapeMbt(s: string): string {
  let out = "";
  for (const ch of s) {
    if (ch === "\\") out += "\\\\";
    else if (ch === '"') out += '\\"';
    else if (ch === "\n") out += "\\n";
    else if (ch === "\t") out += "\\t";
    else if (ch === "\r") out += "\\r";
    else out += ch;
  }
  return out;
}

function severityOf(a: Arm, wSet: Set<number>, hSet: Set<number>): string {
  if (wSet.has(a.code)) return "Warning";
  if (hSet.has(a.code)) return "Hint";
  return "Error";
}

function langOf(a: Arm): string {
  // 5xxx（C# 预留段）→ CSharp 先行落位；现库无 5xxx（审阅 P2-3）
  if (a.code >= 5000) return "CSharp";
  if (a.code >= 4000) return "Cpp";
  return "C";
}

function prefixOf(a: Arm, wSet: Set<number>, hSet: Set<number>): string {
  if (wSet.has(a.code)) return "W";
  if (hSet.has(a.code)) return "H";
  return "E";
}

/** 与 moon fmt 一致的 80 列贪心装行（前缀 4 空格，元素 "N," 逗号+空格分隔）。 */
export function wrapInts(nums: number[]): string {
  const lines: string[] = [];
  let cur = "    ";
  for (const n of nums) {
    const tok = `${n},`;
    if (cur !== "    " && cur.length + 1 + tok.length > 84) {
      lines.push(cur);
      cur = "    ";
    }
    cur += cur === "    " ? tok : " " + tok;
  }
  if (cur !== "    ") lines.push(cur);
  return lines.join("\n");
}

export function renderErrorCode(
  arms: Arm[],
  w: number[],
  h: number[],
  entries: Entry[],
  srcHash: string,
): string {
  const wSet = new Set(w);
  const hSet = new Set(h);
  const entrySet = new Set(entries.map((e) => e.code));
  const sorted = [...arms].sort((a, b) => a.code - b.code);

  let b = "";
  b +=
    "// @generated by scripts/moonbit/gen_diag —— 禁手改（git/diff 工具链按 @generated 识别；再生成：cd 仓库根 && go run ./scripts/moonbit/gen_diag）。\n" +
    `// 源：scripts/moonbit/diagnostics_data/error_codes.json（#39 迁出冻结区；sha256/${srcHash}）\n` +
    "// 基线：153 臂 / catalog 109 条（漂移时本脚本 fail loud；随 expectedArms/expectedCatalog 连坐更新）。\n\n" +
    "///|\n" +
    "/// 诊断错误码（153 臂，禁手抄，T2 纪律；基线数随批在 gen_diag.go expectedArms 更新）。\n" +
    "/// 段位：1xxx 词法 / 2xxx 语法 / 3xxx 语义 / 4xxx C++ 专属。\n" +
    "/// severity 由 W/H 白名单（与变体前缀双向对账）决定；lang 按 4xxx 段位。\n" +
    "pub(all) enum ErrorCode {\n";
  for (const a of sorted) b += `  ${a.name}\n`;
  b += "} derive(Debug, Eq, Hash, Compare)\n";

  // #54 A2：0079 显式提升声明（implicit_impl_as_method 将被工具链移除——
  // 短名形态零 moon.pkg 连坐；生成物侧由本模板单源）
  b +=
    "\npub extend ErrorCode with Debug::{to_repr}\n" +
    "\npub extend ErrorCode with Eq::{not_equal, equal}\n" +
    "\npub extend ErrorCode with Hash::{hash, hash_combine}\n" +
    "\npub extend ErrorCode with Compare::{op_lt, op_le, op_ge, compare, op_gt}\n";

  b +=
    "\n///|\n" +
    "/// 编号（穷尽 match，无下划线兜底——增删臂即编译红）。\n" +
    "pub fn ErrorCode::code(self : ErrorCode) -> Int {\n  match self {\n";
  for (const a of sorted) b += `    ${a.name} => ${a.code}\n`;
  b += "  }\n}\n";

  b +=
    "\n///|\n" +
    "/// 严重级（穷尽；W 白名单 11 码 / H 白名单 1 码，生成时与变体前缀双向对账——\n" +
    "/// P3 语义单源：W/H 数值区间与 E 交织，不可按数值段判定）。\n" +
    "pub fn ErrorCode::severity(self : ErrorCode) -> Severity {\n  match self {\n";
  for (const a of sorted) b += `    ${a.name} => ${severityOf(a, wSet, hSet)}\n`;
  b += "  }\n}\n";

  b +=
    "\n///|\n" +
    "/// 语言域（穷尽）：Cpp = 仅 C++ 形态触发（4xxx 段）；C = C 共通域\n" +
    "/// （C++ 中的 C 子集同样触发）。\n" +
    "pub fn ErrorCode::lang(self : ErrorCode) -> SourceLang {\n  match self {\n";
  for (const a of sorted) b += `    ${a.name} => ${langOf(a)}\n`;
  b += "  }\n}\n";

  b +=
    "\n///|\n" +
    "/// 变体名（与 Rust 逐字一致——稳定标识，诊断序列差分锚的 key）。\n" +
    "pub fn ErrorCode::name(self : ErrorCode) -> String {\n  match self {\n";
  for (const a of sorted) {
    const line = `    ${a.name} => "${a.name}"`;
    // 与 moon fmt 折行规范一致（>80 列折值到下一行），避免 fmt 与 gen 互踩。
    // 行内容全 ASCII，故 .length（UTF-16 code unit）== Go len（字节）。
    b += line.length > 80 ? `    ${a.name} =>\n      "${a.name}"\n` : `${line}\n`;
  }
  b += "  }\n}\n";

  b +=
    "\n///|\n" +
    "/// 显示码串（P3 段位前缀单源：E1001 / W3053 / H3057——与 Rust\n" +
    "/// code_prefix + 码值拼接同形）。\n" +
    "pub fn ErrorCode::display_code(self: ErrorCode) -> String {\n  match self {\n";
  for (const a of sorted) b += `    ${a.name} => "${prefixOf(a, wSet, hSet)}${a.code}"\n`;
  b += "  }\n}\n";

  b +=
    "\n///|\n" +
    "/// 全量清单（139，编号升序）——覆盖率断言与差分遍历的载体。\n" +
    "pub fn ErrorCode::all() -> Array[ErrorCode] {\n  [\n";
  for (const a of sorted) b += `    ${a.name},\n`;
  b += "  ]\n}\n";

  b +=
    "\n///|\n" +
    "/// 编号 → 码；未知编号返回 None。\n" +
    "pub fn ErrorCode::from_code(value : Int) -> ErrorCode? {\n  match value {\n";
  for (const a of sorted) b += `    ${a.code} => Some(${a.name})\n`;
  b += "    _ => None\n  }\n}\n";

  const withC: number[] = [];
  const withoutC: number[] = [];
  for (const a of sorted) (entrySet.has(a.code) ? withC : withoutC).push(a.code);
  b +=
    "\n///|\n" +
    "/// 有教学卡片的码清单（升序）。\n" +
    "pub fn catalog_codes() -> Array[Int] {\n  [\n" +
    wrapInts(withC) +
    "\n  ]\n}\n";
  b +=
    "\n///|\n" +
    "/// 无卡片码清单（升序；含 Unknown=0）——「码无卡片」可断言清单（T2）。\n" +
    "pub fn codes_without_catalog() -> Array[Int] {\n  [\n" +
    wrapInts(withoutC) +
    "\n  ]\n}\n";
  return b;
}

function causesLit(causes: string[]): string {
  return causes.map((c) => `"${escapeMbt(c)}"`).join(", ");
}

export function renderCatalog(entries: Entry[], srcHash: string, catalogHash: string): string {
  let b = "";
  b +=
    "// @generated by scripts/moonbit/gen_diag —— 禁手改（git/diff 工具链按 @generated 识别；再生成：cd 仓库根 && go run ./scripts/moonbit/gen_diag）。\n" +
    `// 源：scripts/moonbit/diagnostics_data/catalog.json（#39 迁出冻结区；枚举源 sha256/${srcHash}；卡片源 sha256/${catalogHash}，行尾归一）\n` +
    `// 基线：${entries.length} 条（漂移时本脚本 fail loud）。#130 批③b（2026-10-17）：卡片\n` +
    "// 文本数据落 teaching/content_data（lean 拆包——不进 wasm 产物）；\n" +
    "// diag 侧 catalog() 查 catalog_texts 载体（本表经 install_baked 装载）。\n\n" +
    "///|\n" +
    "/// 诊断卡片数据表（键=码，值域见 @diag.catalog_codes；跨包构造经\n" +
    "/// CatalogEntry::of 契约入口）。\n" +
    "pub let catalog_data : Map[Int32, @diag.CatalogEntry] = {\n";
  // 码升序（与装载段发射的字典序同构——四位数码位域数值序=字典序）
  const sorted = [...entries].sort((a, b2) => a.code - b2.code);
  for (const e of sorted) {
    // 爆开形态与 moon fmt 输出逐字节一致：fmt 宽度按 UTF-8 **字节**计
    //（中文 3 字节），causes 整行 >84 字节即爆开（字符串字面量不可折）。
    // 此处必须 Buffer.byteLength——JS 的 .length 是 UTF-16 code unit。
    const causes = causesLit(e.common_causes ?? []);
    const causesLine = `    [${causes}],`;
    const causesForm =
      Buffer.byteLength(causesLine, "utf8") <= 84
        ? causesLine
        : `    [\n      ${causes},\n    ],`;
    b +=
      `  ${e.code}: @diag.CatalogEntry::of(\n` +
      `    ${e.code},\n` +
      `    "${escapeMbt(e.icon)}",\n` +
      `    "${escapeMbt(e.title)}",\n` +
      `    "${escapeMbt(e.explanation)}",\n` +
      `${causesForm}\n  ),\n`;
  }
  b += "}\n";
  return b;
}

function main(): void {
  const root = projectRoot();
  const moonbit = path.join(root, "moonbit");
  const fail = fatal;

  const args = parseFlags(
    process.argv.slice(2),
    { bool: ["-check", "--check"], value: ["-json", "-out"] },
    fail,
  );
  if (args.rest.length > 0) fail(`未知参数 ${args.rest[0] ?? ""}`);
  const check = args.has("-check", "--check");

  let jsonDir = path.join(root, "scripts/moonbit/diagnostics_data");
  const jsonArg = args.value("-json");
  if (jsonArg !== undefined) jsonDir = path.resolve(moonbit, jsonArg);

  let outDir = path.join(moonbit, "diag");
  const outArg = args.value("-out");
  if (outArg !== undefined) outDir = path.resolve(moonbit, outArg);

  // ---- ① 装载 JSON 真源（#39 翻转，2026-10-05）----
  // 行尾归一后取 sha：工作区 LF/CRLF 形态（git autocrlf、checkout 差异）不得
  // 影响产物落款——否则换行尾即 -check 假红。
  let ecRaw: Buffer;
  try {
    ecRaw = fs.readFileSync(path.join(jsonDir, "error_codes.json"));
  } catch (e) {
    return fail(`读 JSON 真源失败 error_codes.json: ${(e as Error).message}`);
  }
  ecRaw = toLF(ecRaw);
  const srcHash = sha8(ecRaw);

  let catRaw: Buffer;
  try {
    catRaw = fs.readFileSync(path.join(jsonDir, "catalog.json"));
  } catch (e) {
    return fail(`读 JSON 真源失败 catalog.json: ${(e as Error).message}`);
  }
  catRaw = toLF(catRaw);
  const catalogHash = sha8(catRaw);

  const arms = loadArms(ecRaw);
  if (arms.length !== EXPECTED_ARMS) {
    fatal(
      `枚举臂数 ${arms.length} ≠ 基线 ${EXPECTED_ARMS}——JSON 真源已变更，请人工核对后更新 EXPECTED_ARMS 并登记差异`,
    );
  }
  const { w, h } = deriveWhitelists(arms);

  const entries = loadEntries(catRaw);
  if (entries.length !== EXPECTED_CATALOG) {
    fatal(
      `卡片数 ${entries.length} ≠ 基线 ${EXPECTED_CATALOG}——JSON 真源已变更，请人工核对后更新 EXPECTED_CATALOG 并登记差异`,
    );
  }
  crossCheckCatalog(entries, new Set(arms.map((a) => a.code)));

  const genCode = renderErrorCode(arms, w, h, entries, srcHash);
  const genCatalog = renderCatalog(entries, srcHash, catalogHash);

  emitWithMoonFmt({
    root,
    check,
    fail,
    driftHint: "源已变更未再生成（cd 仓库根 && node scripts/moonbit/gen_diag/main.mts）",
    products: [
      { rel: path.relative(moonbit, path.join(outDir, "error_code_gen.mbt")), content: genCode },
      // #130 批③b：卡片数据产物迁 content_data（lean 拆包）
      { rel: "teaching/content_data/catalog_data_gen.mbt", content: genCatalog },
    ],
  });

  if (check) {
    process.stdout.write("gen_diag: check OK（产物与 JSON 真源一致，2 文件未漂移）\n");
  } else {
    process.stdout.write("gen_diag: 生成完成（2 文件）\n");
  }
}

// 入口守卫：被 node:test import 时只取纯函数，不落盘
if (
  process.argv[1] !== undefined &&
  pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url
) {
  main();
}
