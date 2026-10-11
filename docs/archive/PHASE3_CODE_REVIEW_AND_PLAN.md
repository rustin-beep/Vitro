# Phase 3 代码审查与实施计划

> 基于对项目文档和全部核心源码的全面审查，整理本阶段错误、架构优化点与后续实施计划。

---

## 一、后续计划（Phase 3 及以后）

根据 `PHASE2_COMPLETION.md` 和 `DESIGN.md`，当前处于 **Phase 3：诊断与可视化**。

| 阶段 | 核心任务 | 当前状态 |
|:---|:---|:---|
| **Phase 3** | 中文错误分级 (L1/L2/L3)、QuickFix 引擎、知识卡片、零侵入可视化注入、内存/指针视图 Canvas、单步调试完成 | 进行中。`__cide_output`、`__cide_step` 已注入，Source Map 接口已预留，但 `cide_step_next` 仍为 stub |
| **Phase 4** | 算法模式识别、运行时验证、数据结构诊断 (`vis_array`/`vis_list`/`vis_tree`)、Starter Code 模板 | 未开始 |
| **Phase 5** | Android 触控手势、虚拟键盘适配、横竖屏切换、性能优化 (降帧率、CancelAll+Snap) | 未开始 |
| **Phase 6** | OCR 引擎集成、编译器驱动纠错核心、修正确认界面 | 未开始 |
| **Phase 7** | 子集渐进式解锁、知识图谱、社区贡献模板 | 未开始 |

---

## 二、本阶段实际存在的 Bug / 严重问题

### 🔴 1. 超时后 wasm3 线程泄漏（严重）
**文件**: `native/src/capi/cide_capi.cpp` (L551-L557)

```cpp
if (timedOut) {
    wasmThread.detach(); // let it run in background; we can't safely kill it
    ...
}
```

**问题**: 当程序执行超时时，wasm3 线程被 `detach()` 后放入后台继续运行。这意味着：
- 线程仍在消耗 CPU 和内存
- 用户再次点击"运行"时会创建新的 wasm3 runtime，旧线程可能产生竞争条件
- 多次超时后系统资源逐渐耗尽

**建议**: 使用 `std::jthread` + 停止标志，或在 wasm3 的 `m3_Yield` 中检查原子标志，使超时的线程能**安全且尽快地**自行退出，而不是永久泄漏。

---

### 🔴 2. 字符串字面量地址与全局内存可能重叠
**文件**: `native/src/compiler/WasmCodeGen.cpp` (L1094-L1112)

`stringAddrs_` 的起始地址 `nextStringAddr_` 默认为 **0**，而全局变量内存从 `0x1000` 开始。虽然当前不会立即重叠，但如果字符串总长度超过 `0x1000`，就会覆盖全局变量区。

**建议**: 将 `nextStringAddr_` 初始化为一个独立的只读数据区地址（如 `0x20000`），并在内存布局文档中明确划分。

---

### 🟡 3. 全局变量取地址 (`&global`) 无法区分标量与数组
**文件**: `native/src/compiler/WasmCodeGen.cpp` (L1593-L1626)

```cpp
// TODO: add globalTypes_ tracking.
EmitGlobalGet(idx); // 如果是标量全局变量，得到的是值，不是地址
```

**问题**: `EmitAddressOf` 中对全局变量取地址时，由于缺少 `globalTypes_` 映射，无法判断该全局变量是标量（global 存的是值）还是数组/struct（global 存的是基地址）。这会导致对全局标量变量的 `&` 操作产生错误结果。

**建议**: 在 `Generate()` 中建立 `globalTypes_` 映射表（`name → Type`），在 `EmitAddressOf` 中根据类型决定行为。

---

### 🟡 4. 堆内存分配只增不减，无重用
**文件**: `native/src/capi/cide_capi.cpp` (L367-L384)

`malloc` 实现只是线性递增 `heapOffset`，`free` 仅标记 `isFreed = true`，从不回收内存。一个简单的循环 `malloc`/`free` 几次就会耗尽 128KB WASM 内存。

