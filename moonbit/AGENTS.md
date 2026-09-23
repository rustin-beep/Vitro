# MoonBit 活跃区操作手册（moonbit/）

> **本文件是按需读取的分区手册**——根 [`AGENTS.md`](../AGENTS.md) 双区制路由指向此处，**仅在触碰 MoonBit 活跃区（`moonbit/`）时才读取**，与 [`native/AGENTS.md`](../native/AGENTS.md)（Rust 冻结对照区）对称。
> **全域纪律**（中文输出 / 禁擅自 git 提交 / 实测大于脑测 / 诚实记录 / 红→绿 / J9 / archive 规则 / 提交署名规则）以根 AGENTS.md 为准，同样约束本区。
> **上位文档**：[MoonBit迁移总计划](../docs/current/01-定位与路线/MoonBit迁移总计划.md)（包切分 L0–L9 / 锚点体系 / F1–F9 语言事实）+ [第一阶段计划](../docs/current/01-定位与路线/MoonBit迁移第一阶段计划.md)。本手册只沉淀**工程操作层**（命令 / 陷阱 / 纪律 / 发布），不重复上位文档内容。

## 包清单与状态（S6 开工批二——memory + host 建包；语料真值 **600**，2026-09-22 实测）

| 包 | 层 | 职责 | 状态 |
|---|---|---|---|
| `vitro/engine/source` | L0 | SourceLoc + 列单位契约（column = 行内 UTF-8 字节偏移+1）+ Pos 双坐标 | ✅ 已发布 0.1.1 |
| `vitro/engine/opcode` | L0 | 132 条 opcode（空号 44–49）+ Instruction | ✅ 已发布 |
| `vitro/engine/diag` | L1 | ErrorCode 137 臂（gen_diag 生成）+ catalog 77 + E4 出口 | ✅ 已发布 |
| `vitro/engine/ast` | L2 | Type 17 / Expr 26 / Stmt 16 全族 + depth + E1 emitter + 谓词/compute_type_size（S3 消费驱动补齐） | ✅ 已发布 |
| `vitro/engine/lexer` | L4 | 独立预处理 pass + LineMap + 宿主 IO（token 契约面子包 `lexer/token`） | ✅ 已发布 0.3.0 |
| `vitro/engine/parser` | L4 | token → AST：表达式瀑布/声明符螺旋/语句族/声明族/C++ 分支；**depth 参数化防护**；声明符自顶向下累加器（F3-v2）；Rollback 七字段全量快照；stall_count 活性观测 + 零推进熔断 | ✅ 已发布（随 0.5.0 进架，2026-09-23） |
| `vitro/engine/names` | L3 | 名字单源：`__ctor__`/`__dtor__` 产名族唯一出口（parser 8 处散拼已收口）+ `type_mangle_suffix` 17 变体 + `method_mangled_name`（D1 单源照搬）；InstKey→InstId 派生随 S9 C++ 裁定 | ✅ S4 建包（5 测试） |
| `vitro/engine/libc` | L5 | builtin 签名单表 57 条（visit_call 58 臂去 std__move；照搬现状口径，printf/putchar void 的 N3 漂移登记）+ 放行名全集 175（= host 110 名 ∪ bytecode 88 名 − print_int）；**三表一致性由 `scripts/moonbit/libc_single_source -check` 机判（2026-09-22 接线）**——「以本表为单源回填」在 L5/L6 依赖方向下不可派生，已诚实登记为对账 | ✅ S4 建包（3 测试） |
| `vitro/engine/typeck` | L5 | C 子集类型检查 + lowering（4 Pass；TypeKind 裁定入 ast——TK_ 前缀；lowering 函数式重建：visitor 值进值出）；C++ 专属延后 S9（convert 的 Reference/RValueRef/is_upcast 分支剔除登记） | ✅ S4 主体收官（T5-b/c/d，2026-09-20）：4 Pass 全量接线——call/init/builtin/decl 四文件（visit_call 58 臂 + check_user_func 四级回退（bytecode_libc_sig 表入 libc 包）+ dispatch_stmt 语句族 + VarDecl 巨臂（auto/typeof 推导）+ 数组/struct 初始化器尺寸推断）；13 白盒锚（183 测试）；**598 语料 E1–E4 归一逐字节一致**（2 条 F3-v2 白名单 FORK(known)——parser 层分叉的 typeck 消费面放大，S8 台账）；quote-include 哨兵入 gap（vfs 偶然对齐监测，语料 597→598）；遗留：decl_types 独立批并入本批；E1 全量对拍管道 CI 化已接线（2026-09-20 审阅批补，typeck_diff 四目录入 CI） |
| `vitro/engine/bytecode` | L6 | 产物 schema（CompileOutput 13 字段 + FuncMeta/LocalBuffer/Symbol）+ Bytecode Libc 固定索引（88 函数数组单源，索引=1000+下标派生+断言锚）+ R1 布局纯函数（align4/compute_heap_base/argv_region_footprint）+ canonical dump emitter（Map 键码元字典序——**内置 String compare 非字典序**见陷阱 #29）+ **调用形态单一路由表**（`route.mbt`：`CallRoute` + `call_route` 派生 + 遮蔽集显式清单；`host_func_id_gen.mbt` 由 `gen_host_route` 生成，S6 自 codegen 上提） | ✅ S5 开工批建包（2026-09-20，8 测试：Rust 源 88 对硬编码对账锚 +1——2026-09-21 审阅补）：emitter 与 Rust `dump-compile` 14 键逐字段同构（Type/浮点文本化/转义经 ast 单源）；r1 第 7 道布局断言全量搬；**S6 host 建包批（2026-09-23）**：路由表落点自 codegen 上提至此（14 测试：原 8 + 路由 6）——**落点裁定与总计划 L7 行字面表述相左**：codegen(L6) 编译期即需知道 host id，L6→L7 反向依赖被 §4 硬约束禁止，故定义点只能 ≤L6；libc(L5) 又无法反向 import 本包的 88 名单源。详见生成器头注与 `route.mbt` 模块头 |
| `vitro/engine/codegen` | L6 | BytecodeGen 状态机（**双入口**：`compile` 常规 / `compile_library` library mode——预编译 Bytecode Libc 自身，不预注册固定索引段 + 全局偏移自 0 起；library 入口已由 `scripts/moonbit/libc_boot_diff` 对拍 3 源全 SAME）；C only 裁剪——47 字段剔 C++ 专属 7 项：顶层 6 + ScopeFrame.class_vars 嵌套 1）+ Pass 1 全量（全局注册/初始化位模式 T-P0-1/2/字符串延迟回填 P2）+ Pass 2/3 骨架（Block/Expr(stmt)/Return + 四字面量/Identifier）+ 入口 wrapper + libc 预注册（strcpy/strcat Host 分发例外）；**槽位策略 v1 逐位兼容**（LIFO 池 v2 随八条事故回归批） | ✅ S5 开工批 + 扩展批一/二/三号（三号 2026-09-21：赋值全量（Identifier 三路+Deref+struct 拷贝+11 复合运算符含 float 分支——kr_1_15 对拍实锤修漏）+ 三目 + 控制流五件（if/while/do-while/for/switch——跳转补丁 base 截断语义）——**全语料 SAME 325/598（54%）**：baseline 262 + knr 35 + leetcode 18 + gap 10，CONTENT-DIFF 全 0；**F3-v2 白名单入 codegen_diff**（function_pointer_return_ptr/kr_5_11——parser 层分叉的 codegen 消费面放大）；二号：二元 19 运算符穷尽（隐式提升链/指针算术/U 族/短路+T-P1-1 规范化）+ 一元（Neg/Not/BitNot/Deref 的 immediate_base_kind/Addr 含 static/++-- 全分派）+ Cast 10 向 + sizeof/alignof/offsetof + type_align 纯函数随迁——**baseline SAME 56→174**（180 剩余，CONTENT-DIFF=0）；一号：VarDecl 全量接线（emit_single/static/VLA/数组 init/struct init/designator/zero-init Memset）+ CallPtr（host 路由 110 对脚本生成 + SplitD/Q 变参 + CallVar + struct 传参 words）+ gen_addr 最小集 + gen_nested_init/struct_copy_to_local——SAME 0→56；二号后累计 174/363，knr 7 + leetcode 2 + gap 7；16 测试）：未接线语句/表达式族 report_error fail loud；**A 级对拍**——13 条骨架语料（native/tests/cases/codegen_skeleton/，2026-09-21 审阅批 +3：2^64 溢出/浮点 inf/`__func__`）Rust dump-compile vs cmd/dump_compile 归一逐字节一致（codegen_diff 管道，含 code 段逐指令）；**baseline 363 例归因（2026-09-21 审阅，扩展批优先级；数字为 VarDecl/CallPtr 接线前基线）**：剩余面 354 例全在 gen 层——VarDecl 245（另有 22 处"未声明标识符"级联噪声随其消失）> CallPtr 71 > 二元 13 > for 8 > 赋值 6 > if 6 > while 3 > 三目 1；**勿接 Call**（Expr::Call 仅 C++ ctor 路径构造、C 输入不可达，直接/指针调用统一在 CallPtr 臂——两侧 parser 同构） |
| `vitro/engine/memory` | L7 | 1MB 载体 `Memory`（`FixedArray[Byte]` + 脏页位图；**`bytes`/`dirty` priv**——包外拿不到裸字节，唯一路径是 `MemoryMap::check_access` + 受检读写）+ `MemoryMap`（regions = **addr 键插入序 `Map`**（平行索引取消，坑 6 失配面归零）/ free_list / quarantine（`@deque` FIFO）/ 堆游标 / `release` 单出口（三条释放路径合一）/ `check_access`（NULL 区→上界→UAF）/ `verify` 不变量自检）+ `FreedLogs`（**有序数组 + 二分**：`find_overlapping` 单次探测、`remove_overlapping` 降序提前 break + 部分重叠精确裁剪）+ `MemFault` 结构化故障（文案归 vm） | ✅ S6 开工批建包（2026-09-23，27 测试：白盒 21 锚 + 黑盒 6）：常量不双写（布局常量仍 `@bytecode.` 单源，本包只消费 MEM_SIZE/NULL_TRAP_SIZE/HEAP_START/align4）+ 硬编码对账锚；红锚照搬坑 6/7/10 + churn 超预算不撞墙 + 1MB 墙返回 NULL；J9 双路注入证红（整条删除→4 红；二分差一→13 红）；已知代价登记：数组 `remove` 为 O(n) 搬移，复用路径下标近 0 时搬移接近全长（10 万次 churn 实测 1.6s，暂不构成问题；换 `@sorted_map` 时算法与红锚不变）。**登记未落地**：快照批量装载 `load_*`（形状待 vm 定 `VMSnapshot`/`MemoryImage`）、`MemoryFragmentData`（L8 导出 DTO）、cstring 通道（`\xHH≥0x80→Latin-1` 口径单源在 L6 `codegen/init.mbt` 且 priv，须先上提） |

