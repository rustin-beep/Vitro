# WASI 拓展面设计单——沙箱能力授权制与 C 脚本/裁判形态

> **as_of 2026-11-05** · 纯设计批（不写引擎代码，`moonbit/` 零改动）· 措辞三档：**〔已验证〕**=本会话亲读代码/亲读仓内文档（行号在手）；**〔推断〕**=由已验证事实外推；**〔未覆盖〕**=显式留白。
> **状态：设计完成，待用户拍板。** 本设计依赖 [核载体迁移设计单](核载体迁移设计单——153码表wasm子集实体化.md)（下称 REHOST）批 1 落地——wasm 发射器（`moonbit/wasmenc/`，批 1a 在途〔已验证，工作区已有 emit/fold/templates 等件〕）产出真 wasm 载体后，WASI 面才有挂靠点。
> **并入注记（2026-11-17）**：本文档自设计分支并入主线时补——REHOST 批 1–4 已落（#505/#526，含 dispatch-loop 与 V8/wasmtime 三方对拍闸）；WASI 期 0 骨架已落（#492 `script` 子命令 argv/shebang/exit 透传）。设计本体未改动，拍板状态不变。
> 命题语境（用户拍板）：vitro 本质是沙箱（VFS 内存态 / 无进程 / 无真文件 / 无 env），判定型脚本与对拍裁判因此全用 `.mts`，C 不可作脚本（issue #274「C 当裁判」废案为证）。**wat+拓展集是可能突破的方向**：拓展集增加 WASI 式系统指令面，宿主侧（native 直链壳 / V8 影子）实现——沙箱边界从全封闭变为**能力授权制**（教学态默认全沙箱零影响；脚本态显式开面）。

---

## 0. 一句话架构

**H3 系统通道**（与 H2 host ABI 并列的第二个 import：`env.vitro_syscall(op, args_ptr) -> i64`）承载 WASI preview1 子集 + 非 WASI 标准的进程面自定义指令；**import 的存在性即能力开关**（教学产物不 import H3 ⇒ 零指令面、防线零变化；脚本产物 import H3 ⇒ 宿主按授权模型供给）；**宿主双实现**（native 直链壳 C 实现 / V8 影子 JS 实现 / wasmtime 跑器 Rust 桩）；授权模型 = **产物级声明 ∩ 宿主级上限**，默认拒绝。

```
现有（全封闭沙箱）                     拓展后（能力授权制）
┌──────────────────────┐          ┌──────────────────────────────┐
│ C 程序（教学态）         │          │ C 脚本（脚本态，显式开面）        │
│  printf/scanf/fopen…   │          │  WASI 面：fd_write/path_open/  │
│  ↓ CallHost 110 路由    │          │   environ/proc_spawn(自定义)   │
│  ↓ H2: vitro_host_call │          │  ↓ H2（libc，不变）             │
│  ↓ VFS 内存态/输入状态机  │          │  ↓ H3: vitro_syscall（新）      │
│ 引擎=唯一真值源          │          │  ↓ 宿主实现：C 壳/V8 JS/Rust 桩  │
└──────────────────────┘          └──────────────────────────────┘
  无进程/无 env/无真文件/无网络          真文件/真进程/真 env（授权范围内）
```

---

## 1. 废案证据链：现有框架 C 脚本不可行的沙箱面完整盘点

> 逐面引代码行号（本会话亲读）；每面给「C 脚本要什么 vs 现状给什么」。

### 1.1 五面盘点表

