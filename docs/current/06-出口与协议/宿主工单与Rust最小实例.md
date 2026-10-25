# 宿主工单与 Rust 最小实例

> **性质**：宿主侧（协议边界外）工单席位职责书 + 最小实例册。回答一个问题：**Rust 在本仓要做什么、每件的最小形态是什么、怎么验收**。
> **分工**：上游裁定见《[出口分档与宿主策略](出口分档与宿主策略.md)》§6.4 语言版图（末句「**宿主侧语言不进版图，引擎侧只认协议**」为本 doc 的合法性依据）；出口形态与消费者选型见《[出口形态全景与选型研究](出口形态全景与选型研究.md)》。本文不改变任何上游结论，引擎侧零侵入——MoonBit 唯一实现语言不变。
> **证据纪律**：全部数字为 **2026-10-24/25 本机实测**（Windows x64；zig 0.17.0 sha 钉版 / rustc·cargo 1.95.0 / bun 1.4.3 / node 25.9），可复跑工件在 `tmp/sizeprobe/` 与 `tmp/zigprobe/`（tmp 为 gitignore 面，关键数字已内联）。绝对值随机器漂移，比值与语义对账（终态/步数逐位一致）为准。
> **最后核对**：2026-10-25

## 1. 席位与触发线

| 席位 | 内容 | 语言 | 开工信号 |
|---|---|---|---|
| **R1 工单①：polyfill 宿主** | 内嵌 wasm 运行时 + 供给 js-string builtins + 反射式常量装载；引擎永远只出 ON 态单制品 | **Rust（在任）** | 非 JS 宿主真实消费者出现 / 全景 §3.4 #4 正式立项 |
| **R2 工单②：delegate 加速核** | 契约面纯数值 ABI 核（plain wasm + native 双出口），引擎委派热任务 | **Rust/Zig 并列**（终裁=γ 触发后一周级同台探针） | **γ**：mb_opt 落地 + 生成器排期后仍出步预算真红 |
| R3 wasmtime 依赖 | 随 R1/R2 走的版本钉版义务 | — | crate ≤48（rustc ≥1.96 放宽），lockfile 登记 |

旁挂（不属本 doc、防遗失）：**α** CI 非 Windows native 臂/clang 钉版漂移 → zig cc 候选（工具非语言）；**β** instrumented corpus+clang 内部裁判落地后仍实锤同源盲区 → 跨语言第二实现重开（WAT/Zig/Rust 同台）。

## 2. 为什么是 Rust（三层，从硬到软）

1. **在任事实**：工单①原型已是 Rust——`tmp/wasmtime_host`（Cargo 工程）完成过零导入风味端到端验收（全景 §3.4，2026-10-17）。wasmtime 本身是 Rust 生态一等制品（171 个 GC 引用操作函数），用它即有 Rust 依赖，区别只在宿主用一等 API 还是绕 C API。
2. **形态匹配**：宿主持**引擎堆的 GC 引用**，引用出错 = 腐蚀引擎堆——恰是借用检查器最值钱的场景；delegate 核是纯数值 ABI plain wasm（无需 GC），Rust 的 `wasm32-unknown-unknown` 生产级稳定且经仓库自家 wasmopt 闸实测通过。
3. **版图豁免**：§6.4 末句明文。与既往筛选的关系（全在引擎侧，本 doc 是宿主侧新岗）：C 重写五轮驳回（引擎）、双语言核心过筛 2026-09-25（引擎，Zig A-04 两条排除判的是核心席位）、#273 ts 统一（scripts 域）、py 排除（缺的恰是 Rust 有一等 wasmtime 绑定）、Kotlin 驳回（无实测无触发线）、OCaml 避难所+S9「不做预案」（本 doc 不触碰）。用户选型四原则（2026-10-24）的操作化：**申请的是席位+可证伪触发线+反向条款（未命中不开工），不是现在开工**。

## 3. 工单①：polyfill 宿主（未开工——三件最小实例）

