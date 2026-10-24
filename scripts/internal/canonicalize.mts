// canonicalize.mts —— 差分锚的 JSON 归一器（单源；#273 存量 Go 重写批）。
//
// 归一规则（与退役目标 Go 版一致）：
//  1. 对象键按字节字典序排序（数组顺序保持——排序数组会销毁信息）；
//  2. 数字形态保持（原始 token 直通：1 / 1.0 / 1e2 不互相改写）；
//  3. 字符串解码后按 Go encoding/json 口径重转义（HTML 转义关闭；
//     U+2028/U+2029 恒转义；控制字符 \u00xx；其余 UTF-8 原样）；
//  4. 缩进固定 2 空格 + 尾随换行。
//
// 纪律：fail loud（非法 JSON / 多值 / 尾随内容抛错，禁止静默 default）；
// 不打印、不 exit——呈现方式归调用方（CLI 壳与各驱动自决）。
//
// 与 Go 版的差异边界：错误文案只求语义等价（调用方只判 err != nil）；
// 数值 token 与转义形态逐字节对齐（差分锚的可信前提）。

export class JsonNumber {
  readonly raw: string;
  constructor(raw: string) {
    this.raw = raw;
  }
}

export type JsonValue = null | boolean | string | JsonNumber | JsonValue[] | Map<string, JsonValue>;

class Parser {
  private i = 0;
  private readonly s: string;
  /** true 时每个值包成 JsonRaw（带原始切片）——`json.RawMessage` 语义用。 */
  wrapRaw = false;

  constructor(s: string) {
    this.s = s;
  }

