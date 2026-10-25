#!/usr/bin/env node
// corpus_fuzz —— 存量语料的对抗随机分叉防线（Go→.mts 重写，refs #273；原 main.go 935 +
// generators.go 165 行，2026-10-18 立项）。
//
// 判据：clang -O0 × vitro-native × vitro-js 三方对拍，分桶——
//
//	AGREE          三方一致（含双拒）
//	ARM_DIVERGENCE js/native 不一致（最高优先桶）
//	VITRO_REJECT   clang 接受而 vitro 拒（误拒面）
//	VITRO_TRAP     clang 正常而 vitro trap
//	WRONG_VALUE    输出不一致
//	CLANG_REJECT   clang 拒而 vitro 接受（误收面）
//
// 指纹 = "suite/seed|mutator"（或生成器段 "gen:<域名>/<序号>"）→ bucket。
// fuzz_baseline.json 入库锁定（-freeze 生成）；跑出**基线外指纹**或**桶恶化**即 rc=1
// fail loud——同桶内输出字节变化不判红（值漂移由既有 digest 闸管）。
//
// 桶恶化序（低→高）：AGREE < CLANG_REJECT < VITRO_REJECT < VITRO_TRAP
// < WRONG_VALUE < ARM_DIVERGENCE。
//
// 缓存：.corpus_fuzz_cache/（gitignored）存变体源；键 = 种子集合 hash + 规则 hash。
// 判定缓存（#309 P0）：.corpus_fuzz_judge/（gitignored）存**判定结果**——epoch 键 =
// clang 版本 + 双臂引擎产物 + sh 壳 + 规则 + 本脚本 + node 宿主七组件 hash（任一
// 变化全量失效，保守设计）；条目键 = fp + 变体源字节（语料批单条失效）。-freeze
// 不读（全量语义）但写（freeze 即真跑，结果可复用）；CI 夜间轮 CF_JUDGE_REFRESH=1
// 全量重算覆写防缓存腐化（复用 clang golden 缓存方案 A 的双闸形态）。
//
// 迁移口径（#292 批）：
//   - **全程字节语义**：Go 侧 src 是 string（按字节索引），本版一律 Buffer——语料里
//     有中文注释，按 UTF-16 code unit 索引会让 codeMask/firstIntLit 的位点整体漂移、
//     变体字节随之不同（对拍立刻可见）；
//   - detRand 是 uint64 回绕算术 → BigInt + 0xFFFF…FF 掩码（number 会在 >2^53 丢精度）；
//   - 变体生成（RNG × 11 算子 × 2 生成器）的等价性由 `testdata/variants/` 的**Go 侧
//     金样本**逐字节锁定；判定流水线（clangOutcome/parseVitro/bucketOf/latin1Fold）由
//     parity 的 `-probe` 模式对拍——全量跑一轮 ~9 分钟/侧，不适合放在对拍闸里；
//   - 写盘模式（-freeze）不进对拍（状态性）。
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { spawnSync } from "node:child_process";
import type { SpawnSyncReturns } from "node:child_process";
import { pathToFileURL } from "node:url";
import { byteCompare } from "../internal/text.mts";

// ── 规则（rules.json 单源）──

export interface Rules {
  seeds_per_suite: number;
  mutators_per_seed: number;
  seed: number;
  mutators: string[];
  suites: string[];
  generators: Array<{ name: string; count: number }>;
}

export interface BaselineEntry {
  bucket: string;
  issue?: string;
  note?: string;
}

interface Baseline {
  entries: Map<string, BaselineEntry>;
}

const RUNNER_EXE = "moonbit/_build/native/release/build/cmd/run/run.exe";
const JS_ENGINE = "moonbit/_build/js/release/build/cmd/vitro_js/vitro_js.js";
const VITRO_SH = "scripts/bin/vitro";
const CACHE_DIR = ".corpus_fuzz_cache";
const JUDGE_CACHE_DIR = ".corpus_fuzz_judge";

/** 桶恶化序（数值越大越坏）。 */
export const BUCKET_RANK: Record<string, number> = {
  AGREE: 0,
  CLANG_REJECT: 1,
  VITRO_REJECT: 2,
  VITRO_TRAP: 3,
  WRONG_VALUE: 4,
  ARM_DIVERGENCE: 5,
};

class ExitErr extends Error {
  readonly code: number;
  constructor(code: number) {
    super("exit");
    this.name = "ExitErr";
    this.code = code;
  }
}

/** Go `die`：stderr 前缀 `corpus_fuzz: `，退出码 2。 */
export function die(msg: string): never {
  process.stderr.write("corpus_fuzz: " + msg + "\n");
  throw new ExitErr(2);
}

const errText = (e: unknown): string => (e instanceof Error ? e.message : String(e));

// ── 确定性随机（uint64 回绕）──────────────────────────────────────

const MASK64 = (1n << 64n) - 1n;

export class DetRand {
  state: bigint;
  constructor(seed: bigint) {
    this.state = seed & MASK64;
  }
  next(): bigint {
    this.state = (this.state * 6364136223846793005n + 1442695040888963407n) & MASK64;
    return this.state >> 33n;
  }
  intn(n: number): number {
    if (n <= 0) return 0;
    return Number(this.next() % BigInt(n));
  }
}

// ── 可用字符掩码（跳过注释与字符串/字符字面量区域）────────────────

export function codeMask(src: Buffer): Uint8Array {
  const m = new Uint8Array(src.length);
  let i = 0;
  const n = src.length;
  while (i < n) {
    const c = src[i] as number;
    if (c === 0x2f && i + 1 < n && src[i + 1] === 0x2f) {
      // //
      while (i < n && src[i] !== 0x0a) i++;
    } else if (c === 0x2f && i + 1 < n && src[i + 1] === 0x2a) {
      // /*
      i += 2;
      while (i + 1 < n && !(src[i] === 0x2a && src[i + 1] === 0x2f)) i++;
      i += 2;
    } else if (c === 0x22 || c === 0x27) {
      const q = c;
      m[i] = 1; // 引号本体可用（变异保守）
      i++;
      while (i < n && src[i] !== q) {
        if (src[i] === 0x5c) i++;
        i++;
      }
      if (i < n) i++;
    } else {
      m[i] = 1;
      i++;
    }
  }
  return m;
}

