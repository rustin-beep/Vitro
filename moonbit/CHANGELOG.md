## [Unreleased]

### 破坏面与下游可见行为变更


1. **教学推断/标注文案全族修真（审阅 v2 批 B12，#436；B11 teaching_truth 闸 39 条失真登记全数翻面，2026-11-04）**：① `infer_gcd` mod 算式余数改算术事实 `x % y`（t 换行暂存形态行末 b 未更新，旧文案每帧错报旧 b）；② bubble compare/swap 下标对改**行内容提取**（旧恒拼 j/j+1 与 `arr[i]>arr[j]` 行脱钩）+ 守卫改数组界语义（旧 `j<n-1-i` 模板界吞无 -i 变体后半程合法帧）+ 交换组**跨迭代幽灵帧守卫**（行帧串跨 for 增量的末帧不产 swap——新发现的既有失真面）；③ BFS/DFS `visit` 判据收紧为 `visited[X]=1` 裸赋值形态（重置行 `=0`/判断行 `==` 误标消除，dijkstra U1#1 P0-1 同族补修）+ 节点值取行内下标变量（旧取 u/front/start 与行脱钩、白盒 -1 直拼）；④ KMP 回溯读形态（`j=next[j]`/`k=next[k]`）前置判定——skip 词汇复活（旧被 build_next 判据吞、回溯后 j 当下标报建表文案）；⑤ `string_reverse` swap 判据收紧半长形态 `len/2`（打印循环误标 swap + 自交换荒谬帧消除）；⑥ quick `partition_init` 判据补 RHS `partition(` 调用形态（取枢轴行/分区判断行的「枢轴值当落位下标」消除）；⑦ `is_swap_assign_line` v3：RHS 须下标读或教科书暂存名（`visited[i]=0`/`next[j]=k`/`arr[i]=i`/`queue[rear++]=v` 单向下标写不再判交换——collector semantic_label 的「交换 arr[N]↔arr[N+1]」大面积误标族消除）；⑧ collector 交换 label 下标/数组名改行内提取（单源 `swap_index_pair`，**新 pub fn**——旧 pick_inner_index 回退末位 + 恒 +1 的 arr[5]↔arr[6] 越界/arr[-1]↔arr[0] 负哨兵消除，回写行对侧无据不产）；⑨ detect：`prim` 判据改 `has_word` 整词（isPrime 误配 prim_mst 消除）、binary 结构分支补 Identifier 赋值形态（`left=mid+1` 真二分检出——锚二十九翻案）、quick 结构分支去 `has_nested_loops` 死锁（形态 A「递归调 partition」检出）、merge 结构分支补 `has_single_loop` 语境门槛（递归链表归并 mergeTwoLists 误命中消除）；⑩ trace_analyzer 越界根因初值权威源改循环头 init 解析（`for (int i=0; i<=5` 的 i 从 0 起 OffByOne 旧被 20 帧窗口截断误判 WrongInit「建议将初始值改为 0」）。消费面：`algorithm_step.description`/`semantic_label`/`root_cause_hint` 出口文案与**帧产出面**变化——① swap 播报从交换组三行三帧收缩为主行一帧（回写行串末帧恒为跨迭代幽灵、暂存读行本就无帧——PR #463 审阅 P3-4 点名：教学观感变化，逐帧 stepper 少两帧）；② 非交换行（重置/建表/入队/初始化）的 collector「交换」label 全消失（落循环变量播报或行号兜底）；③ KMP skip 帧文案不拼下标数字（审阅 P2-1 处方 b——next[N] 的 N 混新旧值语义）。demo 透传自动正；teaching_annotation_diff golden v3 重冻（122 处正当漂移）。
2. **诊断卡文案**：E0（未分类——codegen 无码错误兜底卡，#409 N1）三字段中性化——title「内部错误（未分类）」→「未分类错误」；explanation 去除「而不是你的代码有明确的语义错误」断言（对容量超限/级联未声明等用户代码错误撒谎），改「以上方错误信息为准…指向你的代码则按提示修改」；common_causes 换容量上限 + 级联未声明两条用户侧成因 + 编译器边界一条。`error_catalog` 方法与 compile 诊断 `fix_suggestion`（空 suggestion 回退链）出口文案随之变化。
3. **typeck 声明/初始化四处（审阅 v2 批 B9，#433；M09 报告四处方，clang/gcc 三方对拍）**：① 具名 union 字段 brace elision 从 E3006 硬拒 → 接受（`struct S{union U u; int x;} s={1,2,3,4};` 扁平流按首成员叶数重组，C11 §6.7.9p17/p20，clang 仅 -Wmissing-braces）；② `static int a=1, b=n;` 的 extra 变量从丢 static 轨（非常量初始化零诊断误收+静默置 0）→ 整条声明同轨（C11 §6.7.1，非常量初始化器报 E3075 对齐 clang）；③ W3084「可能缺少 return」判据不再下钻嵌套循环（`while(1){while(c)break;}` 假警消除）且 Block 遇 return 即停（其后不可达 break 不再假警）；④ W3005「初始化列表元素超量」判定移到 brace elision 重组之后按重组后元素数判（`struct Out{struct In in; int c;} o={1,2,3};` 假警消除；真超量仍警）。
4. **typedef union / 嵌套 union / 不完整数组（审阅 v2 批 B9 第二批，#433；M03/M10c 报告处方，clang/gcc 五方对拍）**：① `typedef union TAG{...} alias;` 从 E2005×3+E3042×2 炸穿 → 接受（dispatch 前瞻补 Union + Union 臂补 tag+body 分支，对称 typedef struct 病 38 形态；匿名/具名/指针别名全形态通）；② struct 成员位与局部 `union {...}` 的 `sizeof` 编译期折叠从 E1006 假阳性 → 正确（parse_struct_body 的 is_union 透传——union 误记 struct 表致 snapshot_unions 查无；运行时 sizeof 本就正确）；③ `extern int m[][3]; int m[2][3];` 多维不完整数组升级从永不触发（判据 es==-1 只合一维）+ 重建尺寸误用首维 → 判据 dims[0]==-1 + 尺寸取 dims 乘积（sizeof 12→24 对齐 clang；三维 48→96 同理）；④ `sizeof(不完整数组)` 从零诊断静默 rv=4 → E3076 对齐 clang error（判据 array_size≤0 且 dims[0]==-1，`char g[]="str"` 的尺寸回写形态不误伤）；⑤ 函数重定义三漏检从零诊断 → E3003 对齐 clang：variadic 位入签名判等（`int f(int,...)` vs `int f(int)`）、原型+定义+定义的第二定义（is_definition 回写）、static 与非 static 双表交叉互斥（C11 §6.2.2p7 链接性冲突）。
5. **`VMSnapshot.heatmap` 类型变更（pub(all) 字段，#176 P0b，2026-11-02）**：`Map[Int32, UInt64]` → `FixedArray[UInt64]`（行号下标即计数，未命中行为 0 不变）——**下游直读该字段者编译红**，改经 `VitroVM::heatmap_count_at` 读口（签名与语义不变）。同批 `VitroVM` 字段面：新增 `observe : Bool`（run 全速态观测落闸开关——`run()` 自进自出自管，非会话配置）与 `vis_events_by_line`（vis 事件行号派生索引）两字段、`heatmap` 转 `mut`（惰性扩容）。
6. **run 全速态观测语义（#176 P0）**：`VitroVM::run()` 执行期间 heatmap / `last_accessed_vars` / StepEvent vis 事件队列三件**不记录**（run 前后三件恒空——run 入口清 `last_accessed_vars`；三件在 run 态零消费方，消费面全在 step 态 engine/collector，#176 §5 亲证）。step 态逐步（单步/断点/时间旅行/逐帧采集）逐字保留。协议字段 `heatmap_count` 的「截至本步累计」口径限定为 step 态累计（schema 文档已同步）。
7. **CLI `compile --json` 首次有 stdout 输出（B3 批 2026-11-02，审阅 v2 M35 A6）**：diag 帧（`{"type":"diag","frame":…}`，与 `run --json` 同形）自此落 stdout——旧形态 lib 内 drop 通道吞帧，失败/成功两路 stdout 均 0 字节（rc=1 却无诊断可读）。文本模式不变（stdout 恒空、COMPILE-OK/诊断行走 stderr）。连坐：`cmd/lib/cli.compile` **签名加 `write_stdout~ : (Bytes) -> Unit` 具名参数**（pub 面变更，四壳调用点同批接线）；`cmd/compile` 独立 exe 补 stdout_stub.c（第四副本，single_source 闸纳管）。
8. **CLI `step` rc=3（步数超限）首次可达（M35 A2'）**：判定串对齐引擎现行 step-limit 文案「程序执行步数达到预算上限」——旧串「超过限制」与模板失配致所有 step-limit 恒 rc=2（契约 §2 的 3 在 step 上从不成立）；`--max-steps` 域检对齐 run 的 1..=2147483647（旧 0 被静默钳 1）、尾置缺值文案对齐 run。
9. **CLI `api` 未知旗标 fail loud rc=4（M35 A1）**：旧前置旗标静默吞照常执行 rc=0、尾随旗标误报成 params；api 仅认 `--batch`。
10. **gateway 目标面 `+wasm`（R3 P1-1）**：`supported_targets` 补 wasm 使 `moon info` 落盘 `gateway/pkg.generated.mbti`（下游 `invoke` 签名可发现；0.9.1 包内无此文件）；`append_leak_report` pub→priv（纯同包消费）；裸 `moon test` 自此纳入 gateway（158 用例）。
11. **fs native 臂两处行为修复（vendored fs_native.c 本地逻辑修复，THIRD_PARTY.md 登记）**：① `is_dir`/`is_file`/`path_exists` 失败消息不再张冠李戴（Win32 stat 族失败按 GetLastError 映射 errno；旧形态读前序 CRT 残留——`create_dir` 已存在后 `is_dir(不存在)` 报 "File exists"，M37 A-3）；② `read_dir` 单遍历动态缓冲（旧两遍历 TOCTOU：遍历间目录收缩尾部 NULL 槽 / 增长越界写，V3-③-A1）。三后端行为分歧矩阵登记于 `fs/fs.mbt` 头注。
12. **dump 族产物名与门禁（M36）**：`dump_ast`/`dump_typeck` 裸名单文件模式产物名统一含 `.c`（`good.c.ast.json`——旧裸名丢 .c 与目录模式分裂）；四 dump 参数过多 / 输出目录==语料目录 一律 rc=4 拒绝（旧 ast/typeck/tokens 三家静默忽略、out==target 直接污染语料目录）；`dump_compile` VFS 收集改收全部文件（与另三家同形，`#include "part.c"` 不再独家 E1021）。
13. **`@vitro/protocol` TS 绑定（V3-②）**：`exports["."]` 补 `import` 运行时入口（旧 `import { SCHEMA_VERSION } from "@vitro/protocol"` 编译过、运行时 ERR_PACKAGE_PATH_NOT_EXPORTED）；`./fields` 补 `types`（新生成物 `fields.d.ts`，字面量精确类型，gen_protocol_ts 第三产物）；consumer MAX_STEPS 400→800。
14. **README**：新增「端到端（喂 C 源码 → 诊断 + stdout + 退出码）」节 + gateway 行「下游可直接 import」+ session 内部件声明 + Windows 下游 `MOON_CC=clang-cl` 口径；仓库新增 `examples/downstream-mini-c/`（独立 module 钉 `vitro/engine@0.9.1`，五步管线 + gateway NDJSON 两形态，三目标输出逐字一致）。
15. **行为修复（下游可感知，#425 审阅 v2 B2 批）**：判零截断族三案——① 复合赋值右值不再预收口到左类型（C11 6.5.16.2p3：`E1 op= E2 ≡ E1 = (T)(E1 op E2)`，op 按常规算术转换）——旧形态 `x *= 0.5` ≡ `x *= (int)0.5`（错值 0）且 `x /= 0.5` 假除零 trap 误杀合法程序；现运算域提升（compound_domain 单源，int<char<int 域序 + 病 30/34 unsigned 口径）+ 运算后窄化由 codegen 发射。② `&&`/`||` 操作数判零弃截断 Cast（CastF2I/D2I/Q2I——(0,1) 开区间浮点恒判假）改数值比较（`PushConstF/D/Q 0 + NeF/NeD/NeQ`）。③ `!` 按操作数类型数值零判（f32 位模式 0x80000000 判真、LL 只看低 32 位的位判病根除；int 家族照旧）。缺直连指令的 Q↔F 两形态走双跳（CastQ2F/F2Q 不存在，经 D 中转——精度注登记 M12-A2 族）。codegen digest 7 例存量重冻（产物变、运行输出零变化）；vm 存量零漂移。
16. **行为修复（下游可感知，#424 审阅 v2 B1 批）**：全局初始化装载层按声明宽度写——char 目标（数组 designated / 标量字面量 / `char[]` 字符串逐字节 / struct char 成员）原一律经 `globals_init_32` 无条件 4 字节 store，负值符号扩展 `0xFFFFFFFF` 越权抹相邻全局（`char a=300; char b;` → b=1、`char a[4]={[1]=-1}` → a[2]/a[3]=-1、无初值邻居永久污染）；现按 4 字节对齐字小端合并（`push_char_init_byte` 单源）装载，与 C 真值逐位一致。同批：static 局部指针以裸数组名初始化不再静默置 NULL（E3083 trap 消除）；static 局部函数指针数组元素不再静默落 0（CallPtr 越界 trap 消除）；嵌套 struct 赋值（call 实参位置 `a = id(b = c)`）dst 地址槽按嵌套深度分层，外层拷贝不再写错目标。dump 产物 `globals_init_32` 表形态随之变化（char 条目合并为字、前插）；11 个存量语料 codegen digest 重冻（运行输出零变化）。
17. **诊断修复（下游可感知，#424 B1 遗留批）**：W3053「被隐式转换为 char」豁免边界两处修正——① 豁免域按**目标符号性**判（signed char [-128,127] / unsigned char [0,255]；旧只按 signed 域，`unsigned char u = 200` 域内值误警）；② 补 **Neg 字面量臂**（`char c = -1` / designated `[1] = -1` / `static char sc = -2` 惯用写法旧落 `_ => false` 全误警）；③ 补齐 W0-4 漏豁免的**全局标量**与 **struct char 成员**两路径（`struct S1 a = {7}` / `{'a'}`——char 常量按 C 语义定型 int，旧 struct 路径未调豁免谓词）。域外真截断（`char c = -300` / `unsigned char u = -1, 300`）维持教学警（比 clang 默认严一档，-Wextra/-Wconstant-conversion 同判）。同批 M11-B3：局部 struct 数组 designated 嵌套聚合元素的 E3006 误导游说（「期望 'struct S'，实际 'void'」——InitList 占位类型当实际类型报）改为全局版收窄文案「designated initializer 的嵌套聚合元素暂不支持」。typeck digest 9 例存量重冻（全部为 W3053 误警消失）；运行期输出与 codegen/vm 产物零变化。
18. **诊断修复（下游可感知，#459 审阅处置批 P2-1）**：W3053 char 豁免补**普通赋值路径**——`gq.c = 'B'`（struct 成员赋值）/ `char d; d = 'C';` / `d = -1`（域内 Neg）此前仍误警（初始化器四路径已豁免而 `resolve_assign` 的 `check_assignable` 漏包裹，同族面只修一半）；现与初始化器同款包裹、豁免判定单源 `is_char_safe_initializer`。边界：域外 `a = 200` 教学警保留；复合赋值（`c += 1`）不在豁免域（提升回写非初始化器语义）。typeck digest 62 处重冻（全部为 W3053 误报消失，含 m12/m13 两处 = B1 遗留批豁免语义对 #464 新语料的 rebase 首覆）；realcode gold 重冻（chibicc +1 / multifile +174 条误报消失，H3057 提示与 E 系零变化）；运行期输出与 codegen/vm 产物零变化（vm_diff 818 SAME / clang_direct 931·18·0）。

