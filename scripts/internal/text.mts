// text.mts —— Go 标准库「字符串 / 字节口径」的 .mts 复刻（#273 存量 Go 重写批）。
//
// 为什么单开一件：ts 字符串是 UTF-16 code unit、Go 是 UTF-8 字节——凡是
// 排序 / 比较 / 切分进**判定面**（输出文案、基线键序、白名单对账）的地方，
// 用 JS 原生默认口径就会与 Go 侧漂移。本模块把这些口径收成单源，重写批按需 import。
//
// 面：
//   - byteCompare / byteSort：复刻 Go 的字符串 `<` 与 `sort.Strings`（UTF-8 字节字典序）。
//     JS `.sort()` 默认按 UTF-16 code unit 比，astral 面（U+10000 以上）与字节序不同。
//   - goTrimSpace / goFields：复刻 `strings.TrimSpace` / `strings.Fields`（unicode.IsSpace）。
//     JS `\s` 与 Go 的空白集**不等价**：Go（unicode.IsSpace = Unicode White_Space）
//     比 JS `\s` 多 U+0085（NEL），且 U+2028/U+2029 必须显式列入（本文件曾漏，
//     #292 审阅 P3 实测 `TrimSpace("\u2028x\u2029")` Go 返 "x"、TS 返原串）；
//     JS `\s` 含而 Go **不含**的是 U+FEFF（BOM，非 White_Space）。
//   - goJSONMarshalIndent：复刻 `json.MarshalIndent`（`SetEscapeHTML` 默认 true）。
//     原实现散在 teaching_annotation_diff；本批上收为单源，那边改为 re-export
//     （避免两份「Go 序列化口径」并存——#289 审阅 P2-1 的 154 行伪漂移就是这类口径缺口）。

/** Go `unicode.IsSpace` 的空白集（含 U+0085/U+2028/U+2029；不含 U+FEFF）。 */
const GO_SPACE_RE = /[\t\n\v\f\r \u0085\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000]/;
const GO_SPACE_EDGE_RE = /^[\t\n\v\f\r \u0085\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000]+|[\t\n\v\f\r \u0085\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000]+$/g;

/** Go `strings.TrimSpace`。 */
export function goTrimSpace(s: string): string {
  return s.replace(GO_SPACE_EDGE_RE, "");
}

/** Go `strings.Fields`：按 Go 空白集切分，**丢弃空段**（连续空白不产空串）。 */
export function goFields(s: string): string[] {
  const out: string[] = [];
  let cur = "";
  for (const ch of s) {
    if (GO_SPACE_RE.test(ch)) {
      if (cur !== "") {
        out.push(cur);
        cur = "";
      }
      continue;
    }
    cur += ch;
  }
  if (cur !== "") out.push(cur);
  return out;
}

/** 字节字典序比较（Go 字符串 `<`）：返回负 / 0 / 正。 */
export function byteCompare(a: string, b: string): number {
  return Buffer.compare(Buffer.from(a, "utf8"), Buffer.from(b, "utf8"));
}

/** `sort.Strings` 等价：返回按字节序排序的副本（不改入参）。 */
export function byteSort(xs: readonly string[]): string[] {
  return [...xs].sort(byteCompare);
}

/**
 * Go `json.MarshalIndent` 口径（`SetEscapeHTML` 默认 true）：
 * `<` `>` `&` 与 U+2028/U+2029 一律转义成 `\uXXXX`。
 *
 * **为什么必须补**（#289 审阅 P2-1 实测）：`JSON.stringify` 不转义这些字符，
 * 直接写回会把入库 golden 里 190 处 `\u003c/\u003e/\u0026` 换成裸字符 ——
 * 未变更树上 `--freeze` 会产出 154 行 / −950 B 的伪漂移。只读模式对拍不存在
 * 该面（它不写盘），故此前等价证据覆盖不到。
 */
export function goJSONMarshalIndent(v: unknown): string {
  return JSON.stringify(v, null, 2)
    .replace(/</g, "\\u003c")
    .replace(/>/g, "\\u003e")
    .replace(/&/g, "\\u0026")
    .replace(/\u2028/g, "\\u2028")
    .replace(/\u2029/g, "\\u2029");
}
