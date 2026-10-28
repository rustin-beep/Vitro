# DUMP_ARTIFACTS_V1 — dump 族产物契约（随包分发）

> 状态：**成文 2026-10-27（issue #230——此前 dump 族输出零文档，下游无法基于产物建工具链）**。
> 消费先例：仓内差分防线（`scripts/diff_gate` 的 parser/typeck/codegen 三驱动逐字节消费本契约产物）。
> **契约级变更纪律**：本文件描述的产物形态是差分对拍的 B 级锚——任何列序/键序/转义/末行变更须连坐五家 golden digest 重冻，禁止静默改形。

## 0. 工具族与用法（四件，native only）

```
moon run cmd/dump_tokens  -- <corpus_dir|file.c> <out_dir> <raw|pp|both>
moon run cmd/dump_ast     -- <corpus_dir|file.c> <out_dir>
moon run cmd/dump_typeck  -- <corpus_dir|file.c> <out_dir>
moon run cmd/dump_compile -- <corpus_dir|file.c> <out_dir> [--library]
```

- 构建：`MOON_CC=clang moon build --target native cmd/dump_tokens cmd/dump_ast cmd/dump_typeck cmd/dump_compile`（clang 口径见根 AGENTS 纪律 11）。
- 输入：单 `.c` 文件或语料目录（目录模式按字典序处理全部 `*.c`）；自定义 include 的 VFS 自动收集同目录 `.h`（`tokenize_with_vfs` + `base_dir`——目录级收集一次共享）。
- **用法错 rc 契约（#230 起，2026-10-27）**：缺参 / 模式非法 / 参数过多 / 输出目录与语料目录相同 ⇒ stdout 一行原因（用法行或具体原因）+ **rc=4**（与 `vitro` 总入口用法错同口径，#215）；旧形态（未捕获 `Failure` 的 PanicError 栈 + rc=127）已退役。
- 处理成功 ⇒ stdout 汇总行（`dump_<name>: N 个输入 -> <out_dir>`）+ rc=0。

## 1. 文件名规则（两族约定，勿混）

| 工具 | 产物（每输入一份） | stem 约定 |
|---|---|---|
| dump_tokens | `<stem>.l1.tsv`（raw 层）/ `<stem>.l2.tsv`（pp 层） | **剥 `.c`**（`probe.c` → `probe.l1.tsv`） |
| dump_ast | `<stem>.ast.json` | **含 `.c`**（`probe.c` → `probe.c.ast.json`；F11 对拍键约定） |
| dump_typeck | `<stem>.typeck.json` | 含 `.c` |
| dump_compile | `<stem>.compile.json` | 含 `.c` |

> 差异是历史对拍约定（F11）：tokens 族剥扩展名、其余三族保留——**下游按上表消费，勿假设统一**。

## 2. L1/L2 token TSV（`lexer/tsv.mbt` 单源发射）

每 token 一行，制表符分隔，LF 行尾，UTF-8：

- **L1（raw，预处理前）**：`<index>\t<Ty>\t<text>\t<line>\t<col>\t<byte_off>`
- **L2（pp 后）**：`<index>\t<Ty>\t<text>\t<line>\t<col>`（无 byte_off；位置钉**宏调用点**）
- **末行**：`count=<n>\terrors=<n>\twarnings=<n>`（count = 非 Eof token 数，即末 token 下标；L1 的 warnings 恒 0）

列语义：

| 列 | 语义 |
|---|---|
| index | token 序号（0 起，Eof 是最后一个 token） |
| Ty | token 类型名（`Int` / `Identifier` / `LParen` / … / `Eof`） |
| text | **规范化值**：整数十进制 / 字符串解码值 / 字符数值 / 浮点源拼写（非源码原文） |
| line / col | 源坐标；**col = `column − text 的 UTF-8 字节数`**（回推公式，列计数按字节——#242；无缺陷坐标用 byte_off） |
| byte_off | 仅 L1：token 起始字节偏移（0 起） |

text 转义（仅四字符，其余原样含非 ASCII）：`\` → `\\`、换行 → `\n`、制表 → `\t`、回车 → `\r`。Eof 行 text 为空（连续两个制表符）。

## 3. `<stem>.c.ast.json`（dump_ast，E1/E2 面）

顶层五键（手写发射，键间带 `, ` 分隔——与 compile.json 的 compact 形态不同，消费侧勿假设统一空白风格）：

```json
{"ok": bool, "parse_error_count": N, "ast": {...}|null,
 "parse_errors": [{"code": N, "line": N, "column": N, "message": "..."}], "stall_count": N}
```

- **ok 语义**：程序结构是否可得——含错占位的 program 也算 `true`（实测 `int main() { int a = ; }` → `ok:true` + `parse_error_count:2`）；**诊断判读以 parse_errors 为准，勿单看 ok**。
- `ast`（Program）七键：`structs / unions / globals / funcs / classes / templates / template_instantiations`（后三者为 C++/泛型残留位，C 子集恒空数组）；节点内部结构单源 `@ast.ast_dump_json`（与 serve `ast.dump` 方法帧同构）。
- 词法错误形态：`{"ok": false, "lex_error_count": N, "ast": null, "parse_errors": [], "stall_count": 0}`。
- `stall_count`：解析器活性观测（零推进熔断计数，勘察 6-3）。

## 4. `<stem>.c.typeck.json`（dump_typeck，E4 + 三段诊断）

顶层七键（同款 `, ` 分隔手写发射）：

```json
{"ok": bool, "parse_error_count": N, "typed_ast": {...}|null,
 "parse_errors": [...], "type_errors": [...], "type_warnings": [...], "type_hints": [...]}
```

- 诊断条目四字段同 §3（code/line/column/message，push 序保序）。
- **管线语义**：parse 错误非空 ⇒ typeck 不跑（`typed_ast:null` + 三段 type_* 全空）；词法错误 ⇒ `lex_error_count` 形态。
- `typed_ast` = lowering 后 ProgramNode（E4 面，`@typeck` 单源）。

## 5. `<stem>.c.compile.json`（dump_compile，A 级 14 键对拍面）

**compact 无空白**发射，外层四键：

```json
{"ok":true,"slot_strategy":N,"verify":{"ok":bool,"violations":[...]},"dump":{...}}
```

- `dump` **14 键**（`@bytecode.compile_output_dump_json` 单源；version + CompileOutput 13 字段）：
  `version / code / globals_init_32 / globals_init_64 / func_table / func_index / string_data / source_map / symbols / struct_defs / union_defs / f64_constants / i64_constants / global_data_end`
- `code` 元素：`{"op":"<OpName>","operand":N,"loc":{"line":N,"column":N,"file_id":N}}`。
- 外层 `slot_strategy`（槽位策略版本，对拍闸字段）与 `verify`（#200 P0 bytecode 结构验证器出口——`violations` 空数组 = 结构通过）是**包装层**，不参与 14 键对拍面。
- 失败形态（管线逐层 fail loud）：`{"ok":false,"stage":"lex|parse|type|gen","errors":["<msg>"]}`——stage 供差分驱动按层对齐。
- `--library`：library mode（预编译 Bytecode Libc 自身——不预注册固定索引段、全局偏移自 0 起）；**main 检查不豁免**。

## 6. 编码与行尾总则

- 全部产物 UTF-8、LF 行尾（发射器直写 `\n`，不做平台转换）。
- JSON 字符串转义单源 `@ast.json_escape_string`（serde_json 口径，U+0000–001F 全 `\u00XX`）。
- 产物文件由工具一次性整文件写出（无追加语义）；同路径重跑覆盖。
