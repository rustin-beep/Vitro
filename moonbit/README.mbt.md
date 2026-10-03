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

## 性能现状（诚实披露，2026-09-26 实测）

VM 是为单步执行与时间旅行可观测性构建的**解释器**，不以裸速度为目标。
同机对拍 Rust oracle：端到端小程序（baseline 366 例中位，编译主导）
**1.42×**；计算密集 fib(20) / 冒泡 200 / 500×500 嵌套 **1.92× / 6.32× /
15.7×**；条件 A 300×300 循环（完整引擎 vs oracle JIT 路径）**10.1×**。
全速执行差距的正解是 bytecode→wasm-GC 生成器（规划 0.7.0+）；解释器持
续服务单步语义与时间旅行。完整口径见 `README.md`「性能现状」节与
`CHANGELOG.md`。

## 验证

```bash
moon check && moon test    # 629 测试（source 14 / opcode 10 / diag 21 / ast 14 / lexer 52 / parser 31 / names 5 / libc 4 / typeck 30 / bytecode 17 / codegen 15 / memory 31 / host 112 / vm 82 / time_travel 40 / teaching/steps 48（批六号 +4：oracle detect 两锚照搬〔BST deleteNode 不误判链表删除〕+ 十一判据正面覆盖〔cash 排除/union+find 双形态〕+ 十一算法 phase 表〔josephus m/remain 与 union_find x 数值文案〕——43/43 全量收官；批五号 +5：dp 两锚照搬〔初始化双层内层 j 排除 + 真实体 inner_loop〕+ math/dp 判据与 prev_vars 算式锚〔48 % 18 = 12 行入口操作数〕+ math+dp phase 表〔hanoi 柱名还原/币种主语〕；批四号 +8：oracle 两侧 tests 照搬三锚〔linearSearch 不误判 BFS/递归 binarySearch 不误判 DFS/命名反锚〕+ 七算法命名正面覆盖 + dijkstra 收紧正反锚 + BFS/graph phase 表双锚；审阅销项 +4：结构特征真 AST 锚〔bubble/binary/insertion——loop_depth 恒 0 死分支等价锚实锤 oracle 继承死分支〕+ B13 族序锚〔bstKmpSearch 双命中元素序〕；批一号 sorting 族+骨架；批二号 search/string 四算法〔binary 三红锚照搬+KMP nextval 优先序/行文本下标〕；批三号 tree 族八算法〔bst 家族双条件判据七锚照搬——isValidBST 方案②/裸命名 TreeNode 语境/语境反锚 + validate 三 phase 模板行锚 + delete 八行 phase 表〕；批四号 graph 族〔U1#1 P0-2 收紧版判据 + 七 infer 注释照搬〕——dp/math/structures 族随批；golden 族级对拍已建〔scripts/teaching_annotation_diff，五族 28 算法 82 模板全绿，未迁移族随批扩 rules.json〕） / diagnostics 32（段一~四 2026-10-02：数据层四表〔gen_diagnostics 双产物+J9〕+ 机制层五件〔generate_fix/apply_fix/误区滑窗〔confidence f32 语义化——值面 round_to_f32 位模式对齐，文本面随审阅 P1 销案走 gateway double_to_json_text〕/路径组装/图激活〕；黑盒 26 = Rust 单测照搬 13 + 行为锚 8 + 出口点名 1 + 审阅 F6/F7 锚 4；白盒 6 = 机制锚 6——f32 文本化锚随审阅 P1 销案退役，wire 锁定移 gateway probe 锚） / util 7 / protocol 46 / session 12；分解和 623 + 根 README doc test 6）——S5 起 bytecode/codegen 入列、S6 起 memory/host/vm 入列、S7 起 protocol 入列、S8 起 time_travel 入列、diagnostics 入列（2026-10-02）（CheckpointManager 自 vm 迁入 + 门 3 六锚随迁 + 批一号二段 FrameWindow/UnifiedEngine 十一锚（含整数积分界锚），2026-09-30/10-01）；protocol 46 = 白盒 39（schema 11 + types 5 + vocabulary 7 + stream 16〔8 锚照搬 Rust tests + 索引 0 预留 + 窗口直通 + 审阅 P1/P3 六锚：vis_events 幂等×2 + 符号表全内容 + 同长 return_line + 删除重现 + get_sym 越界〕）+ 黑盒 5（对外面消费面点名；stream encode/decode 往返）+ 包 README doc test 2（协议演化纪律三条成文 + json_or_null 组合子——批四号 openseek ①③）；白盒含审阅 P1/P3 批六锚（vis_events 双幂等锚 + 符号表全内容 + 同长 return_line + 删除重现 + get_sym 越界）；libc 4 为 N3/N4 漂移登记锚（审阅批四恢复）；bytecode 17 / memory 31 / host 112 各含 2 个包 README doc test（补指引批——时点见 git log）；memory 31 = 白盒 23 + 黑盒 6 + doc test 2；host 112 = 白盒 102 + 黑盒 8（+G-3 桥保真锚与三 handler trap 锚〔审阅五轮：fopen/va_start/fread 非法地址→trap 文案〕） + doc test 2（黑盒承担对外面消费面点名）；vm 81 = 快照 wbtest 8 + 观测 wbtest 6（S8 批一号三段-a：变量快照作用域/find_var_name 数组区间与跨帧/数组快照 256 截断与元素形态/vis take 幂等；审阅 P1/P2 红锚 2026-10-01：find_var_name 元素宽度维度〔double 8/char 1——base_kind 修复锚〕+ 指针数组快照〔int*[2] 按 Int 取值/char*[2] 步长 1〕）/ 快照 wbtest〔门 3 六锚随 CheckpointManager 迁 time_travel（2026-09-30 批一号一段）〕+ executor wbtest 63〔含 void host 栈平衡红锚〕+ 黑盒 2（八族 + 审阅修复批符号扩展锚×10 + 段二 F/D/Q 三族锚 4 + 控制流锚 7 + 批三号一段分发锚 5〔ctype/math-exit/exit 族/malloc-free/输出与 rand〕+ 三轮审阅锚 3〔NegF 零符号/附注去重/fmod·atan2 非对称〕）+ 黑盒 2；对外面以 go run ./scripts/moonbit/moonbit_surface -check 对账；分解数以 moon test -p 逐包为准、裸总数以 facts `moonbit_test_passed` 为准；wasm-gc 库形态：`moon build --target wasm-gc gateway`（4 函数导出 + js-string 直传，Node 宿主驱动见仓库 scripts/wasm_gateway/host.js）；另有 native-only 包测试 96 个（fs 9 / gateway 87——step 族九锚 + dump 族七锚 + 批四号接线双锚〔bubble 正向/gcd 反向〕+ 审阅销项锚〔二次 begin 重标注链路〕2026-10-01~02 + 审阅销项三锚〔confidence wire 双形态 2/3 与 1.0 / completion 显式 null / records codes 浮点形态〕2026-10-02）不在裸口径内——`moon test --target native` 全量 725（CI 门禁口径，2026-10-02 实测）；两口径并存系包目标后端差异（默认 wasm）
moon info                  # .mbti 接口面（API 变更信号）
```

## 坐标契约（vitro/engine/source）

输入档案：[列号口径冻结](../docs/current/07-质量与裁定/列号口径冻结.md) §2。

```mbt nocheck
SourceLoc { line, column, file_id }  // column = 行内 UTF-8 字节偏移 + 1
Pos { byte_off, col_scalar, col_utf16 }  // 双坐标预留，三值同源派生
```
