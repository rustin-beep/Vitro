// stmt_expr —— realcode_diff 的纯文本变换与判定口径（Go 版逐函数复刻）。
//
// 面：
//   - stripStdbool：stdbool.h → #define 三行（P4 剥壳；漏 true/false 时 Clang 必红）
//   - stripStmtExprs：GNU `({...})` 语句表达式消解（P4'，-probe 模式专用）
//   - layerOf：诊断码段 → 层（E1=lex / E2=parse / E3=typeck）
//   - normalize / vnEqualIgnoreDigits / firstLine：运行对比的输出归一与截断
//
// 字节口径：Go 侧全是 byte slice；本文件对源文本用 JS 字符串（只在 ASCII 边界
// 切片，不会撕裂多字节字符），对**程序输出**用 Buffer 比较——长度类文案一律
// `Buffer.byteLength`。
import { goTrimSpace } from "../internal/text.mts";
import type { Diag } from "./types.mts";

const GO_WS = "[\\t\\n\\f\\r ]";

// ---------- P4: 剥壳(stdbool→int + true/false) ----------
const stripStdboolRe = new RegExp(`^(${GO_WS}*)#include <stdbool\\.h>`, "gm");

export function stripStdbool(src: string): { src: string; changed: boolean } {
  if (!src.includes("#include <stdbool.h>")) return { src, changed: false };
  const out = src.replace(
    stripStdboolRe,
    "$1#define bool int\n$1#define true 1\n$1#define false 0",
  );
  return { src: out, changed: true };
}

// ---------- P4': 语句表达式消解 ----------
const assertCallRe = new RegExp(`\\b([A-Z][A-Z0-9_]*)${GO_WS}*\\(`, "g");
const assertCallOneRe = new RegExp(`\\b([A-Z][A-Z0-9_]*)${GO_WS}*\\(`);

/** 消解源码中的 GNU 语句表达式。返回 (变换后源码, 消解处数)。 */
export function stripStmtExprs(src: string): { src: string; count: number } {
  let count = 0;
  for (;;) {
    const found = findAssertStmtExpr(src);
    if (found === null) break;
    const repl = rewriteAssertStmt(src, found.start, count);
    if (repl === null) break;
    src = src.slice(0, found.start) + repl + src.slice(found.end);
    count++;
  }
  return { src, count };
}

/** 找第一处「宏调用的第二实参是语句表达式且处于语句位置」的调用。 */
function findAssertStmtExpr(src: string): { start: number; end: number } | null {
  assertCallRe.lastIndex = 0;
  for (const m of src.matchAll(assertCallRe)) {
    const matchStart = m.index ?? 0;
    const open = matchStart + m[0].length - 1; // '(' 位置
    const arg2Start = secondArgStart(src, open);
    if (arg2Start < 0) continue;
    if (!src.startsWith("({", arg2Start)) continue;
    if (!matchBrace(src, arg2Start + 1).ok) continue;
    const callEnd = findMatchingParen(src, open);
    if (callEnd < 0) continue;
    const rest = src.slice(callEnd + 1).replace(new RegExp(`^${GO_WS}*`), "");
    if (!rest.startsWith(";")) continue;
    return { start: matchStart, end: callEnd + 1 };
  }
  return null;
}

/** 第二个实参起始位置；找不到返回 -1。 */
function secondArgStart(src: string, open: number): number {
  let depth = 0;
  let inStr = false;
  let inChr = false;
  let commas = 0;
  for (let i = open; i < src.length; i++) {
    const c = src[i] ?? "";
    if (inStr) {
      if (c === "\\") i++;
      else if (c === '"') inStr = false;
      continue;
    }
    if (inChr) {
      if (c === "\\") i++;
      else if (c === "'") inChr = false;
      continue;
    }
    switch (c) {
      case '"':
        inStr = true;
        break;
      case "'":
        inChr = true;
        break;
      case "(":
      case "[":
      case "{":
        depth++;
        break;
      case ")":
      case "]":
      case "}":
        depth--;
        if (depth === 0) return -1;
        break;
      case ",":
        if (depth === 1) {
          commas++;
          if (commas === 1) {
            let j = i + 1;
            while (j < src.length && (src[j] === " " || src[j] === "\t")) j++;
            return j;
          }
        }
        break;
      default:
        break;
    }
  }
  return -1;
}

/** 从 '(' 位置找匹配的 ')'；找不到返回 -1。 */
function findMatchingParen(src: string, open: number): number {
  let depth = 0;
  let inStr = false;
  let inChr = false;
  for (let i = open; i < src.length; i++) {
    const c = src[i] ?? "";
    if (inStr) {
      if (c === "\\") i++;
      else if (c === '"') inStr = false;
      continue;
    }
    if (inChr) {
      if (c === "\\") i++;
      else if (c === "'") inChr = false;
      continue;
    }
    switch (c) {
      case '"':
        inStr = true;
        break;
      case "'":
        inChr = true;
        break;
      case "(":
        depth++;
        break;
      case ")":
        depth--;
        if (depth === 0) return i;
        break;
      default:
        break;
    }
  }
  return -1;
}