/** 掩码内查找子串（返回字节偏移；首末字节均在掩码内才算命中）。 */
export function indexMasked(src: Buffer, sub: string, m: Uint8Array, from: number): number {
  const sb = Buffer.from(sub, "utf8");
  let i = from;
  for (;;) {
    const at = src.indexOf(sb, i);
    if (at < 0 || at + sb.length > src.length) return -1;
    if (m[at] === 1 && m[at + sb.length - 1] === 1) return at;
    i = at + 1;
  }
}

export function isIdentCh(b: number): boolean {
  return b === 0x5f || (b >= 0x61 && b <= 0x7a) || (b >= 0x41 && b <= 0x5a) || (b >= 0x30 && b <= 0x39);
}

/** 首个裸十进制整数字面量（掩码内、非标识符中段、非预处理行）；找不到返 -1。 */
export function firstIntLit(src: Buffer, m: Uint8Array): { start: number; end: number } {
  let lineStart = true;
  for (let i = 0; i < src.length; i++) {
    if (src[i] === 0x0a) {
      lineStart = true;
      continue;
    }
    if (lineStart) {
      let j = i;
      while (j < src.length && (src[j] === 0x20 || src[j] === 0x09)) j++;
      if (j < src.length && src[j] === 0x23) {
        // '#' 预处理行整行跳过
        while (j < src.length && src[j] !== 0x0a) j++;
        i = j - 1;
        continue;
      }
      lineStart = false;
    }
    if (m[i] !== 1 || (i > 0 && isIdentCh(src[i - 1] as number))) continue;
    const c = src[i] as number;
    if (c >= 0x30 && c <= 0x39) {
      let j = i;
      while (j < src.length && (src[j] as number) >= 0x30 && (src[j] as number) <= 0x39) j++;
      if (j >= src.length || !isIdentCh(src[j] as number)) return { start: i, end: j };
    }
  }
  return { start: -1, end: -1 };
}

export function isAllDigits(s: string): boolean {
  if (s === "") return false;
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c < 0x30 || c > 0x39) return false;
  }
  return true;
}

export function isSep(b: number): boolean {
  return (
    b === 0x20 || b === 0x09 || b === 0x0a || b === 0x0d || b === 0x3b || // ' ' \t \n \r ;
    b === 0x2c || b === 0x28 || b === 0x29 || b === 0x7b || b === 0x7d || // , ( ) { }
    b === 0x5b || b === 0x5d || b === 0x3d || b === 0x3c || b === 0x3e || // [ ] = < >
    b === 0x2b || b === 0x2d || b === 0x2a || b === 0x2f || b === 0x25 // + - * / %
  );
}

/** 裸类型声明替换首处（跳过 unsigned/long/short 前缀语境与标识符中段）。 */
export function replaceFirstBareType(src: Buffer, from: string, to: string): Buffer {
  const m = codeMask(src);
  const fb = Buffer.from(from, "utf8");
  let idx = indexMasked(src, from, m, 0);
  while (idx >= 0) {
    const pre = idx >= 9 ? src.subarray(idx - 9, idx).toString("utf8") : "";
    if (
      !pre.endsWith("unsigned ") &&
      !pre.endsWith("long ") &&
      !pre.endsWith("short ") &&
      (idx === 0 || !isIdentCh(src[idx - 1] as number))
    ) {
      return Buffer.concat([src.subarray(0, idx), Buffer.from(to, "utf8"), src.subarray(idx + fb.length)]);
    }
    idx = indexMasked(src, from, m, idx + 1);
  }
  return src;
}

// ── 变异算子（无匹配 → 原样返回；对拍 AGREE，无害锁定）──────────────

export type MutatorFn = (src: Buffer, r: DetRand) => Buffer;

const withMask = (src: Buffer, f: (m: Uint8Array) => Buffer): Buffer => f(codeMask(src));

