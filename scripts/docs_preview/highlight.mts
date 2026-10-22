// highlight.mts —— 轻量语法高亮（#273 批二：Go highlight.go 逐行为移植，零第三方依赖）。
//
// 边界（诚实记录）：这不是 Pygments / Chroma 的等价物，只做词法级着色——
// 注释 / 字符串 / 数字 / 关键字 / 类型 / 函数名 / 预处理指令 / 属性键。
// 不做语义分析、不做宏展开、不分辨同形标识符，词表按语言常见子集手工维护。
//
// 语言覆盖（按 docs/ 实测的围栏信息串统计）：rust cpp c dart bash csharp powershell
// xml json yaml text python toml markdown cmake typescript tsx css html kotlin js，
// 另带 go / java / sql / ini / make / diff / lua / swift 等别名兜底。

interface LangDef {
  lineComments: string[];
  blockComments: Array<[string, string]>;
  quotes: string;
  keywords?: ReadonlySet<string>;
  types?: ReadonlySet<string>;
  preprocHash?: boolean;
  keyish?: boolean;
  markup?: boolean;
  dashIdent?: boolean;
}

function set(s: string): ReadonlySet<string> {
  return new Set(s.split(/\s+/).filter(Boolean));
}

function union(a: ReadonlySet<string>, b: ReadonlySet<string>): ReadonlySet<string> {
  return new Set([...a, ...b]);
}

const kwC = set(
  "auto break case const continue default do else enum extern for goto if inline register restrict return sizeof static struct switch typedef union volatile while __attribute__ __restrict __inline __asm asm"
);
const kwCPP = set(
  "alignas alignof and and_eq asm bitand bitor catch class compl concept consteval constexpr constinit const_cast co_await co_return co_yield decltype delete dynamic_cast explicit export false friend mutable namespace new noexcept not not_eq nullptr operator or or_eq private protected public reinterpret_cast requires static_assert static_cast template this thread_local throw true try typeid typename using virtual xor xor_eq override final import module"
);
const tyC = set(
  "void char short int long float double signed unsigned bool _Bool size_t ssize_t ptrdiff_t wchar_t FILE va_list int8_t int16_t int32_t int64_t uint8_t uint16_t uint32_t uint64_t uintptr_t NULL true false"
);
const tyCPP = set(
  "void char short int long float double signed unsigned bool size_t ssize_t wchar_t FILE va_list nullptr_t string string_view vector map unordered_map set unordered_set list deque pair tuple array optional variant unique_ptr shared_ptr weak_ptr function iterator const_iterator int8_t int16_t int32_t int64_t uint8_t uint16_t uint32_t uint64_t uintptr_t size_type value_type NULL true false"
);
const kwRust = set(
  "as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while yield"
);
const tyRust = set(
  "i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str String Vec VecDeque Option Result Box Rc Arc RefCell Cell HashMap HashSet BTreeMap BTreeSet Cow Path PathBuf OsString Duration Instant Ordering Some None Ok Err Rc Weak Mutex RwLock AtomicUsize AtomicBool"
);
const kwGo = set(
  "break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var"
);
const tyGo = set(
  "bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 uint16 uint32 uint64 uintptr any comparable nil true false iota"
);
const kwPy = set(
  "and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield None True False self match case"
);
const tyPy = set(
  "int float complex bool str bytes bytearray list tuple dict set frozenset object type range print len enumerate zip map filter sorted sum min max abs open isinstance issubclass super Exception ValueError TypeError KeyError IndexError RuntimeError"
);
const kwJS = set(
  "var let const function return if else for while do switch case break continue new delete typeof instanceof in of class extends super this null undefined true false async await yield import export default try catch finally throw void static get set with debugger"
);
const tyJS = set(
  "String Number Boolean Object Array Promise Math JSON Date RegExp Map Set WeakMap Symbol BigInt Error any unknown never void interface type enum namespace declare readonly as satisfies keyof infer Partial Required Record"
);
const kwCS = set(
  "using namespace class struct interface enum public private protected internal static readonly const virtual override abstract sealed async await new return if else for foreach while do switch case break continue try catch finally throw this base null true false var get set partial record where out ref in params delegate event is as typeof nameof lock checked unchecked fixed stackalloc"
);
const tyCS = set(
  "int uint long ulong short ushort byte sbyte bool string char double float decimal object dynamic void Task List Dictionary IEnumerable Span Memory Stream Exception Console Math"
);
const kwDart = set(
  "class extends implements with mixin abstract final const var void async await sync try catch on finally throw rethrow if else for while do switch case default return new this super static get set late required factory operator typedef enum assert is as in is_"
);
const tyDart = set(
  "int double num String bool List Map Set Iterable Future Stream Object Null dynamic Symbol Function Record"
);
const kwKotlin = set(
  "fun val var class object interface if else when for while return try catch finally throw null true false this super override open abstract sealed data enum companion object init import package suspend inline lateinit vararg by where as is in out typealias"
);
const tyKotlin = set(
  "Int Long Double Float Short Byte Boolean Char String Any Unit Nothing List MutableList Map MutableMap Set MutableSet Array Sequence Pair Triple"
);
const kwBash = set(
  "if then else elif fi case esac for while until do done function in return local export readonly declare source alias unset shift eval exit set trap"
);
const tyBash = set(
  "echo cd ls cat grep sed awk rm cp mv mkdir touch chmod curl wget git cargo go python node npm test true false"
);
const kwPS = set(
  "function param if else elseif foreach for while switch return try catch finally throw begin process end class enum filter in do until break continue new"
);
const tyPS = set(
  "Get-Item Get-ChildItem Set-Item Remove-Item Write-Host Write-Output New-Object Select-Object Where-Object ForEach-Object Test-Path Join-Path Split-Path"
);
const kwSQL = set(
  "select from where insert into values update set delete join left right inner outer on group by order having limit offset create table index drop alter primary key foreign references not null default unique distinct as and or in like between case when then else end union all asc desc"
);
const tySQL = set(
  "int integer bigint smallint varchar nvarchar text char date datetime timestamp decimal numeric float double boolean blob uuid"
);

