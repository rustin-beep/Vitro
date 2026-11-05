# 核载体迁移设计单——153 码表实体化为 wasm 子集+扩展（语义冻结，只换载体）

> **as_of 2026-11-05（批 1a 勘误版——探针实证欠账三处修正〔§2.1 责任转移表 / §2.1 边界口径 / §2.2.1 发射规范〕+ §2.2 全量对账勘误 + §6 解锁清单补 V8 全托管叙事；实施批已启动：`moonbit/wasmenc` 骨架 + A 类 83 条全量往返绿，见 `tmp/batch_REHOST_1a_REPORT.md`）** · 设计批基底 = 分支 `batch-corpus-chibicc-port`（4820c92c）
> 措辞三档：**〔已验证〕**=本会话亲读代码/亲读仓内实测报告（行号在手）；**〔推断〕**=由已验证事实外推；**〔未覆盖〕**=显式留白。
> **状态：设计完成，待用户拍板。实施触发条件写死于 §9——不满足不启动。**
> 直接前置：`tmp/jit_survey/report.md`（本仓 `tmp/` 为 gitignore 会话工作区，不入库——CI 语境无此文件，数字结论已内联本单；2026-11-02，PoC 299–481× + §7.3 解释器兼容帧七原则——本设计单消费其全部实测结论，不重复实测）。

---

## 0. 命题与两条铁律（用户拍板，设计全程不漂移）

**命题**：把 bytecode 的 153 条私有码表（`moonbit/opcode/opcode.mbt:26-181`，编号 0..155 含空号 47–49）**实体化为「wasm 子集+扩展」载体**——semantics-preserving rehosting。语义不是设计变量，载体才是。

| 铁律 | 内容 | 设计落点 |
|---|---|---|
| **1. 语义冻结** | 153 opcodes 语义已由既有防线（三臂 digest / 全部修复锚 / verify 锚 / W4 对拍）冻结。验收判据 = **现有锚资产全绿 + digest 零漂移**，不发明新判据 | §3 每批的验收面全部引用现役闸（vm_diff / clang_direct / vitro_cli_smoke / STEP-INV / W4）；新产物只做**增量闸**（产物验证器），不动既有对拍面 |
| **2. V8 = 影子验证器，不是执行路径** | 引擎 = 唯一语义权威（单步 / 时间旅行 / 内存视图 / VisEvent 永在引擎侧）；V8 双跑对拍——先出结果（快路径）等待引擎确认（权威）；不一致 → 双结果展示 + 告知用户 + 上报后台（离线 clang 对拍定责）。分歧 = 检测功能，不是架构危机 | §4 全节；权威执行器=引擎内折叠执行器（§3.1），V8 无任何职权 |

**一句话架构**（§3 展开）：`codegen 语义发射函数族（唯一真相源）→ 发射 wasm 子集二进制（真 wasm，checked 形态含步锚+trap 检查）→ 三个消费者`——①引擎内**折叠执行器**（装载期把 wasm 字节按发射模板折叠回组操作，权威路径，三臂同源）；②**V8**（js/wasm 臂宿主与浏览器/CEF 壳，快路径影子）；③**wasmtime**（W4 第四臂现役资产，第二证人+未来多 runtime）。**一份载体，三个消费者；语义裁判只有一个。**

---

## 1. 历史判死复核表——归档方案 B 六条缺点逐条裁定

信息源：`docs/archive/WASM_BACKEND_FEASIBILITY_ANALYSIS.md`（归档文档，按本任务书指定作历史线索复核，不作行为依据）。**其方案 B 的语境是「用 Clang/LLVM 把用户 C 直接编成标准 wasm、废弃教学 VM」**——与本命题（自家 153 码表换编码载体、引擎权威不动）不是同一件事。复核结论：六条缺点在自家发射器语境下**五条翻案、一条形态转移**；但翻案不等于该做——是否做由 §9 触发条件裁决。

| # | 方案 B 缺点（归档原文口径） | 载体论下裁定 | 机制（翻案/维持的根据） |
|---|---|---|---|
| 1 | **丧失 VisEvent**（标准 wasm 无事件发射机制） | **翻案** | VisEvent 永在引擎侧（铁律 2）：`execute_debug` 的 vis 命中登记在权威执行器 `execute_*` 臂内原样保留（`moonbit/vm/exec_debug.mbt:21-110` 本会话亲读）；且 run 全速态 vis 事件**零消费方**已由 P0 落闸实证并短路（`moonbit/vm/exec_step.mbt:64-78,95-100`）——快路径（V8）根本不承担 VisEvent 义务。事件高频成本的实测方案见 §2.4 |
| 2 | **丧失中文诊断**（Clang 诊断英文、面向专家） | **翻案** | 诊断在前端（lexer/parser/typeck/diag 全族），编译期产物换编码载体不触碰；运行期 trap 文案（E3086 数组越界带符号名/长度，`exec_debug.mbt:69-110`）在引擎侧渲染——wasm 载体只发 `unreachable`+trap 码，文案由权威执行器回查**侧车符号表**（§2.3 扩展机制 T3） |
| 3 | **丧失受控子集**（标准 C 指针算术/UB 全暴露） | **翻案** | 受控子集由**前端**界定（C 子集 typeck + builtin 放行名全集 175），载体消费的是受控 bytecode 的换形——子集边界是编译器属性不是执行器属性。jit_survey §3.2 同结论〔已验证〕 |
| 4 | **编译器体积 50MB+**（打包 clang/LLVM wasm 版） | **翻案** | 不打包 clang：发射器 = 引擎内 MoonBit 代码（LEB128+段编码器，§7 估 ~1.5k 行），模块零外部依赖纪律不破 |
| 5 | **调试困难**（DWARF→wasm→SourceMap 多层映射） | **翻案** | 单步在引擎侧：**步锚组 = 步**（§2.4），`source_map` 侧车原样（`moonbit/bytecode/schema.mbt:87`），断点判定仍在 `StepEvent` 语义内（`exec_debug.mbt:37-44`）——调试协议零变化，不给 wasm 载体配 DWARF |
| 6 | **内存可视化**（wasm 线性内存单一数组、无区域划分） | **翻案** | R1 区域化地址方案**直落**线性内存：`MEM_SIZE=1MB / NULL_TRAP 0x1000 / GLOBAL_START 0x1000 / HEAP_START 0x5000 / GLOBAL_REGION_LIMIT 64KB / STACK_START=MEM_SIZE`（`moonbit/bytecode/memory.mbt:15-40` 亲读）即 wasm memory 的地址语义；regions/quarantine/UAF 元数据是引擎侧 `MemoryMap` 状态，不进载体（§5） |
| — | 方案 B 隐含前提「**废弃 CideVM**」 | **形态转移（仍成立的部分）** | 本命题不废弃执行器只换编码载体；但「引入第二载体」本身的新工程风险（发射↔折叠互逆一致性、V8 语义非确定面、host ABI 跨界开销）真实存在——进 §7.3 风险表，逐条给缓解机制 |

