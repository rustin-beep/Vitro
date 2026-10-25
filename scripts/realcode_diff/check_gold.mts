// check_gold —— 仓内金样本静态合规闸（CI hygiene，四道 + 三向对账）。
//
// 口径（与 Go 版逐条复刻）：
//   ① 格式：_meta 含 source_fork/source_commit/total；files 字段类型
//   ② 零渗漏：条目七键白名单 + 字符串值限长 + 诊断码形态 + Σ码 == errs/warns
//   ③ _meta ↔ files 重算：total / 分桶计数
//   ④ corpora.json 三向对账：语料目录 ↔ 登记表 ↔ 金样本键集/total/license_file
// 任何不符即 fail loud（exit 2）。
import fs from "node:fs";
import path from "node:path";
import { fatal } from "../internal/capi.mts";
import { byteSort } from "../internal/text.mts";

const checkRunWords = new Set([
  "",
  "match",
  "mismatch",
  "clang_build_fail",
  "clang_timeout",
  "clang_run_fail",
  "rand_diff_match",
  "rand_diff",
]);

const checkLayerWords = new Set(["", "ok", "lex", "parse", "typeck"]);

const entryKeys = new Set(["clang_ok", "gcc_ok", "vitro_errs", "vitro_warns", "codes", "layer", "run"]);

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function goFmt(v: unknown): string {
  if (v === undefined || v === null) return "<nil>";
  if (typeof v === "string") return v;
  if (typeof v === "number" || typeof v === "boolean") return String(v);
  return JSON.stringify(v);
}

function fileExists(p: string): boolean {
  try {
    return fs.statSync(p).isFile();
  } catch {
    return false;
  }
}

function dirExists(p: string): boolean {
  try {
    return fs.statSync(p).isDirectory();
  } catch {
    return false;
  }
}

function isAllDigits(s: string): boolean {
  if (s === "") return false;
  for (const ch of s) {
    if (ch < "0" || ch > "9") return false;
  }
  return true;
}