| `vitro/engine/host` | L7 | 110 路由表的**消费侧** + 输出通道（`OutputKind` 三通道 / `OutputChunk` / `OutputLog`——**载体 Bytes 化**：非 UTF-8 字节保真，`putchar(200)` 落 1 字节 `0xC8` 而非 String 化的 2 字节；16MB 预算环形丢最旧保最新 + 截断注记；64B 小段合并摊还 O(1)）+ 内存族 handlers（`host_malloc/calloc/realloc/free`，返回 **`HostMemReply{value?,note?,trap?}`** 结构化三件——不碰值栈，内存语义可脱离 VM 锚定）+ E3061/E3027 教学文案 + 堆耗尽附注 + **余量批一号（2026-09-23）70 个 VM 无耦合 handler**：ctype 14（纯函数）+ math 22（位模式进出：`@math` + `Double::sqrt/abs/mod`——fmod IEEE 语义含 `mod(x,0)=NaN` 探针锚；`log→ln` 位对；**pow 先弹 x、atan2 先弹 y 的弹参序不一致已登记为 vm 接线义务**）+ 字符串/内存 19（**读侧一律受检**——oracle `read_cbytes` 裸读三缺口〔NULL 静默零/UAF 静默读/越界当 0，坑 16/18〕转教学 trap，`memset` 超长截断/`strncpy` 负 n 补零到尾等**界内软夹紧照搬**；`memset/memcpy/memmove` 写侧受检化与 oracle 的 U5#1 无检分叉**登记两侧同修候选**；`strpbrk` 族字节语义替代 oracle lossy-char 语义〔ASCII 域一致，非 ASCII oracle 侧缺陷登记〕；strcpy/strcat E3070 双重校验——堆块容量 + 栈缓冲容量〔`StackBufferSpan` 显式参数，vm 侧从 call_stack 展平传入，命中即停语义〕）+ 转数值 6（strtol/strtod 纯字节扫描已证与 oracle lossy 管道逐位等价；`errno` 以 `errno_addr : UInt?` 参数化解耦符号表；strerror 消息**含内嵌 NUL 计入 size**〔勘察 §3.2-9 口径〕，区域 ty 落 `"int"` 与 oracle `"char"` 的元数据微差登记）+ 杂项 9（`RandState` LCG / deterministic 时钟恒 0 / unreachable 文案 / `va_*` 4 件纯内存操作）。**`HostMemReply.value` 加宽 `UInt?→UInt64?`**（strtol/strtod/llabs 等压 64 位值；vm 值栈本就是 u64 位模式——0.6.0 面变更入 CHANGELOG） | ✅ S6 开工批二建包（2026-09-23，28 测试）+ **余量批一号（2026-09-23，28→68 测试：白盒 62 + 黑盒 6）**：受检访问一律经 memory 包单入口；两条 oracle 存量缺陷已两侧同修（2026-09-23 审阅批：calloc 置零次序换位 + 尺寸链回绕预检；锚 `calloc_reuse_after_eviction_no_uaf` / `calloc_oversize_reports_heap_exhausted`，全文见 CHANGELOG）；黑盒承担对外面消费面点名（每个 pub 符号 `@host.` 形态）。**余量批二号已落（2026-09-23，68→88 测试：白盒 81 + 黑盒 7）——printf/scanf/字符 IO 族 10**：printf 引擎（`format_fixed` 用 `@bigint` 精确十进制展开 + **half-even** 舍入对位 Rust `{:.*}`〔oracle release 实测锚：0.125→0.12、3.5→4、-0.0→"-0"〕；`%g` 指数段 `{:+#03}`；`powi10` 不走 `@math.pow`〔exp/log 位级不同〕；oracle 既有偏差照搬：`%+`/`% ` 旗标无效、`%.1s` 忽略精度、`%c` 高位字节经 char 通道变两字节；U2#9 宽度/精度 1MB 预算闸）+ `InputState` 输入状态机（游标/EOF 粘滞/ungetc/Batch-Interactive 双模式；`InputOutcome` 三值〔Value/Waiting/Trap〕承载 `waiting_input` 语义）+ scanf **V-P1-13 流式游标**（虚拟字节流 + 映射表推进，五连锚）+ A1 EOF 粘滞 + `%s` 栈缓冲校验 + sscanf（无守卫/逐臂计数——坑 17 照搬）。栈深守卫族内不一致照搬：printf/fprintf/scanf 有、sprintf/snprintf/sscanf 无。**审阅修复批（2026-09-23，100→104 测试）**：① **P1 `powi10` 重写**——oracle `10f64.powi` 语义（精确 10^e 最近舍入、平局向上、e=126 已知偏离显式锁定；**633 指数全表与本机 Rust 1.95 位模式对拍仅 e=126 差异**）；修复前逐乘链从 e≥23 起分叉（`%g` 9/60）、次正规区 `powi10(-320)=0` 致 `infe-320` 泄漏；DBL_TRUE_MIN 上两侧同形 `infe-324`（照搬 oracle 泄漏形状）。② **P2 `memchr` 补实现**（110 路由中唯一未登记缺口）+ 新闸 `host_route_coverage` 兜底；③ **P3 `%%` 锚补齐**（含 oracle 实测的 `used < args.len()` 守卫偏差：实参耗尽后 `%%` 原样输出；M4 突变复验新锚会红）；④ 弃用 API 清零（`Char::from_int`→`Int::unsafe_to_char` 7、`not()`→`!` 18、`try?`→try/catch 9、`Map::new()`→`Map([])` 2、`FmtScan`/`ScanfItem` priv）；⑤ `host_test.mbt` 7 处真 NUL 修复 + 新闸 `source_hygiene`（连带冻结区 `vitro_lexer/src/string.rs` 索引侧 `i/-text` 潜例修复）。
**余量批三号已落（2026-09-23，88→100 测试）——VFS 17 + vfs 本体**：`vfs.mbt`（`VirtualFileSystem`：文件表/描述符表/fd 计数；数据存 VM 堆〔区域名 `vfs:<name>`、FILE\* 名 `FILE:<path>`〕；文本模式 CRLF 伸缩三件〔逻辑↔物理互转 + `read_text_byte`〕；容量扩容 `max(2×容, 需求)` 对齐 4）——**坑 13 修复**（append 建文件：oracle 死分支恒不可达、追加写静默丢弃；本实现按 `VfsMode` 穷尽分支，**登记分叉**）+ `host_file.mbt` 17 handler（FILE\* 协议 = 堆上 4 字节存 fd；哨兵流 0/1/2 前置分支给 fd 0〔oracle 裸读 NULL 区零值的等价形态〕；fputs 的 stdout/stderr 通道分流 E-P1-5；perror → stderr）；**登记分叉续列**：VFS 内部分配/释放走 memory 单出口（FILE\* 释放进 UAF 窗口——二次 fclose 受检读 trap，oracle 裸读得陈旧 fd 返 -1〔`free_region` 不写 freed_logs——缺口②〕，已设分叉锚）、数据读写受检化（oracle `read_memory_to` 不查 UAF）、`fgets` 二进制模式也压 `
`（oracle 现状）。**未开工**：exit/abort/assert_fail/guards/STEP/OUTPUT/qsort/bsearch 控制流族（随 vm 片——`set_finished`/`call_user_function` 宿主回调哨兵是 VM 状态） |
命名规则：module = `vitro/engine`（mooncakes owner `vitro`），包全名 `vitro/engine/<pkg>` 一律全名，代码与配置禁用简称。

