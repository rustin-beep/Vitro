// gofmt.mts —— Go 文本口径复刻单源（#273 存量 Go 重写批）。
//
// 双轨期要求「TS 产物 == Go 产物」逐字节一致，故 Go 的几个格式化 / 排序
// 口径必须显式复刻，不能靠 JS 默认行为凑：
//
//   goQuote      = Go `fmt %q` / `strconv.Quote`（可打印 rune 原样，控制字符
//                  走短转义，不可打印落 \xNN / \uNNNN / \UNNNNNNNN）
//   padEndRunes  = Go `%-Ns`（宽度按 rune 计——JS padEnd 按 UTF-16 code unit 计）
//   byteCompare  = Go `sort.Strings` / `bytes.Compare`（UTF-8 字节字典序——
//                  JS 默认 sort 走 UTF-16 code unit 序，代理对区与字节序分歧）
//
// 用法边界：仅在「与 Go 版对拍」的生成器 / 闸上使用。新写的纯 TS 脚本不要
// 为了整齐而套这层——它们是 Go 兼容层，不是 TS 惯用法。

/** Go unicode.IsPrint 的类判（L / M / N / P / S + ASCII 空格）。 */
const PRINT_CLASS = /^[\p{L}\p{M}\p{N}\p{S}\p{P}]$/u;

function isPrint(cp: number): boolean {
  if (cp === 0x20) return true;
  if (cp < 0x20 || cp === 0x7f) return false;
  return PRINT_CLASS.test(String.fromCodePoint(cp));
}

function hex(n: number, width: number): string {
  return n.toString(16).padStart(width, "0");
}

/**
 * Go `strconv.Quote` 复刻：返回带双引号的字面量。
 *
 * 中文 / 全角标点属可打印面，原样输出（`"排序"`），与 Go 版一致；
 * 不可打印面按 Go 的短转义表与 \x / \u / \U 三级宽度落转义。
 */
export function goQuote(s: string): string {
  let out = '"';
  for (const ch of s) {
    const cp = ch.codePointAt(0) ?? 0;
    if (ch === '"') out += '\\"';
    else if (ch === "\\") out += "\\\\";
    else if (cp === 0x07) out += "\\a";
    else if (cp === 0x08) out += "\\b";
    else if (cp === 0x0c) out += "\\f";
    else if (cp === 0x0a) out += "\\n";
    else if (cp === 0x0d) out += "\\r";
    else if (cp === 0x09) out += "\\t";
    else if (cp === 0x0b) out += "\\v";
    else if (isPrint(cp)) out += ch;
    // Go appendEscapedRune：`\xNN` 只给 r < ' ' 与 0x7f；其余不可打印走
    // \uNNNN（< 0x10000）/ \UNNNNNNNN。U+00A0 这类「非 ASCII 但不可打印」
    // 归 \u 面，不是 \x 面（2026-10-23 与 go run 对拍实锤）。
    else if (cp < 0x20 || cp === 0x7f) out += "\\x" + hex(cp, 2);
    else if (cp < 0x10000) out += "\\u" + hex(cp, 4);
    else out += "\\U" + hex(cp, 8);
  }
  return out + '"';
}

/** Go `%-Ns` 复刻：按 rune（码点）计宽，不足补尾随空格。 */
export function padEndRunes(s: string, width: number): string {
  const n = Array.from(s).length;
  return n >= width ? s : s + " ".repeat(width - n);
}

/** Go `sort.Strings` / `bytes.Compare` 复刻：UTF-8 字节字典序。 */
export function byteCompare(a: string, b: string): number {
  return Buffer.compare(Buffer.from(a, "utf8"), Buffer.from(b, "utf8"));
}

/** 就地按字节字典序排序（Go `sort.Strings` 等价）。 */
export function sortBytes(list: string[]): string[] {
  return list.sort(byteCompare);
}
