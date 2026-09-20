# C# 教学子集前端引入计划（2026-09-20 v4：砍 C++ 后 MoonBit 载体重设计）

> **决策背景**：SharpTutor（WPF/.NET 的 C# 教学 IDE）是本仓库前端切割后的**第一个外部消费者**，
> 已完成 C/C++ 引擎集成对接（capi 签名评审定稿、serve 主路径、15 用例冒烟集，见
> `CAPI评审回复与实现状态.md`）。在此之上，其"多语言对比教学"要从静态并排面板升级为
> **可执行白箱对照**，需要原生 C# 引擎：算法可视化自动检测 + 极细颗粒度纠正。
> 其自研 Roslyn 转译路线（C# 降解为 C 再调 Vitro）已实证**文本层降解撞语义错位**——报错
> 定位在生成代码行号、误区模式表无法映射 C# 引用语义——从反面验证了原生白箱前端的必要性。
>
> **立项三条件齐备**：锚定客户（13 章课程代码 = 天然验收用例集）、真实需求（对方明确的
> 消费缺口）、替代路线已排除（转译器降为参考实现，见 §8）。
>
> **执行时机**：本仓库 `结构重构与C23锚定决议.md` 全批次交付后启动（时序见 §7）。
> 本计划 v3 已吸收 SharpTutor 消费侧评审（2026-09-11），吸收记录见 §11。

## 1. 定位边界声明

**定位扩展**：教学 C/C++ 子集参考执行引擎（白箱）——主轴不变，新增 **C# 教学子集作为
第二前端**，由 SharpTutor 诉求锚定。原"后端语言锁定 C/C++"口径（定位主计划 §0）随之
扩展，**待在 `后端定位与白箱计划.md` 同步声明**（待办，见 §11）。

**不换（行为资产，与重构计划同一张清单）**：
- 编译管线五段结构（Lexer → Parser → TypeChecker → CodeGen → VM）
- 字节码格式与 680 个 Shadow golden（C# 侧只允许按既有规则**追加** opcode，本计划追加 3 个）
- 出口协议（capi ABI / serve 协议 / StepPayload schema——只增不改语义）
- VM 1MB 线性内存模型与教学检测语义（UAF/Double-Free/泄漏报告）

**换**：
- 语言分派：`is_cpp_mode` 布尔穿透 → `enum SourceLang { C, CSharp }` 单源化
  （**砍 C++ 裁定（2026-09-20）后为二语言**；Rust 侧现状检测点 `compile_pipeline.rs:631`
  实测，`Session`/`CompileState` 无语言字段，9 处 `"main.c"` 兜底字符串按扩展名生成；
  MoonBit 侧落点：前端入口包选择 + lang 由错误码构造方式携带，随 diag 包一并）
- 前端载体：**`vitro/engine/csharp/{lexer,parser,typeck,codegen}` 四包**（2026-09-20
  拍板）——执行载体已随 MoonBit 迁移转为 MoonBit workspace（v3 写的
  `vitro_csharp_frontend` crate 作废），CS 批次排 S6 后启动；共享/专属切线 =
  **表达式/语句层共享**（Expr/Stmt 全族 + `ast` 包已预留的 `Try`/`CatchClause`
  激活——MoonBit `ast/stmt.mbt` 现状即 reserved-for-csharp）、**声明层分叉**
  （类/引用语义在 csharp/typeck；表达式定型内核消费 `vitro/engine/typeck`，
  S4 函数式重建形态对此友好）
- 新增 3 个 opcode：**`TryBegin`=44 / `TryEnd`=45 / `Throw`=46**——进 MoonBit
  opcode 编号契约（0..137）的历史空号 44–49；Rust 侧同段为空号，**对拍面零扰动**
  （不再需要 v3 设想的"executor 分发 + JIT 白名单 + 跳转重定位"三处成本清单——
  S6 vm 按三执行状态 v1 设计直接内建，见总计划包图 L7）

**明确不做**：
- **Roslyn 进引擎**：wasm 出口（Roslyn 进不了 wasm32，白箱形态会死）+ 诊断主权
  （E 码/中文修复建议/子集裁决是引擎卖点，CSxxxx 标准诊断替代不了）。Roslyn 固定在
  防线侧（golden 生成）与消费侧（SharpTutor 编辑器波浪线/补全），与引擎互补。
- 动态语言 variant VM / Python 前端（前序评估已裁：赛道有霸主、无锚定客户）
- ORC/所有权模型降解（C# 心智模型是"引用"，所有权是额外概念负担）

## 2. 核心设计裁决

