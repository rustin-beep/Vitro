# Changelog

All notable changes to the Vitro project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed (S6 审阅修复批：P1/P2/P3 全销项，2026-09-23)

用户 blob 级审阅（五阶段复核）+ 本轮逐条亲验后修复；每条红→绿留痕。

- **P1 `powi10` 重写（数值，`format_g` 的 10^e 路径）**：oracle 用
  `10f64.powi(e)`（= 精确 10^e 的最近舍入，633 个指数中仅 e=126 偏 1 ulp），
  旧实现逐乘链从 e≥23 起分叉（实测 `%.17g` 6/6 特选值分叉、默认 `%g`
  抽样 2/100），次正规区 `powi10(-320)=0` 导致 `8.88e-320` 输出 `infe-320`。
  新实现 = `@bigint` 精确有理数 + 最近舍入（`2r ≥ d` 进位 = 平局向上）+
  **e=126 显式锁定**；**633 指数（-324..308）与本机 Rust 1.95（oracle 同
  工具链）位模式全表对拍**。红→绿锚：`format_g_powi_oracle_alignment`
  （12 值 oracle release 真机锚，含 `1e23→0.9999999999999998e+23`、
  DBL_MAX、次正规、**DBL_TRUE_MIN→`infe-324`**——oracle 自身 `powi(-324)=0`
  的泄漏形状照搬同形）/ `powi10_bit_alignment`（10 点抽查）。
- **P2 `memchr` 补实现**：110 路由中**唯一未登记缺口**（oracle
  `string.rs:426-442` 有 handler、月球侧整批漏实现；既有对账锚只校验
  「常量↔名字」不校验「路由↔实现」）。红锚 `memchr_scan_unsigned_and_bounds`
  → 实现 → 绿；登记分叉（越界从静默 break 转受检 trap，读侧同族）。
- **新闸 `host_route_coverage`**：路由名 ↔ host 实现覆盖对账（规则外置
  `host_route_rules.json`：别名 / vm 白名单；**白名单双向对账**——出现实现
  即红逼清理）。J9 双路证红（删别名 → 未实现红；白名单塞已有实现 → 过期红）。
- **P3 `%%` 语义锚**：全批零 `%%` 用例（M4 突变实证：`parse_format_specs`
  不跳 `%%` 时 100/100 仍绿）。补 `printf_percent_percent_semantics`
  （**全部 oracle release 真机可验形状**：`"100%%"→"100%%"`、
  `"%d%%"→"42%%"`、`"a%%b%dc"→"a%b7c"`、`"%d%%|%d"→"7%|9"`）——
  锚定过程反查出 **oracle 既有偏差**：`%%` 展开带 `used < args.len()`
  守卫，**实参耗尽后原样输出**（C 语义会展开）；同批登记 typeck 层
  尾 `%` 计入说明符计数的形状（`printf("x%")` 被 E3032 拒）。M4 突变
  复验新锚会红后恢复。
- **P3 弃用 API 清零（host 包）**：`Char::from_int`→`Int::unsafe_to_char`
  7 处、`not()`→`!` 18 处、`try?`→`try/catch` 9 处（含 5 个
  `parse_*_or_zero` wrapper 重写）、`Map::new()`→`Map([])` 2 处、
  `FmtScan`/`ScanfItem` 加 `priv`、未用变量/self 清理 —— host 包
  警告数归零（全局 232→191，余下为其他包既有 Show→Debug/implicit-impl 噪声）。
- **P2 真 NUL 修复 + 新闸 `source_hygiene`**：`host_test.mbt` 7 处真 NUL
  （`b"hello\x00"` 落真字节）致 `git ls-files --eol = w/-text`、
  `git diff --stat = Bin 4802→15346`——**15KB 黑盒测试在 diff/PR 中完全
  不可见**；修复为转义写法（diff 恢复文本：273+/3-）。新闸扫描
  **git tracked 全部文件**的真 NUL（fail-safe 无扩展名白名单；
  allowlist 空集），J9 证红留痕。**连带深挖出冻结区潜例**：
  `native/crates/vitro_lexer/src/string.rs` 的 `'<真NUL>'` 字面量使该文件
  **索引侧 `i/-text` 长期潜伏**（diff 不可见）——改等价转义 `'\0'`，
  `cargo test --workspace` 75 套件 1029 测试复跑全绿。
- **P3-3 `scripts/**` 行尾治理**：`.gitattributes` 补
  `scripts/** text eol=lf`（此前 autocrlf=true 下工作区恒 CRLF、本地
  `gofmt -l` 恒 24 项红——含 **15 项真格式漂移**，非全部行尾假阳性，
  对审阅结论的修正）；33 个 tracked 文件工作区归一（内容零变更，纯 stat
  刷新）+ `gofmt -w` 清 13 处存量漂移（含本批新文件）；**gofmt 入 CI
  hygiene**（scripts/ 必须 gofmt 干净）。
- **CI 接线**：core job +2 步（`source_hygiene` / `host_route_coverage`），
  hygiene job +1 步（`gofmt -l scripts/`）。
- **验证**：moon test 347/347（host 104）；moon check 0 错；十一闸全绿；
  `gofmt -l scripts/` = 0；`go build/vet/test ./scripts/...` 全过；
  cargo test --workspace 1029/1029；README×2 连坐。

### Added (S6 host 余量批三号：VFS 17 handler + 虚拟文件系统本体，2026-09-23)

- **`VirtualFileSystem`**（Rust `vfs.rs:1-771` 照搬）：文件表/描述符表/fd
  计数；**数据存 VM 堆**（区域名 `vfs:<name>`、FILE\* 名 `FILE:<path>`，
  前端内存 Canvas 可直接可视）；文本模式 **CRLF 伸缩三件**
  （`logical_to_physical`/`physical_to_logical`/`read_text_byte`——读压
  `\r\n`→`\n`、写展开）；容量扩容 `max(2×容, 需求)` 对齐 4；`fseek` 负目标
  统一 -1 不动游标（U2#13）；`ftell` 返物理游标（Windows CRT 口径）；
  文本模式 SET/CUR 走逻辑↔物理、END 基于物理末尾（照搬）。
- **坑 13 修复（登记分叉）**：oracle `fopen(path,"a")` 的建文件分支嵌在
  `Write` 块内**恒不可达**（追加写对新文件静默丢弃）；本实现按 `VfsMode`
  穷尽分支、Append 独立建文件路径——oracle 侧修复列两侧同修候选。
- **17 handler**（`host_file.mbt`）：FILE\* 协议 = 堆上 4 字节存 fd
  （`fopen` 分配 + 清 freed_logs + 登记 + 命名）；**哨兵流 0/1/2** 前置分支
  给 fd 0（oracle 裸读 NULL 区零值的等价形态，避免 NULL trap）；`fputs`
  的 stdout/stderr 通道分流（E-P1-5）；`perror` → stderr（空前缀 `"Error\n"`）；
  `fread`/`fwrite` 尺寸链防护（乘法溢出/超 MEM_SIZE → 0）。
- **登记分叉续列**：VFS 内部访问一律走 memory 受检单入口——① FILE\* 释放
  走 `release` 单出口（进 UAF 窗口）：二次 `fclose` 受检读 trap，oracle
  裸读得陈旧 fd 返 -1（`free_region` 不写 freed_logs——缺口②），已设分叉锚；
  ② 文件数据读写受检化（oracle `read_memory_to` 不查 UAF）；③ `fgets`
  二进制模式也压 `\r\n`（oracle 现状照搬，C 语义二进制不该压）。
- **验证**：moon test 343/343（host 88→100：白盒 93 + 黑盒 7）；
  moon check 0 错；九闸全绿（面闸无主清零）；README×2 连坐。
- **登记未落地**：fd 元数据进 `VMSnapshot`（随 vm 片落形——VFS 数据结构
  本身即克隆态；oracle `snapshot_files`/`restore_files` 是死代码不搬）；
  `fprintf` 到自定义 FILE\* 不落盘（oracle 既有偏差，落盘裁定随 VFS 增强批）。

### Added (S6 host 余量批二号：printf/scanf/字符 IO 族 10 handler，2026-09-23)

- **范围**：`host_printf_n` / `host_fprintf_n` / `host_sprintf` / `host_snprintf` /
  `host_scanf_n` / `host_sscanf` / `host_getchar` / `host_ungetc` / `host_puts` /
  `host_putchar`。host 的 110 路由表现余仅 VFS 17（批三号）与控制流/回调
  族 9（随 vm 片）。
- **`format_fixed`——Rust `{:.*}` 的等价实现（本批核心新件）**：MoonBit 无
  定点格式化 API；用 `@bigint` 做**精确十进制展开**（`e ≥ 0` 整数路径 /
  `e = -k` 时 `m × 5^k` 即 `|val| × 10^k` 的精确整数）+ **half-even 舍入**
  （比较 `2r` 与除数、平局取偶）。**值锚全部来自 oracle release 二进制
  实测**：`%.2f` 0.125→`0.12`、`%.0f` 3.5→`4`、999999.5→`1000000`、
  `%.0f` -0.0→`-0`、2.675→`2.67`、0.05→`0.1`。
- **printf 引擎照搬要点**：`%g` 边界（exp=-4 定点 / exp≥prec 科学计数）
  与指数段 `{:+#03}`（实测 `1e-05`/`1.23457e+06`）；`powi10` 用逐乘实现
  （`@math.pow` 是 exp/log 语义，位级不同）；U2#9 宽度/精度 1MB 预算闸；
  **oracle 既有偏差照搬（差异台账域）**：`%+`/`% `/`%#` 旗标无效
  （`apply_width` 只实现 `-`/`0`）、`%.1s` 忽略精度（'s' 分支不取
  precision）、未知说明符原样输出且**消耗实参**、`%c` 高位字节经 char
  通道变 UTF-8 两字节（`putchar(200)` 实测落 `C3 88`——DIFF-LIB-PRINTF
  族）。
- **`InputState` 输入状态机**：oracle `RuntimeState` 输入域整块搬来
  （`lines/index/char_offset/stdin_eof` 粘滞/ungetc/Batch-Interactive）；
  `InputOutcome{Value/Waiting/Trap}` 三值承载 `waiting_input` 语义
  （vm 接线：置位 + ip 回退 + 参数回推）。
- **scanf V-P1-13 流式游标照搬**：虚拟字节流 + 映射表（行间补 `\n`）
  按实际消费量推进——五连锚实证（"1 2"/"3 4" 依次读 1,2,3,4 后 EOF）；
  A1 EOF 粘滞（Batch 耗尽返 -1；字面量不匹配流不动**不**置 EOF）；`%c`
  经补位读到行分隔；`%s` 栈缓冲容量校验（V-P1-6）；`%f` 写 f32 位模式 /
  `%lf` 写 f64。
- **坑 17 族内不一致照搬**：printf/fprintf/scanf 有参数计数守卫（教学
  trap），sprintf/snprintf/sscanf 没有（实参耗尽即字面透传）。
- **登记分叉（批一号口径延续）**：fmt 串与 `%s` 实参受检读（oracle 裸读
  不 trap）；sscanf 源串按字节扫描（oracle 经 lossy char——非 ASCII 的
  `%c` 落点/空白判定不同，A-10 族）；scanf fmt 层非 ASCII 空白指令忽略
  （oracle unicode 空白入指令）。
- **面变更**：新增 pub 13 符号（10 handler + `InputState`/`new` +
  `InputOutcome`），黑盒点名消费；新消费边 8 条（bigint/double 常量/
  string parse 族）登记边表；`PRINTF_FIELD_BUDGET` 收私有。
- **验证**：moon test 331/331（host 68→88：白盒 81 + 黑盒 7）；moon check
  0 错；九闸全绿；README×2 连坐。

### Added (S6 host 余量批一号：70 个 VM 无耦合 handler，2026-09-23)

- **范围**：110 路由表的 VM 无耦合子集一次建齐——ctype 14 + math 22 + 字符串/
  内存 19 + 转数值 6 + 杂项 9（rand/srand/time/clock/unreachable/va_*4）。
  留给后续：printf/scanf/IO 族 10（批二号）、VFS 17（批三号）、控制流/回调
  族 9（随 vm 片——`set_finished`/`call_user_function` 是 VM 状态）。
- **读侧口径（既定接纳方案落地）**：oracle 字符串读路径是裸读
  （`read_cbytes` 只查下界——`strlen(NULL)=0` 静默〔坑 16〕、UAF 静默读
  内容、越界当 0 软夹紧〔坑 18〕）；MoonBit 侧一律走 memory 包受检单入口
  （NULL→UAF→上界），**该 trap 的现在会 trap**——合法输入逐字节一致，
  分叉只出现在 oracle 绕检形状（3 条登记分叉锚：`strlen_null_traps_
  divergence` / `uaf_read_traps_divergence` / `memset_freed_region_traps_
  uaf_divergence`）。界内软夹紧照搬（memset 超长截断到内存尾、strncpy
  负 n 补零到尾——U5#3 形状）；`memset/memcpy/memmove` 写已释放块与
  oracle U5#1 无检的分叉登记两侧同修候选。
- **`strpbrk/strspn/strcspn` 字节语义**：oracle 经 `from_utf8_lossy` 走
  char 语义（非 ASCII 下偏移与原内存错位——坑 8 同族静默错值形状）；
  MoonBit 按 C 字节语义实现——ASCII 域与 oracle 逐位一致，非 ASCII
  oracle 侧缺陷登记两侧同修候选。
- **strcpy/strcat E3070 双重校验照搬**：堆块容量（第一个包含 dest 的存活
  块，`>=` 起始口径）+ V-P1-6 栈缓冲容量——栈缓冲以 `StackBufferSpan`
  显式参数传入（vm 接线时展平 call_stack，逆序=内层优先，命中即停），
  文案逐字照搬 oracle。
- **转数值族**：strtol/strtod 纯字节扫描已证与 oracle lossy 管道逐位
  等价（lossy 串的 ASCII 空白/数字判定与原始字节同构）；`base=0→10` 且
  **不剥 `0x` 前缀**（oracle 现状照搬）；`errno` 以 `errno_addr : UInt?`
  参数化解耦符号表（写入失败照搬 oracle 静默忽略）；`atof` 整串 parse
  失败→0.0（与 C 取前缀的偏差是 oracle 既有行为）；`strerror` 消息
  **含内嵌 NUL 计入 size**（勘察 §3.2-9 口径），区域 `ty` 落 `"int"`
  与 oracle `"char"` 的元数据微差登记。
- **math 族位级对位**：`@math`（`log→ln`）+ `Double::sqrt/abs/mod`（IEEE
  fmod——`fmod(x,0)=NaN` 探针实测与 libm 同）；位模式经
  `reinterpret_as_uint64/reinterpret_as_double` 零损耗往返（3.14 ↔
  4614253070214989087 锚）；**登记**：oracle 弹参序不一致（pow 先弹 x、
  atan2 先弹 y）为 vm 接线义务；@math 与 libm 的 ULP 级差异是 D 级对拍
  风险（差异台账 S8 收口）。
- **杂项**：`RandState` LCG（seed=42 首值 3611 硬锚 + u32 回绕关系锚）；
  time/clock deterministic 恒 0（Phase 1 判分确定性口径）；`va_*` 四件
  为纯内存操作（游标 u32 读写）。
- **面变更（0.6.0）**：`HostMemReply.value : UInt? → UInt64?`（strtol/
  strtod/llabs 等压 64 位值——vm 值栈本就是 u64 位模式）；新增 pub 面
  约 72 符号（70 handler + `StackBufferSpan` + `RandState`），黑盒点名
  消费（新消费边 20 条已登记 `surface_edges.txt`）。
- **验证**：moon test 311/311（host 28→68：白盒 62 + 黑盒 6）；moon check
  0 错；九闸全绿（moonbit_surface / mbti_sync / pkg_deps /
  libc_single_source / single_source / gen_diag / gen_host_route /
  gen_stubs / perf_budget）；README×2 测试数连坐更新。

### Fixed (S6 批一段：moonbit_surface 面闸口径修复，2026-09-23)

- **三处口径不一致之①③修复**（消费侧取目录末段 / provider 按 `@别名` 末段归账 /
  边表两侧末段形式——同名条目只能靠注释区分）：闸门重写为**包全名口径**
  （`vitro/engine/<pkg>`）。`@别名.` 依据**消费文件所属包的 moon.pkg import
  块**解析：普通源码/wbtest = main 块（+ 自引用——注释里的 `@pkg.` 自称按
  自消费归账，保持旧口径）；`*_test.mbt` 与包内 README*（黑盒/doc 测试）=
  main ∪ `for "test"` ∪ 自引用（被测包按末段别名隐式 import）；模块根
  README*（发布面文档承诺）按全仓包末段解析，**歧义即红**（当前 `@host.`
  即末段撞车：L7 与 `lexer/internal/host`）。`as` 显式别名 / 非 `for "test"`
  scope / 块内别名冲突 / 未知别名一律 fail loud。
- **危害与动机**：旧口径下 `lexer` 对 `lexer/internal/host` 的消费（别名
  `host`）会假性救活 L7 `host` 的同名符号——该收的 pub 收不掉（「少收」，
  安全侧）；S6 余量批 ~106 handler 与 VFS 的名域（`vfs_provider` 等）恰与
  L4 存根域撞名，触发线已到。
- **J9 留痕**：注入 `host::vfs_provider` 同名对——旧闸静默放行（可收清单
  4 个纹丝不动、`-check` 绿）；新闸正确分离报「漏收 vitro/engine/host
  vfs_provider」；撤探针后复绿。未知别名注入红（指明文件/consumer/处置）；
  根 README `@host.` 歧义注入红（不静默择一）。
- **边表/白名单全名化重刷**：边 225 条 **1:1 纯改名零漂移**（根 README
  consumer 记 `.`、core/第三方库 provider 记完整路径如
  `moonbitlang/core/string`）；白名单 4 键同步全名化。
- **验证**：moon test 271/271；moon check 0 错；moonbit_surface / mbti_sync /
  pkg_deps / libc_single_source / single_source / gen_diag / gen_host_route /
  gen_stubs 八闸全绿。
- **未做（批二段，挂 0.6.0 发布前）**：提供侧 `Glob("*/pkg.generated.mbti")`
  仍只扫一层——4 个子包（`lexer/token`、`lexer/internal/{host,pp,scanner}`）
  pub 面未入「无主判定」；全递归属行为扩张，与既有收面义务合批。

### Fixed (S6 开工批二审阅批：P1–P6 + oracle 存量缺陷①②两侧同修，2026-09-23)

- **oracle 存量缺陷①（`calloc` 置零先于清理 ⇒ UAF 误报）两侧同修**：
  `host_calloc` 把 `freed_logs_remove_overlapping` 提前到置零之前（一行换位，
  与 malloc/realloc 次序对齐）。修复前 `allocate_raw` 复用隔离驱逐块时，该块
  检验窗口未清，置零的受检写撞自己的窗口 → 对刚被合法重分配的块误报
  Use-After-Free（E3060）。红→绿锚：`native/tests/cases/baseline/
  calloc_reuse_after_eviction.c`（600×512B churn 触发隔离驱逐 + first-fit
  复用，修复前 vitro 侧 UAF trap / Clang 正常输出 `0`、`7`；修复后 match）；
  MoonBit 侧锚翻转为 `calloc_reuse_after_eviction_no_uaf`。
- **oracle 存量缺陷②（`calloc` 尺寸链饱和后回绕 ⇒ 静默元数据损坏）两侧同修**：
  `total` 在 `align4` 之前先与 `MEM_SIZE` 比较，超限直接走堆耗尽分支。修复前
  `saturating_mul` 饱和到 `0xFFFFFFFF`，`align4` 的 32 位加法回绕成 0，
  `allocate_raw(0)` 按"零尺寸分配"短路成功——超大 `calloc` 不失败，反登记
  `addr=0 / size=-1` 的垃圾区域（debug 构建下 `(total + 3)` 直接加法溢出
  panic——红锚实测）。红→绿锚：
  `host_contract_tests::test_calloc_oversize_size_chain_reports_heap_exhausted`
  （修复前 panic FAILED / 修复后断言 NULL + note 附注 + 无垃圾条目）；MoonBit
  侧锚翻转为 `calloc_oversize_reports_heap_exhausted`。两条缺陷的 MoonBit
  侧原固化锚（照搬期锁行为）在修复落地时均先实测转红再翻转。
- **P1（未登记语义偏差）**：`realloc(p, 0)` 遇**已释放**指针，oracle 报
  E3027（内联释放不查 Double-Free，`trap_invalid_free` 的 freed_logs 分支被
  `log.addr != addr` 滤掉落兜底），MoonBit 侧误走 `host_free` 的 Double-Free
  前置报 E3061。修复：`host_realloc` 零尺寸分支直走 `MemoryMap::release`
  单出口 + `invalid_free_message`（oracle 真机实测对齐）。红→绿锚：
  `realloc_zero_size_on_freed_ptr_matches_oracle`（既有锚用的是从未分配的
  `0x8800U`，恰好绕开此路径）。
- **P2（未登记文案偏差）**：E3060 UAF 文案丢动作词（`写入`/`读取`——
  `AccessKind` 就在 `MemFault` 载荷里却被 `_` 丢弃）与时间轴行的"释放
  （第 N 步）"段。`access_fault_text` 补渲染动作词；时间轴整行（含当前步，
  VM 状态）与 `NullDeref` 写侧变体、`OutOfBounds` 符号表增强文案登记为
  vm 接线义务（oracle `core/memory.rs:199-205` + `trap.rs:6-61` 口径）。
- **P3（声明 > 现状）**：`is_host_rerouted` 自称"单点收口"但 codegen 仍两处
  硬编码。修复：`codegen/gen.mbt` 预注册跳过改调 `@bytecode.is_host_rerouted`
  （语义恒等）——新增改判名只改 `route.mbt` 一处即全链生效（`call.mbt` 经
  `func_index` 间接消费，无独立例外知识，保持现状是有意为之）。
- **P4（文档数字错）**：`README.md` / `README.mbt.md` 的 `bytecode 14 /
  codegen 16` 真值均 15（上批移动路由锚后漏改）；连同本批 host +1 锚，总数
  270 → **271**（分解和 265 + 根 README doc test 6）。
- **P5（闸门空窗）**：`gen_diag` / `gen_host_route` / `gen_stubs` 三个生成器
  的 `-check` 均不在 CI——产物漂移只能靠人跑。ci.yml 补"generated-artifact
  freshness"步骤（core job，mbti_sync 之后）。**前置修复（gen_stubs 自身两处
  缺陷，J9 证红留痕）**：此前手工只认 `--check` 双横线（`-check` 静默落入
  生成路径直接改写产物）且生成输出未过 `moon fmt`（干净仓库上 `--check`
  必红，无法入 CI）——重构为 flag 包 + 内置 fmt + check 无写副作用。
- **P6（多余依赖）**：`moonbit/host/moon.pkg` 的 `for "test"` 块声明
  `vitro/engine/libc` 全包零使用（`moon check` unused_package warning）——删除。
- **验证**：`vitro_cli run` 真机实测两侧（realloc(p,0)/E3027、UAF 读写文案、
  calloc churn 用例修复前后）；MoonBit `moon test` 271/271；Rust
  `host_contract_tests` calloc 族 4/4。
- **登记（审阅发现，未修）**：oracle 输出通道在 `putchar(>= 128)` 上与 Clang
  **必然不等**——`runtime.stdout() -> String` 把 `0xC8` 重新编码成 UTF-8 两字节
  `C3 88`，Clang 输出单字节（实测 `putchar(200); putchar(201)` → Clang `c8 c9`，
  oracle `c3 88 c3 89`）。MoonBit 侧输出通道 Bytes 化已对齐 Clang（`0xC8` 落
  1 字节）；shadow 语料**零覆盖**该形状（`putchar(1xx/2xx)` 在 templates/ 与
  native/tests/cases/ 零命中），故该差异从未被防线暴露。补语料的时机在
  MoonBit 引擎接线 shadow 时（届时 MoonBit 侧应为 green、oracle 为 red，且需
  与 `KNOWN_FAILURE_CASES` / `KNOWN_TEMPLATE_FAILURES` 双向监控机制同步登记）。

### Added (S6 开工批二：`vitro/engine/host` 建包 + 路由表单源 + 输出通道 Bytes 化，2026-09-23)

- **范围**：S6 三包（memory / host / vm）的第二片。执行输入仍是勘察报告（任务书），
  落地的是 §5.5「三实现合一 + 输出通道字节累积」与 §9.2 约束 #1/#4，外加 §2.1 的
  host 语义资产。**memory 片已完成**（前一条目）；**vm 片未开工**；host 的其余
  ~106 个 handler 与 VFS 留待下批。
- **① 调用形态单一路由表**（§5.5「把隐式覆盖变成显式声明」）：
  - 现版同一函数最多三条实现路径，且路由分叉**不可见**——`func_index` 预注册的
    88 名会静默遮蔽同名 host handler，**110 个 handler 里有 20 个按名调用到不了，
    而全仓无一处能列出这 20 个名字**。新增 `bytecode/route.mbt`：`CallRoute`
    （`BytecodeLibc(idx)` / `Host(id)`）+ `call_route` 单一派生规则 +
    `shadowed_host_names()` 让遮蔽集成为**可断言事实** + `is_host_rerouted`
    把 strcpy/strcat 的 E3070 例外收成单点。
  - `gen_host_route` 产物自 `codegen/` **上提到 `bytecode/`**（同一 L6 层内换包），
    并补出 `host_func_pairs` 全名表——`host_func_id_by_user_name` 照搬 Rust
    `by_user_name` 语义对 14 个 PURE 名**短路返回 None**，**不能**当成员判定用。
  - **落点裁定（登记为任务书内部不一致）**：总计划 L7 行写"host(110 路由表单源)"，
    但 §4 硬约束"依赖严格单向"禁止 codegen(L6) → host(L7)，而 codegen 在编译期就必须
    选 `Call <固定索引>` 还是 `CallHost <id>`；又因派生需 88 名单源（在 L6），libc(L5)
    也无法反向 import L6。⇒ 定义点只能 ≤ L6，落 `bytecode`（与固定索引同层同域）。
    生成器头注 / `route.mbt` 模块头 / 总计划 L7 块三处已写清。
- **② 输出通道 Bytes 化**（§5.5「输出通道改为字节累积」+ §9.2 约束 #4）：
  `OutputKind`（stdout/stderr/note 三通道）/ `OutputChunk` / `OutputLog`。
  片段的承载从 `String` 改 `Bytes` ⇒ **非 UTF-8 字节保真**（`putchar(200)` 落
  1 字节 `0xC8`；String 化会成 2 字节 `C3 88`——现版预期 FAIL 的正是这条）。
  语义照搬 Rust：16MB 预算、环形丢最旧保最新、单块超预算截头保尾、截断注记只补一次、
  note 不占预算不丢弃不入合并、64B 小段合并、O(1) 长度。**三处结构性适配**：
  （a）`Bytes` 不可变故小段合并会退化 O(n²)，故未封口尾块用可变累加缓冲、封口时一次物化；
  （b）**读取走只读视图、不封口**——Rust 的 `chunks` 是稳定结构，读 `len()` 不影响
  后续合并；若读取顺手封口，则"读一次再写小段"会另起一块（实测块数 1→2），与 Rust 分叉；
  （c）部分截除**不做 UTF-8 边界对齐**（Bytes 无"非法 UTF-8"；刻意差异）。
- **③ 内存族 handlers**：`host_malloc` / `host_calloc` / `host_realloc` / `host_free`
  + E3061 / E3027 三分支文案 + 堆耗尽附注。与 Rust 的**结构性差异**：handler 返回
  `HostMemReply{value?, note?, trap?}` **三件结构化事实，不碰值栈**——压栈与发 trap
  归执行器。收益是内存语义可**脱离 VM** 锚定（Rust 同族用例必须先 `setup_vm` +
  手工 push/pop），且"同一语义 host 与 core 两处各写一遍"的病灶只剩一处。
  受检访问一律经 memory 包单入口：`calloc` 置零走段级 `fill`、`realloc` 搬运走段级
  `copy`（Rust 是逐字节 `store_i8` 循环，每条字节重跑一次 NULL/上界/UAF 判定）。
- **新发现两条 oracle 存量缺陷（照搬不私改 + 登记 + 红锚固化）**：
  ① **`calloc` 的置零发生在清理 freed_logs 之前** ⇒ `allocate_raw` 从 `free_list`
  复用驱逐块时，置零会撞上该块自己的检验窗口 → **Use-After-Free 误报**（该块刚被
  合法重分配）。触发条件：此前分配使隔离区超预算。修复形态是一行换位；
  ② **`calloc` 尺寸链饱和后仍回绕** ⇒ `align4(0xFFFFFFFF)` 在 32 位加法下等于 0，
  `allocate_raw(0)` 按零尺寸短路成功，于是"超大尺寸"**不失败**，反而返回 NULL 并登记
  一条 `addr=0 / size=-1` 的**垃圾区域**。这是独立于坑 9（`qsort` 那条已被 `checked_mul`
  修掉）的第二条路径——`calloc` 用的是 `saturating_mul`。已给 `MemoryMap::verify`
  增补"区域条目有效性"检查，把这条静默损坏变成**可断言事实**。
- **memory 包补三处 host 必需的查询面**：`FreedLogs::get` /
  `MemoryMap::freed_logs_get`（E3061 文案要 `freed_line`/`alloc_line`）/
  `MemoryMap::find_live_region_containing`（E3027「内部地址」判定）+
  `verify` 的区域有效性检查。
- **锚点**：host 27 测试（白盒 24 + 黑盒 3）、bytecode 新增 6（路由表黑盒契约）。
  三条跨包对账锚：遮蔽名单逐字对齐勘察 §1.7；路由并集（176）与 `vitro/engine/libc`
  放行名全集逐名对齐（差 `print_int` 别名——S4 坑②「以 libc 为单源回填」在此接续）；
  每个表内名恒有唯一形态。
- **J9 证红留痕（三路，注入后字节级还原）**：① 路由表 `is_host_rerouted` 改恒假
  ⇒ 遮蔽清单与路由锚变红；② `OutputLog::push` 去掉合并分支 ⇒ 小段合并锚变红；
  ③ `host_free` 的 Double-Free 前置判定改后置 ⇒ E3061 锚变红。
- **门禁全绿**：`moon check --target all` 0 错、`moon test` **270/270**、十闸 PASS。
  工具侧同步：`single_source` / `libc_single_source` 的规则 JSON 更新产物路径；
  `surface_edges.txt` +12 条边（含 `codegen bytecode host_func_id_by_user_name`）。
- **闸门盲区登记（新发现）**：`moonbit_surface` 的 consumer 侧按**目录末段**取名，
  而 L4 `lexer/internal/host` 与 L7 `vitro/engine/host` 末段同为 `host` ⇒ 两者的
  `@host.` 引用会互相被当作"已消费"（本批符号名与
  `{stub_lookup,stubs_provider,vfs_provider,StubsProvider,VfsProvider}` 无交集，
  故未触发；已在边清单注释登记）。

### Added (S6 开工批：`vitro/engine/memory` 建包——1MB 载体 + 堆状态机 + `checked_access` 单入口，2026-09-23)

- **范围与依据**：S6（`vitro/engine/{memory,host,vm}`）开工批，只做 `memory`
  一片（纯算法、零下游依赖、可独立红锚验收，符合"分片可停可续"）。执行输入是
  勘察报告（任务书）`MoonBit迁移_vitro_vm与vitro_runtime模块勘察报告20260918`
  （提交 `917251e` 内，仅存于 git 历史）。落地的是该报告的**资产 R + M 建议**，
  不是"Rust 现状直译"：`§5.1`（载体/元数据分离 + 单入口 + 脏页移位 + 批量快路径）、
  `§5.5`（freed_logs 有序数组 + 二分 + 内存不变量自检）、`§9.2` 约束 #1/#5。
- **五文件结构**：`layout.mbt`（常量面板）/ `types.mbt`（数据壳 + `MemFault`）/
  `freed_logs.mbt`（有序数组 + 二分 + 精确裁剪）/ `memory_map.mbt`（`MemoryMap`：
  regions / free_list / quarantine / 堆游标 / 判定入口）/ `carrier.mbt`（`Memory`：
  字节载体 + 脏页 + 受检读写 + 批量）。
- **常量单源不双写**：地址布局常量沿 S5 的 `bytecode/memory.mbt` 定义点，本包一律
  `@bytecode.` 前缀引用（只消费 `MEM_SIZE` / `NULL_TRAP_SIZE` / `HEAP_START` /
  `align4` 四个）；本包自有页几何（`PAGE_SHIFT/SIZE/COUNT`、`DIRTY_WORD_COUNT`）
  与隔离预算（`DEFAULT_QUARANTINE_BUDGET`），并用**硬编码对账锚**锁
  `PAGE_SIZE × PAGE_COUNT == MEM_SIZE`、`DEFAULT_QUARANTINE_BUDGET × 4 == MEM_SIZE`。
- **面扩张（minor，0.6.0 候选）**：`bytecode` 的 `MEM_SIZE` / `NULL_TRAP_SIZE` /
  `HEAP_START` / `STACK_START` / `argv_region_footprint` / `compute_heap_base`
  由 `const`/`fn` 升为 `pub`（S5 已留"S6 前置"注释）。后三者的消费者是 vm 片
  （同批后续），已登记 `surface_allowlist.txt` 待 vm 接线后清理。
- **三处结构性收紧（相对 Rust 现状，均出自勘察建议）**：
  1. **取消平行索引**（坑 6 的根因）：`regions` 改为 **addr 键的插入序 `Map`**
     （core `Map` 即 LinkedHashMap，既有键 `set` 保插入位）——"同 addr 两条目"与
     "索引与 regions 失配"在类型层面不可表达，`rebuild_region_index()` 的恢复
     义务整个消失。地址也不在 `MemoryRegionData` 里（键即地址），失配面归零。
  2. **释放路径单一出口**（堆有界隔离决议 §3）：`MemoryMap::release` 原子完成
     "置 `is_freed` + 登记 freed_logs + 进 FIFO 隔离区"三步。Rust 现版同一语义
     在 `host_free` / `realloc(p,0)` / `free_memory` 三处各写一遍。
  3. **受检访问单入口**（§9.2 约束 #1）：`Memory.bytes` 是 **priv 字段**，
     包外拿不到裸字节；判定只经 `MemoryMap::check_access`（NULL 区 → 上界 → UAF），
     写路径再补脏页记账。"host 层绕过检测"从纪律要求变成结构不可能。
     顺带关闭 Rust 的存量漏网：`read_memory_to` 只查 NULL/上界不查 UAF。
- **已知代价（诚实登记）**：freed_logs 用有序数组，`remove`/`insert` 是 O(n) 尾部
  搬移。稳态条目数有界（隔离预算 ÷ 最小块 ≈ 16,387），命中路径平均只动 0–2 条；
  **旧块复用**（first-fit 命中低地址驱逐块）时被删下标近 0、搬移接近全长——这是
  本容器相对 `BTreeMap` 的唯一劣化点。实测 10 万次 churn 用例全程 **1.6s**（含
  编译与其余 26 个用例），暂不构成问题；若门 1 基准显示其成为热点，换
  `@sorted_map`（AVL）即可，**区间算法与全部红锚不变**。
- **锚点（27 测试：白盒 21 + 黑盒 6）**：照搬 Rust 红锚——坑 10 部分重叠精确裁剪
  （`test_u213_freed_logs_partial_overlap_trimmed`）、坑 6 复用不双条目
  （`test_u22_realloc_reuse_no_duplicate_entries`）、坑 7 隔离区三语义（窗口内必
  检出 / 窗口外复用 / 预算 0 立即复用 + 稳态窗口存活）、churn 超预算不撞墙、1MB
  墙返回 NULL、复用复位 + 清窗口、统计口径；另加 freed_logs 四类裁剪分支、二分
  边界（相邻不重叠不得误判）、饱和算术、脏页移位、批量 memmove 语义等。
  黑盒文件同时承担**对外面消费面**（喂 `moonbit_surface -check`：本包全部 pub
  符号均有消费，无"无主 pub"）。
- **J9 证红留痕（两路注入，注入后字节级还原）**：
  ① `remove_overlapping` 退化为"重叠即整条删除"（坑 10 修复前行为）→ **4 个用例
  变红**，含坑 10 锚本体与黑盒 `freed_logs_surface`；
  ② `find_overlapping` 二分下界差一（少减 1）→ **13/27 用例变红**。
  另有 `verify_catches_quarantine_bytes_drift` 作为不变量自检的常驻证红。
- **门禁全绿**：`moon check --target all` 0 错（本包零非 derive 告警）、
  `moon test` **237/237**、`pkg_deps`（20 包）/ `moonbit_surface`（可收清单 + 消费
  边）/ `mbti_sync`（16 接口面）/ `single_source` / `libc_single_source` /
  `gen_diag` / `gen_host_route` / `perf_budget` 八闸 PASS。
- **登记未落地项**（不静默）：快照批量装载（`load_*`，形状由 vm 的
  `VMSnapshot`/`MemoryImage` 决定）、`MemoryFragmentData`（L8 导出 DTO）、
  cstring 通道（`write_cstring`/`read_cbytes`：`\xHH ≥ 0x80 → Latin-1` 的口径
  单源当前长在 L6 `codegen/init.mbt` 且为 priv，跨层复用需先上提为独立单源）。

### 发布（mooncakes）：vitro/engine 0.5.0（2026-09-23）

- **版本语义裁定：0.4.0 → 0.5.0（非 patch）**——0.4.0（`2bf3b29`）以来 moonbit/
  接口面有三处实变：codegen 新增 `pub fn compile_library`（library mode 出口）、
  libc 新增 `LibcSig`（签名结构体）、ast 收面移除 `template_arg_eq`（唯一消费者
  同包）。按手册「新增公共 API → minor」取宽；0.x minor 可带 breaking，明示。
- **README 英文化**：顶部新增 English 节（定位一段 + 11 包全量英文表 + 稳定性
  承诺 + 示例）——mooncakes 模块页国际可读；中文包清单表同步补全 4 → 11 包；
  测试数对齐实测 210（ast 13 → 14，B#12 哨兵测试入列）。`description` 升级为
  完整英文句，`keywords` 增 `moonbit`。
- **验收三件**：`moon search` 可查（新 description 上墙）/ 临时项目
  `moon add vitro/engine@0.5.0` 编译运行全对（诊断码 / 教学卡片 / to_c_string /
  depth）/ 包 zip 根级四件齐全。发布前置全绿：moon check 0 错、210/210、九闸 +
  toolchain_probe 全 PASS。
- **外部用户证实**：下载数 25 > 自产上限 ~18（两人三倍验证）——此后对外面变更
  须带兼容负担意识（版本化弃期 / CHANGELOG 记载）。
- **parser「随下一 minor」承诺兑现**：随本 minor 进架，AGENTS.md 包清单状态已
  对齐。

### Fixed (防线)：gen_protocol_ts `-check` 的 CRLF 假红（toolchain_probe 同款第三例，2026-09-23）

- **归因**：`protocol/index.d.ts` / `fields.mjs` 以 LF 入库，本机
  `core.autocrlf` checkout 翻成 CRLF，`-check` 逐字节比较即判红——内容零漂移
  （`git status` 标 M 而 `git diff` 为空即指纹）。P2-1（gen_diag）与
  toolchain_probe（2026-09-22）之后本仓第三例行尾假红。
- **修复双保险**：① 比较前 CRLF→LF 归一化（`-check` 与 `--selftest` 基线两处）；
  ② `.gitattributes` 锁 `protocol/** text eol=lf`（同 `moonbit/**` 先例）。
- **红→绿闭环**：产物翻转 CRLF 复现红 → 修复后同一份文件 PASS；
  `--selftest` 三路注入证红完好（判据自身修复不损判定力）。

## [Unreleased]

### Added (协议 TS 类型生成链 + 首个消费者：A 组 #9/#10，2026-09-22)

- **`scripts/gen_protocol_ts`**：从**权威 Rust 源**生成 `@vitro/protocol` 的 TS
  类型（`protocol/index.d.ts`）与字段元数据（`protocol/fields.mjs`），并与 schema
  文档**双向对账**（架构审阅 v2 §7.5 / §8.4）。
  **权威源的选择是个设计决定**：读 `native/src/unified/{types,root_cause}.rs` +
  `native/src/session.rs` 的 Rust 结构体，而**不是** schema 文档——前者是**编译期
  受字段冻结测试守护**（`native/tests/step_payload_schema_v0_1_test.rs`）的真实源，
  后者是人工维护的表述层。故取「从实现生成 + 与文档双向对账」，任一方向不同步都红：
  这顺带把「**文档与实现是否一致**」这个此前无人守的问题变成了机器判据。
  覆盖 schema §1（`StepPayload`）+ §2（8 个子结构）+ §3.1（`PointerStatus`），
  实测 **10 类型 / 49 字段**，Rust ↔ 文档字段集双向一致（零差异）。
  - **踩坑（生成器自身的 bug，由闸门自己抓出）**：字段正则原要求逗号后直抵行尾，
    于是 `pub access_type: String, // "Read" | "Write"` 这类**带行尾注释**的字段
    被整行漏掉——闸门随即把它误报为「文档多列了字段」。教训与 J9 同源：
    **判据的假红/假绿都可能来自判据自身**；行尾注释这一条已写进正则注释。
  - 判据：① `-check` 幂等（磁盘产物 == 现场生成）② 字段集**双向**对账
    ③ 空集不得绿（0 字段 / 0 类型一律 fail loud）。`--selftest` 三路内存注入
    证红（Rust 新字段 / 文档缺字段 / 文档多字段）。
- **`protocol/`——`@vitro/protocol` 包（第一个消费者落地）**：
  `index.d.ts` + `fields.mjs` 为生成物（禁手改），`package.json` / `README.md` /
  `consumer.mjs` 手写。**`consumer.mjs` 就是报告 §8.5 说的「第一个消费者」**：
  它用**生成的**协议面去消费**真实的**引擎输出（`vitro_cli serve` 的 step 流），
  做逐字段校验（未知字段 / 缺字段 / 枚举越界 / 嵌套结构递归）与最小内容层渲染。
  实测 **399 步真实 payload 字段级校验零错**，渲染输出含变量表、数组快照、指针状态
  与教学语义标签；`--selftest` 四路（三类非法 payload + 真实 payload 正向）全活。
  - **踩坑（协议行为）**：`payload.get(start,end)` **不推进执行**——它只返回已收集
    窗口内的快照（只 `step.begin` 后调用得到 0 个 payload）。消费者必须靠
    `step.next` 逐步行进；请求一次性写入 NDJSON，故预设上限步数。这条已写进
    `consumer.mjs` 头注（文档 §4.1 的「懒重算」措辞容易读成「会自动跑」）。
- **边界诚实登记（两条，都写进 `protocol/README.md`）**：
  ① **§5 差分层（`StepStreamBatch` / `StepPayloadDelta`）未纳入生成范围**——该节
     表格是**压缩式**（多字段合并一行，如 `step_index / code_line / func_name_idx /
     semantic_label_idx`），无法逐字段机判；且它们是编码细节，非内容消费者的必需面。
     待 v0.2 轨道决定。
  ② **编译期收益未验证**——本环境有 node（v22.22.2）但**无 npm / npx / tsc**，
     故只能验「生成物描述得了真实输出」；**验不了**「字段名写错在 tsc 编译期即红」，
     而后者才是 TS 类型的核心收益。消费者取**降级形态**（运行时字段校验），
     待 tsc 环境就绪后补编译期验证。
- **发布动作不在本批**：`npm publish` 属仓库持有者（贡献者无 npm 账号）。本批只把
  包内容与门禁准备到可直接发布的状态。

### Fixed (C ABI 声明：错误码缺口补全 + 权威源勘误 + 对账闸，2026-09-22)

- **`vitro_capi.h` 错误码补全 25 项（73 → 98）**：C 头 `VitroErrorCode` 与
  Rust 权威源的实测差异是「**值全对、码缺一批**」——同名同值 **73/73 全对**
  （抄得准，无伪造码），但缺 64 项，其中 **25 项是 C 侧/预处理器码**：
  预处理器 12 项（`E1011_UnmatchedConditional` … `E1022_TemplateInstantiationLimit`
  + `W1018/W1019`）、C 侧语义 13 项（`E3060_UseAfterFree`、`E3061_DoubleFree`、
  `E3062_PrintfFormatMismatch`、`W3064_DoublePointerCast`、`E3065_ConstViolation`、
  `E3070_BufferOverflow`、`E3071_UndefinedLabel`、`E3072_StructSelfContain` …）。
  这些是 **C 程序最常遇到的运行时错误**，缺了它们下游 C 消费方拿不到符号名
  （只能按裸数值判型）。已按权威源的值补入，**不改任何既有项的值与顺序**
  （纯增量）；剩余 39 项缺口属**正当豁免**：`Unknown = 0` 哨兵 + 38 项
  `E4xxx` C++ 专属码（C++ 已裁定砍除，总计划 §9）。
- **权威源勘误（指错了源）**：C 头原注释写 "Keep in sync with
  `native/src/diagnostics/error_codes.rs`"——该文件实际是
  `pub use vitro_shared::error_codes::*;` 的**一行 re-export**，真实枚举在
  `native/crates/vitro_shared/src/error_codes.rs`（137 项）。已改指真实源，
  并把**裁剪策略**（哪些码有意不暴露、为什么）写进注释——此前它**根本没被
  登记**，这才是"25 项缺失既发现不了也判断不了"的根因。
- **新闸 `scripts/gen_capi_bindings`（CI 接线，check-only 模式）**：三类判据
  ——① **伪造码**（C 头有而源无即红）② **值不一致**（同名必须同值；这是最
  危险的一类，下游按数值判错型）③ **未登记缺口**（源有而 C 头无的项必须匹配
  `excluded_patterns` 的豁免规则，未登记即红——逼「裁剪」成为显式决定）；
  外加一条 **Go 绑定的 DLL 符号名必须都有 C 头声明**（运行时 `Find` 失败是
  只在跑起来才暴露的隐患，实测 15/15 已对齐）。规则外置 `rules.json`；解析出
  0 项 fail loud；`--selftest` **四路内存注入**证红（值不一致 / 伪造码 /
  未登记缺口 / 绑定符号缺声明，各判红 1 处），不动磁盘故无需恢复。
  命名与报告 A 组 #3 一致，**生成模式待裁剪策略定型后接入**（届时按
  `gen_diag` / `gen_host_route` 的三件套：落款源 sha256 + 内置格式化 + `-check` 幂等）。
- **影响面说明**：改的是 `native/include/vitro_capi.h`——**纯声明文件**，
  不参与 Rust 编译（实测确认 `native/build.rs` 只注入 git hash、不读 C 头；
  `capi_string_ownership_contract_test.rs` 仅注释引用），且改动为增量枚举常量，
  不改既有 ABI。

### Added (S6 前置收尾 2：接口面同步闸 + O2 债裁决 + 性能预算闸，2026-09-22)

- **接口面同步闸 `scripts/moonbit/mbti_sync`（CI 接线）**：`.mbt`（实现）与
  `pkg.generated.mbti`（接口面）的一致性此前**纯靠人工跑 `moon info`**——
  本仓已漏过一次（`libc/pkg.generated.mbti` 缺 `type LibcSig`，直到下一轮
  有人顺手跑 `moon info` 才补登）。`moon info` **无 `--check` 子命令**（实测
  moon 0.1.20260920），故取**跑前后快照 sha256 不变量**形态：快照 → 跑
  `moon info` → 再快照 → 比对，不等即红并列出全部变化文件（新增 / 消失 /
  内容脱节三类）；**0 个 `.mbti` 亦红**（拒绝空转判绿）。J9 两路证红：
  `--selftest` 注入脱节内容必红（判红 1 个文件）+ **真实场景**已验证（往
  `moonbit/opcode/opcode.mbt` 注入一个 pub fn 而不跑 moon info → 闸门指出
  `opcode/pkg.generated.mbti` 脱节，exit 1）。**自愈特性**：闸判红时会顺手把
  `.mbti` 同步到当前实现，故本地红完直接提交即可、再跑即绿（已在头注说明，
  避免误读为漏判）。与 `moonbit_surface` 的分工：本闸判「接口面是否跟上实现」，
  surface 判「接口面是否该收窄」，互补不可互替。
- **typeck O2 债裁决：已量测，保留每次重建，不做缓存化**（登记而非改码）：
  `TypeChecker::compute_type_size` 每次调用重建 struct/union 定义表。实测
  613 个 `.c` 语料中 **struct/union 定义最多 2 个**（多文件并列：
  `baseline/e1_c23_alignof.c`、`linked_queue.c`、`knr/kr_6_3.c`）、**单文件
  成员访问最多 37 次**（`leetcode/lc_2.c`，即调用频率上界——`expr.mbt:64`
  每条成员访问一次）⇒ 每次重建至多 ~10 次 map 插入、全文件 ~4×10² 次操作，
  **不可测**。四条裁决依据：① 上述规模上界；② Rust 侧
  `vitro_typeck/src/context.rs:8` **同构**（同样每次重建 + `class_size_map`），
  保持「照搬」以免制造两侧行为分叉；③ **两侧不对称是有意的、非遗漏**——
  typeck 阶段 `self.structs` 在增长（Pass 1 登记，`typeck.mbt:114/125`），
  缓存须带失效逻辑；codegen 侧能用 `self.struct_defs` 恰因那时表已固定
  （typeck 之后才跑）；④ MoonBit `self` 为**值语义**，加缓存字段会让每次
  调用复制更大的 struct 头（27+ 字段），**净收益方向不确定**（可能为负）。
  裁决理由与复评触发已写入该函数头注。
- **性能假设预算闸 `scripts/perf_budget`（CI 接线）**：把「某项优化为什么
  不做」所依赖的**规模前提**变成机判红线——裁决可以写在注释里，但裁决的
  **前提必须有人守**（否则随语料扩展静默过期）。首条 counter = O2 债的
  struct 规模预算（`struct_or_union_defs ≤ 8`、`member_accesses ≤ 200`，
  现状 2 / 37，留 4–5× 余量）；超阈即红并输出 `on_exceed` 指回裁决所在，
  迫使重估。规则外置 `rules.json`；0 语料文件 fail loud；J9 证红：全部
  counter 预算压 0 → 2/2 判红。与 `facts` 分工：facts 管「文档数字 ↔ 机器
  真值」对账，本闸管「性能裁决的规模前提是否仍成立」（阈值断言）。
- **手册补登**：`moonbit/AGENTS.md` 的命令清单此前漏登记
  `scripts/moonbit/single_source -check`（上轮只登记了同批的
  `pkg_deps` / `libc_boot_diff`），本批一并补上。

### Added (S5 收尾批：libc 三表单源对账闸——S6 前置，2026-09-22)

- **`scripts/moonbit/libc_single_source` 新门禁（CI 接线）**：Rust 侧
  「这个名字是不是 builtin」的判据是 `host_func_id::by_user_name` 路由名
  ∪ `BYTECODE_LIBC_ALL_FUNCS` 索引名的并集；MoonBit 侧照搬时把并集手抄成
  libc 包 `builtin_all`，三份表之间零对账——第四套真相源。本闸把「三表
  一致」从注释承诺变成机判红线：等式（`builtin_all == host ∪ bytecode −
  excluded`）+ 交集计数 + PURE 子集 + **空集不得绿**（防「解析失败→
  空集→全绿」的假绿）；规则外置 `rules.json`，J9 三路证红留痕（主判据
  抽名注入 / 交集期望值注入 / 锚点缺失走 fail loud 非静默绿）。
- **勘误（被实测证伪的包注释）**：`moonbit/libc/libc.mbt` 原称「`print_int`
  不在此集（Rust host_func_id 无此名）」——实测 Rust `by_user_name` **明确
  有** `"print_int" | "__vitro_output" => Some(OUTPUT)` 别名臂；host 侧正确
  口径是「109 臂 / **110 名**」（生成物把别名臂展开）。行为未变（集合内容
  经闸门验证与 Rust 并集完全一致），仅修正事实陈述——这正是「无对账的
  手抄副本会让注释先腐烂」的实证。
- **落地偏差登记**：计划原意「以 libc 表为单源**回填**下游两表」在分层
  约束下**不可实现为派生**（libc 在 L5、codegen/bytecode 在 L6，反向
  import 非法）——只能实现为**对账**；真正的派生待 S6 建 host 包时把路由表
  上提为 L7 独立包。现状诚实表述：第四套真相源**已约束，未消除**。
- **槽位策略分档机制闭环（架构审阅 v2 A 组 #2 的 Go 侧半）**：
  `codegen_diff` 新增 `slot_strategy` 对账——读 MoonBit 产物包装层字段并与
  外置 `scripts/codegen_diff/slot_strategy.json` 的期望值比对，不符或
  **无任一成功样本携带该字段**均判红。此前该字段被驱动整个丢弃：
  `cmd/dump_compile` 注释承诺「对拍面只取 .dump，本字段不参与 14 键比对，
  **v2 切换时 codegen_diff 可按此分档**」，实测**为零**——又一处「注释
  声明的机制未落地」。J9 证红留痕（`expected` 改 0 → exit 1 并给出同步
  指引；恢复即绿）；骨架面实测 `slot_strategy=1×12` 绿、SAME=12 +
  AGREE-ERROR=1 不变。同时把 `global_data_end` 交叉点与 v2 前提（v2 必红
  A 级 code 段逐位对拍，须等 Rust 退役）登记进该 JSON。
  **剩余半**：Rust `dump-compile` 产物仍无该字段（平铺 14 键），故当前是
  **单向对账**而非两侧等值；补字段属冻结区产物形态变更（连带「14 键」
  → 15 键口径、MoonBit dump 内层同步、598 语料全量重跑），留独立小批。
- **包依赖方向断言（架构审阅 v2 A 组 #6）**：新闸门
  `scripts/moonbit/pkg_deps`（CI 接线）——总计划 §4 的硬约束「依赖严格单向
  无环」此前**零 CI 校验**，越层/成环的依赖可静默进来。按外置分层表
  （`rules.json`，源 = 总计划 §4 的 L0–L9 包图）断言每个模块内依赖指向低层
  或同层 + DFS 查环；**新包未登记分层即红**、解析出 0 包 / 0 依赖亦红（空集
  不得绿）；`cmd/*` 为工具层豁免方向检查（仍参与环检测）。实测 19 包全绿
  ——现依赖本来就合法，本闸的价值在于它此后不再只是口头纪律。J9 证红：
  注入 `opcode(L0)→bytecode(L6)` **同时触发越层与成环两条判据**。
- **手册分层标注勘误**：`moonbit/AGENTS.md` 包清单把 `lexer` 标 L2、
  `parser` 标 L3，与总计划 §4 的 L4 相差 1–2 档——已按总计划修正为 L4
  （新闸门的分层表以总计划 §4 为准）。
- **libc 自举（S5 尾项）——等价性锚建立，实测成立**：新驱动
  `scripts/moonbit/libc_boot_diff`（CI 接线）。命题是「MoonBit 引擎能否编译
  自己的标准库 C 源，且产物与 Rust oracle 逐字节一致」——`native/runtime_libc/src`
  三源（ctype 282 / stdlib 147 / string 423 条指令）在 **9 个交集字段**上
  逐字节一致（含 code 段逐指令）。
  实现要点与踩坑：
  ① **Rust `export` 不是 library mode，是 workaround**：注入 stub unit
     `int main() { return 0; }` 后编译，再「code[0] Jump→Nop + code 截断到
     wrapper_ip + func_table/func_index 删 main」；`--builtin-libc` 另删
     func_index 里「在 BYTECODE_LIBC_ALL_FUNCS 但不在 func_table」的预注册项。
  ② 两侧 `with_mode(is_library_mode)` 都**只改两个初值**（`next_func_idx`
     起点 0、`next_global_offset` 起点 0），且 **main 检查两侧都不豁免**——
     故 MoonBit 侧无需改 codegen 语义，只差把开关接出来。
  ③ 新增 `codegen.compile_library` + `cmd/dump_compile --library`
     （`.mbti` 已同步；新消费边已登记 `surface_edges.txt`）。
  ④ **唯一注入口径坑**：stub 必须直接接在主源末尾换行之后（不前插空行），
     否则 stub 区 `loc.line` 差 1。本轮首跑即因此判 DIFF——定位到「仅 stub 区
     行号差 1、前面几百条逐字节全等」才排除引擎嫌疑。
  J9 证红：注入 `code[1].operand +1` → 必红；恢复即绿。

### Fixed (收面闸判定盲区修复 + 已发布包面收缩，2026-09-22)

- **`moonbit_surface` 的类型闭包判定盲区修复（本轮核心产出）**：原实现只把
  "字段类型"当闭包、且靠人工白名单登记（`parser ParseError` /
  `bytecode LocalBuffer`），**漏了"pub 函数/常量签名引用"与"enum 变体载荷
  引用"两类**。实测后果：`diag CatalogEntry` / `Severity` / `SourceLang` 与
  `source Pos` 被误报成"可收"——**照清单去收会直接编译错**（pub 函数不能返回
  私有类型）。修复为统一判定：pub 类型若在本包 mbti 内除定义行外还有出现
  （被签名/字段/变体引用）→ 自动归入「签名闭包·非收面」。
  报告面随之精确：**收面清单 10 → 1**，闭包 8 个改由脚本自动识别。
- **已发布包的面收缩（1 符号）**：`ast template_arg_eq` → `priv`——唯一消费者
  是同包的 `template_arg_array_eq`，包外零消费。`ast` 自 0.1.0 起已发布，故这是
  **破坏性面收缩**；按 0.x 语义 minor 可带 breaking，在此**明示**。
- **白名单重构**：`scripts/moonbit/surface_allowlist.txt` 从 10 条 → **1 条**
  （`diag codes_without_catalog`：教学卡片覆盖率断言清单，属对外可核对的
  教学契约，有意保留）。8 个引用闭包全部移出（改由脚本自动识别）——白名单
  语义收敛为「技术上可收、但**有意保留**」的纯人工裁定项。
- `ast/pkg.generated.mbti` 随之同步（`moon info`，少 2 行）。

### Added (S6 前置收尾：B#12 空表哨兵 + A#7 单一真相源清单，2026-09-22)

- **B#12 空表哨兵（架构审阅 v2 §2.6）**：`moonbit/ast/types_predicates.mbt` 的
  `compute_type_size` 在 `Class` / `TemplateId` 分支由**静默返回 0** 改为
  **fail loud**（`abort`）。病灶：C-only 阶段 `class_size_map` 恒空（两处调用点
  `codegen/func.mbt` 传 `{}`、`typeck/context.mbt` 传 `Map([])`），Rust 侧同位置
  静默返 0——**C# 批引入类后若忘接表，会静默给出错尺寸，而 C-only 语料永远
  测不出**。本处为**有意分叉**（预留位 tripwire，总计划 §12），已在代码注释与
  本文件明示。红→绿留痕：新增 `test "panic class size with empty map"`（护栏
  可触发性义务），`moon test` 209 → **210 全绿**；不误触发验证：
  `codegen_diff` 骨架 13（SAME 12 + AGREE 1）与 baseline 365（SAME 355 +
  AGREE 9 + FORK 1）双绿、`libc_boot_diff` 三源自举全 SAME。
- **A#7 单一真相源清单 + `scripts/moonbit/single_source` 校验器（判据 C-04）**：
  C-04 的裁决要点是 L1 判据「同一概念多真相来源」**只覆盖仓内同语言重复**
  （R3 审计已收口），**不覆盖跨语言孪生**——迁移期每个单源在 MoonBit 侧都有
  孪生，同步义务纯人工。本批把清单入版本控制并机判，**8 条**：`compute_type_size`
  为 `enforced`（定义点**文件集**必须 == `allowed_def_files`），其余 7 条
  `registered`（生成物/另有专用闸门，校验两侧路径存在 + 登记检测锚点）：
  opcode 编号表 / 错误码表 137 / catalog 77 / host 路由 110 / bytecode libc 索引
  88 / libc 放行集 / slot 策略版本。
  清单含报告〔补遗 b〕点名的 **`parser/decl.mbt:889` 第三消费点**。
- **闸门撞出的命名债（报告未点出）**：`native/crates/vitro_typeck/src/context.rs`
  有一个与单源**同名**的方法 `pub fn compute_type_size(&self, ty) -> i32`——语义上
  确是委托（方法体收集三张表后调 `vitro_ast::compute_type_size`，报告 §2.3 判定
  正确），但**同名**会让读者/工具误以为存在两份实现。故闸门引入
  `exclude_line_pattern`（排掉含 `self` 的方法定义行），并把该命名碰撞登记在
  `rules.json` 的 `_exclude_note`，待 S6/S9 重排时可改名（如 `TypeChecker::type_size`）。
- J9 证红：注入"第二份实现"文件 → 必红；基线绿时注入 → 捕获（已留痕）。

### Docs (发布状态勘误与排期权威澄清，2026-09-22)

- **`vitro/engine` 发布状态勘误**：`MoonBit迁移总计划.md` 的 S5 行记「moon.mod
  0.4.0 待发」已过时——本机 registry 实测 0.4.0 **已于 2026-09-21 15:49 发布**
  （0.1.0 → 0.1.1 → 0.2.0 → 0.3.0 → 0.4.0；mooncakes 模块页显示 **16 个包在架**）。
  一并澄清一条**容易被误读的策略前提**：MoonBit 的 `moon publish` 是 **module 级**
  发布，故「未发布包零成本收面」的窗口**已在 0.4.0 用尽**——S5 收尾批的收面
  （27 符号）与 `moonbit_surface` / `surface_edges.txt` 双闸正是**赶在该发布之前**
  落地的，不是"窗口还开着"。
- **闸门角色重述**：`scripts/moonbit/moonbit_surface/moonbit_surface.go` 与
  `scripts/moonbit/surface_allowlist.txt` 头部原写「已发布 5 包（source/opcode/
  diag/ast/lexer，0.1~0.3.0 在架）不在收面范围」——该判定写于 0.3.0 时代，
  0.4.0 起全部对外包已进架。注释已改写为「类别① = **历史留白**」，并把本闸的
  角色从"收面工具"明确为「**防扩散闸**」（新 pub + 新消费边一律拦下要人工裁定）。
- **排期权威双头澄清**：`docs/README.md` 原把《统一整备路线图》（U0~U7）标为
  「排期权威」，但 2026-09-18 起实际排期载体已是 MoonBit 迁移总计划的 S 系列
  ——已在索引行标注让位关系，U 表降为历史口径与未闭环项索引。
- **语料真值口径定案**（此前 597 / 598 / 600 三口径并存，且**均未标 as_of**）：
  四语料真值 = **600**（实测 baseline 365 + gap 16 + knr 81 + leetcode 138），
  `codegen_skeleton` 另计 13。已在《脚本总清单与必跑防线》新增 **§1.3** 规定：
  引用语料数前**先数目录**；597（S3 收官）/ 598（S4–S5 收官）是各片收官的
  **as-of 快照**（历史记录不改）；该量随扩展增长，故**不做机器对账**（facts 的
  「解析差分样本数」键长期"待采集"即因此项非稳定量）。`moonbit/AGENTS.md`
  状态栏与 `ci.yml` 的**当前口径**已改 600。
- **CI 隐式前提写明**：`codegen_diff` / `libc_boot_diff` 等步骤**隐式依赖上方
  Release 构建的 `vitro_cli`**（Rust 侧产物真值源）——此前只有 `typeck_diff`
  步骤写了这句。已在 codegen_diff 步骤补注（缺 release 产物会 fail loud，
  不静默降级）。

### Removed (S5 收尾批：孤儿文件清理，2026-09-22)

- **删除 `native/src/compiler/ast.rs`**（架构审阅 v1/v2 §2.2 登记项）：
  `compiler/mod.rs` 只有 `pub use vitro_ast as ast;`、**无 `mod ast;`**，
  该文件不在模块树中。**死文件证法（J9 形态，两路独立）**：① 向其注入
  必然语法错误 `@@@ THIS IS NOT VALID RUST @@@` 后 `cargo check` 仍
  rc=0；② `cargo check --emit=dep-info` 产出的全部 `vitro_native-*.d`
  依赖列表均无该文件。删除后 `cargo check --workspace` 绿。
- **附带登记（环境现象，非本次改动引入）**：本轮首次 check 遭遇
  `os error 5`（拒绝访问）写 incremental 目录，致增量缓存损坏、之后
  check 稳定 panic（`rustc_metadata/rmeta/encoder.rs:2447 no entry found
  for key`）——曾误判为删除所致；`cargo clean -p vitro_native` 后恢复。
  与 `codegen_diff` 头注记载的 Windows 句柄/杀软瞬时锁同类，排查「构建
  失败」时须先排除它。

### Fixed (CI 红处置：28 个 golden 从未入库 + cargo 用例数平台差异，2026-09-19)

- **28 个 baseline golden 补入库（P5"缺 golden 必红"的 CI 首秀战果）**：CI
  E2E 报 28 例缺 golden——根因是这批 .out 被列在 `.git/info/exclude`
  （**本地私有排除，不入库、CI 不感知**；历史遗留），本地文件系统存在
  掩盖了缺口（P5 前静默跳过从未暴露）。清除 exclude 28 行并入库（本地
  E2E 一直消费且全绿，内容为有效 clang golden，抽查 e1_string_concat /
  jit_single_hot_loop 合理）
- **cargo test 用例数归平台相关实测行**：CI 首次以 `--cargo-log` 新鲜
  采集真值（1014）对账，暴露 README:52 陈旧值 845；实测本地 Windows
  1028 / CI Linux 1014（套件含平台条件编译差异）——单一真值对账对平台
  相关数字不成立，该行按实测行语义归人工维护（标注两环境实测值）
- 附注：CI 日志中 replay/serve 断言数"61/57 共行互斥"漂移形态属
  **旧代码判定**（该 CI 轮扫描 48 份文档，对应 P1 之前的 facts）——
  就近绑定已在 e1e664a 修复，当前 HEAD 本地 facts 漂移 0

### Fixed (S0.5 审阅处置批，2026-09-19)

- **P3 白名单护栏自指缺陷修复（审阅【中】项，埋雷复现实证）**：原"计数锚"
  断言测试内手工清单自身长度，与枚举零联动——审阅者埋雷 `W4999_TestProbe`
  三测全绿，"漏登记先红"声明不成立。修复：`WARN_CODES`/`HINT_CODES` 提为
  模块级单点常量 + 新护栏 `test_whitelist_matches_source_variants` 从源文件
  `include_str!` 提取全部 W/H 变体码与白名单**双向对账**（漏登记/腐化登记
  均红，零依赖手扫不用 regex）。J9 埋雷复验：加 `W4999` → 红（消息含
  "漏登记的新 W 码会静默显示 E 前缀"）→ 排雷 → 绿
- **U1 probe 入参 fail-loud（审阅【低】）**：`completion` 块存在但
  line/column 缺失或非法时报错——此前静默空段，S8 对拍会掩盖调用侧错误；
  `records` 保持宽松（ts 缺省 0 是合法语义）
- **canonicalize 尾随内容消息区分（审阅【低】）**：多 JSON 值 vs 尾随
  非 JSON 垃圾分别报错（判定本就无损，仅消息精确化）
- **P4 八进制错误恢复值统一（审阅【低】）**：string 侧超范围截断
  `val&0xFF` → 与 char 侧统一为 0（错误已报、编译失败结局，值无语义）
- **登记未修项**：① 无 main 翻译单元零诊断失败（既有缺陷，
  native/AGENTS.md 已知限制——修复需新增错误码，随 S1 批次处理）；
  ② P3 双源分叉缝隙（severity↔码段位一致性对账——某诊断点把 W 码填
  severity=0 时帧内自洽但与 catalog 矛盾，无护栏；S1 T2 生成器落地时
  从根上对账）
- **勘误（P1 提交信息两处表述，历史不改写）**：① j1 不入 1200 层用例
  的理由应為"clang 对 1200 层可编译 → shadow 判 compile_gap 假红"
  （原文写"vitro_better 假信号"，方向对机制错——vitro_better 是 clang
  败/Vitro 成）；② "J9 证红锚 near_bind_test.go ×6"实为 5 个测试函数
  （其一含红+绿两段断言）

### Chore (M-0 基线冻结，tag `s0.5-baseline-freeze`，2026-09-19)

S0.5 收官：release 重建（HEAD `c5ffc9c`）+ 全防线复跑留痕——shadow C
679（match 675 / known_issue 3 / gap_extension 1；clang 22.1.4 版本串在
shadow_data.json）/ replay 61/61 / serve_smoke 57/57 / facts 漂移 0 /
cargo test 75 套件 / clippy 0。cases_golden 快照在版本控制（S0.5 批含
8 例新 golden：j1 + P2×2 + P4×1 + P5×5 含 cpp×4）；facts.json 取固定
tag（不入库防双真相）。**S0.5 白名单 P1–P7 + U1/U2 全部完成，S1 基础片
（vitro/{source,diag,opcode,ast} 四包）开工。**

### Added (P7 AST/符号表 dump 出口 + Go canonicalizer，2026-09-19)

- **serve `ast.dump` / `symbols.dump`**：E1 B 级锚的 Rust 侧出口——此前
  全仓 `dump_ast` 零命中、AST 27 处 serde 派生无出口（typeck/parser 双
  报告确认）。session 不保留 AST（与 U1 intents 同因），dump 内重解析；
  语法错误帧可归一（fail loud 语义稳定）。**emitter 纪律**落注释：Rust
  侧 serde 派生为唯一 emitter，MoonBit 侧实现显式 emitter 同构输出、禁
  ToJson 直拼（总计划 §B 结构化锚）
- **Go canonicalizer** `scripts/canonicalize`：对象键字典序 / 数字保形
  （json.Number 直通，1.0≠1）/ 字符串转义统一（HTML 转义关闭）/ 缩进
  2 空格 / fail loud（非法 JSON 与多值拼接拒绝输出）/ `--check` 锚定
  模式。J9 ×8（键排序 / 数字保形 / 转义 / 幂等 / 非法拒绝 / 多值拒绝 /
  数组保序 / 自反）
- **管道锚** `ast_dump_test`：dump 输出经 canonicalize 归一幂等——
  E1 锚"两侧同经归一后逐字节比对"的可信前提

### Docs (P6 列号口径冻结，2026-09-19)

- **口径档案** `docs/current/07-质量与裁定/列号口径冻结.md`：现状缺陷**不修**
  （S1 `vitro/source` 双坐标根治），冻结为契约输入与防漂移锚——① 词法路径
  （E1001）：报错列 = 1-based Unicode 字符列 + 1（advance 后报错），四形状
  实测自洽；② 解析路径（E2005）：报错列 = current token 的 column 字段，
  ASCII token 全对、含非 ASCII 的 String token 偏 **−4**——根因亲证
  `make_token` 的 `column = self.column（字符计数）− text.len()（字节数）`
  量纲混算（vitro_lexer/src/lib.rs:448）；**两路径区分是关键发现**——纯
  ASCII 探针对此缺陷零感，差分锚必须含非 ASCII 形状
- **防漂移锚** `source_column_convention_test` ×10 形状（词法 4 + 解析 6，
  精确断言 line/column/code 三元组）：冻结不是口头约定而是测试防线；
  MoonBit 侧 E3 锚对拍时 −4/+1 两类形状列入已登记差异不判缺陷
- **契约输入**（档案 §2）：`vitro/source` 主坐标 = byte_off+1；双坐标
  `Pos{byte_off, col_scalar, col_utf16}` 预留；禁"扫描后计数−长度"回推
  （make_token 根因模式）；词法 +1 不复刻

### Added (U1 认知链最小导出，2026-09-19)

- **serve 新方法 `diagnostics_probe`**：knowledge_graph / misconception /
  learning_path / completion / intent / auto_fix 六个分析器此前外部生产调用
  全为 0（serve/capi/CLI 零出口，第一阶段计划 U1 亲证）——"趁 Rust 版仍在
  做差分扫描"的退路对它们不存在。入参 `{source, records[], completion{}}`，
  返回六段结构化 JSON（诊断码串按 P3 severity 前缀单源；misconception/
  learning_path 由外置编译历史驱动；knowledge_graph 按错误码激活子图 +
  全图规模；intent 重解析采用错误恢复语义——补全场景源码常不完整；
  auto_fix 对 fix_kind 1..=3 逐条应用）。**data_flow 未覆盖**（需 CFG
  管线接线，诚实记录，S8 差分前补）
- **外置用例锚** `tests/cognitive_probe_cases.json` ×4 组（M02 指针生命
  周期 / E3023→VarDecl 概念激活 / printf 补全+意图推断 / 缺分号自动修复）
  + `cognitive_probe_test` 内容级断言（语料与断言外置 JSON 人审，字段面
  即 S8 差分锚单源——MoonBit 侧对拍复用同一 JSON）

### Docs (wasm 多实例并发模型裁定 + U2 拍板，2026-09-19)

- **新文档** `docs/current/06-出口与协议/wasm多实例并发模型与U2拍板.md`：宿主
  并发模型定为 N 线程 × N 独立实例（隔离是 wasm 实例模型的构造性质，不依赖
  引擎线程安全改造）；三宿主形态（浏览器 Worker / Node worker_threads /
  .NET Wasmtime 多 Store——铁律在 Wasmtime 是类型系统强制）；核心精化：
  **隔离来自 core wasm 实例模型而非 wasm-gc 特有——当前 wasm32 出口已具备
  全部性质，下游对接不必等终局**。实证交叉：capi"DLL 并发堆损坏"是构造性
  反例（形态缺陷非 bug）；引擎状态逐项核对全在实例内（VFS/rand/无 time），
  跨实例同输入同输出可复现；边界诚实记录（宿主 import 面的输出会话绑定 +
  N 实例并发尚无实测记录——拍板生效前补锚，已列待办）
- **U2 拍板**（第一阶段计划 §2 U2 状态更新）：第一批 19 声明冻结现状（维护
  至 Rust oracle 退役）；第二批 capi（memory/breakpoints 语言中立化导出）
  裁不做——下游并发改道 wasm 多实例、交互以 serve 协议为终态载体；通知
  义务待用户向 SharpTutor 正式发出（原降级线升级为改道，Wasmtime 集成
  成本换并发能力增强）

### Fixed (P5 golden 完整性与 fail-loud，2026-09-18)

- **缺 golden 必红**：`run_case_with_compiler` 此前无 golden 时静默跳过比对
  （用例退化为"只查能跑"的烟雾测试，golden 缺失无人发现）。改为缺失即
  Err（错误消息含生成指引）；J9 证红：临时移走一个 golden → 必红 → 恢复
  → 绿。四目录存量缺口清零：补 `e2_include_guarded`（漏 golden 的正常
  用例，clang 实跑 `7 3`）与 4 例 C++（`cpp_copy_ctor` / `cpp_default_args`
  / `cpp_nested_class_instance` / `cpp_nttp_class`——live-clang 逐一确认
  编译运行成功后实跑生成，Vitro 侧全对齐）
- **KNOWN_* 常量全部成对**：`KNOWN_BASELINE_COMPILE_FAILURES` 提升为模块
  级并新增 `test_vitro_e2e_baseline_compile_failures_known` 反向监控
  （表内用例转绿即 panic）——五个 KNOWN_* 常量至此全部具备
  "跳过 + 转绿即红"双向咬合
- **gap 七条审计（对齐 C 侧 J2 先例）**：`file_fopen` / `file_fread` /
  `file_fwrite` 三例**假 gap 转正**——均漏 `#include <stdio.h>`，clang 报
  undeclared `FILE` 被 gap_extension 判定掩盖，实为漏头文件伪装；补头后
  双侧 fopen 不存在文件同返 NULL，转 match。`keyword_compat`（真扩展）、
  `function_pointer_sizeof` / `sizeof_array_param`（指针 4 字节架构差异）、
  `bTree_default`（NULL 访问根因在案）四例分类确认正当。shadow 分布：
  gap_extension 4→1、match 672→675
- **手写 golden 显式登记**（CPP_FAILURES.md）：4 例 clang_compile_fail
  用例（`cpp_vitro_vec_class` / `cpp_vitro_list_class` / U3 ×2）的 E2E
  golden 为 Vitro 自证（无独立 oracle 仅回归锚）——选登记而非改写
  `std::vector` 等价物（改写会偏离 `vitro_*` 容器代码路径覆盖，真对照
  版本后续需要时另立新用例）

### Fixed (P4 字符串转义与字节通道收口，2026-09-18)

- **string 侧 hex/八进制转义收口（与 char 侧 U1#7 同口径）**：
  - hex 1~2 位：修复前恰收 2 位，`"\x4"` 单位转义被拆成字面 "x4"
    （sizeof 3，clang 2）；第 3 位 hexdigit 报"超出范围"（clang error
    口径，文案与 char 侧一致）
  - 八进制 `\ooo`（1~3 位，值 ≤ 0xFF）：string/char 两侧此前均缺失
    （仅字面 `\0`），`"A\012B"` 变 NUL+"12"（sizeof 6，clang 4）、
    char `'\7'` 报"未知字符转义"；超范围对齐 clang error
- **C 字符串字节通道（\xHH ≥ 0x80 落单字节）**：`\xff` 转义产物
  （U+00FF）经 Rust String 再 `as_bytes()` 重编码为 2 字节 UTF-8
  （0xC3 0xBF，clang 单字节 0xFF）。新增 `vitro_shared::cstring`
  （`cstring_bytes`/`cstring_len`，唯一真相源）：码点 ≤ 0xFF 按 Latin-1
  单字节、> 0xFF 保持 UTF-8——无歧义依据：UTF-8 源的多字节字符码点
  必然 > 0xFF，U+0080..=U+00FF 只可能来自 \xHH 转义。接线 7 个消费点
  （gen_string_literal / 全局与 static 字节直写 / pending 回填 aligned /
  VM write_cstring / typeck sizeof 折叠与数组尺寸推断）。已知差异（诚实
  记录）：源内直接书写的高位单字节字符按 Latin-1 单字节（clang UTF-8
  execution charset 为 2 字节）
- **全局 `char g[] = "str"` 尺寸推断符号表回写（stash 红线复验顺带抓出）**：
  推断发生在 declare_var 之后，符号表停留在 dims=[-1] 快照，
  sizeof(g) 恒 1（clang 4；局部路径靠"推断后再声明"避开同坑）。新增
  `update_var_type` 推断后回写
- 红→绿锚：`baseline/string_escape_octal_hex.c`（clang golden 实跑
  `10 4 65 10 7 255 7 10 9 3 4 63`：1/2 位 hex、1/2/3 位八进制、
  \xff 字节值、char 侧八进制、全局+局部数组）+ `cstring` 单测 ×4；
  修复前同用例输出 sizeof 全错；边界形状 ×8（含 \x414/\777 双侧
  编译失败、\7A/\8 宽容）逐一对齐 clang

### Fixed (P3 诊断 E 前缀伪造批，2026-09-18)

- **W/H 级错误码被打 E 前缀（4 处伪造点）**：`[警告] … (E3053)`、
  serve 同帧 `code=E3053`+`severity=warning` 自相矛盾。修复为双单源：
  - `vitro_shared::error_codes::code_prefix`（新增）：码值 → 静态前缀的
    段位白名单（W×11/H×1，W/H 数值区间与 E 交织无法按段判定）；静态
    码表（error_catalog `code_str`）走此源——77 条卡片现为 W×7/H×1/E×69
  - `session_api::severity_prefix`（新增）：severity 数值 → 运行时前缀
    （0→E/1→W/2→H）；serve 帧 `code` 与 CLI compile/export 三处显示点
    走此源——前缀与 `severity` 字段同源派生，永不矛盾
- 红→绿锚：`code_prefix_test` ×3（W/H 前缀、E/未知默认、**白名单完备性
  计数锚**——新增 W/H 码漏登记白名单时先红）；现象红复验 `char c = 300`
  CLI 输出 `(E3053)` → 修复后 `(W3053)`；serve 帧实测
  `code=W3053`+`severity=warning` 自洽；`typeck_e3053_regression_test`
  同批核对 4/4 过（数值断言不受前缀影响）
- E3 诊断帧锚点（S1 侧 B 级锚）的硬前提就位：修复前两侧一致地错，无法
  建锚

### Fixed (P2 全局/静态字符串指针静默错值，2026-09-18)

- **`char *p = "hi"` 全局/静态初始化静默错值**：printf("%s", p) 输出 `[]`
  （clang `[hi]`），全局 / 文件级 static / 局部 static 三形态同病，676 用例
  零覆盖。根因在 codegen 静态求值路径三处（typeck check_assignable 本身正确，
  亲读后裁定不做计划中的"typeck 对称化"——插隐式 Cast 会使 codegen 初始化
  match 不再命中 StringLiteral 分支而落入静默丢弃，需连带 Cast 剥壳适配、
  扩大回归面且无行为收益）：① 全局直接字面量初始化按 `sz`（=4 指针）逐
  字节写字符串内容，指针槽变成 'h','i',0,0——加目标类型判据，char 数组保持
  字节直写、其余走 `pending_string_inits` 取址回填（字符串数据入全局区、槽
  写地址，与 flatten_global_init 既有机制同构）；② 全局指针数组
  `char *arr[2] = {"a","b"}` 的 InitList 元素被 `literal_init_bits`/
  `flatten_init_list` 取不到值写成 0（NULL）——含 StringLiteral 元素的数组
  转发递归展开；③ static 局部直接字面量同 ①，但 Pass 3 时序晚于
  pending_string_inits 回填点，须与 emit_static_scalar_array_init 元素级
  处理同型（立即 bump + string_data + 槽写地址）。函数内赋值 / 局部（非
  static）初始化路径本就正确（gen_string_literal 取址），回归保持。
  红→绿锚：`baseline/global_string_pointer.c` / `static_string_pointer.c`
  （stash 复验：修复前 `[][][]` / `[|]`，clang golden 实跑
  `[hi][alice][bob]` / `[>> | <<]`）；static 指针数组 / char 数组既有
  路径回归不变

### Fixed (P1 声明符类型通道栈溢出止血批，2026-09-18)

- **声明符链式数组后缀栈溢出（活的零诊断崩溃）**：`int a[1][1]...` 1300 层在
  `interpret_declarator_node` 递归解释时 release 栈溢出崩溃（1200 层存活，
  边界二进制相关）。三处根因全部收口：① `suffix_count` 死保险丝（全仓 3 处
  只增不比）接上 `MAX_DECLARATOR_SUFFIX=1250` 比较，超限转 E1006 诊断并吞
  剩余后缀干净收敛；② 抽象声明符路径（`sizeof(int[1]x1300)`）同样崩溃
  （is_abstract 全免检）——后缀计数对抽象路径同样生效；③ 函数声明符互递归
  （`int f(int f(...x1300))` 解析期爆栈，guard 每层 parse_declarator 新建
  不累计）——`parse_param_list` 挂 enter_depth 与语句/表达式共享总量语义。
  红→绿锚：`j1_declarator_depth.c`（30000 层，双侧编译失败判 match：clang
  对 10000 层仍编译成功、30000 层 signal 失败两次复测稳定）；验收锚 1200
  通过 / 1300 确定性诊断，1200 层用例不入防线（clang 可编译会造 vitro_better
  假信号）
- **类型深度预算（纵深防御）**：`MAX_AST_DEPTH=512` 只覆盖 Expr/Stmt，病态
  深 Type 对它隐身（`int a[1]x1300` 语句深度仅 2、类型深 1301）。新增
  `vitro_ast::depth::type_depth`（迭代式单源测量）+ `stmt_type_depth` +
  parser 后置 `MAX_TYPE_DEPTH=1250` 预算（globals/structs/unions/classes/
  funcs 全枚举声明点）；不并入 512——Expr 递归安全线不动，合法深层声明
  （1200 层实测存活）独立余量。注：typedef 链经 interpret 维度扁平化进单
  节点 `dims` vec，Type 树不深，1300 层 typedef 链编译成功为正确行为
- **facts 数字对账就近绑定**：此前行内所有落 Lo/Hi 区间数字都归属每条命中
  规则，"replay 61 / serve_smoke 57" 两真值键共行互落对方区间必然互斥判红
  （MoonBit迁移总计划.md:81 既有误报）。改为数字归属（双向）距离最近的规则
  关键词、平局取右（"cargo test 70 套件"后置单位胜）；J9 证红锚 ×6
  （near_bind_test.go：跨键双绿 / 近邻写错仍红 / 数字前置抓回 / 键位平局
  取右 / 最近键独占）

### Added (ABI 2.0.0 → 2.1.0)：四个 buf 写入式 C ABI 出口（零所有权转移）

`vitro_abi_version_into` / `vitro_engine_version_into` / `vitro_get_runtime_error_into` /
`vitro_get_compile_errors_into`——调用方缓冲 + NUL 终止，返回**完整所需长度**
（`n >= max_len` 即截断，消费方可检测）。跨语言 FFI 消费方优先用本形态。
动机（U2#13）：scripts 侧三处 `uintptr→unsafe.Pointer` 逆向转换是 vet
unsafeptr 检查器的不可豁免命中，buf 形态从根上消除——Go 侧 `PtrToGoString`
整体退役删除，`go vet ./scripts/...` 零输出并新入 CI 门禁；头文件四声明同步、
buf/指针两形态语义等价契约测试 ×2。

### Fixed (U2#13 libc 边界批 + 审阅 P1 修订)

- fseek 负偏移三形态（二进制 `as usize` 绕回 / 文本 SEEK_SET 同病 / 文本
  CUR-END 钳 0 假成功）统一为返回 -1 且游标不动（glibc EINVAL 语义）
- bsearch 野指针 key：切片 panic → 按"未找到"返回 NULL；越界早退移到
  `set_qsort_depth(+1)` 之前（审阅 P1-a：早退泄漏深度计数会让 8 次野指针后
  bsearch 永久 NULL、qsort 静默 no-op）
- host_strerror 补齐与 strdup 同型的分配三步契约（审阅 P1-b：无条件
  push_region 在地址复用时造同址双条目 + 索引失配；stale freed_logs 拦截
  写入返回全零缓冲）
- freed_logs 部分重叠整条删除改精确裁剪（前缀缩 size / 后缀改键插新 /
  嵌套拆两条）——UAF 假阴性窗口保留
- `register_function(_name)` 加 `MAX_FUNCTIONS=65536` 上限（u32::MAX 即
  resize 4G 项 OOM abort 的形态由同上限拦截）
- `call_user_function` 非 4 字节参数比较器：assert! panic → 教学 trap
  （检查前移至状态保存前，零污染）

### Fixed (U3#4/#5/#8)：模板实例化三缺陷

- **T1 实例化轮数上限**：`template<class T> int f(T t){return f(&t);}` 无限
  实例化（f<int>→f<int*>→…，一行代码 OOM 编译器，外部审查 3 秒栈溢出实锤）
  → Pass 3.6 循环加 1024 轮上限（对齐 clang -ftemplate-depth），超限新码
  **E1022_TemplateInstantiationLimit** 确定性诊断（触发锚 0.59s 有限完成）
- **T2 类实例化同收敛 drain**：pending_class 只在 Pass 3 后排空一次，Pass 3.6
  期间新发现的类被静默丢弃（合法 C++ 误拒）→ 类与函数在循环内同 drain +
  check_class_methods；**根因另有一层**：函数模板实例化体的 VarDecl 替换把
  TemplateId 静态 mangle 成 Class 名，跳过 visit 阶段的类合成与布局注册
  （`v.push_back(a)` 解析方法签名时 classes.get = None）→ 新增
  replace_template_type_preserve_tiid（VarDecl 路径保留 TemplateId）
- **U3#8 容器重复实例化查重前置**：第二个 `vitro_vec<Foo>` 曾在
  register_single_class_layout 报 E3002"类重复定义"（合法代码被拒，错误
  级联后常显形 E3023）→ 合成前查重（已注册返回占位名）+ push 点
  instantiated_class_names 单源查重

### Fixed (U3#9 止血)：同名嵌套 struct 静默覆盖改显式冲突诊断

两个类各含同名嵌套 struct（不同布局）时，展平命名下直接 insert 覆盖——
后注册者胜出，先者的成员访问全部指向错误布局（A::Inner{x} 被 B::Inner{y}
覆盖后 a.i.x 报 E3042 假错误）。改为保留首个 + 同名不同布局时显式 E3002
（显式拒绝优于静默错布局）。完整根治（嵌套名 mangled 化 Outer__Inner +
访问路径跟随）登记下批。

### Fixed (U3#2 先遣)：变参 double/long long 实参的 8 字节位模式中转

从 4 字节 slot0 + 占位 slot1 止血迁至 8 字节专用槽（call.rs 四处：
Call/CallPtr × D/Q）——两槽分配顺序由各自首次使用决定、不保证相邻，
跨槽写可踩相邻局部变量（3 起槽位 bug 同病灶）。


## [Unreleased]

### Fixed (CI 门禁)：Bytecode Libc 预编译产物在更名提交中被"文本替换"而非重生成——`--check` 自 `3a5e2f8` 起必红

CI 在 `python scripts/precompile_bytecode_libc.py --check` 失败（产物记录
`sha256:7077ef0c…` ≠ 当前计算 `sha256:1fdb34bf…`）。逐层取证后确认这是**真实的产物漂移**，
不是门禁误报：

- **根因（更名改变了源文件遍历顺序，产物却是文本替换的）**：更名提交把
  `native/runtime_libc/cide/` 改名为 `vitro/`。摘要按**整路径排序**遍历源文件，而
  `cide/` 排序在 `src/` **之前**、`vitro/` 排在 `src/` **之后** → 预编译单元的文件拼接顺序
  整体改变（`.cpp` 侧行号 +176、`.c` 侧 −359）。但该提交对产物只做了逐行文本替换
  `cide_`→`vitro_`（`git show --stat -M` = 132+/132−，全文件 32989 行），**没有重跑预编译
  脚本** → `source_digest` 冻结在更名前取值，门禁从该提交起必红（本地与 CI 一致，故排除
  mtime / 平台差异；`cide/`↔`vitro/` 的排序反转已用 `git show 18511d1:` 源文件复现出
  记录值 `7077ef0c…` 验证到字节）。
- **修复**：以当前 HEAD 编译器重跑 `python scripts/precompile_bytecode_libc.py`（`code_len`
  3485 / 88 函数 / `globals_size` 4 均不变，仅布局与元数据更新）。
- **零语义漂移取证**：新旧产物 88 个函数逐一比对——归一化（忽略跳转/调用目标与
  `StepEvent` 行号）后 **3485 条指令的多重集完全相同**，0 个函数指令流不同；差异只有
  三类即函数发射顺序、`SourceLoc` 行号、固定索引重分配（23 个函数），全部可由文件遍历
  顺序变化解释。即：更名期间的产物虽"元数据陈旧"，但语义与当前编译器一致。
- **验收（2026-09-14 实测）**：`--check` 绿；cargo 71 套件 **1000 passed / 0 failed**；
  clippy `--all-targets --all-features -D warnings` 零警告；C Shadow 675（668 match +
  3 known_issue + 4 gap_extension，非预期 0）；C++ Shadow 97（预期 gap 2，非预期 0）；
  serve 冒烟 57/57；replay 61/61。
- **流程教训**：产物是**生成物**，任何触及 `native/runtime_libc/` 的路径/内容改动
  （含目录改名）都必须重跑脚本，禁止对产物做批量文本替换——排序敏感的摘要正是为拦住
  这类"看起来等价"的改动而存在。

### Fixed (性能)：U2#2-b freed_logs 索引化——UAF 检测窗口的 O(16k) 扫描根治（1M churn 34.8s → 1.45s，累计 41.7×）

U2#2-a 的登记跟进批。稳态推演修正后归因确认：churn 稳态下**隔离区容量内
每块各留一条 freed_log**（free 时 push、地址复用时才删）→ ~16k 条，三个
O(16k) 热点：每次 malloc 的 `retain` 区间清理、每次 free 的 Double-Free
`find`、每次访存的 `check_uaf`（17μs/次 × 2M 次 ≈ 34s，与 U2#2-a 后剩余
墙钟精确吻合）。

- **结构**：`freed_logs: Vec` → **`BTreeMap<addr, FreedRegionInfo>`**。
  核心不变量：分配块**互不重叠** ⟹ addr 序即 end 序——区间查询/删除按
  addr 降序探测，end ≤ 查询起点即可判无重叠，O(log n + 命中数)。addr
  唯一（Double-Free 拦截在先）；迭代序变 addr 升序（原为 free 时间序，
  经查无顺序依赖消费者）；clippy 顺带抓出初版"伪循环"（降序首块单次
  探测即可判定）改 `range(..end).next_back()`；
- **API**：`freed_logs_remove_overlapping(start, end)`（替换 6 处
  retain）+ `freed_logs_find_overlapping(addr, size)`（check_uaf /
  trap_invalid_free 共用）+ Double-Free 精确查 `get(&addr)`；
- **差分保护先行**（重构前绿锁语义）：`test_u22b_freed_logs_multi_block_
  interval_semantics`（三块各自 free、复用中间块后未复用块的 UAF 窗口
  保留、跨块清理精确性）+ 既有 fuzz A"已释放块以 freed_logs 为准"压测
  全绿；
- **性能对照（行为零漂移：条目四点逐位一致）**：10k 171→118ms、
  100k 3.40s→**282ms（12×）**、1M 34.8s→**1.45s（24×）**——较
  U2#2-a 前基线（1M 60.4s）累计 **41.7×**；P-1 的 44.6μs/次 →
  ~1.4μs/次（~32×），超线性退化根治。

验收：cargo 70 套件全绿；shadow C 675 零非预期差异；serve 冒烟 57/57；
replay 61/61；clippy `-D warnings` 零警告；facts 漂移 0。

### Fixed (防线 6)：v4 清单 §6 代码侧第二批——文案/挂载点五项修复（人审 ✗ 键全数处置，golden 300→310）

- **#3 dp 子族具名**：外层/内层循环主语按特征词具名——币种循环
  （dpCoinChange：`for (i < coinCount)`）→"遍历币种 i"/"遍历金额 j"；
  物品循环（背包：lookahead 含 `wt[`）→"遍历物品 i"；无特征词保持泛化
  "子问题"（dpFib/dpLIS/dpLCS/matrixChain 的 i 确是子问题下标）。
  人审 ✗：#43（"遍历子问题 i=0"对币种循环不成立且丢信息）；
- **#4 insertion 位置 0 降级消除**：j 在 while 退出后作用域收回时，改用
  **行入口快照 `prev_vars` 的 j**（while 退出后行入口值即最终位置-1）——
  插到位置 0 的帧曾降级成"将 key=11 插入"（无位置），与有位置版同键两态
  互相矛盾（人审 ✗ #77）。修复后四条变体全部带位置且文案统一
  （"将 key=11 插入到正确位置 0" 等）；
- **#5 hanoi/topo 挂载点**：hanoi 体内的 return（含基准分支 L6）改文案
  "该层递归结束，返回上一层"（func_name==main 才报"汉诺塔移动完成"）——
  原文案挂在 L6 基准 return 上与语句不符（人审 ✗ #68）；
  topologicalSort/output 改挂**真输出行**（printf，L18），出队行独立为新
  词条 `dequeue`（"取出队头顶点"）——原判据命中 L17 出队行（人审 ✗ #112）；
- **#6 quick/partition_init 语义修正**：变量 pivot 的值是 partition 返回值
  （分区后枢轴**落位下标**），原文案"选取枢轴 pivot=0"教错——改
  "分区完成，枢轴落位下标 pivot=0"（phase 名不动：对外词汇面改动另行
  裁定，人审 ✗ #93）；
- **#7 KMP next/nextval 分段**：新增词条 `build_nextval`（词汇只增）——
  nextval 构建行/调用行不再混进"构建 next 数组"（computeNextVal 模板 22
  条挂错，人审 ✗ #35）；分支置于 next 之前（`nextval[next[j]]` 行同时含
  "next["）。
- golden 基线随批更新：**37 模板 / 310 条 / 113 键**（300→310：nextval
  变体分离 +9、insertion 位置版 +1 等）。新词条 `build_nextval` /
  `dequeue`（topological_sort）为 phase 词汇新增（algorithm_step.phase
  非冻结词汇表，golden 白名单不查 phase 词集）。

验收：cargo 70 套件全绿；golden CI 绿（漂移 54 处 → 重提取更新 → 复绿）；
shadow C 675 零非预期差异；serve 冒烟 57/57；replay 61/61；clippy 零警告。

### Fixed (防线 6)：v4 清单 §6 代码侧首批——golden 增算法归属 + 终态末帧重放根治 + dp 初始化内层排除（全部红→绿）

依据用户完成的三审处置与人审判定（`算法标注golden审阅意见三审20260914.md` +
人审清单 v4：113 键逐行判定 ✅94/✗11/⛔8），推进 §6 待落地清单：

- **§6-1 golden 增 `algorithm` / `display_name` 字段**（三审 P0-2 裁定 (b)）：
  JSON 帧本就携带（`AlgorithmStepSnapshot`），v3 固化时丢失。bst 家族跨算法
  混流（bstSearch/bstDelete 建树段讲插入）与**算法标签漂移**由此可检。红锚 =
  317 处全量字段差异 → 以 v4 提取数据重固化 → 绿；去重口径钉死 (phase, desc)
  （不因算法扩键）；
- **§6-9 终态末帧重放根治**：`UnifiedEngine.is_finished`——`StepResult::Finished`
  每次调用都 collect+push 同一帧（实测 binary 90 步程序 call#92+ 持续重发
  s=89，且重复帧污染 frame_cache / payload.get 窗口）。终结后再调用返回空
  payloads + finished=true（末帧已在结束轮发布）；`seek_to`（回到过去）复位
  标志。红锚 `test_step_next_after_finish_no_tail_replay`（修复前 FAIL）+
  发布序列严格递增断言；
- **§6-2 dp 初始化内层循环排除**（人审 ✗ ×3）：`infer_dp` 的 j 分支补
  `dp_loop_body_is_init` 排除（多行双层初始化的体 `dp[i][j] = 0;` 不在 for
  行内，outer 分支已有排除而 j 分支漏判）——dpKnapsack L14 / dpLCS L11 /
  matrixChain L6 的初始化挂载消失：dpLCS inner_loop 首现移到真算法循环
  L14；dpKnapsack/matrixChain 的 inner_loop 无首现（算法体内层是 w/k 变量、
  判据只认 j——属覆盖缺口非回归，golden 如实反映）。红锚
  `inner_loop_init_multiline_body_excluded`（修复前 FAIL）+ 反向锚
  `inner_loop_real_body_still_annotated`。golden 基线随批更新：
  **37 模板 / 300 条 / 111 键**（317→300：dpKnapsack -15、dpLCS -1、
  matrixChain -1，全部为人审 ✗ 的初始化变体）；
- 其间顺带实证一个提取器口径陷阱：判据修复后必须**重建 release** 再跑提取
  器（tmp 脚本读 release DLL，旧产物会回灌旧行为数据）。

验收：cargo 70 套件全绿；shadow C 675 零非预期差异；serve 冒烟 57/57；
replay 61/61；clippy `-D warnings` 零警告。

### Added (防线 6①)：算法标注 golden 固化 + CI 接线（U1#1 收官批，2026-09-14）

二审（`算法标注golden审阅意见二审20260913.md`）全部 P0/P1 修复落地后的收尾：

- **全量重提取**（对齐 serve 口径，R2 后 step.next 首调空帧天然适配）：82 模板
  = **37 有标注（317 条首现 / 113 个 (模板,phase) 行）+ 45 零标注**——比二审
  §4.2 预期 34 多出的 3 个恰为 P0-B 批复亮的 bstInsert/bstSearch/bstDelete
  （4/7/11 条），口径吻合；零错误帧；
- **golden 固化 + CI**：`native/tests/golden/algorithm_annotations_v3.json`
  + `algorithm_annotation_golden_test`（Rust 直调 `session_api`——须走
  `session_api::compile`（内含算法检测）而非裸 compile_pipeline，直调管线
  全零标注的实证已锚进注释）；双向防漂移断言（有标注模板集与 golden 键集
  严格相等——新复亮/新转零均红）；J9 埋雷证红（改一条 desc → 红 → 还原绿）；
- **golden 定位（诚实边界）**：三审修复链后的**行为基线快照，非语义人审认证**
  ——人审勾选在基线上继续，更新 golden 须附红→绿锚；
- **§7.4 has_word 表格化单测**（`has_word_segmentation_table`，21 例穷举二审
  手算五形的"大写段末归属"规则）；**§7.1 定性**：`finished` 信号已存在（二审
  提取器未消费），但**结束后 step.next 重复发布末帧**（run_batch 终态重放，
  实测 call#92+ 重发 s=89，违反"每真实步恰投递一次"）——消费方 finished 即停
  故低危，**登记待修**；§6 判据层专属锚未单独补齐（golden 317 条全量锚已
  实质覆盖防漂移诉求，登记豁免理由）。

验收：cargo **70 套件**全绿（+1 golden 套件，15.5s）/ clippy 零警告。

### Fixed (性能/正确性)：U2#2-a regions addr 索引化 + Q7-G6 复核关闭（分段饱和定论，行为零漂移）

**Q7-G6 复核收尾**（裁定 §5.4 表内"待复核"矛盾的证据仲裁，2026-09-14 关闭）：
新增采样驱动 `scripts/core_asset_verdict/regions_growth`（serve 会话 `config.set
max_steps` 提预算 → churn ×N → `memory.regions` 的 `region_counts.heap` **直接读
条目数**，通道失效 fail loud）。四点定论：1k=1002 / 10k=10002 / 100k=16387 /
1M=16387（后两点逐位相同），墙钟 94ms/227ms/4.77s/60.4s——**分段饱和模型**
（裁定 §5a）：推进期条目随 N 线性（"14B/次"成立）+ O(N²) 时间分量；饱和期
（隔离预算 `MEM_SIZE/4`=256KB 填满后 FIFO 驱逐 + free_list 复用）条目恒 16387
（=256KB÷16B）+ O(N) 线性（固定 ~16k 条扫描/次）。裁定"峰值平坦+≈线性"与评估
报告"14B/次+O(N²)"**两侧均为真**（观测区间不同）；饱和机制是隔离区决议的设计内
行为，UAF 检测窗口完好。原方案"归并 freelist 摘要"撤销（条目天然有界），
U2#2 重构收缩为 **addr 索引化**。

**U2#2-a 索引化实现**（差分保护先行 → 热点改写 → 性能对照）：

- **差分保护用例 ×5 先行**（`host_contract_tests`，重构前全绿锁语义）：churn
  稳态隔离窗口存活（freed_logs 不被复用路径误删）、复用元数据复位 +
  freed_logs 清理（不误报 UAF）、churn 泄漏计数 + 条目唯一性、快照恢复后
  free 语义（时间旅行）、realloc 复用无双条目；
- **索引结构**：`MemoryState.region_index: HashMap<addr, idx>`（`#[serde(skip)]`，
  可从 Vec 重建）+ `push_region` / `find_region_mut` / `rebuild_region_index` /
  `verify_region_index`（一致性校验）。不变量：`regions` 只增不删 → 下标稳定；
  addr 唯一；
- **热点改写**（~16k 条线性扫描 → O(1)）：`host_malloc`（复用复位 + 元数据
  更新合并为一次 lookup，消除旧实现的两遍扫描）、`host_free`、`host_realloc`
  ×3 处、`host_calloc`、`host_strdup`、`host_fopen`、VM 内部 `free_memory`、
  `MemoryState::free_region`（vfs 路径）、`vfs::malloc_raw`；
- **存量缺陷修复（同类清查实锤，红→绿）**：`host_realloc`/`host_calloc` 的
  新块登记走无条件 `push`——`allocate_raw` 复用隔离驱逐块时同 addr 双条目
  （泄漏报告把已释放块虚报为泄漏 + 破坏索引不变量）。红锚
  `test_u22_realloc_reuse_no_duplicate_entries`（修复前 FAIL 留痕），改"复位
  or push"后绿；
- **维护点**：快照恢复（`snapshot.rs` regions 重装后 `rebuild_region_index`）+
  `reset_runtime`（索引随 regions 同步 clear）；
- **性能对照（行为零漂移验证）**：四点条目数逐位一致（1002/10002/16387/
  16387 ✓）；墙钟 100k 4.77s→3.40s（1.4×）、1M 60.4s→**34.8s（1.74×）**。
  提升受限的归因（实测吻合）：剩余大头是 `freed_logs` 的两个 O(稳态 16k)
  路径（每次 malloc 的 `retain` 区间清理 + 每次 free 的 Double-Free
  `find`——17μs/次 × 2M 次 ≈ 34s）——需 BTreeMap 区间结构且涉 `check_uaf`
  辐射面，**登记为 U2#2-b 跟进批**（不滚雪球）；
- **本批边界（登记保留线性）**：范围查询类（`trap_invalid_free` 的内部地址
  判定、strcpy/strcat 的 E3070 容量检查——均为低频错误/检查路径，需区间结构）；
  vfs 四处按 addr 改名循环（低频只读，不动 addr 不破坏索引）。

验收：cargo 69 套件全绿（host 契约 100/100）；shadow C 675 零非预期差异；
serve 冒烟 57/57；replay 61/61；clippy `-D warnings` 零警告。

### Fixed (出口 3)：R2——step.next 一帧发布缓冲重复投递（0,0,1，违反 spec 附录 A 冻结不变量）+ replay A4a 版本下限误拒 + 防线缺口闭合（来源：下游 PR 引擎回归审阅）

**回归来源**：U1#1 修"首帧显示赋值前旧值"引入的一帧发布缓冲，声明代价"滞后一帧"，
实现却成重复发布——首帧 `curr` 的克隆被发布后又把 `curr` 入缓冲，下一轮缓冲帧再度
发布（实测序列 `0,0,1`，同一真实步投递两次，违反 schema 附录 A
"`step_index` 严格递增"冻结不变量；M3/V 步进 UI 消费前必须修复，M1 判分不受影响）。

- **引擎修复**（`session_api.rs` `step_next` None 分支）：首调**只建立缓冲、返回空
  payloads 序列**——"滞后一帧"的完整语义。消费方契约变化（schema §6.1 已冻结）：
  首调 `payloads: []`；此后每次恰 1 帧（上一步的帧，语句中间帧清行末标注）；
  `finished` / `paused`（断点 UI 依赖断点行帧随暂停发布）/ `waiting_input` 时冲刷；
  恢复后缓冲重建（首个恢复响应为空）；全序列每真实步恰投递一次；
- **驱动 bug**（`scripts/replay`）：A4a `abiVersionAtLeast` 旧实现 "major 不同即
  false" 把更高的 ABI **2.0.0 误拒**（2.0.0 ≥ 1.1.0 本应通过——项目更名批升 2.0.0
  当天即被误拦）；改 semver 下限语义，selftest 补 5 条埋雷（低于下限/同 major 低
  minor/垃圾串必红，更高 major/边界相等必过）；
- **防线缺口闭合**（审阅实锤："能拦住它的签字回放断言恰好不在上游的验证循环里"）：
  ① `go run ./scripts/replay` 纳入 CI（此前 Go 驱动不在任何验证循环，S1 A7b 断言
  从未跑到）；② replay A7b 口径按缓冲语义重写（首调空帧 + 其后恰 1 帧 + 严格递增，
  重复投递 0,0,1 形态即红）；③ replay S3 A3 口径重写（旧断言的绿恰好依赖修复前的
  克隆直发实现，与 A7b 严格递增互斥——恢复首响应空帧=缓冲重建，次响应新帧不重编号）；
  ④ serve_smoke 旧断言"单次响应 payloads 非空"对重复投递与首调空帧双失明，改合并
  序列断言（非空 + `step_index` 严格递增，+3 条断言）。

红→绿：replay 修复前 `S1 A7b` + `S5 A4a` 双 FAIL 留痕（61 断言 59/2）；修复后
61/61。验收：cargo 69 套件全绿；shadow C 675 零非预期差异；serve 冒烟 57/57
（RSS 护栏绿）；clippy `-D warnings` 零警告；facts check 漂移清零（serve 断言
54→57 机器同步）。**登记（不扩批）**：`go vet ./scripts/...` 存量 3 处
`possible misuse of unsafe.Pointer`（`internal/capi` PtrToGoString 长窗口扫描 ×2
+ `gosmoke/cabi_smoke` cString ×1，后者注释自称"vet 合规"与事实不符）——CI 无
vet 步骤故长期未暴露；修复须与"CI 补 vet"同批，登记待办。

### Fixed (预处理器)：U1#11 预处理器 P0 批——include 静默跳过 / `__has_include` 口径分叉 / `<>` 收紧 / 跨文件条件栈污染 / 环检测长链漏报（全部红→绿闭环）

来源：路线图 U1#11 两处（条件栈污染 + 环检测 fail-open）扩容合并
`实测发现登记20260913_性能与头文件.md` 的 H-1/H-2/H-3（四处修复），六项收口：

- **H-1（include 找不到静默跳过，错误错位到使用点）**：`handle_include` 的
  静默 `return` 改报 **`E1021_IncludeNotFound`**（新增错误码，定位在 include 行，
  文案列出已搜索目录）；既有单测 `test_preprocessor_include_once` 曾把该缺陷
  固化为 `errs.is_empty()` 断言，已改写（include-once 语义改用真实头验证）；
- **H-2（`__has_include` 与 `#include` 口径分叉）**：`has_include` 改与
  `resolve_path` 候选链单源（包含者目录优先），并携带定界形式——
  `__has_include("x.h")` 在头文件内部不再误判 0（T14 实锤修复）；
- **H-3（`<>` 也搜源目录，比 Clang 宽松）**：**收紧**——`<>` 只匹配标准库存根
  （14 个名字），不搜索文件系统目录；`parse_include_path` 起携带定界符。
  存量语料扫描：655 处 `<>` include 全为标准头名，**零存量依赖**；wasm 冒烟
  与 C++ 用例均不受影响；
- **跨文件条件栈污染**：`#__vitro_push_dir` 哨兵起同时记录条件栈深度
  （`include_cond_boundary`）——头文件内未闭合 `#if` 在边界自动闭合报
  `E1013`（不再吞掉包含者后续代码）；头内多余 `#endif` 被拦截报 `E1011`
  （不再弹掉包含者的条件组、错误不再错位到主文件）；
- **环检测长链漏报 + 动态深度保险丝**：静态 DFS 封顶 16/64 → **64/512**
  （`MAX_INCLUDE_DEPTH`/`MAX_INCLUDE_GRAPH_NODES`，20 文件环实测检出——旧封顶
  下静默漏报零诊断）；新增动态嵌套深度保险丝（`dir_stack` 深度 ≥64 报
  `E1015`，两口径共用同一常量防"保险丝口径错"复发）；`should_include` 的
  key_for 失败放行注释更新（fail-closed 由 handle_include 的 E1021 诊断承担）；
- **文档随批（D-1/D-2/D-3）**：C语言子集规范 §1.2 排除原则勘误（旧例
  "完整预处理器、自定义头文件"已由 E2 推翻）、已知差异表 include 行重写、
  §2.11 六项行为变更登记（含 U1#6 漏更的展开保险丝字节口径一并修正）；
  架构设计.md ABI 版本 1.2.0 → 2.0.0。

红→绿锚：`lexer_unit_test` U1#11 组 ×8（修复前 8 FAIL 留痕——含 E1011 错位
line=3 实锤、20 环零诊断实锤）；shadow 新用例 ×4（`e2_include_not_found_quote`
双侧编译失败 / `e2_include_not_found_angle`、`e2_angle_local_header` 修复前
vitro_better→match / `e2_has_include_chain` 修复前 output_gap 输出 0 vs 13）。
验收：cargo 69 套件全绿；shadow C 675（668 match + 3 known_issue +
4 gap_extension，零非预期差异）；C++ shadow 非预期 0；serve 冒烟 54/54
（RSS 护栏绿）；clippy -D warnings 零警告；facts check 漂移清零。

### Changed：项目更名 Cide → Vitro（全量符号落地，ABI 2.0.0）

品牌与符号层一次性统一为 **Vitro**（*in vitro*，"在玻璃之中"——白箱观察 +
Clang 基线诚实对照的定位同构；此前品牌/符号双名并存是 AI 辅助开发的幻觉温床）。
决策依据与完整映射见 [`docs/current/01-定位与路线/项目更名记录.md`](docs/current/01-定位与路线/项目更名记录.md)。

- **crate（10 个）** `cide_*` → `vitro_*`；主包 `cide_native` → `vitro_native`（cdylib `vitro_native.dll`）；
- **C ABI（41 入口）** `cide_*` → `vitro_*`，契约版本 **1.3.0 → 2.0.0**（符号面 breaking → major；
  函数语义 / JSON 帧格式 / 状态码零变化，消费方迁移 = 纯符号改名 + 重链接）；
- **CLI** `cide_cli` → `vitro_cli`（`src/bin/vitro_cli.rs`）；C 头文件 `cide_capi.h` → `vitro_capi.h`；
  运行时 libc 目录 `runtime_libc/cide/` → `runtime_libc/vitro/`；Go module `cide` → `vitro`；
- **CideVM → VitroVM**（虚拟机名随品牌）；大小写三变体 cide/Cide/CIDE → vitro/Vitro/VITRO 全量替换；
- **边界（诚实记录）**：`docs/archive/` 内容与归档文件名保留 Cide 原样（历史快照不篡改，维护者裁定
  2026-09-14）；活文档中对归档原文件名的引用受保护未替换；英文词 `INCIDENT(S)`/`accidental` 天然豁免；
- **联动修改**：`test_e2e_my_strlen` 输入字面量 `"CideVM"`（6 字符）→ `"VitroVM"`（7 字符），
  期望输出 `"6"` → `"7"` 联动（非预期值粉饰，注释已锚定）；
- **品牌资产**：`assets/logo/` 横幅锁定 + 方形图标 + 预览页（README 头图已引用 vitro-logo.svg）；
- **验证**：cargo check / clippy(-D warnings) / 全量 test（68 套件）全绿；go vet exit 0；
  Shadow 防线 671 用例 match 664 + known_issue 3 + gap_extension 4（与改名前基线逐项一致，
  行为零差异）；serve 冒烟 54 项断言全 PASS。

### Fixed (教学标注)：二审 P0-B——bst 家族判据定清（名字+语义双条件）+ bst_validate/bst_delete 新算法 + is_recursive 真实管线激活

二审（`05-教学体验/算法标注golden审阅意见二审20260913.md` §2 P0-B）实锤
`isValidBST` 被按"BST 插入"教学（三条文案全部与所挂语句语义不符），采用
**方案②** 处置，并顺带定清 bst 家族判据（同文档"同一判据的两侧"）：

- **bst 家族判据重写**（`algorithm_detector/tree.rs`）：`has_word("bst")`
  单条件改为**名字 + 语义词双条件**（bst 命名语境 + insert/add、search/find、
  delete/remove、valid/validate 任一整词）；bst_validate 判据优先于
  bst_insert（isValidBST 不得落插入）；bstHeight/bstTraverse 等无语义词
  名字不再被讲成插入。红→绿：`isvalidbst_detected_as_bst_validate_not_insert`
  / `bst_names_without_semantic_word_not_insert`（修复前实测 FAIL 留痕）。
- **人审档 A 裸命名漏检补齐**（bstInsert/bstSearch/bstDelete 模板函数名为
  裸 insert/search/deleteNode）：新增 `FuncFeatures::is_treenode_ctx`
  （任一参数/返回类型 pointee 为 `TreeNode` 结构，穿透指针层**整名**匹配
  ——BTreeNode/AVLNode/RBNode/HashEntry 均不命中），裸命名判据 =
  语义词 + TreeNode 语境；bst_search 额外要求递归（迭代 findMin 不算）。
  三个模板从零标注复亮：bstInsert 4 条、bstSearch 7 条（bst_insert +
  bst_search）、bstDelete 11 条（bst_insert + bst_delete）。
- **新增 bst_validate 步骤模板**（`vitro_algorithm_steps/src/tree.rs`）：
  empty_valid（空树合法）/ range_check（(min,max) 开区间校验）/ recursive
  （区间收窄递归）三 phase，挂载点即二审表格的 L20/L21/L32——实测
  binarySearchTreeValidation 三条错误插入文案全部替换为正确校验文案。
- **新增 bst_delete 步骤模板**：not_found / compare / recursive /
  single_child / free / find_successor / replace 七 phase。
- **is_recursive 真实管线激活（两处既有缺陷，检测器单测因手工构造
  features 未暴露）**：① `extract_features` 曾给 walk 传空 func_name，
  自调用比较永假；② 本前端函数调用统一为 `Expr::CallPtr { callee }`
  形态，walk 只匹配 `Expr::Call`——`is_recursive` 在真实管线上恒 false
  （bstSearch 的 search 函数 47 帧零标注即此两叠加）。补 CallPtr 分支 +
  传真实函数名；管线级回归锚落在
  `native/tests/algorithm_detector_pipeline_test.rs`（Lexer→Parser→
  detect_algorithms 全链路，修复前 search 零 match）。
- **影响面精确性对账**（82 模板 × 4000 步提取，25s）：受影响模板集合
  恰好 = {binarySearchTreeValidation, bstInsert, bstSearch, bstDelete}，
  总首现条数 303 → 325；sorting 侧依赖 is_recursive 的 quick/merge/heap
  补充分支在模板集上零新命中。门禁：cargo test 962/0、clippy 零警告、
  serve_smoke 54/54。

### Fixed (教学标注)：U1#1 管道批——collector→infer 上下文扩容，四项登记全部收口（P0-4/P1-3/P1-4/P1-1 边界）

新增 `InferEnv`（collector 构造，随帧传入 inferrer）：`prev_vars`（行入口
变量快照——session 维护行变化时的上一行末帧变量）、`at_callee_entry` +
`caller_is_main`（callee entry 帧的 caller 栈层判定）、`lookahead`（下 3
行源码，嵌套 for 头穿透）。

- **P0-4 收口**：gcd mod 用行入口操作数拼算式——三轮全部正确
  （`48 % 18 = 12` / `18 % 12 = 6` / `12 % 6 = 0`，二审实锤的
  "48 % 12 = 0" 错误算式消除）。
- **P1-3/P1-4 收口**：`at_callee_entry && caller_is_main` 区分顶层启动
  调用——quick 首现"启动快速排序：处理区间 [left=0, right=4]"、merge
  "启动归并"从死代码 0 次变 1 次（均挂 main 调用行）。
- **P1-1 边界收口**：lookahead 穿透嵌套 for 头——dpLCS outer_loop 首现
  L13（初始化 for L10 已离开）、matrixChain L9（L5 已离开）；dpFib/
  dpCoinChange 保持正确位点；六 dp 模板 transition 全在真转移行。
- **顺带实锤并修复**：上批 §7.3 的 append 改动把逻辑写反（curr 被发布、
  缓冲置 None——gcd 帧级调试暴露中间帧带标注泄漏），回正为 curr 整体
  移入缓冲 + match 外统一赋值。
- 验收：cargo 69 套件 / clippy 零警告 / serve_smoke 54/54。

### Fixed (教学标注)：U1#1 第四批（二审 P0-C + P1 批，含两处如实登记未修）

- **P0-C**：gcd mod 判据 `contains('%')` 过宽（printf 格式符命中，首现
  漂 main 打印行）——排除 IO 行 + 要求 `%` 出现在表达式语境（` % ` /
  `%=`）。首现回真语句 L6。
- **P1-2**：radixSort count 的 `++` 曾被 for 头 i++ 满足（清零行误命中）
  ——收紧为 `]++` 自增形态。首现回 L13 统计行。
- **P1-5**：函数签名行统一排除（infer_algorithm_step 总入口：类型关键
  词开头 + `{` 结尾；`int mid = ...;` 以分号结尾不受影响）——hanoi L3
  七条、getNext L4 的 next[-1]=-1、isValidBST L19 签名帧标注全部消除。
- **P1-1（部分）**：dp outer_loop 排除"循环体为 dp[..] = 纯字面量"的
  初始化循环——单行 for 形态修复 2/4（dpCoinChange/dpLIS 离开初始化位）；
  dpLCS/matrixChain 的多行 for 体不在 for 行内、单行判定不可达——
  **登记边界**（跨行上下文需 collector 管道）。
- **§7.5**：hanoi 零盘递归（n=1 的 hanoi(n-1)）不再产出"递归移动 0 个
  盘子"。
- **§7.3**：step_next 发布缓冲改 append 语义（insert 替代 vec![pending]
  整体替换）——run_batch 恒 batch=1 时等价，batch 调大时防静默丢帧。
- **P1-3/P1-4（如实登记未修）**：顶层调用与递归的区分——实测带标注帧
  是 **callee entry**（func_name 已是被调函数、code_line 仍是 main 调用
  行），`func_name=="main"` 判定不触发（本批首版尝试即因此回退）；
  merge 的旧 `contains("main")` 死代码已删。正解需 at_callee_entry 传入
  inferrer——与 P0-4 prev_vars 同批的管道改动（collector→infer 上下文
  扩容），登记下一批。
- **P1-6**：零标注缺口登记进清单头注（activitySelection/externalSort/
  mergeSortedLists 转零是误判消除的代价；huffmanTree select 零触发）。
- 验收：cargo 69 套件 / clippy 零警告 / serve_smoke 54/54；七项修复
  逐一模板实测（gcd L6 / radix L13 / 签名行 0 条 / 零盘 0 条）。

### Fixed (教学标注)：U1#1 第三批（用户机器复核驱动）——has_word 缩写漏报 + 四算法误判 + dp 判据 + P1 判据批

用户以 100 行逐行判定复核 v2 清单（62 ✅ / 25 ✗ / 13 ⛔，见
`05-教学体验/算法标注golden审阅意见.md`），五个 P0 + P1 表全部处置：

- **P0-1 has_word 驼峰缩写漏报**（用户修复引入、本轮修正）：连续大写
  被逐字母切开（isValidBST → ["is","valid","b","s","t"]），bst 整词
  永不命中 → binarySearchTreeValidation 4001 帧零标注（静默漏报）。
  改标准驼峰边界（小写→大写分词；大写→大写且下个小写分词——段末大写
  归下词；纯缩写合并）。单测 +2（isValidBST/allCapsAcronymBFS 识别、
  subString 不识别）。
- **P0-2 四算法误判**（huffmanTree/activitySelection/externalSort →
  selection_sort、mergeSortedLists → merge_sort，13 行 ⛔ 之源）：
  selection 收紧为 select/selection 整词 + sort 语境（结构分支排除
  huffman/activity/replacement 贪心语境）；merge 收紧为 merge 整词 +
  sort 语境。四模板实测误判清零（huffman 只剩正确的 huffman_tree 标注）。
- **P0-3 dp 判据**：transition 要求同语句两侧都有 `dp[`（5 个 dp 模板
  首现曾全挂 `dp[0] = 0;` 初始化行）；outer_loop 收紧为 i 形态判据
  （`contains("n")` 曾因 amount 含 n 把内层循环误判外层）；文案
  "遍历物品"泛化为"遍历子问题"。
- **P0-4 gcd mod 数值全错**（行末帧 b 已被赋值，48%12=0 真值 48%18=12）：
  本批安全降级为不展示操作数的文案；**prev_vars 快照管道（运算过程类
  phase 用语句前操作数）登记下一批**——口径规则：展示结果值的 phase 用
  行末帧、展示运算过程的 phase 用执行前操作数。
- **P1 判据批 10 项**：selection 的 minIdx 别名 + j∈[0,n) 越界守卫
  （min_idx=? / arr[5] 越界消除）；insertion insert 收紧 `arr[j+1]=key`
  形态（不再命中 `int key=arr[i];` 读行，j 不可得时文案去位置）；
  primMST add_vertex 收紧 `lowcost[k]=` 形态（初始化行"顶点 -1"消除）；
  countingSort place 收紧 `index++` 形态（`int index=0` 初始化不再命中）；
  radixSort digit_loop 位序修正（exp 是位权，"第 10 位"→"第 2 位"）；
  hanoi 递归以 `n-1` 实参形态区分调用点（main 调用 n=3 不再报"2 个"）；
  quick side 默认空串（"子子数组"错字根因）+ 空区间帧屏蔽 +
  merge 顶层调用改"启动归并"；build_next 调用点改无数值启动文案；
  bfs 首帧"起点入队"；seqList update_len 收紧 `length--/++` 形态。
- **selection 整词回归当轮抓回**：收紧后 selectionSort 零标注（整词是
  "selection" 非 "select"）——补两形态后恢复。
- 验收：cargo 68 套件 / serve_smoke 51/51 / shadow C 671（664/3/4）/
  C++ 非预期 0 / clippy 零警告。**主表重提取与 v3 清单待办**（本轮
  修复批先记录于清单头部，用户二审复跑提取脚本对账）。

### Fixed (教学标注)：U1#1 第二批（用户审阅驱动）——首帧旧值 + 结构特征误判 + dp 孤儿接线（红→绿）

用户审阅否决 v1 人审清单（"数值列系统性不可信，勾选会把错误固化成 golden"），二轮修复：

- **P0-1 首帧旧值**（用户实测三例：binary 首帧"计算中点 mid=0"实际 mid=2、
  shellSort"取增量 gap=0"、dijkstra"顶点 -1"）：同一语句的多帧中首帧在
  赋值发生前。修复双层：① run_batch 返回数组 + frame_cache 同步去重
  （同行非末帧标注清除，含跨批衔接）；② serve step.next 一帧发布缓冲
  （流式协议下行末判定需要未来信息——当前帧暂存、下一帧到来回改上一帧
  后发布；首帧直接发布保证 payloads 恒非空；结束冲刷按行号决定标注
  去留）。实测三例首帧错误值全部消失。
- **P0-2 结构特征误判**（用户实测：linear→"BFS 遍历完成"、hashTable→
  "队列非空继续广度优先搜索"、stringBasicOps→"递归查找插入位置"）：
  检测器四个结构分支收紧为命名主导——BFS 删 `search+单循环+回边`、
  DFS 删 `递归+search`、BST 插入/查找收紧 bst 语境、链表删除收紧
  linked/list 语境（bstDelete 的 deleteNode 曾被误判链表删除）。
- **dijkstra confirm 误匹配**：`visited[v0] = 1;` 初始化行曾被判
  "确认顶点 -1"——收紧为 `visited[u] =` 形态。
- **P1-a dp 孤儿接线**：`infer_dp` 已实现但检测器无 dp 分支（永不调用）——
  features 补 `dp[` 状态表特征 + 检测分支；dpFib 实测出现
  transition/outer_loop/finish。dp 文案"遍历物品"的泛化问题入人审清单。
- **已知代价（人审清单待裁定）**：bstInsert/bstSearch/bstDelete 模板
  函数名为裸 insert/search/deleteNode，收紧后漏检——建议模板函数名加
  bst_ 前缀（对 golden 无影响）。
- **v1 口径错误修正**（用户指出）：v1 把 target=7 探针序列误写"模板实测"
  （模板默认 target=5 一次命中仅 4 条）——v2 清单描述均注明探针来源。
- 红→绿锚：检测器单测 +7（linearSearch/递归 binarySearch/hashTable 插入/
  BST deleteNode 四误判反向锚 + bfs/dfs/bst/链表 delete 正向锚）、
  dijkstra confirm 单测 ×2。人审清单 v2 重写（38 模板 × 100 条，行末帧
  语义；覆盖缺口分三档）。
- 验收：cargo 68 套件 / serve_smoke 51/51（一帧缓冲协议兼容）/
  shadow C 671（664/3/4）/ C++ 非预期 0 / clippy 零警告 / facts check 绿。

### Fixed (教学标注)：U1#1 第一批——防线 6 算法标注三误标修复 + 88 模板标注人审清单（红→绿）

- **三个审查实锤误标全部机器取证后修复**：
  - **二分三分支不可达**（`vitro_algorithm_steps/search.rs`）：mid_calc 旧
    条件 `contains("mid") && contains('=')` 过宽——`if (a[mid] == target)`
    含 `==`、`left = mid + 1` 含 `=`，compare / narrow_left / narrow_right
    三分支全部被短路。机器取证：比较行被标"计算中点 mid=2"，学生在循环
    体里只看得到"计算中点"（概念教反级）。收紧为声明/赋值形态
    （行首 `int mid` / `mid =` 且含除法）。
  - **right=mid 打印硬编码差一**：旧文案打印 `right={mid}`，标准二分是
    `right = mid - 1`。改打印**边界变量实际值**——对闭区间与左闭右开
    两种约定都正确。
  - **insert 子串误判插入排序**（`algorithm_detector/sorting.rs`）：
    `insert_node`（链表插入）曾被判插入排序。收紧为 insertion /
    insert_sort / insertsort（驼峰折叠）形态；实测 `insert_node` 程序
    零算法标注。
- 修复后二分标注序列（实测）：`搜索范围 [0,4]` → `计算中点 mid=2` →
  `arr[2] 与目标值 7 比较` → `目标值在右半区，调整左边界 left=3` →
  `找到目标值，返回索引 3`。
- **红→绿锚**：vitro_algorithm_steps 单测 ×3（比较行不被短路 / narrow
  实际值 / mid_calc 反向锚）+ algorithm_detector 单测 ×2（insert_node
  零误判 / 标准命名仍识别）。
- **人审清单交付**（U1#1① 的"人审固化"环节）：
  `docs/current/05-教学体验/算法标注golden人审清单.md`——88 模板批量
  提取（serve 会话逐步收集 algorithm_step），37 模板 × 58 条标注待逐行
  勾选；45 模板零标注（检测覆盖缺口）、7 超大模板步数截断、6 个 cpp
  模板待 C++ 提取口径；附 insert 同族子串风险 5 项待裁定
  （merge/binary/quick/heap/select）。
- 验收：cargo 68 套件 / shadow C 671（664/3/4）/ C++ 非预期 0 /
  clippy 零警告。

### Fixed (parser/ast)：U1 第六批 #8——递归深度防护补全（五通道）+ 后置 AST 深度预算（红→绿）

- **五通道实测栈溢出复现后修复**（修复前 release vitro_cli 全部
  "has overflowed its stack"）：初始化列表嵌套（3000 层）、赋值右结合链
  （3000 级 `a = b = b = …`）、一元运算符链（5000 个 `!`）崩在 parser
  递归；数组后缀链（5000 个 `[0]`）与左结合加法链（5000 项，外部审查
  实锤"崩在 typeck 非 codegen"）崩在 typeck / 递归 Drop——parser 层是
  循环不递归，构造期无拦截点。
- **修复双层**：
  - parser 挂点：`parse_init_list` / `parse_assign` / `parse_ternary` /
    `parse_unary` / `parse_abstract_declarator` 五个递归入口挂防护壳
    （超限 E1006 + 跳 EOF 让外层循环收敛）。
  - 后置 AST 深度预算：`vitro_ast::depth` 迭代式 DFS（显式栈——被测的
    就是病态深 AST，递归测量自身会先溢出），`parse()` 成功后对函数体/
    全局初始化式测深，超 512 报 E1006 并 `mem::forget`（递归 Drop 同样
    溢出，在"泄漏一次编译的 AST"与"崩溃进程"间选前者）。
- **首版口径错误教训（当轮抓回）**：链壳挂共享计数后每层括号消耗 4 计数
  （primary+assign+ternary+unary），上限 64 时 16 层括号即触发——**误伤
  30~40 层合法嵌套与既有回归测试** `test_legal_deep_expression_still_compiles`。
  修正：上限 64 → 256（256/4 = 64 层语法嵌套，**与原语义精确等价**）；
  中间试验过"链计数独立 + primary 重置"方案因链式操作数也经 primary（
  重置把链计数每级清零，s3 赋值链漏拦）而废弃。
- 红→绿锚：crash_regression_tests 新增 6 条（五通道 + 合法嵌套反向锚，
  修复前 5 通道实测溢出留痕）；全量验证 cargo 68 套件 / shadow C 671
  （664/3/4）/ C++ 非预期 0 / clippy 零警告。

### Fixed (lexer 预处理器)：U1 第五批 #6——宏展开双保险丝修复（死代码复活 + 字节口径，红→绿）

- **缺陷 ①（深度保险丝死代码）**：深度检查只在 `expand_tokens`（depth=0
  公开入口）而递归全部走无检查的 `expand_inner`——自引用/互引用靠
  expanding 集合停止，但**不同名对象宏链** `#define M0 M1`、`M1 M2`、…
  不触发查重，逐层递归直至栈溢出（实测 5000 层 `thread 'main' has
  overflowed its stack` 崩溃）。既有测试 `test_preprocessor_depth_fuse`
  在旧代码下通过是**被 token 预算的同码 E1017 掩盖**（REP 嵌套先撞
  26 万 token 预算），并未覆盖深度路径——"防线照不到"的又一实证。
- **缺陷 ②（预算口径错——数 token 不数字节）**：`S(x) x x` + 4KB 字面量
  × 14 层 = 16384 个 token（远低于 26 万预算）但实际产出 **67MB**
  （诊断暴露 `char[67108865]`），零 E1017，67MB token 流全程进入
  parser/typeck。
- **修复**：① 深度检查移入 `expand_inner` 每层递归入口（错误只报一次，
  新增 `depth_exceeded` 标志）；② `emitted` 计费改**累计字节**（token
  文本长度 +1 分隔），常量 `EXPAND_TOKEN_BUDGET`(26 万) →
  `EXPAND_BYTE_BUDGET`(16MB)；③ trace 单条长度封顶
  `TRACE_ENTRY_MAX_CHARS`(2KB 截断)——条数封顶不防单条，67MB 展开的
  结果拼写拼进一条 trace 同样是病态内存。
- 红→绿锚（lexer 单测 ×3）：`test_preprocessor_depth_fuse_object_macro_chain`
  （5000 层链：旧代码栈溢出崩溃 → E1017）、
  `test_preprocessor_byte_budget_large_literal_amplification`
  （67MB 放大：旧代码零诊断 → E1017）、
  `test_preprocessor_normal_nesting_not_affected_by_fuses`
  （反向锚：正常 4 层嵌套零误伤）。

### Fixed (codegen)：U1 第四批 #3——初始化基址槽被嵌套调用覆盖（止血版，红→绿）

- **根因（外部审查 P0-1 复现确认）**：数组/结构体初始化的写入基址存
  `temp_slot0`，但初始化列表元素的 `gen_expr` 内部同样消费 slot0——两个
  实测触发分支：① 变参调用的 double/long long 实参走 `StoreLocalD/Q slot0`
  （8 字节写入同时踩 slot0/slot1）；② 按值传 struct 的 Call 实参地址临时。
  基址被覆盖后，后续元素写内存变野地址（实测 trap"向 NULL 指针区域写入
  （地址 0x0010）"——数组越界假错/内存写坏）。
- **修复（触发面止血）**：初始化三路径（string_array / array / struct init）
  的基址改专用槽 `get_init_base_slot()`（惰性分配、enter_function 重置，
  与 `temp_slot_64` 同模式）。初始化表达式内不会再进入声明初始化（C 语法
  不允许表达式内声明），单槽安全。作用域化槽位分配器的根治在 U3。
- 红→绿锚（baseline，golden 由 clang 生成）：`init_base_slot_variadic.c`
  （变参 double 实参形状：修复前 NULL 区写入 trap → `1.0 2.5 3.0 4.0`）+
  `init_base_slot_struct_call.c`（外部审查原始形状 `take(mk(4))`：
  `1.0 9.0 3.0` 两侧一致）。

### Fixed (codegen C++ RAII)：U1 第三批 #4——RAII break/continue 析构作用域差一（假 Double-Free，红→绿）

- **根因**：`emit_dtors_for_scope_exit` 的 `start_frame_idx = target_depth.saturating_sub(1)`
  把调用方传入的"循环体 frame 索引"再减一（长度 vs 索引错位；函数注释描述的
  "参数层 frame 0"实际不存在——`enter_function` 即 `clear()`，索引 0 是函数
  最外层 block）。后果按循环形态分两支：
  - **while/do-while 的 break/continue**：析构起点多退一层——循环外层 scope
    的栈对象被提前析构，正常退出时再析构一次（红锚 `cpp_raii_break_while` /
    `cpp_raii_break_dowhile`：`dtor 1` 在 `after loop` 前出现、结尾再出现，
    clang++ 各只一次；持资源类即假 E3061 Double-Free，路线图抽验实锤形状）。
  - **for 的 continue**：起点恰为 for-init frame——每轮 continue 重复析构
    for-init 对象（红锚 `cpp_raii_continue_for`：`dtor 9` 出现两次，clang++
    仅 for 结束时一次）。
- **修复**：`emit_dtors_for_scope_exit` 改为直接接收帧索引（语义单源，调用方
  负责起点）；新增平行栈 `loop_break_has_init_frame`（for/range-for 为 true）
  区分语义——break 跳出整个循环语句时 for-init/临时 frame 随之销毁（多退一层），
  continue 跳回 step/cond 时 init frame 仍存活（从循环体 frame 起析构）。
  while/do-while 两者都从循环体 frame 起。`gen_return` 的 `emit_dtors_for_scope_exit(0)`
  语义不变（析构全部）。range-for 同步接入。
- 红→绿锚：`native/tests/cases/cpp/cpp_raii_{break_while,continue_for,break_dowhile}.cpp`
  ×3（golden 由 clang++ 生成；修复前 `test_vitro_e2e_cpp` 3/81 FAIL 留痕，
  修复后输出与 clang++ 逐行一致）。

### Fixed (codegen/VM JIT)：U1 第三批 #5——emit_zero_init 指令爆炸 × trace 录满注册半截 trace（合法循环程序被判错，红→绿）

- **复合缺陷（路线图抽验实锤：`for(...){int a[12];...}` × 300 值栈溢出）**，
  两半一并修复：
  - **codegen 侧**：`emit_zero_init` 的 sz>4 分支逐字节 StoreMemByte（5 指令/
    字节，`int a[12]` = 240 条）——改 `Memset` 单指令（designated-init 同文件
    已有先例；其 push 回的返回值补 `Pop` 平衡）。顺带消除该路径对
    `temp_slot0` 的占用（基址直接在值栈上消费，不再跨嵌套存活）。
  - **VM JIT 侧**：`jit_trace.rs` 录满 `MAX_TRACE_LEN=256` 时返回 `Finish`
    ——半截循环体（backward jump 未闭合）的栈效应不平衡 trace 被注册编译，
    重放值栈溢出。改 `Abort`（丢弃不注册）。
- 红→绿锚（baseline，golden 由 clang 生成）：`jit_zero_init_trace_boundary.c`
  （`int a[12]` + unrolled 赋值：修复前"值栈溢出"运行错误 → 修复后
  `total=89700` 与 clang 一致）；`jit_trace_overflow_abort.c`（**修复 2 独立
  锚**：60 个 unrolled 赋值使循环体指令数仍超 256——Memset 修复不改变该
  事实，录满必须 Abort 而非注册半截 trace，`total=107400` 两侧一致）。
- 附带影响：循环体内大零初始化数组不再膨胀指令数（教学常见形状
  `int a[10000]` 的 zero-init 从 5 万条指令降为 7 条）。

### Fixed (lexer/parser)：U1 第二批——#7 词法保真四点 + #10 回滚 anonymous_structs 缺口（红→绿）

- **#7 词法保真（前端审查 #12 + 评估 R3，四点全实测复现后修复）**：
  - 单位十六进制转义（反斜杠 x 加 1 位 hex）是合法 C——修复前恰好吃
    2 位导致被 E1001 误拒；4 位超值域形态报"未闭合"错乱诊断（clang：
    "hex escape sequence out of range"）。重构 hex 转义分支：1~2 位
    收集 + 第 3 位报"超范围"（教学子集 2 位上限）+ 错误路径消费完整
    残段杜绝级联错诊。
  - `08` 拆成 "0"+"8" 两个 token 零词法诊断（后续报错全部错位）——
    八进制循环后遇 8/9 消费残段并报"八进制常量中含非法数字"。
  - `99999999999999999999`（超 u64）静默变 0（clang 报 error）——十进制
    解析 Err 改报 E1006"超出可表示范围"（对齐既有 hex/bin 口径）；
    八进制溢出的 `unwrap_or(0)` 一并同口径化。**R3 认知修正**：2^31 与
    2^63 邻界十进制实测 wrapping 与 clang 一致（非缺陷），真实实锤形状
    是超 u64 值。
  - `.5`（前导点浮点，合法 C）落进 Dot 臂报"预期表达式"——主分发加
    `'.'+数字 → number()`（其 dot_float 分支本就支持，`--.5`/`1.5e-3`
    等形态不受影响）。
- **#10 ParseCheckpoint 回滚缺口（评估 M3 + 前端审查 #6，两处独立复现）**：
  回滚只恢复 pos + errors，不回滚 `anonymous_structs`——试探解析失败回滚
  重解析把匿名 struct 二次 push，且命名 `__anon_struct_{pos}` 同位置同名
  → "重复定义 E3002"，合法复合字面量 `(struct {int a;int b;}){7,8}.a`
  被误拒（clang 输出 7，红留痕）。修复：新增 `Rollback` 三元快照
  （pos/errors_len/**anon_len**）+ `save()/restore()`，机械替换全部
  回滚点（实测 **23 处**，crate 化后已多于路线图记的 5 处；含 8 处
  "纯位置回退"型一并纳入）；零进度保护的 `pos == checkpoint` 比较
  改 `.pos` 字段访问。红→绿：复合字面量输出 7 与 clang 一致。

### Fixed (typeck/codegen/parser)：U1 第一批 P0 静默错值收口——#12 数组形状零诊断 + #2 初始化列表静默置 0 + #9 常量折叠 panic 家族

- **#12 非法数组形状零诊断（评估 C5/T6 实锤，红→绿）**：`int a[];`（无尺寸
  无初始化器——任何索引都是未知边界越界）、`int b[-5];`（负尺寸——此前
  `Unary(Neg)` 不被 `array_dim_info` 识别，**静默变成 VLA**）、`int c[0]={1,2};`
  （显式零尺寸——init.rs 的 `dims[0] <= 0` 推断分支把它**静默改成 2 元素
  数组**）三者此前全部"编译成功"零诊断（clang 均拒绝）。修复：新增
  `check_array_dims_legality`（typeck 局部 + 全局双接线；哨兵语义：
  -1=未指定、0=显式零、负字面量原样；VLA/extern/参数退化不误伤）；
  `array_dim_info` 折叠一元负字面量；init.rs 推断收紧为仅 `-1`。
  **误伤教训**：首版 `has_init_list` 只认 InitList——`char s[]="hello"`
  （StringLiteral）被误拒，shadow 6 例 compile_gap 当场抓回，补
  StringLiteral 判定后 668 全绿。baseline `u1_array_dims_legality.c`
  固化（双侧编译失败 = match）。
- **#2 初始化列表静默置 0（评估 R1 动态实锤，红→绿）**：`int a[2]={f(),3}`
  的 a[0] 输出 **0**（f() 的 7 被吞）——codegen 局部数组 4 字节元素只对
  Identifier/StringLiteral 走 gen_expr，其余落入 flatten 值
  （非字面量返回 None）→ `unwrap_or(0)` → PushConst 0。红锚实测
  `0 3 | 0 0 0` vs clang `7 3 | 11 49 93`（五个非 Identifier 元素全静默）。
  修复：与 8 字节分支一致无条件 gen_expr（flatten 调用保留——其
  designated-initializer 诊断副作用仍在）；char 数组路径同分支自动同步
  （`{f(),'B',0}` → "AB" 与 clang 一致）。shadow 668 门禁通过零回归。
- **#9 常量折叠溢出 panic 家族（前端审查 #4，红→绿）**：求值器
  `eval_enum_const`（原路线图引用的 cond.rs 已随 crate 化迁移至
  parser/decl.rs）中取负与双移位是裸运算——`_Static_assert(1<<1000)` 在
  debug 构建 **panic**（decl.rs:845 shift overflow，本机复现留痕）、release
  UB 绕回静默错值（"构建配置决定语义"）；除/模已是 checked。修复：
  `checked_neg` / `checked_shl` / `checked_shr`（负移位与 ≥64 一律 None，
  走"非常量表达式"诊断）。红锚 debug 轮廓 panic → 修复后 debug/release
  双轮廓绿。

### Changed (tests/tools)：U0 #1 + #6 收官——vitro_better 16 → 0（J2 闭环）+ 红→绿规约成文

- **vitro_better 16 例逐例审计（J2 二择一：补头转真 golden / 移 gap 写明扩展）**：
  统一真实根因为 `NULL` / `bool` / `FILE` 标识符缺失（undeclared identifier
  是 `-Wno-implicit-function-declaration` 压不住的硬错误；只缺 printf/malloc
  头的用例被该 flag 救为 match——已实证核对口径）。处置：12 例补
  `stdlib/stdio/stddef` 头转真 golden；`keyword_compat` 移 gap（`register`
  变量取地址：C 标准禁止、Vitro 宽容接受——真实扩展差异，注释写明）；
  `file_*` 3 例（VFS 沙盒 I/O）由驱动新增 **`gap_extension` 分类**承载
  （gap 目录语义即"Vitro 扩展，非 C 标准"，不再冒充 vitro_better；启动自检
  表同步加行）。**终态 667 = 660 match + 3 known_issue + 4 gap_extension +
  0 vitro_better，门禁通过**。
- **known_issue 处置**：`spfa_default` 模板队列溢出修复（普通队列容量上界
  = 每点最多入队 n 次 → `MAXV*MAXV` + 根因注释；按 E2E_FAILURES 登记建议）
  → 转 match；`function_pointer_sizeof` / `sizeof_array_param` 用例注释补
  spec 指向（指针 4 字节模型已在 C语言子集规范 记载——bug 通道语义即
  "已记录差异"，非待修缺陷）；`bTree_default` 保持登记（模板程序 UB）。
- **SKIP 清点**：全 workspace 零 `#[ignore]`（天然达标）。**弱断言扫描**：
  contains 断言 215 处，高危"stdout 数值 contains"子类 ~150 处（该区域由
  shadow 全量字节比对兜底）——抽样升级 `cpp_lambda_test` 一处示范
  （`contains("d=3.00")` 对错值 "3.001" 漏放 → 改整行断言），全量升级登记
  为 U7 结构债。
- **红→绿规约成文（U0#6）**：AGENTS.md 新增"红→绿纪律"小节——先红留痕、
  修复提交引用用例名、护栏先证会红（J9）；以本日 6 批实践为范例。
  **至此 U0 全部八项收官（CS0 前置门禁达成）。**

### Added (tools/ci)：U0 #2/#3/#4 观测设施收尾——RSS 护栏 + 磁盘卫生门禁 + 事故留痕核查

- **RSS 护栏（U0#2）**：`serve_smoke.py` 新增第三批——远距 seek 压力形状
  （65 万逻辑步程序 × 多轮远距 seek 重放）下以 ctypes psapi 采 serve 子进程
  提交峰值（与 `scripts/internal/probeutil` 同口径，**驱动侧独立测量**），
  超预算 fail 并回显峰值。默认预算 512MB = 当前基线的宽松护栏（实测形状
  峰值 75MB；**非 J5 的 64B/步**——那要等 U2 生命周期重构后收紧，注释中
  明示分层）；`VITRO_RSS_BUDGET_MB=5` 证红（peak=75MB > 5MB → exit 1），
  "先证会红"义务闭环。防线对宿主内存零观测（两次 GB 级事故的制度性根因）
  就此补上常设监控。
- **磁盘卫生（U0#4）**：删除已死 android 交叉 target 三目录 ~2.6GB
  （aarch64-linux-android 1.6G / armv7-linux-androideabi 978M / android 7M，
  随前端切割已废弃）；CI 在 engineering health 之后新增 **target 体积预算
  门禁（10GB，超限 fail 并回显目录分布）**；策略文字制度化进 AGENTS.md
  构建命令节（wasm32 为活性出口不清理；本地 debug 累积建议 cargo clean）。
- **事故留痕（U0#3）核查结论：三项已于 2026-09-12 建档时全部完成**——
  INCIDENTS/README 模板与归档规则、第二次泄漏补录（既有档案"63.6GB 事故 +
  复发"回填两洞完整证据链）、`diag_mem.ps1` 已转正 `scripts/` 且被 git
  跟踪。路线图"剩余项"表述过时已修正；仓库根一份未跟踪的本机副本属用户
  工作区文件，不处理。

### Fixed (capi/tools)：U0#5 `as` 无防御转换收口（第一批）——负 argc 实锤 + `checked_conversions` 清零 deny

- **负 argc 修复（红→绿）**：`vitro_set_argv` 的 `Vec::with_capacity(argc as usize)`
  把负 argc 绕回 `usize::MAX` → 分配器 capacity overflow panic（被入口 guard
  吞成静默无操作）。修复：argc < 0 忽略本次调用（会话 argc/argv 不动）。
  回归锚 `capi_negative_argc_test`——观测手段为 **panic hook 计数**（guard
  吞掉的 panic 也过 hook，可精确断言"零 panic"）；红留痕：撤修复实测计数
  非 0 断言失败。U0#5 点名的负参三处至此全部闭环（`payload.get` 负 end /
  `get_payloads` 负参随 W0-2、负 argc 随本批）。
- **`checked_conversions` 14 处清零后 deny**（workspace lints）：手写值域
  钳制（`val <= u32::MAX as u64` / `next_value >= i32::MIN as i64 && ...`）
  全部改 `try_from(..).is_ok()` 表达（语义严格等价，lexer 10 处 /
  parser decl 4 处 / primary 1 处）。
- **判据实测修正（记录进路线图）**：`cast_possible_wrap` 全量命中 **246 处**
  ——"转 deny + 其余登记豁免"不可一步到位（246 条豁免是噪音淹没信号），
  改为按 U0#5 本意做**"算术→索引/容量"子类定向清理**：本批已修 capi
  `with_capacity(argc as usize)`（负参实锤）；`memory.rs:400`
  `with_capacity(array_size as usize)` 守卫在前（`array_size <= 0` 提前
  拦截，安全）；`len() as i32` 类 5 处（jit_templates / collector / engine）
  受上游有界结构约束（frame_cache 窗口 / MAX_TRACE_LEN / 循环变量表），
  现实不可能溢出——登记豁免，待 U2 有界化后该类风险面进一步收缩。

### Fixed (unified/serve)：W0-2 止血收口——seek/payload.get 参数域三处 panic 真修 + serve 主循环 panic 护栏

- **R-2026-09-01/02（seek 越程 panic）本轮真修**：`finish_replay_window` 的
  `split_off(discard)` 在 seek 目标远超已有步数时理论 discard 大于缓存长度
  （10 步程序 + `seek(50000)` → split index 48001 > len 10）。此前工作区曾
  以为"已修复"，实测 **8 个探针会话仍各 panic 一次**（stderr 日志实证）——
  修复 = `discard.min(len)` 钳位 + 缓存起点按实际推进量记账。
- **R-2026-09-03（payload.get 负 end panic）本轮真修**：`get_payloads` 的
  `((-1).min(cache_end) as usize)` 绕回 `usize::MAX` 后切片 panic——旧"修复"
  的 clamp 顺序有缺陷（`min` 对负数不封底，`as usize` 负数绕回）。
  修复 = 先钳到 `[start_step, cache_end]` 再转 usize。
- **R-2026-09-04（serve 主循环无护栏）**：`cmd_serve` 给 `serve_handle` 包
  `catch_unwind`——panic 转错误帧（"内部错误（会话已重置）"）+ 保守重建会话，
  一条畸形请求不再杀死整个会话进程。**埋雷验证（J9）**：注入 `panic!` 实测
  错误帧返回、后续请求正常服务、进程存活。
- 回归锚：`native/tests/serve_param_domain_regression.rs` 五条（远/中距越界
  seek、越界后回 seek、多次远距 seek、负参 get_payloads 单元级）。
- 验收：`interaction_probe`（Go，J9 有牙）**从红转绿**——1800 请求 0 死亡
  0 非法响应 0 不变量违反、fuzz 30/30 响应进程存活、stderr 零 panic 记录。

### Changed (capi)：W0-3 契约止血——`vitro_get_capabilities_json` 所有权对齐书面契约（ABI 1.3.0）+ 头文件补齐 20 声明 + 入口护栏全覆盖

- **所有权 P0 修复（红→绿）**：`vitro_get_capabilities_json` 曾返回 `OnceLock`
  静态指针（"无需释放"），与书面契约"全部 JSON 函数为 rust-alloc 所有权
  （`vitro_free_string` 释放）"矛盾——**下游按契约释放即 UAF**。改为
  序列化进程级缓存一次、每次调用 clone 出独立 rust-alloc 缓冲；契约测试
  `capi_string_ownership_contract_test` 先红（两次调用返回同一指针）后绿
  （不同指针 + 各自 free + 会话级 JSON 出口全周期 free 存活）。ABI
  1.2.0 → **1.3.0**（行为契约变更 = minor）。
- **头文件补齐 20 个缺失声明**（实测更正：裁定原记 19）：含 `vitro_free_string`
  与整个 `*_json` 族、`vitro_set_max_steps` / 断点 / 步进 / JIT 统计 / 隔离区
  预算等——此前只存在于注释里，下游按头文件编程即缺声明。导出 41 = 声明 41
  对账零缺失；新增**三种所有权分区总说明**（rust-alloc 必 free / 会话租借
  勿 free / 调用方缓冲）逐函数标注；clang 纯 include 编译验收通过。
- **入口护栏全覆盖**：`capi/mod.rs` 的 22 个入口统一补 `catch_unwind`
  （此前仅 first_batch 16/19 有，文档承诺"全部入口"）；`guard` 提为
  `pub(crate)` 共用。22/22 对账。
- 删除 `native/src/shared/` 三个孤儿文件（func_meta/symbol/type_utils，无 mod
  声明从未编译，实际类型已在 `vitro_runtime`）。

### Fixed (typeck)：W0-4——char 初始化器的 W3053 误报轰炸（R-2026-09-12）

- **现象**：`char c='A'` + `char s[5]={72,101,...}` + `char t[]={'x','y',0}`
  共 **9 条**"被隐式转换为 char，可能会丢失精度"轰炸完全合法代码
  （clang 零警告）。根因：字符常量在 C 语义中是 int，char 特征在
  `resolve_literal` 提升时丢失，`check_scalar_assignable` 只见 Int→Char。
- **修复（两层）**：① 初始化路径豁免——`is_char_safe_initializer`
  （字符常量 / char 值域内整常量）+ `char_narrow_suppress` 标志在
  decl.rs 四处 / init.rs 两处调用点成对置位；② `report_warning` 对
  W3053 做（行, 码）去重，列表轰炸最多 1 条。
- **豁免不过度（反向锚定）**：超值域常量（`char c=300`）、int 变量赋值
  （`char d=i`）、普通赋值语句（`c=i;`）**仍必须报警**——回归测试
  `typeck_e3053_regression_test` 四条全覆盖（修复前主用例 9 条 → 0）。
- baseline `char_init_no_false_positive.c` 固化运行时语义（clang golden）。

### Fixed (vm)：JIT trace 静默错值——fast path 在录制期间禁用（R-2026-09-13）

- **现象**：嵌套纯计数循环（教科书 JIT 目标形状）在 `vitro_cli run`（executor + JIT）
  下静默错值（`inner=20200 j=0`，正确值 `inner=40000 j=200`），零诊断；`unified`
  路径与 clang 均正确。debug/release 同输出（纯逻辑缺陷）。
- **根因**：`VitroVM::run` 的 JIT fast path 在 trace 录制期间仍然生效——外层录制
  推进到已 JIT 化的内层循环头时命中内层 trace 被 bulk 一次跑完，外层 trace
  **缺失内层指令**却被注册；此后每轮外层由该不完整 trace 执行，内层被完全跳过。
  触发三层条件：外层回边 ≥ `JIT_THRESHOLD=100` + 内层已 JIT 化 + 外层循环体无
  条件分支（有分支则录制 Abort 退回解释、结果正确）。
- **修复**：fast path 加 `!trace_recorder.is_recording()` 判断（`executor/mod.rs`）。
  行为等价于复现实验中验证正确的"录制逐条 step → 遇内层回边 Abort"路径；由此
  JIT 作用域**天然收缩为最内层循环**（任何含内层循环的 trace 录制必然 Abort）。
- **红线留痕（红→绿）**：修复前 shadow 实测 665 用例 / match 644 / output_gap 2
  （`jit_nested_counting_loop.c` + `_longlong.c`，2026-09-13 落案）；修复后
  665→666 / match 646 / 门禁通过（两条 JIT 用例转绿 + 新增单层热循环用例）。
- 归因修正记录在案：与 `long long` 无关（纯 int 版同样出错）。

### Changed (tests)：`vm_bench.rs` 方学校正——"JIT 不赚反亏"结论撤销，实测 9x+

裁定 §14.8 认定的两处方法学缺陷修复：

- **① 真禁用开关**：`jit_traces_mut().clear()` 只清表，`ip_hits` 仍累积并重新
  录制，"纯解释"轮实为混合。新增 `VitroVM::jit_enabled` 结构性开关（fast path
  不命中、热点检测与录制均不触发，`set_jit_enabled`/`jit_enabled` 访问器）。
- **② 统一入口**：两分支同走 `execute_run`（旧版 JIT 走 `execute_run`、解释走
  裸 `vm.run`，双变量无归因）。
- **③ best-of-5 计时 + fail-loud 自检**：解释分支断言零 JIT 步、JIT 分支断言
  加速步 > 0，对照前提失效即拒给数字；程序改 `return sum` 使返回码直接锚定
  计算值（旧版只断言 ret==0，**错值程序照样绿**——旧 nested "JIT 时间"实际建立
  在穿透 bug 跳过内层的错值执行上，且曾以 0.66x 的表面数据参与"不赚反亏"结论）。
- **重测结果（release，best-of-5）**：嵌套纯计数 **9.16x**、单层热循环
  **9.43x~9.7x**、递归（JIT 无效形状）0.97x（开关开销噪声级）。Phase 25
  加速比声明由"未验证"更新为实测。
- 附带发现：修复后嵌套 1k×1k 撞默认 10M 步上限——修复前内层被穿透跳过、
  步数虚低。基准显式放宽至 50M。

### Added (tests)：J10 落地——JIT 生效区间独立防线（margin=20）

裁定 §14.9/§14.11.4：JIT 路径正确性不得由"解释器正确"推断。

- **`native/tests/jit_path_parity.rs`（8 条）**：双路径差分三锚——同程序 JIT
  开/关各跑一次（parity 锚）+ 手算期望值（期望值锚，不依赖引擎自证）+ JIT
  生效性断言（J9 锚：`steps_accelerated>0` / 禁用分支恒 0，等价性断言不测空气）。
  覆盖：嵌套 200×200 穿透形状、单层算术+位运算、数组读写、long long 累加
  100k、双变量循环携带、返回码通道、短循环阈值下不触发（fib46）。
- **baseline `jit_single_hot_loop.c`**：JIT bulk 主战场（单层热循环）的 clang
  golden 覆盖；既有两条嵌套用例注释由"保持红"更新为"保持绿"（红→绿完成）。
- **弱断言升级**：`jit_unit_test.rs` 两处 `contains("200"/"400")` 对错值
  "-200"/"-400" 同样为真，改 `starts_with`（`vitro_get_output` 为展示视图无法
  整体 eq，该通道上可用最强断言）。
- **突变验证留痕（J9 先证会红）**：注入 `tpl_add` 加→减突变，实测 **cargo 侧
  11 红 + shadow 侧 9 红（3 条 JIT 专项 + 6 例热循环 LeetCode 连带），margin=20
  ≥ 3**；未生效形状（fib46/factorial）正确保持绿。还原后全防线复绿。
- 诚实记录：`bTree_default` 在 CLI 与 DLL 两入口间 match/FAIL 漂移——模板程序
  自身 UB（读未初始化 children，堆残留决定 NULL 与否），E2E_FAILURES 既有条目
  已登记"表现非确定性"，FAIL 态命中 shadow 白名单，非本轮引入的回归。

### Added (capi)：`vitro_get_compile_errors_length`（ABI 1.2.0）

- 新增编译错误 JSON 的字节长度出口（不含 NUL；无错误返回 0），与 `vitro_get_compile_errors`
  配套——驱动侧先取长度再定长读取，**根治** `ptrToGoString` 变长窗口扫描对短于
  窗口的分配构成越界读的瑕疵（PR 评审第 1 项）。按"加函数 = minor"承诺升
  `VITRO_ABI_VERSION` 1.1.0 → **1.2.0**；新增 capi 集成测试
  `test_compile_errors_length_matches_string`（干净会话 0/null、失败会话 length 与
  NUL 串字节数一致）。
- 连带修复：replay S5 A4a 的 ABI 断言由硬编码 `"1.1.0"` 改为**版本下限语义**
  （`≥ 1.1.0`，major 变更必红）——快照冻结具体串会让每次兼容性加函数都假红，
  下限语义保留检测牙齿；改后 S1-S5 回放 61/61 PASS。

### Changed (tools)：D5 收尾重构——scripts 建共享包 + 白名单外置（PR 评审第 2/3 项）

PR 评审认定的三项技术债全部落地（评审意见：ptrToGoString UB 假设 / v0.1 白名单
双份硬编码 / serve 封装 ×8 份重复）：

- **仓库根新建 `go.mod`**（`module vitro`，零第三方依赖不变），新增共享包
  `scripts/internal/{capi,pyrandom,probeutil}`：DLL 绑定 + 字符串读取 + 产物新鲜度、
  CPython random 逐比特复刻（MT19937 双 seeding 路径单源）、探针 CLI 定位 + psapi
  采样。六个 Go 驱动迁入各自子目录（`scripts/shadow_verify/main.go` 等，
  git mv 保历史），同目录 package main 符号冲突随之消除，`go vet ./scripts/...`
  达成全绿。删除跨文件重复约 **600 行**（pyRandom 整份 ×2、capi helper ×3-4、
  psapi 采样 ×3、路径探测 ×6）。
- **v0.1 字段白名单外置** `scripts/replay/v01_payload_fields.json`：Go/Python 两个
  回放驱动共读同一份，加载失败/schema 不符 fail loud（exit 2）。**有意不从引擎
  运行时拉取**：白名单是 S5 断言的"验收快照"，运行时跟随会取消漂移检测语义
  （评审建议的部分采纳理由见 AGENTS.md D5 收尾重构段）。
- **capi.Load 统一绑定全部符号**（含 `vitro_get_compile_errors_length`），
  shadow C/C++/random_diff 的编译错误读取全部改定长路径；`ptrToGoString` 剩余
  调用方（engine_version / runtime_error）为短而有界串，UB 假设已在
  `internal/capi` 头注声明（评审第 1 项的注释义务 + 根治一并落地）。
- **有意保留**：serve 会话封装 ×3（replay / interaction_probe / seek_accumulation
  各自的 stderr 捕获、退出检测、采样钩子语义有差异），留待单独一站统一；
  `gosmoke/cabi_smoke.go` 维持单文件最小冒烟形态不动。
- CI 同步：`go run ./scripts/shadow_verify` / `./scripts/shadow_verify_cpp`，
  缓存 key 增列 `hashFiles('scripts/internal/**/*.go')`。

## [Unreleased]

### Changed (D5 语言迁移最后一站：C 影子验证主驱动 shadow_verify.py Python→Go)

唯一硬门禁（防线 1 主驱动）完成迁移，**D5 六站全部收官**：

- **新增 `scripts/shadow_verify.go`**：判定口径与 Python 版逐项对齐——五目录
  sorted(glob *.c) 用例加载（`@category` ASCII 限定提取、剔除 `// @` 行、同名 `.in`
  注入 stdin）、文件用例原目录编译（`#include` 解析）、编译 30s / 运行 5s 超时、
  worker 隔离运行目录 + VFS 预设文件、结果运行目录归一化 `<rundir>`、
  `KNOWN_FAILURE_CASES` 豁免、`classify_compile_error` 关键词表、报告三件套
  （Markdown/JSON 带时间戳 + latest + `kr_leetcode_report.json`）、门禁退出码
  （非预期差异 exit 1 / Clang 预检与产物新鲜度 exit 2）。
- **双轨对账 PASS**：663 用例集合/顺序/逐用例 diff_type/expected/summary/
  category_frequency/clang_version 全维度一致（`663 / match 644 / known_issue 3 /
  vitro_better 16 / 0 非预期差异`）；`--refresh-clang` 全量重算与缓存热跑、16 路与
  32 路并发三次交叉验证逐用例 verdict 一致。CI 已切换（缓存 key 同步改
  `hashFiles(scripts/shadow_verify.go)`）；Python 主驱动（`shadow_verify.py` /
  `vitro_output.py` / `extract_shadow_cases.py`）退役删除。
- **形态（有意差异）**：两段流水线——Clang 侧并发（`--jobs N`，0=自动
  min(CPU,16)，实测 32 路仅比 16 路快 6%，瓶颈在子进程启动/IO），Vitro 侧互斥串行
  （DLL 非线程安全实证，实测串行段 ~1.5s 占比可忽略）；Clang 结果缓存为 Go 自有
  schema（`go1`，Go 结构体序列化 + sha256），与历史 Python 缓存同目录共存、key
  空间不相交；Clang 编译失败重试 3 次（第一站实证）；瞬态环境异常（超时 / 启动
  失败 / `0xC0000005` 映像崩溃）自动重试且**不落缓存**（Python 连超时异常也落缓存
  的固化风险未踩到，此处加固）；无硬编码 `SHADOW_CASES` fallback（目录加载失败
  fail loud，不留 ~300 行永不执行的死重）。
- **迁移中新挖出的三类隐性口径（对账逐用例 diff 抓出，均已锚定并记录于 Go 版头注）**：
  1. **`pathlib` 排序平台差异**——Python `sorted(glob)` 在 Windows 上按大小写规范化
     字符串比较（casefold 序），Linux 上是码点序；`bTree_default` 等大小写混排用例
     的顺序两侧不一致。Go 版统一 casefold（跨平台稳定，`--limit` 语义不随 runner 漂移）。
  2. **Go `ExitError` 与 Python 异常模型的结构性错位**——Python `subprocess.run`
     不带 check 时程序自身 exit != 0 是**正常返回**（输出保留），仅超时/启动失败抛异常；
     Go `cmd.Run()` 对两者都返回 error。首版把 exit 1 误走"丢输出"分支，被
     `e1_func_identifier`（全仓唯一 `return helper()` 即 exit 1 的用例）当场抓出。
  3. **同名 exe 并发覆盖映像竞态**——Windows 上 16 路并发快速覆盖+执行同名
     `test.exe` 确定性触发 `0xC0000005`；编译产物改 per-case 唯一命名
     （`test_<name>.exe`，C++ 版第一站早已采用）。
- **性能**：冷启动全量重算 663 用例 ~26s（Python 632 用例时代 ~20.4s，同量级；
  用例数 +5%）；缓存热跑 ~5s（Python ~1.0s，均为秒级，CI 门禁占比可忽略）；
  J9 启动自检 15 条断言（判定树全分支 + strip/CRLF 雷 + 豁免口径 + 分类器优先级）。
- CI 同步：Shadow Verification 步骤 `go run scripts/shadow_verify.go`（夜间
  `--refresh-clang` 语义不变）；AGENTS / AGENTS_EN / README / 影子验证框架 /
  模板维护指南 / 快速入门 / 构建指南 / 架构图引用同步。

### Changed (D5 语言迁移第五站：资源域长跑探针 Python→Go)

`resource_longrun.go` + `seek_accumulation.go`（U2 验收的测量通道，psapi 驱动侧采样）：

- **两个 Go 版探针**：采样/看门狗机制对齐（commit_mb 驱动侧采样、cap 超限击杀、
  seek 重放放大 3 规模 / malloc 登记表 3+4 规模 / putchar 1M / 同会话 6 次往返 seek
  的 before-after-settled 时间线）。看门狗击杀改用进程句柄 Terminate（Python 经
  taskkill 子进程），有意差异。
- **对账（测量类探针采用结构口径）**：数值（wall_s / commit_mb）是测量值，双轨不
  要求相等；对账比较结构 / case 序列 / exit 码 / seek 成功标志 / 耗时指数。实测
  PASS——malloc 耗时指数 Python 1.024 vs Go 1.018（均近线性，**独立复核确认非
  O(N²)**）；malloc 400k exit=1 撞步数上限，与裁定 §13.4 更正一致。
- seek_accumulation 实测：峰值提交 513.6MB（watchdog 未触发，cap 1200MB），
  settled 回落——瞬时窗口放大而非单调泄漏，与裁定既有结论一致。
- mutation_facet_test 评估结论：它是**突变编排器**（打补丁 → cargo build → 影子 +
  cargo test → 还原），深度耦合主驱动 shadow_verify.py——迁移与主驱动绑定做，
  不单独迁移。
- Python 版保留为双轨对照基准（头部已标注）。

### Changed (D5 语言迁移第四站：交互切面探针 Python→Go) — **⚠️ 附 P0 实证**

`scripts/core_asset_verdict/interaction_probe.go`（随机交互序列 + 恶意输入 fuzz，U0 验收的
主探测通道）：

- **⚠️ P0 紧迫性实证（非回归，是新证据）**：seed=20260912 的随机交互下，**9 个会话中
  8 个死于 `engine.rs:400` seek panic**（`split index should be <= len`），Part B 恶意输入
  `payload.get end=-1` 死于 **`engine.rs:416` panic**——裁定 W0-2 止血批次（clamp + 参数域
  防御 + serve catch_unwind）的两个 P0 在 master 上**仍然全部活着**，且 seek panic 的
  触发密度远比"已知问题"高（任意会话期望几十次交互内必死）。**建议 W0-2 立即执行**。
- 双轨对账 PASS：RNG **整数 seeding** 复刻（`Random(int)` 不走 sha512，直接 init_by_array——
  与 random_diff 的字符串 seeding 是两条路径），同 seed 下 op 序列、请求序列一致；
  统计 6 项（reqs 578 / dead 8 / badjson 0 / protocol 0 / state 0 / violations 0）、
  8 条会话死亡记录（程序名 + 死亡点 + stderr 洗 PID 后逐字一致）、正常记录、
  fuzz 响应序列（30 输入 / 9 响应 / #10 死于 end=-1）全部一致。
- 采样口径移植：psapi `GetProcessMemoryInfo` 驱动侧采样（commit/peak commit），零依赖。
- 门禁加牙（有意差异）：Python 版恒 `return 0`；本版在 会话死亡 / 非法响应 / 不变量违反 /
  fuzz 杀死进程 任一发生时 exit 1——**当前 master 上本探针 exit 1**（8+1 处 panic），
  修复 W0-2 后应转绿，转绿即是止血验收。
- Python 版保留为双轨对照基准（头部已标注）。

### Changed (D5 语言迁移第三站：随机三路差分探针 Python→Go)

裁定文档 §13.3 W3-1 探针集第一件（`random_diff`，三路差分是"核心不重写"裁定的证据通道；
库内旧产物（c3159ac）与当前脚本 + 当前 Python 3.14 的运行结果不一致——历史环境不可复现，
本次为**首个可复现基线**）：

- **新增 `scripts/core_asset_verdict/random_diff.go`**：10 族生成器 × 100 例 + 语义模型求值 +
  clang / Vitro 三路对照，判定口径对齐（`model_clang_mismatch` / `clang_vitro_mismatch` / `agree`，
  mismatch 落 `.findings/` 最小复现，报告 `random_diff.json` 字段同名）。
- **RNG 逐比特复刻**：MT19937 + CPython 字符串 seeding（sha512 → init_by_array）与
  getrandbits/_randbelow/randint/choice/random 全链路——**同 seed 生成同一用例集合**，
  双轨对账达逐用例精度。selftest 内置 CPython 3.14 实测金标（random()×3 / randint×5 /
  choice / 大范围 randint），复刻破坏即 exit 2 拒绝运行（J9）。
- **双轨对账 PASS**：1000 例用例集合一致、verdict + expected 逐用例一致、clang 动态输出
  0 例不一致。耗时 47.0s（Python 50.7s，持平——vitro 串行是共同瓶颈，探针不在 CI 热路径）。
- **⚠️ 引擎侧实证发现：DLL 非线程安全**。Vitro 调用与 clang 并发同池时进程以
  `0xc0000374`（STATUS_HEAP_CORRUPTION）崩死（2.5s 即现）——引擎存在非线程安全的内部
  状态。此前 Python 版未崩只是 6 线程下 vitro 调用碰撞率低，**不是**线程安全的证据。
  Go 版 Vitro 调用已恢复互斥串行；主驱动 `shadow_verify.py --jobs` 的并发口径存在同源
  风险，待专项评估（本条为风险记录，非回归）。
- 语义口径修正：clang 子进程 stdout 显式做 CRLF→LF 归一（对齐 Python `text=True` 的
  universal newlines；Windows CRT 文本模式会写 `\r\n`，不归一则全部假 mismatch）。
- **门禁加牙**（有意差异）：Python 版 `main` 恒 `return 0`；Go 版非 agree 即 exit 1。
- `.randomdiff/` / `.findings/` 进 gitignore；Python 版保留为双轨对照基准（头部已标注）。

### Changed (D5 语言迁移第二站：S1–S5 回放驱动 Python→Go)

裁定文档 §13.3 W3-1 第二站落地（`replay` 不在 CI，为 schema v0.1 签字材料采纳驱动）：

- **新增 `scripts/replay/replay_s1_s5.go`**：61 条断言（S1 防抖编译 A1–A10 / S2 fixtures 判分 A1–A6 /
  S3 单步-seek-内存交错 A1–A16 / S5 预留位语义 A1–A5）与 Python 版逐项对齐，serve NDJSON
  会话语义一致（id 关联、帧全量收集、shutdown 退出码门禁 S1 A10）。
- **双轨对账 PASS**：61 条断言状态与编号逐行一致，exit 0（Python 0.39s / Go 0.47s 含 go run 编译）。
  serve 会话是单进程时序协议流，不做会话内并发。
- **实测更正**：裁定 §13.1 "replay ≥3 分钟未完成（已中止）" 已失效——W0-2 止血（`engine.rs`
  panic 修复）后 Python 版实测 **0.39s 全绿**；W1-1 的 "replay 并发化" 目标自然达成，
  已记入裁定 §13.7。
- **J9 埋雷补强**：Go 版新增 `--selftest`（9 条注入断言：Report 透传、diagErrors 过滤、
  锚点正则命中/拒绝、未知键/预留字段/哨兵值必被识别），不过即 exit 2 拒绝运行——
  Python 版无此自检。
- 前置门禁同口径：`capabilities.engine_version` 必须含当前 HEAD（exit 2 fail fast）；
  `--anchor` 缺省从版本串自取，显式传入必须命中。A4b 的 `vitro_engine_version` 读取走
  规范指针 + `vitro_free_string` 契约（Python 版 `c_char_p` 副本无法释放，属已记录差异）。
- Python 版 `replay_s1_s5.py` 保留为**双轨对照基准**（头部已标注）。

### Changed (D5 语言迁移第一站：C++ Shadow 驱动 Python→Go)

裁定文档 [`VITRO_CORE_ASSET_RECONSTRUCTION_VERDICT.md`](docs/current/VITRO_CORE_ASSET_RECONSTRUCTION_VERDICT.md) §13.3 W3-1 的第一站落地：

- **新增 `scripts/shadow_verify_cpp.go`**，接管 CI（`ci.yml` 改为 `go run scripts/shadow_verify_cpp.go`）。判定口径与 Python 版逐项对齐：用例来源（内嵌 + 目录、同名目录胜出）、`// category:` 解析、clang 失败重试 3 次、编译 30s / 运行 5s 超时、`.strip()` + CRLF 归一比对、`category=gap` 预期差异豁免、非预期差异 exit 1、报告 JSON 同路径同字段。
- **性能**：Clang 侧并发 16 路（§13.1 实测 6.0x 依据），全量 **24.75s → 5.2s**（CI 门禁占比 50% → ~12%）。Vitro DLL 调用保持串行——引擎会话级线程安全性未验证，试点不做此假设（clang 子进程并发才是耗时大头）。
- **迁移纪律执行**：双轨同跑对账 **PASS**——94 用例集合一致、逐用例 `diff_type` 一致、Vitro stdout 内容级一致（Go：92 match + 2 已知 `clang_compile_fail` / 0 非预期；Python：同）。Python 版 `shadow_verify_cpp.py` 保留为**双轨对照基准**（Go 版判定异常时用于归因复现），日常运行与 CI 均走 Go 版。
- **纪律移植**：① 启动自检 fail loud（J9）——7 条 compare 口径断言含 3 条语义雷（尾部空白 / CRLF / 单侧运行失败），不过即 exit 2 拒绝运行；② E-P1-5 结构化输出通道同口径（缺符号 fail fast，不退回文本清洗）；③ 产物新鲜度门禁（`vitro_engine_version()` 须含 HEAD 短哈希）；④ UTF-8 原生处理，消除 Python 侧编码样板。
- **vet 豁免裁定沿用**：`go vet -unsafeptr=false`——DLL `Call` 返回值转 `unsafe.Pointer` 是 Win32 互操作必然形态（与 `scripts/gosmoke/cabi_smoke.go` 同裁定），uintptr→Pointer 转换集中在 `ptrToGoString` 一处。
- 已知差异（有意，记录在案）：clang 编译错误文本从 stdout+stderr 混流改为仅 stderr（对齐 Python `capture_output` 语义）；超时路径的错误文本措辞不同（判定不受影响，超时均归入对应 gap）。

### Fixed (产物新鲜度：影子验证/回放在陈旧二进制上假绿)

提交后复测时发现并修掉的一个**方法论级缺陷**（比功能 bug 更危险，因为它制造假绿）：

- **症状**：`git commit` 不改变任何包内文件，`native/build.rs` 原先依赖"包内文件变更即
  重跑"的默认启发，于是版本串停留在上一次**改源码**的时刻——实测 HEAD 已是 `622a859`
  而 release dll 仍报 `0.1.0 (94c16d2)`（更早还观察到 `10591ad`）。此时回放/影子验证读的
  都是 `native/target/release/` 里的**陈旧产物**，却会全绿；S5 A4b 的"版本锚定"只校验
  "版本串含调用方传入的锚点"，传旧锚点 + 旧产物照样通过，防线形同虚设。
- **修复 1（根因）**：`native/build.rs` 显式声明 `rerun-if-changed`（`src` / `Cargo.toml` +
  `.git/HEAD` + 其指向的 ref + `packed-refs`）——提交/切分支也会刷新哈希。
  注意声明 rerun-if-changed 会关闭默认启发，故包内路径必须一并列出。
- **修复 2（防线）**：`ensure_abi()`（C/C++ 影子驱动共用）除 ABI 符号外，比对
  `vitro_engine_version()` 与 `git rev-parse --short HEAD`；`scripts/replay/replay_s1_s5.py`
  前置门禁改为 **fail fast（exit 2）**，且 `--anchor` 缺省从 `capabilities.engine_version`
  自动取（默认值再也无法过期；显式传入则必须命中版本串）。
- **配套**：`session_api::capabilities()` 新增 `engine_version`（additive）——消费方据此
  自检"手上的产物是不是当前提交构建的"；`capi::engine_version_string()` 成为 C 出口与
  该字段的单源。实测门禁：`--anchor deadbeef` → exit 2 并给出可操作提示。

### Added (下游需求清单第二批：B2 / C1 / C2 / D2 / D3)

响应对端 SharpTutor《Vitro后端-C#扩展期需求清单》（锚定 `10591ad`）的非阻塞项。
逐项回执见 [`docs/current/VITRO_DOWNSTREAM_REQUESTS_RESPONSE.md`](docs/current/VITRO_DOWNSTREAM_REQUESTS_RESPONSE.md)。

- **B2 schema v0.2 激活轨道**（把"字段只增不改"从文档承诺变成机器防线）：
  - **v0.1 正式冻结**（2026-09-12）：schema 状态由"定稿候选"改为"**v0.1 已冻结**"，
    依据 S1–S5 签字回放 61/61 PASS；
  - 新增 `native/src/unified/contracts.rs`：`RESERVED_FIELDS_V0_2`（四预留位字段名冻结）、
    `V0_2_ACTIVATION_CHECKLIST`（五条激活清单）、`V0_2_FIELD_LEDGER`（v0.2 字段台账：
    四预留位 + `code_file` + `call_stack[].return_line` + `func_display_name / func_mangled_name`）、
    `BEHAVIOR_CONTRACTS`（行为契约表）；
  - **激活 tripwire**：`test_v0_1_reserved_fields_absent` 递归扫描 payload 全量键集合，
    发现任一预留位字段即失败并打印激活清单——"悄悄激活 v0.2 字段"在结构上不可能；
  - **`UNWINDING 不得合并单步`可执行判据**：`contracts::check_unwinding_granularity`
    （相邻展开步 `unwind_frames_left` 下降 ≤ 1；`finally` 步可持平；回增/未归零为违规），
    CS3b 回放驱动将复用同一函数；
  - schema 新增 **§9 v0.2 激活轨道**（清单 + 台账 + 行为契约）与**附录 B `semantic_label`
    受控词汇表**；§8 #1/#2/#9 的计划列指向台账。
- **B2 `semantic_label` 受控词汇表单源**：新增 `native/src/unified/vocabulary.rs`
  （C 域 10 条 active + 异常域 4 条 reserved，取自 SharpTutor S4 §6），`classify()` 为
  "产出 label → 词汇条目"的唯一映射；出口 serve `semantic_labels`。
  防线 `test_semantic_label_vocabulary_closed` 断言引擎产出的每个非空 label 都能归类
  （新增标签不登记词汇表即失败）。
- **C2 `memory.regions` 三段式内存地图**：`regions` 统一为带 `kind`
  （`global` / `stack` / `heap`）的数组并按地址升序，栈/全局区域补 `name` / `alloc_line`
  （栈帧 = 进入该帧的调用行、全局 = 声明行）+ `alloc_by`（`call` / `static`），
  响应新增 `region_counts`。栈/全局区域**只在导出层合成**，不写回内部堆清单
  （堆统计口径零影响，有独立测试护栏）。C2 的 `kind` 字段同时落到
  `MemoryRegionData`（`serde(default = "heap"`，向后兼容）。
- **D3 `pointer_snapshots[].target_name` 跨帧解析**：新增
  `VitroVM::find_variable_name_at_addr`（当前帧 → 全局 → 其余活跃帧；命中判据为变量起始地址
  或数组元素区间），collector 在当帧未命中时回退到它。实测 S3 的 swap 载体：
  `a → x`、`b → y`（此前恒为空串，S3 §6 观测 #2）。schema §2.5 据此写明"空串语义收窄"。
- **D2 serve 会话拓扑显式化**：`session.create/reset/destroy` 响应携带 `session` 字段
  （`model: single-active-session` / `active_sessions` / `concurrent_sessions:false` /
  各操作语义 / 并发建议），把"单 serve 进程 = 单活跃会话"从文档约定变成可直读字段。
- 出口新增：serve `semantic_labels` / `contracts` 方法；
  `capabilities` 增 `schema`（版本轨道）与 `behavior_contracts`（additive）。
- 新增测试：`native/tests/memory_map_segments_test.rs`（三段式 + 跨帧解析 + 堆统计护栏 3 例）、
  `step_payload_schema_v0_1_test` 增 5 例（预留位缺省 / 字段名冻结 / 词汇闭合 / 展开粒度 /
  文档↔代码单源校验）。

### Fixed (下游需求清单第二批：语义标签判定顺序)

- **`semantic_label` 三条词汇在真实程序里不可达**（B2-3 词汇闭合防线首日抓到）：
  `infer_semantic_label` 把"循环上下文"判定（`loop_depth >= 1`）排在具体语句模式之前，
  而循环变量在循环结束后仍在作用域内，于是循环之后的 `printf(...)` / `free(p);` /
  `return 0;` 全部被标成 `循环 i=3` —— `释放内存` / `调用 printf` / `返回` 三条词汇
  形同虚设。现改为**具体语句模式优先，循环上下文降为行号兜底前的最后一档**：
  循环体内无特征语句仍保留"循环 i=k"标注（教学价值最高的用法不变），
  循环之后的具体语句恢复正确标签。`cargo test --workspace` 全绿，S1–S5 回放 61/61。

### Fixed (下游需求清单第一批：A1 / A2 / B1 / D1)

响应对端 SharpTutor《Vitro后端-C#扩展期需求清单》（锚定 `10591ad`，逐项实测后修复）：

- **A1 输入耗尽 EOF 语义**：`scanf` 族在输入流耗尽时此前**无条件**挂起
  `waiting_input`，导致 `while (scanf("%d", &n) != EOF)` 这类 C 第一课习语在有限输入下
  永久挂起。现：`InputMode::Batch`（`batch_input:true` / CLI `run` 路径）下返回 `EOF(-1)`，
  程序正常 `finished`；默认 `Interactive` 保持"等待学生键入"挂起语义不变
  （`crates/vitro_vm/src/host/io.rs`，与既有 `getchar` 的 Batch 分支同口径）。
  CLI `cmd_run` 作为 headless 批处理路径固定走 Batch。
- **A2 增量输入喂入**：serve 新增 `input.feed { text }` 方法（语义单源
  `session_api::input_feed`），`run` 返回 `waiting_input` 后追加 stdin 并续跑，
  状态机 `waiting_input → input.feed → running → waiting_input | finished | trap`。
  修复过程中同时发现并修正 **capi `vitro_provide_input_line` 的既有缺陷**：此前在
  `vitro_run` 前清 `waiting_input`，使 `execute_run` 误判为新一次运行而从 `main`
  重跑（首个 `scanf` 读到新喂入文本、已产生输出重复打印）。
- **B1 error_catalog 机器可读导出**：新增 `error_catalog::export_json()`（含
  `code/code_str/lang/category/emoji/title/explanation/common_causes`，按 code 升序稳定可差分）；
  出口 `vitro_get_error_catalog_json`（capi，rust-alloc）与 serve `error_catalog` 方法。
  **码段澄清**：E4xxx 已被 C++ 占用（`error_codes.rs` 定义 `E4001~E4031`），
  `lang_of_code` 按码段推断语言（1-3xxx=C / 4xxx=C++ / 5xxx=C#）。
- **D1 成员函数类型重载**：此前同参数个数、仅类型不同的成员函数重载
  （`show(int)` / `show(double)`）mangled 名只带 arity → 撞名 → 定义处后写覆盖、
  调用点静默错派发 → 运行时"栈下溢"trap。现 mangled 名带**参数类型编码**
  （`method_mangled_name` 单源，定义处 `check_class_methods` / `load_class` 与调用处
  `resolve_method_overload` 共用），并新增"无匹配重载 → E4026 编译诊断"（
  `expr/mod.rs`，此前返回 `None` 静默放行）。实测 `show(21)`/`show(3.5)` 正确派发。
- **A1 遗留分支：EOF 粘滞语义**（补第一批 A1 的缺口）。首修只覆盖"判定 EOF 的
  那一次调用"——判定后**未推进游标**、也**无粘滞标志**，于是 `scanf` 触发的 EOF
  对 `getchar` 不可见：实测输入 `7\n`，Clang 给 `r1=1 r2=-1 c=-1`，Vitro 给 `c=10`
  （把 scanf 未消费的 `'\n'` 当普通字符读出）。现 `RuntimeState::stdin_eof` 为粘滞位
  （对齐 C11 7.21.5.1 `feof`）：判定 EOF 时置位并**把游标推到底**；`scanf`（含
  `%d/%u/%f/%c/%s` 各转换符的"跳白后耗尽"分支，经显式 `exhausted` 标志与"字面量/
  格式不匹配"区分）与 `getchar` 统一查询；`set_stdin` / `push_stdin_text` 重新喂入
  时清位。新增回归 `baseline/scanf_eof_loop.c` / `scanf_eof_after_exhaust.c`
  （Golden 由 Clang 22.1.4 生成）。附带修正测试侧两处缺陷：
  - Shadow 加载器的 `@category:\s*(\S+)` 会跨越中文标点吞掉整段 C 注释，污染
    用例名（实测读到 "`，走"）→ 限定为 `[A-Za-z0-9_\-]+`；
  - E2E `test_vitro_e2e_baseline` 对全部用例硬编码 `InputMode::Interactive`，
    导致"故意读到流末"的用例以 `run_ret=2` 假失败 → 带 `.in` 的用例改走 Batch
    （"预设完整输入"的语义，与 Shadow 防线口径统一）。

验证：`cargo test --workspace` 全绿（0 失败）；`cargo clippy --workspace --all-targets
--all-features` 零警告；`shadow_verify.py` 662 用例（含新增 2 例）无 compile_gap /
runtime_gap / output_gap；`shadow_verify_cpp.py` MATCH（2 例存量 `CLANG_COMPILE_FAIL`
为 `vitro_list`/`vitro_vec` 已记录问题，与本次无关）。

### Added (重构批次 E3：C23 语义级——nullptr / static_assert 真求值 / constexpr / 属性 / unreachable)

执行 [`docs/current/VITRO_RESTRUCTURE_PLAN.md`](docs/current/VITRO_RESTRUCTURE_PLAN.md) 的 E3 批次
（口径与差异见 `C_SUBSET_SPEC.md` §2.12）：

- **`nullptr`**：关键字入表，与 `NULL` 同路径（`void*` 空）；无独立 `nullptr_t`
  类型（教学子集差异，spec 记录）。Clang gnu17 默认模式拒绝，不出 golden（同
  数字分隔符口径，单测覆盖）。
- **`static_assert` / `_Static_assert` 真求值**：此前仅消费语法（`_Static_assert
  (1==2, ...)` 静默通过，与 Clang 相反）；现经编译期常量求值（复用 enum 初始化器
  求值器并扩展 `sizeof(内建类型)`），为假 → E1020 编译错误（携带消息）。双拼写、
  双参/单参（C23）、顶层与块作用域均支持。
- **`constexpr` 对象**：按 `const` 语义处理（教学子集边界入 spec：无常量传播）。
- **`[[属性]]`**：顶层/语句前缀位置解析并忽略（无属性语义）。
- **`unreachable()`**：`<stddef.h>` 声明 + Host Func；执行到即教学 trap（确定性
  诊断），死代码调用不影响输出。
- **回归与验证**：4 个新 baseline 用例（含 static_assert 失败的"双侧编译失败=
  match"形态与 unreachable 死代码形态）+ 5 个管线单测；`cargo test --workspace
  --all-features` **875/0**；clippy 零警告；C Shadow **660 用例 0 非预期差异**。

### Changed (重构批次 R4：债务与防线收口——G1/G2/G10/G11/G12/G13 + D14/D16)

执行 [`docs/current/VITRO_RESTRUCTURE_PLAN.md`](docs/current/VITRO_RESTRUCTURE_PLAN.md) 的 R4 批次，
重构计划全批次（R1→E1→R2→E2→R3→E3→R4）至此交付：

- **D14 unwrap 收敛**：`vitro_typeck/src/decl.rs` 3 处 `unwrap()` 消除
  （`take().unwrap()` ×2 → let-else（外层 if-let 守卫语义不变）；默认参数
  `clone().unwrap()` → 跳过 None）。生产代码 unwrap 回到 0。
- **D16 decl.rs 拆分**：typeof/auto 类型解析家族（`type_has_auto` /
  `type_has_typeof` / `strip_top_level_qualifiers` / `resolve_typeof_in_type` /
  `replace_auto_in_type`）移入新模块 `decl_types.rs`（104 行），decl.rs 非空行
  905 → 792，回到 <800 规约。
- **G1 生成器恢复**：`scripts/sync_templates.py` 自前端切割前提交恢复，并去除
  Flutter assets/Index 输出步骤（前端已切割）——模板 → 用例链路重新可用。
- **G2 wasm 冒烟进 CI**：新增 `scripts/wasm_smoke/wasm_smoke.js`（ABI 导出 +
  `__heap_base` 传参 + capi 全链路 + 纯 stdout 通道断言；wasm-bindgen 占位导入
  以 Proxy 桩通过——冒烟路径不触达回调）；ci.yml 新增 wasm32 构建 + 冒烟步骤。
- **G11 engineering_health 进 CI**：ci.yml 新增看板生成 + artifact 上传（阈值
  门禁待基线固化后启用）；FRB 时代注释口径更新。
- **G10 C++ E2E 计数对账**：`CPP_FAILURES.md` 74 → 78（与 `cases/cpp/` 实际
  用例数一致）。
- **G12 模板失败口径统一**：实测 `infixEvaluation_default` 已通过（陈旧失败
  条目标注修复）；AGENTS.md 模板口径 82/78 绿/4 失败 → **82 个，80 绿，
  2 已知失败**（`bTree_default`/`spfa_default`，与 `KNOWN_TEMPLATE_FAILURES` /
  `KNOWN_FAILURE_CASES` 常量一致）。
- **G13 C++ 活约束入 spec**：`CPP_SUBSET_SPEC.md` 补记"同一模板类不可跨文件
  重复定义"与"`T()` 值初始化不支持"。
- **回归与验证**：`cargo test --workspace --all-features` 875/0；clippy 零警告；
  C Shadow 660 用例 0 非预期差异；serve 冒烟过；wasm 冒烟本地全通。

### Fixed (schema v0.1 签字回放 S1–S5：61/61 PASS——五个引擎缺陷修复)

采纳 SharpTutor 签字材料（`docs/vitro-replay/` 五文档，锚定 `7dbeaef`），新增
回放驱动 `scripts/replay/replay_s1_s5.py`（断言编号与对端文档一一对应），
**61/61 断言 PASS**。回放暴露并修复五个引擎缺陷：

- **越窗 seek 负下标无限分配（严重）**：`push_or_replace_in_replay` 的
  `step - start_step` 为负时 `as usize` 成天文数字，占位填充循环无限 push
  （实测吃满 63.6GB 物理内存 + 33.9GB 页面文件峰值）。修复：越窗重放前窗口
  重置到检查点步 + `usize::try_from` 防御。
- **step 0 锚点检查点被裁剪**：50 上限滚动删除最旧检查点，时间旅行起点丢失，
  越窗 seek 永久失败。修复：锚点（step 0）永不裁剪。
- **重放区间排他**：`checkpoint..target` 把目标步本身留在窗口外，恢复后
  frame_cache_index 落空。修复：`..=target`。
- **断点暂停双层**：断点命中同时置位 VM `paused` 与统一引擎 `is_paused`，
  清断点只恢复 VM 层。修复：`set_breakpoints(空)` 同时 resume 两层
  （serve 出口明示的恢复手段）。
- **进入被调函数第一步误标"递归调用 X"**（schema §8 #10 实锤项）：入口步行号
  归因于调用点行，旧启发把 `swap(&x, &y);` 判成递归。修复：
  `infer_semantic_label` 增加 `at_callee_entry` 判定（caller_line == code_line）。

**语义演进**：seek 在锚点固化后更新——step 0 检查点恒存在，任何 >=0 的 seek
都可成功（已同步下游 S3 §6 观测 #5）。构建期新增 `build.rs` 注入
`VITRO_GIT_HASH`（`vitro_engine_version()` 含锚定 commit，S5 A4 / 回放纪律 #2
的版本锚定依赖）。

### Changed (重构批次 R3：语义单源审计)

执行 [`docs/current/VITRO_RESTRUCTURE_PLAN.md`](docs/current/VITRO_RESTRUCTURE_PLAN.md) 的 R3 批次。
审计清单归档于 [`docs/current/R3_MULTI_TRUTH_AUDIT.md`](docs/current/R3_MULTI_TRUTH_AUDIT.md)
（A 本批收口 3 项 / B 历史批次复核确认 5 项 / C 有意保留 3 项含 CS0/CS5/R4 归属 / D 扫描方法）：

- **教学语义标注单源化（核心）**：删除 `unified/engine.rs::quick_semantic_label`
  第二套简化启发（"循环边界"/"交换" vs StepPayload 的"循环"/"交换 arr[i]↔arr[i+1]"
  词汇不一致）；`collector.rs::infer_semantic_label` 升级为**全库唯一分类器**
  （`local_vars: Option` 双形态——StepPayload 全量形态 / 检查点保存降级形态），
  检查点判定与教学标注出自同一函数，标注矛盾类缺陷结构性消除（P0-3 同类事故
  不再可能复发）。
- **堆耗尽教学消息常量化**：`report_heap_exhausted` 文本硬编码 "1MB/256KB"
  改为自 `MEM_SIZE`/`DEFAULT_QUARANTINE_BUDGET` 格式化（改常量不再漏改文案）。
- **`session.reset` 语义单源**：配置保留式重置自 vitro_cli 迁至
  `session_api::reset_session_preserving_config`（出口薄包装纪律）。

### Added (重构批次 E2：模块化预处理器 + 预定义宏族 + capabilities 出口)

执行 [`docs/current/VITRO_RESTRUCTURE_PLAN.md`](docs/current/VITRO_RESTRUCTURE_PLAN.md) 的 E2 批次
（§3 设计定案全项落地；口径与诚实放弃清单见 `C_SUBSET_SPEC.md` §2.11）：

- **`vitro_lexer/preprocessor/` 子模块化**（皮肤与内核分离）：
  `resolver`（include-once + 依赖环静态检测 + quote-include 候选链 + 存根加载）、
  `macro_table`（宏表单源 + 遮蔽诊断 W1018 + 预定义宏族）、
  `expander`（token 树转录展开 + 深度 64/产出 262144 双保险丝 + 展开链教学追踪 +
  自引用停止展开栈查重 + 宏参数副作用检测 W1019）、
  `cond`（`#if`/`#elif` 整数常量表达式求值，`&&`/`||` 短路、短路分支除零不触发、
  `defined()` 宏展开前提取、分支选择原因记录）、
  `splice`（`#` 字符串化 / `##` 拼接——操作数不预先展开、结果必须为单个合法 token）、
  `directives`（指令消费骨架，保留行号补偿机制）。
- **修复三个暴露的预存缺陷**：① 同宏嵌套 `MAX(MAX(1,5),3)` 失败（实参未先展开
  又被自身名涂蓝；现按 C99 §6.10.3.1 实参先行展开，`#`/`##` 体例外用原始实参）；
  ② include 拼接点在 include 行尾之前，行尾消费循环会吃掉内容首行（存量头文件
  首行均为注释而未暴露；改为整行消费后再拼接）；③ 嵌套自定义头文件的相对路径
  按源码目录解析（改为"包含者目录优先"候选链 + `#__vitro_push_dir/pop_dir` 哨兵
  精确维护目录栈）。
- **新增指令/能力**：`#if`/`#elif`（含短路算术表达式求值 E1014）、`#undef`、
  `__has_include`、include-once、环检测 E1015、拼接非法结果 E1016、双展开保险丝
  E1017、遮蔽警告 W1018、副作用警告 W1019；预定义宏族 `__STDC_VERSION__=202311L`
  （名义锚点）与 `__VITRO_SUBSET__`。
- **capabilities 出口**（"版本宏当能力探测"三层配套之一）：capi
  `vitro_get_capabilities_json()` + serve `capabilities` 方法，机器可读真实能力
  （语言锚点/预定义宏/预处理能力/内存模型常量，后者自 `vitro_runtime` 单源引用）。
- **教学追踪出口**：宏展开链 + `#if` 分支选择原因随 `compile.preprocessor_trace`
  导出（serve compile 响应含该字段，容量封顶 64 条）。
- **回归与验证**：9 个新 baseline 用例（含环用例的"双侧编译失败=match"形态）+
  14 个词法单元测试；`cargo test --workspace --all-features` **870/0**；clippy 零
  警告；C Shadow **657 用例 0 非预期差异**（648+9）；serve 冒烟扩展 capabilities
  断言后全过。

### Changed (重构批次 R2：会话收口——flutter_bridge 整删，出口单轨化)

执行 [`docs/current/VITRO_RESTRUCTURE_PLAN.md`](docs/current/VITRO_RESTRUCTURE_PLAN.md) 的 R2 批次：

- **vitro_cli 全部子命令迁 `Session` + `session_api`**：compile/run/step 三条路径
  改为本地 `Session` 直驱（unified/export/serve 原已如此）；serve 与 CLI 现共用
  同一套语言中立入口，三出口薄包装纪律闭环。
- **`flutter_bridge.rs` 整删（-836 行）**：全局会话单例（`SESSIONS` u64 map +
  `CURRENT_SESSION_ID`/`UNIFIED_ENGINES` static + `POISON_COUNT`）全部退役——
  MAINTENANCE_PLAN D12 的问题域（全局 Mutex poison）**结构性消除**：现行出口
  （capi/serve/CLI）均为 `&mut Session` 独占访问，进程内无共享锁。
  ROADMAP G6 销项；孤儿类型 `CompileResult`/`RunResult` 随消费者一并移除。
- **`session_api` 新增两个语言中立入口**（自 flutter_bridge 语义收口，出口复用）：
  `vm_step`（普通 VM 单步；首调初始化步进环境推进到首个 step 事件的语义原样保留）
  与 `variables`（栈帧局部变量快照）。
- **`benches/vm_benchmark.rs` 改造**：基准对象不变（编译管线 + 统一模式环境
  初始化），从全局单例改为本地 Session。
- **CLI 行为不变（冒烟对照验证）**：compile（退出码契约：失败非零）/run（输出、
  trap、stdin `-i`、argv `--` 传参、等待输入提示）/step（p/o/r 命令、首步事件
  暂停语义）/unified/export/serve 全部逐项对照通过。
- **回归与验证**：`cargo test --workspace --all-features` 856/0；clippy 零警告；
  C Shadow 648 用例 0 非预期差异；serve 冒烟通过。

### Added (重构批次 E1：C23 lexer/typeck 级 + B 档快赢)

执行 [`docs/current/VITRO_RESTRUCTURE_PLAN.md`](docs/current/VITRO_RESTRUCTURE_PLAN.md) 的 E1 批次。
C23 锚定决议下的第一批语言能力（详细口径与差异见 `C_SUBSET_SPEC.md` §2.10）：

- **C23 特性**：`0b` 二进制字面量、`'` 数字分隔符、`u8"..."` 前缀字符串（教学子集差异：
  无独立 char8_t，按 char[] 处理）、`_Alignof`/`alignof`、`typeof_unqual`（三种拼写，
  推导并剥离顶层限定符）、`enum E : T` 底层类型声明（`sizeof(enum E) == sizeof(T)`，
  成员常量支持 64 位）。
- **B 档快赢**：相邻字符串字面量拼接（C89）；`long long` 位运算全链路
  （E3048 半成品缺陷——typeck 误拒而算术族已有 Q 系列；新增 7 个 64 位位运算
  opcode BitAndQ/BitOrQ/BitXorQ/BitNotQ/ShlQ/ShrQ/LShrQ）；`limits.h` 全宏
  （`ULLONG_MAX` 等 (i64::MAX, u64::MAX] 值域按 64 位位模式承载为 unsigned long long）；
  科学计数法浮点字面量（C89 基础能力，`float.h` 的病根）；`<float.h>` 宏可用；
  `va_copy`；`__func__` 预定义标识符。
- **浮点字面量语义修正（行为变化，诚实记录）**：无后缀浮点字面量为 **double**
  （C 标准），带 `f`/`F` 后缀为 float。此前一律建模 float，`2.2e-308` 经 f32 位模式
  存储下溢为 0（DBL_MIN 打印 0），且 typeck `resolve_float_literal` 无条件返回 float
  与 codegen `PushConstD` 位宽错位（二元浮点运算结果损坏，kr_1_3 温度转换家族
  全部 output_gap）。
- **浮点比较语义更替（行为变化，诚实记录）**：double/float 比较从 1e-6 epsilon
  容差改为 **IEEE 754 精确语义**——原容差使 `0.1 + 0.2 == 0.3` 判真，与 C 标准和
  Clang golden 矛盾（实测 clang 输出 0）。IEEE 754 运算确定性，容差无存在依据。
  6 个固化旧语义的 `*_epsilon_*` 单元测试同步更替为精确语义断言（`*_exact_*`），
  非粉饰：语义变更有 C 标准与 Clang 双重依据。
- **暴露的预存差异（如实记录进 spec §2.10）**：struct/union 布局为 packed
  （sizeof 与 Clang 不一致，alignof 口径与自身布局内部不一致）；VM 指针 4 字节
  vs Win64 宿主 8 字节。均为预存结构特性，本批通过 alignof 用例暴露后建档。
- **回归与验证**：新增 12 个 baseline E2E 用例（`e1_*.c`，Clang golden 全 match）+
  5 个词法单元测试；探针 13 项全 PASS；`cargo test --workspace --all-features`
  **856 passed / 0 failed**；clippy 零警告；C Shadow **648 用例 0 非预期差异**
  （636 存量 + 12 新增，kr_1_3 家族等 11 例由浮点修复转绿）；C++ Shadow 0 非预期
  差异；serve 冒烟通过。数字分隔符为 C23-only 语法（Clang gnu17 无法出 golden），
  由词法单元测试覆盖不进 baseline。

### Changed (重构批次 R1：内存边界收口——动态堆起点 + 全局区判据单源)

执行 [`docs/current/VITRO_RESTRUCTURE_PLAN.md`](docs/current/VITRO_RESTRUCTURE_PLAN.md) 的 R1 批次
（手术清单五项全部落地，基线锚点标签 `pre-restructure`，全程防线在线）：

- **堆起点动态化（R1 ①）**：`heap_base = max(HEAP_START, align4(global_data_end))`——堆区不再写死
  从 `HEAP_START`（20 KB）开始，而是越过本程序的全局数据末端（codegen 导出
  `CompileOutput.global_data_end`，含 Bytecode Libc 预留段）。栈碰撞检查（`control.rs` 读动态
  `heap_offset`）自动跟随；时间旅行快照新增 `heap_base` 字段随检查点往返。
  "大全局 + malloc" 的静默压坏在结构上不再可能（见下文 Fixed 的已知限制销项）。
- **判据单源化（R1 ②）**：`gen_string_literal` 的 `MEM_SIZE / 16` 魔数与 VM `setup_argv` 的
  `HEAP_START` 判据统一为 `vitro_runtime::GLOBAL_REGION_LIMIT`（`0x10000` = 64 KB，取值不变、
  不收紧存量行为）；全局区全部 7 个 bump 站点（全局变量 / extern 占位 / vtable / 字符串字面量 /
  全局初始化字符串 / 静态局部变量 / 静态数组字符串元素）收敛到 codegen `bump_global_offset`
  单一入口，越过上限编译期报错。**行为变化（诚实记录）**：旧引擎"全局数据 > 60 KB 且无字符串、
  无 malloc"可静默放行（本就处于损坏风险区），现编译失败（fail loud）；`vitro_vm/core/state.rs`
  与 `vitro_runtime` 的同值双写常量改为 `pub use` 再导出（真相单源）。
- **argv 编址修复（R1 ③）**：`setup_argv` 旧实现以 `global_count`（恒 0）编址，argv 指针数组
  落在 `GLOBAL_START`，与全局数据重叠（预存 bug）；现改自 `GLOBAL_REGION_LIMIT` 向下分配
  （占用由 `argv_region_footprint` 统一计算），与全局数据冲突时明确 trap。带 argv 的程序
  堆起点相应上移至 64 KB（argv 程序为教学少数场景，堆损失可接受，已在代码注释说明）。
- **heap_base 统计字段（R1 ④）**：`MemoryState` 新增 `heap_base`；`build_heap_stats` /
  `fragmentation_rate` 改以动态 `heap_base` 为基准；`flutter_bridge::get_heap_stats` 的内联复算
  改走 `build_heap_stats` 单源；serve `memory_regions` 视图新增 `heap_base` 字段（additive）。
- **大全局编译 warning（R1 ⑤）**：全局数据越过 `HEAP_START` 时产生 severity=1 诊断，提示
  堆起点将上移与剩余堆空间（信息性——静默损坏已结构性消除）。
- **回归与验证**：新增 `native/tests/r1_memory_boundary_test.rs` 7 项（大全局+malloc 数据完好 /
  malloc 耗尽明确返回 NULL / 深递归明确 trap / argv 不与全局数据重叠 / 超上限编译失败 /
  大全局 warning / 布局函数单元测试）；`cargo test --workspace --all-features` **852 passed / 0 failed**；
  clippy `--all-targets -D warnings` 零警告；C Shadow 636 用例与 C++ Shadow 100 用例
  **均 0 非预期差异**（`lc_22` / `lc_977` 等"全局区越过 20 KB 不用堆"存量用例行为不变）；
  `lc_22`/`lc_977` 回归由 Shadow 防线覆盖通过。

### Fixed (CI 门禁失效 + Bytecode Libc 产物漂移 / 不可重现 / 全局区越界)

起因：CI 在 `python scripts/precompile_bytecode_libc.py --check` 步骤失败。
逐层排查后发现该失败同时暴露了三个真实缺陷，均已修复。

- **`--check` 在干净检出下必然误报（门禁失效）**：旧实现用文件 **mtime** 判断产物是否过期，
  而 `actions/checkout` 不保留 mtime、且按路径顺序写文件（`native/crates/...` 先于
  `native/runtime_libc/...`），使源文件 mtime 普遍晚于产物 → 检查在 CI 中必然失败（本地因
  改过源码才重新生成，反而看不出问题）。现改为**源文件内容摘要**（SHA-256，含相对路径，
  并**规范化行尾**以消除 `core.autocrlf` 带来的平台差异），产物新增 `source_digest` 字段。
  实测：只改 mtime 不改内容 → 通过；改一个字节内容 → 正确拦截。
- **产物确实已过期**：仓库中的 `bytecode_libc_data.json` 是 2026-06-28 生成的，此后编译器演进
  （`SourceLoc.file_id`、字节码生成变化）已使其与当前编译器不同步（`code_len` 3387 → 3485）。
  已用当前编译器重新生成（一次性 diff 较大，同时包含键序重排与布局变化）。
- **`BYTECODE_LIBC_GLOBALS_RESERVED` 自我递增漂移（严重）**：library mode 下预编译 libc 的全局/字符串
  数据也从 `BYTECODE_LIBC_GLOBALS_RESERVED` 开始分配，于是
  `globals_size = reserved + 数据大小`，脚本再算出
  `reserved' = ceil(globals_size / 1024) * 1024 = reserved + 1024` —— **每重新生成一次产物就膨胀 1 KB**，
  最终把用户全局区压缩到不足 1 KB 并**溢出到堆区**（`HEAP_START = 0x5000`）。
  修复：library mode 下 `next_global_offset` 从 0 开始（产物记录的地址本就是相对 `GLOBAL_START`
  的偏移，用户侧仍从 `reserved` 之后分配）。实测 `globals_size` 14340 → **4**、
  `BYTECODE_LIBC_GLOBALS_RESERVED` 15360 → **1024**（稳定不再漂移）。
- **编译输出不可重现**：`generate_implicit_move_ctors` 遍历 `HashSet<String>`，
  隐式移动构造函数的生成顺序随进程随机种子变化 → 同一份源码的字节码布局每次不同；
  产物 JSON 又直接序列化 Rust 侧 `HashMap`，键序同样随机。修复：按类名排序后遍历 +
  生成脚本 `json.dump(..., sort_keys=True)`。实测连续 3 次生成的产物**字节级完全一致**。
- **全局/字符串数据段上限越过堆区（记录为已知限制，未改行为）**：`gen_string_literal` 的越界判据是
  `MEM_SIZE / 16`（64 KB），而堆区从 `HEAP_START`（20 KB）开始，两者共享同一块线性内存且编译期
  不校验是否重叠 → "全局/静态数据超过约 19 KB **且**程序使用 `malloc`"会静默压坏堆数据。
  **尝试把上限收紧为 `HEAP_START` 后发现会误伤 `lc_22` / `lc_977` 等现有用例**
  （它们的全局区本就越过 20 KB，只因不使用堆而行为正确），故**回滚该改动**，
  并如实记入 `AGENTS.md` 的已知限制而非擅自改变行为。
- **回归表现与验证**：上述第 3 项使 `test_vitro_e2e_leetcode` 的 `lc_67` / `lc_76` 失败
  （`lc_67` 的 `static char res[1000]` 溢出到堆区，`printf` 打出被压坏的内存内容，
  实际输出 `100 / o / world / 1 2 3 4 5`）。修复后
  `cargo test --workspace --all-features` 全量 **0 failed**。

### Docs (文档体系翻新：归档旧文档 + 重写核心文档 + 英文下线)

前端切割（2026-09-11）后对文档体系做整体收口：

- **归档 17 份旧文档**至 `docs/archive/`（统一 `ARCHIVE_` 前缀 + 归档横幅，索引见 `docs/README.md`）：
  前端耦合的构建/部署文档（`BUILD_SCRIPTS` / `CI_FAILURES` / 两份 `WEB_DEPLOYMENT` /
  `IMAGE_INPUT_INTEGRATION_PLAN` / `LOCAL_PERSISTENCE_PLAN` / `PANEL_DRAG_GESTURE_DESIGN`）、
  已完成的计划（`DATASTRUCTURE_SYNTAX_ROADMAP` / `POINTER_COMPOUND_ASSIGN_PLAN` /
  `PHASE_KR_LEETCODE_TEST_PLAN` / `CPP_BUILTIN_LAYOUT_DECOUPLING_PLAN` / `RECURSIVE_TYPE_SYSTEM_REFACTOR`）、
  被取代的评估与报告（`code_review_report.md`(2026-06-13/14) / `M7_BETA_READINESS` /
  `S6_READINESS_ASSESSMENT` / `SHADOW_VS_CI`）、定位被取代的 `VITRO_MOBILE_TEACHING_THREE_LANGUAGE_PLAN`。
- **重写核心文档**：根 `README.md`（纯后端定位 + 三出口一核心 + 实测状态）、`docs/README.md`（索引）、
  `docs/current/{DESIGN,ROADMAP,BUILD,QUICKSTART}.md`；其中 `ROADMAP.md` 新增「已知缺口」诚实记录表。
- **保留文档去前端化**：清除 `CideFlutter` / FRB / Dart 残留与失效引用，修正 crate 路径沉降
  （`native/src/vm/*` → `native/crates/vitro_{vm,runtime}/src/*`、`compiler/cpp_frontend/` → `crates/vitro_cpp_frontend/`、
  `unified/checkpoint.rs` → `vitro_vm::snapshot`），更新过时统计与日期口径；历史日志条目一律保持原样。
- **英文文档下线**：删除 `README_EN.md`、`docs/current/{BUILD_EN,VITRO_CLI_EN,QUICKSTART_EN}.md`、
  `native/third_party/README.md`（目录随之移除）与归档中的英文占位文件；仓库仅保留 `AGENTS_EN.md`（翻译后续再议）。
- **`AGENTS.md`**：新增「文档体系」纪律（新文档进 `current/`、被取代者带 `ARCHIVE_` 前缀入 `archive/`、
  英文只留 `AGENTS_EN.md`）与 `docs/{current,spec,archive}` 目录说明。
- **新如实记录的缺口**：①模板 → 用例生成器 `scripts/sync_templates.py` 随前端切割消失，
  `native/tests/cases_template_generated/` 83 个用例成为静态留存（链路断裂，见
  `SHADOW_VERIFICATION_FRAMEWORK.md` §6 与 `ROADMAP.md` G1）；②算法运行时属性验证
  （`validate_algorithm()` / `ValidationResult`）在 Rust 后端**从未落地**，
  原载体为 `CideFlutter/lib/models/algorithm_validation.dart`（见 `ROADMAP.md` G9；
  注：`AlgorithmMatch` 结构体在 `native/src/session.rs` 确实存在，缺的是"验证"环节）。

### Removed (tools)：D5 收官——7 个被 Go 版替代的 Python 驱动退役删除（仅留 git 历史）

- 删除：`shadow_verify_cpp.py`（630 行）、`replay/replay_s1_s5.py`（639 行）、
  `core_asset_verdict/{interaction_probe,random_diff,resource_longrun,seek_accumulation,winmem}.py`
  ——全部满足三条件：Go 版已接管 CI/防线、双轨对账一致的记录已归档
  （裁定 §13.7 各站）、CI 与活性代码零引用。`winmem.py`（ctypes psapi）唯一
  消费者即上述将删文件，Go 侧同款实现在 `scripts/internal/probeutil`。
  需要回看时 `git show 1d458eb^:scripts/<path>` 可取。
- 顺带清理：`scripts/{,__pycache__}`、`replay/__pycache__` 与 replay 目录下
  两个调试残留日志（均已被 gitignore，不在 git 内）。
- **保留不动**（各有明确理由）：① CI 活性 Python 四件
  `ci_three_tier_check.py` / `serve_smoke.py` / `precompile_bytecode_libc.py` /
  `engineering_health.py`（迁移 Go 是后续批次，删除即防线缺口）；
  ② 一次性取证脚本（`case_census` / `clang_oracle_audit` / `repro_panics` 等，
  裁定 §13.7 明确不迁移）；③ `mutation_facet_test.py`（会再跑，J3 测量工具，
  迁移待办）；④ 活性生成器/工具（`extract_cpp_builtin_layout.py`——
  C++ 布局真相来源、`sync_templates.py`、`unified_perf_baseline.py`、
  `debug_p3_leak.py`）。
- 验证：删除前后 `go vet ./scripts/...` 输出逐字节一致（3 个存量
  `unsafe.Pointer` 警告非本批引入）；`precompile --check` / `serve_smoke`
  / `ci_three_tier_check` 全绿。

### Removed (前端切割：仓库转型为纯后端)
- **执行主计划的前端切割决议**（[`VITRO_BACKEND_SPLIT_WASM_WHITEBOX_PLAN.md`](docs/current/VITRO_BACKEND_SPLIT_WASM_WHITEBOX_PLAN.md)）：
  本仓库只保留教学 C/C++ 子集参考执行引擎（白箱后端），前端迁出给社区，原生移动端放弃。
  切割前最后完整状态由标签 **`before-frontend-split`**（打在 `7dfd04f`）保留，
  `git checkout before-frontend-split -- CideFlutter` 可取回。
- 移除 `CideFlutter/`（Flutter 前端全套：编辑器、调试面板、算法可视化、教程引导、Android/iOS/Windows 工程）。
- 移除 FRB 桥接：`native/src/api/`（FRB 出口层）与 `native/src/frb_generated.rs`（本地生成物），
  `Cargo.toml` 删除 `flutter_rust_bridge` 依赖；9 个文件清除 `use flutter_rust_bridge::frb` 与 `#[frb]` 标记。
  - **能力保留**：自动修复应用器 `apply_fix` 的本体此前只存在于 FRB api 层（前端迁出会连带丢失），
    现迁入语言中立层 `native/src/diagnostics/auto_fix.rs`（三出口均可复用），
    `crash_regression_tests` 的 3 个相关用例改走新入口。
  - `flutter_bridge.rs`（手写会话包装层，无 FRB 依赖）保留——`vitro_cli` 当前消费；名称待后续重构收敛。
- 移除 web 部署：`.github/workflows/deploy_web.yml`（CideFlutter web → GitHub Pages + Gitee Pages）。
- 移除 Flutter 构建脚本（`build_flutter.py` / `build.py` / `build_release.py` / `build_utils.py` /
  `test_mobile.py` / `test_full_chain.py` / `patch_flutter_windows_generator.py` / `build_web.sh` /
  `sync_templates.py` / `test_templates.py`）与 5 份 FLUTTER_* 文档；`.gitignore` 清理对应条目。
- CI 收缩为纯后端：`ci.yml` 删除 flutter / android / ios 三个 job 与 rust job 内的
  FRB codegen / 模板同步步骤；Rust 引擎 + 三出口防线（shadow / serve 冒烟 / 一致性检查）全部保留。
- `templates/`（算法模板源）暂保留——后端防线不依赖（Shadow 模板用例已静态化在
  `native/tests/cases/`），待社区前端或 wasm 出口认领。
- 同步改写 `AGENTS.md` / `AGENTS_EN.md`：定位、技术栈、目录、构建命令、调试技巧全部对齐纯后端仓。

### Fixed (C++ lambda · 批次 H：条目 1 返回类型推断 / 条目 2 文件作用域 lambda 变量)
- **条目 1（lambda 返回类型硬编码 `Type::int()`）**：`__call` 的返回类型此前在
  `resolve_lambda`（`crates/vitro_typeck/src/expr/cpp.rs`）与 Pass 4 生成的 `FuncDecl`
  （`crates/vitro_typeck/src/lib.rs`）中**各自硬编码 `int`**，非 `int` 返回的 lambda 在调用点被当作 `int`
  （`printf("%.2f", d(1.5))` 触发 `E3062` 格式不匹配）。
  新增 `TypeChecker::infer_lambda_return_type`（取 body 首个 `return` 表达式的轻量推断：字面量 /
  形参 / 已捕获变量 / 二元运算取较宽者 / 显式转型），结果存入 `LambdaInfo::return_type`，**两处共用同一来源**。
  实测 `auto d = [](double x){ return x * 2.0; };` → Vitro `d=3.00`，与 Clang++ 一致。
- **条目 2（文件作用域 lambda 变量）**：`auto gf = [](int x){ return x + 7; };` 定义在 `main` 之外时，
  Pass 2.5 的 `declare_var` 登记的是**替换前的 `auto`**（类型替换发生在登记之后），于是调用点查表得到
  `auto` → `E3066 不能对非函数类型进行调用`。Pass 2.5 改为**先定型再登记**：全局 `auto`/`typeof`
  先由初始化器解析出类型并替换 `g.ty`，再登记符号；解析结果缓存给检查循环复用（避免重复解析 lambda
  导致 `pending_lambdas` 二次登记）。实测 `gg=8 6`，与 `CPP_FAILURES.md` 记录的 Clang++ 对照一致。
- 附带：`TypeChecker` 的 4 个类型工具函数（`type_has_auto` / `type_has_typeof` /
  `resolve_typeof_in_type` / `replace_auto_in_type`）提升为 `pub(crate)` 以便跨模块复用。
- 回归：新增 `native/tests/cpp_lambda_test.rs`（3 用例：返回类型推断、文件作用域 lambda 可调用、
  带捕获的局部 lambda 回归护栏）；`native/tests/CPP_FAILURES.md` 两项标记已修复并附剩余限制
  （多 `return` 类型合并与尾置返回类型 `-> T` 仍按 `int` 处理）。

### Fixed (scanf 族与标准输入 · 批次 G：条目 3 / 条目 4 + 输入换行口径统一 + Shadow 支持 `.in` 注入)
- **条目 3（scanf 返回值未实现）**：`scanf` 此前被 typeck 声明为 `void`，`int r = scanf(...)` 报 `E3004`，
  `while (scanf(...) != EOF)` 一类教学写法完全不可用。现按 C11 7.21.6.2 返回**成功匹配并赋值的项数**：
  typeck 侧返回 `int`，VM 侧 `host_scanf_n` 统计成功项并压栈（`sscanf` 早已如此，本次对齐）。
- **条目 4（scanf 普通字符指令被忽略）**：格式串中的非空白非 `%` 字符（如 `"a=%d"` 的 `a=`）此前被整段忽略，
  `scanf("a=%d", &x)` 读 `a=42` 得到 `x=0`（Clang 得 42）。现新增 `ScanfItem::Literal(u8)`：与输入流的下一个
  字符**精确比较**，不匹配即按标准**停止解析**并返回已赋值项数；`%%` 同样展开为字面 `%` 参与匹配。
  `sscanf` 同族同修（与空白指令修复的先例一致）。
- **标准输入换行口径统一（重要，由防线扩容暴露）**：capi `vitro_set_input`、FRB `set_input`、
  `vitro_cli serve` 的 `run.input` 与 `-i` 输入文件此前各自用 `str::lines()` 拆分，**丢掉行尾 `'\n'`**，
  而 E2E 防线用 `split_inclusive('\n')` —— 同一份输入在不同出口语义不一致，`getchar()` 永远读不到换行。
  现统一到 `RuntimeState::split_stdin` / `set_stdin`（保留换行、`\r\n` 规整为 `\n`），四个入口共用。
- **Shadow 防线支持用例自带 `.in` 注入（能力扩容）**：此前 Shadow 一律批量运行且不喂 stdin
  （脚本注释自述"纳入 key 以备扩展"），K&R 目录里 29 个 `.in` 文件从未被使用 ——
  "无输入"两侧恰好一致的**虚假 match**。现 `ShadowCase` 携带 `stdin`、Clang 与 Vitro 喂同一份字节、
  缓存 key 纳入真实 stdin。首次启用即暴露上述换行缺陷（19 例 `output_gap`：`kr_1_8` 的换行计数恒为 0
  等），修复后全部转绿。
- 回归：新增 3 个 Shadow/E2E 用例（`baseline/scanf_return_value.c`、`scanf_literal_match.c`、
  `scanf_literal_mismatch.c`，含负向"字面不匹配须停止解析"），Golden 由 Clang 生成。

### Fixed (会话级保险丝 · 批次 F：步数保险丝从未生效 + 配置静默丢弃 + 无回显)
> 起因：复核 PR 清单「条目 5：堆决议第三道墙」时给第三道墙补用例，结果发现**第二道墙本身是坏的**。
- **步数保险丝对全速运行的程序从未生效（严重）**：`native/src/engine/compile_pipeline.rs::setup_vm`
  里硬编码了 `vm.set_max_steps(10_000_000)` —— 每次 `run` 之前都会把会话配置**抹掉**，
  与 `VitroVM::reset()` 的"保留会话级配置"注释直接冲突。实测：设 2000 步的程序一路跑到
  **16 万步、直到撞 1MB 堆墙**才停；教学场景"可控地撞上限拿教学 trap"完全落空。
  旧用例 `test_second_wall_max_steps_fuse` 只断言 trap 消息含"步数超过限制"，1000 万步同样满足，
  因此长期掩盖该缺陷。现删除该行（默认值由 `VitroVM::default()` 提供、`reset()` 保留用户配置），
  并把用例强化为**回显配置值**（`（1000 步）`）。
- **会话级配置静默丢弃**：`vitro_set_max_steps` / `vitro_set_call_depth_limit`（capi）与
  `vitro_cli serve` 的 `config.set` 此前都写成 `if let Some(vm) = session.vm.as_mut() { .. }`
  并返回"成功" —— 会话尚未编译时（无 VM）配置被丢弃却报告成功。现下沉到语言中立层
  `Session::set_max_steps` / `Session::set_call_depth_limit`（无 VM 时先建立承载配置的 VM），
  capi 与 serve 共用同一入口。
- **配置可写不可读**：`session_api::config()` 补 `max_steps` / `call_depth_limit` 回显
  （VM 未创建时为 `null`），并给 `VitroVM` 补 `max_steps()` getter —— 消费方（SharpTutor / 判分脚本）
  据此可确认保险丝真的落到 VM 上，而不是"设置成功、实际未生效"。
- **堆决议三道墙用例补齐**（`VITRO_HEAP_QUARANTINE_DECISION.md` §6 的最后一项，原记为"推导项"）：
  新增 `crash_regression_tests::test_third_wall_region_table_bounded_when_step_fuse_trips_first`
  —— leak 路径上步数保险丝先触发时，region 条数必须 ≤ 步数上限（有界），且未撞 1MB 墙。
- 回归：新增 `native/tests/session_config_test.rs`（4 用例：配置跨 run 存活并生效、调用深度上限存活、
  `config()` 回显、capi 在编译前设置也生效）；`test_second_wall_max_steps_fuse` 强化断言。

### Fixed (教学标注 · 批次 E：P1-6 C++ 向上转型被误报为"数据截断")
- **P1-6（多态基础被讲成危险操作）**：`Base* b = new Derived();` 此前报
  `不兼容的指针类型赋值：Base* ← Derived*` 并建议"隐式类型转换可能导致数据截断" ——
  复用了**标量**转换码 `W3053_ImplicitScalarConversion`。C++ 向上转型是隐式允许的多态基础写法，
  Clang++ 在 `-Wall -Wextra` 下实测零警告。
  - 新增专用码 `W3067_PointerTypeMismatch`（`vitro_shared::ErrorCode` + 错误目录条目 + 建议文案
    "指针类型不兼容，需要显式转换；向上转型（派生类指针 → 基类指针）本就不需要转换"）。
  - `TypeChecker::is_upcast`：沿**单继承链**回溯判定向上转型（教学子集不支持多继承，单链足够；
    带 32 步步数上限防环），向上转型不再产生任何指针诊断。
  - 向下转型（`Base* → Derived*`）与无关类型指针仍报 `W3067`，文案改为指针语义
    （不再出现"数据截断"）。
- **诚实记录补录**：该差异此前未写入 `CPP_SUBSET_SPEC.md`（违反"以 Clang 为标准、不一致必须记录"的纪律）。
  现补 §4.5「指针赋值的方向语义」：三场景对照表 + 修复记录 + **剩余差异**（Clang 对向下转型是
  **error** 拒绝编译，Vitro 仅为警告并继续编译）+ 已知显示瑕疵（警告的 code 被加 `E` 前缀，见下）。
- 回归：新增 `native/tests/pointer_upcast_test.rs`（3 用例：向上转型无指针诊断、向下转型仍提示、
  无关类型仍提示且不出现"截断"文案）；`type_checker_unit_test.rs` 的 B39 用例改用新码文案。
- **已知显示瑕疵（未修，如实记录）**：诊断 JSON 的 `code` 字段与 `vitro_cli` 输出对**警告**也加 `E` 前缀
  （`W3067` → `E3067`，此前 `W3053` → `E3053` 同源）；`severity` 字段正确。修复需让
  `session_api::compile` 按 severity 生成 `E`/`W`/`H` 前缀 —— 属独立小项，本次不动。

### Fixed (教学标注 · 批次 D：P0-4 多文件会话的行号归属)
- **P0-4（多文件会话语义标注凭空捏造）**：多文件编译会把各编译单元合并成一份源码
  （`merge_compile_units`），因此字节码与 `code_line` 里的是**全局行号**；而语义标注此前固定用
  `compile_units.first()` 的**文件内行号**去查 —— 单文件时两者恰好一致（所以问题长期未暴露），
  多文件时必然错配（实测 `main.c` 仅 13 行却报出 `line 20..25`），会产出与真实执行行无关的
  "看似合理"的描述。
  - 新增 `Session::source_line_at(global_line)`：按 `CompileState.file_ranges`（`merge_compile_units`
    产出，随编译期写入）换算 `(文件, 文件内行号)`；单文件会话（`file_ranges` 为空）保持
    "全局行号 == 文件内行号"的原语义。
  - 四处重复且各自为政的实现统一到该方法：`unified/collector.rs`（语义标签）、
    `Session` 的 `AlgorithmContext::source_line`（算法步骤）、`unified/engine.rs`（检查点用的
    轻量标签）、`unified/trace_analyzer/utils.rs`（轨迹分析）。
  - **顺带修复**：函数定义行（`int helper(int x) {` 含 `helper(`）此前被标成"递归调用 helper"，
    现按"签名与 `{` 同行"排除该误判（左花括号换行的写法仍可能误判，已记为已知限制）。
- 回归：`native/tests/step_payload_vars_test.rs` 扩至 **8 用例**（新增：多文件下 main 的标签不得
  串用 helper.c 的源码行、函数定义行不得报为递归调用）。

### Fixed (教学标注 · 批次 C：P0-2 越界描述 / P0-3 两套标注互相矛盾)
- **P0-2（描述不存在的比较）**：`vitro_algorithm_steps::sorting::infer_bubble_sort` 新增内层下标有效性判据
  —— 内层循环条件为 `j < n-1-i`，故参与相邻比较的 `j` 合法上界是 `n-2-i`；当 `j` 停在退出值上时
  **不再产出** "比较/交换 `arr[j]` 与 `arr[j+1]`"，直接返回 `None`（宁缺勿错）。修复前实测 5 元素数组
  产生 **24 步**含 `arr[5]`（数组上界为 4）的描述、真实比较只有 10 次；修复后 **0 步**。
  （诚实记录：这 24 步此前落在**交换**模板上而非清单所写的"比较"模板 —— 比较模板采样时 `j` 尚未自增到退出值。）
- **P0-3（同一 payload 内两套标注互相矛盾）**：`native/src/unified/collector.rs` 的交换标签不再取
  `loop_vars.first()`（白名单首位常是规模量 `n`，实测取到 `n=5` → `交换 arr[5]↔arr[6]`，而同一 payload 的
  `algorithm_step` 说 `交换 arr[0]↔arr[1]`）。改为**从源码行解析数组下标标识符**（`temp = arr[j];` → `j`）
  后到循环变量里查值；解析不到时按内层循环命名回退（`j` → `i` → `k` …），最后才取候选末位。
  实测同一步的两套标注现已逐字一致。
- 回归：`native/tests/step_payload_vars_test.rs` 扩至 **6 用例**（新增：算法描述不得引用越界下标、
  同一步两套交换标注必须一致、冒泡"第 k 趟"必须等于"第 k 大"）。

### Fixed (教学标注与 CLI 契约 · 批次 B：P2-7 变量快照可见性与类型名)
- **P2-7a（同名变量无法区分）**：`VitroVM::get_variable_snapshot` 改为按 **(函数归属, 声明行)** 过滤并对同名去重 ——
  新增 `Symbol::decl_line`（codegen 在参数/局部/静态/全局各构造点填入），`decl_line > 当前执行行` 的符号视为
  "尚未进入作用域"不可见，同名保留"已进入作用域且声明最晚"者；`code_line == 0`（预热步 / 库函数内部）时
  不输出局部变量（无法判定作用域时保守留空，而不是猜一个）。两个 `for` 各声明一个 `i` 时，现在按执行位置
  在两者之间正确切换（回归测试断言地址序列恰为两个且有序）。
  `scope_depth` 在所有构造点都是常量（局部 1 / 静态 0），不表达嵌套深度，**不能**用作判据 —— 已在字段注释如实记录。
- **同源缺陷（清单未提，本次一并修复）**：函数内声明的符号此前**不过滤函数归属**，`helper` 的局部变量会出现在
  `main` 的 payload 里，并且是用 `main` 的 `locals_base` 去读 `helper` 的偏移 —— 地址错位、值无意义。
  多文件会话下这还会污染 `semantic_label`（出现两个 `i` / 两个 `j`）。
- **P2-7b（数组暴露"地址式"值）**：`local_vars` 中数组条目的 `value` 改为**元素摘要**（`{5, 3, 1, 4, 2}`，
  超过 16 个元素截断为 `…`）。此前显示首元素（多为 `0`），与 `array_snapshots` 重复且易被消费方误读成
  "数组的值"；`addr` 字段保留（内存/指针视图仍需数组基址）。
- **P2-7c（类型名泄漏内部结构）**：`ty_name` 由 `format!("{:?}", ty)` 改为 `vitro_runtime::type_display_name`
  —— C/C++ 风格稳定可读名（`int` / `unsigned int` / `const char*` / `int[5]` / `struct Node` / `Foo` / `int&`）。
  该函数同时成为 `array_snapshots[].element_ty` 的单一来源（输出值不变 `int`，消除手写映射漂移）。
- **回归与文档**：新增 `native/tests/step_payload_vars_test.rs`（3 用例：同名变量按声明行切换、跨函数隔离、
  数组摘要与可读类型名）；`docs/spec/STEP_PAYLOAD_SCHEMA_V0_1.md` 同步（`ty_name` 语义与示例、
  §8 风险 #7 标记已修复、新增 #8 记录跨函数/同名问题）。

### Fixed (教学标注与 CLI 契约 · 批次 A：P0-1 冒泡趟数文案 / P1-5 `compile` 退出码 / 引擎附注粘连)
- **P0-1（教学文案把概念教反）**：`crates/vitro_algorithm_steps/src/sorting.rs` 冒泡排序外层循环的描述由
  `kth = n - i` 改为 `i + 1` —— 第 pass 趟确定的是「第 pass 大」的元素（升序冒泡每趟把当前未排序区间的最大值
  冒到区间末尾），旧式是"剩余待排个数"，与排名恰好相反（n=5 时第 1 趟显示"第 5 大"= 最小元素）。同时加
  `i + 1 <= n` 有效性判据。错误并非实现偏离设计：`docs/archive/REVIEW_REPORT_2026-05-18_FULL.md:1059`
  的设计稿即写作 `第 {i} 趟：将第 {n-i} 大的元素`。
- **P1-5（CLI 退出码不反映编译失败）**：`native/src/bin/vitro_cli.rs::cmd_compile` 此前丢弃 `compile_file`
  的返回值，`vitro_cli compile bad.c` 会带着诊断信息退出 0，CI 脚本 / headless 消费方（SharpTutor）据此
  误判"编译通过"。现与 `cmd_run` 一致：编译失败即 `std::process::exit(1)`。
- **引擎附注粘连（泄漏报告压成一行）**：`RuntimeState::push_note` 统一为每段附注补齐尾随 `\n`。display 视图是
  零分隔顺序拼接，而 `append_leak_report` 的 5 行**全部没有尾随换行**（只有首行有前导 `\n`），实测输出被压成
  `===== 内存泄漏检测报告 =====发现 1 处未释放的堆内存，共 16 字节：  • 第 4 行的 malloc…💡 提示：…======`。
  **仅 note 通道做此规范化；程序 stdout / stderr 逐字节保真，不做任何加工。**
- 复核与修复跟踪：新增 [`docs/current/code_review_report_2026-09-11.md`](docs/current/code_review_report_2026-09-11.md)
  （外部 PR 清单 12 项的独立复现结论、对清单 3 处表述的修正、以及分批修复状态表）。

### Fixed (E-P1-5：输出通道分离——程序 stdout 与引擎附注不再混装)
- **根因**：`RuntimeState::output_lines` 一个 `Vec<String>` 同时承担「程序 stdout / 程序 stderr / 引擎附注」三种语义，
  且附注可在流**中间**插入（如 `[堆] 内存耗尽` 提示在 `malloc` 失败处 push，程序随后还会继续输出）。
  消费方只能靠文本正则把附注洗掉，同一套清洗规则散落**十余处**（`shadow_verify.py`、`shadow_verify_cpp.py`、
  `vitro_e2e.rs`、`bytecode_libc_consistency.rs`、`test_utils.rs`、`bytecode_gen_cpp_unit_test.rs`、
  `end_to_end_extra_test.rs`、`qsort_test.rs`、`test_more.py`、`test_massive.py` …），且语义互不一致
  （全局替换 vs 行内截断、`>=30` vs `==30` 个等号、丢空行 vs 仅 strip 首尾）。教学程序自己打印
  `程序运行完成，返回值：7` 时会被**整段删除**，一条本来正确的用例被记成 `output_gap`（假阳性）。
- **修复**：`vitro_runtime` 新增 `OutputKind{Stdout,Stderr,Note}` + `OutputChunk`；`RuntimeState::output_chunks`
  成为唯一真相，提供 `stdout()` / `stderr()` / `notes()` / `display()` 四个投影（`output()` 保留为 `display()` 别名，
  UI / CLI 展示语义不变）。约 20 处 push 点完成分类迁移：`printf`/`puts`/`putchar`/`fputs(stdout)` → stdout；
  `fputs(stderr)`/`fprintf(stderr)`/`perror` → stderr；运行完成提示 / 泄漏报告 / `malloc(0)` 警告 / 堆耗尽提示 /
  `[abort]` / 断言失败 / `qsort`·`bsearch` 深度提示 → note。快照（`vitro_vm::snapshot::RuntimeSnapshot`）
  同步携带分段，时间旅行回退不丢通道标记。
- **出口（ABI 1.0.0 → 1.1.0，加函数 = minor）**：capi 新增 `vitro_get_program_output_length` /
  `vitro_get_program_output` / `vitro_get_engine_notes_length` / `vitro_get_engine_notes` /
  `vitro_get_program_output_delta`；`vitro_get_output*` 保持「展示视图」语义不变（`CideFlutter` 集成测试依赖其含
  "程序运行完成"文本，故不改语义、不升 major）；`vitro_cli serve` 的 `output.delta` 新增可选 `stream` 参数
  （`display`（默认）/ `stdout` / `stderr` / `note`），响应带 `stream` 字段。`native/include/vitro_capi.h` 同步。
- **驱动侧**：十余处清洗规则**全部删除**；`shadow_verify.py` 与 `scripts/shadow_verify_cpp.py` 共用
  `native/tests/shadow_verification/vitro_output.py`（结构化读取唯一入口，禁止再自行清洗）；DLL 缺新符号时
  **fail fast** 并提示重建，不退回旧清洗口径。
- **回归固化**：新增 `native/tests/cases/baseline/engine_note_lookalike.c`（程序打印与引擎附注逐字相同的文本、
  触发一次 `malloc(0)` 附注、走一次 stderr、以无尾换行收尾），Golden 由 Clang 生成（`cases_golden/baseline/`）；
  新增 `end_to_end_extra_test::test_e2e_engine_note_does_not_pollute_stdout` 断言 stdout / note 分离。

### Changed (Shadow 验证提速：Clang 结果缓存 + 并行执行 + release DLL 陈旧检测)
- **Clang 结果缓存（方案 A）**：`native/tests/shadow_verification/shadow_verify.py` 新增 Clang Golden 缓存 ——
  key = `schema + platform + clang 版本 + 编译/运行参数 + 用例源码（含 `#include` 头文件内容哈希）+ stdin + VFS 预设文件哈希`，
  任何一项变化自动失效；`--refresh-clang` 无条件重算并覆盖（CI 夜间 schedule 使用，防 clang 版本漂移）。
  原子落盘（临时文件 + `os.replace`），损坏/schema 不符一律视为未命中（宁重算，不用不可信 Golden）。
- **并行执行（方案 B）**：`--jobs N`（默认 0 = `min(CPU, 8)`，1 = 串行）。
  首选 `multiprocessing.Pool`（`imap_unordered` 任务级负载均衡）；**命名管道被禁的环境自动回退分片 subprocess**
  （`subprocess` 用匿名管道，不受限）。两条路径均按用例索引重排 —— 报告与门禁结论与串行逐项一致。
  `prepare_test_files` 从"每用例调用"改为 **worker init 一次**，且写入**各 worker 私有的隔离运行目录**
  （同时作为 Clang 运行的 cwd），并行 worker 之间不再互相覆盖。
- **release DLL 陈旧检测（顺手修）**：Shadow 用 `target/release` DLL 而日常构建多为 debug，改完引擎不重建就会
  拿**旧引擎**跑门禁（2026-09-11 实际踩到）。现启动时比对引擎源码（`native/src`、`native/crates`、`Cargo.toml`）
  与 DLL 的 mtime，过期即打印醒目警告；`--rebuild` 可自动 `cargo build --release`。
- **不再使用 `tempfile`**：其 `mkdtemp` 内部以 `os.mkdir(p, 0o700)` 建目录，在受限（沙箱）环境下生成**不可写**目录
  （实测 WinError 5），且临时目录位于系统 TEMP 时同样不可用 —— 改为自管生命周期的工作区目录 `.shadow_tmp/`。
- **确定性修复**：`load_case_files()` 的 glob 结果改为 `sorted(...)`（glob 顺序依赖底层 scandir，**跨进程不保证一致**，
  并行 worker 按索引取用例会错配）；分片 payload 同时携带用例 **name**，主进程按索引回收后再做 name 对账。
- **实测（632 用例，2026-09-11）**：优化前串行全量 **103.6s** → 优化后（缓存命中 + 8 并行）**1.1s**，
  冷启动（并行 + `--refresh-clang` 全量重算）**20.4s**；三次运行的 `(用例, 判定)` 序列**逐项完全一致**（0 非预期差异）。
- **CI**：`.github/workflows/ci.yml` 新增 `schedule`（夜间 18:00 UTC）夜间模式加 `--refresh-clang`；
  新增 `actions/cache` 缓存 `.clang_cache`（key 含 OS + clang 版本 + 脚本哈希，clang 升级自动失效）。
- **性能顺带优化**：`run_with_vitro` 的 `ctypes.CDLL` 加载与全部函数签名设置从**每用例一次**改为**每进程一次**。

### Added (Phase 1 出口 3：`vitro_cli serve` JSON-lines 会话模式)
- **新增 `native/src/bin/vitro_cli.rs::cmd_serve`**：stdin 每行一个 JSON 请求 / stdout 每行一个 JSON 响应（NDJSON）。
  契约：**id 关联**（响应原样回填 `id`）、**错误帧与成功帧同构**（`{"id","ok","result"}` / `{"id","ok","error":{kind,message}}`）、
  `session.reset`（长寿命进程复用）；方法集 `compile` / `run` / `output.delta` / `step.begin` / `step.next` /
  `payload.get` / `seek` / `breakpoints.set` / `memory.regions` / `config.get|set` / `session.*` / `ping` / `shutdown`。
- **语言中立层提炼 `native/src/session_api.rs`（新增）**：capi 第一批的 JSON 结果构造（编译诊断 / 运行三态 /
  游标增量 / 单步 payload / 窗口查询 / 断点写入 / 内存视图 / 会话配置）全部下沉，`capi` 与 `serve` **共用同一实现**
  （主计划纪律 §2.2-2：三出口只做薄包装，防"typeck 与 codegen 双轨语义"重演）。capi 侧变为薄包装，出口 JSON 形状不变。
- **防线**：`scripts/serve_smoke.py`（26 项断言：id 关联 / 帧同构 / 生命周期 / 与 capi 同形的 payload 字段 /
  默认隔离预算 262144 / `config.set` 生效 / 非法程序诊断 / 未知方法错误帧），已进 CI。
  文档见 [`docs/current/VITRO_CLI.md`](docs/current/VITRO_CLI.md) §6。

### Added (StepPayload Schema v0.1 定稿文档 + 字段冻结测试)
- **新增 [`docs/spec/STEP_PAYLOAD_SCHEMA_V0_1.md`](docs/spec/STEP_PAYLOAD_SCHEMA_V0_1.md)**（语言中立）：
  顶层 14 字段语义、子结构、**指针四状态枚举（Valid/Freed/Null/Dangling）及其判定优先级**、
  `accessed_vars` 读写枚举、`vis_events.ty` 编码、**frameCache 窗口语义**（2000 帧 / 丢弃最早 20% /
  `cache_start_step` / 越窗 seek = 检查点恢复 + 正向重放 / seek 后窗口重置与截断）、
  `StepStreamBatch`/`StepPayloadDelta` 差分编码（`null` = 未变 vs `[]` = 空 的区分是契约）、
  出口形状、版本化纪律（字段只增不改语义）与**回放场景校验记录**（我方 C1–C4 已实测；对端 S1–S3 待 SharpTutor 执行，如实标注）。
- **新增 `native/tests/step_payload_schema_v0_1_test.rs`（5 用例）**：从 **capi 出口 JSON** 层面冻结 schema ——
  顶层 14 字段键集合、子结构字段集合、`PointerStatus` 与 `access_type` 字面量、窗口 2000 帧上限与
  `cache_start_step` 前移。字段一旦改名/增删即测试失败，强制走版本化流程（防止 schema 文档悄悄过期）。

### Added (堆隔离预算的会话配置出口)
- **`vitro_set_quarantine_budget` / `vitro_get_quarantine_budget`（capi）**：补齐堆决议 §1「隔离预算可调，写进会话配置」
  的对外暴露缺口（此前仅引擎字段可调，capi 无 setter）。语义：默认 256KB；`0` = 关闭隔离（教学对照，
  free 后立即可复用）；超大值裁剪到堆上限（1MB）；负值拒绝。serve 侧经 `config.set` / `config.get` 暴露同一字段。
- **集成测试 3 例**（`capi_first_batch_tests.rs`，该文件 15→18）：`test_set_quarantine_budget_controls_address_reuse`
  （默认预算下 `free` 后地址不复用 → 预算 0 时立即复用，用同一程序的 `p == q` 输出证明）、
  `test_quarantine_budget_is_clamped_to_heap_limit`、`test_quarantine_budget_setter_rejects_null_session`。

### Added (capi 第一批：SharpTutor 评审定稿落地，10/13 函数)
- **新增 `native/src/capi/first_batch.rs`**，按 [`VITRO_CAPI_REVIEW_RESPONSE.md`](docs/current/VITRO_CAPI_REVIEW_RESPONSE.md) §1 落地第一批：`vitro_abi_version`（契约版本 `1.0.0`，加函数=minor / 改签名=major）、`vitro_engine_version`（crate 版本 + 可选构建期 git hash）、`vitro_free_string`（rust-alloc 所有权唯一释放入口，废弃 caller-buffer 双轨）、`vitro_last_error`、`vitro_compile_json`（诊断含 `severity` 枚举与 `end_line/end_column`——精确跨度需动三处错误结构体，本批先给"起点+1"退化值，schema 不欠债）、`vitro_run_json`（`status` 三态 + `return_value`/`trap` E 码透传/`waiting_input`/`steps_executed`）、`vitro_get_output_delta`（游标增量，多字节边界安全）、`vitro_set_max_steps`、`vitro_set_call_depth_limit`、`vitro_set_deterministic`/`vitro_get_deterministic`。
- **横切契约**：全部 JSON 返回为 rust-alloc 字符串（`vitro_free_string` 释放）；全部入口 `catch_unwind` 包裹（panic 不跨 C 边界）；状态码 `0=成功/负=入参或会话无效/正=领域状态`；Session 非线程安全声明；UTF-8 输入输出。
- **引擎侧配套**：`VitroVM` 新增 `call_depth_limit` 字段（V-P1-10）与 `do_call_inner` 深度检查（下限 16 层兜底），`reset()` 不再清空会话级配置（`max_steps`/`call_depth_limit` 由 `set_*` 设定后须跨运行存活）；`RuntimeState` 新增 `deterministic` 字段，`host_time`/`host_clock` 在该模式下固定返回 0（Phase 1 判分确定性最小形态；完整 step 派生伪时钟仍留 Phase 3）。
- **断点 / 单步三函数（同批落地）**：`vitro_set_breakpoints`（JSON 整数数组，须在 `vitro_step_begin` 之后设置——step_begin 会重建 VM 并清空断点）、`vitro_step_begin`（新增入口：装载 VM + 重建运行时 + 初始检查点）、`vitro_step_next_json`（返回 `AutoStepResult` JSON，命中断点时 `paused=true`）、`vitro_get_step_payloads_json`（按步号区间取 payload 数组 + `cache_start_step`/`max_collected_step`）。配套：`UnifiedEngine` 由 `Session` 持有（`Session::unified`，三出口共用同一会话）；`StepPayload` 类型链（含 `PointerSnapshot`/`AccessedVar`/`ArraySnapshot`/`ApiFrameInfo`/`AlgorithmStepSnapshot`/`RootCauseHint` 等 16 处）补 `serde::Serialize`。
- **集成测试** `native/tests/capi_first_batch_tests.rs`（15 用例）：字符串所有权与重复分配、`severity`/`end_column` 字段、运行三态、游标增量三场景（初始/末尾/负游标）、三处保险丝（max_steps 死循环 trap、call_depth_limit 深递归 trap、deterministic 冻住 `time()`）、统一模式（未编译返回 -2、单步 payload schema 关键字段、断点命中 `paused=true`、非法断点入参）。
- **本批全部 13/13 落地**（含上表断点/单步三函数）。

### Fixed (标准库 stub 头文件不可用 —— include 换行被吞)
- **根因**：预处理器把标准库 stub 的换行**全部替换为空格**（原意是"避免源文件行号偏移"），导致 stub 内的 `#define` / `#ifdef` 等指令落到行中间、不再被识别为预处理指令 —— `time.h` / `float.h` / `errno.h` / `assert.h` / `stdarg.h` **五个含宏的标准库 stub 整体编译失败且不给任何诊断**（`stdio.h` 恰好不含宏，长期掩盖了该问题）。
- **修复**：include 内容**保留原始换行**，改为**行号补偿** —— 插入前先把 `self.line` 减去插入内容的换行数，扫描完插入内容后行号恰好回到 include 行的下一行，因此后续源码的诊断行号与 include 无关。自定义头文件同样受益（此前它保留换行但无补偿，行号会整体偏移）。
- **实测**：`CLOCKS_PER_SEC` / `FLT_RADIX` / `EINVAL` 宏可正常展开（输出 `1000000 2 1`）、`assert(1 == 1)` 可用、语法错误仍报原始第 4 行（零偏移）；C shadow 632 用例与 C++ shadow 100 用例 0 非预期差异。
- **回归测试**：`crash_regression_tests.rs` 新增 3 例（含宏 stub 编译与展开、assert 函数式宏、include 不顶偏诊断行号）。

### Changed (堆内存模型：bump 分配 + 有界隔离 —— 2026-09-11 决议落地)
- **`malloc`/`calloc` 改为 bump 顶指针推进 + 隔离区驱逐复用**（`MemoryState::allocate_raw`）：隔离区超预算（默认堆上限 1/4 = **256KB**，会话级可调）时按 FIFO 驱逐最老已释放块归还 `free_list`，再 first-fit 复用。原"free_list 查找 + 相邻合并"的分配路径退役，`merge_free_list` 降级为驱逐路径内部实现。
- **`free` 改为进入 FIFO 隔离区**（`MemoryState::release_to_quarantine`）：地址在隔离期内不复用。`freed_logs` / 泄漏判定 / E3027·E3061 诊断逻辑全部保留。`host_free`、`realloc(p, 0)`、VM 内部 `free_memory`（`new[]` 构造失败回滚）三条释放路径统一走该出口。
- **`realloc` 恒为新块拷贝**：移除"堆顶原地收缩"与"优先复用旧地址"两个特例——前者会把 `heap_offset` 回退进隔离区，后者让刚 free 的地址立即重新生效，都会破坏"隔离窗口内地址不复用"的保证。E2E 断言 `test_e2e_realloc_in_place_shrink` 按决议 §4-3 重写为 `test_e2e_realloc_new_block_copy`（把分配器复用行为从契约中除名，改测"搬移 + 原数据完整保留"）。
- **隔离区纳入快照与重置闭环**：`MemorySnapshot` 增加 quarantine 三字段（时间旅行回退后隔离窗口不丢失，否则 UAF 检测出现假阴性）；`reset_runtime` 清空隔离区但保留会话级预算配置。
- **堆耗尽（1MB 墙）返回 NULL + 一次性教学提示**：leak 路径 bump 单调推进直至撞墙，`malloc`/`calloc`/`realloc` 三条 OOM 路径输出教学诊断（按内容去重）。**不 trap** —— C 标准要求分配失败返回 NULL，Clang 同样返回 NULL，trap 会偏离"必须检查返回值"的编程习惯（与决议 §5"教学 trap"措辞的差异已记入 `C_SUBSET_SPEC.md` §2.9-4）。
- **`fopen` 的 FILE\* 分配统一走堆分配入口**：此前直接推进 `heap_offset`，绕过隔离与驱逐逻辑。
- **碎片可视化语义变更（决议 §4-2 处置）**：`free_list` 现仅承载"隔离期满已归还"的块，外部碎片只在驱逐复用路径出现；Phase 14 的"碎片率"指标仍保留（`build_heap_stats` 不变）但语义收窄。三色堆图（已分配 / 隔离中 / 可复用）随 capi 第二批的内存 API 一并落地（`status: allocated|freed`），本次先在引擎层把语义备好。
- **测试防线**：`host_contract_tests`（3a）新增 4 条隔离区契约（free 入隔离区不入 free_list / 驱逐后地址复用 / realloc 必搬移 / `heap_offset` 不回退）；`crash_regression_tests.rs` 新增 5 条堆语义专项（churn 10 万次不撞墙 + 驱逐后地址复用 / 隔离窗口内 UAF 与 Double-Free 必检出 / 1MB 墙 NULL + 教学提示 / realloc 搬移保留数据）。
- **`C_SUBSET_SPEC.md` 新增 §2.9**：堆模型、设计动机（churn / leak 分离）与四项与 Clang 的差异（隔离窗口外 UAF 漏检、realloc 恒搬移、复用时机不同、堆耗尽不 trap）。

### Fixed (SharpTutor Issue A/B：教学阻断修复)
- **Issue A：scanf/sscanf 格式串空白指令不跳白**（教学阻断，优先级最高）。`parse_scanf_specs` 此前只提取 `%` 转换符、丢弃格式串中的空白字符，导致 `scanf("%d %c %d", &a, &op, &b)` 读 `3 + 4` 时 `%c` 捕获空格而非 `+`（C11 7.21.6.2 要求空白指令匹配输入中任意数量（含零）的空白字符）。现解析结果改为有序项序列 `ScanfItem::{Spec, Whitespace}`，空白指令只跳白不取参；参数计数改按 `Spec` 项数统计（空白指令不消费指针参数）。scanf/sscanf 共享解析，全族同病同修。`%c` 不自动跳白是既有正确语义，未受影响。
- **Issue B1/B3：lambda 立即调用编译错与错误码误用**。`[](int a, int b){ return a + b; }(2, 3)` 此前编译失败——`vitro_typeck/src/expr/call.rs::resolve_call_ptr` 只处理 callee 为标识符的调用，Lambda 表达式节点的 callee 一路落到"非函数指针"兜底，且误用 `E3045_CompoundAssignType`（复合赋值类型错误），建议文本随之串成"+= -= *= /= 等复合赋值要求操作数类型兼容"。现 typeck 识别 Lambda callee，与变量形式（`auto f = lambda; f(1)`）**共用同一改写函数 `rewrite_lambda_call`**（消除双轨语义）；新增错误码 **`E3066_CallNonFunction`**（含 error_catalog 条目与建议文本），兜底报错改用之。Clang 对照语义：`called object type 'int' is not a function or function pointer`。
- **Issue B2：lambda 槽位按 0 字节分配，StoreLocal 冲出 1MB 线性内存**。`gen_lambda` 在栈上推的是**闭包对象地址**、lambda 变量槽里存的也是该地址（4 字节），但槽位与闭包对象大小一律按闭包类字段总大小计算——无捕获闭包 size 为 0，于是 `auto f = [](int x){ return x + 100; };` 在帧内根本没有槽位，`StoreLocal` 写到帧外并越出线性内存（实测 `locals_base=1048572`、`operand=4`、`addr=1048576` = MEM_SIZE）。触发条件为"先出现 lambda 立即调用、后声明 lambda 变量"（仅立即调用不触发，仅变量声明也不触发）。修复：新增 `is_lambda_closure_type` 作**单一判定来源**，lambda 变量槽位与闭包对象均保底 4 字节；同时修正实参处理——lambda 一律按 1 word（地址）压栈，不再按字段数补零（**双字段捕获闭包此前会多压 1 word 造成参数错位**，与 B2 同源）。**同源第三处**：`static` lambda 变量走全局区分配（`emit_static_var`），同样按闭包类字段大小占地——两个 static 闭包地址重叠，实测 `printf` 输出乱码（Clang 对照 `s=8 6`），已按同一判定修为一并覆盖。同批实测记录的两项**未实现能力**（文件作用域 lambda 变量、lambda 返回类型非 int）已记入 `native/tests/CPP_FAILURES.md`。
- **回归测试**：`crash_regression_tests.rs` 扩展 11 个用例（19→30）——Issue A 4 个（空白指令正/反向对照 + 多空白等价 + sscanf 共享语义）、Issue B 7 个（立即调用、实参位置、立即调用后声明变量、有捕获闭包实参、static 变量槽位、变量形式反向对照、E3066 错误码与建议文本断言）。全部期望值取自 Clang/Clang++ 实测 Golden，Vitro 输出逐字节一致。

### Added (capi 签名评审定稿：SharpTutor API 诉求逐条回应)
- **新增评审回复文档** `docs/current/VITRO_CAPI_REVIEW_RESPONSE.md`：对 SharpTutor《后端 API 需求与签名评审》逐条回应（§1~§9 全覆盖）+ 六个开放问题的正式回答。核心结论：**整体接受，一处分歧修订为并行**。含三项实证核验——重复编译内存有界（10000 次交替编译 RSS 16.6→18.4MB 平台期，将固化为回归断言）、`MemoryRegionData.alloc_line/alloc_by` 已存在（零成本直通）、frameCache 越窗行为已查证（检查点恢复+正向重放）；SharpTutor 项目实地核验（三进程架构、EndLine/EndCharacter 消费点属实）。
- **主计划修订（§3.2/§5.3/§6/§7）**：StepPayload schema v0.1 定稿从 Phase 3 **前置到 Phase 1**（第一批 `step_next_json` 输出即 StepPayload，协议不可能晚于消费它的 API）；`vitro_set_deterministic` 最小形态（time 固定 + rand 种子固定）提前进 Phase 1，与 Phase 3 完整伪时钟分层（判分确定性 vs 重放确定性）；wasm 与 capi 第二批改为**并行**（Phase 2a/2b，各约一周互不抢资源——wasm 是社区前端生态冷启动开关，不因单一消费者无需求而后置）；capi 第一批扩容（engine_version/last_error/free_string 字符串所有权/set_max_steps/set_call_depth_limit/run_json 判分契约/断点三函数）；serve 增加 id 关联、错误帧同构、session.reset；JIT 断点完整性从 V-P1-2 提级为行为契约。

### Changed (战略转型：后端独立化与 wasm32 白箱化)
- **定位转型决策**：Vitro 从"跨平台教学 IDE"转型为"教学 C/C++ 子集参考执行引擎（白箱）"。本仓库只做后端，MIT 许可；前端切割给社区（首个外部消费者 SharpTutor/WPF 已提出集成）；原生移动端放弃（"看"场景由 wasm32 + Web 前端的移动浏览器覆盖）。决策依据与完整路线见新增设计文档 `docs/current/VITRO_BACKEND_SPLIT_WASM_WHITEBOX_PLAN.md`（切割清单、capi 分批补全、交互资产两层重构、Phase 0~3 规划与验收标准）。
- **wasm32 冒烟实证（零修改通过）**：全部 workspace crate（含 vitro_native 主 crate）`cargo check --target wasm32-unknown-unknown` 零错误；release 构建产出 3.75MB `vitro_native.wasm`；Node 实例化后经 C ABI 全链路验证（session → compile → run → get_output，输出正确）；E3070 栈缓冲区溢出等教学安全检测在 wasm 下正常触发。唯一阻碍点为 FRB 生成代码的 wasm-bindgen import 残留（C API 路径不触碰，stub 验证通过；正式修复为 `#[cfg(not(target_arch = "wasm32"))]` 门控 FRB 模块，随前端切割一并完成）。
- **AGENTS.md 项目概览重写**为三出口一核心架构（capi / wasm32 / cli-serve）+ 架构纪律（新能力先落语言中立层、三出口一套语义、capi 版本化）；旧移动端计划文档头部标注已被新计划取代。
- **记录外部 Issue（SharpTutor，已核实待修）**：A. scanf/sscanf/fscanf 格式串空白指令不跳白（`"%d %c %d"` 读 `3 + 4` 时 `%c` 捕获空格；根因 `parse_scanf_specs` 丢弃格式串空白字符，教学阻断优先级最高）；B. lambda 调用三缺陷（立即调用误报 E3045 且建议文本串行、任何实参位置调用 lambda 运行时 StoreLocal 越界——与临时槽位家族同构）；C. headless 机器可读边界提案（评估结论：capi 下沉为主 + cli serve JSON-lines，分三批补全，详见新计划 §5.3）。

### Added (教学安全检测强化：2026-09-06 审查报告"提前插入"项 V-P1-6/12/13 + 第四批 Flutter 首批)
- **V-P1-6 栈缓冲区溢出检测（E3070）**：此前 `strcpy/strcat/scanf("%s")` 的容量检查只覆盖堆 region，栈上 `char buf[4]` 被静默覆写相邻局部变量——这是教学 IDE 最需要捕获的经典错误。现由编译期登记栈缓冲区表（`FuncMeta.local_buffers`，局部数组声明时填充，经 compile_pipeline 透传至 VM，随 Call 帧克隆），宿主函数经 `check_stack_buffer_capacity` 校验并给出含变量名/容量的教学 trap。strcpy/strcat 的用户侧分发从 Bytecode Libc 路径切回 Host（libc 索引表与预编译产物不变，仅调用分发；Bytecode 版逐字节 StoreMem 无法做整体容量校验）。
- **V-P1-12 无效 free 分场景诊断**：`free(p+4)`（块内部）、`free(&栈变量)`（完全无效）此前静默"成功"——学生以为释放成功且泄漏报告不出现该块，双重误导。现按三种场景（活跃块内部/已释放块内部/无效地址）给出 E3027/E3061 教学 trap；`realloc(p, 0)` 的 free 分支同构处理。
- **V-P1-13 scanf 字符流语义**：此前每次调用整行消费（`input_index += 1`），输入 `"1 2\n3 4"` 下第二次 `scanf("%d")` 读到 3（C 流式语义应读同行剩余的 2）。现从 `(input_index, input_char_offset)` 起拼接虚拟字节流（行间补逻辑 `\n`），解析后经映射表按实际消费量推进游标——与 getchar 共享同一游标，未消费字符留给后续输入函数；`%c` 也能读到行尾字符。
- **delete/delete[] nullptr 判空（V-P1-12 暴露的存量缺陷）**：`vitro_vec` 空容器析构 `delete[] data`（data 为 0）时 `ptr-4` wrap 为 `0xFFFFFFFC` 后 free——旧行为被 free 静默忽略掩盖。现 codegen 生成 null 短路（C++ 标准要求 no-op）。
- **第四批 Flutter 首批（U-P0-1 / U-P1-9 / U-P1-10）**：
  - `WatchTab` 迁移为 `ConsumerStatefulWidget`：TextEditingController 不再在 build 中创建（每次 rebuild 泄漏一个 ChangeNotifier 且打断输入）。
  - `EditorPanelV2.dispose` 补 `_cancelLongPress()`：长按 Timer 未取消会在组件销毁后用 defunct context 弹出菜单崩溃。
  - `AutocompleteController` 补 `dispose`（取消防抖 Timer）与 `_safeNotify`（异步 gap 后守卫），销毁后不再抛断言。
- **回归测试**：`crash_regression_tests.rs` 扩展 7 个用例（12→19），覆盖三个安全检测的正反场景与 scanf 流式语义（helper 同步支持 stdin 输入与 C++ 文件名）。

### Fixed (codegen soundness：2026-09-06 代码审查报告第三批 P0 修复，8 条 P0 + 顺带 2 条 P1)
- **T-P0-1/T-P0-2 全局初始化位模式**：新增 `literal_init_bits` 统一"字面量 → 目标类型位模式"编码（含负数字面量、`Cast{字面量}` 剥包），收敛全局标量、static 局部、数组的五处初始化路径。修复：`double g = 1` 得 0（int 位写进 double 槽）、`long long ga[2] = {1,2}` 得 `0 0`（i64 写成 f64 位模式）、`double g = -2` 静默丢失。
- **T-P0-3 浮点/long long 自增自减**：`gen_mem_inc_dec` 与 Identifier 路径按类型分派 opcode（D/Q/Byte 系 + float 经 CastF2D/CastD2F 转换链）；typeck 同步放行 LongLong/Char 并把 ++/-- 结果类型改为与操作数一致（C 左值语义）。修复：`double d = 1.5; d++;` 无效、`long long q++` 被误拒。顺带修正 `(*p)++` 误用指针步长的原有错误。
- **T-P0-4 struct char 成员赋值**：assign.rs Member 分支五组 match 与 `emit_field_init` 补 `StoreMemByte/LoadMemByte`。修复：`gq.c = 'B'` 4 字节写越界覆盖相邻全局（gnext 变 0）。
- **T-P0-5 char 数组元素自增**：`cs[0]++` 改 1 字节 LoadMemByte/StoreMemByte 读改写。修复：`{255,5}` 自增后 `{0,6}` 进位污染。
- **T-P0-6 嵌套赋值地址槽**：`gen_assign` 引入嵌套深度计数 + 按深度分配地址槽（同层复用），`enter_function` 重置（与 temp_slot0~3 同机制）。修复：`a[0] += (b[0] = 5)` 写错目标。
- **T-P0-7 同名 static 跨函数共享**：`enter_function` 清空 `static_local_indices/types`。修复：两个函数各含 `static int x` 时后者读到前者的值。
- **F-P0-2 unsigned long long**：`long long` 声明不再提前 return 丢失 unsigned/const；UnsignedLiteral 按 u64 值域分派（超 i32 转 LongLiteral 保真）；lexer 的 U/u 后缀按值域升级到 LongLiteral。修复：`unsigned long long a = 4000000000ULL` 输出 -294967296。
- **F-P0-3 enum 初始化器常量折叠**：新增 `eval_enum_const`（负数/四则/位运算/比较），无法求值时报 E1006 而非静默取旧值。修复：`enum { NEG = -1, ZERO, BIG = 1+2 }` 输出 `0 1 2`（应 `-1 0 3`）。
- **T-P1-1 逻辑运算规范化**：`&&`/`||` 短路结构末尾补 `PushConst 0 / Ne`，结果恒为 0/1（`5&&3` 得 3 → 1），短路语义与浮点操作数不受影响。
- **64 位临时槽**：新增 `temp_slot_64`（8 字节，按函数重置）承载 double/long long 读-改-写中间值——4 字节槽被 64 位写踩踏曾引入 9 个 baseline 回归（链表/队列类），已在开发中捕获并修复。
- **固化回归用例** `baseline/codegen_soundness_regression.c`（10 断言组，golden 由 Clang 生成，Vitro 输出与 Clang 完全一致）；baseline 防线 314 → 317。
- **顺带修复** `infixEvaluation_default` 模板（自增/自减作数组索引的 codegen 缺陷，曾误记为模板自身栈下溢）：E2E 转绿，`KNOWN_TEMPLATE_FAILURES`（3→2）、shadow `KNOWN_FAILURE_CASES`、E2E_FAILURES.md 三处同步更新——防线 5 双向监控首次实战生效。

### Fixed (CI 门禁：2026-09-06 代码审查报告第二批 P0 修复)
- **E-P0-1 Shadow 门禁退出码**：`shadow_verify.py` 此前 `main()` 无任何非零退出路径，防线 1 在 CI 中恒绿。现与 C++ 版 `shadow_verify_cpp.py` 对齐：非预期差异（compile_gap / runtime_gap / output_gap）→ exit 1；match / known_issue / vitro_better → 通过。
- **E-P0-4 Clang 预检 fail fast**：新增 `verify_clang_available()`——Clang 缺失/异常时 exit 2 并给出明确指引（此前 runner 镜像变更导致 clang 不在 PATH 时，所有用例被吞异常归类 `vitro_better`，报告反而"更好看"）；Clang 版本串写入 JSON 报告供审计。
- **门禁化后暴露并处置 4 例存量差异**（此前被恒绿掩盖，非新回归）：
  - `kr_5_8`（output_gap）：根因是用例自身缺陷——使用 `atof` 却未 `#include <stdlib.h>`，Clang 22 下属非法隐式函数声明，被 `-Wno-implicit-function-declaration` 压制后产生 UB 输出（`0 3.14 42 -1 2.71`，排序错误）；Vitro 输出与正确编译的 Clang 完全一致。修复：用例补 `#include <stdlib.h>`，shadow 转为 match。
  - `bTree_default` / `infixEvaluation_default` / `spfa_default`（runtime_gap）：E2E 防线 `KNOWN_TEMPLATE_FAILURES` 已记录的模板已知偏差（VM 边界检查比 Clang 严格暴露模板自身越界/空指针缺陷，根因见 `E2E_FAILURES.md`）。shadow 新增 `KNOWN_FAILURE_CASES` 与该常量对齐，归类 known_issue；防线间双向监控：任一防线转绿需同步移除。
- **E-P0-2 三层对账读取 cargo 退出码**：`ci_three_tier_check.py` 此前只正则解析 `test result:` 行——cargo 编译失败/依赖拉取失败时输出无该行，返回全 0 统计被误判 PASS。现要求 `proc.returncode == 0` 且成功解析到 `test result:` 行，否则 FAIL 并打印输出尾部。
- **E-P0-3 一致性问题分级计入退出码**：`check_consistency` 拆分 hard/soft——hard（文档声明 `KNOWN_FAILURE` 但测试已全过、失败记录文件缺失）计入 CI 退出码，实现防线 5 声明的「KNOWN_FAILURE 现在通过 → 报错」方向；soft（测试失败时的记录提醒）保持 WARN 不阻塞，因文档为自由文本无法精确匹配用例名（精确对账由 `vitro_e2e.rs` 的 `KNOWN_*` 常量闭环承担）。

### Fixed (崩溃止血：2026-09-06 代码审查报告第一批 P0 修复)
- **F-P0-1 递归深度防护**：深嵌套/粘贴输入不再击穿编译器栈（SIGSEGV 无法被 catch_unwind 捕获，曾导致 IDE 直接崩溃）
  - `vitro_lexer`：`next_token` 的注释/预处理跳过分支由递归改为 `loop` 重派发（2 万行 `//c` 注释曾栈溢出）。
  - `vitro_parser`：新增共享递归深度计数器（`MAX_PARSE_DEPTH = 64`），`parse_statement` / `parse_primary` 入口防护，超限报 `E1006` 并跳到文件尾（6 万层 `{{{{`、5 万层 `((((` 曾栈溢出）。上限取 64 的依据：实测每层括号嵌套消耗 ~3KB 栈（完整优先级链 + 大体积 Expr 帧），300 层即溢出 1MB 线程栈；40 层合法嵌套实测不受影响。
  - `vitro_parser`：`DeclaratorGuard.ptr_count` 新增上限 32（`*` / `&` / `&&` 声明符），超限报 `E1007` 并吞掉剩余修饰符（10 万个 `*` 曾在后续 AST 遍历栈溢出）。
- **T-P0-8 自含 struct 环检测**：`struct S { struct S inner; };`（学生写链表节点漏 `*` 的经典错误）曾导致 `compute_type_size` 无限递归栈溢出
  - `vitro_typeck` Pass 1 新增值成员循环包含检测（含数组包裹、struct/union 互相包含），报新增错误码 `E3072_StructSelfContain` 并给出"请改用指针成员"教学提示；指针成员不构成环，合法链表不受影响。
  - `vitro_ast` / `native/src/compiler/ast.rs` 的 `compute_type_size` 引入 `visiting` 路径集合，环出现时返回 0 防崩（双处同步）。
  - `vitro_typeck` 的 `type_contains_resource` / `compute_class_has_resource` 引入 visiting 集合，循环继承（A:B 且 B:A）不再无限递归。
- **V-P0-1/2 算术溢出防护**：`INT_MIN % -1`、`LLONG_MIN / -1`、`LLONG_MIN % -1`、`-LLONG_MIN` 在 release 下曾直接 panic（Rust 溢出检查不受构建模式影响）
  - 解释器 `OpCode::Mod` / `DivQ` / `ModQ` / `NegQ` 与 JIT 模板 `tpl_div` / `tpl_mod` / `tpl_neg` 统一补齐 `MIN / -1` 与 `MIN` 取反防护，转为教学 trap 诊断（与 `Div`、`Neg` 既有防护对齐）。
- **V-P0-3 统一模式 FFI panic 防护**：`run_auto_steps` / `seek_to_step` / `step_next_unified` 三入口补 `catch_unwind`（照抄 `execute_run` 的 B47 模式），panic 不再穿越 FRB 边界（FFI panic 为 UB，曾导致 Flutter 进程 abort），且 panic 后 VM 归还 session 避免状态丢失。
- **V-P0-5 乘法溢出防护**：`host_qsort` / `host_bsearch` / VFS `fread` / `fwrite` 的 `nmemb * size` 改 `checked_mul` 并校验总量不超 VM 线性内存（`qsort(base, 2^32, 2^32, cmp)` 乘积曾 wrap 为 0 绕过边界检查，随后 `(0..2^32).collect()` 分配 ~32GB OOM abort）。
- **E-P1-6 apply_fix 中文行 panic**：诊断修复坐标在字节/字符语义混用下，含中文（UTF-8 多字节）的行按字节切片曾 panic（前端"一键修复"崩溃）。新增 `safe_byte_col`：优先按字节边界解释，非字符边界时回退按字符索引解释，任何输入不再 panic。
- **新增回归测试防线** `native/tests/crash_regression_tests.rs`（12 个用例）：上述全部复现场景固化为断言，含 3 个反向回归（40 层合法嵌套、合法链表指针不误伤）。

### Added
- **C++ 扩展 Stage A/B/C**：默认参数、嵌套类实例化、类模板非类型模板参数（NTTP）
  - 默认参数：支持函数/方法参数 `int f(int a = 0)`，调用时可省略尾部实参；TypeChecker 在普通函数调用、方法调用、无限定方法调用中统一填充默认值；修复隐式移动构造被误选为 0 参默认构造的回归。
  - 嵌套类 `Outer::Inner` 实例化：Parser 将 `Outer::Inner` 解析为 `Outer__Inner` 限定类名，`TypeChecker` 按限定名注册/查找类布局；新增 `native/tests/cases/cpp/cpp_nested_class_instance.cpp` 回归用例。
  - 类模板 NTTP：AST/Parser/TypeChecker 支持 `template<typename T, int N> class Array { T data[N]; ... }; Array<int, 5> a;`。
    - Parser：新增 `parse_template_arg_expr`，通过扫描顶层分隔符（逗号/匹配 `>`）并在截取的 token 子流中解析表达式，解决 `>` 被误解析为关系运算符的问题；正确跳过括号、方括号、花括号内的 `>`/`<`。
    - TypeChecker：`try_monomorphize_class` 构建 `type_map` 与 `value_map`；`replace_template_type` 评估 VLA 维度表达式；`replace_template_types_in_expr` 将非类型模板参数标识符替换为整数常量；`evaluate_constexpr` 支持字面量、变量、`sizeof` 与四则运算。
    - 新增 `native/tests/cases/cpp/cpp_nttp_class.cpp` 回归用例（输出 `5`）。
  - C++ Shadow Verification 扩展至 99 个用例，97 个一致 + 2 个已记录 `clang_compile_fail`（`cpp_vitro_vec_class` / `cpp_vitro_list_class`）。
- **C++ 扩展 Stage D：自定义拷贝构造函数**
  - 支持 `Class(const Class& other)` 用户定义拷贝构造函数；`Class b(a);` 与 `Class b = a;` 两种初始化语法均会调用拷贝构造。
  - TypeChecker：新增 `constructor_mangled_name` / `is_copy_constructor_param` 辅助函数；`resolve_constructor_overload` 按实参类型选择 `__ctor__{Class}__copy`；`try_process_ctor_init` 将拷贝初始化重写为拷贝构造调用；`check_assignable` 允许 `const Class&` 绑定到非 const `Class` 对象。
  - 新增 `native/tests/cases/cpp/cpp_copy_ctor.cpp` 与 `bytecode_gen_cpp_unit_test::test_cpp_copy_ctor` 回归用例（输出 `5 5 5` / `5 10 5`）。
  - C++ Shadow Verification 扩展至 100 个用例，98 个一致 + 2 个已记录 `clang_compile_fail`。
- **教学用例库大规模扩展**：继续推进维护计划任务 G，新增 LeetCode / K&R / C++ E2E 用例
  - LeetCode 防线扩展至 128 题（新增 `lc_7` Reverse Integer、`lc_67` Add Binary、`lc_83` Remove Duplicates from Sorted List、`lc_190` Reverse Bits、`lc_191` Number of 1 Bits、`lc_202` Happy Number、`lc_205` Isomorphic Strings、`lc_219` Contains Duplicate II、`lc_231` Power of Two、`lc_263` Ugly Number、`lc_292` Nim Game、`lc_345` Reverse Vowels of a String、`lc_349` Intersection of Two Arrays、`lc_367` Valid Perfect Square、`lc_383` Ransom Note、`lc_389` Find the Difference、`lc_392` Is Subsequence、`lc_401` Binary Watch、`lc_409` Longest Palindrome、`lc_412` Fizz Buzz、`lc_415` Add Strings 等）
  - K&R 新增 5 个变体：`kr_1_hello`、`kr_2_celsius`、`kr_4_atoi`、`kr_5_itoa`、`kr_6_getword`；K&R 防线扩展至 81 个用例
  - C++ E2E 新增 11 题：`cpp_pair_template`、`cpp_template_func_multi`、`cpp_reference_member`、`cpp_template_array`、`cpp_template_stack`、`cpp_unique_ptr_reset`、`cpp_class_array`、`cpp_ctor_init_list`、`cpp_reference_param_chain`、`cpp_function_overload_template`、`cpp_vitro_vec_class`；C++ E2E 防线扩展至 72 题
  - 诚实记录 Vitro C++ 子集当前已支持默认参数、嵌套类 `Outer::Inner` 实例化、类模板非类型模板参数、自定义拷贝构造函数（`vitro_vec<T>` / `vitro_list<T>` 类类型模板实参已支持）；函数模板显式 `<>` 调用等特性暂不支持
  - C Shadow Verification 更新为 616/620，C++ Shadow Verification 更新为 100 个用例（98 个一致 + 2 个已记录 `clang_compile_fail`）
- **CLI `unified` 命令支持 `--max-steps` 选项**：`vitro_cli unified <file> [--max-steps <n>]` 可自定义统一模式最大执行步数（默认 100_000），便于教学场景中长程序的时间旅行调试与性能基线测试
- **统一模式后端性能基线**：新增 `native/benches/unified_perf_baseline.c`（50 个逆序元素冒泡排序，约 10 万 VM 步）与 `scripts/unified_perf_baseline.py`，生成 `reports/unified_perf_baseline.md` 记录后端吞吐（当前约 18,500 步/秒，release 模式）
- **统一模式 frameCache 滑动窗口**：为 `UnifiedEngine.frame_cache` 引入有界滑动窗口（默认 2000 帧，超出时丢弃最早的 20%），解决长程序执行时内存无界增长问题
  - Rust 后端：`UnifiedEngine` 新增 `frame_cache_window_size`、`frame_cache_trim_ratio`、`frame_cache_start_step`；`run_batch` 自动截断，`seek_to` 支持窗口外懒加载重放
  - Dart 前端：`UnifiedState` 新增 `frameCacheStartStep`，`UnifiedNotifier` 同步后端窗口；所有读取 `frameCache[currentStep]` 的 Widget 改为按相对索引访问
  - 传输层：`AutoStepResult` / `StepStreamBatch` 增加 `cache_start_step`，`api/vitro.rs` 暴露 `get_frame_cache_start_step()`
  - `VarHistoryTab` 改为显示当前窗口内的变量历史，避免遍历全量帧
  - 新增 `native/tests/unified_engine_window_test.rs` 验证窗口化后的公共 API 行为
- **指针复合赋值运算符全面拓展**：支持指针与整数的 `+=` / `-=` 复合赋值
  - `vitro_typeck`：对 `AddAssign` / `SubAssign` 单独分支，允许左侧为完整对象类型指针（含 `void*`）、右侧为整数；函数指针、指针与指针的运算、其他复合赋值运算符保持清晰报错（`E3045_CompoundAssignType`）。
  - `vitro_codegen`：在 `gen_assign` 中提取 `ptr_step` 并在 `AddAssign` / `SubAssign` 分支中生成 `PushConst step`、`Mul`、`Add`/`Sub` 序列，复用现有标量复合赋值的左值形态处理（局部/全局/静态/解引用/成员/数组索引）。
  - 新增 9 个 `baseline/pointer_add_assign*.c` 回归用例，覆盖普通数据指针、`char*`、`double*`、`struct S*`、多级指针 `int**`、负整数偏移、结构体成员指针、`void*` 扩展以及右侧带副作用表达式。
  - 诚实记录：`void*` 算术按 GCC/Clang 扩展以 1 字节处理，严格 C 标准未定义；复合赋值表达式返回值在 Vitro 中为右值指针，与 C 标准左值语义存在差异。
- **C11 `_Generic` 泛型选择支持**：为信语言输出的类型分发提供编译期类型选择能力
  - `vitro_lexer`：新增 `TokenType::Generic` 关键字 token，映射 `_Generic`。
  - `vitro_ast`：新增 `Expr::Generic` 节点，包含控制表达式、类型关联列表与可选 `default` 分支。
  - `vitro_parser`：在 `parse_primary` 中解析 `_Generic(assignment-expr, type-name: expr, ..., default: expr)`。
  - `vitro_typeck`：对控制表达式类型执行数组到指针退化后，按精确类型匹配选择关联表达式；无匹配且无 `default` 时报 `E3004_TypeMismatch`。
  - `vitro_codegen`：直接生成选中关联表达式（或 `default`）的字节码，未选中分支不产生任何指令。
  - 新增 `baseline/c11_generic.c` 回归用例，Shadow Verification 与 Clang 输出一致（`10 1 2`）。
  - 诚实记录：当前为精确类型匹配（含数组退化），未完整实现 C11 类型兼容规则（如 `int` 与 `signed int` 兼容、qualifier 忽略等），教学场景常用类型分发足够使用。
- **C99/C11 复合字面量支持**：为信语言生成的结构体构造提供表达式级初始化能力
  - `vitro_ast`：新增 `Expr::CompoundLiteral` 节点，包含目标类型与初始化列表。
  - `vitro_parser`：在 `parse_primary` 与 `parse_unary` 的 cast 回退中识别 `(type-name) { initializer-list }`，避免与强制转换 `(Type)expr` 冲突。
  - `vitro_typeck`：对结构体/数组/标量复合字面量分别调用 `check_struct_initializer` / `check_array_initializer` / 标量赋值检查；数组未指定大小时由初始化列表长度推断并同步 `array_size` 与 `dims`。
  - `vitro_codegen`：新增 `expr/compound_literal.rs`，在栈帧上分配临时空间、调用现有局部变量初始化逻辑、在栈顶留下临时对象地址；复合字面量作为 lvalue 可用于取地址。
  - `vitro_codegen` 变量声明初始化：识别右侧 `CompoundLiteral`，数组/结构体场景直接展开为对应初始化列表，标量场景从临时地址加载值后存储。
  - 新增 `baseline/compound_literal.c` 回归用例，Shadow Verification 与 Clang 输出一致（`1 5 20 7`）。
  - 诚实记录：复合字面量生命周期简化为当前块结束；未完整实现 C11 所有类型兼容/qualifier 规则；复杂嵌套 designated initializer 按教学子集处理。

### Fixed (模板系统修复与测试框架)
- **模板系统全面修复**：修复点击模板后无法退出、C++ 模板无法加载、覆盖率显示超过 100% 等问题
  - `TemplateLoader` 现在读取 `index.json` 的 `ext` 字段，正确加载 `.c` 与 `.cpp` 模板；源码缺失时抛出 `TemplateLoadException` 而不是静默跳过。
  - `CodeTemplate` 新增 `ext` 字段；`completeTutorial` 根据模板扩展名将当前文件切换为 `main.c` 或 `main.cpp`，确保 Rust 后端按正确语言模式编译。
  - `IdeState.copyWith` 新增 `clearActiveTutorial` 标志，修复 `activeTutorial: null` 无法清除教程状态的问题；教程模式下隐藏 `ExecutionControlPanel`，避免上一段运行的残留进度条/覆盖率造成“无法退出模板”的错觉。
  - `ExecutionControlPanel._buildCoverageText` 前端过滤超出当前源码行号范围的 heatmap 条目，解决覆盖率显示超过 100%（如 633.3%）的问题。
    - **诚实记录**：这只是前端绕过，热力图底层仍混有标准库/预编译字节码行号。完整修复需要给 `vitro_shared::SourceLoc` 增加文件标识字段，并在 VM 执行层只记录用户主文件行号；~~当前因改动面大、回归风险高而未实施~~ **已实施**，详见 `docs/current/TEMPLATE_GUIDE.md`。
- **彻底修复覆盖率超过 100% 的绕过问题**：从 VM 层区分用户源码与标准库/预编译字节码行号，移除前端过滤 workaround。
  - 给 `vitro_shared::SourceLoc` 增加 `file_id: i32` 字段（0 为用户主文件，非 0 为外部文件），并通过 `#[serde(default)]` 保持与旧 `bytecode_libc_data.json` 产物的兼容。
  - `vitro_vm::bytecode_libc_loader` 加载预编译产物后，将所有 libc 指令的 `loc.file_id` 置为 1。
  - `vitro_vm::core::executor` 记录 heatmap 时只统计 `file_id == 0` 的指令，从源头避免 Bytecode Libc 行号混入。
  - Flutter 端 `ExecutionControlPanel._buildCoverageText` 移除按 `totalLines` 过滤的绕过逻辑；覆盖率百分比现在真实反映用户代码执行情况。
  - 同步清理已知失败：`threadedBinaryTree_default` 已因模板源码修复（标准头节点法遍历）通过，从 `KNOWN_TEMPLATE_FAILURES` 与 `E2E_FAILURES.md` 中移除并归档。
- **模板源码缺陷修复**
  - `factorial` / `fib`：在函数调用处补充 `/*__PARAM_n__*/` 占位符，与 `meta.yaml` 参数声明一致。
  - `merge`：调整函数顺序，避免 Clang 报 `merge` 隐式声明错误。
  - `threadedBinaryTree`：改用标准头节点法遍历，修复原线索化遍历无限循环问题。
- **模板测试防线**
  - 新增 `scripts/test_templates.py`：校验模板目录结构、meta.yaml、占位符与参数一致性、Flutter assets 同步。
  - 新增/扩展 Dart 测试：`template_loader_test.dart`、`ide_template_bar_test.dart`、`ide_notifier_test.dart` 中 `completeTutorial` 的文件扩展名切换测试。
  - CI 在 Rust job 中加入 `python scripts/test_templates.py`。
  - 新增 `docs/current/TEMPLATE_GUIDE.md` 记录模板规范、同步机制、测试防线与诚实修复记录。

### Changed (Workspace 模块化拆分)
- **Rust 后端单 crate 拆分为多 crate workspace**：在 `native/Cargo.toml` 建立 `[workspace]`，将编译器/运行时各阶段下沉为独立 crate，降低编译缓存粒度与模块耦合
  - 新增 `crates/vitro_shared`（`SourceLoc`、`ErrorCode` 等共享基础类型）
  - 新增 `crates/vitro_ast`（AST 节点与类型系统）
  - 新增 `crates/vitro_runtime`（`RuntimeState`/`MemoryState`、符号表、内存布局常量、`unified` 基础数据）
  - 新增 `crates/vitro_vm`（VitroVM、host 函数、VFS、JIT、快照）
  - 新增 `crates/vitro_lexer`（词法分析器）
  - 新增 `crates/vitro_parser`（语法分析器）
  - 新增 `crates/vitro_cpp_frontend`（C++ 内置容器布局与类型映射）
  - 新增 `crates/vitro_typeck`（类型检查器）
  - 新增 `crates/vitro_codegen`（字节码生成器）
  - 新增 `crates/vitro_algorithm_steps`（算法步骤语义标注）
  - `vitro_native` 通过 `pub use vitro_xxx as xxx;` 保持既有 `crate::compiler::xxx` / `crate::vm::xxx` / `crate::unified::algorithm_steps` 路径兼容
  - `CheckpointManager` 从 `native/src/unified/checkpoint.rs` 下沉到 `vitro_vm::snapshot`，签名去除 `Session`/`StepMeta` 依赖
  - 引入 `VmContext` 替代部分 `Session` 上帝对象，切断 `vm` 与 `session` 的循环依赖
  - 受 FRB 孤儿规则与 `Session` 耦合限制，`native/src/unified/`（含 `StepPayload` 等 FRB 导出类型）、`native/src/engine/`、`native/src/api/`、`native/src/diagnostics/` 暂保留在 `vitro_native` 内部，已诚实记录为后续拆分障碍

### Changed (架构重构)
- **内置容器布局解耦（CPP_BUILTIN_LAYOUT_DECOUPLING_PLAN）**：将 `vector<int>`/`vector<float>`/`vector<char>`/`string`/`list<int>` 的布局与方法签名从 Rust 硬编码迁移到 `.cpp` 接口声明文件
  - 新建 `native/runtime_libc/vitro/{vector_int,vector_float,vector_char,string,list_int}.cpp` 作为唯一真相来源，通过 `clang++ -fsyntax-only` 语法验证
  - 新增 `scripts/extract_cpp_builtin_layout.py` 轻量解析脚本，从 `.cpp` 提取字段、方法签名并生成 `native/src/compiler/cpp_frontend/builtin_layout_data.json`
  - 重写 `builtin_layout.rs`：改为 `include_str!("builtin_layout_data.json")` + `LazyLock` 加载，零硬编码容器信息
  - 重写 `type_map.rs`：改为 JSON 加载 `cpp_type_to_vitro` / `map_container_method`，零硬编码方法映射
  - `codegen/mod.rs` 与 `typeck/cpp_class_layout.rs` 中的硬编码 `container_mappings` 列表改为动态遍历 `builtin_class_mappings()`
  - `scripts/precompile_bytecode_libc.py` 扩展 glob 支持 `.cpp`（当前仅识别，不预编译为字节码）
  - 删除已废弃的 `native/runtime_libc/vitro/layouts.toml`
  - 全部 600+ 测试通过，零回归

### Fixed (标准库 I/O 行为修复)
- **修复 `fputs(str, stdout)` 无输出**：`crates/vitro_vm/src/host/file.rs` 的 `host_fputs` 现在识别 lexer 预定义的 `stdout`(1)/`stderr`(2) 宏 fd，将字符串直接追加到 `RuntimeState.output_lines`；普通 `FILE*` 文件流写入行为保持不变；新增 `end_to_end_extra_test::test_e2e_fputs_stdout` 回归用例
- **修复 `fclose` 后 VFS `FILE*` 被误报为内存泄漏**：`crates/vitro_vm/src/host/file.rs` 的 `host_fclose` 现在除关闭 VFS 文件描述符外，还会释放 `host_fopen` 在 VM Heap 中为 `FILE*` 结构体分配的 4 字节内存；stdout/stderr 等非堆分配 stream 找不到对应 region 时安全忽略；新增 `native/tests/cases/baseline/fclose_leak.c` 回归用例

### Fixed (VLA 运行时边界检查)
- **修复 VLA 数组索引缺失边界检查**：`vitro_codegen::expr::gen_index` 现在对首维为变量表达式的 VLA 生成运行时边界检查；新增 `TrapBoundsVla` opcode（值为 129），在索引前将 VLA 维度表达式求值并压栈，VM 运行时将索引与该运行时边界比较，越界时触发教学诊断；新增 `native/tests/cases/baseline/vla_bounds.c` 回归用例。参数退化为指针的 VLA 形参仍无法在调用点获知边界，保持跳过。

### Fixed (参数化宏扩展支持)
- **修复参数化宏调用后带分号无法解析**：`vitro_lexer` 在参数化宏展开时，若宏体为大括号块且调用位置后紧跟分号，则动态将宏体包装为 `do { ... } while(0)`，使 `SWAP(int,x,y);` 在 `if/else` 等语句中可正确解析；新增 `native/tests/end_to_end_extra_test.rs::test_e2e_parametric_macro_swap_semicolon` 回归测试。⚠️ 此为 Vitro 教学子集扩展，Clang 标准模式仍报"预期表达式"；若需严格兼容 Clang，建议宏体手动使用 `do { ... } while(0)`。

### Changed (工程质量)
- **拆分 `native/src/unified/trace_analyzer.rs` 继续推进维护计划任务 B**：将 838 行的统一模式根因推断模块按运行时陷阱类型拆分为 `trace_analyzer/bounds.rs`（数组越界 / `BoundsCategory` 推断）、`trace_analyzer/use_after_free.rs`、`trace_analyzer/double_free.rs`、`trace_analyzer/div_zero.rs`、`trace_analyzer/null_deref.rs`、`trace_analyzer/utils.rs`（共享工具 / `LoopInfo`）、`trace_analyzer/tests.rs`（单元测试），入口文件 `trace_analyzer/mod.rs` 仅保留 `TraceAnalyzer::analyze_trap` 分发逻辑（55 行）；所有子文件 <800 行，C/C++ Shadow Verification 无新增失败
- **生产代码 `unwrap`/`expect` 收敛**：继续推进维护计划任务 C，移除 5 处生产路径 `unwrap`
  - `vitro_codegen::lib.rs` 类大小拓扑计算：将 `class_defs.get(class_name).unwrap()` 改为 `if let Some(class)` / `continue`
  - `vitro_codegen::expr::call.rs`：`gen_call` / `gen_call_ptr` 中结构体/类返回值临时偏移从 `ret_temp_offset.unwrap()` 改为 `if let Some(offset)`，删除冗余 `is_struct_ret` 变量
  - `vitro_codegen::expr::struct_.rs`：类方法调用返回值临时偏移同样改为 `if let Some(offset)`
  - 生产代码 `unwrap`/`expect` 从 17 处降至 0 处，全量从 45 处降至 28 处
  - 确认 `templates/bTree/source.c` 的 `bTree_default` 运行时缺口为模板代码访问未初始化子节点指针的已知偏差（`E2E_FAILURES.md` 已记录为 `KNOWN_DIVERGENCE`），与本次 unwrap 收敛无关

### Added (C++ const 引用参数)
- **支持 `const T&` 函数/方法参数绑定到右值**：此前 `const int& x` 参数只能绑定左值变量，绑定字面量或表达式右值会在 CodeGen 阶段失败。修复分为 TypeChecker 与 CodeGen 两层：
  - `vitro_typeck::decl.rs` / `expr/mod.rs` / `expr/call.rs`：统一函数调用、方法调用、函数指针调用的参数检查，对 `const T&` 形参允许右值实参隐式取地址；对非 const 引用形参绑定右值给出明确错误诊断。
  - `vitro_codegen::expr::unary.rs`：`UnaryOp::Addr` 对字面量 / 调用返回值等右值表达式自动物化临时局部变量（`StoreLocal`/`StoreLocalD`/`StoreLocalQ`），再返回临时变量地址，使被调用函数可通过引用安全读取。
  - `vitro_ast::types.rs` 新增 `is_const_reference()` 辅助方法；const 判断同时兼容 `const int&`（const 在 base）与 `int const&`（const 在引用）两种写法。
  - 新增 `native/tests/cases/cpp/cpp_const_reference_param.cpp` 回归用例，覆盖字面量、变量、表达式右值三种绑定场景。

### Added (C++ 内置容器类类型模板实参)
- **支持 `vitro_vec<T>` / `vitro_list<T>` 类类型模板实参**：`crates/vitro_typeck/src/cpp_monomorph.rs` 新增 `try_synthesize_builtin_container_class` / `synthesize_vec_class` / `synthesize_list_class`，当内置容器 `vitro_vec<T>` / `vitro_list<T>` 的模板实参为类类型时，合成走普通类模板路径的容器实例化
  - `vitro_vec<T>`：默认构造、析构、`size()`、`get(int)`、`push_back(T)`，自动扩容与元素拷贝/析构
  - `vitro_list<T>`：合成辅助节点类 `vitro_list_node<T>`，支持默认构造、析构、`size()`、`get(int)`、`push_back(T)`、自动节点释放
  - `crates/vitro_codegen/src/expr/new_delete.rs` 修复 `delete[]` 释放逻辑：无论元素类型是否有显式析构函数，都必须释放 `new[]` 返回地址前 4 字节处的 `base` 地址，避免类类型数组泄漏
  - `crates/vitro_codegen/src/lib.rs` 修复类大小拓扑计算：字段类型为类类型时，必须等依赖类大小计算完成后才计算当前类，避免合成嵌套类（如 `vitro_list_node<T>`）时因依赖类尚未入 `class_sizes` 导致大小为 0
  - `crates/vitro_parser/src/cpp.rs` 透传类类型模板实参
  - 新增 `native/tests/cases/cpp/cpp_vitro_vec_class.cpp` / `cpp_vitro_list_class.cpp` 与 golden，验证 `push_back` / `get` / 自动构造析构
  - `scripts/shadow_verify_cpp.py` 支持首行 `// category: gap` 标记，用于 Clang++ 无法直接编译的 Vitro 内置容器用例

### Fixed (变参函数支持)
- **修复 `va_list` / `va_start` / `va_arg` / `va_end` 自定义变参函数不支持**：
  - 根因是 Parser 将函数调用统一解析为 `Expr::CallPtr`，而 `vitro_codegen::expr::call` 仅在 `gen_call` 中处理变参 `CallVar`，导致变参调用走普通 `Call` 指令，只弹出命名参数；修复方案为在 `gen_call_ptr` 中同步识别变参函数并生成 `PushConst total_arg_words` + `CallVar`。
  - 修复 `CallVar` 总参数 word 数计算：对变参实参按实际 `type_size` 计算 word 数（支持 `double`/`long long` 等 8 字节类型），并对 `float` 等类型应用 C 默认实参提升（`float` → `double`，`char` → `int`）。
  - 修复 `double`/`long long` 变参在栈帧中的存储顺序：codegen 对变参 callee 的 8 字节实参使用 `StoreLocalD/Q` + 高低 32 位分段加载，保证 VM `do_call_inner` 顺序存储后内存为小端布局。
  - 调整 `stdarg.h` 与 lexer 预定义宏：`__vitro_va_arg` 返回 `void*`，`va_arg(ap, type)` 宏展开为 `*(type*)__vitro_va_arg(&(ap), sizeof(type))`，从而直接按目标类型位模式读取内存。
  - 修复 `gen_expr_with_cast` 对 `long long` 目标类型的错误截断：原实现对所有非浮点目标都把 `LongLong` 表达式截断为 `int`，导致 `long long total = total + x;` 等赋值只保留低 32 位；改为传递完整目标类型，仅在目标为 `int`/`char` 时才截断。
  - 修复复合赋值（`+=`/`-=`/`*=`/`/=`）对 `long long` 使用 32 位指令的问题：在 `gen_assign` 的复合赋值闭包中为 `left_is_long_long` 分支添加 `AddQ`/`SubQ`/`MulQ`/`DivQ`。
  - 新增 `native/tests/cases/baseline/variadic.c` 回归用例，覆盖 `int`/`double`/`long long` 变参求和。

### Fixed (类型系统行为修复)
- **修复函数返回 `double` 值异常**：根因是 `return` 语句未对返回值表达式插入隐式类型转换，`return 2.5;` 中的 `2.5` 被解析为 `float` 字面量，导致返回类型为 `double` 时生成 `PushConstF` 而非 `PushConstD`。修复方案为 `vitro_typeck::decl.rs` 在 `return` 语句 `check_assignable` 成功后调用 `insert_implicit_cast`，并新增 `native/tests/cases/baseline/float_func_return.c` 回归用例；`native/tests/cases/leetcode/lc_4.c` 恢复为原始 `double` 返回实现

### Fixed (标准库 I/O 行为修复)
- **修复 `scanf`/`sscanf` 的 `%s` 格式符不支持**：`crates/vitro_vm/src/host/io.rs` 的 `host_scanf_n`/`host_sscanf` 现在处理 `'s'` 格式符，跳过前导空白、读取非空白字符序列并以 `'\0'` 结尾写入目标缓冲区；新增 `native/tests/cases/baseline/scanf_string.c` 回归用例

### Fixed (代码生成行为修复)
- **修复复合副作用数组索引触发 NULL 指针陷阱**：形如 `a[++i] = b[j--]` 的表达式在 Clang/GCC 下正确，但 Vitro 运行时访问 NULL 指针区域。根因是 `crates/vitro_codegen/src/expr/unary.rs` 的 `gen_mem_inc_dec` 与 `gen_assign` 的 Index 赋值复用 `temp_slot0`，右侧索引副作用覆盖了左侧地址临时变量。修复方案为 `gen_mem_inc_dec` 改用 `temp_slot3` 保存新值；新增 `native/tests/cases/baseline/side_effect_index.c` 回归用例

### Fixed (自定义头文件 include 支持)
- **修复 `#include` 非标准库路径不支持**：`#include "header.h"` 现在可基于源文件所在目录加载自定义头文件；`Lexer` 新增 `base_path` 字段与 `with_mode_and_path` 构造函数，`compile_pipeline.rs` 从首个编译单元文件名提取目录传入；`shadow_verify.py` 与 `vitro_e2e.rs` 改用真实源文件路径调用 `vitro_compile_unit`，使 Shadow Verification 与 E2E 测试中的 include 行为与 Clang 一致。新增 `native/tests/cases/baseline/include_custom_header.c` / `include_custom_header.h` 回归用例

### Fixed (Shadow Verification 完整修复)
- **C Shadow 匹配率从 498/511 提升至 505/511（98.8%）**：编译缺口与输出差异归零
  - **支持 `__asm__("...")` GCC 风格内联汇编占位**：`parser/expr.rs` 在 `parse_primary` 中识别并消费语法，返回 void 字面量，不生成汇编代码
  - **支持 `_Static_assert(expr, "msg")`**：`parser/mod.rs` 新增 `parse_static_assert`，在顶层与语句层均可消费，教学子集暂不做编译期求值
  - **支持 `typeof(expr)` 类型说明符**：`parser/mod.rs` 识别 `typeof`/`__typeof__`/`__typeof` 并解析表达式；`ast.rs` 新增 `Type::Typeof`；`typeck/decl.rs` 在变量声明时根据初始化表达式推断实际类型
  - **按需注入 Clang 前向声明修复 `kr_5_8`**：`shadow_verify.py` 的 `make_clang_header` 仅对源码中实际使用的 `atof`/`atoi`/`atol`/`exit` 注入最小前向声明，避免完整 `stdlib.h` 与 K&R 自定义 `itoa`/`qsort` 冲突
  - **完整实现 VFS Windows 文本模式换行转换**：`native/src/vm/vfs.rs` 区分 `"r"`/`"w"` 与 `"rb"`/`"wb"`；写入时 `\n` → `\r\n`，读取时 `\r\n` → `\n`；`fseek`/`ftell` 区分逻辑/物理光标以匹配 Windows CRT 行为
  - **Shadow Verification 用例间文件隔离**：每次用例运行前重置 `test.txt`/`numbers.txt` 为 Vitro 注入的预设内容，避免 Clang 读取上一个用例遗留文件
  - **诚实记录剩余 3 个运行时差异**：`bTree_default`（未初始化指针）、`infixEvaluation_default`（栈下溢）、`spfa_default`（队列越界）已更新为模板代码缺陷分类，Vitro 的边界/NULL 检测作为教学核心特性保持不变

### Fixed (代码审查报告推进)
- **移除生产代码中的调试输出**：删除 `capi/mod.rs` 中 `CAPI: calling run_multi_file_pipeline` 与 `DUMP: VarDecl` 的 `println!`，以及 `engine/compile_pipeline.rs` 中对 `dump_var_decls` 的调用，避免污染程序 stdout 导致 Shadow Verification 误判
- **修复 `printf`/`putchar` 输出缓冲行为**：`RuntimeState::output()` 从 `output_lines.join("\n")` 改为 `join("")`，与 C 标准一致：只有格式字符串显式包含 `\n` 或调用 `puts` 时才换行，不再为每次 `printf` 自动换行
- **struct 体支持多字段声明**：`parser/mod.rs` `parse_struct_body` 改为先 `parse_base_type` 再 `parse_declarator`，并支持逗号分隔的多个声明符（如 `int u, v, w;`）
- **支持 `typedef enum { ... } Alias;`**：新增 `parse_typedef_enum_decl`，解析匿名枚举 typedef；顶层 Enum 分支改为可选消费 `Identifier`
- **支持匿名 `enum { ... };` 声明**：移除顶层 Enum 分支对枚举名的强制要求
- **三目运算符支持数组到指针的通常转换**：`typeck/expr.rs` 对三目分支中的 `Array` 类型统一 decay 为指向元素的指针，使 `" "`（char[2]）与 `""`（char[1]）可统一为 `char*`
- **回归测试扩展**：`parser_unit_test` +3、`type_checker_unit_test` +1、`end_to_end_extra_test` +1
- **Flutter 测试金字塔**：新增 10 个测试文件、90 个测试 + 4 个集成测试
  - `test/models/ide_state_test.dart`：默认值、copyWith、hasErrors/hasWarnings
  - `test/models/unified_state_test.dart`：默认值、copyWith、ExecutionPhase getter 矩阵
  - `test/models/code_template_test.dart`：占位符替换、默认参数、模型字段
  - `test/providers/theme_notifier_test.dart`：主题切换
  - `test/providers/ide_notifier_test.dart`：build、文件管理、面板管理、watch 表达式、学习进度、教程
  - `test/providers/unified_notifier_test.dart`：build、播放控制、onCodeChanged
  - `test/services/learning_progress_service_test.dart`：SharedPreferences load/save/clear、非法 JSON 回退
  - `test/widgets/custom_keyboard_test.dart`：字母/数字/符号模式、配对键、Shift、Space、滚动
  - `test/widgets/file_tab_bar_test.dart`：渲染、切换、关闭按钮、关闭回调、新建文件
  - `test/widgets/tool_button_test.dart`：图标渲染、点击、禁用、自定义颜色
  - `integration_test/app_test.dart`：端到端 smoke 测试，覆盖应用启动、核心 UI 渲染、主题切换、底部 Tab 切换、新建文件
  - 添加 `mocktail: ^1.0.4` 到 `pubspec.yaml` 作为未来 mock Rust API 抽象层的基础
  - 测试揭露并修复：`closeFloatingPanel` 因 `IdeState.copyWith` 的 null 语义无法清除 `activeFloatingPanel`
  - 测试揭露并修复：`PanelItem` 缺失 `intent` 定义导致默认底部 Tab "意图" 无法渲染
  - 测试揭露并修复：`EditorPanelV2` 初始 build 时访问尚未 attach 到 ScrollView 的 `ScrollController.offset`
  - 集成测试适配：`lib/main.dart` 中 `RustLib.init()` 增加幂等保护，避免多个 `app.main()` 调用触发 "Should not initialize flutter_rust_bridge twice"
- **CI Windows 构建修复**：`.github/workflows/ci.yml` 在 `flutter build windows` 前清理 `build/windows/x64` 缓存，避免 CMake 使用缓存中的 `Visual Studio 16 2019` generator 导致在仅有 VS2022 的 runner 上失败
- **Rust 测试 warnings 清理**：`native/tests/b10_new_array_rollback.rs` 移除未使用导入；`native/tests/test_utils.rs` 添加 `#![allow(dead_code)]`
- **失败记录同步**：`bellmanFord_default` 从 `KNOWN_TEMPLATE_FAILURES` 移除；`kr_5_16` 从 `KNOWN_KR_FAILURES` 移除；更新 `E2E_FAILURES.md` / `KR_FAILURES.md`
- **修复 CLI 诊断级别显示错误**：`native/src/bin/vitro_cli.rs` 将 `Diagnostic.severity` 映射修正为 `0=错误/1=警告/2=提示`，与后端 `push_diagnostics/push_warnings/push_hints` 及 Flutter 前端 `DiagnosticInfo` 语义一致
- **抑制 W3052 数组 decay 过度 warning**：`native/src/compiler/typeck/mod.rs` 移除对正常数组到指针隐式转换的 warning，仅保留 `sizeof(数组参数)` 场景下的专门 warning，避免 K&R 标准代码产生噪音诊断
- **确认 K&R `kr_5_8` / `kr_5_14` 已恢复匹配**：经 Clang 与 Vitro 单独 Shadow 验证，两者均为 `match`；原代码审查报告将其标为 `unknown` 编译缺口的状态已过时
- **VFS 文本模式换行转换列为已知限制**：不在虚拟文件系统中模拟 Windows CRT 的 `\n` ↔ `\r\n` 转换，`vfs_io_extensions` / `file_fread` 的输出差异保留为诚实记录
- **修复全局变量区与字符串字面量区内存重叠**：`native/src/compiler/codegen/mod.rs` 延迟分配全局初始化中的 `StringLiteral` 地址；`stmt.rs` / `expr.rs` 的字符串分配改用 `next_global_offset`，确保字符串区位于全局变量区之后
  - 修复 K&R `kr_6_1` 中 `struct key keytab[]` 的 `char*` 成员被字符串内容覆盖的问题
  - 将 `kr_6_1` 从 `KNOWN_KR_FAILURES` 移除并更新 `KR_FAILURES.md`
- **新增 `vitro_set_input_mode` C API**：支持批量/交互输入模式切换；Shadow Verification 脚本统一设 Batch 模式，使 `getchar` 在输入耗尽后返回 EOF，与 Clang 在无输入时行为一致
  - 解锁 `kr_1_*`、`kr_4_*`、`kr_5_*`、`kr_6_*` 等 31 个 K&R 运行时缺口用例
- **精简 Shadow Verification 的 Clang 头文件注入**：`CLANG_HEADER` 不再包含 `stdlib.h` / `string.h`，避免 K&R 示例中用户自定义 `itoa` / `qsort` 与标准库声明冲突
  - 消除 `kr_3_4`、`kr_3_6`、`kr_4_9`、`kr_4_10` 的 `vitro_better` 差异
- **Parser 支持函数指针类型转换（cast）的抽象声明符**：`parser/expr.rs` 的 `parse_type_only` 改为调用 `parse_abstract_declarator`，使 `(int (*)(void *, void *))func` 这类类型转换可被正确解析
  - 解锁 K&R `kr_5_8`（函数指针 qsort 比较器）与 `kr_5_14`（排序字段选项）
  - `kr_5_8` 的 `cases_golden/knr/kr_5_8.out` 已按 Clang + `<stdlib.h>` 重新生成
  - 新增 `parser_unit_test.rs` 回归测试 `test_parser_function_pointer_cast_type`
- **VM 支持 `main(int argc, char *argv[])`**：
  - 新增 `OpCode::PushArgc` / `PushArgv`，VM 在全局数据区后为 argv 分配内存并记录地址
  - `compiler/codegen/mod.rs` 的入口包装代码根据 `main` 参数个数自动推送 `argc`/`argv`
  - `engine/compile_pipeline.rs` 的 `setup_vm` 调用 `vm.setup_argv`
  - `flutter_bridge.rs` 新增 `set_argv`，`capi/mod.rs` 新增 `vitro_set_argv`
  - `vitro_cli run` 支持 `-- arg1 arg2 ...` 传递命令行参数
  - 解锁 K&R `kr_5_10`（echo 命令行参数）；单独 Shadow 验证为 `match`
  - 新增 `end_to_end_extra_test.rs` 回归测试 `test_e2e_main_args` / `test_e2e_main_no_args`
- **Shadow Verification 状态更新**：匹配数从 412 提升至 415；编译缺口从 5 降至 3（仅剩 `inline_asm`/`static_assert`/`typeof_operator` 三个已知不支持特性）；运行时缺口从 31 降至 30
- **K&R 失败记录更新**：`KR_FAILURES.md` 中 `kr_5_8`/`kr_5_10`/`kr_5_14` 标记为已修复；剩余已知失败仅 `kr_6_1`
- **清除 MAUI 前端遗留的死 C API 代码**：`native/src/capi/mod.rs` 从 1384 行精简至约 290 行
  - 删除未使用的会话快照/恢复：`SessionSnapshot`、`vitro_session_save`、`vitro_session_load`
  - 删除未使用的 buf 版本错误获取：`vitro_get_compile_errors_buf`、`vitro_get_runtime_error_buf`
  - 删除未使用的单步/状态查询 API：`vitro_step_next`、`vitro_get_current_line`、`vitro_callstack_count`、`vitro_callstack_get`、`vitro_breakpoint_add`/`remove`/`clear`、`vitro_input_count`
  - 删除未使用的内存/变量/可视化/算法诊断 API：`vitro_memory_region_count`/`get`、`vitro_memory_get_value`/`pointer_target`、`vitro_diagnostic_count`/`get`/`get_fix`、`vitro_sourcemap_lookup`、`vitro_trace_count`/`get`、`vitro_variable_count`/`get`/`get_type`/`find_by_addr`/`get_field`、`vitro_vis_event_count`/`get`/`get_ex`/`clear`、`vitro_algorithm_match_count`/`get`/`vis_event_count`/`vis_event_get`
  - 保留的 API（Shadow Verification + 测试实际使用）：`vitro_session_create`/`destroy`、`vitro_compile`/`compile_unit`/`compile_all`、`vitro_get_compile_errors`、`vitro_set_argv`、`vitro_run`、`vitro_get_runtime_error`、`vitro_set_input`、`vitro_is_waiting_input`、`vitro_provide_input_line`、`vitro_get_output_length`/`get_output`
  - 移除因此变为死代码的辅助函数 `write_str` 和未使用的 `VitroVM`/`setup_vm`/`reset_runtime_for_step`/`inject_preset_files` 导入

### Fixed (代码审查报告继续推进)
- **删除 `InitElement` 的 `Deref`/`DerefMut`（B25）**：`native/src/compiler/ast.rs`
  - 避免 `*init_elem` 隐式解引用到 `Expr` 时丢失 `designators` 信息
  - 同步修复 `algorithm_detector.rs`、`codegen/{mod,expr,stmt}.rs`、`data_flow.rs`、`intent.rs`、`typeck/{mod,expr}.rs` 中 23 处隐式解引用调用，全部改为显式访问 `.value`
- **不兼容指针类型赋值报告 warning（B39）**：`native/src/compiler/typeck/mod.rs`
  - `check_pointer_assignable` 在双指针分支中比较 `pointee` 类型；`void*` 与具体指针互转仍允许并给出 hint
  - 对 `int* p = (double*)&x;` 等不兼容赋值报告 `W3053` warning，但允许编译继续
- **`printf`/`scanf`/`fprintf` 参数不足前置校验（B43）**：`native/src/vm/host_funcs.rs`
  - `host_printf_n` / `host_scanf_n` / `host_fprintf_n` 在按格式字符串 pop 参数前，先检查栈深度是否足够
  - 不足时一次性 trap 并给出明确错误信息，避免多次 `pop()` 下溢产生重复/混乱的运行时错误
- **多维 VLA `array_size` 避免负数（B27）**：`native/src/compiler/parser/mod.rs`
  - 当内部数组大小未指定（`inner_array_size <= 0`）时，不再让 `size * inner_array_size` 产生负值
- **VM 调用帧初始化确认走统一内存检查路径（V9/V10）**：`native/src/vm/vm/mod.rs` + `vm/vm/executor.rs`
  - 复核 `call_user_function` 与 `do_call` 对局部变量的清零/参数写入均已通过 `store_i32`/`store_i8`，自然经过 `check_mem_access` + `check_uaf`，无需额外修改
- **回归测试扩展**：`type_checker_unit_test.rs` +1（不兼容指针赋值 warning）；`host_contract_tests.rs` +2（printf/scanf 参数不足 trap）
- **Shadow Verification 实测**：450 match / 3 compile_gap / 3 runtime_gap / 3 output_gap；`bTree_default` 为 pre-existing runtime_gap（HEAD 已存在），与本次改动无关

### Fixed (代码审查报告继续推进 — 第二轮)
- **`ERROR_CONCEPT_MAP` 键 3035 重复与映射语义修正（B52）**：`native/src/diagnostics/knowledge_graph.rs`
  - 删除对 3035 的重复 `HashMap::insert`
  - 将 3030-3035（printf/scanf family）统一映射到 `FunctionCall`/`ParameterPassing`，替代原先不准确的 `ArithOp`
- **If 条件块不再克隆整棵 AST 子树（B35）**：`native/src/compiler/cfg.rs`
  - 条件基本块 `stmts` 改为只保留 `Stmt::Expr { cond, loc }` 占位，避免 CFG 冗余存储 then/else 子树
- **Return 块不再被误加 fall-through 边（B36）**：`native/src/compiler/cfg.rs`
  - `build_seq` 中顺序 fall-through 边仅对 `Terminator::FallThrough` 添加；`Return` 不再向后连接
- **`analyze_live_variables` 预计算出边邻接表（B37）**：`native/src/compiler/data_flow.rs`
  - 将单次迭代从 O(N×E) 降至 O(E)，大 CFG 分析显著加速
- **回边检测复用 `cfg.find_loops()`（B38）**：`native/src/compiler/intent.rs`
  - 移除依赖块 ID 分配顺序的 `a >= b` 判断，避免前向边被误判为回边
- **extra_vars 构造函数初始化同样插入 this 指针（B40）**：`native/src/compiler/typeck/decl.rs`
  - 提取 `try_process_ctor_init`，统一处理 `Foo a(1), b(2);` 等多变量构造函数初始化
- **`execute_run` 用 `catch_unwind` 保护 take 后的 VM（B47）**：`native/src/engine/session_ops.rs`
  - `setup_vm`/`inject_preset_files`/`vm.run` 中若发生 panic，VM 仍会被还回 `session.vm`，避免永久丢失
- **`unsigned int` 参数类型解析验证（B48）**：`native/tests/completion_unit_test.rs`
  - 新增测试验证 `find_variable_type` 对带空格类型名（如 `unsigned int x`）的正确解析
  - `native/src/engine/completion/mod.rs` 将 `mod candidates` 改为 `pub mod candidates` 以便测试访问
- **回归测试扩展**：`cfg.rs` +2、`data_flow.rs` +1、`intent.rs` +1、`typeck_cpp_unit_test.rs` +1、`completion_unit_test.rs` +1

### Optimized (性能优化 — 代码审查报告 O1/O4)
- **`Type::mangle_name` buffer 复用**：`native/src/compiler/ast.rs`
  - 新增 `mangle_name_into(&self, buf: &mut String)`，所有分支直接向 buffer 写入，消除嵌套类型递归中 O(n²) 的临时 `String` 分配
  - 保留 `mangle_name() -> String` 作为便捷封装，内部调用 `mangle_name_into`
  - 模板实例化、函数指针、多维数组等复杂类型的命名生成分配显著下降
- **VM 单步回退快照 buffer 复用**：`native/src/vm/vm/mod.rs` + `native/src/unified/engine.rs`
  - 新增 `VitroVM::snapshot_into(&self, session, target: &mut VMSnapshot)`，复用 `target` 已有的 1MB `Vec<u8>`，仅执行 `copy_from_slice`，避免 `run_batch` 每步分配新 1MB buffer
  - `UnifiedEngine` 新增私有字段 `pre_step_snap: Option<VMSnapshot>`，首次 step 分配后后续复用
  - `CheckpointManager` 已有的 `snapshot_incremental` 检查点策略保持不变；本优化专门解决 Trap 回退快照的分配热点
  - 统一模式长程序（如 10 万步排序可视化）的堆分配流量不再随步数线性增长 1MB/步
- **回归测试扩展**：`native/tests/ast_unit_test.rs` +2（mangle_name_into 等价性与追加行为）；`native/tests/test_snapshot.rs` +1（snapshot_into 等价性与 buffer 复用）
- **JIT Trace 批量执行修复（O5）**：`native/src/vm/jit_templates.rs` + `native/src/vm/jit_trace.rs` + `native/src/vm/vm/executor.rs`
  - 修复 `execute_trace_bulk` 对条件跳转 side-exit 的处理：当条件跳转 taken 且目标为 trace 起点时继续循环，未 taken 且 ip 仍在起点时推进到 `end_ip` 退出
  - 修复 `TraceRecorder::finish`：Abort 的录制不再被错误编译为不完整 trace，避免生成只包含条件判断的残缺 trace
  - `JitEntry` 新增 `is_conditional_jump` 标志，替代依赖函数指针地址比较的 `func as usize` 判断（同时消除 B15/S9 可移植性风险）
  - 新增 `native/tests/jit_templates_test.rs`：`test_jit_trace_bulk_accelerates_loop` 验证长循环确实被批量加速
- **`host_qsort` 批量写回优化（O10）**：`native/src/vm/host_funcs.rs`
  - 将结果从临时缓冲区写回 VM 内存的方式从逐字节 `store_i8` 改为按元素块 `write_memory`，大数组排序性能显著提升
  - 新增 `native/tests/qsort_test.rs`：整型数组、字节数组、100 元素逆序数组排序回归测试

### Added (P0 语法拓展)
- **通用逗号运算符 `a, b`**：Parser 在 `parse_assign` 前新增 `parse_comma` 层，AST 新增 `BinaryOp::Comma`
  - TypeChecker 取右操作数类型，CodeGen 生成左值计算 + `Pop` 后保留右值
  - 支持 `while (a--, a > 0)`、`for (; ; a++, b++)`、表达式语句多操作等场景
- **Designated Initializer `.field = val` / `[i] = val`**：AST `InitList` 重构为 `Vec<InitElement>`
  - Parser `parse_init_list` 支持 `.field = expr` 和 `[index] = expr` 两种 designator 语法
  - TypeChecker/CodeGen：struct 按字段名写入、数组先 `Memset` 零填充再按索引写入，未指定元素自动为 0
  - 覆盖局部变量上下文（全局/静态 designated init 暂不支持）
- **`offsetof(struct S, field)`**：新增 `Expr::Offsetof`，Lexer 添加 `offsetof` 关键字，Parser 按 `offsetof(type, identifier)` 语法解析
  - TypeChecker 编译期计算字段偏移（struct 累加、union 为 0），CodeGen 直接 `PushConst(offset)`
  - 支持 struct / union 字段偏移查询
- **新增 10 个 E2E 测试**：`test_e2e_comma_operator`、`test_e2e_designated_struct_init`、`test_e2e_designated_array_init`、`test_e2e_offsetof_struct`、`test_e2e_offsetof_union` 等

### Fixed (CI 修复)
- **修复 Rust job 构建时生成 FRB 代码**：`.github/workflows/ci.yml`
  - `native/src/frb_generated.rs` 已改为构建时生成，Rust job 中 `cargo build` 前必须先执行 `flutter_rust_bridge_codegen generate`
  - 在 Rust job 开头新增 `Install flutter_rust_bridge_codegen` 和 `Generate FRB bindings` 步骤，确保 `cargo build`/`cargo test` 前代码已生成
- **修复 Android Gradle wrapper 本地路径问题**：`CideFlutter/android/gradle/wrapper/gradle-wrapper.properties`
  - 将 `distributionUrl` 从本地文件 `file:///D:/code/.../gradle-8.13-bin.zip` 改为官方 `https\://services.gradle.org/distributions/gradle-8.13-bin.zip`
  - 解决 CI runner 上 `FileNotFoundException` 导致 `flutter build apk` 失败

### Added (Flutter 测试抽象层与单元测试)
- **引入 `RustApiService` 抽象层**：`CideFlutter/lib/services/rust_api_service.dart`
  - 将 `flutter_rust_bridge` 生成的全局 Rust API 调用封装到 `RustApiService` 接口
  - 默认实现 `DefaultRustApiService` 继续转发到真实 Rust 后端
  - 所有 Notifier（`CompileNotifierMixin` / `RunNotifierMixin` / `LearningNotifierMixin` / `UnifiedNotifier`）改为通过 `ref.read(rustApiServiceProvider)` 调用服务，解耦对全局函数的硬编码依赖
  - 为 Flutter 单元测试引入 mock 替换点，无需在 Dart VM 中加载原生动态库
- **新增编译 / 运行 / 统一模式单元测试**：`test/providers/compile_run_unified_test.dart`（11 个测试）
  - 编译成功/失败状态与诊断更新
  - 编译成功后自动启动统一模式
  - 运行成功/失败与输出更新
  - 单步执行到结束
  - 统一模式启动失败处理
  - Stream 批量收集完成/异常陷阱处理
  - Seek 到缓存内步骤 / 单步追加到缓存
- **新增测试辅助文件**：`test/mocks/rust_api_service_mock.dart`
  - `MockRustApiService`（基于 `mocktail`）
  - 工厂函数构造 `CompileResult` / `RunResult` / `StepResult` / `UnifiedRunResult` / `StepStreamBatch` / `StepPayload`
- **Flutter 测试总数**：从 90 个提升至 **101** 个，全部通过

### Added (标准库拓展 P0)
- **math.h 全管线支持**：引入 `libm` crate，注册 `sin`/`cos`/`sqrt`/`pow`/`atan`/`log`/`exp` 为 Layer B Rust Host Func
  - TypeChecker 支持 `double` 参数/返回类型，Host Contract 测试覆盖精度、NaN、-inf 边界行为
  - K&R 4.5（栈计算器数学函数）从已知失败中移除
- **头文件存根系统（Stub Headers）**：建立 `native/runtime_libc/include/{stdio.h,stdlib.h,ctype.h,math.h,string.h}`
  - 改造 Lexer：`#include <name.h>` 不再跳过，而是加载对应存根内容到当前翻译单元
  - 存根中声明标准库函数符号，Parser/TypeChecker 自动识别，逐步替代硬编码函数名匹配
  - 预定义宏 `NULL`/`EOF`/`stdin`/`stdout`/`stderr` 在 Lexer 中内置，兼容 K&R 早期示例

### Added (C++ 扩展 M6 — 测试防线收尾)
- **60 个 C++ E2E 回归用例**：新增 `native/tests/cases/cpp/` 目录，覆盖三大类
  - 核心语言（16）：class / ctor / dtor / 引用 / auto / 范围 for / 模板 / 虚函数 / this / 方法重载
  - 容器与算法（15）：自实现 vector<int/float/char> / list<int> / string / 排序 / 栈 / 队列 / 链表 / 二叉树
  - 教学/OJ 题目（29）：Two Sum / 去重 / 移除元素 / 二分 / 最大子数组 / 股票 / 单数 / 多数 / 旋转 / 移动零 / 回文 / 括号 / 反转链表 / 合并链表 / 树深度 / 相同树 / 翻转树 / 爬楼梯 / 帕斯卡 / 平方根 / 罗马数字 / 缺失数字 / 公共前缀 / 首个唯一字符等
- **C++ E2E 测试框架**：扩展 `native/tests/vitro_e2e.rs`
  - `compile_and_run_cpp` 通过 `vitro_compile_unit(..., "main.cpp", ...)` 自动启用 C++ 模式
  - `load_cpp_cases` / `run_cpp_case` 支持 `.cpp` 用例与 `.in` 输入文件
  - `test_vitro_e2e_cpp` / `test_vitro_e2e_cpp_known_failures` 及 `KNOWN_CPP_FAILURES` 监控
  - `TEST_REPORT.md` 生成已汇总 C++ 统计
- **Golden 来源**：所有 60 个 `.out` 文件由 Clang++ (`-std=c++14 -O0`) 生成，Vitro 输出与之逐行对比，目前 60/60 全绿
- **单元测试扩展**：parser_cpp_unit_test（33）、typeck_cpp_unit_test（28）、bytecode_gen_cpp_unit_test（38）全部通过
- **诚实记录子集边界**：`native/tests/CPP_FAILURES.md` 新增 M6 过程中识别的 Vitro C++ 子集边界（如类字段逗号多声明、指针逻辑运算、模板类方法引用参数等），用例已规避，无已知失败

### Fixed (C++ 子集边界消除)
- **指针逻辑运算 `&&` / `||` 支持指针/数组**：`typeck/expr.rs` 放宽 `And`/`Or` 操作数类型检查；`UnaryOp::Not` 同时支持数组
  - `cpp_merge_two_lists.cpp` 恢复标准 `while (l1 && l2)` / `while (h)` 写法
- **类内方法重载**：`ClassSymbol::methods` 从 `HashMap<String, MethodSig>` 改为 `HashMap<String, Vec<MethodSig>>`
  - 新增 `resolve_method_overload` / `overload_match_score`，按参数数量与类型相似度选择最佳签名
  - 方法 mangling 在存在多个重载时使用 `Class__method__N`（N 为用户参数个数），单签名保持向后兼容的 `Class__method`
  - 移除 Pass 2.3 重复注册逻辑；`register_single_class_layout` 统一注册方法/构造/析构函数符号
  - 支持类成员函数体内无显式 `this->` 的方法调用（C++ name hiding），`Call`/`CallPtr` 均会尝试解析为 `MemberCall`
  - 新增 E2E 用例 `cpp_method_overload.cpp`（BST 公有 `insert(int)` + 私有递归 `insert(Node*, int)` + `print` 重载）
- **M6 10 项 C++ 子集边界全部消除**：`CPP_FAILURES.md` 中记录的边界全部修复，`native/tests/cases/cpp/` 60 个用例全部使用标准 C++14 语法，`KNOWN_CPP_FAILURES` 为空

### Fixed (C++ Shadow Verification 3 gap 清零)
- **右值引用绑定函数返回值 `int&& r = foo();`**：`VarDecl` 引用初始化分支区分左值 / 引用表达式 / 纯右值；纯右值创建临时局部变量延长生命周期，再绑定引用地址
- **`const int& r = 5` 绑定字面量右值**：同上临时变量方案，常量左值引用可接受字面量右值
- **`for (auto& x : arr)` 修改数组元素**：
  - `typeck/decl.rs` 修正 `RangeFor` 变量类型推导：`auto&` 推导为 `Reference { base: elem_type }`，`auto&&` 推导为 `RValueRef { base: elem_type }`
  - `codegen/stmt.rs` 数组形式的 `RangeFor` 在循环变量为引用时存储元素地址而非元素值
- **测试扩展**：`bytecode_gen_cpp_unit_test` +3（`test_cpp_rvalue_ref`、`test_cpp_const_ref_rvalue`、`test_cpp_range_for_ref_modify`），`typeck_cpp_unit_test` +1（`test_cpp_auto_ref_range_for`）
- **Shadow Verify 状态**：`scripts/shadow_verify_cpp.py` 中 3 个用例从 `gap` 改为 `baseline`，C++ Shadow Verification 82/82 全绿，0 gap

### Added (C++ 扩展 Stage 1 — 类模板实例化)
- **Parser 模板 id 类型解析**：新增 `Type::TemplateId { base, args }`，`Parser` 维护 `template_names` 集合，`parse_base_type` 识别 `vector<int>` 语法
- **TypeChecker 类模板实例化**：`try_monomorphize_class` 镜像函数模板单态化逻辑，支持字段/方法/构造函数/析构函数中的模板参数替换
  - `resolve_template_id` 递归处理指针/数组/引用等包装器内部的 `TemplateId`
  - 实例化产物立即注册 `ClassSymbol` 并参与 Pass 3.5 `check_class_methods`
- **BytecodeGen 非类 new-init 修复**：`gen_new` 补充非 `Class` 类型（如 `new int(5)`）的 init 直接存储路径
- **MemberCall 参数检查修复**：`user_param_count` 从 `param_types.len() - 1` 修正为 `param_types.len()`（方法签名不含 `this`）
- **zero-size 类 zero-init 跳过**：`sz == 0` 时不 emit `StoreLocal`，避免 `STACK_START` 边界越界
- **集成测试 +5**：`Box<int>` 字段访问、`Adder<int>` 方法调用、`Wrapper<int>` 构造函数 + `new`、`Ptr<int>` 指针字段、类型不匹配负向测试

### Added (C++ 扩展 Stage 6 — `unique_ptr<T>` dogfooding 与构造函数初始化语法)
- **`unique_ptr<T>` 简化版全管线跑通**：模板类 `unique_ptr<T>`（单 `T*` 字段）支持构造、`get()`、`release()`、`reset()`、析构，以及 `std::move` 触发的隐式移动构造转移所有权并置空源对象
  - 新增 `native/tests/cpp_dogfooding_test.rs::test_cpp_unique_ptr_int_dogfooding_runs` 作为 M5 dogfooding 用例
  - 同步更新 `native/runtime_libc/vitro/unique_ptr_int.{c,cpp}` 运行时布局与 `bytecode_libc_sig.rs` 签名（内置 `unique_ptr<int>` 容器走 Bytecode Libc 路径）
- **构造函数初始化语法 `Type name(args);`**：Parser `parse_var_decl_stmt` 识别类/模板类变量后的 `(...)` 为构造参数列表，生成占位 `__ctor__{Class}__{N}`；TypeChecker 解析为实际 mangled 构造函数并在参数列表前插入 `&name` 作为 `this`
- **构造函数重载与隐式默认构造**：
  - 显式构造函数按参数数量编码为 `__ctor__{Class}__{N}`，零参数保持 `__ctor__{Class}`
  - 无显式默认构造的类自动注册隐式默认构造函数，支持 `Class c;` 和 `new Class()`
  - `resolve_constructor_overload` 按参数数量匹配，带 fallback 扫描
- **`new` 表达式类型检查修复**：类类型 `new` 的 init 中尚未包含 `this`，改为根据类方法签名直接检查用户参数，避免参数数量不匹配报错
- **函数指针声明解析修复**：`parse_var_decl_stmt` 通过预读 `Identifier (` 精确区分构造初始化与函数指针后缀，恢复 `int (*fp)(int, int);` 等复杂声明符解析
- **Range-for 数组大小推断修复**：`VarDecl` 仅在构造初始化时提前 `declare_var`，避免数组初始化后推断出的大小与符号表类型不一致
- **Dogfooding 测试 +1**：`cpp_dogfooding_test` 总数达 29 个，全绿

### Added (C++ 扩展 Stage 5 — 隐式移动构造函数自动生成)
- **资源检测**：`ClassSymbol` 新增 `has_resource` 字段；`typeck/cpp_class_layout.rs` 在类布局注册后第二遍计算，递归检测指针、`Reference`/`RValueRef`、含资源 class/struct、数组元素等资源字段
- **隐式移动构造函数生成**：`typeck/cpp_overload.rs` 新增 `generate_implicit_move_ctors`，为含资源且无显式移动构造的类自动生成 `__ctor__{Class}__move`；函数体逐字段拷贝，并将源对象指针字段置 `nullptr`，防止双重释放
- **类型系统适配**：
  - `check_assignable` 允许 `RValueRef<Class>` 赋值给 `Class`（触发移动构造）
  - `Expr::Member` 类型检查支持 `Reference`/`RValueRef` 对象访问
- **BytecodeGen 调用路径**：
  - `VarDecl` 初始化时检测到 `RValueRef`/`Expr::Move` 调用 `__ctor__{Class}__move`，按 VM 参数弹出顺序右-to-left 压入 `this`/`other`
  - `gen_member_addr` 与 `get_member_offset` 支持 `Reference`/`RValueRef` 对象地址计算
  - `gen_addr` 对 `std::move(x)` 返回 `x` 的地址而非值；`CallPtr(std__move)` 在 `gen_expr` 中透传参数
  - 调用移动构造函数后记录 `class_vars`，确保作用域退出时析构被调用
- **测试 +2**：`test_implicit_move_ctor_pointer_nulls_source`、`test_implicit_move_ctor_builtin_vector`，Dogfooding 测试总数达 28 个，全绿

### Added (C++ 扩展 Stage 0.5 — Phase 3 收口)
- **容器库编译器支持补全**：
  - `builtin_layout.rs` 新增 `vitro_list_int` 布局；`layouts.toml` 新增 `[vector_char]`、`[list_int]`
  - `type_map.rs` 新增 `vitro_list_int` 方法映射（push_back/push_front/pop_back/size/get/destroy）
  - `list_int.c` / `vec_char.c` / `sort_int.c` 已预编译为 Bytecode Libc（索引 1000~1059）
- **C++ 容器端到端测试 +3**：`test_cpp_container_vec_char`、`test_cpp_container_list_int`、`test_cpp_sort_int`
  - 覆盖空容器/越界/重复 destroy 边界；22/22 C++ BytecodeGen 端到端测试全绿
- **C++ 测试防线建设**：
  - 创建 `native/tests/CPP_FAILURES.md`（当前零已知失败）
  - `ci_three_tier_check.py` 新增 C++ 三 tier（`parser_cpp_unit_test` 15 例、`typeck_cpp_unit_test` 13 例、`bytecode_gen_cpp_unit_test` 22 例），纳入 CI 一致性监控；C++ 扩展合计 50/50 通过

### Added (C++ 扩展 Stage 2 — 栈对象 RAII)
- **ScopeFrame 重构**：`local_scope_stack` 从 `(String, Option<...>)` 元组向量升级为 `ScopeFrame { shadows, class_vars }`，支持按作用域追踪类类型局部变量
- **构造函数自动调用**：`codegen/stmt.rs` VarDecl zero-init 路径对 `Type::Class` 自动 emit `__ctor__{Class}` 调用，实现 `Class c;` 即构造
- **析构函数自动调用**：
  - `exit_scope` 逆序遍历 `class_vars`，emit `__dtor__{Class}`
  - `Return` / `RetVoid` 前调用 `emit_dtors_for_scope_exit(0)`，覆盖函数最外层 block
  - `Break` / `Continue` 前按 `loop_scope_depths` 计算需退出的嵌套 scope， emit 对应 dtor
- **Loop scope 深度追踪**：新增 `loop_scope_depths` 栈，与 `loop_start_ips` 同步 push/pop，支持 break/continue 的精确析构范围
- **集成测试 +5**：`test_cpp_stack_ctor_dtor_basic`、`test_cpp_nested_scope_dtors_lifo`、`test_cpp_early_return_dtors`、`test_cpp_break_dtors`、`test_cpp_continue_dtors`

### Added (C++ 扩展 Stage 3 — `new[]/delete[]` 元素构造析构)
- **`new A[n]` 元素逐个构造**：`gen_new` 对类类型数组在 `base[-4]` 预存元素 count，`for i = 0..n-1` 调用 `__ctor__{Class}(user_ptr + i * elem_sz)`
- **`delete[] arr` 逆序析构**：`gen_delete` 从 `base[-4]` 读取 count，`for i = n-1..0` 调用 `__dtor__{Class}(user_ptr + i * elem_sz)`，最后 `free(base)`
- **临时变量槽位扩展**：`BytecodeGen` 的 `get_temp_slot` 从 3 个独立 slot 扩展为 4 个（`temp_slot0..3`），避免 `new[]/delete[]` 循环中 `i_temp` 与 `user_ptr_temp` 冲突
- **集成测试 +2**：`test_cpp_new_array_ctor_dtor`（验证构造次数）、`test_cpp_new_array_ctor_dtor_reverse_order`（验证析构逆序）

### Added (标准库全面拓展 P1 — 2026-06-07)
- **新增 19 个 Host Func + 7 个存骨头文件**，覆盖 C89/C99 教学高频函数：
  - `ctype.h`：`isgraph`/`ispunct`/`isblank`
  - `math.h`：`asin`/`acos`/`atan2`/`sinh`/`cosh`/`tanh`
  - `stdlib.h`：`abort`/`strtol`/`strtod`/`llabs`
  - `stdio.h`：`fflush`/`perror`/`clearerr`/`remove`/`rename`
  - `string.h`：`strerror`/`strpbrk`/`strspn`/`strcspn`
  - `time.h`：`time`/`clock` + `time_t`/`clock_t` typedef + `CLOCKS_PER_SEC` 宏
  - `assert.h`：`assert` 宏展开为 `if (!(expr)) __vitro_assert_fail()`
  - `errno.h`：`extern int errno` + `EINVAL`/`ERANGE`/`EDOM`/`ENOENT`/`EACCES` 宏，Host Func 支持通过符号表写入
  - `float.h`：`FLT_MAX`/`DBL_MAX`/`FLT_EPSILON`/`DBL_EPSILON` 等宏
  - `stdint.h`/`stddef.h`：`int8_t`~`uint64_t`、`size_t`/`ptrdiff_t` typedef
- **新增 23 个 Host Contract 测试**：覆盖全部新增函数边界条件
- **VFS 扩展**：`VfsDesc` 新增 `error` 字段，支持 `fflush`/`clearerr`/`remove`/`rename`
- **VitroVM 公开 API**：新增 `is_finished()`/`exit_code()` getter，供测试框架查询 VM 终止状态

### Fixed (标准库拓展中发现并修复的 Bug — 2026-06-07)
- **严重：7 个新增 Host Func 参数 pop 顺序错误**
  - 根因：新增 Host Func 实现时 `vm.pop()` 顺序错误，与 Vitro 编译器「从右到左压栈」约定不匹配
  - 影响函数：`strtol`/`strtod`/`strpbrk`/`strspn`/`strcspn`/`rename`/`atan2`
  - 后果：这些函数在实际 C 代码中被调用时，所有参数全部错位；由于此前无端到端测试覆盖，bug 一直隐藏
  - 修复：调整 `vm.pop()` 顺序，使第一个 pop 得到第一个参数（栈顶）
  - 验证：Host Contract Tests 新增 23 个用例后触发失败，修复后 86 个 Host Contract 测试全部通过

### Fixed (2026-06-04 审阅报告修复)
- **Soundness / 正确性**：
  - `cstr_to_str` 返回 `&'static str` → `Option<String>`，消除 C 端释放后的悬垂引用风险
  - `VM::reset()` 遗漏 `qsort_depth` 重置，两次运行间残留值导致 VFS 行为异常
  - `algorithm_detector::is_adjacent_compare`：字符串匹配 → AST 结构比较（`idx_b` 是否为 `idx_a + 1`）
  - `algorithm_detector` mid 计算检测：字符串匹配 "mid"/"left"/"right" → AST 结构匹配 `(a+b)/2` / `a+(b-a)/2`
  - `algorithm_detector` shift 模式：宽松 `contains('[')` → 精确 `arr[x+1]=arr[x]` 结构匹配
- **性能**：
  - VM 热点路径 `LoadLocal`/`StoreLocal`/`LoadGlobal`/`StoreGlobal` O(n) 符号查找 → O(1) `HashMap`
    - `VMSymbol` 新增 `func_name` 字段，`VitroVM` 新增 `local_sym_map`/`global_sym_map`
    - 函数调用/返回时自动重建局部变量映射
  - `Call`/`CallPtr` 帧设置逻辑提取 `do_call` 辅助方法，消除 ~100 行重复
- **代码质量 / DRY**：
  - `VM::check_mem_access` 统一 `load_i32`/`store_i32`/`load_i64`/`store_i64`/`load_i8`/`store_i8` 的 NULL/边界检查
  - `host_funcs` 提取 `parse_format_spec` 共享函数，消除 `parse_format_specs` 与 `format_printf_string` ~80 行重复
  - `ast.rs` 提取 `compute_type_size`/`base_element_type`，消除 `compile_pipeline` 与 `bytecode_gen` 重复
  - `type_checker::insert_implicit_cast`：6 个重复 if-else → `implicit_cast_target` 映射表
  - `type_checker::check_assignable` 拆分为 4 个独立辅助方法（数组指针/函数指针/标量/通用指针）
  - `parser` 提取 `look_ahead_skip_stars` 辅助函数
- **边界检查**：
  - `do_call` 中 `frame_size > MEM_SIZE` 改为 `> STACK_START - NULL_TRAP_SIZE`，更精确反映可用栈空间
- **工程化**：
  - `SessionSnapshot` 增加 `#[serde(deny_unknown_fields)]`，防止加载不兼容数据
  - `vitro_session_load` 硬编码 `test.txt`/`numbers.txt` → 从 snapshot 序列化/恢复 VFS 预设文件
  - `UnifiedEngine::seek_to` 正向重放时检查 `is_cancelled`，支持长时间 seek 中断
  - `UnifiedEngine::max_steps` 默认 10,000 → 100,000，减少长程序过早终止
  - `lexer` 十六进制解析：`u64::from_str_radix` + 手动溢出检查 → `u32::from_str_radix`，利用类型系统防溢出
  - `parser` `parse_base_type`：`unsigned` 修饰非法组合时 early return 哨兵类型，避免继续构造无效类型
  - `opcode.rs` 添加扩展空间注释（当前最大值 111，上限 255）
  - `bytecode_gen` `push_f64_constant`/`push_i64_constant` 添加去重，相同常量复用索引
  - `bytecode_gen` `ptr_step_size` 支持指向数组的指针步长（如 `int (*p)[3]` 步长为数组总大小）
- **未使用 import 清理**：`e2e_multi_file.rs` 移除 `Type` import

### Fixed (2026-06-08 全面审阅报告修复)
- **`E3057_ConstViolation` 重命名为 `E3065_ConstViolation`**，消除标签与值不匹配
- **`opcode.rs` 更新最大 opcode 注释**：`CallPtr = 111` → `Strlen = 126`
- **`compute_stride` 增加零/负步长 guard**，防止 VLA size 未解析时的静默数据损坏
- **`codegen/mod.rs` 拆分为 `expr.rs` + `stmt.rs`**，解耦表达式/语句生成逻辑（trait 模块化）
- **`Stmt`/`FuncDecl`/`ProgramNode` 添加 `serde::Serialize/Deserialize`**，解除 C++ AST 序列化阻塞
- **C++ 扩展错误码骨架 E4001-E4020 预声明**，防止多人并行开发时编号冲突
- **Flutter `UnifiedNotifier` 覆盖 `dispose()`**，取消 StreamSubscription 防止内存泄漏
- **Flutter `main.dart` 添加应用生命周期监听**，桌面端窗口关闭时释放 VM Session
- **Flutter CI `flutter-action` 启用 `cache: true`**，减少 CI 构建时间
- **预编译脚本 `precompile_bytecode_libc.py` 适配 `vitro/` 目录扫描**

### Fixed (2026-05-18 审查报告修复)
- **Rust 后端 P0 Bug（5 个严重问题）**：
  - `call_user_function` 循环次数错误：拆分 `arg_count` 为 `param_count`（参数个数）和 `param_words`（总 word 数）
  - `restore()` 快照恢复：`.copy_from_slice()` → 安全边界拷贝，防止不同内存配置下 panic
  - 复编译时 `f64_constants` 残留：添加 `clear()` 防止旧常量污染
  - 常量索引越界：`.unwrap_or(0)` → `trap` 报告越界错误
  - `PushConstF` 符号扩展：`operand as u64` → `operand as u32 as u64`，修复负 float 值损坏
- **VM 安全加固**：
  - `TrapBounds`：栈为空时 `trap` 而非静默返回 0
  - C API `vitro_get_call_frame`：`vm.as_ref().unwrap()` → 安全匹配
  - `write_cstring`：移除 `#[allow(clippy::int_plus_one)]`，改写边界条件
- **代码质量与重构**：
  - 统一宿主函数名→ID 映射：`host_func_id::by_user_name()` / `is_builtin()` 消除 3 处重复
  - 合并 `gen_struct_copy` / `gen_struct_copy_to_local` → `gen_struct_copy_common`
  - 合并 `parse_abstract_declarator` / `parse_declarator_node`（新增 `is_abstract` 标志）
  - 删除 `Session.errors_buffer` 冗余字段
  - `insert_implicit_cast`：`std::mem::replace` + dummy Literal → `std::mem::take`
  - 删除未使用的 `parse_call_expr`
  - `cargo clippy -- -D warnings` 完全通过（无手动抑制）
- **工程化**：
  - 检查点内存上限：默认最大 50 个快照，防止长程序内存无限增长
  - 字符串字面量上限：`0x8000` (32KB) → `MEM_SIZE / 16` (64KB)
  - CI 新增 Release 构建验证 + Flutter 测试
  - Android `applicationId`：`com.example.vitro` → `com.vitro.app`
  - `re_editor` 锁定确切版本 `0.8.0`，添加私有 API 依赖注释
  - NDK 配置添加环境变量说明
- **文档同步**：
  - `DESIGN.md`：指令集 `~30 条` → `106 条`，C++ 伪代码 → Rust
  - `AGENTS.md` / `CHANGELOG.md`：测试数量 `44` → `238`
  - `ROADMAP.md`：知识图谱标记为未启动，函数指针标记为已完成
  - `CideFlutter/README.md`：重写为项目说明
- **Flutter 前端加固**：
  - `LinkedListVisualizer` / `TreeVisualizer`：异步 `setState()` 前加 `mounted` 检查
  - `LinkedListVisualizer`：内存上限改为 `rust.getMemorySize()` 动态获取
  - `MemoryTab`：`StatelessWidget` → `StatefulWidget` 缓存 Future
  - `IdeScreen`：键盘状态同步从 `build()` 移至 `didChangeDependencies`

### Added
- **键盘弹出时沉浸编辑模式**（Flutter）：
  - 自定义键盘或系统键盘弹出时，顶部工具栏、模板栏、底部面板通过 `SizeTransition` 平滑收起，编辑器自动拉伸占满剩余空间。
  - 键盘收起后上下栏自动弹出恢复。
  - 系统键盘真实可见性通过 `MediaQuery.viewInsets.bottom` 检测，收起后自动同步状态。
- **编辑器手势优化**（Flutter）：
  - 点击代码字符处：打开键盘。
  - 点击空白处（空行、行尾之后、尾部空白区域）：关闭键盘。
  - 上下滑动（位移 >100px 且垂直方向为主）：关闭键盘。
  - 长按（>600ms）仍弹出上下文菜单，不受单击/滑动逻辑影响。
  - 空白检测通过 `addPostFrameCallback` 延迟到 `re_editor` 内部更新光标位置后执行，避免依赖内部私有 API。
- **Panel drag-and-drop swap logic** (Flutter):
  - All drag interactions now perform **swap** instead of add/remove/move. Both regions (bottom tabs + floating orb) maintain fixed element counts.
  - Cross-region swap: `swapBottomWithFloatingItem(bottomPanelId, floatingIndex)` and `swapFloatingWithBottomItem(floatingPanelId, bottomIndex)` in `ide_notifier.dart`.
  - Item-level `DragTarget` for each floating menu item (`floating_orb_widget.dart`), enabling precise swap with the hovered item.
  - Hover feedback: blue border + shadow on both bottom tabs and floating menu items when a draggable hovers over them.
  - Edge detection: dropping on empty padding/orb area shows a SnackBar "未识别到可交换的目标位置".
  - Same-region filtering: floating menu item `DragTarget` only accepts drags from `PanelLocation.bottom`, preventing accidental same-region swaps.
- **Floating orb menu direction**: menu now prefers expanding **upward** whenever space allows (`_pos.dy >= menuHeight + 28`), making it easier to drag bottom tabs upward into the menu for swapping.

### Changed
- **Flutter bottom panel UI polish**:
  - Output tab empty state now shows `terminal_outlined` icon + "等待执行" text instead of plain text.
  - Diagnostics tab empty state now shows `check_circle_outline` icon + "无诊断信息" text.
  - Algorithm tab empty state now shows `auto_graph_outlined` icon + "未检测到算法模式" text.
  - Copy button in output tab now has a background container (adapts to dark/light theme) and no longer overlaps text (right padding added to scroll view).
  - Removed unused "+" button from bottom tab bar.

### Added
- Host function ID unified constant module (`vm/host_func_id.rs`) to prevent ID mismatch between compile-time and runtime.
- Unified compilation pipeline `run_compile_pipeline()` in `engine/compile_pipeline.rs` to eliminate ~100 lines of DRY violation between `flutter_bridge.rs` and `capi/mod.rs`.
- `rustfmt.toml` for consistent Rust code formatting across the project.
- `CHANGELOG.md` for tracking project evolution.
- **240 unit tests** across all compiler phases (`lexer_unit_test.rs`, `parser_unit_test.rs`, `type_checker_unit_test.rs`, `bytecode_gen_unit_test.rs`, `vm_memory_safety_test.rs`, `compile_pipeline_test.rs`, `end_to_end_test.rs`, `end_to_end_extra_test.rs`, `test_snapshot.rs`).
- **Flutter frontend modularization**: extracted all tab widgets (`AlgorithmTab`, `WatchTab`, `PointerVisTab`, `ArrayVisTab`, `MemoryTab`, `VariablesTab`, `CallstackTab`, `KnowledgeCardTab`), visualizers (`ArrayVisualizer`, `KnowledgeCardItem`), and layout components (`Toolbar`, `SymbolBar`, `TemplateBar`, `HeightResizablePanel`, `DraggablePanelTab`) from `ide_screen.dart` (2004 → 471 lines).
- **Flutter provider split**: extracted `IdeNotifier` to `providers/ide_notifier.dart` (`ide_provider.dart` 726 → 7 lines).
- **数组排序实时条形图可视化**（Flutter + Rust）：
  - Rust: `VitroVM::get_array_snapshots()` 遍历符号表识别 `Type::Array`，从 VM 内存逐元素读取（支持 int/char/float/double/long long）。
  - `StepPayload` 新增 `array_snapshots: Vec<ArraySnapshot>`，`StepCollector` 每步自动收集。
  - Flutter: `ArrayVisTab` 从 `unifiedProvider` 零延迟读取；`ArrayVisualizer` 绘制条形图，高度表示数值，负值红色/正值蓝色。
  - VisEvent 比较事件（如 `arr[i]:arr[j]`）自动高亮对应条形（琥珀色 + 发光阴影）。
- **变量级高亮（读/写标记）**（Flutter + Rust）：
  - Rust: `VitroVM::step()` 中 `LoadLocal`/`StoreLocal`/`LoadGlobal`/`StoreGlobal` 自动记录 `VariableAccess`（Read/Write）。
  - `StepPayload` 新增 `accessed_vars`。
  - Flutter: `VariablesTab` 被读取变量显示蓝色边框+「读」徽章，被写入显示橙色边框+「写」徽章。
- **编辑器行号区域变量访问指示**：统一模式下当前执行行的行号旁追加 `a=W b=R` 标记。
- **运行时异常智能诊断匹配**（Flutter）：
  - `KnowledgeCard` 新增 `relatedTrapKeywords` 字段和 `findByTrapMessage()` 方法。
  - 新增 5 张运行时异常知识卡片：数组越界、NULL 指针解引用、除零、栈溢出、访问已释放内存。
  - `ExecutionControlPanel` 异常提示条新增「查看帮助」按钮，点击弹出 BottomSheet 展示匹配的知识卡片。
- **学习进度追踪（统一模式）**（Flutter）：
  - `LearningProgress` 新增 `totalUnifiedRuns`/`totalStepsExecuted`/`totalTraps`/`totalSeeks`/`maxStepsInSingleRun`。
  - `IdeNotifier` 新增 `recordUnifiedRun()` / `recordSeek()`。
  - `ProgressTab` 新增「调试探索」卡片，显示运行次数/总步数/异常/Seek/峰值步数。
- **算法检测信息在前端展示**（Flutter）：`ExecutionControlPanel` 顶部显示检测到的算法名称（如「冒泡排序」）+ 时间复杂度说明。
- **IDE 热键支持（Desktop）**（Flutter）：F5 运行/继续、Shift+F5 停止、F10 单步、F9 切换断点；`EditorPanelState` 新增 `getCurrentLine()`。
- **变量值变化检测**（Flutter）：`VariablesTab` 比较当前步与上一步变量值，数值增加显示绿色 ↑，减少显示红色 ↓，非数值变化显示黄色 •。
- **断点列表管理面板**（Flutter）：新增 `BreakpointsTab`，显示所有断点行号+源码预览，支持点击跳转和删除。
- **代码覆盖率统计**（Flutter）：`ExecutionControlPanel` 显示覆盖率百分比（已执行行数/总行数），颜色分级（≥80%绿/≥50%橙/<50%红）。
- **算法事件指示条**（Flutter）：`ExecutionControlPanel` 顶部紫色渐变条显示当前步 VisEvent 上下文（如 `arr[i]:arr[i+1]`）。
- **函数指针高级语法支持**（Rust Parser + TypeChecker + BytecodeGen）：
  - 多级函数指针：`int (**pp)(int) = &fp;` — `interpret_declarator_node` 的 `Function` 分支递归解释 `ptr_inner` 为"以函数指针为基础类型的声明符"。
  - 返回指针的函数指针：`int *(*fp)(int) = greet;`。
  - `sizeof` 函数指针类型：`sizeof(int (*)(int))` — 新增 `parse_abstract_declarator()` 支持抽象声明符（括号、多级指针、数组后缀、函数参数列表）。
  - `typedef` 函数指针：`typedef int (*Op)(int, int);` — `parse_typedef` 改用完整 `parse_declarator()` 替代简陋的 `parse_type_only()`。
  - `static` 局部变量：`static int arr[3] = {1,2,3};` — `parse_statement` 识别 `static` 存储类说明符并跳过。

### Fixed
- **Flutter Overlay popup Material missing**: `FloatingPanelPopup` now wraps its content with `Material(type: MaterialType.transparency)`, eliminating the yellow underline artifacts on text and the red `No Material widget found` crash when opening `WatchTab` (which contains `TextField`) or `ProgressTab` (which contains `TextButton`) from the floating orb.
- **Flutter run/step auto-compile**: `IdeNotifier.run()` and `IdeNotifier.step()` now automatically call `compile()` before executing if the session is not already running. Previously, clicking the play button without manually compiling first resulted in a silent `"程序尚未编译"` error because `state.error` was never displayed in the UI.
- **Flutter error visibility**: `IdeScreen` now listens to `state.error` via `ref.listen` and shows a floating `SnackBar` when a new error occurs, preventing silent failures.
- `printf`/`fprintf` format specifiers now correctly skip width/precision/length modifiers (e.g. `%6d`, `%.2f`, `%ld`), preventing stack imbalance from mis-counted arguments. Shared logic extracted into `parse_format_specs()` + `format_printf_string()` in `host_funcs.rs`.
- `scanf` format parsing now also skips modifiers via `parse_format_specs()`, fixing the same miscount bug.
- Comma-separated multi-variable array declarations now preserve per-variable dimensions (`int a[10], b[20];`). `parse_declarator()` extracted; `Stmt::VarDecl.extra_vars` changed to `Vec<(Type, String, Option<Expr>)>`.
- `unsigned char` no longer mapped to `unsigned int`; now correctly preserves `TypeKind::Char` with `is_unsigned: true`.
- Flutter `IdeNotifier.reset()` is now `async` and properly `await`s `rust.resetSession()`, eliminating the race condition.
- `vitro_get_runtime_error()` now uses `error_buffer` snapshot pattern (same as `vitro_get_compile_errors()`), eliminating dangling pointer risk across FFI boundary.
- `vitro_session_load` now restores VM state via `setup_vm()` instead of overwriting with a blank VM.
- `call_user_function` no longer incorrectly pops stack value on `Trap`; returns `None` instead.
- Hex literal overflow check relaxed from `i32::MAX` to `u32::MAX` (`0x80000000` now accepted).
- Algorithm detector now collects all matching patterns per function instead of returning only the first match.
- `call_user_function` temporarily disables breakpoints to prevent internal `Paused` from terminating `run()`.
- `Type::is_scalar()` now includes `Float`, consistent with `TypeChecker::is_scalar()`.
- `malloc(0)` emits a pedagogical warning about implementation-defined behavior.
- Lexer `make_token` column calculation now uses `text.chars().count()` instead of `text.len()`, fixing multi-byte UTF-8 character inaccuracy.
- **统一模式下断点暂停支持**（Rust + Flutter）：`AutoStepResult` 新增 `paused` 字段；`UnifiedEngine::run_batch` 正确传递 `self.is_paused`；Flutter 端 `_collectBatch` 检测到 `paused` 后取消 Timer 并切换到 `paused` 状态。
- **算法可视化事件 context 修复**（Rust）：`vm.rs` 中 `StepEvent` 生成 `VisEvent` 时 `context` 为空；`VitroVM.vis_event_lines` 扩展为 `Vec<(i32, i32, String)>` 保留 context，`compile_pipeline.rs` 传递 `ev.context` 到 VM。
- `cargo clippy` 8 处警告自动修复（`useless_format!` → `.to_string()`，`manual_range_contains` → `(32..=126).contains(&b)`）。

### Changed
- `TypeChecker` now uses `#[derive(Default)]`; `TypeChecker::new()` removed.
- Temp test files (`temp_nested_struct_test.rs`, `temp_ptr_array_test.rs`, `tmp_struct_copy_test.rs`) merged or removed; tests consolidated into `end_to_end_extra_test.rs`.
- `CODE_REVIEW_REPORT.md` updated to reflect actual fix status.
- Lexer internal representation changed from `source: String` (byte-indexed) to `chars: Vec<char>` (char-indexed), making `peek()` and `advance()` O(1) instead of O(n).
- `merge_free_list()` extracted in `host_funcs.rs` to eliminate ~20 lines of duplication between `host_free` and `host_realloc`.
- `push_one()` extracted in `compile_pipeline.rs` to eliminate ~100 lines of duplication between `push_diagnostics` / `push_warnings` / `push_hints`.
- `parse_declarator()` extracted in `parser.rs` to share declarator parsing between `parse_type_and_name()` and comma-separated extra variables.

## [0.1.0] - 2026-05-14

### Added
- **Full C subset compiler pipeline** (Lexer → Parser → TypeChecker → BytecodeGen → VitroVM).
- **Float type support** across the entire pipeline (Lexer/Parser/TypeChecker/BytecodeGen/VM).
- **Host functions**: `printf`, `scanf`, `malloc`, `free`, `realloc`, `strlen`, `strcpy`, `strcmp`, `strcat`, `memset`, `getchar`, `putchar`, `rand`, `srand`, `atoi`, `exit`, `fprintf`, `qsort`.
- **C language features**: `struct`/`typedef struct`, `enum`, arrays (multi-dimensional), pointers (arithmetic, dereference, cast), `#define` macros, function forward declarations, `sizeof`, explicit casts, compound assignments (`+=`, `-=`, etc.), ternary operator, bitwise operators (`& | ^ ~ << >>`).
- ** pedagogical diagnostics**: Chinese error messages with emoji, fix suggestions, error catalog with explanations.
- **Algorithm visualization**: Bubble sort, selection sort, insertion sort, quick sort, merge sort, binary search detection with visual event hooks.
- **Memory map visualization**: 1MB VM memory grid with color-coded regions.
- **Flutter frontend**: IDE screen with `re_editor`, console, variable watch, step debugging, algorithm animation panel.
- **Session save/load**: `serde_json`-based snapshot of compile/runtime/memory state.
- **CI/CD**: GitHub Actions workflow for Rust build/test/clippy + C# build/test.

### Fixed
- Parser zero-progress deadlocks (`struct*`, `ParseBlock`, `parse_case_stmt`).
- VM security hardening: u32 overflow on addr arithmetic, step_count overflow, heap limit closure capture, jump target bounds, value stack limits.
- `char` array initialization using `StoreMemByte` instead of `StoreLocal`.
- Implicit cast hint system with severity levels (warning vs hint).
- UTF-8 safety in Lexer (`chars().nth()` instead of `as_bytes()[i] as char`).
- `printf`/`fprintf` format modifiers (`%6d`, `%.2f`, `%ld`) no longer cause stack unbalance.
- Comma-separated multi-variable array declarations (`int a[10], b[20];`) now preserve per-variable dimensions.
- `unsigned char` no longer incorrectly mapped to `unsigned int`.
- `vitro_get_runtime_error` dangling pointer: now uses buffer snapshot pattern.
- `call_user_function` return_ip uses `HOST_CALLBACK_SENTINEL` instead of `code.len()`.
- `session.rs` removed misleading `#![forbid(unsafe_code)]`.
- `host_realloc` in-place shrink when old block is at heap boundary.
- `host_qsort` recursion depth limited to `MAX_QSORT_DEPTH = 8`, preventing stack overflow from indirect recursive qsort calls.
- `host_scanf` `%c` no longer skips whitespace (matches standard C semantics).
- `compute_stride` zero-dimension fallback fixed: `dims[i] == 0` now produces stride 0 instead of 1.
- Algorithm validation regex no longer matches `int main(` inside string literals or comments.
- `flutter_riverpod` upgraded from `^3.3.2-dev.2` to stable `^3.3.1`.
- **多维数组初始化回归**：`bytecode_gen.rs` 中 `InitList` 处理在 `elements` 数量少于 `count` 时（如 `{{1,2,3},{4,5,6}}` 的顶层只有两个内层列表，总元素为6），`else` 分支错误 push `0` 而非 `values[i]`，导致数组元素全零。

### Changed
- `host_memset` now uses slice `.fill()` instead of per-byte `store_i8` for large blocks.
- `host_realloc` supports in-place shrink when the old block is at heap boundary.
- `RuntimeState::output()` replaces 13 repeated `output_lines.join("\n")` calls in `flutter_bridge.rs`.
- `TrapBounds` VM instruction now performs full bounds check in a single instruction (was ~15 instructions via manual `Ge`/`Lt`/`JumpIfZero` chain). `gen_index` bytecode shrunk by ~73%.
- `host_memset` now uses slice `.fill()` instead of per-byte `store_i8` for large blocks.

### Refactored
- `Expr::loc()`/`ty()`/`set_ty()` deduplicated with `macro_rules! expr_field!`.
- `merge_free_list()` extracted to eliminate duplication between `host_free` and `host_realloc`.
- `push_one()` unifies `push_diagnostics`/`push_warnings`/`push_hints`.
- `TypeChecker::visit_call()` split into 19 `check_builtin_xxx()` methods + `check_user_func()`.
- `format_type()` in `capi/mod.rs` removed; uses `Type::to_string()` instead.
- FRB duplicate data structures unified: `VisEvent`/`AlgorithmMatch`/`CompileResult`/`RunResult`/`StepResult`/`StepStatus` now single-source in `session.rs`, re-exported by `api/vitro.rs`.
- `OpCode::from_u8` auto-generated via `define_opcode!` macro, eliminating manual repr/match maintenance.
- `Lexer::new` takes `&str` instead of `String`, removing `.to_string()` clones in compile pipeline and all tests.
- `flutter_bridge.rs` breakpoint API batchified: `setBreakpoints(Vec<i32>)` replaces N+1 FFI calls.
- `api/vitro.rs` now re-exports FRB types from `session.rs`, eliminating duplicate struct definitions between `flutter_bridge.rs` and `api/vitro.rs`.

### Security
- `compile_pipeline.rs` unsafe string write bounds validated.
- C API naked pointers documented with lifetime contracts.

---

## Migration History

- **Phase 0** (2025-10): Rust skeleton + C API stubs.
- **Phase 1** (2025-10): VM migration (VitroVM + host functions).
- **Phase 2** (2025-11): Compiler frontend migration (Lexer/Parser/TypeChecker/BytecodeGen).
- **Phase 3–5** (2025-11): C# frontend E2E tests, Android builds, C++/CMake cleanup.
- **Phase 6–8** (2025-12–2026-01): Warning cleanup, float support, diagnostic system expansion.
- **Phase 9–10** (2026-02–2026-05): Flutter frontend from scratch, memory canvas, algorithm visualization FRB integration.