  parseDocument(): JsonValue {
    this.skipWs();
    const v = this.parseValue();
    this.skipWs();
    if (this.i < this.s.length) {
      const rest = this.s.slice(this.i);
      if (/^[{["\-0-9tfn]/.test(rest)) throw new Error("输入含多个 JSON 值（锚数据必须是单值）");
      throw new Error("首个 JSON 值后存在尾随内容；锚数据必须是单值");
    }
    return v;
  }

  private skipWs(): void {
    while (this.i < this.s.length) {
      const c = this.s[this.i];
      if (c === " " || c === "\t" || c === "\n" || c === "\r") this.i++;
      else break;
    }
  }

  private fail(msg: string): never {
    throw new Error(`非法 JSON: ${msg}（位置 ${this.i}）`);
  }

  private parseValue(): JsonValue {
    if (this.i >= this.s.length) this.fail("意外结束");
    const start = this.i;
    const v = this.parseValueInner();
    return this.wrapRaw ? new JsonRaw(this.s.slice(start, this.i), v) : v;
  }

  private parseValueInner(): JsonValue {
    if (this.i >= this.s.length) this.fail("意外结束");
    const c = this.s[this.i] ?? "";
    if (c === "{") return this.parseObject();
    if (c === "[") return this.parseArray();
    if (c === '"') return this.parseString();
    if (c === "t") return this.parseLiteral("true", true);
    if (c === "f") return this.parseLiteral("false", false);
    if (c === "n") return this.parseLiteral("null", null);
    if (c === "-" || (c >= "0" && c <= "9")) return this.parseNumber();
    this.fail(`意外字符 ${JSON.stringify(c)}`);
  }

  private parseLiteral(lit: string, v: boolean | null): boolean | null {
    if (this.s.startsWith(lit, this.i)) {
      this.i += lit.length;
      return v;
    }
    this.fail(`期望 ${lit}`);
  }

  private parseObject(): Map<string, JsonValue> {
    const out = new Map<string, JsonValue>();
    this.i++; // {
    this.skipWs();
    if (this.s[this.i] === "}") {
      this.i++;
      return out;
    }
    for (;;) {
      this.skipWs();
      if (this.s[this.i] !== '"') this.fail("对象键必须是字符串");
      const key = this.parseString();
      this.skipWs();
      if (this.s[this.i] !== ":") this.fail("对象键后缺冒号");
      this.i++;
      this.skipWs();
      out.set(key, this.parseValue()); // 重复键后者覆盖（与 Go map 解码一致）
      this.skipWs();
      const c = this.s[this.i];
      if (c === ",") {
        this.i++;
        continue;
      }
      if (c === "}") {
        this.i++;
        return out;
      }
      this.fail("对象缺 , 或 }");
    }
  }

  private parseArray(): JsonValue[] {
    const out: JsonValue[] = [];
    this.i++; // [
    this.skipWs();
    if (this.s[this.i] === "]") {
      this.i++;
      return out;
    }
    for (;;) {
      this.skipWs();
      out.push(this.parseValue());
      this.skipWs();
      const c = this.s[this.i];
      if (c === ",") {
        this.i++;
        continue;
      }
      if (c === "]") {
        this.i++;
        return out;
      }
      this.fail("数组缺 , 或 ]");
    }
  }

  private parseString(): string {
    this.i++; // "
    let out = "";
    for (;;) {
      if (this.i >= this.s.length) this.fail("字符串未闭合");
      const c = this.s[this.i] ?? "";
      if (c === '"') {
        this.i++;
        return out;
      }
      if (c === "\\") {
        this.i++;
        const e = this.s[this.i];
        switch (e) {
          case '"':
            out += '"';
            this.i++;
            break;
          case "\\":
            out += "\\";
            this.i++;
            break;
          case "/":
            out += "/";
            this.i++;
            break;
          case "b":
            out += "\b";
            this.i++;
            break;
          case "f":
            out += "\f";
            this.i++;
            break;
          case "n":
            out += "\n";
            this.i++;
            break;
          case "r":
            out += "\r";
            this.i++;
            break;
          case "t":
            out += "\t";
            this.i++;
            break;
          case "u": {
            this.i++; // 越过 'u'
            const cp = this.parseHex4();
            if (cp >= 0xd800 && cp <= 0xdbff) {
              // 高代理：后随低代理则合成码点，否则按 Go 口径替换为 U+FFFD
              if (this.s.startsWith("\\u", this.i)) {
                const save = this.i;
                this.i += 2;
                const lo = this.parseHex4();
                if (lo >= 0xdc00 && lo <= 0xdfff) {
                  out += String.fromCodePoint(0x10000 + ((cp - 0xd800) << 10) + (lo - 0xdc00));
                } else {
                  this.i = save;
                  out += "\ufffd";
                }
              } else {
                out += "\ufffd";
              }
            } else if (cp >= 0xdc00 && cp <= 0xdfff) {
              out += "\ufffd";
            } else {
              out += String.fromCharCode(cp);
            }
            break;
          }
          default:
            this.fail(`非法转义 \\${e ?? ""}`);
        }
        continue;
      }
      const code = c.charCodeAt(0);
      if (code < 0x20) this.fail("字符串含未转义控制字符");
      out += c;
      this.i++;
    }
  }

  private parseHex4(): number {
    const hex = this.s.slice(this.i, this.i + 4);
    if (!/^[0-9a-fA-F]{4}$/.test(hex)) this.fail("\\u 后须 4 位十六进制");
    this.i += 4;
    return Number.parseInt(hex, 16);
  }

  private parseNumber(): JsonNumber {
    const start = this.i;
    if (this.s[this.i] === "-") this.i++;
    if (this.s[this.i] === "0") {
      this.i++;
    } else if (this.s[this.i] !== undefined && this.s[this.i]! >= "1" && this.s[this.i]! <= "9") {
      while (this.s[this.i] !== undefined && this.s[this.i]! >= "0" && this.s[this.i]! <= "9") this.i++;
    } else {
      this.fail("数字缺整数部分");
    }
    if (this.s[this.i] === ".") {
      this.i++;
      const d = this.i;
      while (this.s[this.i] !== undefined && this.s[this.i]! >= "0" && this.s[this.i]! <= "9") this.i++;
      if (this.i === d) this.fail("小数点后缺数字");
    }
    if (this.s[this.i] === "e" || this.s[this.i] === "E") {
      this.i++;
      if (this.s[this.i] === "+" || this.s[this.i] === "-") this.i++;
      const d = this.i;
      while (this.s[this.i] !== undefined && this.s[this.i]! >= "0" && this.s[this.i]! <= "9") this.i++;
      if (this.i === d) this.fail("指数缺数字");
    }
    return new JsonNumber(this.s.slice(start, this.i));
  }
}

function quote(s: string): string {
  let out = '"';
  for (const ch of s) {
    const cp = ch.codePointAt(0) ?? 0;
    if (ch === '"') out += '\\"';
    else if (ch === "\\") out += "\\\\";
    else if (ch === "\n") out += "\\n";
    else if (ch === "\r") out += "\\r";
    else if (ch === "\t") out += "\\t";
    else if (cp < 0x20) out += "\\u00" + cp.toString(16).padStart(2, "0");
    else if (cp === 0x2028) out += "\\u2028";
    else if (cp === 0x2029) out += "\\u2029";
    else out += ch;
  }
  return out + '"';
}

/** Go `json.Marshal` 的字符串转义（`SetEscapeHTML` 默认 true：`<` `>` `&` 也转义）。 */
function quoteGoHTML(s: string): string {
  return quote(s)
    .replace(/</g, "\\u003c")
    .replace(/>/g, "\\u003e")
    .replace(/&/g, "\\u0026");
}

function keyCompare(a: string, b: string): number {
  return Buffer.compare(Buffer.from(a, "utf8"), Buffer.from(b, "utf8"));
}

function encode(v: JsonValue, depth: number): string {
  if (v instanceof JsonRaw) return encode(v.value, depth);
  const pad = "  ".repeat(depth);
  const padIn = "  ".repeat(depth + 1);
  if (v === null) return "null";
  if (typeof v === "boolean") return v ? "true" : "false";
  if (typeof v === "string") return quote(v);
  if (v instanceof JsonNumber) return v.raw;
  if (Array.isArray(v)) {
    if (v.length === 0) return "[]";
    return "[\n" + v.map((x) => padIn + encode(x, depth + 1)).join(",\n") + "\n" + pad + "]";
  }
  const keys = [...v.keys()].sort(keyCompare);
  if (keys.length === 0) return "{}";
  const body = keys.map((k) => padIn + quote(k) + ": " + encode(v.get(k) as JsonValue, depth + 1)).join(",\n");
  return "{\n" + body + "\n" + pad + "}";
}

// canonicalize：原始 JSON 文本/字节 → 规范形（尾随换行含）。非法输入抛错。
export function canonicalize(raw: string | Uint8Array): Buffer {
  const text = typeof raw === "string" ? raw : Buffer.from(raw).toString("utf8");
  const value = new Parser(text).parseDocument();
  return Buffer.from(encode(value, 0) + "\n", "utf8");
}

export function canonicalizeText(raw: string): string {
  return canonicalize(raw).toString("utf8");
}

// ── 结构化读写面（#292 批补：libc_boot_diff 需在「保数字形态」树上做字段级
//    搬移——Go 侧是 json.RawMessage，TS 侧靠 JsonNumber 直通原始 token）─────

/**
 * `json.RawMessage` 的等价节点：`raw` = 该值在源文本里的**原始切片**，
 * `value` = 结构解读（对象为 Map / 数组为数组 / 标量为解码值）。
 *
 * 为什么需要它（#292 实测实锤）：Go `json.Unmarshal` 到 `map[string]RawMessage`
 * 再 `json.Marshal` 回去时，**只有被解码成 map 的那一层**键被排序；值以原始
 * 字节内嵌（含嵌套对象的原键序）。全层排序会改写 `{"loc":{"line":…,"column":…}}`
 * 这类内层顺序，proj 哈希立刻失真。
 */
export class JsonRaw {
  readonly raw: string;
  readonly value: JsonValue;
  constructor(raw: string, value: JsonValue) {
    this.raw = raw;
    this.value = value;
  }
}

/** 解析为「每个值带原始切片」的树（键序按源文；对象键已解码）。 */
export function parseRawJson(raw: string | Uint8Array): JsonValue {
  const text = typeof raw === "string" ? raw : Buffer.from(raw).toString("utf8");
  const p = new Parser(text);
  p.wrapRaw = true;
  return p.parseDocument();
}

/**
 * Go `json.Marshal` 内嵌 RawMessage 时的 `compact(raw, escapeHTML=true)` 口径：
 * 删去字符串外的空白；字符串内 `<` `>` `&` 与 U+2028/U+2029 转成 `\uXXXX`；
 * 既有转义序列原样保留（compact 不重写转义）。
 */
export function compactGoJson(raw: string): string {
  let out = "";
  let inStr = false;
  for (let i = 0; i < raw.length; i++) {
    const ch = raw.charAt(i);
    if (inStr) {
      if (ch === "\\") {
        out += ch + (raw.charAt(i + 1) ?? "");
        i++;
        continue;
      }
      if (ch === '"') {
        inStr = false;
        out += ch;
        continue;
      }
      if (ch === "<") out += "\\u003c";
      else if (ch === ">") out += "\\u003e";
      else if (ch === "&") out += "\\u0026";
      else if (ch === "\u2028") out += "\\u2028";
      else if (ch === "\u2029") out += "\\u2029";
      else out += ch;
      continue;
    }
    if (ch === '"') {
      inStr = true;
      out += ch;
      continue;
    }
    if (ch === " " || ch === "\t" || ch === "\n" || ch === "\r") continue;
    out += ch;
  }
  return out;
}

/** 值的「内嵌形态」文本：JsonRaw 走 compactGoJson；其余走紧凑编码。 */
export function embedText(v: JsonValue): string {
  if (v instanceof JsonRaw) return compactGoJson(v.raw);
  return encodeCompact(v);
}

/** Go `json.Marshal(map[string]RawMessage)`：键按字节序排序，值取内嵌形态。 */
export function emitSortedObject(entries: ReadonlyMap<string, string>): string {
  const keys = [...entries.keys()].sort(keyCompare);
  return "{" + keys.map((k) => quoteGoHTML(k) + ":" + (entries.get(k) as string)).join(",") + "}";
}

function encodeCompact(v: JsonValue): string {
  if (v === null) return "null";
  if (typeof v === "boolean") return v ? "true" : "false";
  if (typeof v === "string") return quoteGoHTML(v);
  if (v instanceof JsonNumber) return v.raw;
  if (Array.isArray(v)) return "[" + v.map(encodeCompact).join(",") + "]";
  const keys = [...v.keys()].sort(keyCompare);
  return "{" + keys.map((k) => quoteGoHTML(k) + ":" + encodeCompact(v.get(k) as JsonValue)).join(",") + "}";
}