/** 单金样本合规校验；返回文件条目数。 */
export function checkOneGold(filePath: string): number {
  let raw: string;
  try {
    raw = fs.readFileSync(filePath, "utf8");
  } catch (e) {
    fatal(`金样本缺失: ${e instanceof Error ? e.message : String(e)}`);
  }
  let g: unknown;
  try {
    g = JSON.parse(raw);
  } catch (e) {
    fatal(`金样本 JSON 解析失败: ${e instanceof Error ? e.message : String(e)}`);
  }
  if (!isRecord(g)) fatal("金样本顶层不是对象");
  const meta = g["_meta"];
  if (!isRecord(meta)) fatal("_meta 缺失或非对象");
  for (const k of ["source_fork", "source_commit", "total"]) {
    if (!(k in meta)) fatal(`_meta.${k} 缺失（provenance 锚）`);
  }
  const files = g["files"];
  if (!isRecord(files) || Object.keys(files).length === 0) fatal("files 缺失或为空");

  const recount: Record<string, number> = { clang_red: 0, both_green: 0, vitro_red: 0 };
  for (const [name, v] of Object.entries(files)) {
    if (!isRecord(v)) fatal(`files.${name} 非对象`);
    const run = v["run"];
    if (typeof run !== "string" || !checkRunWords.has(run)) {
      fatal(`files.${name}.run 非法值域: ${goFmt(run)}`);
    }
    const layer = v["layer"];
    if (typeof layer !== "string" || !checkLayerWords.has(layer)) {
      fatal(`files.${name}.layer 非法值域: ${goFmt(layer)}`);
    }
    const codes = v["codes"];
    if (!isRecord(codes)) fatal(`files.${name}.codes 缺失`);
    let sumE = 0;
    let sumWH = 0;
    for (const [c, n] of Object.entries(codes)) {
      if (
        Buffer.byteLength(c, "utf8") !== 5 ||
        (c[0] !== "E" && c[0] !== "W" && c[0] !== "H") ||
        !isAllDigits(c.slice(1))
      ) {
        fatal(`files.${name}.codes 键非诊断码形态: ${JSON.stringify(c)}`);
      }
      if (typeof n !== "number" || n < 1) {
        fatal(`files.${name}.codes[${c}] 计数非法`);
      }
      if (c[0] === "E") sumE += n;
      else sumWH += n;
    }
    if (typeof v["vitro_errs"] === "number" && sumE !== v["vitro_errs"]) {
      fatal(`files.${name} 求和失账：Σ(E码)=${goFmt(sumE)} != vitro_errs=${goFmt(v["vitro_errs"])}`);
    }
    if (typeof v["vitro_warns"] === "number" && sumWH !== v["vitro_warns"]) {
      fatal(`files.${name} 求和失账：Σ(W+H码)=${goFmt(sumWH)} != vitro_warns=${goFmt(v["vitro_warns"])}`);
    }
    for (const [k2, v2] of Object.entries(v)) {
      if (!entryKeys.has(k2)) {
        fatal(`files.${name} 未知键 ${JSON.stringify(k2)}（schema 白名单外——疑透传诊断文案）`);
      }
      if (typeof v2 === "string" && k2 !== "run" && k2 !== "layer" && Buffer.byteLength(v2, "utf8") > 8) {
        const clipped = Array.from(v2).slice(0, 60).join("");
        fatal(`files.${name}.${k2} 字符串超长(疑源码渗漏): ${JSON.stringify(clipped)}`);
      }
    }

    const clangOK = v["clang_ok"] === true;
    const errs = typeof v["vitro_errs"] === "number" ? v["vitro_errs"] : 0;
    if (!clangOK) recount["clang_red"] = (recount["clang_red"] ?? 0) + 1;
    else if (errs === 0) recount["both_green"] = (recount["both_green"] ?? 0) + 1;
    else recount["vitro_red"] = (recount["vitro_red"] ?? 0) + 1;
  }

  if (typeof meta["note"] === "string" && Buffer.byteLength(meta["note"], "utf8") > 300) {
    fatal("_meta.note 超长");
  }
  const total = meta["total"];
  if (typeof total !== "number" || Math.trunc(total) !== Object.keys(files).length) {
    fatal(`_meta.total ${goFmt(total)} != files 计数 ${Object.keys(files).length}`);
  }
  const mb = meta["buckets"];
  if (!isRecord(mb)) fatal("_meta.buckets 缺失或非对象");
  for (const k of ["clang_red", "both_green", "vitro_red"]) {
    const got = typeof mb[k] === "number" ? (mb[k] as number) : 0;
    if (Math.trunc(got) !== (recount[k] ?? 0)) {
      fatal(`_meta.buckets.${k} = ${goFmt(mb[k])} != files 重算 ${recount[k] ?? 0}`);
    }
  }
  return Object.keys(files).length;
}

