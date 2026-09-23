# MoonBit 迁移总计划

> **定稿**：2026-09-18（探测阶段收官版）｜ **性质**：唯一存活计划文档——本文件浓缩并取代探测阶段的 16 份文档（评估报告 + 13 份模块勘察 + 蓝图 v1.1 + 八轮第一手复核记录，全部经提交 `917251e` 保存在 git 历史，取回方法见 §11）
> **证据基线**：四道证伪门全部实测关闭（0 红）+ 27 项丢/继承/改进决定逐项亲证（0 推翻）+ 9 条 MoonBit 语言事实一手实证。所有论断可溯三层之一：勘察报告原文亲读、复核实测、代码亲验。
> **执行文档**：第一阶段（S0 收尾 + S0.5 Rust 止血批 + S1 基础片）的逐项任务清单见 [`MoonBit迁移第一阶段计划.md`](MoonBit迁移第一阶段计划.md)。

---

## 1. 形态与范围裁定

| # | 裁定 | 依据摘要 |
|---|---|---|
| F-1 | **同仓绞杀者渐进迁移**：Rust 版冻结不删、降级为差分对照 oracle；MoonBit workspace 与 `native/` 并列。冻结纪律：Rust 侧只收安全修复，新特性一律 MoonBit 侧 | 项目所有者拍板；"每搬一包趁 Rust 版仍在做差分扫描"是唯一不重踩坑路径 |
| F-2 | **v1 范围 = C only**：C++ 子集（≈6,514 行 / 8.5%）延后 S9 单独裁定；包边界第一天预留；砍 C++ 与 CS2 复用策略冲突须合并裁定；空输入短路可取得"砍"的主要收益。**裁定已出（2026-09-20）：砍**——C++ 零迁移（寄生面由"从不落块"天然完成 U3#6/#9 手术）；CS2 复用冲突合并裁定：Rust oracle 冻结区保留为 C# 类机制**语义参考**（Phase 32/33 实现思路可查），"先在 C++ 上趟平"的垫脚石损失可接受（C++ 栈对象 RAII 与 C# 引用类型+ARC 语义本大异，直接可复用面仅 AST 形态与 vtable 布局思路）；C++ 防线（shadow_cpp 99 / E2E 83 / CI 三 tier）随砍退役归档 | VM 零 C++ 感知（实测 3 处偶然命中）；is_cpp_mode 全在 lexer+parser 最前两层 |
| F-3 | **JIT 倾向不搬**（S9 复核）：宿主 V8 自带 JIT 边际缩水；JIT 与解释器溢出语义分歧现存未修；统一模式下 JIT 录制纯浪费。`jit_path_parity` 八形状外置 JSON 作"复活必全绿"遗产 | 门 1 实测：放弃 JIT 代价收敛为热循环 ~2.8× 且仍快于现役解释器 |
| F-4 | **驱动层 v1 保留 Go**（10,767 行清白资产）；Node 宿主为新增薄层（engine-host 接口：spawn/stdin 字节/stdout 逐行/stderr/超时 kill/退出码/RSS 采样）；golden 生成器由 Node 宿主驱动承担 | D5 刚收官；绞杀者策略新语言只承担引擎本体 |
| F-5 | **wasm-gc 单出口、多宿主**：浏览器（主交付）/ Node 22+（CI 主力）/ Wasmtime（需 `-W gc`，部署文档写明）；宿主接口 4 函数（invoke/reset/protocol_version/engine_version）+ 21 方法表；`memory.regions` 字段当场定型；砍 capi 45 导出 | 门 2 实测 2.34s 真实运行；45 导出中 28 无消费者（亲证） |

## 2. 四道证伪门终局（全部实测，0 红）