export const MUTATORS: Array<{ name: string; fn: MutatorFn }> = [
  {
    name: "brace_wrap",
    fn: (src) =>
      withMask(src, (m) => {
        const { start: s, end: e } = firstIntLit(src, m);
        if (s < 0) return src;
        // 前溯最近赋值号（同一行内、跳过空白）
        let k = s - 1;
        while (k >= 0 && (src[k] === 0x20 || src[k] === 0x09)) k--;
        if (k < 0 || src[k] !== 0x3d || (k - 1 >= 0 && src[k - 1] === 0x3d)) return src;
        return Buffer.concat([src.subarray(0, k + 1), Buffer.from(" {"), src.subarray(s, e), Buffer.from("}"), src.subarray(e)]);
      }),
  },
  {
    name: "char_escape",
    fn: (src, r) => {
      const m = codeMask(src);
      const escapes = ["'\\n'", "'\\''", "'\\\"'", "'\\\\'", "'\\t'", "'\\0'"];
      const repl = escapes[r.intn(escapes.length)] as string;
      for (let i = 0; i + 3 <= src.length; i++) {
        if (m[i] === 1 && src[i] === 0x27 && src[i + 2] === 0x27 && src[i + 1] !== 0x5c && src[i + 1] !== 0x27) {
          return Buffer.concat([src.subarray(0, i), Buffer.from(repl, "utf8"), src.subarray(i + 3)]);
        }
      }
      return src;
    },
  },
  {
    name: "init_partial",
    fn: (src) => {
      // 首个多元素初始化列表去尾元素（部分填充面）
      const m = codeMask(src);
      for (let i = 0; i < src.length; i++) {
        if (m[i] !== 1 || src[i] !== 0x7b || i + 1 >= src.length || m[i + 1] !== 1) continue;
        let depth = 0;
        let j = i;
        for (; j < src.length && src[j] !== 0x0a; j++) {
          if (m[j] !== 1) continue;
          if (src[j] === 0x7b) depth++;
          else if (src[j] === 0x7d) {
            depth--;
            if (depth === 0) break;
          }
        }
        if (j >= src.length || depth !== 0) continue;
        const inner = src.subarray(i + 1, j);
        const comma = inner.lastIndexOf(0x2c);
        if (comma > 0) {
          return Buffer.concat([src.subarray(0, i + 1), inner.subarray(0, comma), src.subarray(j)]);
        }
      }
      return src;
    },
  },
  {
    name: "static_inject",
    fn: (src) => {
      // 函数体内首个 4 空格缩进的声明行加 static（#171/#179 面）
      const lines = splitLines(src);
      for (let idx = 0; idx < lines.length; idx++) {
        const ln = lines[idx] as Buffer;
        const t = ln.subarray(leadingSpaces(ln));
        const tstr = t.toString("utf8");
        if (
          t.length > 0 &&
          t[0] !== 0x2f &&
          t[0] !== 0x2a &&
          t[0] !== 0x23 &&
          startsWith(ln, "    ") &&
          !startsWith(ln, "        ") &&
          (tstr.startsWith("int ") || tstr.startsWith("char ") || tstr.startsWith("double ") || tstr.startsWith("long "))
        ) {
          if (ln.includes(Buffer.from("static"))) continue;
          lines[idx] = Buffer.concat([Buffer.from("    static "), t]);
          return joinLines(lines);
        }
      }
      return src;
    },
  },
  {
    name: "brace_strip",
    fn: (src) => {
      // #183 逆面：首个 `= {<int>}` 解包（单元素包裹 ≡ 裸形态）
      const m = codeMask(src);
      for (let i = 0; i < src.length; i++) {
        if (m[i] !== 1 || src[i] !== 0x7b || i + 1 >= src.length || m[i + 1] !== 1) continue;
        const j = src.subarray(i).indexOf(0x7d);
        if (j < 0) break;
        const inner = src.subarray(i + 1, i + j).toString("utf8");
        const t = inner.trim();
        if (t !== "" && isAllDigits(t)) {
          let k = i - 1;
          while (k >= 0 && (src[k] === 0x20 || src[k] === 0x09)) k--;
          if (k >= 0 && src[k] === 0x3d) {
            return Buffer.concat([src.subarray(0, i + 1), Buffer.from(t, "utf8"), src.subarray(i + j)]);
          }
        }
        i += j;
      }
      return src;
    },
  },
  {
    name: "nested2flat",
    fn: (src) => {
      // #179/#180 等价变换：嵌套 {{a,b},{c,d}} 拍平（brace elision 两侧应同值）
      const m = codeMask(src);
      for (let i = 0; i + 1 < src.length; i++) {
        if (m[i] !== 1 || src[i] !== 0x7b || src[i + 1] !== 0x7b) continue;
        let depth = 0;
        let j = i;
        for (; j < src.length; j++) {
          if (m[j] !== 1) continue;
          if (src[j] === 0x7b) depth++;
          else if (src[j] === 0x7d) {
            depth--;
            if (depth === 0) break;
          }
        }
        if (j >= src.length || depth !== 0) continue;
        const inner = src.subarray(i + 1, j);
        const flat = Buffer.from(inner.filter((b) => b !== 0x7b && b !== 0x7d));
        return Buffer.concat([src.subarray(0, i + 1), flat, src.subarray(j)]);
      }
      return src;
    },
  },
  {
    name: "memset_zero",
    fn: (src) => {
      // 首个 `{0}` 整体初始化展开为 `{0,0,0}`（#19 零初始化族邻面）
      const m = codeMask(src);
      const idx = indexMasked(src, "= {0}", m, 0);
      if (idx < 0) return src;
      return Buffer.concat([src.subarray(0, idx), Buffer.from("= {0, 0, 0}"), src.subarray(idx + 5)]);
    },
  },
  {
    name: "cmp_swap",
    fn: (src) => {
      // 首个比较换向：`a < b` → `b > a`（等价变换）
      const m = codeMask(src);
      const rev: Record<string, string> = { " < ": " > ", " > ": " < ", " <= ": " >= ", " >= ": " <= " };
      for (const op of [" <= ", " >= ", " < ", " > "]) {
        const j = indexMasked(src, op, m, 0);
        if (j < 0) continue;
        let a = j - 1;
        let b = j + op.length;
        while (a > 0 && !isSep(src[a - 1] as number)) a--;
        while (b < src.length && !isSep(src[b] as number)) b++;
        if (a < j && b > j + op.length) {
          return Buffer.concat([
            src.subarray(0, a),
            src.subarray(j + op.length, b),
            Buffer.from(rev[op] as string),
            src.subarray(a, j),
            src.subarray(b),
          ]);
        }
      }
      return src;
    },
  },
  {
    name: "div2shift",
    fn: (src) => {
      // 首个 `/ 2` → `>> 1`（负数域两侧应同现此差）
      const m = codeMask(src);
      const idx = indexMasked(src, "/ 2", m, 0);
      if (idx < 0) return src;
      return Buffer.concat([src.subarray(0, idx), Buffer.from(">> 1"), src.subarray(idx + 3)]);
    },
  },
  {
    name: "paren_wrap",
    fn: (src) => {
      // 首个二元算术段加括号（解析等价）
      const m = codeMask(src);
      for (const op of [" + ", " - ", " * "]) {
        const j = indexMasked(src, op, m, 0);
        if (j < 0) continue;
        let a = j - 1;
        let b = j + op.length;
        while (a > 0 && !isSep(src[a - 1] as number)) a--;
        while (b < src.length && !isSep(src[b] as number)) b++;
        if (a < j && b > j + op.length) {
          return Buffer.concat([src.subarray(0, a), Buffer.from("("), src.subarray(a, b), Buffer.from(")"), src.subarray(b)]);
        }
      }
      return src;
    },
  },
  {
    name: "cast_strip",
    fn: (src) => {
      // 首个单类型 cast 剥除（显式转隐式应同值）
      const m = codeMask(src);
      for (const t of ["(int)", "(char)", "(double)", "(long)", "(unsigned)"]) {
        const j = indexMasked(src, t, m, 0);
        if (j < 0) continue;
        return Buffer.concat([src.subarray(0, j), src.subarray(j + t.length)]);
      }
      return src;
    },
  },
];

export function mutatorByName(name: string): MutatorFn | null {
  for (const mu of MUTATORS) if (mu.name === name) return mu.fn;
  return null;
}

// ── Buffer 小工具（Go strings 的字节等价面）────────────────────────

function splitLines(src: Buffer): Buffer[] {
  const out: Buffer[] = [];
  let start = 0;
  for (let i = 0; i < src.length; i++) {
    if (src[i] === 0x0a) {
      out.push(src.subarray(start, i));
      start = i + 1;
    }
  }
  out.push(src.subarray(start));
  return out;
}

function joinLines(lines: Buffer[]): Buffer {
  const parts: Buffer[] = [];
  for (let i = 0; i < lines.length; i++) {
    parts.push(lines[i] as Buffer);
    if (i !== lines.length - 1) parts.push(Buffer.from("\n"));
  }
  return Buffer.concat(parts);
}