> 消费者：含 JS 宿主（浏览器/node）直接用引擎 wasm-gc 制品，**不经本工单**；本工单只服务「无 JS 宿主的 wasm 环境」（全景 §5 判据）。壳内**引擎照常执行**——壳只供给 imports，无双真相。

### R1-1 js-string builtins 供给

- **目标**：wasmtime（经 Rust crate）实例化现役 ON 态引擎制品（其 imports = `wasm:js-string`×6 + 4111 个导入字符串常量，全景 §3.4）。
- **三步**：① Linker 上按 `wasm:js-string` 名字空间定义 6 个内建（签名走 GC array：`array<i16>` UTF-16 口径，全景 §3.4 硬约束②）；② 枚举模块 imports，反射式把 4111 个导入字符串常量按**导入名即内容**物化成 GC array 常量；③ 实例化并跑 `ping`/`error_catalog` 冒烟。
- **验收判据**：`engine_version()`/`protocol_version()`/`invoke(ping)` 三帧绿（对齐 §3.4 已有 Rust 宿主验收面）；中文文案字节正确。
- **预判坑**：名义类型（`VMSharedTypeIndex`）必须借用模块自带 `ArrayType`（§3.4 硬约束①）；UTF-16 编解码不得按 UTF-8 解。

### R1-2 引擎装载门（能力探测）

- **目标**：宿主能力探测 → 选路：JS 宿主→引擎直载；无 JS 宿主→R1-1 供给。
- **三步**：① 探测面（js-string builtins 支持与否）落一张表；② 两路装载各出一条端到端冒烟；③ 失败路 fail loud 文案（装不上报什么、去哪找替代——sidecar/js 兜底指针）。
- **验收判据**：两路同一契约程序终态一致；错误路 rc≠0 且文案指路。
- **预判坑**：装载门是运行时接线非编译期分叉（delegate 协议同款性质），不得做成双制品。

### R1-3 单文件分发

- **目标**：宿主+引擎制品打进单 exe（烂环境交付容器）。
- **三步**：① bun `with { type: "file" }` 形态内嵌（**实测在案**：`readFileSync(new URL(...))` 形态不内嵌资产，运行时 ENOENT——bun_rust2.exe 91.9MB 为正确形态对照物）；② Rust 侧等价物 = `rust-embed`/include_bytes + cargo build；③ 冒烟 run。
- **验收判据**：exe 在无 wasm 运行时的裸机跑通引擎冒烟；体积口径如实记录（91.9MB 里 bun/JSC 运行时占绝对大头，核体积不敏感）。

## 4. 工单②：delegate 加速核（基线已建成——五件最小实例，全部实测）

> 已建成部分即「最小实例」本身；γ 未触发前不再前进。Rust/Zig 双方终态与步数**逐位一致**，座次差为 dispatch 形态非语言。

### R2-1 契约核（native + wasm 双出口）✅ 已建成

- **工件**：`tmp/sizeprobe/rust_core/`（与 `tmp/zigprobe/a1_core/main.zig` 逐语句对应的 Rust 移植：手写最小 JSON 扫描 + 15 opcode + 位模式值栈/帧；零依赖零 unsafe）。
- **结果**：**steps=115000021、终态 992237507**，与 Zig native（8ns/步）四方逐位一致；Rust native **1-2ns/步（零 unsafe，全边界检查）**；imports=0 双出口。
- **坑**：`include_str!` 相对源文件；cdylib/bin 同名撞 PDB；`Instant::now()` 在 wasm32-unknown-unknown **panic**（freestanding 无时钟——计时交宿主，`#[cfg]` 门控解决；Zig 核头注早有明文，属平台事实非缺陷）。

### R2-2 三档帧锚采样 ✅ 已建成

- **工件**：同上，`ZSAMPLE_MODE=0/1/2`（L1 计数 / L2 环形 `(ip<<32|sp)` 65536 槽）。
- **结果**：L0=2ns anchors=0；L1/L2=2ns **anchors=10000006 与 Zig 采样器精确吻合**（契约预测 1000 万+循环外 6）——全采零税跨语言复现；窄事件流格式（出口 8 的雏形）可跨语言移植。

### R2-3 委派双接线 ✅ 已建成