| 门 | 判定 | 关键数字 | 随迁条件/遗留 |
|---|---|---|---|
| 门 0 LLM 效率 | **通过（弱）** | 干净上下文 6 真实函数：首过 1/6、每函数 ≤2 轮收敛、6/6 正确（含 quirk 保真与饱和边界断言） | 无同协议 Rust 对照组；三大语言差异进 S1 工程约定 |
| 门 1 VM 吞吐 | **通过** | 真实引擎锚（vm_bench 1k×1k）：现役解释器 512ms / JIT 55ms；MoonBit 迷你 VM（含 NULL/UAF 16,384 条二分/脏页检查链，校验和同口径）native 81ms / wasm-gc·V8 156ms = **快于解释器 3.3×、慢于 JIT 2.8×** | 条件 A：S6 片起 1k×1k 等价基准对照 512/55ms 双基线；条件 B：LeetCode 全量 ≤3s |
| 门 2 Wasmtime | **有条件通过** | 零 import 产物 `-W gc` 下 2.34s 真实运行（哨兵双证红）；v33 CLI 默认拒 GC 模块 | 部署须显式开特性 |
| 门 3 快照往返 | **通过（模块级）** | PASS 5/5 双目标（1MB 逐字节 + freed 全表 + 隔离区三件套 + seek 确定性 + UAF 无假阴性） | S6 集成版验收 |

**门 1 方法论教训（入档）**：首轮"名义红 7×"系对照物失真（理想化 Rust 孪生比现役解释器快 23×）——**比值结论必须声明分母引擎**。

## 3. 已实证 MoonBit 语言事实（F1–F9，全部一手取证）

| # | 事实 | 后果 |
|---|---|---|
| F1 | `Int` 四则**静默回绕**（`2147483647+1→-2147483648`），全 core **无 checked API**；`1<<1000=256`（位移 mod 32）；`x/0`→RuntimeError | 教学溢出 trap 必须应用层显式检测（`to_int64` 中转 + 范围判定，与 Rust `arithmetic.rs` 同构）；检测成本占每算术指令比已入门 1 数据 |
| F2 | `String` 内部 UTF-16（`"中文".length()=2`，`@utf8.encode().length()=6`）；`to_bytes()` 已弃用 | C 字节流一律 `Bytes`/`FixedArray[Byte]`；坐标单位契约进 `vitro/engine/source` 包 |
| F3 | `Bytes` 不可变且是 `FixedArray[Byte]` 的 `%identity` 视图（core 源码取证）；`FixedArray[Byte]` 可写、**packed**（100M 元素 106.9MB vs Int 406.9MB = 1:3.8，实测） | 1MB 内存载体定案；门 1a 通过 |
| F4 | 21 帧瀑布递归栈深：wasm-gc 854 / js 538 / native 1005（崩溃 0xC00000FD 不可捕获，与 Rust 同形态） | 深度上限必须显式做；`MAX_PARSE_DEPTH` 语义可沿用但阈值重标定 |
| F5 | wasm-gc 产物 imports 仅 `spectest.print_char`（宿主收 Unicode 码点，须自做 UTF-8 编码）；`@env` 无宿主实现、无熵源 | 驱动协议 = 宿主提供的 import 组；引擎 rand 默认种子不得依赖系统熵 |
| F6 | `Hasher` 种子 wasm/wasm-gc=0、native/llvm/js=随机；`HashMap::iter` 序 unspecified | **一切产物输出显式排序/LinkedHashMap**；"同输入两次产物哈希相同"入 CI |
| F7 | `moon check`/`moon build` 下缺臂 enum match **默认即 error**（删臂实验 exit 127）；诊断**列出**缺失变体名 | 穷尽收益成立；CI 用 `moon check` 即可（`-d` 非必需） |
| F8 | moonc v0.10.13 存在跨文件顶层 `pub let` link-core ICE（常量内联即消失） | 工具链不稳信号，A6 持续监控 |
| F9 | `@json` 浮点序列化 `1.0→1`、`-0.0→0`（与 serde_json 不同）；libc 产物 f64/i64/string_data 全空（实测）故暂不触发 | **bundle 禁逐字节比对，解析后结构化比对** |

## 4. 包切分总图（L0–L9，`.mbti` 取代 ABI 版本化成为对外义务载体）

