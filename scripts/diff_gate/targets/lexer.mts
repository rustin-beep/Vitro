#!/usr/bin/env node
// lexer_diff —— S2 词法差分对拍（#273 差分族重构批；原 scripts/lexer_diff/main.go）。
//
// 管线：语料 LF 归一副本 → `moon run cmd/dump_tokens <norm> <out> both` 产
// `.l1.tsv` / `.l2.tsv` → 每文件 sha16 ↔ 冻结清单比对。
//
// 骨架（语料归一 / 三模式 / 报告 / 退出码）在 internal/diffgate.mts；
// 本文件自持两部分：① dump 与 case 命名；② **digest 的 JSON 形状**
//（`version/sources/tsvs`，顶层按 Go struct 字段声明序，不是字典序）。
import fs from "node:fs";
import path from "node:path";
import {
  moonDump,
  sha16,
  type DiffTarget,
  type Fail,
  type GateContext,
  type GoldenSection,
  type GoldenStore,
} from "../../internal/diffgate.mts";
import { makeFail } from "../../internal/genio.mts";
import { sortBytes } from "../../internal/gofmt.mts";

// 函数声明形式：TS 的控制流分析只在「显式声明 + 返回 never」处切断可达性，
// 用 const 箭头会让调用方后续代码报 TS2454/TS2538。
export function fatal(msg: string): never {
  return makeFail("lexer_diff: ", 1)(msg);
}

// ---- digest 形状（lexer 私有） ----

export interface LexDigest {
  version: number;
  /** corpus → { 文件名: sha8 } */
  sources: Record<string, Record<string, string>>;
  /** "corpus/case" → sha16 */
  tsvs: Record<string, string>;
}

const GOLDEN_REL = "scripts/lexer_diff/golden_digest.json";

export function loadLexDigest(root: string, fail: Fail = fatal): LexDigest {
  const p = path.join(root, GOLDEN_REL);
  const empty: LexDigest = { version: 1, sources: {}, tsvs: {} };
  if (!fs.existsSync(p)) return empty;
  let d: LexDigest;
  try {
    d = JSON.parse(fs.readFileSync(p, "utf8")) as LexDigest;
  } catch {
    return fail(`digest 清单坏或版本不识 ${GOLDEN_REL}`);
  }
  if (d.version !== 1) fail(`digest 清单坏或版本不识 ${GOLDEN_REL}`);
  return { version: 1, sources: d.sources ?? {}, tsvs: d.tsvs ?? {} };
}

/**
 * 复刻 Go `json.MarshalIndent` 的**两层**键序：
 *   顶层 = struct 字段声明序（version → sources → tsvs，**不是字典序**）；
 *   内层 = map 键的字节字典序。
 * 用通用 JSON 规范化器会把顶层也按字典序排（sources/tsvs/version）——与入库
 * 文件错位。边界：不做 Go 的 HTML 转义（< > &）；digest 键面不含该三字符。
 */
export function serializeLexDigest(d: LexDigest): string {
  const q = (s: string): string => JSON.stringify(s);
  const corpusKeys = sortBytes(Object.keys(d.sources));
  const sourcesBody =
    corpusKeys.length === 0
      ? "{}"
      : "{\n" +
        corpusKeys
          .map((c) => {
            const m = d.sources[c] ?? {};
            const files = sortBytes(Object.keys(m));
            const body =
              files.length === 0
                ? "{}"
                : "{\n" +
                  files.map((f) => `      ${q(f)}: ${q(m[f] ?? "")}`).join(",\n") +
                  "\n    }";
            return `    ${q(c)}: ${body}`;
          })
          .join(",\n") +
        "\n  }";
  const tsvKeys = sortBytes(Object.keys(d.tsvs));
  const tsvsBody =
    tsvKeys.length === 0
      ? "{}"
      : "{\n" + tsvKeys.map((k) => `    ${q(k)}: ${q(d.tsvs[k] ?? "")}`).join(",\n") + "\n  }";
  return `{\n  "version": ${d.version},\n  "sources": ${sourcesBody},\n  "tsvs": ${tsvsBody}\n}\n`;
}