function leadingSpaces(ln: Buffer): number {
  let n = 0;
  while (n < ln.length && ln[n] === 0x20) n++;
  return n;
}

function startsWith(buf: Buffer, prefix: string): boolean {
  const p = Buffer.from(prefix, "utf8");
  return buf.length >= p.length && buf.subarray(0, p.length).equals(p);
}

// ── 域生成器（凭空造域对抗，与算子互补）──────────────────────────

class SourceBuilder {
  private lines: string[] = [];
  line(s: string): void {
    this.lines.push(s);
  }
  linef(fmt: string, ...args: Array<string | number>): void {
    let i = 0;
    this.lines.push(fmt.replace(/%[sd]/g, () => String(args[i++])));
  }
  build(): Buffer {
    return Buffer.from(this.lines.map((l) => l + "\n").join(""), "utf8");
  }
}

/** 域 1：char 全局/局部/static/邻接排布的算术字节域（#177/#198 定向）。 */
export function genCharArith(r: DetRand): Buffer {
  const edgeVals = [-129, -128, -127, -1, 0, 1, 47, 126, 127, 128, 129, 200, 254, 255, 256];
  const v1 = edgeVals[r.intn(edgeVals.length)] as number;
  const v2 = edgeVals[r.intn(edgeVals.length)] as number;
  const scopes = ["global", "local", "static", "adjacent"];
  const scope = scopes[r.intn(scopes.length)] as string;
  const tys = ["char", "unsigned char"];
  const uty = tys[r.intn(tys.length)] as string;
  const ops: Array<[string, string]> = [
    ["+=", "1"],
    ["-=", "1"],
    ["*=", "2"],
    ["++", ""],
    ["--", ""],
  ];
  const op = ops[r.intn(ops.length)] as [string, string];

  const b = new SourceBuilder();
  b.line("#include <stdio.h>");
  b.line("");
  if (scope === "global") b.linef("%s c1 = %d; %s c2 = %d; char nb = 'Z';", uty, v1, uty, v2);
  else if (scope === "static") b.linef("static %s c1 = %d; static %s c2 = %d;", uty, v1, uty, v2);
  else b.linef("%s nb = 'Z';", uty);
  b.line("int main(void) {");
  if (scope === "local" || scope === "adjacent") b.linef("  %s c1 = %d; %s c2 = %d;", uty, v1, uty, v2);
  if (scope === "adjacent") b.line("  char a1 = 'A', a2 = 'B', a3 = 'C';");
  if (op[1] === "") {
    b.linef("  c1%s; c2%s;", op[0], op[0]);
  } else {
    b.linef("  c1 = %d; c2 = %d;", v1, v2);
    b.linef("  c1 %s %s; c2 %s %s;", op[0], op[1], op[0], op[1]);
  }
  b.line('  printf("%d %d\\n", c1, c2);');
  if (scope === "adjacent") b.line('  printf("%c%c%c\\n", a1, a2, a3);');
  b.line("  return 0;");
  b.line("}");
  return b.build();
}

/** 域 2：六诊断面的合法邻域（#175/#174/#182/#156/#154 防误伤）。 */
export function genDiagLegal(r: DetRand): Buffer {
  const k = r.intn(6);
  const b = new SourceBuilder();
  b.line("#include <stdio.h>");
  if (k === 0) {
    const sizes = [2, 3, 5];
    const sz = sizes[r.intn(sizes.length)] as number;
    const muls = [1, 2, 3];
    const m = muls[r.intn(muls.length)] as number;
    b.linef("int arr1[%d]; int arr2[%d];", sz, sz);
    b.line("int main(void) {");
    b.linef("  for (int i = 0; i < %d; i++) arr1[i] = i * %d;", sz, m);
    b.line("  int *p = arr1;");
    b.line('  printf("%d %d\\n", arr1[0], p[1]);');
    b.line("  return 0; }");
  } else if (k === 1) {
    const members = [2, 3, 4];
    const m = members[r.intn(members.length)] as number;
    b.line("struct S { int f0");
    for (let j = 1; j < m; j++) b.linef(", f%d", j);
    b.line("; };");
    b.line("int main(void) { struct S s = {0};");
    b.linef("  s.f0 = %d; s.f1 = s.f0 + %d;", r.intn(100), 1 + r.intn(9));
    b.line('  printf("%d\\n", s.f0 + s.f1);');
    b.line("  return 0; }");
  } else if (k === 2) {
    b.linef("enum A { X1 = %d };", r.intn(10));
    b.line("enum B { Y1, Y2 };");
    b.line("int main(void) { enum A a = X1; enum B b = Y2;");
    b.line('  printf("%d %d\\n", a, b);');
    b.line("  return 0; }");
  } else if (k === 3) {
    b.linef("int main(void) { register int r = %d; register int s = r * %d;", 1 + r.intn(50), 2 + r.intn(4));
    b.line('  printf("%d\\n", r + s);');
    b.line("  return r + s; }");
  } else if (k === 4) {
    b.line("typedef int T; typedef int T; typedef double D;");
    const divs = [2, 4];
    b.linef("int main(void) { T v = %d; D w = v / %d.0;", 1 + r.intn(99), divs[r.intn(2)] as number);
    b.line('  printf("%.1f\\n", w);');
    b.line("  return 0; }");
  } else {
    const sizes = [1, 4, 7];
    const sz = sizes[r.intn(sizes.length)] as number;
    b.linef("int g[%d];", sz);
    b.line("int main(void) {");
    b.linef('  char s[] = "ok%d"; int a[%d] = {0};', sz, sz);
    b.linef("  for (int i = 0; i < %d; i++) a[i] = i;", sz);
    b.linef('  printf("%%d %%s %%d\\n", a[%d], s, (int)sizeof(g));', sz - 1);
    b.line("  return 0; }");
  }
  return b.build();
}

export const GENERATORS: Array<{ name: string; fn: (r: DetRand, idx: number) => Buffer }> = [
  { name: "char_arith", fn: (r) => genCharArith(r) },
  { name: "diag_legal", fn: (r) => genDiagLegal(r) },
];

export function generatorByName(name: string): ((r: DetRand, idx: number) => Buffer) | null {
  for (const g of GENERATORS) if (g.name === name) return g.fn;
  return null;
}

// ── 进程对拍 ──────────────────────────────────────────────────────

export interface Outcome {
  status: string; // OK / REJECT / TRAP / CRASH
  out: string;
}