/** `MACRO(a, ({ body }));` → `{ body; int __vitro_sxN = last; MACRO(a, __vitro_sxN); }` */
function rewriteAssertStmt(src: string, callStart: number, idx: number): string | null {
  const m = assertCallOneRe.exec(src.slice(callStart));
  if (m === null) return null;
  const openRel = (m.index ?? 0) + m[0].length - 1;
  const name = src.slice(callStart, callStart + openRel);
  const open = callStart + openRel;
  const args = twoArgs(src, open);
  if (args === null) return null;
  let arg1 = goTrimSpace(src.slice(args.arg1Start, args.arg2Start));
  if (arg1.endsWith(",")) arg1 = arg1.slice(0, -1);
  arg1 = goTrimSpace(arg1);
  const brace = matchBrace(src, args.arg2Start + 1);
  if (!brace.ok) return null;
  if (hasControlFlow(brace.body)) return null;
  const split = splitLastStmt(brace.body);
  if (!split.ok) return null;
  const inner = `${split.stmts} int __vitro_sx${idx} = ${split.last}; ${name}(${arg1}, __vitro_sx${idx});`;
  return "{ " + inner + " }";
}

function twoArgs(src: string, open: number): { arg1Start: number; arg2Start: number } | null {
  let depth = 0;
  let inStr = false;
  let inChr = false;
  let commas = 0;
  const arg1Start = open + 1;
  let arg2Start = 0;
  for (let i = open; i < src.length; i++) {
    const c = src[i] ?? "";
    if (inStr) {
      if (c === "\\") i++;
      else if (c === '"') inStr = false;
      continue;
    }
    if (inChr) {
      if (c === "\\") i++;
      else if (c === "'") inChr = false;
      continue;
    }
    switch (c) {
      case '"':
        inStr = true;
        break;
      case "'":
        inChr = true;
        break;
      case "(":
      case "[":
      case "{":
        depth++;
        break;
      case ")":
      case "]":
      case "}":
        depth--;
        if (depth === 0) {
          if (commas < 1) return null;
          return { arg1Start, arg2Start };
        }
        break;
      case ",":
        if (depth === 1) {
          commas++;
          if (commas === 1) {
            let j = i + 1;
            while (j < src.length && (src[j] === " " || src[j] === "\t")) j++;
            arg2Start = j;
          }
        }
        break;
      default:
        break;
    }
  }
  return null;
}

// ---------- 末条语句切分（GNU 语句表达式的值 = 最后一条语句的值） ----------

const declKeywords = [
  "int", "char", "short", "long", "float", "double", "void", "signed", "unsigned",
  "_Bool", "_Complex", "struct", "union", "enum", "const", "volatile", "static",
  "extern", "typedef", "register", "auto", "inline", "_Alignas", "_Atomic",
  "_Noreturn", "_Thread_local", "thread_local", "__thread",
];

export function splitLastStmt(body: string): { stmts: string; last: string; ok: boolean } {
  const trimmed = goTrimSpace(body);
  if (trimmed === "") return { stmts: "", last: "", ok: false };
  const bounds = topLevelStmtEnds(trimmed);
  if (bounds.length === 0) return { stmts: "", last: trimmed, ok: true };
  const lastEnd = bounds[bounds.length - 1] as number;
  let lastStart = bounds.length >= 2 ? (bounds[bounds.length - 2] as number) + 1 : 0;
  lastStart = skipCompoundStmt(trimmed, lastStart, lastEnd);
  const last = goTrimSpace(trimmed.slice(lastStart, lastEnd));
  const stmts = goTrimSpace(trimmed.slice(0, lastStart));
  if (last === "") return { stmts: "", last: "", ok: false };
  if (!isExprLikeStmt(last)) return { stmts: "", last: "", ok: false };
  return { stmts, last, ok: true };
}

function isExprLikeStmt(s: string): boolean {
  const t = goTrimSpace(s);
  if (t === "") return false;
  if (t.startsWith("{")) return false;
  for (const kw of declKeywords) {
    if (
      t === kw ||
      t.startsWith(kw + " ") ||
      t.startsWith(kw + "\t") ||
      t.startsWith(kw + "*") ||
      t.startsWith(kw + "\n")
    ) {
      return false;
    }
  }
  return true;
}

function skipCompoundStmt(s: string, from: number, to: number): number {
  let i = from;
  while (i < to && (s[i] === " " || s[i] === "\t" || s[i] === "\n" || s[i] === "\r")) i++;
  if (i >= to || s[i] !== "{") return from;
  const brace = matchBrace(s, i);
  if (!brace.ok || brace.end >= to) return from;
  return brace.end + 1;
}

