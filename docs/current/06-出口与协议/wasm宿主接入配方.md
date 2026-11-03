# wasm 宿主接入配方（gateway/wasm 产物）

> as_of 2026-11-02 · B3 批成文。素材 = W4 批第四臂普查（`tmp/batch_W4_REPORT.md`；探针资产
> `scripts/wasmtime_arm/`〔Rust 跑器 + node 跑器 + 对拍驱动〕已随 PR #422 合入 master `5233ad65`）+ moonbit/AGENTS.md
> 陷阱 40（wasm-gc 导出三事实）+ 《出口分档与宿主策略》§3.5 宿主可达性矩阵 + S9 判定书
> 「.NET 通道 = serve sidecar 或 WebView2」裁定。姊妹册：《宿主工单与Rust最小实例》（R1/R2 工单席位）。

## 硬结论

**gateway/wasm 宿主面 = V8 系开箱、Rust 可写、其余免谈。**

- **V8 系开箱**：产物按 js-string builtins 提案编译（`builtins:['js-string']` +
  `importedStringConstants:'_'`），node/Chromium/Edge/Firefox 均原生供给六内建——零宿主代码。
- **Rust 可写**：wasmtime 无 js-string 实现，但经 **wasm polyfill 供给**（六内建用 wasm 自己
  实现，宿主零 host call）后 corpus run 面 **1.21×** 于 node——Cranelift/copying-GC 本征差距
  就是全部代价，实测可写可用。
- **其余免谈**：.NET（绑定层 48 编译期拒 non-externref）、Python（无 wasm-GC 值面绑定）等
  宿主的替代路径 = **serve sidecar 子进程（NDJSON over stdio）或 WebView2**，不做 js-string
  供给层（S9 判定书裁定）；「去 js-string 的 i32 壳第二产物」已否决（不维护第二产物——W4 批
  用户拍板）。

## 产物面事实（接配方前须知）

| 事实 | 值 |
|---|---|
| 构建命令 | `moon build --release --target wasm-gc gateway/wasm` + 后置 `node scripts/wasmopt/main.mts <产物>`（binaryen 132，-19.1% raw；等价性由 CI vm_diff 背书） |
| 导出 | `invoke` / `reset` / `protocol_version` / `engine_version`（`invoke(String) -> String` NDJSON 单口） |
| import 面 | `wasm:js-string` 六函数（`length`/`charCodeAt`/`equals`/`concat`/`fromCodePoint`/`fromCharCodeArray`）+ `_` 模块字符串常量（opt 产物 3841 条）——**零功能性 imports** |
| String 语义 | js-string builtins 下 String 按 UTF-16 code unit 直传宿主（陷阱 40 ②） |
| 交付形态参考 | opt 产物 sha256 `70aef830…`、829,813 B（W4 批实测锚） |

## 配方一：node builtins 开箱版（默认形态）

```js
// node ≥ 22（Chromium/Edge/Firefox 同款编译选项；Safari 见《出口分档》§3.5 可达性矩阵）
const buf = fs.readFileSync("wasm.wasm");
const { instance } = await WebAssembly.instantiate(buf, {}, {
  builtins: ["js-string"],            // js-string builtins 提案
  importedStringConstants: "_",       // "_" 模块字符串常量（名称须与产物 import 段一致）
});
const invoke = instance.exports.invoke; // (string) -> string
const resp = invoke('{"id":1,"method":"ping","params":{}}');  // → '{"id":1,"ok":true,...}'
```

- 零宿主代码；NDJSON 帧序（session.create → compile → run → step.begin/next → output.delta）
  见随包 `moonbit/docs/spec/CLI_PROTOCOL_V1.md`。
- V8 把六内建当**编译器内建内联**（W4 分离实验实测 ~1ns 级）——宿主无需任何优化。
- 仓内现成装载器：`scripts/wasm_load.mts`（统一装载 + 断言）；端到端样例 = `examples/downstream-mini-c/`。

## 配方二：Rust wasmtime 手工供给版（~150 行核心 + ~80 行 WAT）

wasmtime（50.0.1，MSRV 1.97）无 js-string 提案实现——六内建必须自己供给。**两种供给形态的
性能差是结构性的**（W4 §6b 分离实验，perf 集 92 帧）：

| 供给形态 | host call 次数 | wasmtime | node | 倍率 |
|---|---|---|---|---|
| 宿主函数 `Func::new`（动态分派） | 2.2 亿 | 23.0s | 1.14s | 20× |
| 宿主函数 `Func::wrap`（typed） | 同 | 11.2s | 同 | 9.9× |
| **wasm polyfill（零 host call）+ Cranelift 内联** | **0**（仅 invoke 边界） | **3.0s** | 同 | **2.6×** |

（corpus 全量 run 面 927+static：polyfill 1.42s vs node 1.17s = **1.21×**；deep-nomem 3.9×。）
主因不是 Cranelift 代码质量：引擎 VM 热路径**每步 ~90 次字符串 host call**（`loop_5M_steps`
纯整数循环实测 4810 万次/54 万 VM 步——charCodeAt+equals 占 92%），V8 内联后无人察觉，
wasmtime 每次跨 wasm↔host 边界 ~51ns。

**polyfill 方案**（W4 实证形态，产物与引擎零改动）：