**复核纪律注**：上表未全盘翻案也未全盘维持——第 6 条的「区域划分」在 wasm 侧确实不存在（维持缺点的事实部分），但可视化协议本来就消费引擎侧 regions 元数据，故**结论**翻案。逐条给机制如上。

---

## 2. 载体映射：153 opcodes → wasm 指令直映表

### 2.1 wasm 子集边界（发射面 + 自研执行器语义边界清单）

**子集 = wasm MVP 核心 + saturating trunc 指令 +（期 2 评估）bulk memory**。零 GC 类型（不碰 WasmGC struct/array/ref——jit_survey §3.2 PoC 实证 MVP 足够〔已验证〕）。逐段清单：

| wasm 段 | 用/不用 | 用途 |
|---|---|---|
| magic+version | 用 | 载体头 |
| type（id 1） | 用 | 主函数 + host ABI 单一签名 |
| import（id 2） | 用 | **仅 1 个 import**：`env.vitro_host_call(route_id : i32, argv_ptr : i32) -> i64`（§2.3-H2，CallHost 110 路由的全部回接面） |
| function（id 3） | 用 | 单主函数（dispatch-loop 形态，§2.5） |
| table（id 4）/ elem（id 9） | **不用** | 基线形态无 `call_indirect`——CallPtr/CallVar 在软件栈模型下=pc 跳转（§2.5） |
| memory（id 5） | 用 | `{min:16, max:16}` = 恰 1MB 不增长——wasm 页越界 trap 与 vitro 上界检查**精确等价**（jit_survey 裂缝 2〔已验证〕） |
| global（id 6） | 用 | 步数计数器 `$steps`（checked 形态静态计数）+ 帧基址 `$fb`（spill 辅助） |
| export（id 7） | 用 | `main(start_ip : i32) -> i32`（任意块首进入——deopt/reenter 协议基础）+ `memory` + `steps()` 读取器 |
| start（id 8） | 不用 | — |
| code（id 10） | 用 | 指令主体 |
| data（id 11） | 用 | 全局初始化（`globals_init_32/64` + `string_data`，`schema.mbt:82-86`）——V8 实例化自动铺设；折叠执行器装载期同源铺设 |
| data count（id 12） | 不用 | 无 bulk memory |

**消费指令面（约 100 条 MVP 指令）**：控制流（`loop/block/br/br_if/br_table/if/else/return/call/end/unreachable/nop`）、参数（`drop/select`）、变量（`local.get/set/tee`、`global.get/set`）、内存（i32/i64/f32/f64 的 load/store 全宽度族——对齐立即数按载体实际访问宽度）、数值（i32/i64/f32/f64 四型算术/比较/转换 + `i32.wrap_i64`/`i64.extend_i32_s/u`/`f64.promote_f32`/`f32.demote_f64`/`i32.trunc_sat_f32_s` 等 saturating 族 + reinterpret 族）。

**自研执行器必须实现的 wasm 语义边界清单**（折叠执行器形态下，多数边界的责任从「解释期」转移到「发射期」——责任转移表）：

| wasm 语义边界（spec 定义） | 折叠执行器（权威路径）责任 | V8 路径责任 | 备注 |
|---|---|---|---|
| 整数四则回绕（add/sub/mul） | **发射期**：有符号族必须发检查序列（§2.3-E1），折叠后=现役 trap 语义 | 检查序列内的 `unreachable` | U 系族回绕语义两侧同构〔已验证，jit_survey 裂缝 1〕 |
| `i32.div_s/rem_s` trap（除零、INT_MIN/-1） | **直映即同构**：现役 `Div/Mod` 同 trap 面（`exec_arith.mbt` 头注「INT_MIN / -1 先拦截」亲读） | wasm 原生 trap | 两侧 trap 码归一（§4.3） |
| 移位量取模（wasm 按 mod 32/64） | **发射期**：Shl/Shr/LShr/Q 族先发域检查（现役 0~31 越界 trap，`exec_arith.mbt:271-290` 亲读）再发移位 | 同上 | 检查后移位量必在域内，取模语义不可达 |
| 浮点 NaN payload 非确定性（nan:canonical/arithmetic） | **发射期回避**：NaN 只经 `store/load` 位模式传递；运算产生的 NaN 若被后续 printf/位观察消费，printf 走 CallHost 回**引擎 host**——文本化单源 | V8 侧 NaN 位模式可能与权威不同 | §7.3-R4 残余风险登记（极窄面：NaN 参与位级观察） |
| trunc 越界 trap（非 sat 转换） | **不用非 sat trunc**：CastF2I/CastD2I 是饱和语义（`exec_float.mbt:7,98-100,170-172` 亲读）→ `i32.trunc_sat_*` 精确直映 | trunc_sat 是标准指令（nontrapping conversions 提案，已并入 wasm 2.0 基线） | 直映成立，无检查序列 |
| 线性内存 OOB trap | 上界白送（16 页恰 1MB）；NULL 区（`<0x1000`）显式检查序列 | 同 | UAF/quarantine 不在载体（引擎侧 MemoryMap，host 层）。**边界口径（探针 1 实测）**：wasm 验证器**不查** load/store 静态 offset 与 memory 声明的大小关系——静态 offset 任意 u32 即合法，越界属**运行期** effective address trap（V8 实测 `memory access out of bounds`）；装载期 wabt 验证拦结构/类型/对齐错，**拦不住语义级地址错** |
| 验证（类型检查/栈平衡） | **装载期：按侧车组表的模板核对**（探针 2 实证修正：盲折叠在等价双发歧义对上必错其一且 re-emit 自校验不能检出——`[PushConst(-1);BitXor]` 与 `[BitNot]` 字节恒等 `41 7f 73`，**组表侧车是折叠完备性的必要条件而非可选优化**；组边界 + 逐组 op/operand 核对，非自家发射产物 fail loud 拒载）；CI 另加 wabt `wasm-validate` 外部闸（§6-3） | V8 编译期自带 | 双保险 |
| 实例化语义（data 段铺设/globals init 求值） | 装载期从侧车同源铺设（与 data 段字节一致） | 引擎实例化 | — |

### 2.2 直映表（153 条 → 五类；发射面 = 148 条，C 前端零发射 5 条）

编号契约与分段依据：`opcode.mbt:2-25`。下表**五分类**覆盖 153 条全表（分组引 dispatch 实装族 `exec_step.mbt:144-297` 亲读对齐）：

**A 类：精确直映（1:1 wasm 指令，零检查序列）——83 条**