| # | 裁决 | 内容 |
|---|------|------|
| D1 | 语言标识单源化 | `SourceLang` 二元 enum 替代布尔穿透（砍 C++ 后无第三元）；MoonBit 侧 lang 与 ErrorCode 同包，由码的构造方式直接携带 |
| D2 | 对象模型 | 引用类型 = 堆分配 + 引用即 u32 指针 + **ARC 确定性回收**（见 §3）——**原生设计不借道 C++**（C++ 栈对象 RAII 与 C# 引用类型是两个语义世界，砍 C++ 后无"照搬多 Pass"包袱：类注册 → 字段布局（引用字段标 ARC）→ 方法签名（无 C++ 重载 mangling 全族，`vitro/engine/names` 产名族机制复用、规则简一档）→ this 即引用） |
| D3 | 子集边界 | 以 SharpTutor ch01–04 课程裁剪（§5），第一版明确不做 LINQ/委托/属性/异常以外的高级特性 |
| D4 | 错误码 | **E5xxx 新段**维持原裁；**E4xxx 冻结不重映射**（砍 C++ 后 tempted 把 E4 段让给 C#——不做：码表 versioned 只增不改 + MoonBit diag 137 臂照搬自 Rust（实测 38 个 E4 码位在 `error_code_gen.mbt`，分布两段：E4001–E4031 + E4100–E4106——2026-09-21 审阅勘误，原文"E4001~E4038"连续段写法失真，E4032–E4038 不存在），重语义化破坏照搬对拍。E4xxx 保哑臂（C 语料永不触发、对拍无害），语义冻结登记进 S8 差异台账 |
| D5 | 诊断管线 | **机制复用、数据表分语言**：TraceAnalyzer/误区模式/概念图/学习路径的机制（滑窗计数、图激活、路径组装）语言无关，C# 换错误码表 + 模式表 + 第二张概念图 |
| D6 | StepCollector 参数化 | C 硬编码两处（`collect_pointer_snapshots` 的线性内存假设、`infer_semantic_label` 的 C 库函数文本启发）按 `SourceLang` 分派；C# 模式下指针快照语义变为**引用快照**（schema 只增） |

## 3. ARC：引用类型生命周期（替代 GC）

**裁决**：GC 不是教学内容，降解为 **ARC 确定性模型**——引用类型堆分配，region 元数据挂
`refcount: u32`，赋值/传参/返回/作用域退出/字段与集合元素覆盖时插 release/retain 对，
计数归零立即释放。

**实现要点**（MoonBit 载体形态）：
- Retain/Release 走 `CallHost(RETAIN/RELEASE)` 两个新 host id，**零新 opcode**（参数走
  操作数栈传 u32 地址，既有 host func 约定）；
- 插桩点由 csharp/typeck 按静态类型判定，落点为 **S5 codegen 的作用域化槽位池**
  （LIFO acquire/release + 重复占用断言——codegen 勘察的必做项，砍 C++ 后无
  `cpp/raii.rs` 形态可照搬也不需要：C++ RAII 要处理"任意用户析构函数跑在退出
  路径上"，ARC 只插 retain/release 指令对，无用户代码在退出路径，复杂度低一档）；
- `refcount` 随 `MemorySnapshot.regions` 自动序列化——**S6 vm 的 region 表 v1 设计
  即含 refcount 字段**（时间旅行免费安全，非事后扩快照结构）；
- 与真实 .NET 对象头的计数位置差异不可观测（子集无 unsafe、无 `sizeof(class)`）。

**为什么成立**：
1. 行为对齐问题被子集边界消解——子集不支持 `GC.Collect`/`WeakReference`/Finalizer/
   `IDisposable` 模式，ARC 与 tracing GC 的差异在 **stdout 通道不可观测**，shadow 防线
   照常（golden 由 dotnet 生成，逐字节一致）；
2. "不回收"方案有真实撞墙风险：1MB 堆区约 900KB，密集 new 循环 3~5 万次即 trap，
   会制造假教学错误（真实 .NET 不会）；
3. 白箱增值：计数变化实时可见 = "值类型 vs 引用类型赋值语义"（C# 教学头号难点）的
   可视化，.NET 真实 GC 反而给不了。

**循环引用**：ARC 下永不释放 → 泄漏报告抓出 + E5xxx 教学卡（"这是 ARC 学习点不是错误，
真实 .NET 的 GC 会回收"）。双向链表类用例配专门话术。

**诚实记录（进 C# 子集 spec）**："引用类型生命周期采用 ARC 确定性模型降解；与 .NET
tracing GC 的差异在子集输出通道不可观测；内存面板展示 ARC 模型；循环引用为 ARC 特有
教学点。"ARC 的机制层（region 表 + refcount + 确定性释放）未来可反哺 C 侧别名教学。

## 4. 异常设计（核心章节，教材高频特性，不裁）

