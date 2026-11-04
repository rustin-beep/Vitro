#!/usr/bin/env node
// conv_specs：printf/scanf 转换符表单源对账闸（审阅 v2 批 A7 / R1a 处方 R3，2026-11-02）。
//
// 背景（R1a ④ M3「枚举表成员不全」形态）：同一张 C11 标准转换符表在仓内被
// 四个消费面各自手抄枚举——printf 的 host 白名单 is_known_conv_code（18 字母）/
// printf 的 typeck 判据臂（16 字母，缺 a/A）/ scanf 的 host SCANF_* 常量集（9
// 字母 + scanset）/ scanf 的 typeck W3063 判据臂（16 字母）——**四面四个数**，
// 枚举进度彼此独立漂移：scanf %e 在 typeck 零警告、在 host 静默失败（R1a-F3），
// 病 23 修 8 个转换符漏 %c、病 26 printf 补白名单而 scanf 至今无白名单（F7）。
// 本闸把「哪个字母哪一面认」收口到 rules.json 一张声明表，四面源码实际枚举
// 必须与声明逐字母一致——改一面不改表即红，改表不改另一面亦红。
//
// 用法（**仓库根**）：
//   node scripts/moonbit/conv_specs/main.mts            # 四面字母集报告 + 判定
//   node scripts/moonbit/conv_specs/main.mts -check     # 判定（CI 门禁用）
//   node scripts/moonbit/conv_specs/main.mts --selftest # J9：三路内存注入必红
//
// 判据（规则见 rules.json）：
//   ① 每面源码抽取的字母集 == 声明表该面标 true 的字母集（双向差集红）
//   ② host≠typeck 的字母必须带非空 divergence（登记公开待修清单，不是豁免）
//   ③ divergence 在场但两面已一致 = 僵尸 reason（逼着清账）
//   ④ C11 全集（脚本内置，非 rules.json）每成员必须在声明表中——防「只枚举见过的」
//   ⑤ 任一面抽取空集 = 锚点失效，拒绝判定
//
// fail loud：源文件缺失 / 锚点找不到 / 规则 schema 不对 → exit 2；断言不过 → exit 1。
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../../internal/capi.mts";

export const RULES_PATH = "scripts/moonbit/conv_specs/rules.json";

/** C11 §7.21.6.1 p8 printf 转换符全集（% 不列——%% 非转换符）。 */
export const C11_PRINTF = ["d", "i", "o", "u", "x", "X", "f", "F", "e", "E", "g", "G", "a", "A", "c", "s", "p", "n"] as const;
/** C11 §7.21.6.2 p12 scanf 转换符全集（含 scanset `[`；% 不列）。 */
export const C11_SCANF = ["d", "i", "o", "u", "x", "X", "a", "A", "e", "E", "f", "F", "g", "G", "c", "s", "p", "n", "["] as const;

export interface MarkerExtra {
  marker: string;
  letter: string;
  note?: string;
}

export interface SourceSpec {
  file: string;
  anchor_start: string;
  anchor_end: string;
  kind: string;
  extra_by_marker?: MarkerExtra[];
  note?: string;
}

export interface LetterDecl {
  host: boolean;
  typeck: boolean;
  divergence?: string;
  note?: string;
}

export interface FamilyDecl {
  c11_ref: string;
  host_face: string;
  typeck_face: string;
  letters: Record<string, LetterDecl>;
}

export interface RulesDoc {
  schema: number;
  sources: Record<string, SourceSpec>;
  families: Record<string, FamilyDecl>;
}

export interface Face {
  name: string;
  letters: string[];
  set: Set<string>;
  srcPath: string;
}

const RE_NEXT_TOP_FN = /^(pub )?fn /m;
const RE_CODEPOINT_EQ = /\bc == (\d+)\b/g;
/** 单字符字面量（字母或 `[`）——插值串 `'%\{spec}'` 因 `%` 后非 `'` 不命中。 */
const RE_CHAR_LIT = /'([a-zA-Z[])'/g;
const RE_SCANF_CONST = /^[ \t]*const SCANF_[A-Z_]+ = (\d+)\b/gm;

function fatal(msg: string): never {
  process.stderr.write(`conv_specs: ${msg}\n`);
  process.exit(2);
}

function abs(p: string): string {
  return path.isAbsolute(p) ? p : path.join(projectRoot(), p);
}

/** 字节序排序（Go sort.Strings 口径——与仓内各对账闸同款）。 */
export function byteSort(xs: string[]): string[] {
  return [...xs].sort((a, b) => Buffer.compare(Buffer.from(a, "utf8"), Buffer.from(b, "utf8")));
}