| 族 | opcode（数量） | wasm 直映 |
|---|---|---|
| U 系无符号对偶段 | `ULt/ULe/UGt/UGe/UDiv/UMod/LShr/USub/UAdd/UMul`（10）+ Q 对偶 `CastU2Q/UDivQ/UModQ/UNegQ/ULtQ/ULeQ/UGtQ/UGeQ`（8） | `i32.lt_u / i32.div_u / i32.shr_u / i32.add…`（回绕/无符号=精确同构）；Q 族 i64 同形 |
| 除法/取模有符号 | `Div/Mod/DivQ/ModQ`（4） | `i32.div_s / i32.rem_s / i64.div_s / i64.rem_s`——trap 面（除零+INT_MIN/-1）**精确同构**（§2.1 表） |
| 位运算 | `BitAnd/BitOr/BitXor/BitNot/BitAndQ/BitOrQ/BitXorQ/BitNotQ`（8） | `and/or/xor`；BitNot=`i32.const -1; xor`（2 条序列，语义直映） |
| 整型比较 | `Eq/Ne/Lt/Le/Gt/Ge/EqQ/NeQ/LtQ/LeQ/GtQ/GeQ`（12） | `i32.eq / i32.lt_s` 族 |
| 逻辑 | `And/Or/Not`（3） | `i32.and/or`（操作数已是 0/1 域）；Not=`i32.eqz` |
| f32 族算术/比较 | `AddF/SubF/MulF/DivF/NegF/EqF/NeF/LtF/LeF/GtF/GeF`（11） | `f32.add…f32.ge` |
| f64 族算术/比较 | `AddD/SubD/MulD/DivD/NegD/EqD/NeD/LtD/LeD/GtD/GeD`（11） | `f64.add…f64.ge` |
| Q 算术（回绕态） | `AddQ/SubQ/MulQ`（3）——注意：**归 E1**（见下，现役为 i64 域检查 trap？亲读核实：`AddQ` 走共享算术核 I64 域带范围检查 → 归 E 类。此处修正为归 E） | — |
| 纯转换直映 | `CastF2D/CastD2F/CastI2F/CastI2D/CastI2Q/CastQ2I/CastQ2D/CastD2Q/CastU2D/CastU2F/CastUQ2D/CastUQ2F`（12）+ 饱和 `CastF2I/CastD2I`（2） | `f64.promote_f32 / f32.demote_f64 / f32.convert_i32_s / i64.extend_i32_s / f64.convert_i64_s / i64.trunc_f64_s / i64.reinterpret_f64 / f64.convert_i32_u…`；饱和对→`i32.trunc_sat_f32_s / i32.trunc_sat_f64_s` |
| 栈操作 | `Pop/Dup/Swap/Nop`（4） | `drop`；Dup/Swap=值栈局部换序（`local.tee` 辅助 2–3 条序列，栈效果直映） |
| 内存读（越权检查=上界白送） | `LoadMemByte/LoadMemUByte/LoadMem/LoadMemD/LoadMemQ`（5） | `i32.load8_s / i32.load8_u / i32.load / i64.load / f64.load`——上界由 16 页 memory 精确等价；NULL 区检查见 E4 |
| 常量 | `PushConst/PushConstF/PushConstD/PushConstQ`（4） | `i32.const / f32.const / f64.const / i64.const` |
| 其余 | `RetVoid`（1，软件栈形态下=清帧跳回，见 C 类边界） | — |

（A 类精确计数随 E 类边界微调，下两行修正归并：`AddQ/SubQ/MulQ/NegQ` 四条有符号 i64 溢出检查 → E 类；`Ret/RetVoid/Call/CallPtr/CallVar` → C 类。**A 类净数 82，E 类 +4，C 类 6**。）

**B 类：组合展开（多条 wasm 指令序列，发射模板唯一）——34 条**

| 族 | opcode | 展开形态（模板要点） |
|---|---|---|
| 有符号溢出检查算术 | `Add/Sub/Mul/Neg/AddQ/SubQ/MulQ/NegQ`（8） | i64 中间值法：`i64.extend_i32_s ×2 → i64.add → 越界比较（与 0x80000000/0x7FFFFFFF）→ 越界则 br 到本组 trap 出口（unreachable+trap 码）；未越界 i32.wrap_i64`。PoC 实测保真代价 ~1.5×、收益仍 318–385×〔已验证，jit_survey §4.2〕 |
| 移位域检查 | `Shl/Shr/LShr/ShlQ/ShrQ/LShrQ`（6） | `local.tee $sh；i32.const 0；i32.ge_s …（域 0..31/63 比较）→ 越界 br trap 出口；域内 i32.shl/shr_s/shr_u` |
| 访存 NULL 区+受检 | `StoreMem/StoreMemByte/LoadMem*（补 NULL 检查）`（4） | 上界白送（A 类）；NULL 区= `addr < 0x1000` 显式 2–3 条比较+br trap 出口（jit_survey 裂缝 2：NULL 区需显式、实测 318× 含此成本） |
| 全局变量 | `LoadGlobal/StoreGlobal/LoadGlobalD/StoreGlobalD/LoadGlobalQ/StoreGlobalQ/LoadGlobalByte/LoadGlobalUByte/StoreGlobalByte`（9） | 编译期地址已知：`i32.const <绝对地址> → i32.load/store`（组合直映——语义等价现役「operand→global_syms 地址查表再访存」） |
| 位拆分 | `SplitD/SplitQ`（2） | `i64.reinterpret_f64（SplitD 先 reinterpret）→ local.tee → i64.const 32 → i64.shr_u → i32.wrap_i64 ×2`（低/高各符号扩展压栈，`exec_memory.mbt:76-84` 亲读同构） |
| 块内存原语 | `Memcpy/Memset`（2） | 组内小循环（`loop + load/store + i32.add + br_if`）——**期 2 评估换 `memory.copy/fill` 前必须先核实重叠语义**（wasm memory.copy 定义为 memmove 语义；现役 Memcpy 语义亲读未及此批次——实施批补锚，§8-O3） |
| 栈分配 | `StackAlloc`（1） | `mem_stack_top` 软件栈指针：负数/溢出检查（`exec_memory.mbt:85-94` 亲读 trap 面）+ 指针下移 + 地址压栈 |
| 步进/预算锚 | `StepEvent`（1） | 见 §2.4 步锚——`global.get $steps; i32.const 1; i32.add; global.set $steps` + 块首预算安全点；`current_line/断点/vis` 语义留权威侧（StepEvent 组在权威执行器内仍走 `execute_debug`） |
| 入口杂项 | `GetFrameBase/PushArgc/PushArgv`（3） | `global.get $fb`（或 `local.get`）；argc/argv=编译期常量 `i32.const`（argv 区已由 data/侧车铺设，`bytecode/memory.mbt:57-69` 亲读） |
| 局部变量 | `LoadLocal/StoreLocal/LoadLocalD/StoreLocalD/LoadLocalQ/StoreLocalQ`（6） | **基线不提升**：locals 在内存（`locals_base+offset` 内存编址，`types.mbt:57` CallFrame.locals_base 亲读）→ `global.get $fb; i32.const <off>; i32.add; i32.load/store`。取址分析提升（jit_survey 裂缝 3 的 PoC 已实现）留期 3 优化——**基线全留内存=帧布局不变=语义冻结最强形态** |