| # | 沙箱面 | 现状代码证据〔已验证〕 | C 脚本需求 vs 现状 |
|---|---|---|---|
| 1 | **文件=VFS 内存态** | `moonbit/host/vfs.mbt:3-6`（头注「文件**元数据**在引擎侧；文件**数据**存 VM 堆〔区域名 `vfs:<name>`〕」）；分配走 `vfs_malloc_raw`（`vfs.mbt:164-172`，`register_alloc(..., "vfs", true)`）；预设文件仅宿主注入（`inject_preset_file`，`vfs.mbt:234-264`）；`list_files` = `vfs.list` 协议帧唯一定义点（`vfs.mbt:1002-1013`） | 脚本要读/写真文件（配置、语料、产物落盘）——现状 `fopen` 只开 VM 堆里的内存块，宿主不注册 include_reader 时连预设文件都没有；写出的数据随 VM 生命周期消失 |
| 2 | **无 env** | `moonbit/libc/unsupported_sig.mbt:22-23`：`getenv` 显式拒绝，注释原文「沙盒无环境面」——进 **E3073 类「已知不支持」诊断**（`unsupported_libc_sig` 表，typeck `check_user_func` 第四级消费），不是「未定义」而是「加原型也没用」 | 脚本要读环境变量（`PATH`、`VITRO_*` 配置）——现状类型面可过、语义面恒拒绝 |
| 3 | **无进程** | `unsupported_sig.mbt:24-25`：`system` 显式拒绝「沙盒禁系统命令」；host 114 名表全表无 spawn/fork/exec/popen 族（`moonbit/bytecode/host_func_id_gen.mbt` 亲读——全表仅 IO/libc 名）；放行名全集 175（`moonbit/libc/libc.mbt:555` 附近）同样无进程面 | 脚本要起子进程（调 clang、并行任务、管道消费）——现状唯一「系统」出口 `system()` 是显式排除项 |
| 4 | **无网络** | host 114 ∪ bytecode 88 ∮ 放行 175 三表〔已验证，`moonbit/AGENTS.md` L5/L6 行 + `route.mbt:41-54` 亲证〕无 socket/connect 族——**从未实现也从未声明**，与 env/进程的「显式拒绝」不同，网络是**名表空白**（学生引用 socket 头直接走 E3036 未定义路径） | 脚本形态 v1 **不开网络面**（见 §2.1 表尾——安全面收益/复杂度比不成立，留开放问题 O8） |
| 5 | **exit/argv/clock 的半开面**（对照：已有能力证明沙箱不是铁板一块） | exit：host 路由 38（`host_func_id_gen.mbt:58,381`）——但只影响 `// EXIT <ret>` 标记行（`moonbit/cmd/lib/cli/cli_run.mbt:8-11` 注释「进程码唯一消费方 = shell/agent」），不透传宿主 rc；argv：`vm/state.mbt:588 setup_argv` + CLI `--` 透传（`cli_run.mbt:34-36 RunArgs.argv_passthrough`）——**argv 面已工作**；clock：宿主注入 `gateway/gateway.mbt:96 set_clock_source`，未注册恒 0〔已验证，native 报告同证〕 | exit code 透传/argv 直用是**独立小改**（§3 映射表）——这一行证明「能力注入」在本仓有成熟先例（include_reader/clock 双先例，`gateway.mbt:87-98`） |

### 1.2 现役能力注入先例（本设计的机制母型）〔已验证〕

- `set_include_reader(read : (String) -> String?)`（`gateway/gateway.mbt:87`）：native 壳注册文件系统读取、wasm 臂不注册 ⇒ include 家族解析为 **E1021 not found 正当教学诊断**（`gateway.mbt:76-86` 头注原文「宿主注入文件表是将来扩展位」——**本设计单就是这个扩展位的兑现**）。
- `set_clock_source(f : () -> UInt64)`（`gateway.mbt:96`）：native 注册真墙钟、wasm 恒 0——同一引擎双宿主按「注册与否」分叉语义，**能力不存在 ≠ 故障**。
- 两条先例共同构成「宿主注入 = 能力授权」的母型：**未注册 = 能力不存在（教学诊断正当），注册 = 宿主自担语义**。WASI 面把这对偶从「编译期 include / 时钟」扩到「运行期文件/进程/env」。

### 1.3 #274 喂入式形态的边界（废案的精确表述）

issue #274（本会话亲读全文）的架构是「ts 权威实现（裁判）→ C 跟随实现（选手）跑在 vitro 上 → ts 驱动 spawn vitro 喂输入收输出对拍」。其设计决策三条中与本设计相关的边界：

1. **「ts 单向真相，不存在双向」**——C 版永远是错误候选，判定面恒在 ts 侧。理由是排除记录里的自证循环红线：「**C 当裁判：自证循环红线，判官不能是被告写的——引擎病则防线同病、红上加红无法定位**」。**这条红线不因 WASI 面成立而消失**（§4 复兴评估的核心论据）。
2. **「范围开放，不预设围墙」**——原文「今天做不了的 IO 面（spawn/管道）由 ts 驱动宿主喂入式解决，明天 stdlib 扩展后自然纳入」。喂入式 = **C 选手没有主动 IO 面**：输入域由 ts 驱动决定（`-i` stdin 文件 / `--json` input 帧 / `InputState::push_lines`，`host/host_io.mbt:77-87` 亲证），C 代码不能自己开文件、起进程、读 env——**只能做纯变换任务**（输入→输出）。凡是任务本身需要 IO 主动性的（遍历目录、读配置、并行子任务）都落在 #274 范围外。
3. **喂入式的形态边界**：stdin 是**预置行数组 + EOF 粘滞**（`InputState`，`host_io.mbt:45-96`），非交互流——脚本要的「任意时序读 stdin」（提示→读→再提示）在 Batch 模式下不可表达；Interactive 模式的 `waiting_input` + ip 回退是 **step 态教学语义**（`vm/host_dispatch3.mbt:14-16` 头注亲证），不是脚本直通。

**结论（废案证据链收口）**：C 作脚本不可行的根因 = 五面盘点表的 1–3 面（文件/env/进程全无）+ stdin 形态边界（喂入非直通）；其中 argv/exit-code/clock 三点已有半开面。**全部症结在同一根：宿主能力零供给**——这正是「宿主侧实现系统指令面」能一次性解锁的原因。

---

## 2. 系统指令拓展集设计

### 2.1 指令面选型表（WASI preview1 子集 + 非 WASI 标准进程面）