export function norm(s: string): string {
  return s.split("\r\n").join("\n").split("\r").join("");
}

/** 同步 sleep（Go 的重试退避用；主流程是同步的，不能让出事件循环）。 */
function sleepSync(ms: number): void {
  const sab = new SharedArrayBuffer(4);
  Atomics.wait(new Int32Array(sab), 0, 0, ms);
}

interface CmdResult {
  stdout: string;
  stderr: string;
  rc: number;
}

export function runCmd(
  args: readonly string[],
  dir: string,
  timeoutMs = 20_000,
  dec: "utf8" | "latin1" = "utf8",
): CmdResult {
  const r: SpawnSyncReturns<Buffer> = spawnSync(args[0] as string, args.slice(1), {
    cwd: dir,
    input: Buffer.alloc(0), // 显式空 stdin（Windows 上 null = 继承父句柄 → scanf 族挂死）
    timeout: timeoutMs,
    maxBuffer: 64 * 1024 * 1024,
  });
  let rc = 0;
  if (r.error !== undefined) rc = -98; // 超时/无法启动——单例有界
  else if ((r.status ?? -1) !== 0) rc = r.status as number;
  return {
    stdout: (r.stdout ?? Buffer.alloc(0)).toString(dec),
    stderr: (r.stderr ?? Buffer.alloc(0)).toString("utf8"),
    rc,
  };
}

/** 相对路径绝对化（槽位隔离后 exe 以 workdir 为 cwd 启动）。 */
export function absPath(p: string): string {
  return path.isAbsolute(p) ? p : path.resolve(p);
}

/**
 * clang 侧判定（-O0 编译 + 运行）。编译失败按 clang_direct 同判据退避重试 2 次
 * （Defender 实时扫描锁 a.exe 令 clang 瞬态非零）。
 */
export function clangOutcome(src: string, workdir: string): Outcome {
  const exe = path.join(workdir, "a.exe");
  let r = runCmd(["clang", "-O0", src, "-o", exe], ".");
  if (r.rc !== 0) {
    for (let attempt = 0; attempt < 2; attempt++) {
      sleepSync(1000 << attempt);
      r = runCmd(["clang", "-O0", src, "-o", exe], ".");
      if (r.rc === 0) break;
    }
  }
  if (r.rc !== 0) return { status: "REJECT", out: norm(r.stderr) };
  // stdout 走 latin1 解码（字节↔码点双射，无 U+FFFD 折叠）——与 parseVitro 折回域
  // 同域后 byteCompare 等价 Go 版纯字节比较。utf8 解码会与折回域失配：UTF-8 多字节
  // 输出（col_utf8_units 中文形态）字节相同却被判 WRONG_VALUE（#301 merge 批实证）。
  const run = runCmd([absPath(exe)], workdir, 20_000, "latin1");
  fs.rmSync(exe, { force: true });
  if (run.rc !== 0) {
    // 崩溃域（Windows 异常码 ~3.2e9）与合法非零 return（0..255）区分
    if (run.rc > 255 || run.rc < 0) return { status: "OK", out: "EXIT:" + String(run.rc) };
    return { status: "OK", out: norm(run.stdout) };
  }
  return { status: "OK", out: norm(run.stdout) };
}

export function vitroNative(src: string): Outcome {
  const r = runCmd([RUNNER_EXE, src, "--json"], ".");
  return parseVitro(r.stdout);
}

export function vitroJs(src: string): Outcome {
  const r = runCmd(["sh", VITRO_SH, "run", src, "--json"], ".");
  return parseVitro(r.stdout);
}

export function parseVitro(ndjson: string): Outcome {
  let diagOK = "";
  let stdout = "";
  let status = "";
  let trap = "";
  for (const rawLine of ndjson.split("\n")) {
    const line = rawLine.trim();
    if (!line.startsWith("{")) continue;
    let f: Rec;
    try {
      f = JSON.parse(line) as Rec;
    } catch {
      continue;
    }
    const t = typeof f["type"] === "string" ? (f["type"] as string) : "";
    const result = (f["frame"] as Rec | undefined)?.["result"] as Rec | undefined;
    if (t === "diag") {
      diagOK = "ok";
      if (result?.["ok"] !== true) diagOK = "reject";
    } else if (t === "stdout") {
      // JSON 出口把单字节 0x80–0xFF 按 Latin-1 码点转义 → 折回字节域再比
      stdout = latin1Fold(typeof result?.["delta"] === "string" ? (result["delta"] as string) : "");
    } else if (t === "run") {
      status = typeof result?.["status"] === "string" ? (result["status"] as string) : "";
      trap = typeof result?.["trap"] === "string" ? (result["trap"] as string) : "";
    }
  }
  if (diagOK === "reject") return { status: "REJECT", out: "" };
  if (diagOK === "") return { status: "CRASH", out: "" };
  if (status === "trap") return { status: "TRAP", out: trap };
  return { status: "OK", out: norm(stdout) };
}

type Rec = Record<string, unknown>;

/** UTF-8 的 U+0080–U+00FF 双字节序折回 Latin-1 单字节（JSON 通道语境）。 */
export function latin1Fold(s: string): string {
  const b = Buffer.from(s, "utf8");
  const out: number[] = [];
  for (let i = 0; i < b.length; ) {
    const c = b[i] as number;
    if (c === 0xc2 && i + 1 < b.length) {
      out.push(b[i + 1] as number);
      i += 2;
      continue;
    }
    if (c === 0xc3 && i + 1 < b.length) {
      out.push(((b[i + 1] as number) + 0x40) & 0xff);
      i += 2;
      continue;
    }
    out.push(c);
    i++;
  }
  return Buffer.from(out).toString("latin1");
}

/** 三方分类。 */
export function bucketOf(c: Outcome, nj: Outcome, na: Outcome): string {
  if (nj.status === "OK" && na.status === "OK" && nj.out !== na.out) return "ARM_DIVERGENCE";
  let vt = nj;
  if (vt.status === "OK" && na.status !== "OK") vt = na;
  else if (vt.status !== "OK" && na.status === "OK") vt = na;
  if (c.status === "REJECT") {
    if (vt.status === "REJECT") return "AGREE";
    return "CLANG_REJECT";
  }
  switch (vt.status) {
    case "REJECT":
      return "VITRO_REJECT";
    case "TRAP":
      return "VITRO_TRAP";
    case "CRASH":
      return "ARM_DIVERGENCE";
  }
  if (vt.out === c.out) return "AGREE";
  return "WRONG_VALUE";
}