**C 类：控制流（dispatch-loop 结构化映射）——6 条**

`Jump/JumpIfZero/JumpIfNotZero`：基块划分后 `br`（块内直跳）/`br_table`（pc 分发）；`Call/CallPtr/CallVar`：**软件调用栈**（压帧=内存写+`$fb` 更新+块首 pc 赋值，与现役 `do_call` 四重栈溢出防护同构——`exec_control.mbt:72-73` call_depth_limit 亲读）；`Ret/RetVoid`：清帧+pc 回跳+`$fb` 恢复。**不使用 wasm call 做用户函数调用**（理由 §2.5）。

**D 类：import 宿主（H2 单一 ABI）——1 条**

`CallHost`（110 路由）：弹参→参数写入 1MB 内存约定区→`call env.vitro_host_call(route_id, argv_ptr)`→返回值压栈。宿主回调（qsort/bsearch 经 `call_user_function` 反调用户代码，`exec_control.mbt:276-298` 哨兵亲读）：host ABI 返回「回调请求」描述 → 快路径**该函数禁译**（回调函数走权威）或经块首重入协议续跑（§2.5）——首版禁译白名单覆盖（jit_survey 裂缝 6 同款〔推断〕）。

**E 类：零发射/保留——5 条**

`TryBegin/TryEnd/Throw`（44–46，reserved-for-csharp，`opcode.mbt:9-11`）+ `Strlen/TrapBoundsVla`（126/129，零发射死码，`opcode.mbt:21-22`）。发射器穷尽 match 显式拒载（编译期红）——码表完整保留于 `vitro/engine/opcode`（产物对拍依赖编号冻结，不删）。

**TrapBounds（37）**：观测指令，B 类展开（索引域检查：`index<0 || index>=size` → br trap 出口；operand 编码进组元数据供权威侧渲染 E3086 文案，`exec_debug.mbt:69-110` 亲读）。

**全量对账勘误（批 1a，2026-11-05——逐条清单已实体化于 `moonbit/wasmenc/templates.mbt` 153 臂穷尽表，`tmp/batch_REHOST_1a_REPORT.md` 为账目报告）**：上文五分类计数（A 82 / B 36 / C 6 / D 1 / E 5 = 130「其余 23 条为 A 类细分」）**不成立**——「23 条细分」是样例级罗列的凑数话术而非逐条账。对账后四态口径（发射器实测）：**A 完全一致 83 / B 组合可逆 50 / C 歧义需侧车 13 / D 不可映射 7 = 153 闭合**。归类修正五笔：① `AddQ/SubQ/MulQ` 系 Q 族**回绕不 trap**（`exec_float.mbt:216` 亲读——本单行 92「归 E 类溢出检查」系误记；仅 `NegQ` 有 LLONG_MIN 教学 trap 归 B）；② `And/Or` 为 codegen 短路结构下的**不可达占位零发射**（`binary.mbt:380-382` 亲读）归 D——本单漏计（E 类 5→7）；③ `PushArgc/PushArgv` 与 `PushConst` 发射字节同形（编译期常量直映）归 C 靠侧车消歧——本单误归 B；④ `BitNot/BitNotQ` 歧义实锤（探针 2）归 C——本单误归 A；⑤ C 类计数 6 漏 `CallVar`（实为 8 条控制流 + CallHost 单列 D 类 = 四态 C 13 含二者）。另 `TruncUByte` 初归 A 误——wasm 无 `i32.extend8_u`（sign-extension-ops 仅 `_s` 族，wabt parseWat 编译实证）移 B（`i32.const 0xFF; i32.and` 规范化形态）。

### 2.2.1 发射规范两条红线（批 1a 实体化实证，探针报告 §5 吸收）

- **栈序不变量 API**：访存类组「先弹值再弹地址」= wasm 栈 `[addr, value]`（探针会话 4 次执行错误全为此序拼反——**wasm 验证器不拦**，静默错值/死循环）。发射器必须封装取数序（`wasmenc` 的 `TemplateSpec.pops/pushes` 栈效应声明 + soft-stack 双实现对拍单测锁定——mini wasm 栈机执行发射序列 vs Vitro 位模式参照逐位一致，不能只测字节往返）。
- **组前计步**：控制流组以 `br` 结束，步进序列发在组后 = br 后死代码永不计步（探针 3 实测漏计形态）——**步锚一律组前发射**，对普通/控制流组语义一致。
- **码位外部证人**：发射/折叠共享指令枚举的形态下，码位写错往返自洽仍绿（批 1a 活案例：按记忆写的 convert 族五连 + `i32.extend8_s` 码位错，往返 16/16 绿而 wabt 一验即红）——仓内 spec 码位锚（硬编码断言）+ 开发期 wabt 编译实证双层锁定，批 1c wabt 闸转 CI 常态。

### 2.3 扩展机制选型（逐扩展列选型）

| 扩展面 | 选型 | 理由（对比逐项） |
|---|---|---|
| **E1 溢出/除零/移位域 trap** | **组合展开**（wasm 指令序列内联检查） | vs import 宿主：每算术指令一次跨界调用 = 快路径死因（W4 §6b 实证 host-call 51ns×每步 = 7–522× 慢〔已验证〕）；组合展开保真代价实测 1.5×、收益 318×〔已验证〕 |
| **E2 受检访存（NULL 区/UAF）** | 混合：上界=memory 精确等价（零成本）+NULL 区=组合展开+**UAF/quarantine=引擎侧**（malloc/free 本就是 CallHost，堆区访存的 UAF 检查在 host 层回引擎） | jit_survey 裂缝 2 同款分层；堆访存占比 ~1%（#176 实测） |
| **E3 控制流任意跳转** | 组合展开（基块划分+br/br_table dispatch-loop） | PoC：dispatch-loop 299× 已达结构化 78%，免 relooper〔已验证〕；结构化收 +20% 留期 3 |
| **E4 CallHost 110 路由** | **import 宿主（H2 单一 ABI）** | vs 每函数 110 import：import 面大、V8 侧供给 110 个 JS 桩；H2 路由表单源=`bytecode/route.mbt` CallRoute（面不增）；跨界一次/调用，host 占比 ~1% |
| **E5 步数计数/预算** | 组合展开（global $steps 静态计数+块首安全点） | PoC steps 逐位一致〔已验证〕；预算 trap overshoot ≤1 块——**权威确认路径消化**（§4.2：快路径结果标待确认，预算边界由权威终裁） |
| **T1 断点/Paused** | 不进载体（权威侧 StepEvent 语义） | 铁律 2：单步/断点永在引擎侧 |
| **T2 WaitingInput（ip 回退重执行，`exec_control.mbt:254-266` 亲读）** | **禁译白名单**：含 scanf 族的函数整函数走权威 | jit_survey §7.3 原则 7 同款；asyncify/JSPI 整模块变换否决（复杂度不成比例） |
| **T3 trap 文案（E 码/符号名）** | 侧车元数据：载体只发 `unreachable`+trap 码（global 或内存约定字）；权威侧组号→operand→symbols 回查渲染 | 文案单源留在引擎（E3086 等模板不动） |