/** 金样本 + corpora.json 三向对账；返回进程退出码。 */
export function runCheck(root: string): number {
  const dir = path.join(root, "scripts", "realcode_diff");
  const names = ["gold_signatures.json"];
  let dirents: fs.Dirent[];
  try {
    dirents = fs.readdirSync(dir, { withFileTypes: true });
  } catch (e) {
    fatal(`金样本扫描失败: ${e instanceof Error ? e.message : String(e)}`);
  }
  for (const e of dirents) {
    if (!e.isFile()) continue;
    if (!/^gold_.*\.json$/.test(e.name)) continue;
    if (e.name !== "gold_signatures.json") names.push(e.name);
  }
  const sortedNames = byteSort(names);

  const regPath = path.join(dir, "corpora.json");
  let corpora: Record<string, unknown> = {};
  if (fs.existsSync(regPath)) {
    let raw: string;
    try {
      raw = fs.readFileSync(regPath, "utf8");
    } catch (e) {
      fatal(`corpora.json 解析失败: ${e instanceof Error ? e.message : String(e)}`);
    }
    let parsed: unknown;
    try {
      parsed = JSON.parse(raw);
    } catch (e) {
      fatal(`corpora.json 解析失败: ${e instanceof Error ? e.message : String(e)}`);
    }
    if (!isRecord(parsed)) fatal("corpora.json 解析失败: 顶层不是对象");
    corpora = parsed;
  }

  const registered = new Set<string>();
  const corporaField = corpora["corpora"];
  if (isRecord(corporaField)) {
    for (const [name, v] of Object.entries(corporaField)) {
      registered.add(name);
      if (!isRecord(v)) fatal(`corpora.json corpora.${name} 非对象`);
      for (const k of ["gold", "license", "upstream_commit", "total"]) {
        if (!(k in v)) fatal(`corpora.json corpora.${name} 缺字段 ${k}`);
      }
      const gold = v["gold"];
      if (typeof gold !== "string" || gold === "") {
        fatal(`corpora.json corpora.${name}.gold 为空`);
      }
      if (!fileExists(path.join(dir, gold))) {
        fatal(`corpora.json corpora.${name}.gold 指向的金样本不存在: ${gold}`);
      }
    }
  }

  const corpusDir = path.join(dir, "corpus");
  if (dirExists(corpusDir)) {
    for (const e of fs.readdirSync(corpusDir, { withFileTypes: true })) {
      if (!e.isDirectory()) continue;
      if (!registered.has(e.name)) {
        fatal(`语料批 ${e.name} 存在但未在 corpora.json 登记（悬空）`);
      }
    }
  }
  for (const name of registered) {
    if (!dirExists(path.join(corpusDir, name))) {
      fatal(`corpora.json 登记的语料批 ${name} 目录不存在（僵尸登记）`);
    }
  }

  if (!isRecord(corporaField)) {
    fatal("corpora.json 缺失或 corpora 段非对象（三向对账无从对起）");
  }
  for (const [name, rawEntry] of Object.entries(corporaField)) {
    if (!isRecord(rawEntry)) fatal(`corpora.json corpora.${name} 非对象`);
    const licenseFile = rawEntry["license_file"];
    if (typeof licenseFile === "string" && licenseFile !== "" && !fileExists(path.join(dir, licenseFile))) {
      fatal(`corpora.json corpora.${name}.license_file 不存在: ${licenseFile}`);
    }
    const goldName = typeof rawEntry["gold"] === "string" ? rawEntry["gold"] : "";
    const goldKeys = new Set<string>();
    let goldRaw: string;
    try {
      goldRaw = fs.readFileSync(path.join(dir, goldName), "utf8");
    } catch (e) {
      fatal(`金样本读取失败 ${goldName}: ${e instanceof Error ? e.message : String(e)}`);
    }
    let goldParsed: unknown;
    try {
      goldParsed = JSON.parse(goldRaw);
    } catch (e) {
      fatal(`金样本解析失败 ${goldName}: ${e instanceof Error ? e.message : String(e)}`);
    }
    if (!isRecord(goldParsed) || !isRecord(goldParsed["files"])) {
      fatal(`金样本 files 缺失或非对象: ${goldName}`);
    }
    for (const k of Object.keys(goldParsed["files"])) goldKeys.add(k);

    const units = new Set<string>();
    const batchDir = path.join(corpusDir, name);
    let ents: fs.Dirent[];
    try {
      ents = fs.readdirSync(batchDir, { withFileTypes: true });
    } catch (e) {
      fatal(`语料批目录读取失败 ${name}: ${e instanceof Error ? e.message : String(e)}`);
    }
    for (const ent of ents) {
      if (ent.isDirectory()) units.add(ent.name + "/");
      else if (path.extname(ent.name) === ".c") units.add(ent.name);
    }
    for (const u of units) {
      if (!goldKeys.has(u)) fatal(`语料 unit ${name}/${u} 不在金样本 ${goldName} 键集（漏冻）`);
    }
    for (const k of goldKeys) {
      if (!units.has(k)) fatal(`金样本 ${goldName} 键 ${JSON.stringify(k)} 无对应语料（僵尸条目）`);
    }
    const total = rawEntry["total"];
    if (typeof total !== "number" || Math.trunc(total) !== units.size) {
      fatal(`corpora.json corpora.${name}.total = ${goFmt(total)} != 实际 units ${units.size}`);
    }
  }

  let totalEntries = 0;
  for (const name of sortedNames) {
    const n = checkOneGold(path.join(dir, name));
    process.stderr.write(`${name} 合规 OK: ${n} 文件条目（格式/值域/零渗漏/_meta 对账）\n`);
    totalEntries += n;
  }
  process.stderr.write(
    `金样本多文件扫描完成: ${sortedNames.length} 个文件、${totalEntries} 条目（登记表 ${registered.size} 个语料批）\n`,
  );
  return 0;
}