// ── 判定缓存（#309 P0）────────────────────────────────────────────
//
// bucket 是 (变体源, clang 版本, js 引擎, native 引擎, 壳, 判定口径, node 宿主)
// 的确定性函数——把这七元组全部 hash 进 epoch 键，任一变化整体失效（保守：宁多
// 跑不少跑；node 宿主入键 = CI 预装 node 漂移不携旧 bucket）；条目键再叠加
// fp + 变体源字节，语料批只失效变化的单条。缓存命中 ⇒ 跳过三方进程对拍直接用
// 历史 bucket 判红——本地定性循环 9m/轮 → 秒级，CI 引擎未变批 8.7m → ~1m。

export interface JudgeEpochInputs {
  clang: string;
  native: string;
  jsEngine: string;
  shell: string;
  rules: string;
  script: string;
  node: string;
}

/** epoch 键（纯函数，24 hex）：七组件任一变化 ⇒ 换目录全量失效。 */
export function judgeEpochKey(x: JudgeEpochInputs): string {
  const h = crypto.createHash("sha256");
  h.update(`clang:${x.clang}\nnative:${x.native}\njs:${x.jsEngine}\n`);
  h.update(`shell:${x.shell}\nrules:${x.rules}\nscript:${x.script}\n`);
  h.update(`node:${x.node}\n`);
  return h.digest("hex").slice(0, 24);
}

/** 条目键（纯函数）：fp + 变体源字节——同 fp 源变（语料批）单条失效。 */
export function judgeEntryName(fp: string, src: Buffer): string {
  return crypto.createHash("sha256").update(fp, "utf8").update(src).digest("hex") + ".json";
}

export interface JudgeCacheable {
  fp: string;
  bytes: Buffer;
}

interface JudgeEntryFile {
  fp: string;
  bucket: string;
}

/**
 * 读条目；miss 返 null。损坏 JSON / fp 窜条 / 非法桶名一律按 miss **fail open
 * 到真跑**（缓存是加速层不是真相源——基线判红仍以真跑为准）。
 */
export function judgeCacheGet(dir: string, v: JudgeCacheable): string | null {
  let raw: JudgeEntryFile;
  try {
    raw = JSON.parse(fs.readFileSync(path.join(dir, judgeEntryName(v.fp, v.bytes)), "utf8")) as JudgeEntryFile;
  } catch {
    return null;
  }
  if (raw.fp !== v.fp) return null;
  if (typeof raw.bucket !== "string" || !Object.hasOwn(BUCKET_RANK, raw.bucket)) return null;
  return raw.bucket;
}

export function judgeCachePut(dir: string, v: JudgeCacheable, bucket: string): void {
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, judgeEntryName(v.fp, v.bytes)), JSON.stringify({ fp: v.fp, bucket }) + "\n", "utf8");
}

function hashFileShort(p: string): string {
  try {
    return crypto.createHash("sha256").update(fs.readFileSync(p)).digest("hex").slice(0, 32);
  } catch {
    return `<missing:${p}>`;
  }
}

/** 收集本机七组件算 epoch（clang 首行 + 四文件 hash + 规则字节 + node 版本）。 */
export function collectJudgeEpochInputs(rulesBytes: Buffer): JudgeEpochInputs {
  const cv = runCmd(["clang", "--version"], ".", 10_000);
  const clangLine = cv.rc === 0 ? (cv.stdout.split("\n")[0] ?? "").trim() : "<no-clang>";
  return {
    clang: clangLine,
    native: hashFileShort(RUNNER_EXE),
    jsEngine: hashFileShort(JS_ENGINE),
    shell: hashFileShort(VITRO_SH),
    rules: crypto.createHash("sha256").update(rulesBytes).digest("hex").slice(0, 32),
    script: hashFileShort(import.meta.filename),
    node: process.version,
  };
}

/** 清掉非当前 epoch 的子目录（防本地/CI 缓存目录无限膨胀）。 */
export function pruneJudgeEpochs(keepEpoch: string, base: string = JUDGE_CACHE_DIR): void {
  let ents: fs.Dirent[];
  try {
    ents = fs.readdirSync(base, { withFileTypes: true });
  } catch {
    return;
  }
  for (const e of ents) {
    if (e.isDirectory() && e.name !== keepEpoch) {
      fs.rmSync(path.join(base, e.name), { recursive: true, force: true });
    }
  }
}

// ── 主流程 ────────────────────────────────────────────────────────

export function runMain(argv: readonly string[]): number {
  try {
    return mainFlow(argv);
  } catch (e) {
    if (e instanceof ExitErr) return e.code;
    throw e;
  }
}

interface Opts {
  freeze: boolean;
  rules: string;
  baseline: string;
  regen: boolean;
  probe: string;
}

export function parseArgs(argv: readonly string[]): Opts {
  const o: Opts = {
    freeze: false,
    rules: "scripts/corpus_fuzz/rules.json",
    baseline: "scripts/corpus_fuzz/fuzz_baseline.json",
    regen: false,
    probe: "",
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i] as string;
    const eq = a.indexOf("=");
    const name = eq >= 0 ? a.slice(0, eq) : a;
    const inline = eq >= 0 ? a.slice(eq + 1) : undefined;
    const take = (): string => {
      if (inline !== undefined) return inline;
      const next = argv[i + 1];
      if (next === undefined) die(`${name} 缺参数值`);
      i++;
      return next;
    };
    if (name === "-freeze") o.freeze = true;
    else if (name === "-regen") o.regen = true;
    else if (name === "-rules") o.rules = take();
    else if (name === "-baseline") o.baseline = take();
    else if (name === "-probe") o.probe = take();
    else die(`未知参数 ${a}`);
  }
  return o;
}

export interface PlannedVariant {
  /** 指纹（基线键） */
  fp: string;
  /** 缓存目录内文件名 */
  filename: string;
  /** 变体源字节 */
  bytes: Buffer;
  /** 溯源信息（CF_TRACE 用） */
  suite: string;
  seed: string;
  mutator: string;
}

/**
 * 生成计划：算子段（每种子确定性抽 mutators_per_seed 个算子）+ 生成器段。
 * **纯函数**（不编译、不落盘）——测试以它逐字节比对 Go 侧金样本。
 */