**VisEvent 高频成本实测方案**（任务书点名）：基线**不进载体**（run 态零消费方已实证，`exec_step.mbt:95-100`）。若未来产品需要「快路径过程回放」（长跑算法动画加速），实测方案=**块粒度 vis 锚 import**（`env.vitro_vis(line, extra0, extra1)` 仅在含 vis 登记行的基块首插入；预期量级：vis 行密度典型 ≤1/10 块，跨界开销参照 W4 host-call 51ns/次——推断 <5% 长跑耗时）。启用条件与实测脚本列入 §6-6 期 3，**本设计批不实测**（纯设计纪律）。

### 2.4 「步」的定义迁移：IR 结构步 → 显式步锚（语义冻结的核心机制）

现役「步」= 一条 `Instruction`（`exec_step.mbt:32` step_count 自增亲读）。换载体后 wasm 指令粒度更细，**步语义必须显式化**：

- **发射期**：每个 opcode 组（对应该组 wasm 指令序列）恒计 1 步——组尾发射步进序列（E5）；`steps_executed` 由 `$steps` 静态计数**精确还原**（PoC 5,761,029 逐位一致〔已验证〕）。
- **权威执行器**：组=原子执行单元（`dispatch(gip)` 一次一组）——`StepResult` 五态（`types.mbt:46-53` 亲读）、帧流 `step_index` 严格 +1（STEP-INV INV3a 判据）、快照间隔 `SNAPSHOT_INTERVAL`（`exec_step.mbt:45-57`）全部按组保持——**对外观测口径零变化**。
- **time_travel**：`VMSnapshot`/CheckpointManager 快照字段含 `ip → gip`（组索引）换名不换义；seek/回放按组重放（确定性不变量原样）。

### 2.5 载体执行模型：单函数 dispatch-loop + 软件栈（与现役 VM 同构）

**选型：全部用户代码编为单个 wasm 函数，`loop + br_table(pc)` 分发；调用栈软件化（1MB 内存 + global `$fb` 帧基址 + 引擎侧权威执行器的 CallFrame 数组）。**

- vs **函数化（用户函数=wasm 函数，Call→wasm call）**：wasm 栈与软件栈双栈记账才能保 call_depth_limit/帧元数据语义；深递归撞 wasm 栈预算（W4 §4.1：V8 ~1MB 栈 6000 层临界〔已验证〕——新增栈溢出分叉面）；块首任意进入（deopt/reenter 协议）在函数化形态下不可行（jit_survey §7.3 原则 2）。dispatch-loop 三缺点全免，代价是放弃 wasm 内联优化（299× vs 385×，差 22%——量级已足）。
- 与现役同构性：现役 VM 本就是软件调用栈 + 1MB 线性内存帧布局——**执行模型不换，只换编码**。这是「只换载体」的最强保证，也是 digest 零漂移的机制根基。

---

## 3. 语义等价迁移策略：分批迁移序

### 3.1 总架构（终态）

```
                    codegen 语义发射函数族（唯一真相源，L6）
                    │  emit_wasm(op, operand, loc) → wasm 字节序列（checked 形态）
                    ▼
        ┌─────────────────────────────────────────────┐
        │  载体：wasm 子集二进制（真 wasm，过验证器）        │
        │  + 侧车：组表（组号→op/operand/loc）· symbols/   │
        │    source_map/func_table/…（CompileOutput 12    │
        │    字段原样——仅 code 字段换编码，schema.mbt:80-97）│
        └──────────┬──────────────┬──────────────┬─────┘
                   │ 装载期折叠      │ instantiate  │ 装载（wasmtime）
                   ▼              ▼（V8 快路径）    ▼
        ┌───────────────┐  ┌─────────────┐  ┌─────────────┐
        │ 权威执行器（引擎）│  │ V8 影子验证器  │  │ wasmtime     │
        │ 装载：wasm 字节按 │  │ web=demo 浏览器│  │ （W4 第四臂   │
        │ 发射模板折叠回组操 │  │ 桌面=CEF 内 V8 │  │  现役资产）    │
        │ 作→execute_* 现役 │  │ 先出结果→待权威 │  │ 第二证人      │
        │ 函数族（单步/时间  │  │ 确认（铁律 2）  │  │              │
        │ 旅行/观测/trap 全保)│  └─────────────┘  └─────────────┘
        └───────────────┘
     三臂同形：js/wasm/native 全部经权威执行器（折叠器是 MoonBit 代码，三臂同源）
```

**折叠执行器**（关键设计）：装载期把每组 wasm 字节序列按**发射模板库**模式匹配折叠回组操作（组操作=现役 `execute_*` 函数族的调用——VM 的值栈/调用栈/内存/观测/trap 体系**原样复用**，只换「取指分发」层：`code[ip]` → `groups[gip]`）。发射↔折叠互为逆函数、同一语义表驱动、两侧穷尽 match（编码纪律 1——opcode 增删两侧同红）；**装载期模板不匹配即 fail loud 拒载**（非自家发射产物不可执行）——运行期零分叉，双实现税从「人肉记两处」降为「编译器+装载期强制」（jit_survey §7.3 原则 4 升格为装载期闸）。

### 3.2 分批迁移序（每批锚资产验收面 + 回退点）