19. **printf 族行为修复（#427 审阅 v2 批 B4，2026-11-03；clang/gcc 三方对拍 + 三臂一致；PR #462 审阅处置批 2026-11-04 扩）**：① **`format_fixed`（pub 函数）NaN 输出 `"NaN"` → `"nan"`**（C11 7.21.6.1 小写口径——下游直调该函数且断言 NaN 拼法者需连坐）；② `%a/%A` 从字母原样+实参不消耗+后续转换符错位 → hexfloat 规范输出（随 glibc「最短精确」`0x1.8p+0`；UCRT 13 位全印属实现定义域分叉）、`%F` 从字母原样 → %f 同义+大写 inf/nan、`%n` 从不写回 → 写回已输出字符数（按 hh/h/l/ll 分档）；③ `%05.0d` 族从**三臂进程崩溃** → 空格填充（C11 精度在场 0 旗标忽略）；④ `%hhd/%hd/%hhu/%hu` 从不截断 → 按修饰截断（`%hhd` 300 → 44）；⑤ `%#08x` 前缀位置（`0x0000ff`）、`%#g` 保尾零、`%q` 未知字母输出与实参余量无关；⑥ `%.17g/%.17e` 高精度段换 bigint 精确路径（1e23/1e126/1.5e126/次正规/DBL_TRUE_MIN 全对齐 clang——`infe-324` 泄漏清账）；⑦ vprintf 族 len≥4 字符串实参从 VM 栈下溢崩溃 → 正常（codegen 变参 word 计数数组退化）；⑧ scanf/sscanf `%3c` 宽度生效（旧只读 1 字节）。typeck 连坐：printf `%n` 判据正向化（`&x` 零警 / `42` 报 W3062）、`a/A` 补类型判据臂（conv_specs 闸 printf 族两面 18/18）。**审阅处置批（PR #462 评论）追加**：⑨ `sprintf`/`snprintf` 的 float 实参提升 double（P1——旧 `CastF2D` 白名单只认 printf/fprintf，float 位模式当 double 直传静默错值：`sprintf(b,"%f",3.25f)` → `0.000000`）；⑩ `#` 对 o 改「提精度」语义（P2-1/2：`%#.3o` 8 → `010` 非 `0010`、`%#.0o` 0 → `0` 非空串）；⑪ `#` 恒含小数点族（P2-3：`%#.0f` → `2.`、`%#.0e` → `2.e+00`——f/F/e/E 臂补 alt）；⑫ typeck `%ln/%lln/%hn/%hhn` 判据补段（P3-2）。

20. **MCP 播放器产物两缺陷修复（#468/#469，DSH mbt 化批连坐，2026-11-04）**：① extern 模板字面量转义丢失（#468）——PLAYER 模板内 `\s`/`\w`/`\d`/`\[` 与 `split("\n")` 被 node 模板解释层吃掉，产物 `<script>` 段整段 SyntaxError（static/interactive 双模式播放器交互全灭——播放/单步/滑条/主题/键盘/朗读全不可用，页面只有 CSS 骨架）；修复 = 模板内转义双写 + `mcp_smoke` 扩产物 script 语法门（vm.Script 编译）与 PLAYER 逐帧驱动对拍（双语料 swap 锚 5/21，J9 突变双证红）；工具链陷阱条目补录（moonbit/AGENTS.md 陷阱 44——extern 模板字面量多层转义）。② swap 高亮归属过滤恒假（#469）——字幕展示名 `arr` ≠ 数组真名（如 `a`）时壳层正则咬字幕形态恒 false，swap 类名零渲染（401 帧 × 399 交换字幕帧全灭）；修复 = `swapPair` 改 vis_events context 归属（demo `visEvents.ts` 同款守卫：ty=2 + context 点名 + 哨兵/越界/相等丢弃），字幕正则兜底退役（脆弱前缀匹配形态——protocol `semantic_label_id` 立项理由早已否决）。
21. **MCP 审阅 v2 处置批（PR #457，2026-11-04——P2×4 + P3-②③，下游可见行为变更）**：① `frames_query` 的 `to` 不再旁路「每页 ≤50」（to 与 start+limit 双上限取小——修前 `{to:超界}` 一次吐全量帧、`{to,limit}` 并存时 limit 被无视）；② 多文件工程 `session_open` 的 overview 行号与帧行号同基（引擎拼接坐标——compile 出口**新增 `file_ranges` 字段**〔merge_units 区间表出口化，只增不改〕，mcp 侧 offset 映射；修前 agent 按 overview 调 `filter.line`/`run_to{breakpoint_line}` 静默空集）；③ 无 id 的通知形态 `tools/call`/`tools/list`/`ping`/`initialize` 不执行不回帧（JSON-RPC 通知无响应——修前通知形态 tools/call 真建会话且回 `id:null` 帧）；④ `session_open` inputSchema `required` 置空（source/files 二选一由校验兜底——修前 `["source"]` 与「给 files 则 source 可省」自相矛盾，严格校验客户端拒纯 files 调用）；⑤ `render`/`animate` 的 `ok` 语义改「产物已落盘」+ 新增 `compile_ok` 字段（编译失败的诊断卡是可用交付物——修前 ok:false 让按 ok 判断的 agent 丢弃已落盘产物）；⑥ `files[].source` 补 64KB 上限（修前 files 通道绕过顶层 source 校验）。
22. **MCP 仓外资产收编（PR #457 审阅 v2 P3-④ 销案，2026-11-04）**：① 黑盒验收 `accept.mts`（28 断言——CI 跑 27，PNG 预览断言依赖本机 Edge/Chrome 仅本地）收编至 `scripts/moonbit/mcp_smoke/accept.mts` 并挂 CI `cli_smoke` 步（原 `D:/tmp/vitro-dsh-plugin/` 仓外件——读者无法核对，审阅实锤）；顺手修仓外版两处：`VITRO_MCP_WCP` 环境变量 typo → `VITRO_MCP_WASM`、编译错诊断卡断言按 #16-⑤ ok/compile_ok 新契约翻面。② 设计单源 `design.md` 收编至 `docs/current/06-出口与协议/DSH-MCP设计单源.md`（历史设计稿原样冻结 + 收编横幅；`mcp/moon.pkg` 与 DSH-MCP服务器.md 引用改仓内相对路径，docs 索引连坐）。
23. **seek 族六形态修复（审阅 v2 批 B7+B7b，#430；M26 A1/A2/A3/C1 + M31 A-2 + R4 H1 三源汇流，2026-11-04）**：⑥ **视口回看脱节自动对齐（B7b，M31 A-2 证据二——用户拍板直修不登记）**：窗口内 seek（直返）只移动视口不动 VM（engine 记 `viewport_step`），`step.next` 续跑前发现 VM 在视口未来即重放对齐到视口——发布流从视口后继连续推进（教学播放器语义：seek=拖进度条、下一步=视口下一帧；旧形态 VM 在原位置续跑——用户 seek(100) 后下一步拿到 step_index=1000「瞬移」）。触发面收窄：trap 史会话不对齐（`saw_trap` 粘性——trap 回退位重放会重现 trap 且重投旧帧，保持 rollback_before_trap 直接续跑既有语义）；every 采样批的 step_count>max 常态脱节不涉。⑦ **等待输入态零重复投递（B7b）**：scanf 等待步 ip/步数双回退语义下，旧形态每次续调 `step.next` 重新 collect 同号帧→发布缓冲滚动重发（同一帧反复投递，违反「每真实步恰投递一次」）——engine `run_batch` 等待态零投递守卫（空批 + `waiting_input:true` 照报；`input.feed` 清位后续跑正常）。原 ①—⑤（B7 主批）：① 越窗 seek 不再回滚会话配置——断点/暂停位是会话层配置非执行状态，`VitroVM::restore` 保留现役值（`VMSnapshot` 侧两字段仍记录、仅诊断用，恢复侧不再消费——有意偏离 Rust oracle 照搬渊源〔oracle 同病〕）；重放区间命中断点只标记不拦（命中即时解除，防非断点行假暂停）。「设断点 → 快进滑窗 → seek 回退重看 → 续跑」断点不再静默失效。② seek 成功即清发布缓冲 `unified_pending`（两臂一致——窗口内直返清亦无损，下一次 step.next 重建、首调回到空帧形态）：越窗回退后旧 pending「未来帧」不再倒挂发布流（旧形态首批发布 step_index=2599 再跳回 4）。③ `seek` 负数目标参数层 param_err（`expected:"step:int>=0"`，#133 分类文案同款）+ engine `seek_to` 负值零副作用早退——旧形态落入越窗分支：已收集帧窗全毁 + VM 静默回滚 +「无法获取目标步的 payload」误导文案。④ 终态 seek 幽灵终帧治本（M31 A-2）：窗口内直返臂不再复位 `is_finished`（直返只移动视口不动 VM——无时间旅行，终态粘性保持；`is_trapped` 复位保留——trap 态有 rollback_before_trap 真·回退机制接续，两态不对称有意）；越窗重放臂到达终态时置位 `is_finished`（旧形态漏置）。两臂统一「终态 seek 后 step.next = 空批 + finished」，不再产 step_index 与终帧同号重复/越终步 +1 的幽灵帧。⑤ `breakpoints.set` 参数域 fail loud：缺 `lines` / 非数组 / 元素非整数一律 param_err（`expected:"lines:int[]"`；旧形态静默当空 = 清空断点并恢复运行——一次手滑即静默改变执行语义）；空数组仍是显式清空（两层恢复语义不变）。连坐：protocol_frames 基线重冻 48→74 帧（seek 组合 26 帧入表：负数 param_err / 越窗 seek × 断点存活命中 / 发布流重建 / 粘性暂停帧 / 视口对齐帧〔B7b——seek(600) 直返后发布 601 视口后继〕）；gateway 锚 `serve_step_seek_roundtrip_and_payload_get` 断言值随 ② 翻面（首调空帧形态 + 第二调发布）；`UnifiedEngine` 新增 `saw_trap`/`viewport_step` 两内部字段（pub struct 面，零行为出口）。
## [0.9.1] - 2026-10-31（在架事故修复版——moonc ≥0.10.18 删 core/abort 致 0.9.0 包下游 `moon add` 后 build 必红；版本号口径见 [0.9.1.md](../docs/current/08-发布档案/0.9.1.md)）