> 参照系 = WASI preview1 规范面（fd_write/fd_read/path_open/args_get/environ_get/clock 等）〔推断：规范知识，非仓内实测〕。**proc_spawn 族非 WASI 标准面**——WASI p1 无进程模型（相关提案仍在 draft 态），vitro 以自定义宿主指令供给，命名带 `vitro_` 前缀避免与未来 WASI 标准撞名。逐项：指令名 / 语义 / 宿主实现 / 能力分级（级 1 观察 ≤ 级 2 流 IO ≤ 级 3 文件 ≤ 级 4 进程）。

#### 级 1「观察」（只读无副作用——argv/env/时钟）

| 指令（WASI 名） | 语义 | 宿主实现 | 备注 |
|---|---|---|---|
| `args_sizes_get` / `args_get` | argc/argv 载入内存约定区 | native：壳进程 argv；V8：`process.argv`（Node）/ 壳注入（浏览器降级为 [script 名] 单元素） | **现役先例直映**：`setup_argv`（`vm/state.mbt:588`）已做内存铺设——H3 版 = 同布局 + 宿主真值源 |
| `environ_sizes_get` / `environ_get` | 环境变量表载入 | native：`environ`；V8：`process.env`（Node）/ 白名单注入（浏览器） | 解锁 `getenv`（§3 映射表） |
| `clock_time_get` / `clock_res_get` | 墙钟/精度 | **复用现役 `set_clock_source` 注入链**（`gateway.mbt:96`）——H3 handler 直接调注册的钟源，未注册恒 0 | 教学确定性口径不动（`--realtime` 旗标先例，`cli_run.mbt:37-39`） |
| `vitro_sys_capabilities`（**自定义**） | 宿主能力位图（四级 + 文件根目录清单 + 宿主形态标识） | 各宿主静态自报 | **能力探测指令**——脚本据此降级（浏览器无进程面等），双侧契约的一部分（§2.4） |

#### 级 2「流 IO」（stdio 直通——副作用=输出）

| 指令 | 语义 | 宿主实现 | 备注 |
|---|---|---|---|
| `fd_write(fd=1/2)` | stdout/stderr 直通宿主流 | native：`write(1/2)`（C 壳直写）；V8：`process.stdout.write` / console | **与现役 OutputLog 三通道并存**（`moonbit/AGENTS.md` L7 host 行）：OutputLog 是**观测通道**（教学 UI 消费），H3 fd_write 是**直通通道**（脚本态壳消费）——脚本壳默认双写（OutputLog 留痕 + fd 直通），见 §2.4 契约 |
| `fd_read(fd=0)` | stdin 直通（任意时序） | native：`read(0)`；V8：Node 可直通、浏览器形态降级为预置输入 | 解锁交互式脚本（提示→读→再提示）；现役 `InputState` 喂入面照旧（教学态不动） |

#### 级 3「文件」（授权目录内真文件 IO）

| 指令 | 语义 | 宿主实现 | 备注 |
|---|---|---|---|
| `path_open` | 在**授权根目录**内开真文件 | native：真 `fopen`（路径须落在授权根内——规范化 + 前缀校验，防 `../` 逃逸）；V8：Node `fs`、浏览器 OPFS〔未覆盖：浏览器形态期 2 再裁〕 | **授权模型核心面**（§2.5）；WASI p1 的 fd_prestat 预开目录模型**不选**——以「授权根目录清单」替代（复杂度：prestat 须宿主预开 fd 表，与 vite/CI 等无预开目录的宿主不合） |
| `fd_read/fd_write/fd_close/fd_seek`（fd>2） | 真文件读写游标 | 宿主 fd 表（**与现役 VFS fd 表分域**——VFS fd 1..n 已占，H3 fd 从 3 起，零冲突〔推断：分域编号即可，实施批定表〕） | WASI 语义：返回 errno 码（0=成功），非 C ABI 哨兵 |
| `path_filestat_get` | stat 元数据 | 宿主实现 | 覆盖「遍历目录判大小」类任务的最小面；`path_filestat_get` 配 `fd_readdir`？——**目录列举 v1 不选**（面收窄，列目录走 §3 独立小改的 `vfs.list` 语义或期 2 再开）〔未覆盖〕 |

#### 级 4「进程」（非 WASI 标准——vitro 自定义宿主指令）

| 指令（**自定义，如实标注**） | 语义 | 宿主实现 | 备注 |
|---|---|---|---|
| `vitro_proc_spawn` | 起子进程（argv 数组 + 可选管道绑定） | native：`CreateProcess`/`posix_spawn`；V8：Node `child_process.spawn`、浏览器**恒 ENOTSUP**（能力位图自报） | WASI 标准无此面〔推断：WASI 进程相关提案仍在 draft〕——自定义命名隔离未来标准演化 |
| `vitro_proc_wait` | 等待/收割（返回 exit code） | 宿主 waitpid 语义 | |
| `vitro_pipe_create` / `vitro_pipe_read/write/close` | 匿名管道 | 宿主 pipe 语义 | 解锁「脚本作为管道一环」（`vitro script.c | grep x` 与脚本内部再起管道两形态） |

