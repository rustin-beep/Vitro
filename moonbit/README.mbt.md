# Vitro MoonBit 引擎（活跃区）

> Rust 冻结对照区（`../native/`）的渐进迁移目标实现。上位文档：
> [MoonBit迁移总计划](../docs/current/01-定位与路线/MoonBit迁移总计划.md) ｜
> [第一阶段计划](../docs/current/01-定位与路线/MoonBit迁移第一阶段计划.md)

## 包清单（S1 基础片）

| 包 | 层 | 职责 | 锚 |
|---|---|---|---|
| `vitro/engine/source` | L0 | SourceLoc 三字段 + 列单位契约（字节偏移+1 主坐标 / Pos 双坐标预留） | 白盒单测（三量纲分歧锚） |
| `vitro/engine/opcode` | L0 | 135 条 opcode（编号照搬不重排；44–46 = C# 异常三件，47–49 空号）+ 双向映射 + Instruction | 0..255 全空间断言 |
| `vitro/engine/diag` | L1 | ErrorCode 137 臂（**gen_diag 生成，禁手抄**）+ Severity/SourceLang + catalog 77 条 + E4 出口 | 覆盖率断言 + E4 全量对拍（canonicalize 后逐字节一致） |
| `vitro/engine/ast` | L2 | Type 17 / Expr 26 / Stmt 16 / decl 全族 + depth（显式栈）+ type_eq + to_c_string 单源 + mangle + E1 dump emitter | E1 对拍两样本 diff 空 + E5 黄金串 `prefix_p_a2_3_int` |

## 关于 cmd/ 子包

本模块附带 6 个命令行工具（4 个 `cmd/dump_*` 差分对拍 + `cmd/run` 端到端
runner + `cmd/serve` JSON-lines 会话模式 native 壳）——它们是仓库开发工具，
随包分发但下游只消费引擎库时可忽略 `moon build` 生成的 cmd 产物。

## 生成物纪律

```bash
cd moonbit
go run ./scripts/gen_diag          # 从 Rust 源再生成 diag 包机器单源部分
go run ./scripts/gen_diag -check   # 幂等校验（源变产物变 / 产物被篡改即红）
```

- `diag/error_code_gen.mbt`、`diag/catalog_gen.mbt` 为生成物（**禁手改**，文件头有源 sha256 落款）；
- 生成流程内置 `moon fmt`——产物最终形态以 fmt 输出为准，gen 与 fmt 不互踩；
- 基线漂移（137 臂 / 77 卡片）fail loud：源变更须人工核对后更新 `expectedArms` / `expectedCatalog` 并登记差异。

## 性能现状（诚实披露；2026-09-26 首测，2026-10-04 S8 收官批复跑）

VM 是为单步执行与时间旅行可观测性构建的**解释器**，不以裸速度为目标。
同机对拍 Rust oracle：端到端小程序（编译主导）**1.42×**；计算密集
fib(20) / 冒泡 200 / 500×500 嵌套 **1.92× / 6.32× / 15.7×**；条件 A
300×300 循环（完整引擎 vs oracle JIT 路径）**10.1×**。
S8 收官批复跑：计算密集三项同量级（1.58–15.8×），HEAD vs 0.7.0 同时段
A/B 判**无回归**；**wasm-gc 主出口有实测背书——同请求七场景全部快
native CLI 1.5–6.3×**。诚实短板：全速执行慢 CPython 9.6–19.8×（wasm-gc），
系 VM 解释循环本身（自 Rust 期继承）；bytecode→wasm-GC 生成器实测仅
2–2.8×、量级不足（issue #41 评估中）；解释器持续服务单步语义与时间旅行。
完整口径见 `README.md`「性能现状」节与 `CHANGELOG.md`。

## 验证