```
L0 零依赖   vitro/engine/source(SourceLoc+坐标契约)   vitro/engine/opcode(132+Instruction+operand 校验)
L1 诊断契约  vitro/engine/diag(ErrorCode 137+Severity+SourceLang+Diagnostic+catalog JSON+覆盖率断言)
L2 抽象语法  vitro/engine/ast(Type 17/Expr 26/Stmt 16+depth+判等渲染单源；不含 compute_type_size)
L3 名字单源  vitro/engine/names(InstKey→InstId→mangled Name 唯一产出口；parser/typeck 共依赖)
L4 前端     vitro/engine/lexer(facade tokenize→LexResult；internal/{source,pp,host})  vitro/engine/parser
            〔CS 批·S6 后〕vitro/engine/csharp/lexer + csharp/parser（C# 前端；插值字符串 hole 级 span）
L5 语义     vitro/engine/typeck ─ vitro/engine/containers(JSON 数据驱动) ─ vitro/engine/libc(单表签名)
            〔CS 批〕vitro/engine/csharp/typeck（引用语义/类系统/异常类型链/ARC 插桩点判定；表达式定型内核消费 vitro/engine/typeck——共享切线=表达式/语句层，声明层分叉；原 typeck/cpp 预留位随砍 C++ 裁定撤销）
L6 发射     vitro/engine/codegen(internal/{Layout Planner, frame LIFO 池, c})  vitro/engine/bytecode(产物 schema+libc 固定索引)
            〔CS 批〕vitro/engine/csharp/codegen（ARC 插桩/异常映射 trap→Throw/顶层语句入口合成；原 internal/cpp 子目录规划随砍 C++ 裁定撤销）
L7 执行     vitro/engine/memory(载体+MemoryMap+checked_access 单入口+bump/隔离堆+freed_logs 有序结构)
            vitro/engine/host(宿主函数域：路由表消费侧+输出通道 Bytes 化+内存族 handlers；vfs 入场待建)
            vitro/engine/vm(executor 穷尽 match+snapshot 不可变派生)
            〔S6 开工批二裁定·任务书内部不一致登记（2026-09-23）〕"110 路由表单源"的**定义点落 L6 `bytecode`**
              （`route.mbt` + `host_func_id_gen.mbt`）：本行原表述"路由表单源属 host(L7)"与 §4「依赖严格单向」
              **不可同时成立**——codegen(L6) 在编译期就必须选 `Call <固定索引>` 还是 `CallHost <id>`，
              即路由表是 L6 的必需品，L6→L7 反向依赖被禁；又因派生需 `bytecode_libc_all_funcs`（88 名单源在 L6），
              libc(L5) 亦无法反向 import L6。host 为消费方（执行期分发），落点详见生成器头注与 `route.mbt` 模块头。
            〔CS 批·v1 设计输入非事后补丁〕vm 三执行状态：handler 栈/异常寄存器/UNWINDING + memory region 表 refcount 字段——opcode TryBegin=44/TryEnd=45/Throw=46 进历史空号（对 Rust 对拍面零扰动，双侧皆空号）；VMSnapshot 一等含三状态（时间旅行免费安全）
            〔S9 裁定〕vitro/engine/jit(必须可整体移除)
L8 会话/协议  vitro/engine/session(SessionConfig 值对象)  vitro/engine/protocol(帧+schema 版本+StepPayload/词汇/契约)
            vitro/engine/gateway(wasm-gc 4 函数导出+NDJSON)
L9 教学智能  vitro/engine/time_travel  vitro/engine/teaching/steps  vitro/engine/analysis(cfg/algorithms)  vitro/engine/diagnostics
            —— 经 VmObserver/SourceProvider/AlgorithmContext 三接口依赖反转，不依赖 session
仓库外      Go 驱动层(保留) + Node engine-host(新增薄层) + spike 目录
```

硬约束：依赖严格单向无环；`.mbti` 只暴露 `protocol` 全量 / `lexer.tokenize` / `typeck.check` 三面；跨包不变量做成可执行断言包；版本承诺锚 `protocol_version` 编译期常量。

## 5. 在途工作接纳（摘要）