**不选面清单**（显式收窄，防面蔓延）：socket 族（网络，O8）、`random_get`（教学确定性冲突——随机走现役 `srand/rand` host 路由〔已验证，route 面〕不进 H3）、`fd_prestat_*`（上述）、`sched_yield`/信号面（脚本价值不成比例）、`fd_readdir`（v1 收窄）、sock_dgram 等 WASI p1 其余 IO 面（fd_datasync/fd_sync/fd_tell/fd_advise——文件语义增强项，v1 全不做）。

### 2.2 接入机制：H2 扩展 vs 新 H3 系统通道（对比+推荐）

REHOST 设计单 §2.2-D 类已定「CallHost 110 路由 = 单一 import `env.vitro_host_call(route_id : i32, argv_ptr : i32) -> i64`」。WASI 面的接入两案：

| 维度 | 案 A：H2 扩展（route_id 空间加 WASI 段，如 200+） | 案 B：新 H3 通道（`env.vitro_syscall(op : i32, args_ptr : i32) -> i64`，**推荐**） |
|---|---|---|
| ABI 面 | 单 import 不增 | import +1（仍全数字 ABI，无字符串 import——wasm 臂构建图友好〔推断：REHOST §2.3-E4 同论证〕） |
| **能力开关硬度** | **弱**：route 分段只是命名约定，产物 import 了 H2 就物理可调任何 route_id——能力判定退化为**运行期查表拒绝**（每调用一次检查，且「教学产物能不能带 WASI route」靠发射器纪律而非验证期约束） | **硬**：**import 的存在性就是能力开关**——wasm 验证期/链接期约束〔推断：wasm 规范，import 未供给即 instantiate 失败〕。教学产物**不 import H3** ⇒ 物理零指令面；脚本产物 import H3 ⇒ 宿主按授权供给。装载期一次判定，运行期零检查 |
| 语义域纯度 | H2 = C libc 弹参语义（CallHost 弹值栈入约定区，REHOST §2.2-D），WASI = errno 返回 + iovec 内存布局——两种 ABI 混一张 route 表，宿主实现层分叉 | H3 独立域：WASI 语义（errno 码 + iovec）单表单源；H2 原样不动（**110 路由零扰动**） |
| 宿主实现 | 三宿主（C 壳/V8/Rust 桩）在既有 host_call 分发函数里加 switch 段 | 三宿主各写一个新 JS/C/Rust 函数——与 H2 handler 完全隔离 |
| 与 REHOST 批次关系 | 动 route 表 = 动 H2 面 = 连坐 `gen_host_route`/`host_route_coverage`/libc 三表对账闸（`moonbit/AGENTS.md` 命令清单亲证）——**批间耦合** | **零连坐**：route 表不动，H3 是纯新增叶面（`pkg_deps` 登记新边即可） |

**推荐案 B（H3 独立通道）**。决定性论据是能力开关硬度：**沙箱边界从全封闭改能力授权制，安全语义必须落在装载期/链接期这个不可绕过的点上**，运行期查表是软门（漏查一处即逃逸面）；import 存在性是 wasm 模块验证器替我们把守的硬门——「教学产物不带 WASI 面」从纪律约定升格为**结构不可能**。次级论据：H2 语义域零污染（110 路由三表对账闸全绿不动）。

### 2.3 教学态零影响论证（默认关 = 零指令面）

1. **产物面**：教学 compile 管线不发射 H3 import ⇒ 载体与 REHOST 批 1 产物逐字节同域——`vm_diff`/`clang_direct`/digest 面零变化（铁律 1「语义冻结」自动满足——不是「不变」，是「物理无新面」）。
2. **帧/防线面**：H3 指令在权威执行器内 = 组操作一枚（CallHost 同族——一次 syscall 计 1 步〔推断：与 REHOST §2.4 步锚同构，实施批锚定〕）；教学产物无 H3 ⇒ STEP-INV 帧流零变化。
3. **语义面**：现役 VFS `fopen` 族走 H2 路由 60+（`host_func_id_gen.mbt:121-124,402-403` 亲证）——**教学态文件语义（VFS 内存态）一行不动**；H3 `path_open` 是并行新面非替换。getenv/system 的 E3073 拒绝面同样不动（教学诊断语义保持，`unsupported_sig.mbt:22-25`）——**脚本态开面走 H3 指令面，不走 libc 名表扩容**（两域隔离：教学 C 程序的 `getenv()` 调用与脚本态的 `environ_get` 指令是两条路径；脚本态 libc 适配层见 §3）。
4. **宿主面**：未注册 H3 handler 的宿主（demo 浏览器、判题壳）对带 H3 import 的产物 instantiate fail loud——与 include_reader 未注册 E1021 同构的「能力不存在 ≠ 故障」语义（§1.2 母型）。

### 2.4 宿主实现层：双侧契约（native 直链壳 / V8 影子 / wasmtime 桩）

**契约单源**：op 码表 + iovec 布局 + errno 码表 = 一张机器可读表（JSON 入 `scripts/` 规则表族〔推断：随实施批定格式，参照 host_route_rules.json 外置先例〕）——三宿主三实现共同消费，漂移即 CI 红（三向对账，参照 libc 三表一致性闸形态）。