function langDefFor(lang: string): LangDef | null {
  switch (lang.toLowerCase().trim()) {
    case "c":
    case "h":
      return {
        lineComments: ["//"],
        blockComments: [["/*", "*/"]],
        quotes: "\"'",
        keywords: kwC,
        types: tyC,
        preprocHash: true,
      };
    case "cpp":
    case "c++":
    case "cc":
    case "cxx":
    case "hpp":
    case "hh":
    case "hxx":
      return {
        lineComments: ["//"],
        blockComments: [["/*", "*/"]],
        quotes: "\"'",
        keywords: union(kwC, kwCPP),
        types: union(tyC, tyCPP),
        preprocHash: true,
      };
    case "rust":
    case "rs":
      return {
        lineComments: ["//"],
        blockComments: [["/*", "*/"]],
        quotes: '"',
        keywords: kwRust,
        types: tyRust,
      };
    case "go":
    case "golang":
      return {
        lineComments: ["//"],
        blockComments: [["/*", "*/"]],
        quotes: "\"'`",
        keywords: kwGo,
        types: tyGo,
      };
    case "python":
    case "py":
      return { lineComments: ["#"], blockComments: [], quotes: "\"'", keywords: kwPy, types: tyPy };
    case "javascript":
    case "js":
    case "jsx":
    case "typescript":
    case "ts":
    case "tsx":
    case "mjs":
    case "cjs":
      return {
        lineComments: ["//"],
        blockComments: [["/*", "*/"]],
        quotes: "\"'`",
        keywords: kwJS,
        types: tyJS,
      };
    case "csharp":
    case "cs":
    case "c#":
      return {
        lineComments: ["//"],
        blockComments: [["/*", "*/"]],
        quotes: "\"'",
        keywords: kwCS,
        types: tyCS,
      };
    case "dart":
      return {
        lineComments: ["//"],
        blockComments: [["/*", "*/"]],
        quotes: "\"'",
        keywords: kwDart,
        types: tyDart,
      };
    case "kotlin":
    case "kt":
    case "kts":
      return {
        lineComments: ["//"],
        blockComments: [["/*", "*/"]],
        quotes: "\"'",
        keywords: kwKotlin,
        types: tyKotlin,
      };
    case "java":
      return {
        lineComments: ["//"],
        blockComments: [["/*", "*/"]],
        quotes: "\"'",
        keywords: union(kwJS, kwCS),
        types: union(tyJS, tyCS),
      };
    case "bash":
    case "sh":
    case "shell":
    case "zsh":
    case "console":
      return { lineComments: ["#"], blockComments: [], quotes: "\"'", keywords: kwBash, types: tyBash };
    case "powershell":
    case "ps1":
    case "pwsh":
      return {
        lineComments: ["#"],
        blockComments: [["<#", "#>"]],
        quotes: "\"'",
        keywords: kwPS,
        types: tyPS,
        dashIdent: true,
      };
    case "sql":
      return {
        lineComments: ["--"],
        blockComments: [["/*", "*/"]],
        quotes: "\"'",
        keywords: kwSQL,
        types: tySQL,
      };
    case "json":
    case "jsonc":
      return { lineComments: ["//"], blockComments: [], quotes: '"', types: set("true false null"), keyish: true };
    case "yaml":
    case "yml":
      return {
        lineComments: ["#"],
        blockComments: [],
        quotes: "\"'",
        types: set("true false null yes no on off"),
        keyish: true,
      };
    case "toml":
    case "ini":
    case "cfg":
      return { lineComments: ["#", ";"], blockComments: [], quotes: "\"'", keyish: true };
    case "cmake":
      return {
        lineComments: ["#"],
        blockComments: [],
        quotes: '"',
        types: set(
          "if else elseif endif foreach endforeach function endfunction macro endmacro set unset project add_executable add_library target_link_libraries include message option list find_package target_include_directories"
        ),
      };
    case "make":
    case "makefile":
      return {
        lineComments: ["#"],
        blockComments: [],
        quotes: '"',
        types: set("all clean install test build run"),
      };
    case "xml":
    case "html":
    case "xaml":
    case "svg":
    case "razor":
    case "cshtml":
      return { lineComments: [], blockComments: [["<!--", "-->"]], quotes: "", markup: true };
    case "css":
    case "scss":
    case "less":
      return {
        lineComments: ["//"],
        blockComments: [["/*", "*/"]],
        quotes: "\"'",
        keyish: true,
      };
    case "lua":
      return {
        lineComments: ["--"],
        blockComments: [],
        quotes: "\"'",
        types: set("function end if then else elseif for while do return local nil true false and or not"),
      };
    case "swift":
      return {
        lineComments: ["//"],
        blockComments: [["/*", "*/"]],
        quotes: "\"'",
        keywords: set(
          "func var let class struct enum protocol extension if else guard for while switch case return try catch throw import init deinit self super nil true false async await actor some any where in as is"
        ),
      };
    case "diff":
    case "patch":
      return { lineComments: [], blockComments: [], quotes: "" };
  }
  return null;
}