## 构建与验证命令

```bash
# —— moon 命令：cwd = moonbit/ ——
cd moonbit
moon check                # 快速类型检查（日常常跑）
moon check --target all   # 全后端检查（发布前）
moon test                 # 209 测试（白盒 _wbtest.mbt + 黑盒 _test.mbt + doc 测试；数字为 2026-09-21 快照，真值以 facts `moonbit_test_passed` 为准）
moon test --update        # 快照更新（inspect content= 变更时；核对 diff 再提交）
moon fmt                  # 格式化（生成物也参与——见 gen_diag 内置 fmt）
moon info                 # 生成 .mbti 接口面（API 变更信号；pkg.generated.mbti 入版本控制）
# —— 以下 go 驱动命令：cwd = 仓库根（不是 moonbit/）——
# 2026-09-22 勘误：此前本清单写作 `./scripts/gen_diag` 等（少了 `moonbit/` 段），
# 在 moonbit/ 与仓库根两处均无法运行（moonbit/ 下无 go.mod 也无 scripts/）；
# moonbit_surface.go 内部自带 os.Chdir("moonbit")，故必须从仓库根调用。
go run ./scripts/moonbit/gen_diag          # diag 码表再生成（内置 moon fmt）
go run ./scripts/moonbit/gen_diag -check   # 幂等校验（源变产物变 / 篡改即红）
go run ./scripts/moonbit/gen_host_route       # host 路由 110 对再生成（bytecode 包，源 host_func_id.rs；S6 自 codegen 上提）
go run ./scripts/moonbit/gen_host_route -check  # 幂等校验（同 gen_diag 三件套：落款 sha + fmt 内置 + 漂移红）
go run ./scripts/moonbit/gen_stubs          # 标准库存根表再生成（lexer/internal/host/stubs_gen.mbt，源 native/runtime_libc/include/*.h）
go run ./scripts/moonbit/gen_stubs -check   # 幂等校验（2026-09-23 审阅批重构：flag 包口径 + 内置 moon fmt + check 无写副作用——此前手工只认 --check 且无 fmt，干净仓库上必红、-check 单横线会静默改写产物）
go run ./scripts/moonbit/moonbit_surface -check # 对外面双面闸（①无主 pub 须收面或入白名单 ②跨包消费边须在 surface_edges.txt 登记——新边=面扩张必红；provider 全递归 17 包〔批一段全名口径 + 批二段全递归，2026-09-23〕；J9 注入双红留痕）
go run ./scripts/moonbit/source_hygiene      # 源码卫生闸（真 NUL 扫描——git 判二进制/diff 不可见事故族；白名单 source_hygiene_allowlist.txt；J9 证红）
go run ./scripts/moonbit/host_route_coverage # 路由覆盖闸（110 路由 ↔ host 实现；别名/VM 白名单规则外置 host_route_rules.json，白名单双向对账；J9 双路证红）
go run ./scripts/moonbit/libc_single_source -check # libc 三表单源对账闸（builtin_all == host ∪ bytecode - excluded；交集计数 + PURE 子集 + 空集不得绿；J9 三路证红 ✅）
go run ./scripts/moonbit/pkg_deps -check  # 包依赖方向断言（按总计划 §4 L0–L9：依赖只能向下或同层 + 无环；新包未登记分层即红；cmd/* 豁免方向；J9 证红 ✅）
go run ./scripts/moonbit/libc_boot_diff   # libc 自举对拍（MoonBit library mode ↔ Rust export；stub + wrapper 截断口径 + 9 交集字段；J9 证红 ✅）
go run ./scripts/moonbit/single_source -check # 单一真相源清单校验（判据 C-04 跨语言孪生层：8 条；enforced 判定义点文件集唯一、registered 验路径存在；J9 证红 ✅）
go run ./scripts/moonbit/mbti_sync -check # 接口面同步闸（.mbt ↔ pkg.generated.mbti；moon info 无 --check 故取跑前后快照不变量；判红时顺手自愈同步 .mbti；J9 证红 ✅）
go run ./scripts/perf_budget -check     # 性能假设预算闸（语料规模前提守护：typeck O2 债裁决依据 struct 定义 ≤2 / 成员访问 ≤37；超预算即红迫使重估；J9 证红 ✅）
go run ./scripts/toolchain_probe        # 工具链健康探针（版本锁定/索引预检/ICE 特征；升 moon 后必跑，漂移须 --update-baseline + 全门禁）
go run ./scripts/parser_diff <corpus>        # S3 解析差分（E1/E2/活性；仓库根跑）
go run ./scripts/parser_diff --pathological  # E3 病态 12 样本同等拒绝
go run ./scripts/parser_diff --legal-deep    # E4 合法深嵌套反向锚
go run ./scripts/parser_diff --threshold     # E3+ 阈值样本（A/B 族两侧一致 + C 族形状）
go run ./scripts/typeck_diff <corpus>        # S4 类型检查差分（E1 诊断/E4 类型化 AST + E2/E3 投影；红面基线期大面积 DIFF 属预期——typeck 实现推进中收敛）
go run ./scripts/codegen_diff <corpus> [--baseline] # S5 codegen 差分（A 级 14 键全量 + **槽位策略版本对账**〔读产物外层 slot_strategy ↔ scripts/codegen_diff/slot_strategy.json，不符或空集即红〕；--baseline 豁免 one-sided 能力缺口，CONTENT-DIFF 永不计豁免；仓库根跑，语料 native/tests/cases/codegen_skeleton 为骨架可通面）
```