- **Rust 侧必修（P1–P7，S0.5 执行，详见第一阶段计划）**：J1 声明符栈溢出、★A 全局字符串指针双侧修复、E 前缀 4 处、string 转义收口、golden 补齐与 fail-loud（含 4 例手写 golden 循环论证处置）、列号口径冻结、AST dump 出口新建；外加 U1（认知链二/三/四层 Rust 侧补最小导出——差分退路现在不存在）与 U2（`vitro_capi.h` 19 声明是 SharpTutor 当前阻塞项，与开工同批拍板）。
- **直接按目标架构实现（要点）**：单态化纯函数化+实例化缓存（1024 上限三处改法：按栈深/带真实 SourceLoc/点名模板）；SourceLang 单源（is_cpp_mode 46 处亲证）；预处理独立 pass+LineMap+双坐标；Layout Planner；LIFO 槽位分配器（8 条事故回归必挂）；统一写路径校验器；freed_logs 有序数组+二分；OutputLog 载体 Bytes 化；VFS 入快照；诊断结构化；note 有界；U6#4；Trap 回退改"检查点+正向重放"（消每步 1MB 快照——engine.rs:169 亲证）；stream 升格窗口表示；语义标注改执行事件；签名真相源单表（printf/putchar/strcpy 三处实测冲突）；golden 生成器换 Node 宿主；memory.regions 定型；"喂入不重置运行态"与"会话级配置不可被初始化覆盖"两条不变量；发布缓冲显式状态类型；`Stmt::Try` 保留标 reserved-for-csharp。
- **放弃并记录**：capi 全部后续批次；双轨管线（生产零调用亲证）；unified/stream 死码（外部引用零亲证）；`OpCode::Strlen`/`TrapBoundsVla` 死 opcode（codegen 零发射亲证）；`compiler/ast.rs` 死文件；`extract_cpp_builtin_layout.py`（OUTPUT_PATH 指向不存在目录亲证）；K&R 语法；`-I` 搜索路径；H-4 存根硬遮蔽；D14（已清零销项）/D16 再拆；诊断切面 38/810（差分锚替代）；vm_benchmark.rs。

## 6. 差分对账分级锚点体系

| 级 | 锚点 | 前提 |
|---|---|---|
| **A 字节级** | ①字节码产物 code 段 ②stdout ③最终 1MB 内存映像 | Go canonicalizer（键排序/转义/缩进固定，fail loud）；**三条冻结**：槽位策略版本化 / 绝对 IP 跳转编码 / libc 固定索引（1000/1024/1089 按名→索引比对）；**排序义务显式继承**（现版产物确定性完全依赖 Go 侧 sort_keys，MoonBit 侧原生有序）；bundle 禁逐字节（F9） |
| **B 结构化** | token TSV / AST dump（依赖 P7 出口）/ 符号表 / 诊断序列 / mangled 名集合 / 实例化产物 / 协议帧 NDJSON / error_catalog JSON / 标注首现序列 | 两侧**显式 emitter**（禁一侧 serde 一侧 ToJson）；serve 补字段级冻结测试（protocol_frames.jsonl 双宿主对拍）；白名单补"缺失即红"；含非 ASCII/\xHH 用例（现覆盖 0） |
| **C 端到端** | Clang golden 733 全量 / replay 61 / serve_smoke 57 / JIT parity 八形状（若复活） | golden 缺失必红；`.out` 只作第二来源，live clang 为主真值 |
| **D 三联 diff** | stdout+返回码+1MB 映像 × 30 例矩阵（JIT 形状+UAF/隔离区+快照往返+字节通道+浮点+调用栈+VFS+路由分叉） | 内存 dump 出口新增 |

## 7. 裸奔期最小防线与重建里程碑

最小防线 = **24~26 例**（全部 baseline、已有 golden、无 stdin；五条选例标准；必含 `engine_note_lookalike.c` 与 `codegen_soundness_regression.c`）；三条防假绿纪律（空集不得绿 / golden 缺失必红 / 字节层比对）；M-0 基线冻结（shadow 快照+facts 入版本控制）；重建里程碑 M-1~M-9（驱动骨架→golden 解析→全量→live-Clang→三层契约→fuzz→facts→台账 CI）。

## 8. 差异台账 v0（机器单源，S8 片落地）

格式：`DIFF-<域>-<序号>`；`class ∈ {architectural, implementable, pedagogical}`；`carry_over ∈ {inherit, fix, drop, retest}`；JSON schema 含 `anchors`（与 shadow KNOWN 常量双向对账）与 `detectable_by_defense` 诚实字段；capability_flags **17 项**；落地三步（单源→CI 对账→J9 埋雷）。初始条目 14 条代表项（DIFF-PTR-4BYTE-01 / DIFF-LAYOUT-PACKED-01（防线零覆盖，先立 golden）/ DIFF-LIB-PRINTF-01 / DIFF-LIB-PUTCHAR-01（golden 缺口）/ DIFF-PREPROC-MULTILINE-01（规范反向漂移，先修规格）/ DIFF-TYPE-SHORT-01 等）。守门规则：引擎行为与台账冲突时要么改行为要么改台账，禁止沉默漂移。