| 宿主 | 形态 | 系统能力实现 | 依据 |
|---|---|---|---|
| **native 直链壳**（脚本主形态） | C ABI 直链（`vitro_init`/`vitro_invoke` 两函数薄包装——native 导出面已实测打通，native 导出面探针报告 §2-4 全绿（现场批次产物，不入库），release 2.28MB） | C 实现：`env.h` H3 handler 表——`args`（main 的 argv 直传）/ `environ`（CRT environ）/ `fd_write/read`（read/write 系统调用）/ `path_open`（真 fopen + 授权根前缀校验）/ `proc_spawn`（CreateProcess/posix_spawn） | 该报告 §2 已证 include_reader 注册先例（`@fs.read_file_to_string`）；H3 handler 同层落位（壳层 C 代码，不进引擎包） |
| **V8 影子**（js/wasm 臂 + demo/CEF） | JS import 桩（与 H2 `vitro_host_call` 桩并列，`WebAssembly.Instance` imports 对象加 `vitro_syscall` 键） | JS 实现：Node 形态全能力（`process`/`fs`/`child_process`）；浏览器/CEF 形态降级（stdio 走 console/OPFS、进程面 ENOTSUP——能力位图自报，脚本据此降级） | REHOST §4.1 V8 嵌入三形态直接复用（demo Worker / CEF / node 跑器） |
| **wasmtime 跑器**（W4 第四臂） | Rust Linker 桩（`Linker::func_wrap` 供给 `vitro_syscall`） | Rust 实现：WASI 面可直接用 wasmtime WASI ctx（但 **H3 是自定义 import 名**，不等于 wasi_snapshot_preview1——须自写薄桩映射到 `std::fs`/`std::process` 或桥接 wasmtime_wasi） | 审阅 v2 R3b「wasmtime Rust 供给 0.38ms runtime 对拍独有保留」先例〔已验证，20261102 审阅报告 v2 总报告〕 |

**stdout 双通道契约**（脚本态特有）：H3 `fd_write` 直通宿主流的同时，权威执行器照记 OutputLog（观测通道不缺）——脚本壳消费直通流（rc/管道语义），UI/对拍消费 OutputLog（字节保真语义，`moonbit/AGENTS.md` L7 host 行「载体 Bytes 化」）；两流一致性不设闸（同一字节序列两出口，无对拍意义）〔推断：实施批若发现双写成本再裁〕。

### 2.5 能力授权模型（三案对比 + 推荐——默认拒绝、显式授权）

| 案 | 形态 | 优点 | 致命伤 |
|---|---|---|---|
| **A 编译选项** | `vitro compile --wasi <级>` 决定发射 H3 import 面 | 能力=产物属性（wasm 生态惯例——import 面即能力面，与 §2.2 硬门天然咬合） | 源码与能力分离：同一份 C 两种产物，「这个脚本要什么面」要靠编译命令传话 |
| **B 会话开关** | gateway `config.set` 增 wasi 键 | 运行期可控 | 与硬门机制**冲突**：产物已 import H3、会话拒绝 ⇒ 链接期就失败（不是运行期拒绝）——开关位置错位；且授权粒度挂在宿主侧单点，脚本作者无法声明意图 |
| **C 文件级声明** | 源码伴生 manifest（`script.c.vitro.json`：`{"wasi": {"level": 3, "roots": ["./data"]}}`）或源内 pragma（`#pragma vitro wasi(level=3)`） | 声明即授权（脚本生态同构：Node package.json / Python venv）；能力意图随源码走，可见可审 | 学生代码携带 manifest 的注入面——**见下：宿主上限是硬门所以注入无效**（判题宿主上限 0 ⇒ 任何 manifest 都拿不到面） |

**推荐：A+C 复合（产物声明、manifest 源）+ 宿主上限硬门**：

```
有效能力集 = min(产物 import 面（A，编译期从 manifest/旗标 C→A 定级）, 宿主供给上限（宿主启动参数）)
```

- **默认拒绝**：无 manifest 无旗标 ⇒ 级 0 零面；宿主未指定上限 ⇒ 上限 0（判题/demo 默认形态）。
- **硬门在宿主**：`vitro script --allow-wasi <级> --root <授权根>`——判题壳/教学产品域**永不传**这两参 ⇒ 学生代码携带任何 manifest 都拿不到面（结构性免疫，非纪律约定）。
- **pragma 形态不做**（v1 只 manifest + 旗标）：pragma 进 C 源会被学生互相拷贝传播，manifest 是文件级显式动作、意图清晰；期 2 若脚本生态反馈刚需再议〔未覆盖〕。

---

## 3. C 脚本形态终稿：`vitro script.c`

### 3.1 体验项 × WASI 面依赖映射表