export function planVariants(
  rules: Rules,
  seeds: ReadonlyArray<{ suite: string; name: string; path: string; absPath?: string }>,
): PlannedVariant[] {
  const out: PlannedVariant[] = [];
  for (const s of seeds) {
    // 读盘走 absPath（测试用），但 RNG 种子仍取**相对路径长度**（与 Go 侧一致）
    const src = fs.readFileSync(s.absPath ?? s.path);
    // 每种子确定性取 mutators_per_seed 个算子
    const r = new DetRand(BigInt(rules.seed) + BigInt(s.path.length));
    const pool = [...rules.mutators];
    for (let i = pool.length - 1; i > 0; i--) {
      const j = r.intn(i + 1);
      const tmp = pool[i] as string;
      pool[i] = pool[j] as string;
      pool[j] = tmp;
    }
    const chosen = pool.length > rules.mutators_per_seed ? pool.slice(0, rules.mutators_per_seed) : pool;
    for (const mname of chosen) {
      const mu = mutatorByName(mname) as MutatorFn;
      const mut = mu(src, r);
      const stem = s.name.endsWith(".c") ? s.name.slice(0, -2) : s.name;
      out.push({
        fp: `${s.suite}/${s.name}|${mname}`,
        filename: `${s.suite}_${stem}_${mname}.c`,
        bytes: mut,
        suite: s.suite,
        seed: s.name,
        mutator: mname,
      });
    }
  }
  // 生成器段：凭空造域 × 确定性随机参数（键空间 gen:<域名>/<序号>）
  for (const gr of rules.generators) {
    const gen = generatorByName(gr.name);
    if (gen === null) die(`未知生成器名 ${JSON.stringify(gr.name)}（规则与实现失配——fail loud）`);
    for (let i = 0; i < gr.count; i++) {
      const r = new DetRand(BigInt(rules.seed) * 0x9e3779b9n + BigInt(gr.name.length) * 31n + BigInt(i));
      const bytes = gen(r, i);
      out.push({
        fp: `gen:${gr.name}/${String(i).padStart(3, "0")}`,
        filename: `gen_${gr.name}_${String(i).padStart(3, "0")}.c`,
        bytes,
        suite: "gen",
        seed: gr.name,
        mutator: String(i).padStart(3, "0"),
      });
    }
  }
  return out;
}

/// 基线序列化（转义口径对齐 Go MarshalIndent + SetEscapeHTML——PR #289
/// P2-1 立的口径，.mts 迁移时曾丢失：freeze 把既有 \u003e 形态条目反向
/// 漂移成裸 `>` 3 处实锤）。`<` `>` `&` 与 U+2028/U+2029 在字符串值内转
/// \uXXXX；这些字符不出现在 JSON 结构位（键为 ASCII 指纹），整体替换安全；
/// U+2028/2029 JSON.stringify（ES2019 well-formed）本就转义，显式两行
/// 是口径自述。键序 = 字节字典序（调用方已 sort）。
export function marshalBaselineText(
  entries: Record<string, BaselineEntry>,
): string {
  const ls = String.fromCharCode(0x2028);
  const ps = String.fromCharCode(0x2029);
  return (
    JSON.stringify({ entries }, null, 2)
      .replaceAll("<", "\\u003c")
      .replaceAll(">", "\\u003e")
      .replaceAll("&", "\\u0026")
      .replaceAll(ls, "\\u2028")
      .replaceAll(ps, "\\u2029") + "\n"
  );
}