测试计数真值入 facts 台账（`moonbit_test_passed` 键，`--run` 采集 / CI 每轮刷新）。**注意（2026-09-20 审阅实测）**：moonbit/README*.md 的测试数为**分解式**写法（逐包拆解 + `分解和 179 + doc test 4`），facts 规则将分解式归"人工维护"不机判——**机判抓红不覆盖该处**，改测试数同步 README 是人工义务；裸总数以 facts.json 真值为准。

## MoonBit 语言与工具链陷阱（全部一手实证，2026-09-19）

> 总计划 §3 的 F1–F9 仍有效；以下是**工程语法/工具层**补充，多数来自 S1 实作的编译器报错。

1. **`ref` 是保留字**——可变局部状态用 `let mut x = 0`（`Array.push` 改内容**不需要** mut，mut 只管重新绑定；unused_mut 默认 error）。
2. **比较 trait 是 `Compare` 不是 `Ord`**——`derive(Debug, Eq, Compare, Hash, Default)`；derive 子句在类型体 `{}` 之后。
3. **`derive` 不能作方法名**（关键字）——S1 用 `Pos::from_byte_off` 替代。
4. **枚举构造器可与其余类型名同名**（`Type::Int` 与内置 `Int` 按期望类型消歧）；但**两个枚举的同名构造器**（`AssignOp::Assign` vs `Expr::Assign`）在构造与模式两处都要显式 `Expr::Assign(...)` 限定。
5. **跨包类型必须 `@pkg.` 前缀**——包括 struct 字段类型与函数签名参数（`loc : @source.SourceLoc`），裸类型名会撞"未定义"或静默歧义。
6. **无参构造器模式**要逐参数通配：`Literal(_, _, _)`——`Literal(..)` 不是合法通配。
7. **`for k, v in` 只解构 Map**——元组数组迭代用 `for t in arr` 后 `t.0 / t.1`。
8. **fn 参数不能 `mut`**（`mut stack : ...` 是解析错误）；局部重绑定不需要时勿加 mut。
9. **大写开头的局部绑定非法**（`let L = ...` 编译错）。
10. **`assert_true(x)` 单参数**——带消息断言用 `guard cond else { fail("...") }`。
11. **`String::substring` 已弃用**——用切片 `s[a:b]`（ASCII 安全场景免 try）+ `.to_owned()`（视图转拥有串；`.to_string()` 在视图上同样弃用）。
12. **`<+` / `<?` 宏右侧只能接模板字符串/对象字面量**——任意表达式（函数调用、Int）不合法，用 `buf.write_string("...\{interp}")`。
13. **`1e16` 等 e 记法浮点字面量不可用**——写定点 `10000000000000000.0`；指数值用除法/构造。
14. **`Double::to_string` 与 serde_json/ryu 两处分歧**（实测）：整值 `1.0 → "1"`、负零 `-0.0 → "0"`；中段指数区间（≥1e16 / ≤1e-6）两侧记法不同。**JSON 浮点文本化必须走 `@ast.double_to_json_text`**（ryu-pretty 全区间对齐 + 非有限 → null）——那是单源，禁再写一份。
15. **moon fmt 宽度按 UTF-8 字节计**（中文 3 字节；超 ~84 字节爆开/折行）——**生成物与 fmt 会互踩**：gen_diag 的解法是生成流程内置 `moon fmt`，产物形态以 fmt 为准，gen 原始输出只是中间态。任何新生成器沿用此模式。
16. **doc 测试（docstring `mbt check` 块与 `*.mbt.md`）是黑盒**——被测包自动 import 为 `@self`，构造器要 `@pkg.Type::Variant` 形态；README.mbt.md 同理（它同时是可执行测试文件）。
17. **`moon.mod` / `moon.pkg` 是新格式**（非 .json）；`moon.pkg` 的 import 块声明依赖，代码内一律 `@alias.fn` 调用。
18. **mooncakes 发布规则**：module 名首段**必须等于发布者用户名**（`vitro/engine` ↔ 账号 `vitro`；403 User mismatch 即此因）；发布后 checksum 入 registry **不可覆盖**——修复只能递增版本；readme 字段须指向**根 `README.md`**（`README.mbt.md` 不会被模块页渲染）；索引同步有数分钟延迟（`moon add` 暂时 404 是正常节奏，轮询即可）。
19. **本仓库 bash 工具层的 heredoc 会吃一层反斜杠转义**（`\\n` 变真换行、`\r\n` 字面量损毁）——跨 heredoc 写 Go/代码文件时用 `chr()` 拼接或 python 中转写盘；此坑曾致 gen_diag 归一逻辑静默变空操作（P2-1 复盘）。
20. **core `Map`/`Set` 是可变哈希结构**（`Map::set(k,v)` / `Set::add(k)` 原地、返回 Unit；S3 实测）——勘察 M3 设想的"不可变结构共享快照"不成立，回滚快照 = `.copy()` 整表拷贝（教学符号表小，可接受）。
21. **`loop { ... }` 是函数式循环（deprecated 语法且 `break` 不适用）**——命令式循环写 `while true { ... break }`（S3 瀑布实测）。
22. **顶层常量用 `const`**（`let MAX_X = ...` 大写绑非法：Expected lower case identifier）。
23. **match guard 必须与模式同行**（`_ if cond =>` 跨行非法）；**或模式分支的构造器各自全参展开**（`Reference(..)` 不合法——`..` 剩余通配不存在，逐参数 `_`）。
24. **`String` 索引/`s[i]` 返回 UInt16 码元**（非 Char）——`write_char(s[i])` 类型错；切片 `substring(start=a, end=b)` 命名参数形态（位置参数形态非法）。
25. **数值位模式重解释**：`UInt64::to_int64` = `%u64.to_i64_reinterpret`（bitcast，正是 Rust `as i64`）；`Int64::to_int` 语义未文档化——i64→i32 截断自己写（低 32 位符号解释，见 parser/decl.mbt `i64_to_i32_bits`）；`Int::to_int64` 是符号扩展（= Rust `as i64`）。
26. **wbtest 不携带 `for "test"` import**（黑盒专用配置）——白盒测试要跨包输入就手工构造（如 token 数组），或把用例放黑盒。
27. **JSON 字符串输出必须转义 < 0x20 控制字符**（`\u00XX`，serde_json 口径）——C 转义序列（`\x4`）解析出的真字节原样写出即非法 JSON（S3 由 baseline 的 string_escape_octal_hex.c 差分抓出）。
28. **wasm 测试运行时的栈预算比 moonrun 更紧**（S3 实测：`interpret_declarator_node` **递归解释**形态 900 层过 / 1200 层溢出——目标 wasm；同函数迭代化后 1250 层全存活；`node_cross_count` 的纯计数递归在 wasm-gc/native 三后端 1250 层存活（S3 审阅实测）——旧区间只适用于"递归解释"形态，勿外推到计数函数）——深结构处理一律迭代化（显式栈/下钻折叠），不能依赖"Rust 侧能过的深递归这里也能过"。
29. **`String` 的 `compare` 与 `<`/`>` 均非字典序**（S5 bytecode 白盒实测：`"delta" > "charlie"` 为 **false**、`"delta".compare("charlie")` 返回 **-1**——疑似长度优先序）——排序/对拍类逻辑**禁用内置 String 比较**，按码元逐位自写字典序（见 bytecode/emitter.mbt `str_cmp`）；Go canonicalize 的 sort.Strings 是字节字典序，ASCII 域两者等价，非 ASCII 键域需显式裁定。