**建议**: 实现最简单的 bump allocator + free list，或至少将 `free` 后的相邻空闲块合并重用。

---

### 🟡 5. 编译错误时，Warning 信息可能丢失
**文件**: `native/src/capi/cide_capi.cpp` (L251-L264)

虽然 warnings 是在 `typeCheckOk` 判断之前收集的，但如果前面阶段（Lexer/Parser）出错直接 `return -1`，后续 TypeChecker 的 warnings 不会被执行。此外，编译失败时前端通常只展示 errors，warnings 被忽略。

**建议**: 即使编译失败，也保留已收集的 warnings 在 `diagnostics` 中，并确保前端能读取。

---

### ~~🟡 6. `cide_step_next` 仍是 Stub，单步调试不可用~~ ✅ 已完成
**文件**: `native/src/capi/cide_capi.cpp` / `native/src/vm/CideVM.cpp`

~~`cide_step_next` 为 stub，直接返回 0。~~

**修复**: CideVM 已改为自定义 VM（废弃 wasm3）。实现基于 `StepEvent` 指令的单步控制：
- `CideVM` 新增 `stepEventHit_` 标志，`StepEvent` 处理时设置该标志
- `cide_step_next` 每次 `Step()` 后检测 `WasStepEventHit()`，命中后自动 `Pause()` 并返回
- 前端 `MainViewModel` 调用真实 `_compiler.StepNext()` 驱动 VM 执行

**验证**: `Phase3Step` 测试 5/5 通过，前端单步调试功能可用。

---

## 三、架构层面的改进点

### 1. 函数类型索引硬编码，限制参数数量
**文件**: `native/src/compiler/WasmCodeGen.cpp` (L552-L566)

当前根据参数数量（0/1/2）硬编码函数类型索引，超过 2 个参数的函数会生成错误的 WASM 类型签名。

**建议**: 在预注册阶段根据实际参数类型和返回值动态生成 `WasmFuncType` 并获取索引。

---

### 2. Source Map 精度不足
**文件**: `native/src/compiler/WasmCodeGen.cpp` (L624-L633)

当前 Source Map 只在注入 `__cide_step` 时记录偏移：

```cpp
uint32_t wasmOffset = static_cast<uint32_t>(ctx_->code.size());
sourceMap_.push_back({wasmOffset, stmt.loc});
```

这意味着 Source Map 只能映射到"语句级别"，无法映射到具体表达式或运行时 trap 的精确指令位置。

**建议**: 在 `GenExpr` 的关键节点（如 `EmitI32Load`、`EmitCall` 等）也插入 Source Map 记录，实现指令级映射。

---

### 3. 错误码体系未贯通
**文件**: `native/src/capi/cide_capi.cpp` (L220-283)

`CideDiagnostic` 结构体有 `errorCode` 字段，但 Lexer/Parser/TypeChecker 的错误对象中 `code` 字段没有系统定义（或始终为 0）。这导致前端无法根据错误码进行分级（L1/L2/L3）和 QuickFix 匹配。

**建议**: 
- 在 `Lexer.hpp`/`Parser.hpp`/`TypeChecker.hpp` 中定义统一的错误码枚举（如 `E1001_未声明变量`、`E2001_类型不匹配`）
- `cide_compile` 中填充真实的 `errorCode`

---

### 4. 局部变量默认初始化生成冗余代码
**文件**: `native/src/compiler/WasmCodeGen.cpp` (L722-L730)

```cpp
uint32_t temp = ReserveLocal(VT_I32);
EmitI32Const(0);
EmitLocalSet(temp);
EmitLocalGet(addrLocal);
EmitLocalGet(temp);
EmitI32Store();
```

可以优化为完全不需要 `temp`：
```cpp
EmitI32Const(0);
EmitLocalGet(addrLocal);
EmitI32Store();
```

---

### 5. `printf` 格式解析过于简单
**文件**: `native/src/capi/cide_capi.cpp` (L409-514)