function isIdentCode(c: number): boolean {
  return (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c === 95 || c >= 0x80;
}

function isDigitCode(c: number): boolean {
  return c >= 48 && c <= 57;
}

function isHexCode(c: number): boolean {
  return (c >= 48 && c <= 57) || (c >= 97 && c <= 102) || (c >= 65 && c <= 70);
}

export function escHTML(s: string): string {
  let out = "";
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (c === "&") out += "&amp;";
    else if (c === "<") out += "&lt;";
    else if (c === ">") out += "&gt;";
    else out += c;
  }
  return out;
}

function span(cls: string, text: string): string {
  return `<span class="${cls}">${escHTML(text)}</span>`;
}

// writeRaw 写出未着色的普通字符：必须转义，否则代码里的 <u32>、<class T>
// 会被浏览器当成 HTML 标签吃掉（内容静默消失）。
function writeRaw(out: string[], c: string): void {
  if (c === "&") out.push("&amp;");
  else if (c === "<") out.push("&lt;");
  else if (c === ">") out.push("&gt;");
  else out.push(c);
}

export function highlightCode(lang: string, code: string): string {
  const def = langDefFor(lang);
  if (!def) return escHTML(code);
  if (def.markup) return highlightMarkup(code);
  if (lang === "diff" || lang === "patch") return highlightDiff(code);

  const out: string[] = [];
  let i = 0;
  let atLineStart = true;
  while (i < code.length) {
    const ch = code[i] ?? "";
    let matched = false;

    for (const lc of def.lineComments) {
      if (code.startsWith(lc, i)) {
        let j = code.indexOf("\n", i);
        if (j < 0) j = code.length;
        out.push(span("tok-c", code.slice(i, j)));
        i = j;
        matched = true;
        break;
      }
    }
    if (matched) continue;

    for (const [open, close] of def.blockComments) {
      if (code.startsWith(open, i)) {
        const idx = code.indexOf(close, i + open.length);
        const j = idx < 0 ? code.length : idx + close.length;
        out.push(span("tok-c", code.slice(i, j)));
        i = j;
        matched = true;
        break;
      }
    }
    if (matched) continue;

    if (def.preprocHash && ch === "#" && atLineStart) {
      let j = code.indexOf("\n", i);
      if (j < 0) j = code.length;
      out.push(span("tok-p", code.slice(i, j)));
      i = j;
      continue;
    }

    if (def.quotes.includes(ch) && ch !== "\0") {
      const j = scanString(code, i, ch);
      out.push(span("tok-s", code.slice(i, j)));
      i = j;
      continue;
    }

    if (isDigitCode(ch.charCodeAt(0)) && (i === 0 || !isIdentCode(code.charCodeAt(i - 1)))) {
      const j = scanNumber(code, i);
      out.push(span("tok-m", code.slice(i, j)));
      i = j;
      continue;
    }

    if (isIdentCode(ch.charCodeAt(0))) {
      let j = i;
      while (
        j < code.length &&
        (isIdentCode(code.charCodeAt(j)) ||
          isDigitCode(code.charCodeAt(j)) ||
          (def.dashIdent === true &&
            code[j] === "-" &&
            j + 1 < code.length &&
            isIdentCode(code.charCodeAt(j + 1))))
      ) {
        j++;
      }
      const word = code.slice(i, j);
      const next = nextNonSpace(code, j);
      const nextCh = next < code.length ? code[next] : "";
      if (def.keywords?.has(word)) out.push(span("tok-k", word));
      else if (def.types?.has(word)) out.push(span("tok-t", word));
      else if (nextCh === "(") out.push(span("tok-f", word));
      else if (nextCh === "!" && code[next + 1] === "(") out.push(span("tok-f", word));
      else if (def.keyish === true && (nextCh === ":" || nextCh === "=")) out.push(span("tok-v", word));
      else out.push(word);
      i = j;
      continue;
    }

    if (
      ch === "$" &&
      i + 1 < code.length &&
      (isIdentCode(code.charCodeAt(i + 1)) || code[i + 1] === "{" || code[i + 1] === "(")
    ) {
      let j = i + 1;
      if (code[j] === "{") {
        while (j < code.length && code[j] !== "}") j++;
        if (j < code.length) j++;
      } else if (code[j] === "(") {
        let depth = 0;
        while (j < code.length) {
          if (code[j] === "(") depth++;
          if (code[j] === ")") {
            depth--;
            if (depth === 0) {
              j++;
              break;
            }
          }
          j++;
        }
      } else {
        while (j < code.length && (isIdentCode(code.charCodeAt(j)) || isDigitCode(code.charCodeAt(j)))) j++;
      }
      out.push(span("tok-v", code.slice(i, j)));
      i = j;
      continue;
    }

    if (ch === "\n") {
      atLineStart = true;
      out.push(ch);
      i++;
      continue;
    }
    if (ch !== " " && ch !== "\t") atLineStart = false;
    writeRaw(out, ch);
    i++;
  }
  return out.join("");
}