## MoonBit 语义实证补充（S6 建包批，2026-09-23 探针实测）

> 以下全部由一次性探针程序当场跑出真值（`inspect` 期望值锚），非文档推断。建新包前先把这些当既定事实，可省一轮编译-报错循环。

30. **struct 是"按引用"传递的**——**字段变更对调用方可见**，普通参数与 `self` 一样生效（实测：`fn bump(c : ProbeCtr) { c.n = c.n + 1 }` 连调两次后调用方看到 `n == 2`）。⇒ ① 需要"值语义"时得显式复制；② **这正是本仓 `MemoryMap`/`Memory` 能把"容器字段的变更"直接暴露给下游的原因**；③ 也意味着"返回内部结构"会暴露可写句柄，要控面就得控制返回类型。
31. **`mut` 字段的赋值不要求 `let mut`**——`let r = Rec::{ ... }` 后 `r.f = v` 合法（`mut` 只管**字段**，不管绑定；与陷阱 #1"mut 只管重新绑定"互补：那一句说的是局部变量，字段同理但受限更松）。match 绑定（`Some(r) => { r.f = v }`）同样合法。**结构展开 `{ ..r, f: v }` 可用**。
32. **`for k, v in` 对数组是 `(下标, 元素)` 解构，不是元组解构**（陷阱 #7 的补全）——`for a, b in array_of_tuples` 拿到的是 `Int` 下标，静默错类型，必须 `for t in arr { t.0 / t.1 }`；只有 `Map` 是 `(键, 值)`。
33. **core 的 `Map` 即 LinkedHashMap**（`linked_hash_map.mbt` 实现的就是 `Map`）——**迭代序 = 插入序**，且既有键 `set` **保持原插入位**（等键分支只写 value）；但**没有 `get_mut`**——就地改值要么 `update(k, fn(V?) -> V?)`（闭包内改 mut 字段），要么 `get` 出来改完 `set` 回去。⇒ "Vec + 平行索引"可整体换成 `Map[K, V]`：O(1) 定位 + 保序 + **失配面归零**（S6 memory 的 regions 即此形态，消掉坑 6 的根因）。
34. **弃用 API 三例（`moon check` 会给 `deprecated` 告警）**：`Array::new(capacity=)` → `Array(capacity=)`、`Deque::new()` → `Deque([])`、`Int::to_uint` / `UInt::to_int` → `reinterpret_as_uint` / `reinterpret_as_int`（**语义相同，只是把"重解释"写明**；注意 `to_uint64()` 未弃用）。
35. **`FixedArray[Byte]` 只有写侧 LE 原语**（`unsafe_write_uint32_le` / `..._uint64_le`），**读侧原语只在 `Bytes`**（`Bytes::unsafe_read_uint32_le`）——用 `FixedArray[Byte]` 当内存本体时，读必须手工 4/8 次索引拼装（与 Rust `i32::from_le_bytes([m[a],...])` 同形）。
37. **经 shell/python 管道写源码时反斜杠转义会层层衰减**（2026-09-23 P2-NUL 事故）：JSON→shell→python 三级解码会吃掉层层反斜杠（两层写法只剩一层，再经 python 字符串解析即成真字节）——`b"hello\x00"` 落成二进制文件、git 判 `w/-text`、15KB 测试 diff 不可见。写含转义序列的源码一律用 `chr(92)` 构造，或写完后 `source_hygiene` 扫一遍兜底。同族：注释里的 \n 会断行、Go 字符串里的 \n 会变真换行。
36. **测试宏的说明文字必须用 `msg=` 具名参数**——`assert_eq(a, b, "说明")` 会被拒（"requires 2 positional arguments"），写 `assert_eq(a, b, msg="说明")`；`assert_true`/`assert_false` 同理。另：**`_` 不能作 `for` 循环变量名**（`for _ = 0; ...` 是解析错误，换 `i`/`n`）。