## 9. 风险登记册（终态）

A2 实测关闭（有条件）；A3 实测关闭（方向有利）；A7 实测关闭（弱）；A8 持续监控（F8 ICE）；R1 门 1 条件 A/B；R2 HashMap 种子（排序义务）；R3 UTF-16 三单位（坐标契约）；R5 双头维护（冻结纪律）；R6 裸奔期（最小防线）；R7 生成物门禁；R9 拖延（分片可停可续）；R11 wasm 冒烟证据链（重建：真 E3070/E3061 断言+体积断言+产物更名，每条护栏先证红）；R12 rand 种子（wasm-gc 无熵源）。

## 10. 里程碑切片

| 片 | 内容 | 验收（锚点级） | 发布 |
|---|---|---|---|
| S0.5 | Rust 止血批 P1–P7 + U1/U2 | 每条红→绿留痕；M-0 基线冻结 | — |
| S1 | `vitro/engine/{source,diag,opcode,ast}` | E1 AST dump（B）+ error_catalog JSON（B）+ 码表生成幂等 | `vitro/engine/diag` 首发 |
| S2 | ✅ `vitro/engine/lexer`（独立 pass+LineMap+宿主 IO；2026-09-19 收官——[执行记录](../07-质量与裁定/20260919_S2词法器执行记录.md)） | ✅ L1/L2 token TSV + 随机差分 2400 例（4800 TSV）+ 真实语料 444 例逐字节一致 | ✅ `vitro/engine/lexer`（0.2.0 首发 + 0.3.0 审阅修复批——real_line 归属通道 + 打包卫生） |
| S3 | ✅ `vitro/engine/parser`（深度统一入口；J1 语义不复刻；2026-09-19 收官——[执行记录](../07-质量与裁定/20260919_S3解析器执行记录.md)） | ✅ E1–E4 全绿：597 真实语料 AST+诊断序列归一逐字节一致 + 病态 12 样本同等拒绝 + 活性 stall=0 + E4 反向锚（1200 层声明符两侧存活且一致） | —（随 0.4.0 发布） |
| S4 | ✅ `vitro/engine/{names,libc,typeck}` 主体收官（2026-09-20 T5-b/c/d + T6：typeck 4 Pass 全接线——call/init/builtin/decl 四文件 + bytecode_libc_sig 表入 libc；**598 语料 E1–E4 归一逐字节一致**（2 条 F3-v2 白名单 FORK(known)——parser 层分叉的 typeck 消费面放大，S8 台账）；quote-include 哨兵入 gap；183 测试；**containers 延后 S9**：内置容器全是 C++ 模板路径，C only 零活跃路径，F-2 推论） | E1–E4；**改形登记（2026-09-20 审阅 F4）**：E2 符号表/E3 mangled 名集合不独立出口，由 E4 typed_ast 投影派生（typeck 内部 Map 状态不外溢产物——C 输入下投影≈快照可辩护：classes 恒空、static_func_sigs/templates 合并差异均以诊断形式落在 E1 面）；**mangled 名集合在 C 子集无对象**（C 侧零模板/方法 mangling——names 的 type_mangle_suffix/method_mangled_name 消费面全在 C++ 路径，S9 后才有差分锚）；勘察 §5 架构优化 M1（单态化两阶段）C only 无对象、M3（诊断结构化）协议层不动照搬旧 TypeError、M4（尺寸单一表达式）/M9（声明定型统一）随 init/decl_types 批、M7（诊断顺序显式化）以 Vec push 序照搬达成隐式确定——均未按『目标架构』形态落地，等价优先 | names——**C 子集零差分覆盖**（8 消费点全在 C++ 语法路径，5 测试为白盒自证；发布形态待 S4 收官时裁定：推迟至 S9 后或以白盒锚为发布锚） |
| S5 | `vitro/engine/{codegen,bytecode}`（**开工批已落**，2026-09-20：bytecode 建包——产物 schema 13 字段 + libc 固定索引 88 函数（数组单源 + 索引派生断言锚，S4 坑②索引表入产物层落地）+ R1 布局纯函数（r1 第 7 道断言全量搬）+ canonical dump emitter；codegen 骨架（**flat 四文件起步**——L6 包图 internal/{Layout Planner, frame, c} 切分随扩展批；2026-09-21 审阅登记）——BytecodeGen C only 裁剪（47 字段剔 C++ 专属 7 项：顶层 6 + 嵌套 1）+ Pass 1 全量（T-P0-1/2 位模式 + P2 字符串延迟回填）+ Pass 2/3 最小集（Block/Expr/Return + 四字面量/Identifier）+ libc 预注册（strcpy/strcat Host 例外）+ 入口 wrapper；**槽位策略 v1 逐位兼容**（**勘察 §5 契约偏差登记（2026-09-21 审阅）**：原定"直接按目标架构实现 LIFO 分配器（8 条事故回归必挂）"，本批改判 v1 先行——A 级 code 段逐位 diff 以现行槽位策略为前提；LIFO v2 批补挂 8 条回归并以 `SLOT_STRATEGY_VERSION` 常量分档——v1 常量已落 codegen 包；**get_temp_slot 越界已改 fail loud**（Rust 静默回退 slot0 不继承））；差分锚已立——Rust `vitro_cli dump-compile`（CompileDump 14 键，含 L4 五字段出口，防线维护）+ MoonBit `cmd/dump_compile` + Go `scripts/codegen_diff`（四类判定 SAME/AGREE-ERROR/ONE-SIDED/CONTENT-DIFF；--baseline 显式豁免 one-sided；J9 selftest 注入证红 ✅）；**A 级对拍**：13 条骨架语料（2026-09-21 审阅批 +3：2^64 溢出/浮点 inf/__func__）归一逐字节一致含 code 段逐指令；未接线语句/表达式族 fail loud（红面基线期；**baseline 363 例归因（2026-09-21）**：lex 7 + parse 2 = AGREE 已闭环；**扩展批一号（2026-09-21）已接 VarDecl + CallPtr**（host 路由 110 对生成器 `scripts/gen_host_route` 三件套：落款 sha + fmt 内置 + -check 幂等——2026-09-21 审阅 P2a 修复"假生成物"；S6 host 建包时上提）——SAME 0→56；**扩展批二号（2026-09-21：二元/一元/Cast/sizeof 族六臂——隐式提升链/指针算术/U 族/短路规范化/IncDecKind 分派/跨包 enum 只读规避）SAME 56→174 / 剩余 180 / CONTENT-DIFF=0**；全语料累计 SAME 190/598（baseline 174 + knr 7 + leetcode 2 + gap 7）；剩余首错：赋值 67 > for 30 > Index 23 > if 17 > while 12 > 三目 10 > Member 5 > switch 5；**扩展批三号（2026-09-21：赋值+三目+控制流五件——emit_compound float 分支照搬遗漏由 kr_1_15 对拍实锤修正）后全语料 SAME 325/598（54%）：baseline 262 + knr 35 + leetcode 18 + gap 10，CONTENT-DIFF 全 0**；F3-v2 白名单（parser 分叉的 codegen 消费面放大）入 codegen_diff；下批 Index/Member 族 + leetcode 复杂组合；**扩展批四号（2026-09-21：Index/Member 全接线 + struct 返回拷贝 + _Generic + 复合字面量；base_kind Pointer 一层语义纠偏——8 例步长真红实锤）后 A 级对拍面全语料闭环：598/598（SAME 583 + AGREE 13 + FORK 2），CONTENT-DIFF=0/ONE-SIDED=0**；codegen 剩余义务：libc 自举 + LIFO v2 + r1 端到端（S6 协力）；**收尾批（2026-09-21）**：收面 27 符号 + moonbit_surface 审计闸（CI 接线，白名单 10 条）+ parser cpp_mode 剔除（F-2 终局）+ moon.mod **0.4.0 已于 2026-09-21 15:49 发布**（本机 registry 实测：0.1.0→0.1.1→0.2.0→0.3.0→0.4.0；mooncakes 模块页显示 16 个包在架）——架构报告待办①闭环，且**收面赶在发布之前完成（"未发布包零成本收面"窗口用尽）**）；**MoonBit 语言事实新增**：String compare/`<`/`>` 非字典序（长度优先疑——emitter 键序自写码元比较，moonbit/AGENTS.md #29） | A 级产物 code 段 + libc 自举 + LIFO 八条事故回归 + r1 7 道 + `--dump-compile-output` 工具 + codegen 自建单测（**开工批**：dump-compile ✅ / r1 纯函数段 ✅ / 骨架自建单测 6+7 ✅ / code 段骨架面对拍 ✅；**在途**：语句族（var_decl/if/while/for/switch/call）与表达式族（二元/赋值/index/member/取址）逐批接线 + libc 自举 + LIFO v2 八条回归 + r1 端到端 7 道（VM 侧，S6 协力）） | — |
| S6 | `vitro/engine/{memory,host,vm}`（**开工批已落 = `memory` 建包**，2026-09-23：1MB 载体 `Memory`（`FixedArray[Byte]` + 脏页位图；`bytes`/`dirty` **priv** ⇒ 包外无裸字节） + `MemoryMap`（regions = **addr 键插入序 Map**——平行索引取消，坑 6 失配面归零；free_list / quarantine FIFO / `release` 三条释放路径**单一出口** / `check_access` 单入口（NULL 区→上界→UAF）/ `verify` 不变量自检） + `FreedLogs`（**有序数组 + 二分**：单次探测 + 降序提前 break + 部分重叠精确裁剪）+ `MemFault` 结构化故障（文案归 vm）；**常量不双写**——地址布局常量仍以 L6 `bytecode/memory.mbt` 为定义点，本包只消费 4 个（其余 3 个的消费者是 vm 片，已登记 surface_allowlist 待清理）；红锚照搬坑 6/7/10 + churn 超预算不撞墙 + 1MB 墙返 NULL；**J9 双路注入证红**（`remove_overlapping` 退化为整条删除 → 4 用例红；`find_overlapping` 二分差一 → 13/27 红）；27 测试（白盒 21 + 黑盒 6，黑盒兼作对外面消费面）；八闸 + `moon check --target all` 全绿；**已知代价登记**：有序数组 `remove` 是 O(n) 搬移，旧块复用路径下标近 0 时搬移接近全长（10 万次 churn 实测 1.6s，暂不构成问题；换 `@sorted_map` 时区间算法与全部红锚不变）；**登记未落地**：快照批量装载 `load_*`（形状待 vm 定 `VMSnapshot`/`MemoryImage`）、`MemoryFragmentData`（L8 导出 DTO）、cstring 通道（`\xHH≥0x80→Latin-1` 口径单源在 L6 `codegen/init.mbt` 且 priv，跨层复用须先上提为独立单源）。**host 开工批二已落（2026-09-23）**：`vitro/engine/host` 建包——① 路由表单源（`bytecode/route.mbt`：`CallRoute` 二分形态 + `call_route` 派生 + **遮蔽集显式清单**（20 个"有实现但按名调用到不了"的 handler 从"无处可查"变成可断言事实）+ `is_host_rerouted` 两条例外（strcpy/strcat 的 E3070 理由）；`gen_host_route` 产物自 codegen 上提至 bytecode 并补出 `host_func_pairs` 全名表——**`by_user_name` 带 PURE 短路，不能当成员判定**）；② **输出通道 Bytes 化**（`OutputKind/OutputChunk/OutputLog`：非 UTF-8 字节保真 + 16MB 环形丢最旧保最新 + 截断注记 + 64B 小段合并；**读取走只读视图不改状态**——否则"读一次再写小段"就不再合并，与 Rust 分叉）；③ 内存族 handlers（`host_malloc/calloc/realloc/free` 返回 `HostMemReply{value?,note?,trap?}` **不碰值栈** ⇒ 内存语义可脱离 VM 锚定；受检访问一律经 memory 单入口，`calloc` 置零/`realloc` 搬运走段级 `fill`/`copy` 而非 Rust 的逐字节 `store_i8`）；27 测试（白盒 24 + 黑盒 3）；**新发现两条 oracle 存量缺陷并固化红锚**（① `calloc` 置零先于清理 freed_logs ⇒ 复用驱逐块时 UAF **误报**；② 尺寸链 `saturating_mul`+`align4` 回绕 ⇒ 超大尺寸不失败反登记 `addr=0/size=-1` 垃圾区域，已由 `verify` 新增区域有效性检查抓到）——均按「照搬不私改」保留行为 + 登记 + 修复形态写明；十闸 + `moon check --target all` 全绿。**host 其余 ~106 个 handler 与 VFS 未开工**；vm 片**未开工**） | D 级 30 例三联 diff + 门 3 集成版 + 条件 A 性能锚；**vm 设计输入（C# 前置，砍 C++ 后新增）**：handler 栈/异常寄存器/UNWINDING 三执行状态 + region refcount 字段进 v1 状态机（见包图 L7）——C# 异常与 ARC 不走 Rust 侧"事后打补丁"路线 | `vitro/engine/vm` |
| S7 | `vitro/engine/{session,protocol,gateway}` + Node 宿主 | 协议帧双宿主对拍 + replay/serve_smoke 重建 | `vitro/engine/protocol` + wasm-gc 产物 |
| S8 | `vitro/engine/{time_travel,teaching,analysis,diagnostics}` + 差异台账 | seek 往返五类相等 + 标注 golden 311 三方 diff + 台账 CI | 认知链切片 |
| S9 | 裁定批：JIT 复核 / ~~C++ 搬或砍~~（**2026-09-20 已裁：砍**，与 CS2 合并裁定落 C# 计划 §11 v4——寄生收口 U3#6/#9 由零迁移天然完成、容器 containers 包改判 C# 走 BCL 数据驱动）/ libc 机制形态 / Wasmtime 形态 | 各自判定书 | — |
| 全量切换 | 758 用例 + golden 733 全绿 + facts 双轨收口 | shadow 逐项一致（match/known_issue/gap 三口径） | 1.0 |