### 破坏面与下游可见行为变更（0.9.0 → 0.9.1）

2. **发版动因（在架事故）**：moonc ≥0.10.18 删除 core/abort——0.9.0 包内引用链在下游新工具链下 `build` 必红（#402 实锤），0.9.1 重建发布物修复断供。
3. **新增方法**：`vfs.list` VFS 预置文件列举口（#95）——gateway 方法表 +1；`algorithms.catalog` 引擎静态出口（#36 三源收编——demo 生成器族集/display_name/分组改读引擎单源）。
4. **行为修复（下游可感知）**：#366 帧出口管道截断（长输出后半截）治本；#363 invalid UTF-8 三臂统一 U+FFFD；#207/#319 run 文本模式 stdout 尾换行四口径统一（原样零修饰）；#66 `\xHH` 字面量 NUL 终止尺寸治本（`char g[]="\xff"` 族越界读根除）；#356 绝对路径主文件 quote-include 候选键 POSIX 锚。
5. **诊断/夹具域**：#324 E-08 渲染金标准夹具整体换引擎实产（同形性机判闸）；#213 语法错不再遮蔽语义错（照跑 typeck）。
6. **opcode 契约**：154..155 u64→fp 无符号对偶（CastUQ2D/CastUQ2F，#345 审阅 P1）——总数 151→153。
24. **新增 `vitro/engine/wasmenc` 包（REHOST 批 1a，2026-11-05——153 码表 wasm 子集实体化的表驱动发射/折叠骨架，纯增量叶包零行为）**：L0 编码库（LEB128 u/s 编解码 + `WInstr` 指令集字节编解码 + wasm 段结构 ModuleBuilder/解析器，探针 166 行 JS 的 MoonBit 直译）+ L1 语义表（`template_spec` 153 臂穷尽：四态标注 + 栈效应 + 发射模板单源——A 类完全一致 83 / B 类组合可逆 50 / C 类歧义需侧车 13 / D 类不可映射 7，计数闭合 153；对账修正：AddQ/SubQ/MulQ 系回绕不 trap 归 A〔exec_float.mbt:216 亲读〕、And/Or 短路占位零发射归 D〔binary.mbt:380-382〕、PushArgc/PushArgv 字节同形移 C、TruncUByte 因 wasm 无 extend8_u〔wabt 编译实证〕移 B）。A 类 83 条全量「发射→折叠→比对」往返 + 混编模块级闭环 + fail loud 拒载 + 组表侧车核对协议（篡改检出）+ soft-stack 双实现对拍（mini wasm 栈机 vs Vitro 位模式参照逐位一致）+ spec 码位锚（开发期 wabt 外部验证 86/86——实证抓出 6 处记忆码位错）+ J9 两路检出。B/C/D 态臂表内标注、发射/折叠 NotImplemented 拒载（批 1b/1c 接线）。测试 +16（裸/native 双口径）；pkg_deps L0 + surface 边 30/白名单 12 连坐；设计单同批出勘误版（探针实证修正三处 + 对账勘误 + §6 V8 全托管叙事）。

## [0.9.0] - 2026-10-25（S9 收官版；已发布——实录见 08-发布档案/0.9.0.md）

> S9 收官版：Rust oracle 脱钩 + 裁定 + 解锁修复面。发布档案：[0.9.0.md](../docs/current/08-发布档案/0.9.0.md)。

### 破坏面与下游可见行为变更（0.8.0 → 0.9.0）

2. **CLI 行为**：#129 通道分立——文本模式 stdout 只承载程序输出，编译诊断/note/标记行走 stderr（下游解析脚本须更新剥离逻辑；`--json` 出口不变）；#67/#68 错误帧带期望形状 + api help 双产物；#91 截断显式化；#92 诊断 E 码前置；#94/#105 config 钳制/未知键 fail loud；#96 libc 缺口走 E3073 专用码；#133 preset 三档 + `run --max-steps`。
3. **协议面**：`code_file` 等 v0.2 预留位字段激活（「字段↔最低版本」表见 #116 销案文档）；`texts.install` 新方法。
4. **包面**：新增 `vitro/engine/icons` / `vitro/engine/stdlib` 两包；接口面 `.mbti` 净 +392/−18 pub fn（4 新包 + 21 包改动）——删除/重排代表：`tokenize_with_vfs` → `tokenize_with[P : @token.SourceProvider]`、`UnifiedEngine::run_batch` 加 `SourceLineProvider` 约束、host printf 族通道化移位；`type_display_name` gateway→ast 上提。
5. **opcode 契约**：U 系对偶段 138..150 扩容 + 151..153 char 字节粒度段，总数 135→151。
6. **码表**：ErrorCode 137→156 臂；error_catalog 教学卡 77→114（补 14 退 9）；gateway 方法表 21→30。
7. **发布物内容面**：协议契约文档（`docs/spec/CLI_PROTOCOL_V1.md`）与 TS 消费绑定（`bindings/ts/`）随包分发（随 PR #307 合入生效）。

### chore(scripts): jsonmbt 空壳清退——39 个无主 moon.pkg + moon.mod + moon.work 删除（用户审计发现）

【定性】scripts/ 下 39 个 moon.pkg（含根 scripts/moon.pkg 空块 + 
scripts/moonbit/moon.pkg）+ moon.mod + moon.work = jsonmbt 合流批
（7c9c7e6d，2026-10-08「11 目录 moon.pkg」）的遗留物——.json.mbt
随 #125 批 C 退役后文件未清；实测 find scripts -name "*.mbt"
（_build 外）= 0、全部驱动均为 Go（README 载明「scripts/moonbit/
下全为 Go」）。风险 = 「MoonBit 化脚本在推进」的假证据 + 假接线雷
（cd scripts && moon check 静默绿 rc=0——ci.yml 两步已注释暂未炸，
有人接闸即永久假绿）。

【处置】git rm 39 moon.pkg + moon.mod + moon.work；删后审计：
moon check 显式报「not in a Moon project」（静默假绿 → 显式错，
语义归位）；go build ./scripts/... 全绿；ci_checklist / 
moonbit_surface / source_hygiene / facts / testcount 五闸复验全绿。
清前审计：worktree 无依赖、闸内代码零引用（历史文档 
docs/current/07-质量与裁定/20261007_jsonmbt真相源迁移.md 的记载
按归档纪律不改写——它记录的是当时形态）。

【教训登记】退役批的「文件清退义务」缺闸——.json.mbt 有翻转闸盯
真源翻转，但翻译过来的空 moon.pkg 无死文件侦测；后续若再立
「X 退役」批，退出清单应含「中间态脚手架回收」项。


### fix(ci+scripts+demo): 云端 CI 双红处置——surface 边漏登记 + E2E DevTools 端口竞态

【surface audit 红（71c658ad run 39127326546）】#162 codegen wbtest
锚手写 AST 新增 codegen→ast FuncDecl/StructDecl 两条消费边漏登记
（纪律 11 连坐面）——surface_edges.txt 按字母序补齐，
moonbit_surface -check 本地复绿。

【Demo E2E 红】E2E 异常 connect ECONNREFUSED 127.0.0.1:9222——
chrome DevTools 端口就绪前连接（"DevTools listening" 日志出现在
异常之后 = sleep 4 固定等待竞态实锤）。五个 e2e 脚本
（diagcard/session/workspace/bootfail/editor）的 /json/list 连接段
统一加就绪重试（ECONNREFUSED 退避 10×500ms）；node --check 全过、
本地 Edge 实跑 diagcard 连接链通。**bootfail/editor 为工作区未跟踪
新文件（用户 #184 demo 在途批）**——同款修复顺带应用，与用户改动
（W18 锚等）无冲突。


### feat(scripts+ci): 对抗分叉防线制度化——scripts/corpus_fuzz（用户拍板：CI 动态生成不落库 + 指纹基线锁定 + 本地缓存）