/**
 * 剥行注释（`//` 之后）——判据臂上方的文档注释里常有字母字面量举例，不能当臂。
 *
 * 判据口径边界（2026-11-04 审阅 P3⑤ 连坐登记，host_shared_guard /
 * twin_fingerprint 两闸共用本函数）：实现为 `indexOf("//")` 首现剥除——
 * ① 同行字符串字面量含 `//`（如 URL）时其后代码同被剥掉（假阴性面：
 * 字面量之后再有真实调用不计数）；② 块注释不剥（注释正文提及符号名
 * 仍算命中面）。当前两闸规则表与本口径自洽；若消费面出现上述形态，
 * 先扩本函数再动规则表，勿在闸侧私自补丁。
 */
export function stripLineComments(text: string): string {
  return text
    .split("\n")
    .map((line) => {
      const i = line.indexOf("//");
      return i < 0 ? line : line.slice(0, i);
    })
    .join("\n");
}

/** sliceByAnchors：anchor_start 定位；anchor_end 为空时用「下一个顶层 fn」收尾。 */
export function sliceByAnchors(text: string, spec: SourceSpec): { body: string; error?: string } {
  const i = text.indexOf(spec.anchor_start);
  if (i < 0) return { body: "", error: `anchor_start 未命中: ${JSON.stringify(spec.anchor_start)}` };
  const rest = text.slice(i + spec.anchor_start.length);
  if (spec.anchor_end !== "" && spec.anchor_end !== undefined) {
    const j = rest.indexOf(spec.anchor_end);
    if (j < 0) return { body: "", error: `anchor_end 未命中: ${JSON.stringify(spec.anchor_end)}` };
    return { body: rest.slice(0, j) };
  }
  const m = RE_NEXT_TOP_FN.exec(rest);
  if (m !== null && m.index > 0) return { body: rest.slice(0, m.index) };
  return { body: rest };
}

/** 按 kind 从函数体切片抽字母集（去重保序）。 */
export function extractLetters(body: string, fullText: string, spec: SourceSpec): string[] {
  const clean = stripLineComments(body);
  const out: string[] = [];
  const push = (l: string): void => {
    if (!out.includes(l)) out.push(l);
  };
  if (spec.kind === "codepoint_eq_chain") {
    for (const m of clean.matchAll(RE_CODEPOINT_EQ)) push(String.fromCharCode(Number.parseInt(m[1] ?? "0", 10)));
  } else if (spec.kind === "match_char_arms") {
    for (const m of clean.matchAll(RE_CHAR_LIT)) push(m[1] ?? "");
  } else if (spec.kind === "scanf_consts") {
    for (const m of clean.matchAll(RE_SCANF_CONST)) push(String.fromCharCode(Number.parseInt(m[1] ?? "0", 10)));
  } else {
    fatal(`未知 kind: ${spec.kind}`);
  }
  for (const ex of spec.extra_by_marker ?? []) {
    if (fullText.includes(ex.marker)) push(ex.letter);
  }
  return out;
}

export function mustFace(rd: RulesDoc, key: string): Face {
  const spec = rd.sources[key];
  if (spec === undefined) fatal(`规则缺 source 定义: ${key}`);
  let text: string;
  try {
    text = fs.readFileSync(abs(spec.file), "utf8");
  } catch (e) {
    fatal(`读源失败 ${spec.file}（须在仓库根运行）: ${e instanceof Error ? e.message : String(e)}`);
  }
  const sliced = sliceByAnchors(text, spec);
  if (sliced.error !== undefined) fatal(`源 ${spec.file} 的锚点定位失败: ${sliced.error}`);
  const letters = extractLetters(sliced.body, text, spec);
  return { name: key, letters, set: new Set(letters), srcPath: spec.file };
}

function declared(fam: FamilyDecl, face: "host" | "typeck"): string[] {
  return byteSort(Object.entries(fam.letters).filter(([, d]) => d[face]).map(([l]) => l));
}

function c11Of(familyName: string): readonly string[] {
  if (familyName === "printf") return C11_PRINTF;
  if (familyName === "scanf") return C11_SCANF;
  return [];
}