| 体验项 | 依赖 | 说明 |
|---|---|---|
| `vitro script.c a b c`（直跑） | **已有** | argv 面 = 现役 `setup_argv` + `--` 透传（§1.1 面 5）——script 壳把 `.c` 后缀参数后的全部进 argv_passthrough 即可 |
| shebang（`#!/usr/bin/env vitro script`） | **独立小改** | 壳层剥 `#!` 首行（词法器不认识 `#!`——C 预处理域外，壳层预处理一步，不进 lexer〔推断：lexer `#` 行族会被 `#!` 撞 E 诊断，实施批锚定〕） |
| exit code 透传（`echo $?`） | **独立小改** | 现役 `exit()` 已有 host 面（路由 38）+ `// EXIT <ret>` 行协议——script 壳消费 run 返回值调 `c_exit(ret)`（cmd/run/main.mbt:44 `c_exit` extern 先例直用） |
| stdin 直通（管道右端/交互） | **WASI 级 2 解锁** | `fd_read(0)` 直通（§2.1 级 2）；现役 `-i` 喂入式保留（教学域） |
| stdout/stderr 直通（管道左端） | **WASI 级 2 解锁** | `fd_write(1/2)`；现役 OutputLog 观测通道并行（§2.4 双通道） |
| 读环境变量 | **WASI 级 1 解锁** | `environ_get` + 脚本态 libc 适配（getenv 从 `unsupported_sig` 表的**脚本态旁路**——注意：E3073 表条目不动〔教学语义〕，脚本态经 H3 后端供给 getenv 实现，libc 路由表增环境后端 handler〔推断：路由面增 1-2 名，走 H2？不——脚本态 getenv 也走 H3 environ 读缓存。实施批定形，见 O6〕） |
| 读/写真文件（授权根内） | **WASI 级 3 解锁** | `path_open` + 授权根（§2.5） |
| 起子进程/管道编排 | **WASI 级 4 解锁** | `vitro_proc_spawn` 族（自定义指令面） |
| REPL | **不设计** | C 非表达式语言、子集须完整编译单元——REPL 语义不成立；替代 = `vitro script.c` 快循环 + 产物缓存（下条）把重跑成本压到毫秒级（native 直链 invoke 0.002-0.003ms 实测〔已验证，native 报告 §0-2〕） |
| **wasm 产物缓存复用**（编译一次反复跑） | **REHOST 批 1 产物面** | script 壳按 `sha256(源码) + 引擎版本 + 发射器指纹` 缓存 wasm 载体（缓存目录参照 `moonbit/tools/cache` 在途形态〔已验证，工作区目录亲见〕；缓存命中 ⇒ 跳过 compile 直 instantiate——长循环脚本开发（改数据不改代码重跑）与 CI 判题跑批的双收益〔推断：收益量级待实测，开放问题 O4〕） |

### 3.2 script 壳落位

- CLI 面：`cmd/lib/cli` 增 `script` 子命令（与 run/compile/step/api 并列，CLI_PROTOCOL_V1 spec 单源连坐扩一节〔推断：rc 值表新增「授权拒绝=5」等 script 专属码，实施批入 spec〕）。
- 三臂同源：`cmd/vitro_js`/`cmd/vitro_wasm`/native 三臂壳全走 `cmd/lib/cli` 单源（第 12 条统一入口纪律直承）；H3 供给能力按臂分叉（native 全能力 / js=Node 全能力 / wasm 浏览器降级——能力位图自报）。
- **注意**：script 态的引擎跑批 = run 态全速（非 step 态）——权威执行器折叠路径（REHOST §3.1），VisEvent/帧流零参与（脚本形态无 UI 消费）。

---

## 4. #274 复兴评估：WASI 面成立后 C 可否升裁判

| 维度 | 案 1 **保守案**（推荐）：C 跟随件获得 IO 面，裁判仍 ts 单向 | 案 2 激进案：C 升裁判（ts 裁判 + C 裁判双实现） |
|---|---|---|
| #274 排除记录是否翻案 | **不翻**——「C 当裁判=自证循环」的论据（引擎病则防线同病）与 IO 能力无关，是**独立性**问题 | 翻案——但须回应自证循环：WASI 面给的是 IO 能力，不是正确性独立性 |
| 任务面 | **扩大**：#274 决策 3「今天做不了的 IO 面由 ts 驱动宿主喂入式解决」升级为「C 选手自带 IO 面」——文件处理/配置驱动/多进程并行任务从范围外进范围内 | 同左（两案共享） |
| 对拍形态 | 不变（ts 裁判 spawn vitro 收输出）；红时分二不变（先翻译漂移后引擎） | 双裁判互证——但 ts 裁判 + clang golden 已是双真相（`clang_direct` 层 2 在役〔已验证，`moonbit/AGENTS.md` 命令清单〕），C 裁判是第三真相，边际价值低 |
| C 裁判的独立性来源 | — | **无解**：跑 vitro = 病同源（parser/typeck/codegen/VM 全链共享）；跑 clang = 重复 `clang_direct`（且脱离「C 跑 vitro」命题本身）。「native 直链壳跑 C 裁判」的中间形态也不成立——编译器层仍共享〔推断：从架构直接可证〕 |
| 新增防线价值 | C 选手带 IO 面 ⇒ **引擎 H3 面 + 三宿主实现进入对拍域**（每次 #274 跑 = H3 链路的活体验证——WASI 面自己的狗粮线） | — |
| 风险 | 低（裁判位不动，#274 骨架零改） | 高（自证循环防线松动 + 双裁判分歧定责面新增） |