当前只支持 `%d`，且参数数量硬编码为 0/1/2。不支持 `%s`、 `%c`、 `%%` 等。

**建议**: 在宿主函数中实现一个通用的 `__cide_printf`（可变参数），在 C 侧解析格式字符串并动态处理参数数量。

---

## 四、与后续 Phase 的衔接建议

| 后续需求 | 当前阻碍 | 建议行动 |
|:---|:---|:---|
| ~~Phase 3 单步调试~~ | ~~`cide_step_next` 为 stub~~ | ~~实现基于 `StepEvent` 的单步执行器~~ ✅ 已完成：CideVM `stepEventHit_` + `cide_step_next` + 前端真实单步驱动 |
| **Phase 3 Source Map 精确映射** | 只记录语句级偏移 | 在 `GenExpr` 的每个 trap 风险点（load/store/div/call）插入映射 |
| **Phase 3 中文错误分级** | `errorCode` 未填充 | 定义统一错误码枚举表，贯通 Lexer→Parser→TypeChecker→C API |
| ~~Phase 3 QuickFix~~ | ~~`fixSuggestion` 始终为空~~ | ~~在编译器各阶段根据错误码填充修复建议~~ ✅ 已完成：后端根据错误消息填充 `fixSuggestion`；前端显示修复提示并支持一键应用（自动补分号等） |
| ~~Phase 4 算法识别~~ | ~~无 AST 模式匹配框架~~ | ~~在 `TypeChecker` 和 `WasmCodeGen` 之间预留 `VisualizationInjector` 插槽~~ ✅ 已完成骨架：`AlgorithmMatcher` 类 + C API + 编译集成 |
| **Phase 4 内存可视化** | 指针追踪仅返回内存值 | 建立 `指针地址 → 目标地址` 映射表，在 `malloc`/`赋值` 时更新 |
| **Phase 5 Android 适配** | P/Invoke 已统一 | 需验证 `cide_native.so` 在 Android 上的加载和 `__cide_step` 的性能开销 |

---

## 五、优先级总结

| 优先级 | 问题 | 影响 |
|:---|:---|:---|
| **P0 - 立即修复** | 超时线程泄漏 (`detach`) | 系统稳定性 |
| **P0 - 立即修复** | 字符串地址与全局内存重叠风险 | 运行时数据损坏 |
| ~~P1 - 尽快修复~~ | ~~`cide_step_next` stub~~ | ~~Phase 3 核心功能阻塞~~ ✅ 已完成：CideVM StepEvent 单步机制 + 前端集成 |
| **P1 - 尽快修复** | 全局变量 `&` 取地址无法区分类型 | 语言特性正确性 |
| ~~P1 - 尽快修复~~ | ~~堆内存 `free` 不回收~~ | ~~长时间运行内存耗尽~~ ✅ 已修复 |
| ~~P2 - 架构优化~~ | ~~错误码体系统一~~ | ~~Phase 3 诊断分级~~ ✅ 已完成：E2005-E2008 结构化自动修复全部实现并通过测试 |
| **P2 - 架构优化** | Source Map 指令级精度 | Phase 3 错误定位 |
| **P2 - 架构优化** | 函数类型动态生成 | 支持多参数函数 |
| **P3 - 质量改进** | 局部变量初始化冗余代码 | 生成 WASM 体积 |
| ~~P3 - 质量改进~~ | ~~`printf` 通用化~~ | ~~标准库兼容性~~ ✅ 已修复（支持 `%d`/`%s`/`%c`/`%%`） |
| ~~P2 - 架构优化~~ | ~~QuickFix `fixSuggestion`~~ | ~~Phase 3 自动修复~~ ✅ 已修复：后端填充修复建议，前端支持一键应用 |
| ~~P4 - 扩展~~ | ~~算法模式识别框架~~ | ~~Phase 4 基础~~ ✅ 已完成骨架：`AlgorithmMatcher` + C API + 前端UI |

本文档一废弃框架改用自己实现vm