/** 五判据全过才绿；打印全部差异不早退。faces 为预抽取的面（selftest 注入用）。 */
export function verdict(rd: RulesDoc, faces: Record<string, Face>): boolean {
  let ok = true;
  const say = (s: string): void => {
    process.stdout.write(`  ${s}\n`);
  };
  for (const [famName, fam] of Object.entries(rd.families)) {
    const c11 = c11Of(famName);
    if (c11.length === 0) {
      ok = false;
      say(`[族] ${famName} 不是脚本已知的 C11 族（printf/scanf）——rules.json 新族须先在脚本登记全集`);
      continue;
    }
    // ④ C11 全集完整性
    const missingC11 = c11.filter((l) => fam.letters[l] === undefined);
    if (missingC11.length > 0) {
      ok = false;
      say(`[C11 缺位] ${famName}（${fam.c11_ref}）声明表缺成员: ${missingC11.join(" ")}——必须列全（标 host/typeck 现状），禁止只枚举见过的`);
    }
    const unknown = Object.keys(fam.letters).filter((l) => !c11.includes(l));
    if (unknown.length > 0) {
      ok = false;
      say(`[非 C11] ${famName} 声明表含非标准成员: ${unknown.join(" ")}`);
    }
    for (const faceKind of ["host", "typeck"] as const) {
      const faceKey = faceKind === "host" ? fam.host_face : fam.typeck_face;
      const face = faces[faceKey];
      if (face === undefined) {
        ok = false;
        say(`[面缺] ${famName}.${faceKind} 引用的 source ${faceKey} 未抽取`);
        continue;
      }
      // ⑤ 空集不得绿
      if (face.letters.length === 0) {
        ok = false;
        say(`[空集] ${face.name} 抽取出 0 个字母——锚点或源文件已变，拒绝判定`);
        continue;
      }
      // ① 面 == 声明
      const want = new Set(declared(fam, faceKind));
      const extra = byteSort(face.letters.filter((l) => !want.has(l)));
      const missing = byteSort([...want].filter((l) => !face.set.has(l)));
      if (extra.length > 0 || missing.length > 0) {
        ok = false;
        say(`[漂移] ${famName}.${faceKind}（${face.srcPath}）实际枚举 ≠ 声明表 ${faceKind}:true 集`);
        if (extra.length > 0) say(`    源码有而声明表未标 true: ${extra.join(" ")}（新支持的字母→改 rules.json 置 true 并同步另一面或登记 divergence）`);
        if (missing.length > 0) say(`    声明表标 true 而源码无: ${missing.join(" ")}（实现被删/改名，或声明失实）`);
      }
    }
    // ② / ③ divergence 纪律
    for (const [l, d] of Object.entries(fam.letters)) {
      const diverged = d.host !== d.typeck;
      const hasReason = typeof d.divergence === "string" && d.divergence.trim().length > 0;
      if (diverged && !hasReason) {
        ok = false;
        say(`[无 reason] ${famName} '%${l}' host=${d.host} typeck=${d.typeck} 两面不一致却无 divergence——必须登记为什么（公开待修清单，不是豁免）`);
      }
      if (!diverged && hasReason) {
        ok = false;
        say(`[僵尸 reason] ${famName} '%${l}' 两面已一致（host=typeck=${d.host}）但仍带 divergence——清账删字段`);
      }
    }
  }
  return ok;
}

export function report(rd: RulesDoc, faces: Record<string, Face>): void {
  process.stdout.write("conv_specs：printf/scanf 转换符表单源对账（审阅 v2 A7 / R1a-R3）\n");
  for (const [famName, fam] of Object.entries(rd.families)) {
    const dec = Object.entries(fam.letters);
    const div = dec.filter(([, d]) => d.host !== d.typeck).length;
    process.stdout.write(`  族 ${famName}（${fam.c11_ref}）：声明 ${dec.length} 成员，host:true ${declared(fam, "host").length} / typeck:true ${declared(fam, "typeck").length}，两面分叉 ${div}（均带 divergence 登记）\n`);
    for (const k of [fam.host_face, fam.typeck_face]) {
      const f = faces[k];
      if (f !== undefined) process.stdout.write(`    ${k.padEnd(14)} ${String(f.letters.length).padStart(3)} 字母 [${byteSort(f.letters).join(" ")}]  ← ${f.srcPath}\n`);
    }
  }
}

export function allFaces(rd: RulesDoc): Record<string, Face> {
  const out: Record<string, Face> = {};
  for (const k of Object.keys(rd.sources)) out[k] = mustFace(rd, k);
  return out;
}

function cloneRules(rd: RulesDoc): RulesDoc {
  return JSON.parse(JSON.stringify(rd)) as RulesDoc;
}

function cloneFaces(faces: Record<string, Face>): Record<string, Face> {
  const out: Record<string, Face> = {};
  for (const [k, f] of Object.entries(faces)) out[k] = { name: f.name, letters: [...f.letters], set: new Set(f.letters), srcPath: f.srcPath };
  return out;
}