function mainFlow(argv: readonly string[]): number {
  const opts = parseArgs(argv);

  if (opts.probe !== "") {
    const c = clangOutcome(opts.probe, CACHE_DIR);
    const nj = vitroJs(opts.probe);
    const na = vitroNative(opts.probe);
    const q = (s: string): string => JSON.stringify(s);
    process.stdout.write(`clang: ${c.status}|${q(c.out)}\n`);
    process.stdout.write(`js:    ${nj.status}|${q(nj.out)}\n`);
    process.stdout.write(`native:${na.status}|${q(na.out)}\n`);
    process.stdout.write(`bucket: ${bucketOf(c, nj, na)}\n`);
    return 0;
  }

  let ruleBytes: Buffer;
  try {
    ruleBytes = fs.readFileSync(opts.rules);
  } catch (e) {
    die(`读规则失败：${errText(e)}`);
  }
  let rules: Rules;
  try {
    rules = JSON.parse(ruleBytes.toString("utf8")) as Rules;
  } catch (e) {
    die(`规则 JSON 解析失败：${errText(e)}`);
  }
  for (const mn of rules.mutators) {
    if (mutatorByName(mn) === null) die(`未知算子名 ${JSON.stringify(mn)}（规则与实现失配——fail loud）`);
  }

  // 种子收集 + 确定性抽样
  interface SeedFile {
    suite: string;
    name: string;
    path: string;
  }
  const seeds: SeedFile[] = [];
  for (const suite of rules.suites) {
    const dir = path.join("corpus", suite);
    let ents: fs.Dirent[];
    try {
      ents = fs.readdirSync(dir, { withFileTypes: true });
    } catch (e) {
      die(`读套件 ${suite} 失败：${errText(e)}`);
    }
    for (const e of ents) {
      if (e.name.endsWith(".c")) seeds.push({ suite, name: e.name, path: path.join(dir, e.name) });
    }
  }
  seeds.sort((a, b) => byteCompare(a.path, b.path));
  const pick: SeedFile[] = [];
  const bySuite = new Map<string, SeedFile[]>();
  for (const s of seeds) {
    const cur = bySuite.get(s.suite);
    if (cur === undefined) bySuite.set(s.suite, [s]);
    else cur.push(s);
  }
  for (const suite of rules.suites) {
    const list = bySuite.get(suite) ?? [];
    const r = new DetRand(BigInt(rules.seed) + 0x9e3779b9n);
    if (rules.seeds_per_suite >= list.length) {
      pick.push(...list);
      continue;
    }
    const chosen = new Set<number>();
    while (chosen.size < rules.seeds_per_suite) chosen.add(r.intn(list.length));
    for (let i = 0; i < list.length; i++) if (chosen.has(i)) pick.push(list[i] as SeedFile);
  }
  pick.sort((a, b) => byteCompare(a.path, b.path));

  // 缓存键：种子集合 + 规则内容
  const keyParts: Buffer[] = [];
  for (const s of pick) keyParts.push(Buffer.from(s.path, "utf8"));
  keyParts.push(ruleBytes);
  const cacheKey = crypto.createHash("sha256").update(Buffer.concat(keyParts)).digest("hex").slice(0, 24);
  const keyFile = path.join(CACHE_DIR, "KEY");
  if (!opts.regen) {
    try {
      if (fs.readFileSync(keyFile, "utf8").trim() === cacheKey) {
        process.stdout.write(`gen：缓存命中（key=${cacheKey}）——变体复用\n`);
      }
    } catch {
      // 无 KEY：首次生成
    }
  } else {
    fs.rmSync(CACHE_DIR, { recursive: true, force: true });
  }
  if (!fs.existsSync(keyFile)) {
    fs.mkdirSync(CACHE_DIR, { recursive: true });
    fs.writeFileSync(keyFile, cacheKey, "utf8");
  }

  // 基线载入（freeze 同样读旧——合并语义：保留人工定性标注）
  const base: Baseline = { entries: new Map() };
  if (fs.existsSync(opts.baseline)) {
    let parsed: { entries?: Record<string, BaselineEntry> };
    try {
      parsed = JSON.parse(fs.readFileSync(opts.baseline, "utf8")) as typeof parsed;
    } catch (e) {
      die(`基线 JSON 解析失败：${errText(e)}`);
    }
    for (const [k, v] of Object.entries(parsed.entries ?? {})) base.entries.set(k, v);
  } else if (!opts.freeze) {
    die(`基线缺失（首跑用 -freeze 生成）：${opts.baseline}`);
  }

  // 判定缓存 epoch（#309 P0）：六组件任一变化全量失效；freeze 轮不读但写
  // （freeze 即全量真跑，结果可复用）；CF_JUDGE_REFRESH=1（CI 夜间轮）无视
  // 缓存全量重算覆写——防缓存腐化的第二道闸。
  const judgeEpoch = judgeEpochKey(collectJudgeEpochInputs(ruleBytes));
  const judgeDir = path.join(JUDGE_CACHE_DIR, judgeEpoch);
  const judgeRefresh = process.env["CF_JUDGE_REFRESH"] === "1";
  let judgeHit = 0;
  let judgeMiss = 0;

  let newFp = 0;
  let worsened = 0;
  let agree = 0;
  let total = 0;
  const report: string[] = [];

  const handle = (fp: string, bucket: string): void => {
    if (bucket === "AGREE") agree++;
    if (opts.freeze) {
      const old = base.entries.get(fp);
      base.entries.set(fp, { bucket, issue: old?.issue, note: old?.note });
      return;
    }
    const ent = base.entries.get(fp);
    if (ent === undefined) {
      newFp++;
      report.push(`  新指纹 ${fp} → ${bucket}`);
      return;
    }
    if ((BUCKET_RANK[bucket] ?? 0) > (BUCKET_RANK[ent.bucket] ?? 0)) {
      worsened++;
      report.push(`  桶恶化 ${fp}：${ent.bucket} → ${bucket}`);
    }
  };

  // 生成计划（纯函数：不含编译——测试用它逐字节比对 Go 侧金样本）
  for (const v of planVariants(rules, pick)) {
    if (process.env["CF_TRACE"] !== undefined && process.env["CF_TRACE"] !== "") {
      process.stdout.write(`TRACE: ${v.suite}/${v.seed} ${v.mutator}\n`);
    }
    total++;
    if (!opts.freeze && !judgeRefresh) {
      const cached = judgeCacheGet(judgeDir, v);
      if (cached !== null) {
        judgeHit++;
        handle(v.fp, cached);
        continue;
      }
    }
    judgeMiss++;
    try {
      fs.writeFileSync(path.join(CACHE_DIR, v.filename), v.bytes);
    } catch (e) {
      die(`写变体失败：${errText(e)}`);
    }
    const variant = path.join(CACHE_DIR, v.filename);
    const c = clangOutcome(variant, CACHE_DIR);
    const nj = vitroJs(variant);
    const na = vitroNative(variant);
    const bucket = bucketOf(c, nj, na);
    judgeCachePut(judgeDir, v, bucket);
    handle(v.fp, bucket);
  }
  pruneJudgeEpochs(judgeEpoch);

  if (opts.freeze) {
    const sortedKeys = [...base.entries.keys()].sort(byteCompare);
    const entries: Record<string, BaselineEntry> = {};
    for (const k of sortedKeys) {
      const v = base.entries.get(k) as BaselineEntry;
      const obj: BaselineEntry = { bucket: v.bucket };
      if (v.issue !== undefined && v.issue !== "") obj.issue = v.issue;
      if (v.note !== undefined && v.note !== "") obj.note = v.note;
      entries[k] = obj;
    }
    // 转义口径对齐 Go MarshalIndent + SetEscapeHTML（PR #289 P2-1 立的口径，
    // .mts 迁移时曾丢失——freeze 反向漂移既有 \u003e 形态条目 3 处实锤）：
    // < > & 与 U+2028/U+2029 在字符串值内转 \uXXXX。这些字符不出现在 JSON
    // 结构位（键为 ASCII 指纹），整体替换安全。
    const text = marshalBaselineText(entries);
    try {
      fs.writeFileSync(opts.baseline, text, "utf8");
    } catch (e) {
      die(`基线落盘失败：${errText(e)}`);
    }
    process.stdout.write(`corpus_fuzz -freeze：基线落盘 ${base.entries.size} 条 → ${opts.baseline}\n`);
    process.stdout.write(`判定缓存写盘 ${judgeMiss} 条（epoch=${judgeEpoch}，freeze 全量真跑值）\n`);
    return 0;
  }

  process.stdout.write(
    `corpus_fuzz：total=${total} AGREE=${agree} 新指纹=${newFp} 桶恶化=${worsened}` +
      ` 判定缓存命中=${judgeHit} 未命中=${judgeMiss}（epoch=${judgeEpoch}${judgeRefresh ? "，REFRESH 全量重算" : ""}）\n`,
  );
  for (const l of report) process.stdout.write(l + "\n");
  if (newFp > 0 || worsened > 0) {
    process.stdout.write("FAIL——新指纹须人工定性后 -freeze 收编（已知未修病带 issue 标注）；桶恶化=回归\n");
    return 1;
  }
  process.stdout.write("corpus_fuzz: PASS——无新指纹、无桶恶化\n");
  return 0;
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  process.exit(runMain(process.argv.slice(2)));
}