/** 顶层语句结束位置（顶层分号；嵌套块整体跳过——只数花括号深度）。 */
function topLevelStmtEnds(s: string): number[] {
  let inStr = false;
  let inChr = false;
  let depth = 0;
  const out: number[] = [];
  for (let i = 0; i < s.length; i++) {
    const c = s[i] ?? "";
    if (inStr) {
      if (c === "\\") i++;
      else if (c === '"') inStr = false;
      continue;
    }
    if (inChr) {
      if (c === "\\") i++;
      else if (c === "'") inChr = false;
      continue;
    }
    switch (c) {
      case '"':
        inStr = true;
        break;
      case "'":
        inChr = true;
        break;
      case "{":
        depth++;
        break;
      case "}":
        depth--;
        break;
      case ";":
        if (depth === 0) out.push(i);
        break;
      default:
        break;
    }
  }
  return out;
}

function matchBrace(src: string, open: number): { body: string; end: number; ok: boolean } {
  if (open >= src.length || src[open] !== "{") return { body: "", end: 0, ok: false };
  let depth = 0;
  let inStr = false;
  let inChr = false;
  for (let i = open; i < src.length; i++) {
    const c = src[i] ?? "";
    if (inStr) {
      if (c === "\\") i++;
      else if (c === '"') inStr = false;
      continue;
    }
    if (inChr) {
      if (c === "\\") i++;
      else if (c === "'") inChr = false;
      continue;
    }
    switch (c) {
      case '"':
        inStr = true;
        break;
      case "'":
        inChr = true;
        break;
      case "{":
        depth++;
        break;
      case "}":
        depth--;
        if (depth === 0) return { body: src.slice(open + 1, i), end: i, ok: true };
        break;
      default:
        break;
    }
  }
  return { body: "", end: 0, ok: false };
}

function hasControlFlow(body: string): boolean {
  return /(?:^|[^A-Za-z0-9_])(return|break|continue|goto)(?:[^A-Za-z0-9_]|$)/.test(body);
}

// ---------- 层判定（码段粗分：E1=lex / E2=parse / E3=typeck） ----------
// PR #350 审阅 P2-1（2026-10-28）：**首个失败层**语义——旧 E3 分支无条件
// 覆盖使「最后一个 error 的类别」胜出（#213 语法错后照跑 typeck 起，
// E2+E3 混合文件被 E3 尾覆盖成 typeck——realcode parse 面分诊清零，且
// 与 codegen 闸 fail_stage:"parse" 对同一事实给相反答案）。E1/E2 分支的
// 既有守卫正是首层序（低层被更高优先的既有值顶住）；E3 补同款守卫。
export function layerOf(diags: readonly Diag[]): string {
  let layer = "ok";
  for (const d of diags) {
    if (d.severity !== "error" || d.code.length < 2) continue;
    if (d.code.startsWith("E1")) {
      if (layer === "ok" || layer === "parse" || layer === "typeck") layer = "lex";
    } else if (d.code.startsWith("E2")) {
      if (layer === "ok" || layer === "typeck") layer = "parse";
    } else if (d.code.startsWith("E3")) {
      if (layer === "ok") layer = "typeck";
    }
  }
  return layer;
}

// ---------- P5: 运行对比的输出归一 ----------
// oxlint-disable-next-line no-control-regex -- ANSI 转义序列判定本就匹配 U+001B
const ansiRe = /\x1b\[[0-9;]*m/g;
const exitLineRe = /\/\/ EXIT \d+[\t\n\f\r ]*$/gm;
const warnBlockRe = /^Warning: \[\d+\][\s\S]*?─{3,}╯[\t\n\f\r ]*$/gm;

/** 去 ANSI / `// EXIT N` 行 / moon 工具链 Warning 块，并裁掉行尾空白。 */
export function normalize(buf: Buffer): Buffer {
  let s = buf.toString("utf8");
  s = s.replace(ansiRe, "");
  s = s.replace(exitLineRe, "");
  s = s.replace(warnBlockRe, "");
  const kept: string[] = [];
  for (const l of s.split("\n")) {
    const t = goTrimSpace(l);
    if (t.startsWith("Warning") || t.startsWith("╭─") || t.startsWith("│") || t.startsWith("╰")) continue;
    kept.push(l.replace(/[ \t\r]+$/, ""));
  }
  return Buffer.from(goTrimSpace(kept.join("\n")), "utf8");
}

export function vnEqualIgnoreDigits(a: Buffer, b: Buffer): boolean {
  const ra = a.toString("utf8").replace(/\d+/g, "#");
  const rb = b.toString("utf8").replace(/\d+/g, "#");
  return ra === rb;
}

/** 首个非空行，截断到 120 字节（Go 侧 `s[:120]` 的字节口径）。 */
export function firstLine(s: string): string {
  let t = goTrimSpace(s);
  const i = t.indexOf("\n");
  if (i > 0) t = t.slice(0, i);
  if (Buffer.byteLength(t, "utf8") > 120) {
    t = Buffer.from(t, "utf8").subarray(0, 120).toString("utf8");
  }
  return t;
}