```bash
moon check && moon test    # 718 测试（2026-10-10 连坐重账：#60 批 +10、审阅处置批 +2〔typeck 锚 + libc 表字符集静态锚〕——总数以 moon test 实跑为准）source 14 / opcode 10 / diag 22 / ast 14 / lexer 56 + internal/scanner 7 = 63（issue #55 批 2026-10-09 +1 锚在 scanner 子包〔scan_raw c11 whitespace vtab formfeed——C11 空白全集 \v 0x0B〕；+4：守卫自 include/守卫互环/无守卫自环反锚——E1015 守卫感知修复锚 + 深环归因锚，2026-10-05） / parser 38（#48 批 2026-10-09 +4 锚：decl 缺 ';' 且 '{' 紧随的级联收口双形态 + 下一声明保全 + 无 '{' legacy 形态反锚〔parse 层内 error recovery〕+ 2 无逐笔批注以实测为准；批三-a +1 五销案锚，2026-10-06） // names 5 / libc 6（审阅处置批二 2026-10-10 +1：libc_table_param_kinds_charset——表字符集静态锚〔P/I/D，786e8102 PX 手误检出点前移〕；批四 +1：N3/N4 销案锚——bytecode_libc_sig 返回值对齐存根，2026-10-07） / typeck 37（审阅处置批 2026-10-10 +1：builtin_table_error_path_copy_anchor——表驱动臂错误支路文案锚〔count 中文数字→阿拉伯/D 位位号/P 位单源三形态〕，P3-1；#60 批三段二 +1：builtin_notes_migration_snapshot_before；#56 批 +1：assign_null_pointer_constant_no_w3054——空指针常量豁免五臂锚〔NULL/字面量 0 正形状 + 非零常量/标识符/无表达式句柄负形状〕，2026-10-10；#47 批 +1：assign_const_gain_pointer_no_w3067——char*→const char* 假阳性抑制锚，2026-10-09；批四 +1：%*d 数量臂零告警锚，2026-10-07） / bytecode 17 / codegen 15 / memory 32 / host 147（#47 病 6 批 +1：realloc_invalid_ptr_reports_not_silent——realloc 无效/已释放指针完整教学诊断锚，2026-10-09；#47 批 +3：scanf_i_x_o_conversions + strdup_heap_exhausted_note + strchr_negative_c_char_conversion〔负 c 按字符转换——Clang 真值 offset 3〕，2026-10-09；审阅 P2-1 同族补齐 +1：sscanf_i_x_o_conversions——host_sscanf 补 %i/%x/%o 三臂与 scanf 同源〔C11 §7.21.6.2〕，2026-10-09；另 +2 无逐笔批注以实测为准；批五 2026-10-07 +3：note 预算双锚 + scanf 抑制不写哨兵锚：note 预算环丢锚 + 单条截头锚〔note 无界治理〕；审阅 P2-a +1：printf 零填充符号前置与浮点旗标锚，2026-10-06；批四 2026-10-07 +2：printf 星号宽度/精度锚 + scanf %*d 抑制锚） /（批二-b +2：fgets 二进制不压缩锚 + 负 n 族 trap 锚，2026-10-05） / vm 84（#47 批 +1：bounds_message_no_embedded_location——文案内不得内嵌 location 段锚，2026-10-09；批五 2026-10-07 +1：apply_reply 全量同文本去重锚）/ time_travel 52（+1 无逐笔批注以实测为准，2026-10-09；S8 批段一 M14 2026-10-03：trace 六臂锚 + 审阅补 bounds 三分类锚〔wrong_init/wrong_increment/uninitialized_index——oracle tests 照搬〕） / teaching/steps 48（批六号 +4：oracle detect 两锚照搬〔BST deleteNode 不误判链表删除〕+ 十一判据正面覆盖〔cash 排除/union+find 双形态〕+ 十一算法 phase 表〔josephus m/remain 与 union_find x 数值文案〕——43/43 全量收官；批五号 +5：dp 两锚照搬〔初始化双层内层 j 排除 + 真实体 inner_loop〕+ math/dp 判据与 prev_vars 算式锚〔48 % 18 = 12 行入口操作数〕+ math+dp phase 表〔hanoi 柱名还原/币种主语〕；批四号 +8：oracle 两侧 tests 照搬三锚〔linearSearch 不误判 BFS/递归 binarySearch 不误判 DFS/命名反锚〕+ 七算法命名正面覆盖 + dijkstra 收紧正反锚 + BFS/graph phase 表双锚；审阅销项 +4：结构特征真 AST 锚〔bubble/binary/insertion——loop_depth 恒 0 死分支等价锚实锤 oracle 继承死分支〕+ B13 族序锚〔bstKmpSearch 双命中元素序〕；批一号 sorting 族+骨架；批二号 search/string 四算法〔binary 三红锚照搬+KMP nextval 优先序/行文本下标〕；批三号 tree 族八算法〔bst 家族双条件判据七锚照搬——isValidBST 方案②/裸命名 TreeNode 语境/语境反锚 + validate 三 phase 模板行锚 + delete 八行 phase 表〕；批四号 graph 族〔U1#1 P0-2 收紧版判据 + 七 infer 注释照搬〕——dp/math/structures 族随批；golden 族级对拍已建〔scripts/teaching_annotation_diff，五族 28 算法 82 模板全绿，未迁移族随批扩 rules.json〕） / diagnostics 32（段一~四 2026-10-02：数据层四表〔gen_diagnostics 双产物+J9〕+ 机制层五件〔generate_fix/apply_fix/误区滑窗〔confidence f32 语义化——值面 round_to_f32 位模式对齐，文本面随审阅 P1 销案走 gateway double_to_json_text〕/路径组装/图激活〕；黑盒 26 = Rust 单测照搬 13 + 行为锚 8 + 出口点名 1 + 审阅 F6/F7 锚 4；白盒 6 = 机制锚 6——f32 文本化锚随审阅 P1 销案退役，wire 锁定移 gateway probe 锚） / util 14（issue #55 批 2026-10-09 +5：json_escape 四锚〔六份收一——五具名转义 + 控制字符全覆盖 + 透传 + into 流式同构〕+ README doc test 一锚；批二 2026-10-06 +1：base64_encode RFC 4648 向量锚〔memory.dump 帧〕；批一同日 +1：utf8_text_partial 三态锚〔CLI utf8_decode 上提〕）/ protocol 46 / session 12；分解和 718 + 根 README doc test 0（2026-10-09 实测重账：逐包实测全含——fuzz_invariant_wbtest 六测试实为 host 包内件〔已含 host 145；工序④ fuzz 路 A：A/B/D/E 场景 + 1MB 墙 + J9 金丝雀，2026-10-05〕，根 doc test 余量位归零、旧两段式旁账撤销；lexer/internal/scanner 7 单列于 lexer 段））——S5 起 bytecode/codegen 入列、S6 起 memory/host/vm 入列、S7 起 protocol 入列、S8 起 time_travel 入列、diagnostics 入列（2026-10-02）（CheckpointManager 自 vm 迁入 + 门 3 六锚随迁 + 批一号二段 FrameWindow/UnifiedEngine 十一锚（含整数积分界锚），2026-09-30/10-01）；protocol 46 = 白盒 39（schema 11 + types 5 + vocabulary 7 + stream 16〔8 锚照搬 Rust tests + 索引 0 预留 + 窗口直通 + 审阅 P1/P3 六锚：vis_events 幂等×2 + 符号表全内容 + 同长 return_line + 删除重现 + get_sym 越界〕）+ 黑盒 5（对外面消费面点名；stream encode/decode 往返）+ 包 README doc test 2（协议演化纪律三条成文 + json_or_null 组合子——批四号 openseek ①③）；白盒含审阅 P1/P3 批六锚（vis_events 双幂等锚 + 符号表全内容 + 同长 return_line + 删除重现 + get_sym 越界）；libc 5 为 N3/N4 销案锚（批四 2026-10-07——漂移登记锚随销案翻转 + bytecode_libc_sig C 面返回值锚）；bytecode 17 / memory 32 / host 126 各含 2 个包 README doc test（补指引批——时点见 git log）；memory 32 = 白盒 24 + 黑盒 6 + doc test 2（#47 病 8 批 +1：allocate_raw 零尺寸返 None 走堆耗尽路径锚，2026-10-09）；host 126+6 = 白盒 118+6 + 黑盒 8（含 Host Contract 补锚段 14〔2026-10-04：三态对账 missing 清零——math 基本值族 10 + scanf B43 + strcpy 高边界/NULL + heap_offset 单调〕）（+G-3 桥保真锚与三 handler trap 锚〔审阅五轮：fopen/va_start/fread 非法地址→trap 文案〕） + doc test 2（黑盒承担对外面消费面点名）；vm 81 = 快照 wbtest 8 + 观测 wbtest 6（S8 批一号三段-a：变量快照作用域/find_var_name 数组区间与跨帧/数组快照 256 截断与元素形态/vis take 幂等；审阅 P1/P2 红锚 2026-10-01：find_var_name 元素宽度维度〔double 8/char 1——base_kind 修复锚〕+ 指针数组快照〔int*[2] 按 Int 取值/char*[2] 步长 1〕）/ 快照 wbtest〔门 3 六锚随 CheckpointManager 迁 time_travel（2026-09-30 批一号一段）〕+ executor wbtest 63〔含 void host 栈平衡红锚〕+ 黑盒 2（八族 + 审阅修复批符号扩展锚×10 + 段二 F/D/Q 三族锚 4 + 控制流锚 7 + 批三号一段分发锚 5〔ctype/math-exit/exit 族/malloc-free/输出与 rand〕+ 三轮审阅锚 3〔NegF 零符号/附注去重/fmod·atan2 非对称〕）+ 黑盒 2；对外面以 go run ./scripts/moonbit/moonbit_surface -check 对账；分解数以 moon test -p 逐包为准、裸总数以 facts `moonbit_test_passed` 为准；wasm-gc 库形态：`moon build --target wasm-gc gateway`（4 函数导出 + js-string 直传，Node 宿主驱动见仓库 scripts/wasm_gateway/host.js）；另有 native-only 包测试 122 个（fs 9 / gateway 99 / cli 14——gateway 99 含 #35 批 +1：serve_step_uaf_root_cause_hint_wire 红→绿锚，2026-10-09；cli 14 = #37 批 cli_zero_anchor_wbtest 15〔gateway 96 含批二 2026-10-06 +1：serve_memory_dump_roundtrip 往返锚〕 - 1〔2026-10-06 批一：utf8_decode 两锚随函数上提 util，cli 计数 16→14〕 + stdout_bytes_of 字节保真锚 1〔2026-10-05 出口编码修复批〕，此前 native-only 计数漏连坐 cli 包；issue #29 #4 vis_events 装配锚 + leak report 教学报告锚〔2026-10-04 analysis 片——append_leak_report 接线，分叉①销案〕〔2026-10-04：compile 第 9 步接线——algorithm_matches 投影灌 vm，恒空分叉销案〕+ step 族九锚 + dump 族七锚 + 批四号接线双锚〔bubble 正向/gcd 反向〕+ 审阅销项锚〔二次 begin 重标注链路〕2026-10-01~02 + 审阅销项三锚〔confidence wire 双形态 2/3 与 1.0 / completion 显式 null / records codes 浮点形态〕2026-10-02）不在裸口径内——`moon test --target native` 全量 840（2026-10-10 实测重账：#60 批 +9、审阅处置批 +2——两锚均双口径计入；836 基线取自 786e8102 提交态实测）（CI 门禁口径，2026-10-10 实测重账：#56 批 typeck +1〔与裸口径同锚〕、#47 病 6/8 批 host/memory 各 +1——病 7 为既有固化锚翻转不计数；此前 2026-10-09 实测——#47/#48 批 +9：host scanf/strdup/strchr 三锚 + typeck W3067 锚 + vm bounds 文案锚 + parser recovery 锚族；批五 +5：host 双锚+哨兵 + vm 去重锚 + gateway 封顶锚；含并发会话 gateway +1：host 双锚 + vm 去重锚 + gateway 封顶锚；批四 +3：libc N3/N4 销案锚 + host 星号/抑制双锚 + typeck %*d 锚；批二 +2：util base64 RFC 向量锚 + gateway memory.dump 往返锚；批一 util +1/cli −2 净 −1）；两口径并存系包目标后端差异（默认 wasm）
moon info                  # .mbti 接口面（API 变更信号）
```

## 坐标契约（vitro/engine/source）

输入档案：[列号口径冻结](../docs/current/07-质量与裁定/列号口径冻结.md) §2。

```mbt nocheck
SourceLoc { line, column, file_id }  // column = 行内 UTF-8 字节偏移 + 1
Pos { byte_off, col_scalar, col_utf16 }  // 双坐标预留，三值同源派生
```