export function saveLexDigest(root: string, d: LexDigest, fail: Fail = fatal): void {
  const p = path.join(root, GOLDEN_REL);
  try {
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(p, serializeLexDigest(d), { mode: 0o644 });
  } catch (e) {
    fail(`写 digest 清单失败 ${GOLDEN_REL}: ${(e as Error).message}`);
  }
}

function makeLexGolden(root: string): GoldenStore {
  return {
    missingHint: "先 --freeze-mb 入账",
    load(corpusName: string): GoldenSection | null {
      const d = loadLexDigest(root);
      const sources = d.sources[corpusName];
      if (sources === undefined) return null;
      const prefix = corpusName + "/";
      const cases: Record<string, string> = {};
      for (const [k, v] of Object.entries(d.tsvs)) {
        if (k.startsWith(prefix)) cases[k.slice(prefix.length)] = v;
      }
      return { sources, cases };
    },
    save(corpusName: string, sec: GoldenSection): void {
      const d = loadLexDigest(root);
      d.sources[corpusName] = sec.sources;
      const prefix = corpusName + "/";
      for (const k of Object.keys(d.tsvs)) {
        if (k.startsWith(prefix)) delete d.tsvs[k];
      }
      for (const [c, v] of Object.entries(sec.cases)) d.tsvs[prefix + c] = v;
      saveLexDigest(root, d);
    },
  };
}

export { makeLexGolden };

// ---- 差异面：dump 与 case 命名 ----

/// L1 行列自洽不变量（#297 处方②，2026-10-24）：同一 loc.line 组内所有
/// token 的 `byte_off − (col − 1)` 必须恒等（= 该行行首偏移）——等价于
/// source_loc 契约「col == byte_off − 行首偏移 + 1」的机判形态。旧「扫描
/// 后列 − 规范化 text 长度」回推对 text≠源拼写的 token 必偏（0x1F +2 /
/// 0b101 +4 / 后缀剥 +1——同行邻 token 即可差出），本闸在 digest 化之前
/// 逐 token 拦截。跨行 token（行拼接字符串）独占其起始行分组，天然通过。
/// L2 无 byte_off 列，不校验。
export function checkLineColInvariant(caseName: string, tsv: string): string[] {
  const errs: string[] = [];
  // line -> 该行推导出的行首偏移（byte_off - (col - 1)）
  const lineBase = new Map<number, number>();
  for (const row of tsv.split("\n")) {
    if (row === "" || row.startsWith("count=")) continue;
    const c = row.split("\t");
    if (c.length < 6) continue; // L1 六列；非数据行跳过
    const line = Number(c[3]);
    const col = Number(c[4]);
    const off = Number(c[5]);
    if (!Number.isInteger(line) || !Number.isInteger(col) || !Number.isInteger(off)) {
      continue;
    }
    const base = off - (col - 1);
    const prev = lineBase.get(line);
    if (prev !== undefined && prev !== base) {
      errs.push(
        `${caseName}: line ${line} 行列失洽——byte_off−col 推得行首 ${base} ≠ 同行既有 ${prev}（col 与 byte_off 量纲回推族缺陷，参见 #297）`,
      );
    } else {
      lineBase.set(line, base);
    }
  }
  return errs;
}

export function runLexerCases(ctx: GateContext, fail: Fail = fatal): Map<string, string> {
  moonDump(ctx.root, "cmd/dump_tokens", [ctx.normDir, ctx.workDir, "both"], fail);
  const out = new Map<string, string>();
  for (const f of fs.readdirSync(ctx.workDir).filter((n) => n.endsWith(".tsv")).sort()) {
    const buf = fs.readFileSync(path.join(ctx.workDir, f));
    if (f.endsWith(".l1.tsv")) {
      const errs = checkLineColInvariant(f, buf.toString("utf8"));
      if (errs.length > 0) fail(errs.join("\n"));
    }
    out.set(f, sha16(buf));
  }
  return out;
}

export const lexerTarget: DiffTarget = {
  name: "lexer_diff",
  fail: fatal,
  golden: (root: string) => makeLexGolden(root),
  runCases: (ctx: GateContext) => runLexerCases(ctx),
};