/** J9：基线须绿；三路注入（面漏抄 / 分叉去 reason / 一致加僵尸 reason）各自必红。 */
export function selftestRun(rd: RulesDoc, faces: Record<string, Face>): number {
  const quiet = (fn: () => boolean): boolean => {
    const w = process.stdout.write.bind(process.stdout);
    process.stdout.write = (() => true) as typeof process.stdout.write;
    try {
      return fn();
    } finally {
      process.stdout.write = w;
    }
  };
  if (!quiet(() => verdict(rd, faces))) {
    process.stdout.write("conv_specs: selftest ABORT——基线不绿，注入后的红无法归因\n");
    return 2;
  }
  const printf = rd.families["printf"];
  const scanf = rd.families["scanf"];
  if (printf === undefined || scanf === undefined) {
    process.stdout.write("conv_specs: selftest ABORT——规则缺 printf/scanf 族\n");
    return 2;
  }
  let fails = 0;
  // 注入①：printf host 面抽掉 'o'（模拟白名单漏抄）
  {
    const f2 = cloneFaces(faces);
    const hf = f2[printf.host_face];
    if (hf === undefined) return 2;
    hf.letters = hf.letters.filter((l) => l !== "o");
    hf.set = new Set(hf.letters);
    const red = !quiet(() => verdict(rd, f2));
    process.stdout.write(`  注入① printf host 面抽掉 'o' → ${red ? "红（捕获）" : "仍绿（闸失效）"}\n`);
    if (!red) fails++;
  }
  // 注入②：scanf 'p' 分叉去 reason（#428 B5 批后 e 已两面一致——探针换 p：
  // host:false / typeck:true 现役分叉成员）
  {
    const r2 = cloneRules(rd);
    const e = r2.families["scanf"]?.letters["p"];
    if (e === undefined) return 2;
    if (e.host === e.typeck) {
      process.stdout.write("  注入② 探针字母 p 已不在分叉态——换 a/A/[ 等现役成员\n");
      return 2;
    }
    delete e.divergence;
    const red = !quiet(() => verdict(r2, faces));
    process.stdout.write(`  注入② scanf '%p' host≠typeck 去掉 divergence → ${red ? "红（捕获）" : "仍绿（闸失效）"}\n`);
    if (!red) fails++;
  }
  // 注入③：printf 'd' 两面一致却加 divergence（僵尸）
  {
    const r3 = cloneRules(rd);
    const d = r3.families["printf"]?.letters["d"];
    if (d === undefined) return 2;
    d.divergence = "僵尸探针";
    const red = !quiet(() => verdict(r3, faces));
    process.stdout.write(`  注入③ printf '%d' 两面一致却带 divergence → ${red ? "红（捕获）" : "仍绿（闸失效）"}\n`);
    if (!red) fails++;
  }
  // 注入④：声明表删掉 C11 成员 'n'（模拟只枚举见过的）
  {
    const r4 = cloneRules(rd);
    const letters = r4.families["printf"]?.letters;
    if (letters === undefined) return 2;
    delete letters["n"];
    const red = !quiet(() => verdict(r4, faces));
    process.stdout.write(`  注入④ printf 声明表删 C11 成员 'n' → ${red ? "红（捕获）" : "仍绿（闸失效）"}\n`);
    if (!red) fails++;
  }
  if (fails > 0) {
    process.stdout.write(`conv_specs: selftest FAIL——${fails} 路注入未被捕获\n`);
    return 1;
  }
  process.stdout.write("conv_specs: selftest PASS——四路注入全部捕获（红），J9 证红成立\n");
  return 0;
}

export function loadRules(p = RULES_PATH): RulesDoc {
  let raw: string;
  try {
    raw = fs.readFileSync(abs(p), "utf8");
  } catch (e) {
    fatal(`读规则失败（须在仓库根运行）: ${e instanceof Error ? e.message : String(e)}`);
  }
  let rd: RulesDoc;
  try {
    rd = JSON.parse(raw) as RulesDoc;
  } catch (e) {
    fatal(`规则解析失败: ${e instanceof Error ? e.message : String(e)}`);
  }
  if (rd.schema !== 1) fatal(`规则 schema 不支持: ${rd.schema}（期望 1）`);
  if (rd.families === undefined || rd.sources === undefined) fatal("规则缺 families / sources");
  return rd;
}

export function main(argv: string[]): number {
  let selftest = false;
  let check = false;
  for (const a of argv) {
    if (a === "--selftest" || a === "-selftest") selftest = true;
    else if (a === "-check" || a === "--check") check = true;
    else fatal(`未知参数: ${a}（可用：-check / --selftest）`);
  }
  const rd = loadRules();
  const faces = allFaces(rd);
  if (!check) report(rd, faces);
  if (selftest) return selftestRun(rd, faces);
  if (verdict(rd, faces)) {
    process.stdout.write("conv_specs: PASS（四面枚举与声明表逐字母一致；分叉均带 divergence 登记；C11 全集列全）\n");
    return 0;
  }
  process.stdout.write("conv_specs: FAIL——转换符表已分叉（详见上方差异）\n");
  return 1;
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  process.exit(main(process.argv.slice(2)));
}