**推荐案 1（保守案）**，不做会怎样：保持案 1 损失的仅是「C 裁判」名义上的对称性——而其独立性缺陷使该对称无实质价值；案 1 已拿到 WASI 面的全部净值（任务面扩大 + H3 狗粮线）。**裁判单制（ts）是终态，不是过渡**〔推断：除非未来出现「vitro 之外的第二 C 执行器」做裁判（异源才独立），仓内不存在此形态〕。

连坐：若本设计获批，#274 issue 补评论一条（决策登记纪律 10.5——含「C 裁判二次评估仍不翻案」的被驳记录与否掉理由）。

---

## 5. 设计单连坐与分期建议

### 5.1 REHOST 解锁清单连坐

REHOST §6 解锁清单增第 7 项（本批已连坐改写该设计单，见提交 diff）：

> **7. WASI 拓展面与 C 脚本/裁判形态**（`vitro script.c` 脚本态 + 能力授权制 + #274 扩面——独立设计单见 [WASI拓展面设计单](WASI拓展面设计单——能力授权制与C脚本裁判形态.md)；启用条件 = 批 1 落地〔H3 import 挂靠 wasm 载体〕+ 批 5〔V8 影子侧供给〕；script 壳的 native 臂不依赖批 5 可先行）｜依赖：批 1（+批 5 全宿主）｜期 2–3

依赖链更新：`批1 发射器 → {2 导出, 3 工具链闸, 4 多runtime(半), 7 WASI 面(半——native)} → …`。

### 5.2 分期表（0.10.x 不可达项如实标注）

| 期 | 内容 | 前置 | 版本窗口 |
|---|---|---|---|
| **期 0** | 独立小改三件：argv 直用已有面收口 / shebang 壳层剥行 / exit code 透传（`c_exit`）+ `script` 子命令骨架（零 WASI 面——纯 run 态包装） | **无 REHOST 依赖** | **0.10.x 可达**（小批，独立验收：script 壳 rc 表 + 三臂 smoke） |
| **期 1** | H3 通道 + 级 1/2（观察 + 流 IO）+ native 壳 C 实现 + V8 Node 形态 | **REHOST 批 1 落地**（wasm 载体 import 面） | 0.10.x **不可达**——如实标注：批 1 在途（`moonbit/wasmenc/` 批 1a 会话），期 1 最早 0.11 窗口 |
| **期 2** | 级 3 文件面（path_open + 授权根）+ manifest/宿主上限授权模型 + 缓存复用 + CEF/浏览器降级形态 | 期 1 | 0.11+ |
| **期 3** | 级 4 进程面（vitro_proc_* 自定义指令）+ #274 扩面（C 选手 IO 任务）+ wasmtime 桩（W4 对拍域收编 H3 面） | 期 2 + REHOST 批 5 | 1.0 窗口前后（与退役评估排期互让，同 REHOST §9 反触发声明） |

---

## 6. 风险与边界

| # | 风险/边界 | 等级 | 处置 |
|---|---|---|---|
| R1 | **安全面：脚本开 WASI 面 = 沙箱逃逸面的受控开放**——级 3 文件/级 4 进程是真 OS 能力，`path_open` 授权根逃逸（`../`、符号链接）是经典攻击面 | 高 | 授权根前缀校验 = 规范化（realpath 归一）后前缀比对，非字符串前缀〔推断：实施批按此验收+红锚〕；**教学产品语义写死：学生代码永不开面**（判题宿主上限恒 0——§2.5 硬门），工具/裁判态才开；级 4 进程面期 3 才开（最晚暴露） |
| R2 | manifest 注入面（学生代码携带高阶 manifest 试图提权） | 中 | 宿主上限硬门结构性免疫（min 交集，§2.5）——「产物要什么」与「宿主给什么」分离，提权点不存在 |
| R3 | **digest 可复现性破坏**：H3 面（时钟真值/文件真值/进程）引入非确定性，vm_diff/clang_direct 的 stdout+rc 口径受染 | 中 | **防线域隔离**：H3 面语料不进 vm_diff/clang_direct 语料域（脚本态产物带 H3 import ⇒ 防线采集器识别即跳过并计数上报）；级 1 的 clock 复用 `--realtime` 旗标先例（默认关=确定性口径，`cli_run.mbt:37-39`） |
| R4 | **三宿主行为分叉**（native 全能力 / Node 全能力 / 浏览器降级）——同脚本不同宿主不同结果 | 中 | 能力位图自报指令（§2.1 级 1）+ 三臂纪律（第 14 条）：H3 面结论须 js+native 双臂、涉 wasm 出口面三臂；宿主差异属设计内（降级非缺陷），对拍闸按能力位图分桶而非强一致 |
| R5 | H3 ABI 契约漂移（三宿主三实现 + op 码表演化） | 中 | 契约单源表 + 三向对账闸（§2.4，参照 libc 三表一致性闸形态；op 码 only-add never-reuse，versioned 常量纪律同 156 码位） |
| R6 | wasmtime W4 臂对 H3 的支持形态：H3 是自定义 import 名，**非** wasi_snapshot_preview1——wasmtime 原生 WASI 不直接可用 | 中 | W4 跑器自写 Rust 薄桩（`Linker::func_wrap`，R3b 先例）；期 3 才收编对拍域（缓暴露） |
| R7 | script 壳与 `cmd/lib/cli` 的 rc 值表/协议面扩张连坐（CLI_PROTOCOL_V1 spec 单源） | 低 | 期 0 批内连坐（spec 增 script 节 + `vitro_cli_smoke` 三臂对拍扩 script 子命令） |
| R8 | #274 骨架改动（裁判线接线 C 选手 IO 任务）过早介入 | 低 | 期 3 才动（缓暴露）；期 0–2 的 script 壳与 #274 线零耦合 |