S4 期坑登记（2026-09-20 审阅，S9 裁定批输入）：① parser/decl.mbt 的类外方法定义名 `"{Class}__{method}"` 散拼（names 包『唯一产出口』声明的孪生漏网——照搬 Rust decl.rs:671 现状，收口随 C++ 片）；② libc 放行并集 175 名与 host_func_id/bytecode_libc_index 的单源关系（S4 以 MoonBit 侧 Set 照搬起步，S5/S6 发射/执行侧入库时**以 vitro/engine/libc 为单源回填**，消第四套真相源）。

节奏纪律：锚点未全绿不发版；每片回填 facts（新键空间独立）；任一时刻可停。

## 11. 探测档案指南（git 历史）

全部 16 份探测文档保存在提交 `917251e`：

```bash
git show 917251e --stat                          # 文件清单
git show 917251e:"docs/current/07-质量与裁定/MoonBit迁移_<模块>模块勘察报告20260918.md"
git log --oneline --follow -- "docs/current/07-质量与裁定/MoonBit迁移蓝图v1_第一手复核记录.md"
```

要点：13 份勘察报告的九节结构（资产/包袱/在途/架构/坑/spike/锚点/包切分/交叉声明）是 S2–S8 各片的执行输入；八轮复核记录含全部实测原始数据（探针输出、vm_bench 数字、门 0 迭代表、wasmtime 哨兵验证、五类工具陷阱）；评估报告含 A1–A9 假设原始表述。**本计划只保留结论与判据，细节以档案为准。**

## 12. 制度随迁

保留直接搬：红→绿纪律、诚实记录（防线哲学第 0 条）、J9 埋雷（升级为脚本上线硬门禁）、事故归档、同类清查义务、指标自报行、预留位 tripwire、KNOWN_* 双向对齐、单源登记义务。保留改写：facts 对账（机制重写，制度保留；覆盖键扩到台账自述数字）、文档数字三分法、RSS 护栏（口径重标定）、磁盘卫生（对象换 MoonBit target/包缓存）、发布节奏（ABI→包版本+.mbti）、产物新鲜度（版本串含 git 短哈希）。作废：ABI 版本化（随 capi）、`#![forbid(unsafe_code)]`、clippy 四规则（找 MoonBit 等价，覆盖度待证）、C ABI 契约测试、双轨驱动制度。新增：wasm-gc 宿主契约、包版本+.mbti 兼容性、每函数预期 1~2 轮编译迭代的排期口径、坐标单位契约、五类工具陷阱规则（SIGPIPE / 管道退出码 / 哨兵证红 / 基准同口径校验和 / 反斜杠 grep）。