function nextNonSpace(s: string, i: number): number {
  while (i < s.length && (s[i] === " " || s[i] === "\t")) i++;
  return i;
}

// scanString 处理转义、多行与原样字符串（` 在 Go/JS 中不转义）。
function scanString(s: string, i: number, q: string): number {
  let j = i + 1;
  while (j < s.length) {
    const c = s[j];
    if (c === "\\" && q !== "`") {
      j += 2;
      continue;
    }
    if (c === q) return j + 1;
    if (c === "\n" && q !== "`") return j;
    j++;
  }
  return s.length;
}

function scanNumber(s: string, i: number): number {
  let j = i;
  if (s.startsWith("0x", i) || s.startsWith("0X", i) || s.startsWith("0b", i) || s.startsWith("0B", i)) {
    j += 2;
    while (j < s.length && (isHexCode(s.charCodeAt(j)) || s[j] === "_" || s[j] === "'")) j++;
    return j;
  }
  while (j < s.length) {
    const c = s[j] ?? "";
    if (isDigitCode(s.charCodeAt(j)) || c === "." || c === "_" || c === "'") {
      j++;
      continue;
    }
    if ((c === "e" || c === "E" || c === "x" || c === "p" || c === "P") && j + 1 < s.length) {
      j++;
      if (s[j] === "+" || s[j] === "-") j++;
      continue;
    }
    if ("fFuUlLizd".includes(c)) {
      j++;
      continue;
    }
    break;
  }
  return j;
}