《C# 本质论》自第 5 章起随手使用 `try/catch/finally/throw`，防御式编程（`throw new
ArgumentException`）本身是教学内容。且**栈展开逐帧动画是 C 侧结构上做不出来的独家白箱
画面**。

### 4.1 字节码层：显式 handler 栈（不用异常表）

真实 CLR 用异常表 + zero-cost 展开，教学子集不用——范围查询复杂、白箱不可见。新增
3 个 opcode：

```
TryBegin <handler_idx>   ; 压入 handler frame
TryEnd                   ; 弹出 handler frame（正常离开 try 范围）
Throw                    ; 抛出：栈顶是异常对象引用
```

VM 新增执行状态：
- **handler 栈**：`Vec<HandlerFrame { catch_ip, frame_idx, stack_depth, mem_stack_top }>`。
  `Throw` 时恢复三项并跳 `catch_ip`，try 块内中间计算值自然作废；
- **当前异常寄存器**：异常对象引用。catch 变量 `catch (Exception e)` 即存入局部变量
  （走 ARC +1）。

catch 匹配按类型链：内置异常族（约 7 个）硬编码继承链，用户自定义异常类查声明链。
多 catch 自上而下、`e.Message` 读取均为普通字节码。

### 4.2 跨函数展开：UNWINDING 状态机 + 逐帧 step

`Throw` 时当前帧无 handler → 进入 **UNWINDING**：逐帧弹出 `call_stack`，每帧批量
release 局部引用（见 4.6）、执行该帧未完成的 finally 块，向上一帧。
**每弹一帧 / 执行一个 finally 块 = 一个 VM step**（行为契约，见 §6-B）。由此直接获得：
时间旅行进度条上展开是平滑可 seek 区间、`call_stack` 逐帧缩短驱动栈展开动画、实现是
普通指令流。

finally 的正常路径语义（return/break/continue 穿过 try 块时执行）由 csharp/codegen
在控制流出口插桩（落 S5 槽位池的控制流出口机制——Rust 侧该形态由 `cpp/raii.rs`
演化而来，MoonBit 侧无此包袱、按 C# 语义直接设计）。finally 内抛新异常覆盖旧异常
按 .NET 自然语义。

### 4.3 内置异常映射：现有 trap 转 throw

| 教材场景 | C 侧行为 | C# 侧行为 |
|---|---|---|
| 整数除零 | trap + 教学诊断 | `DivideByZeroException` |
| 数组越界 | `TrapBounds` trap | `IndexOutOfRangeException` |
| 空指针解引用 | NULL trap | `NullReferenceException` |
| `int.Parse("abc")` | atoi 静默 | `FormatException` |
| `throw new ...` | — | 显式 Throw |

实现落点在 **codegen 层**（C# 模式的检查生成 Throw 序列而非 trap 指令），VM trap 语义
本身不动——C 侧 636 golden 与检测语义零影响。

**未捕获 = trap，含过渡语义**：传播出 `main` → 程序终止，trap 消息 .NET 风格
（`Unhandled Exception: System.DivideByZeroException: ...`）。**CS3a 阶段（无跨帧展开）
Throw 遇当前帧无 handler 时直接 trap**，消息格式与 `error_code` 与最终一致——
CS3b 只把"立即死"改为"逐帧展开后死"，消费端判分契约（`run_json` status 三态 +
`trap.error_code`）两段之间零变化。

**shadow 口径**：判分用例一律 catch 后输出（SharpTutor fixtures 编写规范）；未捕获
异常的终止输出中**栈轨迹部分与 dotnet 不逐字节一致**（简化轨迹），golden 比对只对
message 前缀。进诚实记录。

### 4.4 `throw;` 与 `throw e;`：轨迹保留差异（教材考点，随 CS3a）

`throw;` 保留原始栈轨迹 vs `throw e;` 重置——《本质论》明确警告后者的经典陷阱题。
实现：异常对象挂"原始抛点"字段，`throw;` 不改写、`throw e;` 改写为当前点，未捕获
终态消息展示原始抛点行号。增量 = 一个字段 + Throw 双形态判别。`throw;` 帧内形态随
CS3a（当前异常寄存器与嵌套 try 的外层 handler 在 CS3a 即工作），CS3b 自然获得跨帧
重抛。

### 4.5 × 时间旅行：最深技术点

handler 栈进 `VMSnapshot`（新字段）。**UNWINDING 中间态也是可快照状态**：须记录
"当前异常寄存器 + 剩余待展开帧 + 目标 handler"，否则 seek 落在展开区间中间恢复出
撕裂状态。CS3b 显式设计 + 快照往返测试（展开中间态 snapshot → restore → 继续展开
到同一终态）。异常对象在堆上由 `MemorySnapshot` 自然随行。

### 4.6 × ARC：展开清理复用帧退出清理机制

展开弹帧时被弹帧的引用类型局部变量逐个 release——落点为函数表的"帧退出清理列表"
机制（S6 vm 按此 v1 设计：Rust 侧该列表由 C++ RAII 历史演化而来，MoonBit 侧直接
以"ARC release 动作"为一等 citizens 设计，同一列表机制、动作只有 release）。
异常对象由当前异常寄存器持有（+1），catch 结束 -1。零新机制。

### 4.7 × JIT

JIT 倾向不搬（总计划 F-3，S9 复核）——若复活，**含 `TryBegin` 的函数排除出 trace
编译**为既定行为契约（`contracts.rs::try_excludes_jit` 条目已落，迁移随 S7 protocol/
unified 包平移），与"含断点的循环排除"同一模式。教学程序性能无感。

## 5. 子集口径 v1（待 SharpTutor 红线清单回填）

**支持**：值类型（struct 按值语义，栈分配）/ class（字段/方法/构造/this/静态成员——
**C# 语义原生多 Pass**：类注册 → 字段布局（引用字段标 ARC）→ 方法签名 → this 即
引用；内部名走 `vitro/engine/names` 产名族机制（`ctor_def_name`/`method_mangled_name`
等 API 现成，C# 规则比 C++ 简一档：无模板实参嵌套/命名空间，重载消歧够用））/
继承 + 虚函数（虚表 + `CallPtr`——机制层与 C++ 殊途同归，语义层无 C++ 包袱：无
多重继承/虚继承/纯虚函数声明歧义，单继承 + 隐藏方法 new 关键字按子集裁）/ 数组 /
foreach / `List<T>`、`Dictionary<K,V>`（**BCL 数据驱动**：类型面为内建泛型类型
——非用户模板实例化，自定义泛型 D3 已裁；实现走 host func/bytecode 库 + JSON
接口声明唯一真相来源（Phase 41 机制遗产保留，数据文件换 BCL 签名，落
`vitro/engine/containers` JSON 数据驱动包——dotnet oracle 下它们是真 BCL 类型，
**不走 vitro_vec 式内置容器路线**（4 例 clang_compile_fail 的教训）））/
try-catch-finally-throw / 7 个内置异常 / `e.Message` / 自定义异常类 / `throw;` /
`Console.WriteLine/ReadLine`（host func 映射）。

**裁剪**：`when` 过滤器、checked/`OverflowException`、async、委托/事件、属性语法糖、
LINQ、自定义泛型、`IDisposable`/using 模式、Finalizer、`WeakReference`、`GC.Collect`、
`unsafe`、`decimal`、多文件工程、运算符重载。

**语料画像（2026-09-12 实测，SharpTutor `CourseData`，贡献方确认全量贡献）**：
13 章 521 个 `.cs`，每课自带 `solution.cs` / `exercise.cs` / `expected.txt`
（dotnet golden 已存在）/ `fixtures.json`（**多 fixture**：同一程序多组
stdin→expected，如 alg01 三组判分）。章节→批次映射：ch01–04（78 文件）= CS1
验收面；ch05–06（63）= CS2；ch07（45）= CS4；ch08 LINQ / ch10 Assembly /
ch13 WPF = 裁剪区；ch12_AlgoBank（153，多 fixture 算法库）= CS6 同族。

**ch01–04 特性画像（红线清单的事实底座）**：顶层语句 **100%**（全语料亦然——
无 Main，入口合成是 CS1 硬需求）；`int.Parse/TryParse` 24%、`Console.ReadLine`
23%、表达式体方法 17%、`var` 11%、try/catch 8%（这 7 个用例归 CS3a）、插值 6%、
class 5%、foreach 3%、List 1%、继承 0%（ch05 起）。§5 草案据此修订：
+顶层语句（入口合成）、+表达式体方法、+`var`、**+字符串插值（基础形态：
变量/表达式插值，随 CS1）**——6% 用量看似低，但它是 ch02 的教学主特性、C# 的
签名级语法，教材自第 2 章起随手使用；格式化说明符裁定见下（随 CS4，invariant
固定）。`Convert.` 待红线裁决。

**字符串插值裁定（2026-09-20 下游评审定稿，分层定核）**：语法层（lexer 切分，无争议）
→ **语义核 = format host func**（逐 hole append、invariant 固定）→ 库糖（`string.Format`
CS4+ 委托同一 host func）。五条依据：① 库面依赖倒挂——`string.Format` 显式调用不在
CS1 特性画像，为 6% 语法糖实现整套格式迷你语言 + object[] 装箱 + culture 参数面是
尾巴摇狗，host func 只需一个入口；② 零装箱——CS1 值模型只有值类型，string.Format
形态意味着为单一特性引入装箱，host func 走既有"签名真相源单表"纪律不添第四个格式化
实现面；③ 步进教学（heron M3/V 硬需求）——降级成逐 hole 的 `format_value(v)` +
concat 序列，每个 hole 一帧时间旅行可见（插值恰是"让学生看见每段先求值再拼接"的
特性），string.Format 形态是单步黑盒；④ **`:F2` 边界被结构性封死**——host func 内
固定 invariant，culture 在 CS1 API 面上不存在，"后置"不是暂不实现而是无处存在，
CS4+ 裁定只动 host func 可选第二参数、降级形态零返工；⑤ 诊断保真——各 hole 独立
精确 span，运行期错误直指 hole；且 .NET 6+ Roslyn 真实降级即
`DefaultInterpolatedStringHandler` 逐段 Append，形态反而贴近真实编译器。

**语料实证两修正（随本裁定写入）**：① 格式说明符"后置 CS4 之后"有时间冲突——
全语料 3 处中 2 处在 ch07（= CS4 验收面）：`c03_string.cs` 的 `{ratio:P1}`（百分比，
文化敏感度高于 F：百分号位置 + 小数点）、`c12_format.cs` 的 `{pi:F3}`——**裁"格式
化说明符随 CS4 落地（invariant 固定）"**（ch07 45 文件验收面不裁减；invariant 下
P1/F3 实现面仅 host func 格式化分支；`{ratio:P1}` 兼作 invariant 生效的红→绿锚：
culture 环境下 dotnet golden 与 vitro 逐字节一致即证据）；π ≈ 非 ASCII 字面量——
**编码契约接 `vitro/engine/source` 单源**：源文件与引擎内部一律 UTF-8 字节流（与
column = 字节偏移+1 契约同源），UTF-16 只存在于 host func 边界转换点（Console 输出/
`e.Message`）；Roslyn oracle 的 span 为 UTF-16 码元口径，E1 对拍归一层做一次
码元→字节转译并登记。② 对齐 `,N` 全语料零命中——CS1 语法面**明确拒绝 + 专用诊断**
（E5xxx 一条 + 红→绿锚；拒绝而非静默忽略——静默忽略是 shadow 假 match 温床）。

**词法层锚（下游附加要求，CS1 验收面）**：每 hole 独立精确 span（诊断与步进定位
前提）；hole 内字符串字面量花括号配平边界（`$"{"}"}"` 类）进 lexer 红→绿锚；
`$"""` raw 插值字符串写明非目标；**文化感知归宿写死**——将来若开只以显式 session
config 形态（默认 invariant、**判分模式强制 invariant**，与 `deterministic:true`
同纪律）进 DIFF 台账一条，判分强制这条升格为行为契约（`contracts.rs`/MoonBit
unified 包同表，与 `unwinding_step_granularity` 并列——判分可复现性前提，tripwire
级保护）；`double→string` 最短往返差异（C# ToString 打 `0.3`、printf `%f` 打
`0.300000`）登记诚实记录，`format_value` 为唯一落点——**该差异同时进 C 侧诚实
记录**（printf `%f` 与最短往返表示的固有差异，C 教学同遇）。

**语料格局（2026-09-20 定稿）**：

| 语料 | 形态 | 处置 | 防线角色 | oracle |
|---|---|---|---|---|
| SharpTutor CourseData 13 章 521 `.cs` | 课程程序，子集内，76 golden + 多 fixture | **入库**（授权链：2026-09-12 全量贡献确认；入库 PR 带贡献条款注记——版权归贡献方、授权范围写明，避免 MIT 默认条款覆盖语料） | 运行时 shadow 主语料 + E1–E4 静态对拍 | dotnet（运行时 golden，版本钉死）+ Roslyn（静态） |
| TheAlgorithms/C-Sharp（605 `.cs` / 2.9 万行，本地 `C-Sharp-master`） | 真实世界**类库**：零 Main、xUnit 测试项目、特性面超子集（泛型 29 文件/属性 58/表达式体 89/yield 55/LINQ 11） | **外置不入库**（GPL3 三红线同 C-master：路径不入库/golden 不入库/报告只引文件名与统计） | **静态边界语料**——token/AST/诊断解析面差分 + 子集外特性（泛型/属性/yield/LINQ）**拒绝面回归**（605 文件每个超集构造都是"必须明确诊断而非静默错解析"的锚） | Roslyn（防线侧，不进引擎） |

由此 C# 侧形成**双 oracle 格局**：dotnet 管运行时行为（"clang 之于 C shadow"）、
Roslyn 管静态解析面（token 流/诊断序列/AST 形态）——两者都在防线侧，与"Roslyn
不进引擎"裁决无冲突。

**诊断管线 C# 数据表**（CS5）：误区模式首批 = 空 catch 吞异常、`catch (Exception)` 过宽、
finally 里 return、`==` vs `Equals`、可变列表别名、循环边界 off-by-one 的 C# 表述
（`<=` 配 `arr.Length`）、`List<T>` 容量与 Count 混用、foreach 中修改集合、字符串不可变
性误解（`s.Replace` 非原地）。概念图加异常域节点（栈展开/异常层次/try-catch-finally
顺序）。

## 6. 协议增量（schema v0.1 预留位 + 行为契约）

**A 档：StepPayload 增量字段（四项，随 v0.1 冻结以预留位写入
`spec/STEP_PAYLOAD_SCHEMA_V0_1.md`，CS3b 激活）**：
1. `handler_depth: int`——"当前受几层 try 保护"直读；
2. `unwinding: bool` + `unwind_frames_left: int`——展开态显式标记 + 剩余帧数，
   展开动画驱动字段；
3. `current_exception: {type_name, message, addr, origin_line} | null`——当前异常
   寄存器可见；`addr`（u32 堆地址）联动内存面板 region 高亮（ARC 教学闭环）；
   `origin_line`（原始抛点行号，2026-09-12 评审补充）——`throw;` 保留 /
   `throw e;` 改写（§4.4），知识卡片"原始抛点在第 X 行"结构化直读本字段，
   不解析 trap message 文本。

**B 档：词汇契约**：
- 行为契约：**"UNWINDING 每帧一 step，展开不可被合并成单步"**（与"JIT 断点完整性"
  同列行为契约清单，防未来性能优化毁掉展开动画）——**已落代码**：
  `unified/contracts.rs::BEHAVIOR_CONTRACTS` 条目 `unwinding_step_granularity` +
  可执行判据 `check_unwinding_granularity`（schema §9.3）；
- 行为契约：**含 `TryBegin` 的函数排除 JIT trace**（同表条目 `try_excludes_jit`）；
- `semantic_label` 词汇表补异常域条目（"抛出 IndexOutOfRangeException"/"展开弹出
  Main 帧"/"执行 finally 块"/"捕获 DivideByZeroException"）并进 schema 附录，
  **词汇即契约，消费端 UI 直读不做推断**。
  ——此项同时是重构计划 R3"教学标注双来源"的收口方案：`semantic_label` 从自由文本
  启发升级为受控词汇表枚举，`collector.rs` 的启发逻辑降为词汇表映射函数。
  **2026-09-12 落地**：schema 附录 B + `unified/vocabulary.rs` 单源 + serve
  `semantic_labels` 出口 + 词汇闭包防线（SharpTutor S4 §6 异常域首批 4 条以
  `reserved` 状态预先登记，激活即"契约兑现"而非"新增契约"）。

**C 档：schema 签字回放场景第四组**（前三组：防抖编译流/判分流/单步+seek+内存查询
交错流）：**异常交错流**——throw → 逐帧展开 → catch → 再 throw → finally 内 return，
l07 形态真实课程代码。

## 7. 批次计划与触发时序（v4：MoonBit 载体重排）

**时序锚（2026-09-20 v4 重排——执行载体由 Rust crate 改为 MoonBit workspace，砍 C++ 裁定后前置归位）**：
- **CS0 可与 S7 并行**（纯内部：SourceLang 二元 + lang 携带 + `"main.c"` 兜底按
  扩展名——落 MoonBit diag/入口包）；
- **S5 codegen（作用域化槽位池 LIFO + 布局规划器）为 CS1/CS2 硬前置**——ARC 插桩
  压在显式 acquire/release 槽位池上（codegen 勘察必做项，原 U3 槽位手术由 S5 目标
  架构直接实现，**不再是独立前置批次**）；
- **S6 vm（三执行状态 + region refcount，见总计划包图 L7）为 CS3/CS4 硬前置**——
  handler 栈/异常寄存器/UNWINDING 是 v1 设计输入非事后补丁；
- **原"S3（C++ 收口）为 CS2/CS3 双重硬前置"作废**——砍 C++ 裁定（2026-09-20）后：
  模板手术消失、C++ 寄生收口由零迁移天然完成、CS2 语义参考保留在 Rust oracle
  冻结区（Phase 32/33 实现思路可查，"垫脚石"损失已裁定可接受）；
- S8 差异台账收编：E4xxx 语义冻结、编码口径转译、`double→string` 往返差异三条
  随各批次进账。

**触发/验收前提**：对应 S 批次验收线保持（shadow 逐项一致 / moon test 全绿 /
typeck_diff 四目录 PASS / facts 漂移 0）。

**中止与改判判据（v4 修订，2026-09-12 v1.2 吸收沿用）**：① **R5 判据直接约束 CS
批次——计时对象换 MoonBit S5 新结构**（单遍 codegen + LIFO 槽位池；Rust 侧旧结构
的观察窗不继承，S5 交付起算）：C# 引入（CS2/CS3）后 3 个月内因该结构产生 ≥3 起
合法性缺陷（误拒合法代码或静默错值）→ 结构本身进重判；② 中止条件——任何阶段发现
P0 级新事故（GB 级资源事故/静默错值扩散到核心语义）→ 立即冻结该阶段按事故归档
制度留痕；③ CS 批次缺陷须按"缺设计 vs 缺补丁"归因入台账（R5 的判定输入），嵌入
CS2 起的批次验收。

| 批次 | 内容 | 关键验收 |
|------|------|---------|
| **CS0** | `SourceLang { C, CSharp }` 二元 + 语言分派单源化 + `"main.c"` 兜底按扩展名（可与 S7 并行） | 全防线绿 |
| **CS1** | `vitro/engine/csharp/{lexer,parser}` 骨架 + 薄 typeck/降级 codegen，Hello World + 值类型 + **插值基础形态（format host func 语义核 + 逐 hole span + 词法锚四条，§5 裁定）**；SharpTutor CourseData 语料**入库**（计数见 §5 语料画像；含贡献条款注记） | C# 判分小集（SharpTutor dotnet golden）；**验收面 = ch01–04 课程代码**；C-Sharp-master 静态边界语料接入（Roslyn 防线侧 oracle，拒绝面回归） |
| **CS2** | class/方法/构造/this/静态 + 继承虚函数 + ARC（§3 全部；names 产名族复用） | **预览版交付点**：白箱跑算法 + ARC 别名可视化，SharpTutor 透视模式试用（de-risk CS3 投入） |
| **CS3a** | 3 opcode（**44/45/46 进空号**）+ handler 栈 + finally 插桩 + 内置异常映射 + `throw;`（含 §4.4）+ handler 栈快照 | 帧内 try/catch/finally/throw 全用例；除零/越界/空引用可捕获；无 handler 即 trap（契约稳定） |
| **CS3b** | UNWINDING 状态机 + 跨帧展开 + 展开清理（§4.6）+ 展开中间态快照/seek 往返 | 第四组回放场景；栈展开动画字段（A 档）激活；展开中间态往返测试 |
| **CS4** | 数组/foreach/List/Dictionary（越界→可捕获异常接 CS3a 通路；BCL 数据驱动，containers JSON）+ **格式化说明符随批（P1/F3，invariant 固定，ch07 两文件为红→绿锚）** | 容器用例 + ch07 格式说明符用例（culture 环境下 golden 逐字节一致） |
| **CS5** | E5xxx + catalog 语言字段 + semantic_label 词汇表化（**R3 收口项落地**）+ TraceAnalyzer 异常类目 + C# 误区/概念表 + **G9 算法验证**（`validation.rs` 语言中立层，41 模板元数据为基础） | 认知管线 C/C# 双语出山（首次接线外部消费者） |
| **CS6** | 算法标注审计平移（`AlgorithmContext` trait 解耦良好，41 个 infer 函数逐个审 C 文本模式）+ LeetCode C# 批次 | **differential 双语言标注一致性**（同题 C/C# 解法的算法名/phase/置信度一致，用例集 SharpTutor 提供） |

量级参考：CS1 对标 E2（~2.5k 含测试）；CS3（a+b 合计）约 2~3k 含测试，快照状态机
是大头。

## 8. 双方分工与对等承诺（SharpTutor 评审确认）

**上游（本仓库）**：引擎、管线、协议、防线。

**SharpTutor**：
1. **C# 语料全量贡献**（2026-09-12 确认，本地镜像 `D:\code\SharpTutor`）：
   CourseData 13 章 521 个 `.cs` + 76 个 `expected.txt` golden + `fixtures.json`
   多 fixture 清单。**shadow 驱动与 golden 生成管线归本仓库**（2026-09-12 修订，
   原"golden 由其生成"调整为"语料由其贡献、管线/门禁归引擎仓库"——防线自服务
   与复现性要求 dotnet 版本钉死、用例改动自刷新 golden；跨仓库供货会复刻
   G10/G12 类漂移。dotnet 之于 C# shadow = clang 之于 C shadow，都是外部参考
   实现）；
2. **转译器再定位**：Roslyn 转译器从"替代路线"降为 **CS1/CS2 期间参考实现**（转译
   产物 = 子集用法活文档）+ 原生前端未覆盖特性的快速通道；CS0 前作为需求验证工具
   产出透视模式使用数据；
3. **CS1 验收面**：ch01–04 课程代码即子集用法测试集；
4. **红线清单 C# 版**：子集口径确定后 48 小时内交付（同 C 侧机制），含"判分用例一律
   catch"规范。

## 9. 教学增值（组合画面承诺样例）

学生写的冒泡排序第 3 轮把交换条件写反 → `algorithm_step` 识别"冒泡排序，phase=交换"
但结果序列错误 → TraceAnalyzer 误区模式命中"交换方向反了" → 知识卡"比较的是
arr[j] > arr[j+1]，你想升序还是降序？" → seek 回交换发生的那一步看变量。
——这条链每一环的协议字段已存在或已列入 §6-A 档，C# 立项使它对 C# 代码同样成立。
另：**栈展开逐帧动画**（异常从第 3 层抛出 → 逐帧弹出 → finally → catch 接住）为
C# 白箱独有画面。

## 10. 诚实记录预设（进未来 CS_SUBSET_SPEC）

1. ARC 降解差异（§3 引文）；
2. 未捕获异常终止输出的轨迹简化（§4.3）；
3. `throw;`/`throw e;` 轨迹保留语义按"原始抛点字段"口径实现，与 .NET 完整栈轨迹
   不同（简化轨迹 + 原始抛点行号）；
4. `refcount` 位于 region 侧表而非对象内存（对子集不可观测，记录实现口径）；
5. C# 基础数值类型（`int` 32 位 / `long` 64 位 / `double` IEEE）与引擎现有模型对齐，
   无精度差异；`decimal` 不支持（§5 裁剪）。

## 11. 状态记录

- **2026-09-20 v4 重设计（砍 C++ 裁定联动，本轮全部落档）**：上游拍板**砍 C++**
  （总计划 F-2 裁定：零迁移、Rust oracle 保留为语义参考、C++ 防线退役归档）——本
  计划随之四项重设计：① **载体改 MoonBit 四包** `vitro/engine/csharp/{lexer,parser,
  typeck,codegen}`（CS 批排 S6 后；共享切线 = 表达式/语句层共享、声明层分叉）；
  ② **类模型原生设计**——"照搬 C++ 多 Pass（类布局注册→this 注入→mangled C 函数）"
  全部换 C# 语义原生流程（D2），names 产名族机制复用、规则简一档；③ **VM 面
  前置**——handler 栈/异常寄存器/UNWINDING + region refcount 进 S6 v1 设计（总计划
  包图 L7），opcode 44/45/46 进空号；④ **时序重排**——S5 槽位池/S6 vm 为 CS 硬前置，
  原"S3 C++ 收口 + U3 手术"前置作废归位，R5 计时对象换 S5 新结构。**插值裁定
  （下游评审定稿）**：format host func 语义核（逐 hole append、invariant 固定），
  string.Format 降位 CS4+ 库糖——五条依据与语料实证两修正见 §5（格式说明符改
  **随 CS4**（ch07 两文件为红→绿锚）；对齐 `,N` 零命中明确拒绝 + 专用诊断）。
  **语料格局定稿**：SharpTutor 521 文件**入库**（贡献条款注记随入库 PR）；TheAlgorithms/
  C-Sharp（605 文件，纯类库零 Main、GPL3）**外置**做静态边界语料（Roslyn 防线侧
  oracle，拒绝面回归）——C# 双 oracle 格局：dotnet（运行时）+ Roslyn（静态）。
  **E4xxx 冻结不重映射**（实测 38 码位保哑臂，语义进 S8 台账），E5xxx 维持新段。
  编码契约：源文件与引擎内部一律 UTF-8（接 `vitro/engine/source` 单源），UTF-16
  仅存 host func 边界，Roslyn span 归一时码元→字节转译登记。
- **2026-09-11 v3 定稿**：吸收 SharpTutor 消费侧评审——三点决策答复（`throw;` 保留并
  连带轨迹考点进 CS3a；输出契约确认判分器依赖 `run_json` 三态 + `error_code`；
  CS3 拆 a/b 两段独立验收）；A 档三字段 + `addr` 微增，以 v0.1 预留位随 Phase 1
  冻结写入（待办：编辑 `spec/STEP_PAYLOAD_SCHEMA_V0_1.md`）；B 档词汇表契约确认为
  R3 收口方案；第四组回放场景进签字材料；G9 排期确认（CS5）；ARC 裁决（替代早期
  "计数只做可视化"方案）；Roslyn 定位（防线 golden + 编辑器诊断，不进引擎）。
- **前置待办（2026-09-12 全部清账）**：① ✅ 定位扩展已同步进
  `后端定位与白箱计划.md` §2；② ✅ schema v0.1 预留位已写入
  `spec/STEP_PAYLOAD_SCHEMA_V0_1.md` §7.x（四字段 + 消费方容忍要求）；③ ✅
  重构计划全批次交付完毕（R1→E1→R2→E2→R3→E3→R4，最终 CI 全绿 968a408）。
- **语料调研完成（2026-09-12）**：CourseData 全量摸底（13 章 521 文件 / 76
  golden / 多 fixture 清单），章节→批次映射与 ch01–04 特性画像已录入 §5；
  **新增 CS1 硬需求**：顶层语句入口合成（语料 100% 无 Main，§5 草案未覆盖）。
- **评审吸收（2026-09-12）**：① §6-A `current_exception` 补 `origin_line`
  结构化字段位（原始抛点行号，`throw;`/`throw e;` 轨迹考点的知识卡片直读，
  不解析 trap 文本）；② 字符串插值基础形态（变量/表达式）纳入 CS1，格式化
  说明符后置 CS4 后裁。
- **schema v0.1 签字回放完成（2026-09-12）**：S1–S5 对端材料采纳回放
  **61/61 PASS**（驱动 `scripts/replay/replay_s1_s5.go`，D5 迁移后），暴露并修复五个引擎
  缺陷（越窗 seek 负下标无限分配/锚点裁剪/重放区间排他/断点双层暂停/入口步
  误标递归）。**v0.1 冻结的最后一道检查已过**，S4 激活契约表就位（CS3b 交付后
  以同序列回放 §5 断言）。**CS0 可以开工**。
- **CS0~CS6 待启动**：CS0 不依赖外部（纯内部重构）；CS1 起语料经红线清单裁定
  后接入，`shadow_verify_csharp.py` 最小版随 CS1 落地（dotnet 版本钉死，
  缺失即 fail-fast，与 clang 缺失同口径）。
- **v0.2 激活轨道落地（2026-09-12，响应 SharpTutor 需求清单 B2）**：§6-A/B 的共识
  已固化为**上游测试位**而非文档承诺：
  - schema 新增 **§9「v0.2 激活轨道」**（激活清单五条 + 字段台账 + 行为契约表）与
    **附录 B「`semantic_label` 受控词汇表」**（C 域 10 条 active + 异常域 4 条 reserved）；
    **v0.1 正式冻结**（S1–S5 61/61）；
  - 代码单源 `native/src/unified/contracts.rs`（预留位字段名 / 激活清单 / 字段台账 /
    行为契约）与 `native/src/unified/vocabulary.rs`（词汇表 + `classify()`）；
    出口 serve `contracts` / `semantic_labels`，`capabilities` 增 `schema` 与
    `behavior_contracts`；
  - **激活 tripwire**：预留位字段一出现在任何 payload（含嵌套）即让冻结测试失败并打印
    激活清单——CS3b 落地时不可能"忘记重跑 C1–C3/S1–S5 或忘记更新 §7 校验表"；
  - **`UNWINDING 不得合并单步`**（§6-B 行为契约）有了可执行判据
    `contracts::check_unwinding_granularity`（下降幅度 ≤ 1；`finally` 步可持平），
    S4 §5 A2/A5 回放将直接复用；
  - **CS5 的 R3 收口项已提前半步**：`collector.rs` 的启发逻辑现已受词汇闭包测试约束
    （产出未登记标签即失败），CS5 只需把启发降为"词汇表映射函数"。
- **三语化整备吸收（2026-09-12，整备计划 v1.1）**：[`三语化整备审计计划.md`](../../07-质量与裁定
  裁定——10591ad 泄漏事故（63.6GB / 页面文件 33.9GB）及复发的根因实锤（seek 正向重放
  无界收集，与负下标同管道两洞堵一），**统一模式子系统升级为重构区**；本计划 §7 已同步
  硬前置（S0/S1 → CS0；S2/S2.5/S3 → CS2 与 CS3）。本计划的架构裁决（ARC / 异常 /
  词汇契约）不变。