- **工件**：`tmp/sizeprobe/delegate_dual.cjs` + MoonBit 主制品 `delegate.wasm`（imports 实测=`zigcore.vitro_run/vitro_steps` 两条）。
- **结果**：同一主制品接线表换子代理——Zig 11.1-11.6ns/步、**Rust 3.5-3.8ns/步**，双方 result/steps 逐位一致。协议=运行时接线非编译期分叉，语言无关坐实。

### R2-4 wasmopt 过闸产物 ✅ 已建成

- **结果**：Rust wasm 裸 35.7-38.9KB → 仓库自家 wasmopt 管线 → **27.8KB（gzip 11.6KB）**，opt 后功能完好。对照：Zig 0.17 裸 1.8MB（-fstrip 同）且 **binaryen 拒析**、在档 44.6KB 路径不可复现——「当前唯一过闸的第二语言 wasm 路径」。
- **坑（档案修正三条，随本 doc 入档）**：bun `readFileSync(new URL(...))` 不内嵌资产；「16×」体积算术不复现（实测 870KB vs 91.9MB=108×）；「一条命令交叉编译」被现役 Zig 源码证否（`nowNs` 硬编码 ntdll）。

### R2-5 终裁同台探针（未开工——γ 触发后）

- **目标**：mb_opt 落地+生成器排期后若仍出步预算红，Rust/Zig 同契约同台一周探针定座次（判据：契约面大小 / 二进制体积 / 安全姿态 / 过闸 wasm 体积 / **行数增长形态**〔WAT 手写 104 行 4 轮括号事故 vs Zig 228 vs Rust 321 的外推基线〕；zigprobe 现有比值：mb_as_is 62.33 / mb_opt 4.10 / zig_fast 1.12 / zig_safe 1.48）。
- **边界**：γ 未命中，本件不开工；**裁判语义不归核**——过程层真值锚是 instrumented corpus + clang（裁判姓 clang），核只产低级事实（ip/sp/锚点），教学语义单源钉在 MoonBit。

## 5. 边界与义务

- **Rust 不做什么**：引擎（无 wasm-gc 一等目标）、语义裁判、scripts（#273 ts 执掌）、交付主线（wasm-gc+js+MoonBit native 三臂现役）、应急兜底（S9 终裁不做预案）。
- **开工义务**（触发后）：依赖白名单登记 + lockfile；wasmtime 钉版；CI job 接线（ci_checklist 三向对账）；命名 host 组件；宿主代码闸 inventory 从零建（不因语言豁免）——含测试设施（`zig test`/`cargo test` 对应物）与进程内 fuzz 期权（zig `-fuzz` / cargo-fuzz 同为 LibFuzzer 系，启用随闸 inventory 一并裁）。
- **关联处置**：统一出口按「wasm-gc（ON 态单制品）+ js + 壳」收敛后，`iss-199-wasm-arms` 双风味管线建议 park（push 归档或删+触发线），不得单机裸奔。

## 6. 复跑指引

```bash
# R2-1/2：Rust 契约核 + 三档采样
cd tmp/sizeprobe/rust_core && cargo build --release --bin rust_core
./target/release/rust_core.exe                    # ZSAMPLE_MODE=0/1/2
cargo build --release --target wasm32-unknown-unknown --lib
# R2-3：委派双接线
cd tmp/sizeprobe && node delegate_dual.cjs
# R1-3 对照物 + R2-4：bun 单文件（正确内嵌形态）与 wasmopt
cd tmp/sizeprobe/buntest && bun build --compile embed2.js --outfile bun_rust2.exe && ./bun_rust2.exe
node scripts/wasmopt/main.mts tmp/sizeprobe/rust_core/target/wasm32-unknown-unknown/release/rust_core_wasm.wasm
# Zig 侧对照
cd tmp/zigprobe/a1_core && zig build-exe main.zig -O ReleaseFast -femit-bin=a1perf && ./a1perf
```

---

## 附：zigprobe 十四出口 → 本册落点映射（逐件可查，无一流失）

