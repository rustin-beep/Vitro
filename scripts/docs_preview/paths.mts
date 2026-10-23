// paths.mts —— docs 站的相对路径 / 排序 / 人类可读格式化工具（Go 版逐函数移植）。

// 字节口径：按 UTF-8 逐字节百分号编码（与 Go encodeSegment / clang 路径口径一致，
// UTF-16 code unit 不入库）。
export function encodeSegment(s: string): string {
  let out = "";
  for (const b of Buffer.from(s, "utf8")) {
    const c = String.fromCharCode(b);
    if (/[A-Za-z0-9\-_.~]/.test(c)) out += c;
    else out += "%" + b.toString(16).toUpperCase().padStart(2, "0");
  }
  return out;
}

// encodePath 逐段百分号编码（保留 / 与 ..）。
export function encodePath(p: string): string {
  return p
    .split("/")
    .map((seg) => encodeSegment(seg))
    .join("/");
}

export function pathRel(fromDir: string, target: string): string {
  if (fromDir === "" || fromDir === ".") return target;
  const from = fromDir.split("/");
  const to = target.split("/");
  let i = 0;
  while (i < from.length && i < to.length - 1 && from[i] === to[i]) i++;
  const parts: string[] = [];
  for (let k = i; k < from.length; k++) parts.push("..");
  parts.push(...to.slice(i));
  return parts.join("/");
}

// relHref 输出根内相对路径。
export function relHref(fromDir: string, target: string): string {
  return encodePath(pathRel(fromDir, target));
}

export function depthOf(dir: string): number {
  if (dir === "" || dir === ".") return 0;
  return dir.split("/").length;
}

export function dashPath(rel: string): string {
  if (rel === "." || rel === "") return "";
  return "/" + rel;
}

export function dirLabel(rel: string): string {
  if (rel === "." || rel === "") return "docs";
  const i = rel.lastIndexOf("/");
  return i >= 0 ? rel.slice(i + 1) : rel;
}

export function pathBase(p: string): string {
  const i = p.lastIndexOf("/");
  return i >= 0 ? p.slice(i + 1) : p;
}

function splitNumeric(s: string): string[] {
  const parts: string[] = [];
  let cur = "";
  let digit = false;
  for (let i = 0; i < s.length; i++) {
    const isDig = s[i] !== undefined && s[i]! >= "0" && s[i]! <= "9";
    if (cur.length > 0 && isDig !== digit) {
      parts.push(cur);
      cur = "";
    }
    digit = isDig;
    cur += s[i];
  }
  if (cur.length > 0) parts.push(cur);
  return parts;
}

// naturalLess 让 01- / 02- 这类数字前缀按数值排序，其余按码点序。
export function naturalLess(a: string, b: string): boolean {
  const pa = splitNumeric(a);
  const pb = splitNumeric(b);
  const n = Math.min(pa.length, pb.length);
  for (let i = 0; i < n; i++) {
    const x = pa[i] ?? "";
    const y = pb[i] ?? "";
    if (x === y) continue;
    const nx = Number.parseInt(x, 10);
    const ny = Number.parseInt(y, 10);
    if (!Number.isNaN(nx) && !Number.isNaN(ny)) return nx < ny;
    return x < y;
  }
  return pa.length < pb.length;
}

export function humanSize(n: number): string {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / 1024 / 1024).toFixed(2)} MB`;
}

export function fmtTime(d: Date): string {
  const p = (n: number): string => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
}

// countWords 统计「字数」：CJK 字符按字计，非 CJK 连续字母/数字段按词计。
export function countWords(text: string): number {
  let total = 0;
  let inWord = false;
  for (const ch of text) {
    const cp = ch.codePointAt(0) ?? 0;
    if (cp >= 0x2e80) {
      total++;
      inWord = false;
      continue;
    }
    if (isWordSepASCII(cp)) {
      inWord = false;
      continue;
    }
    if (!inWord) {
      total++;
      inWord = true;
    }
  }
  return total;
}

function isWordSepASCII(cp: number): boolean {
  if (cp === 32 || cp === 9 || cp === 10 || cp === 0xa0) return true;
  if (cp >= 0x21 && cp <= 0x2f) return true;
  if (cp >= 0x3a && cp <= 0x40) return true;
  if (cp >= 0x5b && cp <= 0x60) return true;
  if (cp >= 0x7b && cp <= 0x7e) return true;
  return false;
}

// readingLabel 阅读时长口径：400 字/分钟，不足 1 分钟显示「小于 1 分钟」。
export function readingLabel(words: number): string {
  if (words < 400) return "小于 1 分钟";
  return `${Math.floor((words + 399) / 400)} 分钟`;
}