| 批 | 内容 | 验收面（**全部引用现役锚，不发明新判据**） | 回退点 |
|---|---|---|---|
| **批 0** | 先决确认：#176 P0 观测落闸已落（`exec_step.mbt:64-78` 亲证✓）——**无动作** | — | — |
| **批 1** | wasm 二进制编码器（LEB128+段，`vitro/engine/wasmenc` 新叶包 L0/L6 级）+ `emit_wasm` 发射器（codegen 侧新增发射目标；**legacy 153 code 字段照发**——对拍面零扰动） | 新增产物闸：①全语料（corpus 980 .c 亲数）发射成功率 100%（不可译函数进禁译表须逐条登记）；②wabt `wasm-validate` CI 闸（产物过标准验证器）；③发射器↔模板库穷尽 match 编译红锚。既有闸（codegen diff A 级 14 键/vm_diff 等）**零扰动验收** | 产物纯新增，无回退需求（flag 关闭即无 wasm 产物） |
| **批 2** | 折叠执行器 + **run 态切换**（VM run 路径装载 wasm 载体折叠执行；step 态仍走 legacy） | ①`vm_diff` 四语料全量 digest **零漂移**；②`clang_direct` 全绿；③`vitro_cli_smoke` 三臂对拍；④`moon test` 裸+native 全量；⑤moonbit 全 wbtest golden（protocol golden 锁栈内容） | feature flag：装载失败自动回退 legacy code 执行（过渡期 code 字段双发） |
| **批 3** | **step 态切换 + time_travel/step 采集适配**（单步=组、断点经组表 loc、VMSnapshot ip→gip、StepPayload/帧流发射零变化） | ①STEP-INV 全量（夜间档 995 语料帧流不变量——INV3a step_index 严格 +1 是本批最强锚）；②step golden + time_travel 全量测试；③`wasmtime_arm` deep-nomem 对拍零 DIFF | 同批 2 flag（step 态独立开关） |
| **批 4** | **载体收口**：code 字段停发（CompileOutput schema 变更 → minor 版本）、legacy 取指层退役（`execute_*` 函数族**保留**——组操作仍消费）、`vitro/engine/opcode` 降级为发射器内部表（编号冻结不删） | 全防线回归 + 发版彩排（vitro-release-playbook）；`facts --strict`；`backend_triage` 三面 | 不可逆批——**须 0.11.0 发版窗口**，且批 2/3 各跑满一个发版周期无 digest 漂移后才可启动 |
| **批 5** | V8 影子执行器（§4：demo/桌面嵌入 + 快路径-确认协议 + 分歧上报） | 新增对拍闸：全语料 V8 vs 权威结果级 digest 一致率 ≥ 现有 arm_divergence 基线（不一致=缺陷，进 `arm_divergence` 最高 severity 桶——纪律 14 连坐） | 影子纯增量（不装=无快路径，权威照常） |
| **批 6** | 解锁功能逐项（§6 分期） | 逐项独立验收 | 逐项独立可停 |

### 3.3 迁移期新旧载体并存对拍形态（批 1–4 期间）

- **双发**：CompileOutput 同时携带 legacy `code` 与 `wasm 载体+组表`（产物体积 +wasm 段 ~KB 级——PoC 444–936B/程序〔已验证〕，九百语料合计 <1MB）。
- **对拍闸**（CI 新增，批 2 起）：同一语料 legacy 解释 vs wasm 折叠执行**双跑 digest 逐位对拍**（stdout 字节+rc+steps_executed）——这就是「迁移期新旧载体并存的对拍形态」，批 4 后随 legacy 退役切换为「权威 vs V8 影子」。
- **锚资产口径不变**：vm_diff/clang_direct/e2e 的 digest 键与值域不动——「零漂移」即指这些闸的既有 golden 逐位不变。

---

## 4. V8 影子执行器设计

### 4.1 嵌入形态

| 环境 | 形态 | 依据 |
|---|---|---|
| **web** | demo 既有浏览器 V8（Worker 内第二个 `WebAssembly.Instance`——MVP 模块，`compileStreaming` 装载；CallHost 经 H2 import 由 JS 胶水转发引擎 gateway `invoke`） | demo `js/gw.ts` 已有 js-string 装载先例〔已验证〕；MVP 模块不需要 js-string（零字符串 import——H2 数字 ABI） |
| **桌面** | **推荐 CEF 形态**（`desktop/` Proton 壳，CEF 内 V8 15.0〔已验证，P_proton 报告 CDP 实测〕直接 `new WebAssembly.Instance`）；**B 计划纯 C 壳（Win32/GTK）= 无快路径降级**（权威执行照常——CORE_LANG 报告：B 壳卖点=零 VM 3.66MB〔已验证〕，嵌 V8 破卖点，不为影子执行器引入）；Node 侧车进程=第三选项（进程外 V8，跨进程 H2 转发——**未覆盖**，仅当 CEF 线受阻再评） | CORE_LANG/P_proton 两报告实测背书 |
| **CI** | node 即 V8（现役 `wasmtime_arm/host_node.mts` 跑器形态直接复用） | W4 资产 |

### 4.2 快路径-确认协议

- **触发**：run 态且步数预算 ≥ 阈值（建议 10 万步——冷启动税 14µs 级〔已验证，jit_survey 摘要 D〕，短跑权威反而快；阈值实施批实测校准）。step 态**永不**走快路径（铁律 2）。
- **协议**：`V8 执行 → 出终态(stdout 增量+rc+steps) → UI 先展示【结果待验证】角标 → 权威执行器后台确认 → 一致则摘标，不一致进 4.3`。权威执行不因快路径存在而省略——**双跑是协议本体**（影子验证器语义）。
- **UI 语义拍板项**（开放问题 O1）：默认推荐「先展示+待确认角标」；备选「权威出结果才展示」（纯教学短程序两者无差——阈值以下无快路径）。
- **预算边界**：快路径 overshoot ≤1 块（E5）——最终权威 steps 为准；快路径 stdout 与权威在预算 trap 边界可能差一个块的输出（jit_survey 接缝 3）——确认协议以权威覆写展示。

### 4.3 分歧处理协议

- **UI**：双结果并排展示（权威结果标注「引擎确认值」、V8 结果标注「快速通道」）+ 用户可见文案「执行通道出现分歧，已上报，引擎结果为准」。
- **上报字段**（后台）：`session_id / 语料指纹(源码 sha) / 两侧终态 digest / 首个分歧观测点(块号/组号) / steps 双值 / 引擎版本 / 载体版本(发射器指纹) / runtime 版本(V8|wasmtime)`。
- **后台定责**：离线 **clang 对拍**（vitro-realcode-diff-workflow 既有流程）三方定责——引擎错→引擎缺陷批；载体错（发射/折叠）→载体批；V8 对 wasm 语义实现差异→登记豁免或子集收窄。**分歧=检测功能**（铁律 2）：每次分歧都是防线资产，不panic不回滚架构。

### 4.4 对拍粒度

**推荐：结果级 + 关键观测点；帧级（V8 出帧）不做。**

- 结果级：stdout 字节流 + 返回码 + steps_executed（PoC 三锚〔已验证〕）——run 态全部可观测面。
- 关键观测点：host 调用边界（H2 每次回接记录 route_id+args 摘要——对拍面扩展锚，实施批评估是否默认开）。
- 帧级否决理由：帧/VisEvent=step 态=引擎职权（铁律 2）；V8 出帧需要全量观测序列化（每步 import 回调）——快路径死因（W4 §6b 同构论证〔已验证〕）。过程级需求走 §2.3 块粒度 vis 锚实测方案。

---

## 5. 内存布局：区域化地址 → 线性内存 + memory.dump 帧映射 + 可视化重建协议