> 辩论中已让位四件（纯算吞吐→生成器正解、wasm-gc 套娃→js 后端、js-string 双态→MoonBit 开关、性能独占→WAT/mb_opt）不在十四之数，座次已入 §2。下表为十四件的逐件去向：

| # | 出口 | 本册落点 | 状态 |
|---|---|---|---|
| 1 | 委派子代理 | **R2-3**（已建成：同一主制品换子代理，Rust 3.5-3.8 vs Zig 11.1-11.6 ns/步，终态步数逐位一致） | ✅ 已建成 |
| 2 | 帧锚点采样执行 | **R2-2**（三档 2ns、anchors=10000006 与 Zig 采样器精确吻合） | ✅ 已建成 |
| 3 | 差分第四臂 | 拆两半：**语义裁判→白箱 P0 线**（instrumented corpus+clang，裁判姓 clang，不在本册）；契约级六方一致→**R2-1/R2-3 的验收判据** | 拆分落座 |
| 4 | 可选加速器协议 | **R2-3** 的运行时接线性质 + **R1-2** 装载门同款纪律（快慢档=宿主接线表，非编译期分叉） | ✅ 并入 |
| 5 | WAT/Zig 协同分工 | **§1 R2** 并列候选 + **§2** 比对 + **R2-5** 终裁判据（含行数增长形态） | 座次注记 |
| 6 | 两遍分离执行 | **R2-1 即 Pass2 形态**（裸核：无热力图/freed/StepEvent 语义），Pass1=引擎（14.2s 全量实测）；终态一致性四方验证；预检传递性用例待跑，随 γ | 并入+待验 |
| 7 | 壳保底/全域运行时 | **R1-1/R1-2/R1-3 三件转正为工单①**（bun 91.9MB 单文件跑通；readFileSync 内嵌形态缺陷实证修正） | ✅ 转正 |
| 8 | 窄同步事件流 | **R2-2** L2 环形格式 `(ip<<32\|sp)` + **R2-5** 边界句（核只产低级事实，教学语义单源钉 MoonBit——宽同步=oracle 死因复刻） | ✅ 并入 |
| 9 | 结果先行 | 数字入 **R2-1**（核 0.23s vs 引擎 14.2s，窗口 62×）；**产品接线归 demo 侧前端工单，不在本册**（老浏览器=核出终态+js 臂演动画的产品分层已裁） | 拆分（数字入册/产品另立） |
| 10 | comptime 契约面 | **§2** 比对（Rust 无 comptime——正解=build.rs+cargo 新鲜度，同 TS 注入器三件套；Zig 零机制优势入档）+ **R2-1** 的 include_str+手写扫描即 Rust 侧最小形态 | 比对入册 |
| 11 | 无 UB 裁判 | **R2-1 坑登记**（溢出双构建档双语言对称实测：默认档静默回绕/检查档 panic/常量溢出编译期 deny） | ✅ |
| 12 | 规模化可维护性 | 行数对照 WAT 104（4 轮括号事故）/ Zig 228 / Rust 321（含注释）→ **R2-5 判据「行数增长形态」** | 本轮补入 |
| 13 | 工程设施四件 | 溢出双构建档→**R2-1 坑**；交叉编译证否→**R2-4 修正**；测试设施与进程内 fuzz 期权→**§5 义务**（闸 inventory 隐含，本轮补显式） | ✅ 补显 |
| 14 | native 单文件出口 | **R1-3**（bun 91.9MB 对照，内嵌 Rust wasm 跑通）+ **R2-4** 修正（「16×」算术不复现，实测 108×）+ **§5** 边界（MoonBit native exe 在产，非语言独占） | ✅ 拆并入 |

---

**状态记录**：2026-10-25 建册（九轮选型辩论 + 十四出口全量复跑 + Rust 全量对照收束；issue 形态撤回改落本文）。数字出处：`tmp/sizeprobe/`（rust_core / ovf / buntest / delegate_dual.cjs）、`tmp/zigprobe/README.md`（三臂比值）、`tmp/zigprobe/delegate/delegate_harness.cjs`。上游文档未改动；本文进入工作区待提交，提交指令另听。