## 编码与架构纪律（S1 已定型）

1. **穷尽 match 无兜底臂**——枚举增删变体必须让全仓编译红（gen_diag 生成的 137 臂 / opcode 全表 / emitter 均如此）；`from_code` / `from_u8` 这类 Int→枚举允许 `_ => None`（值域无限，数学必然）。
2. **显式 emitter 纪律**（B 级锚前提）：结构化导出（JSON）两侧手写序列化，禁一侧 serde 一侧 ToJson 派生——字段序、转义、浮点文本化在 emitter 单点对齐 Rust oracle。对拍管道：Rust serve 出口 → Go 归一器归一 → diff。归一单源 = `scripts/internal/canonicalize`（各 diff 驱动**进程内调用**，2026-09-22 抽库）；`go run ./scripts/canonicalize` 仍是**可执行的 CLI 壳**（stdin 进 stdout 出 / `--check`），**不可删**——冻结区 `native/tests/ast_dump_test.rs` 以子进程方式依赖它。
3. **生成物纪律**：`diag/error_code_gen.mbt`、`diag/catalog_gen.mbt` 禁手改（文件头源 sha256 落款）；源（native 侧）变更后必须再生成并提交，`-check` 在 CI/审阅中防漂移；行尾归一双保险（.gitattributes 锁 moonbit/** LF + `-check` 比较前归一）。
4. **照搬不私改**：从 Rust oracle 迁移的定义（opcode 编号、判等语义、Display 渲染口径、mangle）逐字照搬；发现 oracle 现状可疑（如 Display 丢 unsigned）**登记不修正**——差分对拍期两侧一致优先，裁定走差异台账。
5. **坐标契约**（vitro/engine/source）：`column` = 行内 UTF-8 字节偏移 + 1；双坐标消费方用 `Pos`；禁字节/字符量纲混算；词法 +1 现状不复刻。输入档案：`docs/current/07-质量与裁定/列号口径冻结.md`。
6. **诚实延后登记**：暂缓项在包注释/计划文档写明原因与回归时机（如 operand 语义校验待 S5 发射侧实证、E1 全量对拍管道待 S3 parser）。

## 发布流程（T5 定型）

```bash
# 前置：moon check --target all 干净（豁免：Show→Debug 迁移期噪音 10 条，
#       全系 inspect 系测试 API 依赖 core 旧 trait，无本仓侧干净替代——
#       见 S3 执行记录 §7-9/§8-6；core 稳定后清零）+ moon test 全绿 +
#       moon info 无意外 diff + gen_diag -check 绿
cd moonbit && moon publish        # Server 200 OK 后：
# 验收：moon search vitro 可查 → 全新项目 moon add vitro/engine@<ver> →
#       安装后跑一段示例；包 zip（~/.moon/registry/cache）核对根级四件：
#       LICENSE / README.md / README.mbt.md / moon.mod
```

版本语义：修复发布内容 → patch；新增包/公共 API → minor。137 码位等 versioned 常量只增不改。

## facts 接线

`moonbit_test_passed`（`--run` 门采集，cached 沿用）——新增防线产物时按 `moonbit_*` 前缀扩键（总计划 §10 每片回填义务），采集器在 `scripts/facts/facts.go::collectMoonbit`（冻结区，改动属防线维护白名单）。