- **直落**：R1 区域化地址方案（NULL 陷阱区 4KB / 全局区 / argv 区 / 堆区（含 quarantine 256KB 预算）/ 栈区自顶向下——`bytecode/memory.mbt:15-91` + `memory/layout.mbt:20-43` 亲读）**原封不动**落 wasm linear memory（16 页恰 1MB，min=max 不增长）。地址即偏移，零重映射——`compute_heap_base` 等布局函数单源不动。
- **上界白送 / 显式补齐**：wasm OOB trap=内存上界（等价）；NULL 区显式检查序列（B 类 E4）；**堆语义（malloc/free/quarantine/UAF/FreedLogs）全在引擎侧**——host 层（H2 回接）不变，`MemoryMap` 权威不动。
- **memory.dump 帧映射**：gateway `memory.dump`（1MB 映像 base64）从引擎 `Memory` 载体导出——权威路径不变；**新增（批 5，可选）**：V8 侧 `memory.buffer` 快照导出作对拍观测点（两载体内存一致性锚——「同一份 1MB」的机检形态）。
- **可视化重建协议**：区域元数据（regions/quarantine/free_list）由引擎 `MemoryMap` 随帧下发（现行协议面），前端按区域着色重建——**协议零变化**；wasm 载体不携带区域元数据（data 段只有初始数据），消解归档缺点 6 的「单一数组无区域」问题（区域是引擎态不是载体态）。
- **脏页位图**：权威侧随 `Memory` 载体原样；V8 路径不标脏页（run 态零消费方，P0 同款论证）。

---

## 6. 解锁功能清单与分期（每项启用条件 + 依赖关系）

| # | 功能 | 启用条件 | 依赖 | 分期 |
|---|---|---|---|---|
| 1 | **实时对拍+分歧上报**（V8 影子全量接入 UI） | 批 5 完成；阈值实测校准 | 批 1+2+5 | 期 1 尾 |
| 2 | **学生作品导出真 wasm**（编译产物=可独立运行的 wasm 文件+mini host 胶水〔printf→console 等 H2 桩〕） | 批 1（发射器）+导出桩（~200 行 JS）；禁译面内程序（含 qsort/scanf 的暂不导出或导出降级说明） | 批 1 | 期 2 |
| 3 | **标准 wasm 工具链接入**（CI wabt `wasm-validate`/`wasm-objdump` 产物闸；产物可被任意标准 runtime 加载验证） | 批 1 | 批 1 | 期 1（随批 1 落） |
| 4 | **多 runtime 覆盖**（V8/wasmtime/权威三消费者同载体；wasmtime 侧=W4 跑器扩 profile 消费用户载体） | 批 1+批 5 | W4 现役资产 | 期 2 |
| 5 | **防线升维**（W4 对拍对象从「gateway 协议层」扩到「用户载体层」；STEP-INV 不变〔帧流语义零变化〕；arm_divergence 增「载体×runtime」维） | 批 3 后（载体=权威） | W4+STEP-INV | 期 2 |
| 6 | **性能逃生舱**（长跑 300×：真实卡顿场景兜底；vis 块锚实测〔§2.3〕随此项评估） | 批 5；§9 触发条件中的「性能卡顿实证」即此项入口 | 批 1+2+5 | 期 1–2 渐进 |
| 7 | **V8 全托管形态**（叙事补，批 1a 新增——非新工程而是既有解锁项的合流叙事）：用户程序（wasm 载体）与引擎（wasm-gc 产物）**同跑 V8**——浏览器/CEF 壳内不再有第二运行时；前端（lexer/parser/typeck/codegen，js 臂）改动**实时生效**无需重发引擎（解释型本质 + 除冻结核心外整体可变）；教学叙事补全：**学生编译产物 = 真 wasm 文件**（`i32.const`/`i32.add` 是 wasm 规范字节而非私有编码——「你写的人生第一个编译器，产物是浏览器原生可执行的文件」，与 §6-2 导出功能同一份载体） | 批 1（载体=真 wasm）+ 批 5（V8 接入） | 同 2 | 期 2（随导出/影子合流） |

依赖链：`批1 发射器 → {2 导出, 3 工具链闸, 4 多runtime(半)} → 批2/3 载体权威化 → {5 升维} → 批5 影子 → {1 实时对拍, 6 性能}`。

---

## 7. 工程账

### 7.1 MoonBit 侧 wasm 二进制工具链缺口：自写 LEB128+段编码器（推荐）vs 跨界 wasm-tools

| 项 | 自写编码器（推荐） | wasm-tools（Rust 库跨界） |
|---|---|---|
| 依赖纪律 | ✅ 模块零外部依赖（mooncakes 纪律不破；三臂同源——编码器是 MoonBit 代码 js/wasm/native 全可跑） | ❌ 引 Rust 工具链进构建/发行链；native 产物分发需携带或外调——破坏零依赖分发（2.37MB 卖点） |
| 工程量 | LEB128（u/s 两种 ~60 行）+ 段框架 ~300 行 + 指令编码 ~400 行 ≈ **~800 行**（PoC `wasm_poc.mjs` 手拼 emitter 有 JS 先例〔已验证〕，语义直译 MoonBit） | 绑定+胶水+版本锁定（binaryen/wasm-tools 跟随成本） |
| 用武之地 | 引擎内发射（生产路径） | **CI 侧外部验证闸**（wabt CLI 独立安装——与自写不冲突，双保险） |
| 折叠器配套 | 装载期解码=编码器逆（同包配对，~600 行） | — |

**拍板推荐**：自写编码器（引擎内）+ wabt 验证闸（CI 外部）——前者是唯一满足三臂同形纪律的形态，后者白拿标准验证器作第二证人。

### 7.2 工作量分批估算（净新代码，不含测试；对照 jit_survey §3.1「翻译器纯 MoonBit ~1k 行」基线）

| 批 | 件 | 估算 |
|---|---|---|
| 批 1 | wasmenc 包 + emit_wasm 发射器（153 模板穷尽）+ 模板库 + 产物闸 | ~2.5–3.5k 行（发射模板 153 条占大头）|
| 批 2 | 折叠装载器 + run 态接线 + 对拍闸 | ~1.5–2k 行 |
| 批 3 | step/断点/time_travel 适配（组表 loc 映射 + gip 快照） | ~0.8–1.2k 行 |
| 批 4 | 收口（code 字段退役 + schema/文档/彩排） | ~0.3k 行 + 发版流程 |
| 批 5 | 影子执行器（JS/TS 双端：demo + CEF 桥）+ 确认协议 + 上报 | ~1–1.5k 行 |
| 合计 | — | **~6–8.5k 行，批间独立可停**；每批一个发版窗口（对照：S9 全季节奏，批 1+2 ≈ 一个常规阶段） |