function entityLen(s: string): number {
  if (s.length < 3 || s[0] !== "&") return 0;
  if (s[1] === "#") {
    let j = 2;
    if (j < s.length && (s[j] === "x" || s[j] === "X")) {
      j++;
      const start = j;
      while (j < s.length && isHexCode(s.charCodeAt(j))) j++;
      if (j > start && j < s.length && s[j] === ";" && j - start <= 6) return j + 1;
      return 0;
    }
    const start = j;
    while (j < s.length && s[j] !== undefined && s[j]! >= "0" && s[j]! <= "9") j++;
    if (j > start && j < s.length && s[j] === ";") return j + 1;
    return 0;
  }
  let j = 1;
  while (j < s.length && /[A-Za-z0-9]/.test(s[j] ?? "")) j++;
  if (j > 1 && j < s.length && s[j] === ";") return j + 1;
  return 0;
}

// highlightMarkup 处理 XML / HTML / XAML：标签名、属性名、属性值、注释、实体。
// 注意：这是代码块内的着色，所有结构字符都必须转义输出（&lt; 而不是 <），
// 否则代码里写的标签会被浏览器当真实标签吃掉。
function highlightMarkup(code: string): string {
  const out: string[] = [];
  let i = 0;
  while (i < code.length) {
    if (code.startsWith("<!--", i)) {
      const idx = code.indexOf("-->", i + 4);
      const j = idx < 0 ? code.length : idx + 3;
      out.push(span("tok-c", code.slice(i, j)));
      i = j;
      continue;
    }
    if (code[i] === "<") {
      let j = i + 1;
      if (code[j] === "/") j++;
      const start = j;
      while (
        j < code.length &&
        (isIdentCode(code.charCodeAt(j)) ||
          isDigitCode(code.charCodeAt(j)) ||
          code[j] === "-" ||
          code[j] === ":")
      ) {
        j++;
      }
      const name = code.slice(start, j);
      out.push("&lt;");
      if (start > i + 1) out.push("/");
      out.push(span("tok-t", name));
      i = j;
      while (i < code.length && code[i] !== ">") {
        if (code[i] === '"' || code[i] === "'") {
          const k = scanString(code, i, code[i] ?? '"');
          out.push(span("tok-s", code.slice(i, k)));
          i = k;
          continue;
        }
        if (isIdentCode(code.charCodeAt(i))) {
          let k = i;
          while (
            k < code.length &&
            (isIdentCode(code.charCodeAt(k)) ||
              isDigitCode(code.charCodeAt(k)) ||
              code[k] === "-" ||
              code[k] === ":")
          ) {
            k++;
          }
          out.push(span("tok-v", code.slice(i, k)));
          i = k;
          continue;
        }
        if (code[i] === "\n") break;
        writeRaw(out, code[i] ?? "");
        i++;
      }
      continue;
    }
    if (code[i] === "&") {
      const n = entityLen(code.slice(i));
      if (n > 0) {
        out.push(span("tok-m", code.slice(i, i + n)));
        i += n;
        continue;
      }
    }
    writeRaw(out, code[i] ?? "");
    i++;
  }
  return out.join("");
}

function highlightDiff(code: string): string {
  return code
    .split("\n")
    .map((line) => {
      if (line.startsWith("+")) return span("tok-ins", line);
      if (line.startsWith("-")) return span("tok-del", line);
      if (line.startsWith("@@")) return span("tok-v", line);
      return escHTML(line);
    })
    .join("\n");
}
