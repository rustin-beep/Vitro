// modesdigest.mts —— `version/note/modes` 型 golden 清单的共享实现。
//
// 2026-10-23 实测：typeck_diff 与 parser_diff 的 digest **完全同构**
// （`{version, note, modes: {<节名>: {sources, resp_hashes}}}`，节名 = corpus-<name>
// 或合成模式名）。两处各写一份序列化就是重复，故上收。
//
// 与其他两套形状对照（不可合并，各自 target 自持）：
//   lexer  : version / sources（二层）/ tsvs         —— 扁平
//   codegen: version / note / corpora（cases 是判定记录结构体，不是 hash 串）
//
// 序列化必须复刻 Go `json.MarshalIndent` 的两层键序语义：
//   顶层 = struct 字段声明序（version → note → modes，**不是字典序**）；
//   modes 节 = map 键字节序；节内 = struct 字段序（sources → resp_hashes）；
//   sec 内的两张表 = map 键字节序。
import fs from "node:fs";
import path from "node:path";
import type { Fail, GoldenSection, GoldenStore } from "./diffgate.mts";
import { sortBytes } from "./gofmt.mts";

export interface ModesSec {
  sources: Record<string, string>;
  resp_hashes: Record<string, string>;
}

export interface ModesDigest {
  version: number;
  note: string;
  modes: Record<string, ModesSec>;
}

export function loadModesDigest(root: string, rel: string, defaultNote: string, fail: Fail): ModesDigest {
  const p = path.join(root, rel);
  const empty: ModesDigest = { version: 1, note: defaultNote, modes: {} };
  if (!fs.existsSync(p)) return empty;
  let d: ModesDigest;
  try {
    d = JSON.parse(fs.readFileSync(p, "utf8")) as ModesDigest;
  } catch {
    return fail(`digest 清单坏或版本不识 ${rel}`);
  }
  if (d.version !== 1) fail(`digest 清单坏或版本不识 ${rel}`);
  return { version: 1, note: d.note ?? defaultNote, modes: d.modes ?? {} };
}

export function serializeModesDigest(d: ModesDigest): string {
  const q = (s: string): string => JSON.stringify(s);
  const mapBody = (m: Record<string, string>, indent: string): string => {
    const keys = sortBytes(Object.keys(m));
    if (keys.length === 0) return "{}";
    return (
      "{\n" +
      keys.map((k) => `${indent}  ${q(k)}: ${q(m[k] ?? "")}`).join(",\n") +
      "\n" +
      indent +
      "}"
    );
  };
  const modeKeys = sortBytes(Object.keys(d.modes));
  const modesBody =
    modeKeys.length === 0
      ? "{}"
      : "{\n" +
        modeKeys
          .map((mk) => {
            const sec = d.modes[mk] ?? { sources: {}, resp_hashes: {} };
            return (
              `    ${q(mk)}: {\n` +
              `      "sources": ${mapBody(sec.sources, "      ")},\n` +
              `      "resp_hashes": ${mapBody(sec.resp_hashes, "      ")}\n` +
              "    }"
            );
          })
          .join(",\n") +
        "\n  }";
  return `{\n  "version": ${d.version},\n  "note": ${q(d.note)},\n  "modes": ${modesBody}\n}\n`;
}

export function saveModesDigest(root: string, rel: string, d: ModesDigest, fail: Fail): void {
  const p = path.join(root, rel);
  try {
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(p, serializeModesDigest(d), { mode: 0o644 });
  } catch (e) {
    fail(`写 digest 清单失败 ${rel}: ${(e as Error).message}`);
  }
}

/**
 * 造 GoldenStore。`sectionOf(corpusName)` 决定该语料落在哪个节——
 * 普通语料是 `corpus-<name>`，合成模式直接用模式名。
 */
export function makeModesStore(
  root: string,
  rel: string,
  defaultNote: string,
  missingHint: string,
  sectionOf: (corpusName: string) => string,
  fail: Fail,
): GoldenStore {
  return {
    missingHint,
    load(corpusName: string): GoldenSection | null {
      const d = loadModesDigest(root, rel, defaultNote, fail);
      const sec = d.modes[sectionOf(corpusName)];
      if (sec === undefined) return null;
      return { sources: sec.sources ?? {}, cases: sec.resp_hashes ?? {} };
    },
    save(corpusName: string, s: GoldenSection): void {
      const d = loadModesDigest(root, rel, defaultNote, fail);
      d.modes[sectionOf(corpusName)] = { sources: s.sources, resp_hashes: s.cases };
      saveModesDigest(root, rel, d, fail);
    },
  };
}