### 7.3 风险表（工程风险为主——语义风险已由铁律 1 的防线体系消除）

| # | 风险 | 等级 | 缓解机制 |
|---|---|---|---|
| R1 | **发射↔折叠互逆失配**（模板改了一侧漏另一侧→装载 fail loud 频发或错折叠） | 高 | 同语义表驱动+两侧穷尽 match 编译红；装载期模板不匹配 fail loud（拒载非回退静默）；批 2 起全语料双跑对拍闸逐位锁 |
| R2 | **V8/wasmtime 对 MVP 子集实现差异**（规范非确定面：NaN payload/浮点 flush） | 中 | 子集发射策略回避（NaN 只位模式传递，§2.1）；W4 五桶判定+trapCategory 归一先例；分歧走 4.3 三方定责 |
| R3 | **host ABI 跨界开销**（H2 每次回接 ~µs 级） | 中 | host 占比 ~1%（#176 实测）；W4 polyfill 经验可迁移（如未来 host 热点可 wasm 内桩化） |
| R4 | NaN 位级观察面残余分歧（printf %a/位运算消费运算 NaN） | 低 | E 码登记为已知豁免面（对拍白名单机制现役）；实测出现再裁 |
| R5 | **批 4 不可逆**（code 字段退役后 legacy 解释器取指层删除） | 高 | 批 4 前置条件=批 2/3 各跑满一个发版周期零漂移；git 历史+发版 tag 即回退资产 |
| R6 | 产物体积增长（双发期 +wasm 段） | 低 | PoC 单程序 <1KB〔已验证〕；批 4 收口后 legacy code 退役净减 |
| R7 | 禁译白名单面过宽→快路径覆盖率不足（qsort/scanf 族整函数禁译） | 中 | 覆盖率先实测（批 1 统计禁译函数占比语料分布）；回调族块首重入协议为期 3 扩面项 |
| R8 | CEF 壳 V8 版本漂移（桌面影子随 Chromium 版本走） | 低 | 上报字段带 runtime 版本（4.3）；CI node V8+桌面 CEF 双覆盖 |

---

## 8. 开放问题清单（实施批逐项拍板，本设计批给推荐不锁死）

| # | 问题 | 推荐 | 拍板时机 |
|---|---|---|---|
| O1 | 快路径结果 UI 语义：先展示+角标 vs 权威后展示 | 先展示+「待验证」角标（长跑体验主张） | 批 5 |
| O2 | 批 4 时点：0.11.0 还是 1.0（1.0=退役评估阶段，载体收口与退役评估合流？） | 0.11.0 独立完成（不与退役耦合） | 批 3 后 |
| O3 | Memcpy 重叠语义 vs `memory.copy`（memmove 语义） | 实施批先亲读现役 Memcpy 语义补锚，等价才换指令 | 批 1 |
| O4 | 局部变量提升（取址分析）是否进期 1 | 不进（基线全留内存=帧布局不变）；期 3 随结构化优化 | 期 3 |
| O5 | 步锚计数的 checked 常开 vs 双形态产物（checked/raw） | 单 checked 形态（对拍协议要求双跑一致——raw 只在权威确认链外无消费者；保真代价 1.5× 已含在 300× 内） | 批 1 |
| O6 | 禁译函数的步数预算语义（禁译函数走权威时快路径如何对齐 steps） | 整程序快路径只在「零禁译函数」时启用（首版）；含禁译函数=纯权威 | 批 5 |
| O7 | `desktop/`（CEF 测试壳）是否升格为桌面影子执行器的正式承载（vs B 计划壳外挂 CEF 视图） | 桌面影子随 desktop/ CEF 线先行（现役资产），B 壳形态待产品拍板 | 批 5 |

---

## 9. 实施触发条件（写死）

**以下两条件同时满足才启动批 1；不满足不启动（本设计单无限期待命）：**

1. **0.10.0 已发版**（发版纪律与彩排节奏以 vitro-release-playbook 为准——载体迁移批不与发版窗口抢占）；
2. **真实痛点/需求实证**（二者居一）：
   - **性能卡顿场景实证**：run 态长跑在真实产品面（判题/语料跑批/算法演示）出现用户可感知卡顿（参照 20261018 性能实测的基线口径复测，且 P0 落闸+解释器优化空间已榨尽仍不达标）；
   - **解锁功能的产品需求立项**：§6 清单中任一功能（导出真 wasm/多 runtime/实时对拍）进入产品排期。

**反触发声明**：若触发时点 0.11/1.0 排期与 Go 防线层退役评估（1.0 主题）冲突，载体迁移让位或合流由用户拍板——设计单不预设。

---

## 附：本设计单的证据底账（全部本会话亲读）

- 码表与执行器：`moonbit/opcode/opcode.mbt:26-181,197-353`（155 编号/空号/死码）；`moonbit/vm/exec_step.mbt:22-110,136-303`（step 簿记/P0 落闸/dispatch 135 臂）；`moonbit/vm/exec_debug.mbt:21-110`（StepEvent/TrapBounds/E3086）；`moonbit/vm/exec_control.mbt:72-73,220-300`（call_depth_limit/CallPtr host 段/WaitingInput ip+step_count 回退/Ret 回调哨兵）；`moonbit/vm/exec_arith.mbt:14-52,271-290`（共享算术核/Shl 移位域 trap）；`moonbit/vm/exec_float.mbt:7,98-100,170-172`（饱和转换）；`moonbit/vm/exec_memory.mbt:76-94`（SplitD/Q/StackAlloc）；`moonbit/vm/types.mbt:46-75`（StepResult 五态/CallFrame）
- 产物与内存：`moonbit/bytecode/schema.mbt:80-97`（CompileOutput 13 字段）；`moonbit/bytecode/memory.mbt:15-91`（R1 地址常量/argv/compute_heap_base）；`moonbit/memory/layout.mbt:20-43`（页几何/quarantine 预算）
- 会话与时间旅行：`moonbit/time_travel/engine.mbt:24-46`（UnifiedEngine 状态定形）
- 实测报告（仓内，本会话亲读全文）：`tmp/jit_survey/report.md`（PoC 与 §7.3 七原则）；`tmp/batch_W4_REPORT.md`（第四臂/polyfill/host-call 定量）；`tmp/batch_STEPINV_REPORT.md`（帧流不变量/INV3a）；`tmp/batch_CORE_LANG_REPORT.md`（B 计划壳基线）；`tmp/batch_P_proton_REPORT.md` 相关行（CEF V8 版本）
- 历史复核底稿：`docs/archive/WASM_BACKEND_FEASIBILITY_ANALYSIS.md`（按任务书指定作线索，不作依据）
- 数字口径：corpus .c 文件数 980（本会话 `find | wc -l` 亲数——STEP-INV 报告 995 为含后续 chibicc_port 扩桶前口径差异，两数均记录不裁剪）