【形态】存量语料（四 suite 确定性抽样 20×4 种子）× 语义靶制变异
算子（11 个：等价变换类 cmp_swap/paren_wrap/cast_strip/nested2flat/
brace_strip + 已修复面定向类 static_inject(#171/#179)/brace_wrap
(#183)/char_escape(#181)/init_partial/memset_zero(#19)/div2shift）
→ clang -O0 × js × native 三方对拍分桶（六桶，ARM_DIVERGENCE 最优
先）。**机械数值盲改类算子（u 后缀/类型互换/常量改写等九个）按用户
拍板剔除**——对抗要有语义意义，盲改产出随机程序只有噪声。

【指纹基线制】指纹 = (suite/seed, mutator) → bucket；fuzz_baseline.json
入库（240 条 + 定性 note：gap 族 UB/arch_diff 域、static 运行时初始
化误收面候选、等价变换真病候选待挖）；新指纹/桶恶化 fail loud rc=1
（J9 验证：抽基线条目 rc=1 红）；变体 CI 动态生成不落库（本地
.corpus_fuzz_cache/ gitignored 缓存）。

【CI】corpus-fuzz job（windows，消费 build-products artifact——
native exe + js 产物 + 预装 node），~4min。

【首跑定性线索（留下批）】CLANG_REJECT×60（static 局部运行时初始化
vitro 收 clang 拒——误收面候选）；WRONG_VALUE×15（等价变换分叉真病
候选）；VITRO_TRAP×5（受检 vs UB 崩溃域）。

【管道坑实录】变体必须带 .c 后缀（clang 按扩展名识别——无后缀
84% 假 CLANG_REJECT）；spawn 必须显式空 stdin（Windows nil 继承终
端句柄 scanf 族挂死）；native 臂 spawn 漏 --json = 文本模式解析不
出 → 59% 假 ARM_DIVERGENCE；单例 20s 硬超时兜底。


### fix(typeck): 深挖批大货——#183 标量初始化器大括号包裹全线误拒（C11 6.7.9p11 零支持，对抗 excess 形态定性反转）

【定性反转】对抗批 3 例 excess 形态原判「宽容度差异登记不修」——深
挖 clang 行为（w=4,0,7 恰拟合「{K,M} 作 g 扁平 + {M,K} 给标量 n 取
首 + 末元素 excess」）后反转：根子是**独立合法语法面全线缺失**——
C11 §6.7.9p11「标量初始化器为可选大括号包裹的表达式」：`int x={5}`
≡ 5、`int y={9,10}` 取首 9（clang -Wexcess 警告口径）、标量字段
`{{7},{'b'}}`、数组标量元素 `{1,{2},3}`、全局 `int g={42}`——九形态
矩阵全部误拒（报错文案还是误导性 void 错）。

【修】unwrap_scalar_braces 单源（InitList 非空取首 + 多余 W3005；
空 {} 不解包——C11 空初始化器只给聚合；仅初始化器语境——赋值不吃
brace）+ 四收口点接线（局部 VarDecl / 全局标量 / check_field_value
标量字段 / check_array_elem_value 数组元素）。AST 改写单源交既有
resolve/fold 链——codegen 零改动。

【锚与验收】wbtest scalar_brace_unwrap_four_sites（突变 unwrap
no-op 化立红验证区分力）；九形态矩阵 + 对抗 H_049/052/055 逐字对齐
clang（js+native 双臂）；对抗 126 例重拍误拒清零；typeck 74/74、
vm_diff 四套件 696 全 SAME、裸 824/824、native 970/970。语料 +1
scalar_brace_init.c；#183 立档（excess「宽容度差异」登记就此销案）。

### fix(typeck): 随机分叉对抗批——elision 域两邻面虫（字符串行部分填充 / 变量扁平流）随挖随修

【对抗面】本轮对话全部修复面随机分叉（生成器 126 例 = elision/char
变量/转义三域 70 + memchr/sscanf 尾参/struct 实参/符号性折叠/静态
枚举多维四域 56；clang × js × native 三方对拍分桶）。

【虫 α】struct MD{char d[2][4];} v={"ab"}——多维 char 字符串行部分
填充（C11 6.7.9p14 当前子对象），clang 零警告接受；旧多维 `_ =>` 臂
一律拒。修 = StringLiteral + char 基类型放行（codegen #137 臂承接）。

【虫 β】struct S2{char u[2][3];} fv={c,d,0,c,0,0}——#180 首版收紧面
（全字面量）排除变量流致 E3006。修 = 启用面改「resolve 定型后非聚合」
（is_scalar_init_expr——变量/算术式可组、聚合值元素仍排除 #143
形态；顺带回写定型）。

【非虫残余（登记）】excess+深 elision 混合（clang -Wexcess 警告接受/
vitro 从严拒）——次规范形态维持差异；无终止 %s 越界读 UB 域。

【语料 +1】struct_char_row_partial_init（四段）；vm_diff 四套件 694
全 SAME、typeck 73/73、裸 823/823；修复后对抗重拍误拒清零。

### fix(codegen+typeck+lexer): 探针六/七批处置——#179/#180 局部初始化双病 + #173 char 变量初始化 + #181 转义双引号（红锚先行）

【#179 struct 成员多维嵌套错位】gen_nested_init 数组臂步长旧用
elem_type_size（base 元素 4）而 subscript_type() 是子数组（行 12）——
{{1,2,3},{4,5,6}} 第二行 4 字节步进写穿覆盖前行尾得 1,4,5,6,0,0。
修 = 步长改 type_size(subscript_type())；与 #171（static 裸数组）、
emit_field_init（静态 struct）三路径互补归位。

【#180 struct 成员数组 brace elision（C99 6.7.9p20）】typeck 位置
路径新增纯字面量标量流重组（标量字段吃 1、聚合字段按叶标量总数
流式消耗，余零填——agg_scalar_leaf_count 递归计量；启用面收紧为
字面量类叶子防 #143 锚 Member 元素误伤）+ codegen 扁平标量流按
base 步进（与 #179 行步长互斥两形态；字符串元素仍按行 #137 臂）。
`{1,2,3,4,5,6}` 旧 E3006+W3005 误拒，现四形态（单聚合/标量前置/
struct 字段/部分填充）与 clang 逐字一致。

【#173 char 局部数组变量初始化写 0】一维 char 快径 flatten_init_list
对变量元素落 _=>0 兜底（{c,'\0'} 整串 0 变空串——LONG7 词法器
op_buf 形态）。修 = 全字面量才走快径，含变量分流 flat 路径；
flat 的 char 元素（elem_size==1）改 TruncByte+StoreMemByte（旧
4 字节越权覆盖相邻元素，#177 同族局部症状顺治）。

【#181 字符常量转义双引号】lexer char 侧 simple 表漏 '"' 臂
（字符串侧早有——C11 6.4.4.4 不对称）。锚 +1（lexer 59/59）。

【语料 +3】struct_nested_2d_member_init（#179/#180 六段）、
char_escape_quote、char_array_var_init（五段）。【验证】裸 823/823、
native 969/969；三语料双臂与 clang 逐字一致；五家 freeze + typeck
四套件连坐零漂移；vm_diff 四套件 691 全 SAME；testcount/facts 全绿。

### fix(parser+typeck+codegen+scripts): 用户审阅批处置——P1×3 全修（static 枚举折漏接线 / 常量折叠符号性 / #171 多维嵌套）+ 锚补齐 + 钩子 gitignore 根治（红锚先行）

【P1-1 函数内 static + 枚举常量误拒（回归）】fold_enum_in_static_init
只接 parse_var_decl_from_base（聚合定义带声明器形态），普通局部声明
主路径（stmt.mbt）不折 → `static int s = K;` 报 E3075 误拒（clang 放
行）。修：主路径单/多声明符两处补 fold 接线。语料 +1
`static_local_enum_init.c`（单/多声明符/数组/表达式叶/遮蔽五形态）。

【P1-2 常量折叠忽略符号性（零锚新错值）】const_eval 的 CVal 纯值域
无符号位——比较/除法/右移静默走 Int64 有符号域、整↔整 Cast 恒等丢
unsigned：`(0u-1u)>0`/`(unsigned)-1>0`/`-1<1u` 折 0/0/1（clang
1/1/0）。修：CE_AppB 携带左右操作数/结果类型，任一 unsigned 即
UInt64 域比较/除法/逻辑右移 + 算术后按结果类型宽度归一
（ce_normalize）；CE_AppU/CE_Cast 同款归一。wbtest
`const_fold_unsigned_semantics` 红锚先行；typeck 73/73 存量零翻转。
语料 +1 `const_fold_unsigned.c`（七形态含 u8 零扩展/浮截断）。

【P1-3 = #171 函数内 static 多维数组嵌套大括号静默错值】
emit_static_scalar_array_init 4 字节臂 flatten([elem])[0] 只取子列表
首元素、8 字节臂 literal_init_bits(InitList) 恒 None——{{1,2,3},
{4,5,6}} 只写 1,4,0,0,0,0、double 全 0。修：新增表达式级
flatten_init_exprs（保留 String/Float 节点形态），两臂共用扁平序列
按位定位（intern 路径/位模式编码不丢）。语料 +1
`static_nested_2d_init.c`（int/double/char 二维 + 文件作用域/一维
对照组）。

【锚补齐（P3×2，突变验证区分力）】#162 补 codegen wbtest
（struct 元素实参 LoadMem 计数=words——还原旧判定立红）；#161 补
非字面量 fmt 分支锚（回写 no-op 化立红）。

【其余处置】P2-1 fmt 落盘 / P2-2 testcount 分解和双行连坐 / P2-3
#157 E3079 与 clang 默认口径分叉登记（降 W 须先配柔性初始化运行
语义——盲降=静默踩踏，评论在案）/ P3-1 路线图现值句连坐（785/687/
448·81·138·20）/ 探针 skill P14「0x85 ⇒ stdout 归零」断言按四通道
复测推翻改写（#146/#172 全空子族根因待复核）/ review skill 03 演化
两条（A1-g 多语法路径接线覆盖面 + B17 常量折叠层缺对偶）/
editorconfig_check 豁免从硬编码追认制根治为 gitignored 自动豁免
（git ls-files 单源 + J9 双向验证：ignored 脏文件跳过、非 ignored
同款脏文件仍红）。

【验证】裸 moon test 822/822、native 968/968、check --target all
0 errors；三新语料 js+native 双臂与 clang 逐字一致；五家 digest
freeze（baseline +3、typeck 四套件连坐零漂移）；clang_direct
SAME=773 KNOWN=12 共 785；vm_diff 四套件 451+81+138+20 全 SAME；
facts --strict --run 零漂移；testcount PASS（822）。

### fix(host+typeck+codegen): #166/#161/#162 三修——memchr 负 c 连坐 + sscanf 尾参定型缺口 + struct Index/Member 实参通道（红锚先行）

【#166 现象一 host_memchr 负 c 恒不中】`b & 0xFF == c` 裸 i32 比较——
c 未像 host_strchr（病 1）那样取低 8 位，C11 §7.24.5.1「c 转换为
unsigned char 后比较」下 -1≡0xFF 必命中。修 `(c & 0xFF)`；wbtest 锚
翻转先行证红（旧锚系 oracle 病行为固化锚——病 1 修 strchr 漏连坐）。
语料 +1 `memchr_negative_c.c`。**现象二勘误**：0xFF 串错位 +1 非
memchr 游标病——实为字符串字面量 `\xFF` 按 UTF-8 双字节写出（#66
拍板的已知差异面换位，String 载体下两面二选一数学无解），且危害
升级实锤（char[N] 截断丢 NUL → strlen 越界 trap）；重开拍板挂
issue 评论（字节旁路载体 / 全链 Bytes 两选项）。

【#161 sscanf 变参尾参定型缺口（typeck）】check_builtin_sscanf 只查
前两参，尾参 `&r.cls` 的 Member(object) 零 resolve 零回写、保持 Void
占位——codegen 取址 get_member_offset 按 object.ty 落 0，成员偏移
全丢（任何 struct 成员地址作 sscanf 尾参都写偏基址）。修：收编
check_builtin_scanf 同款双路径（字面量 fmt 走 check_scanf_format
格式感知 start=2 / 否则逐参 resolve 回写 + 非指针 W3035）。wbtest
红锚 `sscanf_variadic_tail_member_typed` 首跑红证（Void）→ 绿。
issue 原「实参通道分叉」定责勘误详见 #161 评论；连带挖出 char 全局
读写字节粒度独立病 → #177 立账。语料 +1
`sscanf_struct_member_addr.c`（局部/全局/连发/四转换链/%d 六段）。

【#162 struct Index/Member 实参通道（codegen）】gen_index/gen_member_expr
对 struct/union 结果照发 4 字节 LoadMem（留首字段值），gen_call_ptr
struct 实参兜底臂把它当地址逐字拷贝 → `asum(arr2[0])` TRAP 0x1。
修：load 判定补 struct/union 不 load 留地址（对齐兜底臂与 struct
返回透传既有契约）。vm_diff 四套件 446+81+138+20 全 SAME 零回归；
语料 +1 `struct_array_elem_byval.c`（七段形态）。

【验证】裸 moon test 819/819、native 965/965；三新语料 js+native
双臂与 clang 22.1.4 逐字一致；五家 digest freeze（baseline +2+1、
typeck 四套件连坐重算零漂移）；facts --strict --run 零漂移（测试数
818→819 连坐 8 处、native 964→965 实测）。

### fix(cli/vitro_wasm): #71 病 111——wasm 臂 quote-include 的 `./` 段键归一 + 三代台账终盘实测（2026-10-16）

【病 111】vitro_wasm 胶水的 collect 登记名用 include 原文（`./x.h`）作
vfs 键，gateway resolver 归一查找键失配 → E1021（native 臂经 fs reader
无此问题）。修：登记前剥 `.` 段（strip_dot_segments——gateway resolver
同款归一，键/查找两侧对齐）。实测 `#include "./x.h"` 三臂全通（42）。

【三代台账终盘实测（#47/#61/#71 全病号逐一探针对拍 clang）】可实测面
**全部已修或非病**：P1 24 条（21~44，三梯队批清）/ P2 43 条（45~87，
历史批 + 本两日批：46/67/76/78/82/85/86 + 111）/ 补充轮 107~116（含
P1 双雄 107 变参组合、110 struct 复合字面量传参——实测 SAME）。
**剩余真活口（终态清单）**：①渲染零暴露族 79/80/81（expr_to_string
变体渲染 / type_display_name Function 臂字段错位 / base_kind 三消费表
Struct/Union——零语料零锚、读码定态修复）;②P3 清单 88~92（死面/注释
失实/锚缺口/oracle 同病——88 死面正在并发批处理）;③补登 93~106（P3
为主：文案/排序序/守卫类）;④115/116（include 展开坐标协议面/帧合成
坐标——观察项）;⑤119/120/121（三轮登记不修）。详见 #71 收尾评论。

【验证】moon test 781/781；smoke 三臂全绿（薄壳 include 双文件含）；
demo_smoke 178 全绿。

### Fixed

- **审阅处置批（2026-10-10，五提交审阅报告 P1/P2/P3 全销）**：
  - **786e8102 PX 假码元事故修复（最高优先）**：该并发提交打包时卷入了
    审阅处置中的 J9 注入态——libc 签名表 `strchr` 的 `param_kinds`
    被提交为 `"PX"`（未知码元）。工作区本 diff（PX→PI）即修复，随本批
    提交后 CI 复绿；同批落地的 `check_builtin_table` fail loud（未知
    码元 abort 而非静默按 int 检查）正是唯一能当场拦住此类表手误的层。
  - **demo_ui_lint toggle 过采集修复（P1-2）**：`classListArgs` 把
    `classList.toggle("cls", v !== "off")` 第二参（force 布尔表达式）
    里的比较字面量误当类名报红（4694205b 引入，CI 因 fail-fast 未及
    暴露）。修为 toggle 只解析首个顶层实参（`firstTopArg` 跳过字符串
    与括号内逗号）；selftest 双锚锁死（force 泄漏指纹红 + 首参未定义
    红，J9 注入回退证红）。
  - **clang_direct UB 语料第四形态登记（P2，归因反转）**：报告判
    「CI 全量步会红」经 CI 实况（Windows runner，SAME=712 DIFF=0 全绿）
    与双链冷构建对照证伪——bTree_default 的 trap 文案截断形态随产物
    二进制布局漂（冷/热构建、链、runner clang 版本均为变量），本机
    冷构建实测 4c8b994e 按 digests 集合语义（本地+CI 实测值）登记，
    reason 补记归因；不动 CI 权威面。
  - **表驱动臂错误支路文案锚（P3-1）+ fail loud（P3-2）**：病 11 两层
    收编改了 count/D 位文案（中文数字→阿拉伯、加位号）且该支路零覆盖
    ——补 `builtin_table_error_path_copy_anchor` 三形态直调锚（count/
    D 位/P 位，J9 改文案证红）；`check_builtin_table` 未知 param_kinds
    码元从静默按 int 改 abort（探针证红）。
  - **测试数连坐**：两份 README 705→715（#60 批 +10 未连坐 + 本批
    typeck +1）；native 827 口径待绿态实测重账。

## [0.8.0] - 2026-10-05（S8 收官版。发布档案：[0.8.0.md](../docs/current/08-发布档案/0.8.0.md)）

### Fixed

- **cmd/serve 交互管道死锁修复（2026-10-01 审阅 P1·rss 批销项实锤）**：
  stdout 在管道/重定向形态下全缓冲（MSVC CRT 无可靠行缓冲），批式消费
  方（一次性喂 stdin）无感，**交互式消费方**（写一行读一行——serve_smoke
  rss 批 / 上游宿主）死等首响应（实测 python 交互管道 >60s 零输出；
  Rust 侧 println! 自带行 flush 无此形态）。serve_stdio.c 增
  `moonbit_vitro_serve_flush` + main 循环每响应行显式 fflush。红→绿：
  修复前 rss 批挂死/compile-fail，修复后 4 次 seek 完成峰值 22MB/64MB
  PASS——**rss_guard 批豁免销项**（MoonBit 臂 59 断言与 Rust 臂同数）。


### Added

- **#10 P1 级标准库扩面：difftime + vprintf 族（2026-10-10，引擎侧）+ 五驱动 --refresh 存量重算通道**——新 host 函数 4（difftime=145/vprintf=146/vfprintf=147/vsnprintf=148）：snapshot.rs 扩 + baselines 110→114 + \`gen_host_route\` 再生（顺手把模板五处写死「110」文案 len 化）+ vm dispatch 四臂 + \`host/host_vprintf.mbt\`（difftime 纯 bits；v 族 = 游标预取层按 fmt 逐 spec 宽度从 va_list 读参装数组喂既有管线——**照搬物 host_format.mbt 零改动**）；存根 stdio.h/time.h +4 声明（typed_ast 全域漂移撞 #50 曾回撤一次，#50 合流后重上）；4 语料双侧与 clang 逐字节一致；builtin_all 175→179 连坐。**存量漂移的活通道**：五驱动 \`--freeze-mb --refresh\`（存量例指纹随现状重算——存根注入/引擎重构的合法演化面此前只能「先删旧键」手工绕；单独 --refresh 拒；J9 三连证红：注入坏 hash → 裸跑红 → refresh → 绿；本批重冻 typeck/codegen/parser 各 400 + lexer TSV 108）。
- **标准库事实包 P1（2026-10-10，方案 A 设计稿《标准库单源与头文件多文件设计20261010》）**——新包 `vitro/engine/stdlib`（L3 零依赖）：`headers()` 头文件清单**唯一真源**（14 头，序 = Rust `resolver.rs` match 序冻结）；`gen_stubs` 的 `stubNames` 硬编码**消灭**——改为文本解析 stdlib 真源 + 与 `libc_src/include/` 目录**双向集合对账**（未登记头/登记无文件均 fail loud，J9 双向注入证红）；验收 = `stubs_gen.mbt` 产物**逐字节一致**（sha256 `9df81a02` 前后相同）。引擎内消费（lexer `<>` 判定、sig/binding 数据面）随 P2~P4 逐面接线——「接线哪个面才落哪份数据」，不提前建无消费方的第二副本。连坐：pkg_deps levels（rules.json.mbt 真源 + jsonmbt 再生，40 包）/surface 白名单（headers 有意保留裁定项）/mbti_sync（28 接口面）/AGENTS 包清单。

- **教学资产数据外置批一（2026-10-10，refs #60）**——43 算法文案**双出口架构**落地：`teaching/assets` 独立包，真源 `suggestions.json.mbt`（jsonmbt：43 带参枚举变体拼错写时红 + `#|` 多行）+ `suggestion_map` derive（**43 臂穷尽 match = 编译期名单闸**，J9 删臂证红）；**引擎消费 = steps 直接 import 查表（零生成器/零 JSON 中转——探针实证 pub let 跨包直取已类型化值）**；教师面 = build 出同目录 `suggestions.json` 入仓（改后 `import --fill` 回真源——类型头/注释保留 + round-trip 值闭环实测；CI git diff 同步闸）。中间形态（Go 生成器管线）当日撤除，三轮决策链路归档 #60 评论 6085532499。登记连坐：pkg_deps levels（rules.json.mbt 真源 + 再生）/surface 边表 + 白名单/AGENTS 包清单/脚本册。验收：行为零漂移（moon test 705/705、族级对拍逐条一致、vm_diff/typeck_diff/demo smoke 全绿）。

- **CLI 出口总账三批（2026-10-04，refs #37）**——`cmd/lib/cli`（逻辑单包，
  函数名=命令名）+ `cmd/vitro` 总入口 + `cmd/compile`/`cmd/step` 新薄壳：
  - `vitro run <f> [-i in] [--dump-memory out] [-- argv...] [--json]`：
    NDJSON 事件流（diag/run/stdout 三帧 gateway 单源）；退出码全表
    0=正常/1=编译错/2=trap/3=步数超限/4=用法 IO（`-- EXIT N` 标记行双轨不变）；
  - `vitro compile <f> [--json]`：编译+诊断单出（compile 帧新增
    `algorithm_matches` 字段——teaching detect wire 出口，七字段含
    vis_events；协议「只增不改」纪律内，「自诞生即可选」豁免旧读者）；
  - `vitro step <f> [--max-steps N] [--json|--summary]`：一次性 step 流
    （有意分叉登记：Rust step 为交互 REPL；交互面归 serve）；
    **step 族引擎预算消费 config.max_steps**（原恒 new() 默认 100_000，
    `--max-steps`/config.set 对引擎无效且错配时假 finished——性能实测
    Blocker 1 修正）；
  - `vitro api <method> [params-json] | api --batch < frames.ndjson`：
    **全部协议方法的脚本化出口**——单帧直出 / 批式同进程顺序 invoke
    （状态跨帧保留——seek/breakpoints/input.feed 序列可脚本化）；
  - `-` stdin 源码全命令通用；run note 通道（完成附注 + 泄漏报告，
    行级 `// NOTE` 前缀）；输出契约冻结于
    `docs/spec/CLI_PROTOCOL_V1.md`（标记行六前缀/退出码表/事件流）。

- **`vitro/engine/time_travel`（L9，S8 批一号一段）**——时间旅行引擎域建包：
  `CheckpointManager` 全家自 `vm` 迁入（new/should_checkpoint/save/nearest/
  淘汰不变量三件套 + set_smart_mode/set_max_checkpoints 等会话配置入口）；
  门 3 六锚（全量往返/增量脏页/淘汰不变量/删 Full 级联 pinned/智能模式/
  隔离区三件套）随迁 `checkpoint_wbtest.mbt`，锚名与断言原样。
- **vm 观测面（批一号三段-a，2026-10-01）**：`get_current_line` /
  `call_stack_len`·`call_stack_at`（窄口——不暴露整表可写句柄，Rust
  `&[CallFrame]` 借用的等价形态）/ `take_vis_events`（取出即清）/
  `get_variable_snapshot`（作用域过滤 + 同名声明行择优 + Double 宽读位值）/
  `find_variable_name_at_addr`（跨帧最近定义 + 数组元素区间 slot_covers）/
  `get_array_snapshots`（U2#10 256 截断 + 五类元素文本化）+ 观测 DTO
  `VariableSnapshotData`/`ArraySnapshotData` + `MAX_ARRAY_SNAPSHOT_ELEMENTS`
  ——照搬 `crates/vitro_vm/src/core/{state,memory}.rs`，time_travel collector
  的 VM 调用面（三段-b）。
- **time_travel 批一号三段-b（2026-10-01）：StepCollector + 语义分类器**
  （照搬 unified/collector.rs 478 行）：`collect`（十四字段装配——纯函数
  形态，`SourceLineProvider` trait 依赖反转〔L9 不依赖 session，编排层
  实现注入〕+ heatmap 传值 + freed 查走 vm.mem_map〔比 Rust 少一处
  session 依赖〕；algorithm_step/root_cause_hint 占位 None 随 teaching/
  analysis 批）+ `infer_semantic_label` 全库唯一分类器（判定顺序契约
  头注照搬——具体语句模式优先于循环上下文）+ 指针四态/parse_addr/
  format_value/extract_called_func 辅助族；八锚锁判定链（含两处照搬
  偏差被锚实锤纠正：trim 位归 infer 内部 / extract 整段纯标识符判定）。
- **审阅销项批（2026-10-01，P1/P2/P3 五件）**：① finish_replay 三分支
  直锚 ×4（discard/钳位/截尾/空窗——协议默认窗口 2_000 使小 target
  不可达，A12 形态补锚；双突变证红留痕）+ `UnifiedEngine::with_limits`
  窗口参数入口 + engine 层小窗口锚 ×2（batch>1 批量与双向越窗 seek）；
  ② serve_smoke **豁免僵尸机判**（`--audit-exemptions`：豁免全失效真跑
  一轮，PASS/未触达即僵尸红——D19；CI 接线独立步；J9 假豁免注入
  ZOMBIE(PASS) 留痕）+ 僵尸条目 ×2 删除；③ serve 帧 JSON 键序跨语言
  分叉登记（Rust serde Value=BTreeMap 字典序 vs 本侧插入序——比较口径
  一律 canonicalize，已知限制 ④-6）；④ push_batch trim 时机有意分叉
  标注（oracle 单次 vs 本侧逐帧恒有界，batch>1 不可达）；⑤ serve_dump
  伪分叉注释修正（oracle 失败路径同样空表）。
- **teaching 审阅销项（2026-10-01，用户审阅 P1/P2/P3 五件）**：
  ① 判据族序对齐 oracle（sorting→search→graph→tree→structures→
  string——B13：bstKmpSearch 同命中多族的元素序，tree 先于 string）；
  ② extract_features 结构特征面补真 AST 锚 ×4（此前全 default 零锚
  ——三个突变全绿；现 has_swap/has_array_compare 突变即红）；
  **③ oracle 继承死分支实锤登记**：判据 `loop_depth >= 2` 恒假（两侧
  walk 从不写 f.loop_depth——bubble/selection/insertion 三结构分支
  在 oracle 也是死分支），锚定「不命中 = 等价」，修复归 0.8.0 脱钩
  批裁定；④ 对拍排期调整：golden 不攒末批，族级增量（已迁移族提前
  对拍）；⑤ 文档口径四修（已知限制 ④表编号重排/AGENTS 27→31 锚/
  moon.pkg 批切头注/render 27 变体）。
- **teaching/steps 批三号（2026-10-01）：tree 族八算法**：判据
  （bst 家族「名字+语义双条件」else-if 链——valid 优先于 insert、
  裸命名靠 is_treenode_ctx 补齐；level_order/avl/huffman/threaded
  命名）+ infer 八算法照搬（validate 三 phase 锚定模板行 + v5 ✗2
  顶层调用帧入口语义 + delete 判据置顶优先序）。十一锚照搬（判据
  七锚全套 + infer 四锚——含 bstHeight 无语义词反例与语境反锚）。
- **teaching/steps 批二号（2026-10-01）：search + string 族四算法**：
  判据（binary_search 命名三分支 + 结构分支〔单循环+mid 计算+left/right
  更新〕；string_reverse/bf/kmp 纯命名）+ infer 四算法照搬——含全部
  审阅修复：mid_calc 收紧（比较行不再被短路——三分支不可达修复）、
  narrow 实际边界值（差一修复）、nextval 两表优先序（§6-7 v4 #35）、
  nextval 下标从行文本解析（v5 ✗1）、getNext 调用点无数值
  （U1#1 P1-19/96）。六锚（binary 三红锚照搬 + KMP 两语义锚 +
  判据面锚）。
- **`vitro/engine/teaching/steps`（L9，S8 teaching 批一号，2026-10-01）
  ——算法语义标注建包**：判据（algorithm_detector 1519 行的 features
  特征提取 + sorting 族九算法判据——含 U1#1 P0-2 四处误判收紧全部
  语义：select/merge 整词+sort 语境、insertion 形态、贪心语境排除）
  + 步骤推断（vitro_algorithm_steps sorting.rs 九算法照搬——含全部
  用户审阅修复：j 合法上界越界描述拦截 / minIdx 别名表 / 插入写回
  收紧 + prev_vars 兜底 /「子子数组」错字 / 空区间递归基拦截 / 枢轴
  落位文案 / 位权位序 / count[...]++ 收紧）+ 43 算法教学文案全表
  （后续族直接消费）。十锚（has_word 21 例表 / 判据双锚 / infer 四
  算言语义锚 / parse_int 边界）。**分叉登记**：①CFG 四特征恒默认
  （CFG 属 analysis 域孤儿复核——sorting 零消费，graph 族迁移时再
  定）；②AlgorithmContext trait 不迁（source_line/algorithm 由编排
  层直供——collector 纯函数化先例）。后续批：search/tree/graph/dp/
  math/structures/string 七族逐批 + golden 311 三方 diff（S8 验收锚）。
- **serve dump 族三方法（S8 dump 接线批，2026-10-01）**：`ast.dump` /
  `typeck.dump` / `symbols.dump`——**只读语义**（2026-09-29 契约拍板）：
  独立编译通道不碰会话态（oracle 的 run_multi_file_pipeline 诊断写入
  副作用不照搬——已知限制 ④表）；emitter 零新建（ast/typed_ast 复用
  @ast.ast_dump_json——E1 面 597 语料与 Rust serde 逐字节一致）；
  只读契约机判锚（dump 前后 session 诊断/编译态/产物零变）。
  diagnostics_probe 随 diagnostics 批（依赖分析器域）。七锚
  serve_dump_wbtest。
- **serve step 族五方法（S8 批一号接线批，2026-10-01）**：`step.begin` /
  `step.next` / `payload.get` / `seek` / `breakpoints.set`——编排本体 =
  time_travel 的 UnifiedEngine（三段-c）。gateway 新增 `serve_step.mbt`
  （StepPayload 全家显式 emitter——serde 序 14 字段 + AutoStepResult/
  SeekResult；**UInt 数值字段 number 形态修正**：core `UInt64::to_json`
  出字符串而 serde u64 出 number，域内值经 `to_double` 无损转换）+
  Session 增 `unified` 引擎字段；vm 增断点三口（clear_breakpoints /
  add_breakpoint / unpause）；U1#1 一帧发布缓冲（R2 首调空帧语义）与
  终结冲刷照搬。**层位裁定**：time_travel 自 L9 降 L8（依赖面全 ≤L8、
  语义=编排引擎非教学智能；L9 留 teaching/analysis/diagnostics）——
  gateway(L8) 消费 time_travel 原违反 §4 单向约束。九锚
  `serve_step_wbtest`；serve_smoke MoonBit 臂豁免 12→4（step 族七断言 +
  栈帧 + edge/pending_leak 两整批销项转真跑，54 PASS / 0 FAIL）；Rust
  臂 59/59 零变。分叉登记：reset 作废引擎（保守语义）；rss_guard 批
  豁免留待 RSS 基线。
- **time_travel 批一号三段-c（2026-10-01）：run_batch · seek_to——批一号
  收官段**：`UnifiedEngine::run_batch`（五态分发 + 坑 ⑥-6 终结粘性 +
  U2#7 早退不丢帧）与 `seek_to`（协议 §4.2 越窗五步契约：nearest 检查点
  → restore → 窗口 reset_to → 正向重放含 target → finish_replay 截尾）
  + `get_payloads`/`max_collected_step` 读口。**⑤-5.1「直接按目标架构
  实现」落地**：Trap 回退不再每步拍 1MB 全量快照（pre_step_snap 机制
  不迁——常态每步 O(1MB)→O(1)），改「最近检查点 + 正向重放到 trap 前
  一步」，trap 帧以 trap 前状态收集（语义与 pre-step 回退精确一致）；
  trap 文案在回滚前抓取（回滚后随快照清空）。FrameWindow 增
  frame_at/push_batch（行末去重 U1#1 P0-1）/push_or_replace_at/
  reset_to/finish_replay（钳位族防线）；vm 增 `heatmap_count_at` 窄读口
  （Map 句柄不泄漏）。分叉登记：root_cause_hint 恒 None（TraceAnalyzer
  随 analysis 批）；serve 接线层须保证 vm.max_steps ≥ engine.max_steps
  （两层步数预算）。九锚（trap 回退专项 / 越窗 seek 往返相等 / 续跑
  连续 / Finished 提前终止 / 无检查点失败等）。
- **time_travel 批一号二段（2026-10-01）**：`FrameWindow`——StepPayload
  帧缓存的自带不变量类型（`@deque.Deque` 承载，两端 O(1) 摊还；窗口参数
  2_000/0.2 与 discard=ceil 公式协议锚定逐字保留；**push 唯一写入口**、
  超窗自动裁——U2#1 修复形态类型化；slice 钳位族防线）；`UnifiedEngine`
  状态定形（窗口四字段内聚、`pre_step_snap` 不迁〔Trap 回退改重放的前置〕、
  三粘性标志 reset 唯一清除、`resume` 保留字改 `unpause`）。

### Changed

- **⚠️ 破坏性：`CheckpointManager` 自 `vitro/engine/vm` 迁至
  `vitro/engine/time_travel`**（落点裁定：`should_checkpoint` 的智能判据
  是教学语义词汇——词汇单源在 L8 protocol，VM 包反向依赖应用层语义是
  Rust 侧已登记的分层破损；MoonBit 侧 vm(L7) 只保留无策略快照原语
  `snapshot`/`snapshot_incremental`/`restore`/`MemoryImage::apply_to`）。
  **迁移路径**：`@vm.CheckpointManager` → `@time_travel.CheckpointManager`
  （API 签名零变更）；判据字符串形态照搬（enum 化随 S8 collector 批
  配套 protocol 词汇单源后单批走红→绿）。纯迁移零语义变更：全仓
  `moon test` 508/508 绿（vm 81→75 + time_travel 6）。
- **`type_display_name` 上提 ast（三段-a 触发，gateway 私有 → `@ast` pub）**
  ——首个引擎侧消费者 = vm 观测面的 ty/element_ty 渲染（S7 serve_memory
  头注既定义务兑现）；`@ast.base_element_type` 新增（数组剥壳，照搬
  vitro_ast）。**`@host.format_fixed` pub 化**（vm 数组快照 Float/Double
  `{:.2}` 文本化——与 Rust `{:.2}` 同为精确十进制 half-even，单源复用）。

### Fixed

- **vm 观测面元素宽度维度修复（2026-10-01 用户审阅 P1/P2，红→绿锚
  `observe_find_variable_name_at_addr_elem_width` /
  `observe_array_snapshots_pointer_array`）**：`find_variable_name_at_addr`
  的 slot_covers 原误用 `sym.ty.kind()`（数组自身恒落默认臂 4——double/char
  数组区间归属双向出错）、`get_array_snapshots` 原误用 `base_element_type`
  兼任语义宽度（指针数组落 "?" 且步长错）——两处统一改按既有单源
  `Type::base_kind`（oracle `memory.rs:490/398` 同源：先解一层指针、数组
  递归剥层）；element_ty 显示名保持 `base_element_type`（oracle 显示层
  同款）。观测面为未发布新增面，无兼容负担。

---

> 版本语义：0.7.0 → 0.8.0（minor）——S8 四域新包（time_travel/teaching/steps/diagnostics）+
> CLI 出口三批（cmd/lib/cli + cmd/{vitro,compile,step}）+ compile 帧 algorithm_matches 字段；
> 无已发布 API 破坏（新增均「自诞生即可选」或新包）。（2026-10-01 审阅 P1·rss 批销项实锤）**：
  stdout 在管道/重定向形态下全缓冲（MSVC CRT 无可靠行缓冲），批式消费
  方（一次性喂 stdin）无感，**交互式消费方**（写一行读一行——serve_smoke
  rss 批 / 上游宿主）死等首响应（实测 python 交互管道 >60s 零输出；
  Rust 侧 println! 自带行 flush 无此形态）。serve_stdio.c 增
  `moonbit_vitro_serve_flush` + main 循环每响应行显式 fflush。红→绿：
  修复前 rss 批挂死/compile-fail，修复后 4 次 seek 完成峰值 22MB/64MB
  PASS——**rss_guard 批豁免销项**（MoonBit 臂 59 断言与 Rust 臂同数）。


### Added

- **CLI 出口总账三批（2026-10-04，refs #37）**——`cmd/lib/cli`（逻辑单包，
  函数名=命令名）+ `cmd/vitro` 总入口 + `cmd/compile`/`cmd/step` 新薄壳：
  - `vitro run <f> [-i in] [--dump-memory out] [-- argv...] [--json]`：
    NDJSON 事件流（diag/run/stdout 三帧 gateway 单源）；退出码全表
    0=正常/1=编译错/2=trap/3=步数超限/4=用法 IO（`-- EXIT N` 标记行双轨不变）；
  - `vitro compile <f> [--json]`：编译+诊断单出（compile 帧新增
    `algorithm_matches` 字段——teaching detect wire 出口，七字段含
    vis_events；协议「只增不改」纪律内，「自诞生即可选」豁免旧读者）；
  - `vitro step <f> [--max-steps N] [--json|--summary]`：一次性 step 流
    （有意分叉登记：Rust step 为交互 REPL；交互面归 serve）；
    **step 族引擎预算消费 config.max_steps**（原恒 new() 默认 100_000，
    `--max-steps`/config.set 对引擎无效且错配时假 finished——性能实测
    Blocker 1 修正）；
  - `vitro api <method> [params-json] | api --batch < frames.ndjson`：
    **全部协议方法的脚本化出口**——单帧直出 / 批式同进程顺序 invoke
    （状态跨帧保留——seek/breakpoints/input.feed 序列可脚本化）；
  - `-` stdin 源码全命令通用；run note 通道（完成附注 + 泄漏报告，
    行级 `// NOTE` 前缀）；输出契约冻结于
    `docs/spec/CLI_PROTOCOL_V1.md`（标记行六前缀/退出码表/事件流）。

- **`vitro/engine/time_travel`（L9，S8 批一号一段）**——时间旅行引擎域建包：
  `CheckpointManager` 全家自 `vm` 迁入（new/should_checkpoint/save/nearest/
  淘汰不变量三件套 + set_smart_mode/set_max_checkpoints 等会话配置入口）；
  门 3 六锚（全量往返/增量脏页/淘汰不变量/删 Full 级联 pinned/智能模式/
  隔离区三件套）随迁 `checkpoint_wbtest.mbt`，锚名与断言原样。
- **vm 观测面（批一号三段-a，2026-10-01）**：`get_current_line` /
  `call_stack_len`·`call_stack_at`（窄口——不暴露整表可写句柄，Rust
  `&[CallFrame]` 借用的等价形态）/ `take_vis_events`（取出即清）/
  `get_variable_snapshot`（作用域过滤 + 同名声明行择优 + Double 宽读位值）/
  `find_variable_name_at_addr`（跨帧最近定义 + 数组元素区间 slot_covers）/
  `get_array_snapshots`（U2#10 256 截断 + 五类元素文本化）+ 观测 DTO
  `VariableSnapshotData`/`ArraySnapshotData` + `MAX_ARRAY_SNAPSHOT_ELEMENTS`
  ——照搬 `crates/vitro_vm/src/core/{state,memory}.rs`，time_travel collector
  的 VM 调用面（三段-b）。
- **time_travel 批一号三段-b（2026-10-01）：StepCollector + 语义分类器**
  （照搬 unified/collector.rs 478 行）：`collect`（十四字段装配——纯函数
  形态，`SourceLineProvider` trait 依赖反转〔L9 不依赖 session，编排层
  实现注入〕+ heatmap 传值 + freed 查走 vm.mem_map〔比 Rust 少一处
  session 依赖〕；algorithm_step/root_cause_hint 占位 None 随 teaching/
  analysis 批）+ `infer_semantic_label` 全库唯一分类器（判定顺序契约
  头注照搬——具体语句模式优先于循环上下文）+ 指针四态/parse_addr/
  format_value/extract_called_func 辅助族；八锚锁判定链（含两处照搬
  偏差被锚实锤纠正：trim 位归 infer 内部 / extract 整段纯标识符判定）。
- **审阅销项批（2026-10-01，P1/P2/P3 五件）**：① finish_replay 三分支
  直锚 ×4（discard/钳位/截尾/空窗——协议默认窗口 2_000 使小 target
  不可达，A12 形态补锚；双突变证红留痕）+ `UnifiedEngine::with_limits`
  窗口参数入口 + engine 层小窗口锚 ×2（batch>1 批量与双向越窗 seek）；
  ② serve_smoke **豁免僵尸机判**（`--audit-exemptions`：豁免全失效真跑
  一轮，PASS/未触达即僵尸红——D19；CI 接线独立步；J9 假豁免注入
  ZOMBIE(PASS) 留痕）+ 僵尸条目 ×2 删除；③ serve 帧 JSON 键序跨语言
  分叉登记（Rust serde Value=BTreeMap 字典序 vs 本侧插入序——比较口径
  一律 canonicalize，已知限制 ④-6）；④ push_batch trim 时机有意分叉
  标注（oracle 单次 vs 本侧逐帧恒有界，batch>1 不可达）；⑤ serve_dump
  伪分叉注释修正（oracle 失败路径同样空表）。
- **teaching 审阅销项（2026-10-01，用户审阅 P1/P2/P3 五件）**：
  ① 判据族序对齐 oracle（sorting→search→graph→tree→structures→
  string——B13：bstKmpSearch 同命中多族的元素序，tree 先于 string）；
  ② extract_features 结构特征面补真 AST 锚 ×4（此前全 default 零锚
  ——三个突变全绿；现 has_swap/has_array_compare 突变即红）；
  **③ oracle 继承死分支实锤登记**：判据 `loop_depth >= 2` 恒假（两侧
  walk 从不写 f.loop_depth——bubble/selection/insertion 三结构分支
  在 oracle 也是死分支），锚定「不命中 = 等价」，修复归 0.8.0 脱钩
  批裁定；④ 对拍排期调整：golden 不攒末批，族级增量（已迁移族提前
  对拍）；⑤ 文档口径四修（已知限制 ④表编号重排/AGENTS 27→31 锚/
  moon.pkg 批切头注/render 27 变体）。
- **teaching/steps 批三号（2026-10-01）：tree 族八算法**：判据
  （bst 家族「名字+语义双条件」else-if 链——valid 优先于 insert、
  裸命名靠 is_treenode_ctx 补齐；level_order/avl/huffman/threaded
  命名）+ infer 八算法照搬（validate 三 phase 锚定模板行 + v5 ✗2
  顶层调用帧入口语义 + delete 判据置顶优先序）。十一锚照搬（判据
  七锚全套 + infer 四锚——含 bstHeight 无语义词反例与语境反锚）。
- **teaching/steps 批二号（2026-10-01）：search + string 族四算法**：
  判据（binary_search 命名三分支 + 结构分支〔单循环+mid 计算+left/right
  更新〕；string_reverse/bf/kmp 纯命名）+ infer 四算法照搬——含全部
  审阅修复：mid_calc 收紧（比较行不再被短路——三分支不可达修复）、
  narrow 实际边界值（差一修复）、nextval 两表优先序（§6-7 v4 #35）、
  nextval 下标从行文本解析（v5 ✗1）、getNext 调用点无数值
  （U1#1 P1-19/96）。六锚（binary 三红锚照搬 + KMP 两语义锚 +
  判据面锚）。
- **`vitro/engine/teaching/steps`（L9，S8 teaching 批一号，2026-10-01）
  ——算法语义标注建包**：判据（algorithm_detector 1519 行的 features
  特征提取 + sorting 族九算法判据——含 U1#1 P0-2 四处误判收紧全部
  语义：select/merge 整词+sort 语境、insertion 形态、贪心语境排除）
  + 步骤推断（vitro_algorithm_steps sorting.rs 九算法照搬——含全部
  用户审阅修复：j 合法上界越界描述拦截 / minIdx 别名表 / 插入写回
  收紧 + prev_vars 兜底 /「子子数组」错字 / 空区间递归基拦截 / 枢轴
  落位文案 / 位权位序 / count[...]++ 收紧）+ 43 算法教学文案全表
  （后续族直接消费）。十锚（has_word 21 例表 / 判据双锚 / infer 四
  算言语义锚 / parse_int 边界）。**分叉登记**：①CFG 四特征恒默认
  （CFG 属 analysis 域孤儿复核——sorting 零消费，graph 族迁移时再
  定）；②AlgorithmContext trait 不迁（source_line/algorithm 由编排
  层直供——collector 纯函数化先例）。后续批：search/tree/graph/dp/
  math/structures/string 七族逐批 + golden 311 三方 diff（S8 验收锚）。
- **serve dump 族三方法（S8 dump 接线批，2026-10-01）**：`ast.dump` /
  `typeck.dump` / `symbols.dump`——**只读语义**（2026-09-29 契约拍板）：
  独立编译通道不碰会话态（oracle 的 run_multi_file_pipeline 诊断写入
  副作用不照搬——已知限制 ④表）；emitter 零新建（ast/typed_ast 复用
  @ast.ast_dump_json——E1 面 597 语料与 Rust serde 逐字节一致）；
  只读契约机判锚（dump 前后 session 诊断/编译态/产物零变）。
  diagnostics_probe 随 diagnostics 批（依赖分析器域）。七锚
  serve_dump_wbtest。
- **serve step 族五方法（S8 批一号接线批，2026-10-01）**：`step.begin` /
  `step.next` / `payload.get` / `seek` / `breakpoints.set`——编排本体 =
  time_travel 的 UnifiedEngine（三段-c）。gateway 新增 `serve_step.mbt`
  （StepPayload 全家显式 emitter——serde 序 14 字段 + AutoStepResult/
  SeekResult；**UInt 数值字段 number 形态修正**：core `UInt64::to_json`
  出字符串而 serde u64 出 number，域内值经 `to_double` 无损转换）+
  Session 增 `unified` 引擎字段；vm 增断点三口（clear_breakpoints /
  add_breakpoint / unpause）；U1#1 一帧发布缓冲（R2 首调空帧语义）与
  终结冲刷照搬。**层位裁定**：time_travel 自 L9 降 L8（依赖面全 ≤L8、
  语义=编排引擎非教学智能；L9 留 teaching/analysis/diagnostics）——
  gateway(L8) 消费 time_travel 原违反 §4 单向约束。九锚
  `serve_step_wbtest`；serve_smoke MoonBit 臂豁免 12→4（step 族七断言 +
  栈帧 + edge/pending_leak 两整批销项转真跑，54 PASS / 0 FAIL）；Rust
  臂 59/59 零变。分叉登记：reset 作废引擎（保守语义）；rss_guard 批
  豁免留待 RSS 基线。
- **time_travel 批一号三段-c（2026-10-01）：run_batch · seek_to——批一号
  收官段**：`UnifiedEngine::run_batch`（五态分发 + 坑 ⑥-6 终结粘性 +
  U2#7 早退不丢帧）与 `seek_to`（协议 §4.2 越窗五步契约：nearest 检查点
  → restore → 窗口 reset_to → 正向重放含 target → finish_replay 截尾）
  + `get_payloads`/`max_collected_step` 读口。**⑤-5.1「直接按目标架构
  实现」落地**：Trap 回退不再每步拍 1MB 全量快照（pre_step_snap 机制
  不迁——常态每步 O(1MB)→O(1)），改「最近检查点 + 正向重放到 trap 前
  一步」，trap 帧以 trap 前状态收集（语义与 pre-step 回退精确一致）；
  trap 文案在回滚前抓取（回滚后随快照清空）。FrameWindow 增
  frame_at/push_batch（行末去重 U1#1 P0-1）/push_or_replace_at/
  reset_to/finish_replay（钳位族防线）；vm 增 `heatmap_count_at` 窄读口
  （Map 句柄不泄漏）。分叉登记：root_cause_hint 恒 None（TraceAnalyzer
  随 analysis 批）；serve 接线层须保证 vm.max_steps ≥ engine.max_steps
  （两层步数预算）。九锚（trap 回退专项 / 越窗 seek 往返相等 / 续跑
  连续 / Finished 提前终止 / 无检查点失败等）。
- **time_travel 批一号二段（2026-10-01）**：`FrameWindow`——StepPayload
  帧缓存的自带不变量类型（`@deque.Deque` 承载，两端 O(1) 摊还；窗口参数
  2_000/0.2 与 discard=ceil 公式协议锚定逐字保留；**push 唯一写入口**、
  超窗自动裁——U2#1 修复形态类型化；slice 钳位族防线）；`UnifiedEngine`
  状态定形（窗口四字段内聚、`pre_step_snap` 不迁〔Trap 回退改重放的前置〕、
  三粘性标志 reset 唯一清除、`resume` 保留字改 `unpause`）。

### Changed

- **⚠️ 破坏性：`CheckpointManager` 自 `vitro/engine/vm` 迁至
  `vitro/engine/time_travel`**（落点裁定：`should_checkpoint` 的智能判据
  是教学语义词汇——词汇单源在 L8 protocol，VM 包反向依赖应用层语义是
  Rust 侧已登记的分层破损；MoonBit 侧 vm(L7) 只保留无策略快照原语
  `snapshot`/`snapshot_incremental`/`restore`/`MemoryImage::apply_to`）。
  **迁移路径**：`@vm.CheckpointManager` → `@time_travel.CheckpointManager`
  （API 签名零变更）；判据字符串形态照搬（enum 化随 S8 collector 批
  配套 protocol 词汇单源后单批走红→绿）。纯迁移零语义变更：全仓
  `moon test` 508/508 绿（vm 81→75 + time_travel 6）。
- **`type_display_name` 上提 ast（三段-a 触发，gateway 私有 → `@ast` pub）**
  ——首个引擎侧消费者 = vm 观测面的 ty/element_ty 渲染（S7 serve_memory
  头注既定义务兑现）；`@ast.base_element_type` 新增（数组剥壳，照搬
  vitro_ast）。**`@host.format_fixed` pub 化**（vm 数组快照 Float/Double
  `{:.2}` 文本化——与 Rust `{:.2}` 同为精确十进制 half-even，单源复用）。

### Fixed

- **vm 观测面元素宽度维度修复（2026-10-01 用户审阅 P1/P2，红→绿锚
  `observe_find_variable_name_at_addr_elem_width` /
  `observe_array_snapshots_pointer_array`）**：`find_variable_name_at_addr`
  的 slot_covers 原误用 `sym.ty.kind()`（数组自身恒落默认臂 4——double/char
  数组区间归属双向出错）、`get_array_snapshots` 原误用 `base_element_type`
  兼任语义宽度（指针数组落 "?" 且步长错）——两处统一改按既有单源
  `Type::base_kind`（oracle `memory.rs:490/398` 同源：先解一层指针、数组
  递归剥层）；element_ty 显示名保持 `base_element_type`（oracle 显示层
  同款）。观测面为未发布新增面，无兼容负担。
## [0.7.0] - 2026-09-29

### Added

- **`vitro/engine/protocol`（L8，S7 批一号）——冻结协议 v0.1 的引擎侧权威
  载体（零依赖自持）**：`SCHEMA_VERSION`/`SCHEMA_V0_1_FROZEN_AT` 常量 +
  StepPayload 十四字段白名单（对账单源 `scripts/replay/v01_payload_fields.json`
  ——白盒硬编码第二份逐条锚，任一侧漂移即红）+ 语义标签受控词汇表 14 条
  （10 active c 域 + 4 reserved csharp 域，`classify`/`kind_by_id` 双向）+
  协议 DTO 族 17 类型（StepPayload 全家 + VisEvent/RootCauseHint 收拢进本包，
  `pub(all)`——协议字段即协议面）+ stream 差分编码（SymbolTable + Ref/Delta
  全族 encode/decode 往返）。
- **`vitro/engine/session`（L8，S7 批二号）——会话状态层**：`SessionConfig`
  单一真相源 + 单一写入口（`set_*` 写 config 即经 vm setter 应用——Rust 侧
  「配置散在 VM 字段 + setup 硬编码覆盖 + capi 静默丢弃」三段事故链在本侧
  结构性消除）+ `Session` 骨架（CompileState 聚合 `@bytecode.CompileOutput`
  非散装复制）+ 多文件安全 `source_line_at`（file_ranges 换算）+ 会话侧
  DTO 九型（VisEvent 消费 protocol 不造孪生）。
- **`cmd/serve`（S7 批三号）——JSON-lines 会话模式（协议层在 gateway 包，
  serve 为 native stdio 壳）**：`compile`/`run` 两方法（merge_units 合并
  通道 + 四 pass 管线 + 诊断出口十字段 + preprocessor_trace 真通道；run
  六字段出口，输入模式缺省 Interactive——缺省 scanf 得 `waiting_input`
  而非 EOF）+ 运行态与静态十四方法（`input.feed` 追加式续跑 /
  `output.delta` 四通道游标 / `memory.regions` 三段式合成 / `capabilities`
  + `error_catalog`/`semantic_labels`/`contracts` 三静态导出 /
  `session.create`/`reset`/`destroy`/`config.get`/`config.set`（含
  `quarantine_budget` 通道——一段欠账销项）/ `ping`/`shutdown`）；「2000
  步真停」端到端锚（Rust 事故对照）与 file_ranges 生产者两条登记义务闭环；
  step 族五方法依赖 unified 引擎随 S8 时间旅行片接入。
- **防线（S7 批四号）——serve_smoke 双宿主对拍 + gen_protocol_ts 权威源切
  MoonBit**：`scripts/serve_smoke --moonbit` 跑 cmd/serve exe 同一请求表与
  断言集（豁免面外置 `moonbit_exemptions.json`——表外断言名红即真红，PASS
  也豁免防僵尸条目）；首跑战果抓到 `config.set` 返回裸 config 对象未包
  `serve_ok` 帧的真缺陷（一段锚只 contains 数字未锁帧结构故未暴露）。
  `gen_protocol_ts` 生成源切 `moonbit/protocol/types.mbt`（切源零语义变更
  实证：产物 diff 仅头注源路径行、interface 声明体逐字节一致）；过渡期
  三向对账 = MoonBit↔schema 文档 + MoonBit↔Rust oracle（名字集双向比对，
  Rust 区整体删除时移除）；TS 消费者 `scripts/protocol/consumer.mjs` PASS。
- **已知限制与差异清单**（as-of 0.7.0 主动披露）：四分类 30 条
  （`docs/current/07-质量与裁定/已知限制与差异.md`），README 双落点——
  mooncakes 模块页（`README.mbt.md`）与仓库根 README 均含入口。
- **`vitro/engine/gateway`（L8，S7 批五号）——wasm-gc 单出口（F-5 裁定
  落点）**：NDJSON 帧协议层自 cmd/serve 上提为引擎无关载体（serve 变
  native stdio 壳），4 函数导出 `invoke`（String→String 单口承载 21
  方法表）/ `reset` / `protocol_version`（@protocol.SCHEMA_VERSION
  单源）/ `engine_version`（手维护常量 `ENGINE_VERSION`，与 moon.mod
  版本失联由 host.js 锚判定——发版 bump 忘更即红）；宿主契约 =
  `use-js-builtin-string` + 宿主编译选项 `builtins:['js-string']`
  （String 零拷贝直传、零功能性 imports——import 段仅 "_" 字符串常量
  模块）；quote-include 宿主形态分叉：native 壳经 `set_include_reader`
  注册文件系统读取（**审阅 P2 修复**——此前统一 vfs 空表曾使 native
  静默丢解析），wasm-gc 不注册 ⇒ E1021 教学诊断；Node 宿主驱动
  `scripts/wasm_gateway/host.js`（16 断言：NDJSON 全链 + E3070/E3061
  真 trap + 4 导出面 + 失联锚 + 体积上限）。
- **gateway 拆包（2026-09-29 审阅 P2 假声明销项，§12.6 配方落地）**：
  gateway 本体改 `library`（`+wasm-gc +native`——native 消费者与
  wasm 外壳共用），4 个 `#export_name` 导出面移至新包
  `vitro/engine/gateway/wasm`（foreign_library + wasm-gc 单目标）；
  moon 对 foreign_library 的 native 走 exe 链接 ⇒ LNK1561（上游契约
  缺口）——拆包后 CI 全量 native release 构建门由「已知债豁免」转
  **硬门**；include 双分支锚补齐（审阅 P2 零锚：突变回缺陷形态曾
  58/58 全绿——新锚后突变必红）。
- **stdin 注入通道三件**（2026-09-29 层 2 遗留 stdin 34 例批）：
  - `host::InputState::from_stdin_text(text, batch)`——stdin 切行单源
    （`\r\n` 循环规整 + `split_inclusive` 语义行含尾换行 + 模式一次
    到位），三消费者即刻收口（serve 的 input 参数 / input.feed /
    cmd/run 的 `-i`）；
  - `cmd/run -i <file>`：headless Batch 通道（oracle CLI `-i` 同语义
    ——输入耗尽即 EOF 不交互，A1）；
  - vm_diff / clang_direct 驱动自动配对同名 `.in`（34 例自此测真实
    输入形态而非 EOF 空跑）；clang_direct 的 cacheKey 实写 stdin 维度
    （schema 设计位预留——防同源码不同输入命中旧缓存）。

### Fixed

- **`String::replace` 只替换首个匹配致 CRLF 规整不全**（stdin 34 例批
  首跑实锤）：`from_stdin_text` 单次 replace 只消一个 `\r\n`——
  kr_1_19 实测第二行起 `\r` 泄入程序（输出多 `\r` 分叉，4 例真 DIFF）；
  改循环规整后 knr 29 例全 SAME。语言事实入 moonbit/AGENTS.md 陷阱
  〔String::replace 首个匹配条——AGENTS 陷阱 #37〕；host 包 CRLF
  全量规整锚锁定。
- **bTree known 条目归因勘误**：原写「未初始化子节点指针」——细读
  createNode 已循环置 NULL children，真 UB 面是 `keys[M]` malloc 后
  未清零 + splitChild 搬移读越 keyCount 界；kruskal 修复改变布局后
  UB 走向 NULL 解引用受检 trap（digest 更新 + 归因重写）。
- **`set_call_depth_limit` 缺 V-P1-10 下限 16 兜底**（2026-09-29 用户
  审阅 P2 实锤并双向证明）：Rust `state.rs` 的 `limit.max(16)` 未随
  S6 照搬——`config.set {"call_depth_limit": 0/-5}` 时 oracle 回 16
  / 本侧回原值（过小配置把正常程序直接判死）。修复 = vm setter 补
  clamp（同 Rust）+ Session 写入口同款（回显读 SessionConfig 须持
  clamp 后值——与 Rust「回显读 vm getter」语义对齐）；连坐翻转
  `exec_call_depth_limit_traps` 锚（传 8 的 trap 文案 8 层→16 层——
  无 clamp 期的旧锁值）；新增 vm setter 单元锚 + serve 回显锚。

- **局部 struct 数组部分初始化的零填充偏移双重计数**（2026-09-28
  kruskalMST 调查批实锤）：`var_decl.mbt` 零填充循环照搬 Rust 的
  `(i, _) in range.enumerate()` 形态时，把 enumerate 下标（0 起）误接到
  MoonBit 的 range 迭代值（len 起）上——`idx = len + k` 双重计数使填充
  写偏移翻倍越界（kruskalMST：写 168/180/192 而非 84/96/108，越界砸
  相邻栈数据致 Find 递归读垃圾索引二次越界 trap）。修复 = `idx = k`；
  产物层/运行层/stdout/返回码/1MB 映像五面闭环（codegen_diff SAME +
  clang_direct 转绿销 known 条目〔8→7〕+ vm_diff 三联 SAME）；顺手修
  vm_diff `--cases` 对不存在路径静默跑空判假 SAME 的 fail-loud 缺陷。
- **serve 输入通道的 getchar 行间换行丢失**（2026-09-28 审阅批 P1 实锤
  并双向证明）：`split_stdin_lines` 剥掉行尾换行，与 oracle
  `RuntimeState::split_stdin`（`split_inclusive('\n')`——行含尾换行）
  形态不符，导致 `getchar()` 每行少产一个 `\n`（实测
  `"ab\ncd\n"`：oracle 计 n=6 / 本侧 n=4；`scanf("%s")` 后 getchar
  读到下一行首字符而非 `\n`）。修复 = 切行改保留尾换行（末行无换行
  原样——尾换行信息不丢）；host 侧 scanf 虚拟流的补位守卫（行尾
  ≠ `\n` 才补）天然兼容，零改动。`InputState.lines` 形态约定同步
  勘误为「行含尾换行」（`host_io_wbtest` 的
  `getchar_reads_across_lines_and_eof_sticky` 锚翻转——旧构造
  `[b"ab", b"cd"]` 是 oracle `split_inclusive` 下不可产生的中间态，
  且把错误行为固定成了预期）。三锚新增（n=6 / n=5 / scanf+getchar
  读 10）。

### Added

- `vitro/engine/fs`（L0，native-only）：**vendored 自 moonbitlang/x@0.5.5**
  的文件系统件（唯一依赖清除 B 路线批，2026-09-28）——`read_file_to_string`
  / `write_string_to_file` / `write_bytes_to_file` / `path_exists` / `read_dir`
  / `create_dir` / `is_dir` 七函数 + `IOError`。C 符号前缀
  `vitro_engine_fs_*`；unicode 四函数内联 priv（vendor 边界闭合）。
  上游漂移由 `scripts/moonbit/vendor_drift` 监控（内容哈希口径，CI hygiene；
  处置手册见仓库 docs/current/01-定位与路线/唯一依赖清除路线.md §3B-4）。

### Changed

- **`moon.mod` 依赖块清空——module 零外部依赖**（原唯一依赖
  `moonbitlang/x@0.5.5` 的消费面 cmd×5 全部切换到 `vitro/engine/fs`，
  `@fs` 别名不变，调用方零改动）。发布件自包含：index 行 deps 可空，
  下游安装不再连带拉 x 全模块、不再绑定第三方 registry 存续。
  vendored 文件为 Apache-2.0（文件头保留 + `THIRD_PARTY.md` 全文）。

### Added（S7 批三号二段，serve compile/run 接线配套）

- `vitro/engine/host`：`InputState::push_lines(Array[Bytes])`——交互续跑
  `input.feed` 的追加通道（行追加 + EOF 粘滞清除，读取游标保留——
  Rust `RuntimeState::push_stdin_text` 同形语义）。
- `vitro/engine/vm`：三装载通道方法（跨包 mut 字段只读——MoonBit
  语义下的宿主侧写入口）——`VitroVM::set_input`（运行态输入整体替换，
  Rust `RuntimeState::set_stdin` 落点）、`VitroVM::reset_vfs`（Rust
  `reset_runtime` 的 VFS 重建落点）、`VitroVM::clear_waiting_input`
  （Rust `execute_run` 开头清 session 旗的落点）；`VitroVM.vfs` 字段
  升 `mut`（重建通道前提，快照仍走 `VfsSnapshot` 值形态不受影响）。
- `vitro/engine/session`：`Session` 增 `runtime_argv : Array[String]` /
  `runtime_batch : Bool` 两字段（Rust `session.runtime` 的 argv/
  input_mode 两角最小承载——argv 跨 run 存活；输入模式缺省
  **Interactive** 对齐 Rust `InputMode` 默认首变体）。
- **capabilities 出口的分叉登记**（serve 静态族，批四号双宿主对拍的
  已知必红点）：`abi_version`/`engine_version` 字段不出（MoonBit 侧
  无 capi 层——.mbti 取代 ABI 版本化，构建期 git 短哈希通道不存在，
  版本协商走 mooncakes 版本号）；`languages.cpp` 节不出（F-2 终局
  已裁 C++）。对拍白名单须含此四项。

## [0.6.0] - 2026-09-26

### Added

- `vitro/engine/memory`（L7）：1MB 载体 + `MemoryMap` 堆状态机（bump + 有界隔离
  + first-fit）+ `check_access` 单入口受检访问 + `freed_logs` 有序数组。
- `vitro/engine/host`（L7）：110 路由表消费侧 + 字节保真输出通道（`OutputLog`）
  + 100+ VM 无耦合 handler（内存 / ctype / math / 字符串 / 转数值 /
  printf-scanf / VFS），统一 `HostMemReply` 结构化回复。
- `vitro/engine/vm`（L7）：执行器状态机（135 opcode 穷尽 match）+ 快照体系
  （`VMSnapshot` Full/Delta + 检查点管理器）+ libc 产物装载。
- `cmd/run`：端到端 runner（C 源码 → 编译 → VM 执行，stdout / 返回码 /
  1MB 内存映像三通道）。含源目录 include 解析（`SourceProvider` 文件系统
  注入）、argv[0]=源文件路径与 vfs 预设注入（`test.txt`/`numbers.txt`，与
  Rust CLI 同口径）。
- `vitro/engine/util`（L0）：零语义机械件单点——`utf8_len` / `str_cmp` /
  `i64_to_i32_bits` / `le_u32_at` / `le_u64_at`（G-1 收口件）。

### Changed

- **`host.HostMemReply.value` 类型加宽 `UInt?` → `UInt64?`**（S6 host 余量批，
  2026-09-23）：strtol / strtod / llabs 等 64 位返回值压栈需求；vm 值栈本就是
  u64 位模式。消费方若按 `UInt` 匹配需同步调整。

### 性能披露（2026-09-26 实测，同机对拍 Rust oracle）

- 端到端小程序（baseline 366 例中位，编译主导）：**1.42×**；
- 计算密集程序：fib(20) 1.92× / 冒泡 200 6.32× / 500×500 嵌套 15.7×；
- 条件 A 300×300 循环（完整引擎 vs oracle JIT 路径）：10.1×。

全速执行优化规划于 **0.7.0+**（bytecode→wasm-GC 生成器路线）；解释器持续服务
单步语义与时间旅行。详见模块 README「性能现状」节。