- 六内建用 wasm 自己实现——跑器内嵌 ~80 行 WAT（wasmtime 自带 `wat` crate 直编）：
  字符串 = wasm-gc `(array (mut i16))` 经 `extern.convert_any` 包成 externref；
  `length`/`charCodeAt`/`equals`/`concat`/`fromCodePoint`/`fromCharCodeArray` 以
  `array.len`/`array.get_u`/`array.copy`/`array.new_default` 实现并 `linker.define` 给主模块
  → import 调用变 **wasm→wasm 直接调用**（Cranelift 编译、无 trampoline、无 GC root scope）。
- `_` 字符串常量 3841 条同样走数组；宿主只在 `invoke` 边界经 typed `wrap`/`unwrap`
  构造/读取数组。

**GC 值面 / 引擎配置 API 清单**（wasmtime 50.0.1；代码真源 = `scripts/wasmtime_arm/rs/src/main.rs`）：

| API | 用途 / 陷阱 |
|---|---|
| `Config::compiler_inlining(Yes)` | 值得开：-11% 运行 / +350ms 一次性编译 |
| `Config::max_wasm_stack(N)` | **必须 < 宿主线程栈**，否则栈溢出从可捕获 trap 变**进程崩溃**（Windows 主线程 1MB 配 1MiB 实测 exit `0x40010004`）——跑器主体放 64MB 子线程，≤32MiB 安全 |
| `Config::async_stack_size` | max_wasm_stack ≥ 8MiB 时**连坐调**（默认 2MiB 上限会先炸） |
| `Collector::Auto` | 默认即 copying GC——非配置失误，本征差距来源之一 |
| `RootScope` / `Rooted<T>` | GC 值（externref/array）在 host 侧的 root 管理——host 函数供给形态必需；polyfill 形态只在 invoke 边界用到 |
| `Func::wrap`（typed） | 若走宿主函数供给（不推荐），typed 比 `Func::new` 动态分派快 2× |
| `wat::parse_str` | 内嵌 WAT polyfill 直编 |
| `Linker::define` | polyfill 六函数 + `_` 常量注入主模块 import 命名空间 |

**语义对齐注意**（供给层曾四处偏差，W4 固化时全修——js-string 提案 Overview 口径）：
`charCodeAt`/`fromCharCodeArray` 越界须 **trap**（不是返 0/钳制）、`equals` 允 null、
`fromCodePoint` 代理项码点保真单 code unit、index 参数按 unsigned 解释。

## 配方三（兜底）：其余宿主免谈——替代路径

- **serve sidecar**：宿主语言任意（.NET/Python/Go…），spawn `vitro serve`（native exe）或
  js 壳子进程，NDJSON over stdio 通信——协议面同 gateway，零 wasm 知识。S9 判定书给 .NET
  的处方即此（或 WebView2）。
- **WebView2 / CEF**：宿主内嵌 V8 系 webview，走配方一同构（P 线 desktop 壳即此形态）。
- **i32 壳第二产物**：不做（用户拍板，W4 批）——「去 js-string、String 全走 i32 通道的产物」
  意味着维护两份产物与两条出口测试面，而需要它的宿主（无 GC 值面绑定的运行时）可全部由
  sidecar 替代。若未来 wasm-gc 值面在某运行时成熟，重开评估。

## 普查数据（W4 批，双侧 sha256 逐位一致才采信）

- **零语义分叉**：corpus 927 份 × 3 profile（run / deep-nomem / deep）共 **27,177 帧** wasmtime
  vs node 响应文件逐位一致（opt 三 profile）+ raw 产物 5,580 帧零分叉；对抗合成集 57 语料
  + 25 行级对抗帧：DIFF=0。
- **唯一真分叉 = 栈预算**（非语义）：嵌套 struct 定义链触发引擎递归路径（~400 B/层）——
  wasmtime 默认 512KiB 栈 1000 层过 / 1500 溢出；**配 2MiB 后临界深度 (4000, 6000] 与 V8 默认
  完全重合**，分叉消失（6000+ 两侧皆 TRAP_BOTH）。wasm-opt（binaryen 132）对分叉面零影响。
- **独有诊断价值**：wasmtime 给**具名 backtrace**（V8 只报 `unreachable`）——W4 批靠它钉出
  dump 族深度上限 abort / lone surrogate abort / 会话态 note 泄漏三类引擎问题（§7 登记，非
  runtime 分叉）。
- **过闸建议**（W4 §9）：spot 对拍——发版前置 / 产物重大变更时本地 `all --profile deep-nomem`
  全量 + `--synth`，零 DIFF/零 TRAP_ONE 为过（44s 可挂 release_preflight）；任何 wasm 臂
  `unreachable` 用 debug 产物取具名 backtrace。

## 嵌入纪律速查

1. wasmtime 侧**必须用 polyfill 供给**，不要 host 函数供给（7–20× 慢是结构性的）。
2. `max_wasm_stack` < 宿主线程栈；子线程大栈 + `async_stack_size` 连坐。
3. trap 后**重建 Store/Instance**（MoonBit 运行时态不可信），策略两侧对称。
4. 深嵌套语料（struct 嵌套 > 4000 层）两侧皆溢出属预期——教学域语料远低于此。
