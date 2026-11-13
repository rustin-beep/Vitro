# Vitro MoonBit 引擎（活跃区）

> Rust 冻结对照区（`../native/`）的渐进迁移目标实现。上位文档：
> [MoonBit迁移总计划](../docs/current/01-定位与路线/MoonBit迁移总计划.md) ｜
> [总计划](../docs/current/01-定位与路线/MoonBit迁移总计划.md)

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
node scripts/moonbit/gen_diag/main.mts          # 从 Rust 源再生成 diag 包机器单源部分
node scripts/moonbit/gen_diag/main.mts -check   # 幂等校验（源变产物变 / 产物被篡改即红）
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
moon check && moon test    # 1422 测试（裸口径，facts 键 moonbit_test_passed 机判，漂移即 CI 红；批注明细单源 CHANGELOG——#308；2026-11-04 W4 尾件批 #418-#421 +9 裸域（gateway 7 + pp 1 + parser 1）；2026-11-04 #466 审阅处置 +4 裸域（P1 阈值边界 1 + P2 值级校验 1 + P2 同会话 note 锚 1 + util 透传锚 1）；2026-10-26 #314-#318 五案批 +2 裸域 +1 native-only；#330/#336 四段批 +1 裸域 wbtest；#338 批三 vprintf 族 +8、批四零测试包 +9 裸域；2026-10-27 #87 seek 几何化淘汰+重放快道 +5；2026-10-28 #342 审阅处置 P2-1 窗口塌缩锚 +1；2026-10-28 #325 swap 相位结构判据 +1；2026-10-28 #347 审阅处置 selection 判别力锚 +1；2026-10-28 #251 ULL 翻案批 +2；2026-10-28 #337/#343 声明点语义双案批 +17；2026-10-28 PR #344 审阅处置批 +8；2026-10-28 #213 语法错照跑 typeck 批 +2 native-only；2026-10-29 #356 POSIX 绝对锚批 +2 裸域 +1 native-only；同日审阅处置 +1 裸域 +1 native-only；2026-10-29 #366/#363/#349 三案批 +1 裸 +1 native；2026-10-29 #369/#370 零锚面锚 +2；2026-10-30 PR #375 审阅处置锚 +1；2026-10-29 #364 compile{files} 批 裸持平；2026-10-30 #382 mutation 闸批 +3 裸；2026-10-30 #380 dir_of 批 裸持平、审阅处置 裸持平；2026-10-30 #377/#376 include 归属批 +2 js/native 域（gateway 1 + vitro_wasm 壳 1），裸持平；2026-10-31 PR #401 ds 审阅批 init 定型回写/多维 W3008 锚 +2 裸域；2026-10-31 #95 vfs.list 列举口批 +3（host 1 + gateway 2）；2026-11-01 审阅 v2 批 A2 锚诚实化 +24 裸域（bytecode verify 红锚缺口 23 + host vfs feof 双形态 1）；2026-11-02 审阅 v2 批 B9 typeck 散件（#433）+4 裸域（M09 红锚 4 条入库）；2026-11-02 审阅 v2 批 B9 第二批（#433）+8 裸域（M03 typedef union 3 + M10c Pass2/数组 5）；2026-11-02 #427 批 B4 printf 缺臂族 +13 裸域（%n/%F/%a/%A 执行臂 + %05.0d 崩溃 + %q 门 + %hh 截断 + %# 前缀/尾零/保点 + %.17g/.17e 精确路径 + sprintf float 提升锚）；2026-11-03 审阅 v2 批 B2 判零截断族 #425 +4 裸域（codegen judgezero_wbtest 四锚）；2026-11-04 #467 审阅处置 P1 无符号轴 +2 裸域（codegen U-cast 锚 + typeck 管线锚））；2026-11-04 #459 B1 批链（#424 char4b 装载宽度族 + W3053 豁免族，第八轮 rebase 收拢基 e92d9e41）+11 裸域（codegen char4b 八锚 + typeck w3053 三锚：neg/unsigned 域 1 + 赋值路径/struct 域 2);2026-11-04 QC 属性批 +17 裸域（util quickcheck 属性——moon prove 盲区互补））；2026-11-04 #474/#428 B5 批链（scanf 族修复，rebase 收拢基 a3ba062c）+8 裸域（host_io wbtest：B5 四缺陷+缺臂锚 5 + 审阅处置 %Nc 流尽 EOF/-nan 未闭合/hhd 溢出 3）；2026-11-05 #472/#429 B6 批链（json_parse 孤代理拒绝 + C 字节串码元=字节承载治本，rebase 收拢基 12044941）+11 裸域（json_parse_b6_wbtest 锚族）；2026-11-04 审阅 v2 批 B7 seek 族修复（#430）+10 裸域（time_travel 4 + vm 1 + gateway 5）；B7b 追加 +3〔time_travel 视口对齐+waiting 守卫 2 + gateway waiting 零投递锚 1〕；2026-11-05 #432 审阅 v2 批 B8 预处理族 +3 裸域（pp elifdef_missing_name_diag / commented_include_not_edge / fn_macro_brace_no_dowhile_wrap））；2026-11-05 收口扫除批二（#446/#447/#448/#471/#465）+5 裸域（scanner E1001 列锚 + fs 孤代理编码锚 + codegen #471 四路径锚/LL↔F 双跳锚 + vm CastD2UQ 直驱锚）；2026-11-05 PR #485 审阅处置 +1 裸域 +1 native（codegen vardecl 防御层直驱锚——P2-1 单源化收实）；2026-11-05 PROVE-arith 批 +11 裸域（proofs/arith_mirror 对拍锚 5 + PR #480 处置批逐臂矩阵 6——wrap↔normalize 等价/拒绝路径/移位含 s=63 特判/I32·U32 全算子×边界值积，js/native 双域）；2026-11-05 #434 B10 批链（IO/运行时散件族）+14 裸域（host_convert_b10_wbtest 14 锚：vfs EOF/fgets n1/fseek 过尾/rename 释放/strtol 饱和·endptr·base/strtod 扫描器·inf·nan·hex 尾点/atol·atoi 饱和/strerror 静态块）；B10 PR 批补（遗留收尾）+3 裸域（host strerror UCRT 全表扩表锚 + strtod hex ERANGE 锚 + bytecode rerouted 死段登记锚）；PR #486 审阅处置 +4（vfs fgets 三停因/ftell round-trip 两锚 + strtod 零尾数/hex 零尾数上溢两锚）
                           # moon test --target native 全量 1493（CI 门禁口径，facts 键 moonbit_test_passed_native 机判；native-only 包〔fs/gateway/cli〕逐包分解以 moon test -p 为准；2026-10-29 #369/#370 零锚面锚 +2；2026-10-30 PR #375 审阅处置锚 +1；2026-10-29 #364 compile{files} 批 +5 native-only；2026-10-30 #377/#376 include 归属批 +1（gateway 锚）；同日 PR #390 审阅批 +2 native（gateway stub 两形态锚）+1 js（vitro_wasm collect_walk E2E 锚）；2026-10-31 #207/#319 cli stdout 锚 +1；同日 PR #394 审阅批 stderr 边界三态锚 +1；同日 PR #401 ds 审阅批 +2；2026-10-31 #95 vfs.list 列举口批 +3（host 1 + gateway 2）；2026-11-01 审阅 v2 批 A2 锚诚实化 +24 裸域（bytecode verify 红锚缺口 23 + host vfs feof 双形态 1）；2026-11-02 审阅 v2 批 B9 typeck 散件（#433）+4 裸域（M09 红锚 4 条）；2026-11-02 审阅 v2 批 B9 第二批（#433）+8 裸域（M03 typedef union 3 + M10c Pass2/数组 5）；2026-11-02 #427 批 B4 +13（host_b4_printf_wbtest 13 锚为 js/native 双域）；2026-11-03 审阅 v2 批 B2 判零截断族 #425 +4 native（同四锚）；2026-11-04 #467 审阅处置 P1 无符号轴 +2 native（同两锚））；2026-11-04 审阅 v2 批 B7+B7b seek 族（#430）+13（同锚族，js/native 双域）moon info                  # .mbti 接口面（API 变更信号；2026-11-02 #176 P0 观测落闸锚 +2（vm run_unobs_wbtest）；2026-11-02 #176 P0b 观测降本锚 +3（vm heat_array_wbtest）；同日审阅处置锚 +3（vm reset/global/run 入口））；2026-11-04 #459 B1 批链 +11 native（同锚——js/native 双域);2026-11-04 QC 属性批 +17（同十七属性））；2026-11-04 #474/#428 B5 批链 +8 native（同锚——js/native 双域）；2026-11-05 #472/#429 B6 批链 +11 native（同锚——js/native 双域）；2026-11-05 #432 B8 +3 native（同三锚——js/native 双域））；2026-11-05 收口扫除批二 +5 native（同锚族——js/native 双域）；2026-11-05 PR #485 审阅处置 +1 裸域 +1 native（codegen vardecl 防御层直驱锚——P2-1 单源化收实）；2026-11-05 PROVE-arith 批 +11 native（同锚——js/native 双域）；2026-11-05 #434 B10 批链 +14 native（同锚——js/native 双域）；PR 批补 +3 native（同三锚）；审阅处置 +4 native（同四锚）