**边界声明（本设计不做）**：不修改现役 VFS 语义；不修改 E3073 教学拒绝面（getenv/system 教学诊断保持）；不修改 #274 裁判单制；不开网络面（O8）；REHOST 批次内容不在本设计内（依赖方非实施方）。

---

## 7. 开放问题清单（实施批逐项拍板，本设计批给推荐不锁死）

| # | 问题 | 推荐 | 拍板时机 |
|---|---|---|---|
| O1 | H3 ABI 细节：iovec 布局（1MB 内存约定区直写 vs 参数区指针传递） | 约定区复用 H2 的 argv_ptr 区模式（REHOST §2.2-D 同构），iovec 数组在区内心跳布局 | 期 1 |
| O2 | 文件授权根的路径表示（绝对根清单 / cwd 相对 + 深度限制） | 绝对根清单（min 授权最直观），cwd 相对作糖 | 期 2 |
| O3 | 浏览器/CEF 文件面降级形态（OPFS / 内存盘映射回 VFS / 恒 ENOTSUP） | OPFS 映射（期 2 实测再定；ENOTSUP 为兜底） | 期 2 |
| O4 | 产物缓存键与失效（源码 sha+版本+指纹三键已定；共享缓存目录的并发/清理策略） | `moonbit/tools/cache` 在途形态对齐 + LRU 上限 | 期 2 |
| O5 | script 壳包落位（`cmd/script` 新壳 vs `cmd/lib/cli` 扩子命令即可） | cli 扩子命令（三臂单源纪律最短路径）；独立壳仅当体积/启动预算超标再拆 | 期 0 |
| O6 | 脚本态 getenv 的路由形态（libc 路由表增名走 H2 vs 纯 H3 environ+适配层） | H3 environ 一次读入 + libc getenv 名进路由表但 handler 读 H3 缓存（H2 入口、H3 后端——零 H3 语义进 H2 表） | 期 1 |
| O7 | H3 指令在权威执行器的步语义（1 syscall = 1 步 vs iovec 拷贝计步） | 1 步（CallHost 同族；阻塞 syscall〔fd_read 等待〕的步冻结语义实施批锚定） | 期 1 |
| O8 | 网络面终局（永不开 / 期 4 评估） | 永不开写入设计边界（教学产品无网络需求；开面收益/风险比最差）——留用户终裁 | 本批拍板 |

---

## 附：本设计单的证据底账（全部本会话亲读）

- 沙箱面：`moonbit/host/vfs.mbt:3-6,164-172,234-264,1002-1013`（VFS 内存态/注入/列举口）；`moonbit/libc/unsupported_sig.mbt:22-31`（getenv/system/atexit 显式拒绝）；`moonbit/bytecode/host_func_id_gen.mbt:43,58,121-124,376,381,402-403`（getchar/exit/fopen/fread 路由与全表无进程/网络面）；`moonbit/libc/libc.mbt:555`（放行名全集段）
- 能力注入先例：`moonbit/gateway/gateway.mbt:87-98`（include_reader/clock_source 双注入 + E1021 正当诊断）；`moonbit/vm/state.mbt:588`（setup_argv）；`moonbit/host/host_io.mbt:45-96`（InputState 喂入式/EOF 粘滞）；`moonbit/vm/host_dispatch3.mbt:14-16`（Batch/Interactive 双模式头注）
- 路由与 ABI：`moonbit/bytecode/route.mbt:26-54,121-138`（CallRoute/遮蔽集/派生规则）；REHOST 设计单 §2.2-D/§2.3-E4（H2 单一 ABI 选型）
- CLI 形态：`moonbit/cmd/lib/cli/cli_run.mbt:1-80`（rc 表/argv 透传/--realtime/未知旗标 fail loud）；`moonbit/cmd/run/main.mbt:25-50`（c_exit/write_stdout_stub/clock stub）
- 宿主形态：native 导出面探针报告 §0-4（现场批次产物，不入库；native C ABI 直链全绿/2.28MB/invoke 0.002ms/include_reader 注册先例）；issue #274 全文（GitHub）；`moonbit/wasmenc/` 目录亲见（批 1a 在途）
- WASI 规范面参照〔推断档——规范知识非仓内实测〕：WASI preview1 指令族语义；wasm import 链接期约束；wasmtime WASI ctx
