// aggregate —— result.json → gold_<corpus>.json（只取测量事实，不透传诊断 message）。
//
// 协议红线：message 可引用源码 token，故金样本只存码计数/层/运行判定。
// 序列化口径 = Go `json.MarshalIndent`：map 键按字节序排序、HTML 转义开启、
// 文件字段序 = 结构体声明序、尾随换行。
import fs from "node:fs";
import path from "node:path";
import { fatal } from "../internal/capi.mts";
import { byteCompare, goJSONMarshalIndent } from "../internal/text.mts";
import type { FileResult } from "./types.mts";

export interface AggregateOptions {
  goldOut: string;
  aggRepo: string;
  sourceFork: string;
  sourceCommit: string;
}

export const DEFAULT_GOLD_NOTE =
  "金样本签名清单——只存诊断码/数量/运行判定签名,不存源码文本(GPL 红线)。";

interface GoldFile {
  clang_ok: boolean;
  gcc_ok: boolean;
  vitro_errs: number;
  vitro_warns: number;
  codes: Record<string, number>;
  layer: string;
  run: string;
}

function sortedRecord<T>(entries: Array<[string, T]>): Record<string, T> {
  const out: Record<string, T> = {};
  for (const [k, v] of [...entries].sort((a, b) => byteCompare(a[0], b[0]))) out[k] = v;
  return out;
}

function localDate(now = new Date()): string {
  const p = (n: number): string => String(n).padStart(2, "0");
  return `${now.getFullYear()}-${p(now.getMonth() + 1)}-${p(now.getDate())}`;
}

/** 纯聚合：入参 = result.json 的数组，出参 = 金样本完整文本（含尾随换行）。 */
export function aggregateResults(results: readonly FileResult[], opts: AggregateOptions): string {
  const files = new Map<string, GoldFile>();
  const buckets: Record<string, number> = { clang_red: 0, both_green: 0, vitro_red: 0 };
  const gccBuckets: Record<string, number> = {
    both_green: 0,
    rescued: 0,
    divergence: 0,
    both_red: 0,
  };
  for (const r of results) {
    const clangOK = r.clang_ok === true;
    const gccOK = r.gcc_ok === true;
    const errs = typeof r.vitro_errors === "number" ? r.vitro_errors : 0;
    const warns = typeof r.vitro_warnings === "number" ? r.vitro_warnings : 0;
    const layer = r.vitro_layer ?? "";
    const run = r.run_compare ?? "";
    const codes = new Map<string, number>();
    for (const d of r.vitro_diags ?? []) {
      if (typeof d.code === "string" && d.code !== "") {
        codes.set(d.code, (codes.get(d.code) ?? 0) + 1);
      }
    }
    let bucket = "vitro_red";
    if (!clangOK) bucket = "clang_red";
    else if (errs === 0) bucket = "both_green";
    buckets[bucket] = (buckets[bucket] ?? 0) + 1;

    if (!clangOK && gccOK) gccBuckets["rescued"] = (gccBuckets["rescued"] ?? 0) + 1;
    else if (clangOK && !gccOK) gccBuckets["divergence"] = (gccBuckets["divergence"] ?? 0) + 1;
    else if (clangOK && gccOK) gccBuckets["both_green"] = (gccBuckets["both_green"] ?? 0) + 1;
    else gccBuckets["both_red"] = (gccBuckets["both_red"] ?? 0) + 1;

    files.set(r.path ?? "", {
      clang_ok: clangOK,
      gcc_ok: gccOK,
      vitro_errs: errs,
      vitro_warns: warns,
      codes: sortedRecord([...codes.entries()]),
      layer,
      run,
    });
  }
  const meta = sortedRecord<unknown>([
    ["as_of", localDate()],
    ["repo", opts.aggRepo],
    ["source_fork", opts.sourceFork],
    ["source_commit", opts.sourceCommit],
    ["note", DEFAULT_GOLD_NOTE],
    ["total", results.length],
    ["buckets", sortedRecord(Object.entries(buckets))],
    ["gcc_buckets", sortedRecord(Object.entries(gccBuckets))],
  ]);
  const out = sortedRecord<unknown>([
    ["_meta", meta],
    ["files", sortedRecord([...files.entries()])],
  ]);
  return goJSONMarshalIndent(out) + "\n";
}

export function runAggregate(resultPath: string, opts: AggregateOptions): number {
  let raw: string;
  try {
    raw = fs.readFileSync(resultPath, "utf8");
  } catch (e) {
    fatal(`读取 result.json 失败: ${e instanceof Error ? e.message : String(e)}`);
  }
  let results: FileResult[];
  try {
    results = JSON.parse(raw) as FileResult[];
  } catch (e) {
    fatal(`result.json 解析失败: ${e instanceof Error ? e.message : String(e)}`);
  }
  if (!Array.isArray(results)) fatal("result.json 顶层不是数组");
  const dst = path.join(path.dirname(resultPath), opts.goldOut);
  try {
    fs.writeFileSync(dst, aggregateResults(results, opts), "utf8");
  } catch (e) {
    fatal(`写出失败: ${e instanceof Error ? e.message : String(e)}`);
  }
  process.stderr.write(`聚合完成: ${results.length} 文件 → ${dst}\n`);
  return 0;
}
