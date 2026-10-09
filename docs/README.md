# Vitro 项目文档

> 教学 C 子集参考执行引擎（白箱后端）——架构设计、语言子集规范、协议与测试防线
>
> 最后核对：2026-10-07（**全库逐份翻新第五轮：S9 修复批 + #27 图标批 + #49 统一入口批对齐**——《已知限制与差异》①表活缺陷清零〔22 条修复面销 20，头部真值锚脱 shadow〕/ 总计划 S9 行与路线图当前状态表对单轨真值〔脱钩工序①~④收官回灌〕/ CLI 手册与 CLI_PROTOCOL_V1 spec 补 icons.get + error_catalog.icon + trap 语义 id / 脚本总清单补登图标三脚本 + protocol_frames 33 帧 / 样本库·冻结资产清单·模板双册·golden 清单·认知推理·后端定位·工程债务册·C 规范定位段按删区后现状逐册回灌）。
> 前一沿革：2026-10-05（**删区批文档翻新第四轮**：S9 工序④ native/ 物理删除后的文档面连坐——
> 根 AGENTS 双区制改写为单区+退役档案、根 README oracle 节改退役档案与单轨格局、架构总图重画单轨并改名
> `vitro-architecture.svg`、shadow 门禁图改名 `clang-direct-gate-flow.svg` 且《影子验证框架》归档〔防线由
> clang_direct 吸收〕新建现役《Clang直拍门禁》、统一模式/协议/知识图谱/防线全景四图实现锚自 native/*.rs
> 切换 MoonBit 包〔session/time_travel/diagnostics 真锚实测核对〕、AGENTS_EN 同步）。
> 前一沿革：2026-10-04 全库逐份翻新第三轮（S8 收官 + 0.8.0 发版件对齐 + 10 份过程记录归档，
> 详见 git 历史 6870ca1 与下文归档记录）。
> 前一沿革：2026-09-29 全库逐份翻新第二轮（S7 批二~五全落 / 0.7.0 发版件就绪 / 模块审阅处置批对齐——
> 路线图与架构设计的 S7 状态回灌、出口分档落地状态行、CLI 手册补 MoonBit serve 孪生指引、
> 标准库防线引言测试数对真值（1027+508）、J9 台账补 2026-09-29 两记录并声明覆盖面演化、
> 快速入门 wasm 节 wasm-gc 落地对齐、任务 E 验收项 wasm32 进 CI 翻绿、
> 各活文档最后核对头部随批翻新；归档判定：本批无新增废弃文档。
> 前一沿革：2026-09-27 全库逐项翻新（S6 收官 / 0.6.0 发布 / S7 开工对齐）——
> 总计划与路线图里程碑、双区口径注记、R4/D5/U2 事后事件回灌、8 处发布档案 0.6.0、
> 全库系统性断链清理；2026-09-23 归类翻新——中文化 33 份、归档 7 份；2026-09-11 前端切割后重新整理）
>
> **沿革增补：2026-09-29 全库逐份翻新第二轮**（S7 协议/会话/出口批一~五全落 + 0.7.0 发版件就绪 +
> 模块审阅处置批〔b49d4ff〕的对齐批：路线图 §一/§二/§三 状态回灌〔S7 五批、闸数口径合并为指针式、
> 0.8.0 脱钩批入表〕；
> 架构设计管线行与出口表落地化〔session/gateway 不再"待建"、parser 语料 601 对真值〕；
> 出口分档补落地状态行；CLI 手册 serve 节补 MoonBit 孪生实现指引与超长行形态差；
> 标准库架构与测试防线引言测试数对真值；J9 台账补 serve_smoke 超长行 / facts 越界自检两记录 +
> 覆盖面演化注记；快速入门 wasm 节、工程债务任务 E 验收项、七份头部翻新）

> **沿革增补：2026-09-27 全库逐项翻新**（S6 收官 + 0.6.0 发布 + S7 protocol 批一号/段二入库的对齐批：
> 总计划 §10/§10.5 状态回填〔0.6.0 已发布、段二已落、G-2/G-5 已落〕；路线图 §三 S6 改收官视图 + 补时间线；
> 08 目录补《0.6.0》发布档案；脚本总清单补登 `scripts/moonbit/testcount` 与 `gen_protocol_fields`
> 两闸〔均已接 CI 而册上无记录〕；C 语言子集规范 double/预处理/_Alignof 排除口径随 E1/E2 落地更新；
> 05 目录 golden 主册回填 113 键全 ✅ 并给三份过程记录加闭环横幅；
> 06 目录 U2 拍板取代注记与 S1 双坐标待办勾销；07 目录统一整备路线图头部补让位声明）

> **沿革增补：2026-09-27 新增 01 目录《唯一依赖清除路线》**（唯一外部依赖 `moonbitlang/x@0.5.5` 形状实测：
> 消费面 = 5 个 cmd 包 × 7 函数、引擎核心零消费；五条路线（自写 / vendor+漂移探针〔推荐〕/ 拆模块 /
> 保留 / 等 core 收敛）+ 探针双层口径设计（内容哈希主 + 版本号辅）+ 落地清单；**实测新发现**：上游
> `fs_native.mbt` 已漂移而 version 未 bump（版本号口径探针会漏报）；未拍板，待用户裁定）
>
> **沿革增补：2026-09-26 新增 07 目录《kimicc外部参考调查报告20260926》**（moonbitlang 官方 MoonBit C 编译器
> 五维度深挖：总裁定 = 参考方法学不搬实现；Vitro 自查三产出中两项排版进总计划 §10.5 G-5/G-6、
> 层 2 直拍参照与 S9 JIT W^X 先例注记入 §7.1/§10；2026-09-26 会话调查落档）
>
> **沿革增补：2026-09-25 新增 06 目录《出口分档与宿主策略》**（F-5 执行展开：出口三分档口径 +
> 不提供 C ABI 三条硬理由 + 宿主四通道矩阵 + SharpTutor 迁移路径；2026-09-25 会话出口议题收敛落档）

> **目录约定**：自 2026-09-13 起 `current/` 下按分类存放于子目录（01-定位与路线 / 02-构建与上手 / 03-语言子集 / 04-标准库与防线 / 05-教学体验 / 06-出口与协议 / 07-质量与裁定 / 08-发布档案〔2026-09-23 增设〕）；新文档请放入对应子目录。
>
> **命名约定**：`current/` 下文档自 2026-09-13 起使用中文文件名（专有名词如 C++/CLI/VM/schema 保留英文）；
> 旧英文名在其他分支或本地检出中可能仍被引用，对照关系见各文档自身头部。
>
> **插图（SVG）约定**：`current/` 与 `spec/` 下的 15 张结构插图（架构总览〔原双轨格局图，2026-10-05 删区重画单轨〕 /
> Clang 直拍门禁〔原影子验证图，随防线吸收更名〕 / 三态缓存 / 知识图谱 /
> MoonBit 包切分编译侧 + 执行智能侧 / 统一模式架构 / 统一模式状态机 / 内存布局与有界隔离 /
> MoonBit 验证防线全景 / StepPayload 帧结构 / wasm 并发隔离 / 冻结协议层全景 / Agent Skills 全景 /
> 教学智能流水线）由 `go run ./scripts/gen_svg` 生成——插图自带深浅双底色
> （亮色白底 / 深色品牌墨底，随查看环境自动切换）；Clang 直拍图内的跑批快照数字带 `data-fact`
> 锚，由 `go run ./scripts/facts check` 机判漂移；Agent Skills 全景图从 `.agents/skills/` 盘上
> 目录与 frontmatter 扫描生成，skill 增删改名 / 描述变更必使图失步（`gen_svg -check` 即红）；
> **勿手改**入库 SVG（下次生成即回退）。

## 文档目录

### 📁 [current/](current/) — 当前有效文档

#### 定位、路线与架构

| 文档 | 说明 |
|------|------|
| [`current/01-定位与路线/后端定位与白箱计划.md`](current/01-定位与路线/后端定位与白箱计划.md) | **后端定位主计划**：前端切割决策、三出口一核心架构、协议先行、Phase 0~3 路线（原 `VITRO_BACKEND_SPLIT_WASM_WHITEBOX_PLAN.md`） |
| [`current/01-定位与路线/项目更名记录.md`](current/01-定位与路线/项目更名记录.md) | **项目更名记录**：Cide → Vitro 决策依据、命名映射、ABI 2.0.0 迁移指引、诚实边界与验证记录（2026-09-14） |
| [`current/01-定位与路线/MoonBit迁移总计划.md`](current/01-定位与路线/MoonBit迁移总计划.md) | **MoonBit 迁移总计划（2026-09-18 定稿，当前工作排期权威）**：唯一存活计划——形态裁定（同仓绞杀者/v1=C only〔C++ 已裁砍〕/JIT 倾向不搬/Go 驱动保留/wasm-gc 单出口）；**四门终局 0 红**（门0 弱通过、门1 通过 快于现役解释器 3.3×、门2 有条件 -W gc、门3 通过）；9 条一手语言事实；L0-L9 包切分总图；P1-P7 止血+按目标架构+放弃三清单；A/B/C/D 四级差分锚点；裸奔期最小防线 24 例；差异台账 v0（17 capability_flags）；风险登记册；S0.5-S9+全量切换里程碑（**实测进度：S2–S8 已全部收官；0.8.0 已于 2026-10-05 线上发布（tag `vitro-engine-0.8.0`，线上验收三件全绿）；0.7.0 已于 2026-09-30 线上发布；当前阶段 = S9 修复批——脱钩工序①~④已全部完成〔2026-10-05，native/ 物理删除〕，修复面 22 条已销 20（批一~批五，剩 #10/#20），#47 母跟踪收尾中；单侧演化 #32/#33 待排；2026-10-04 排期改写含 #39 真值源迁移前置；§10.5 G 系列已全闭环**）；探测档案取回指南（提交 `917251e`，16 份文档全量入 git 历史） |
| [`current/07-质量与裁定/moonbit生态参考调研20261005.md`](current/07-质量与裁定/moonbit生态参考调研20261005.md) | **MoonBit 生态参考调研（2026-10-05）**：GitHub 全量扫描（2,995 仓）+ 6 仓 clone 亲读——**Tier 1 事实：moonc 源码已开源**（前端+中端+wasm 后端〔native 后端未开源〕；relaxed SSPL + **非商业修改条款** + **编译产物 license 自选例外**〔vitro/engine 产物无传染〕；moon/core/async 均 Apache-2.0）——**停更应急预案经裁定不做**（判定书 §3.3：真停更即 fork OCaml 维护 wasm 后端链）；Tier 2 模式参考：minimoonbit-public（官方课程 MoonBit 子集编译器〔KNF/RISC-V〕）/ MoonbitNES（wasm 内存特化+多 target 条件编译）/ MoonLLVM（执行加速远期对照）；**零采纳零新增依赖** |
| [`current/07-质量与裁定/S9脱钩与裁定批判定书.md`](current/07-质量与裁定/S9脱钩与裁定批判定书.md) | **S9 脱钩与裁定批判定书（2026-10-05 终稿，十项全裁）**：三裁定实测终判输入——**JIT = wasm-gc 物理无处可放**（制品功能性 imports 仅 js-string ×6，零执行面 API）/ **libc = 单一路由表已落**（86 Bytecode + 2 改判 + 108 Host，遮蔽病结构性消除；**实锤 #39 漏登记第四生成链 gen_libc_data→bytecode_libc_data.json**，已评论登记）/ **Wasmtime 实测不成立**（.NET 绑定 48 编译期拒 non-externref + js-string 两侧无支持；CLI 引擎核心可编译——差距在绑定层，.NET 通道 = serve sidecar 或 WebView2）+ S4 期三欠账补收（names 二选一 / containers 归档〔实测从未建包〕/ decl 散拼重挂）+ **工序③升格冻结资产清单**（四层中间产物 diff〔vm_diff 无基线文件删即失效〕+ e2e 275 三路映射 + trap 锚面〔无 Clang 真值面须逐锚证红〕）+ **工序④准出升级**（替代建成才许移除；MoonBit 侧 fuzz 现状为零）；**§6 裁定表含「不做会怎样/默认值」分级列**（清扫组默认动作直接推进 / 风险防线组硬准出）；工序③④硬准出已改写总计划原文 |
| [`current/07-质量与裁定/S9冻结资产清单.md`](current/07-质量与裁定/S9冻结资产清单.md) | **S9 冻结资产清单（工序③固化验收件，2026-10-05 建；**✅ 已收官转验收档案态**——工序③全绿 + 工序④删区同日执行）**：工序顺序翻转（固化先行→脱钩→修复统一窗口）后的当时主战线——六面逐行（teaching golden ✅ 已迁出冻结区〔sha 对账臂 + 82 模板全量绿〕/ 四层中间产物 golden 601 例 / E1–E4 598 / e2e 275 三路映射 / trap 锚面逐锚证红 / shadow·clang_direct 差量吸收随工序④）；固化 gate = 当轮三防线全绿（起点 CI e8e5b63）；过渡对账臂纪律（旧份活到删区 + 行尾归一比 sha + 删区自动豁免） |
| [`current/07-质量与裁定/实机勘探语料扩充方案——许可分流与gcc分桶裁判.md`](current/07-质量与裁定/实机勘探语料扩充方案——许可分流与gcc分桶裁判.md) | **实机勘探语料扩充方案（2026-10-02）**：候选仓许可三级核验（chibicc/8cc/sds/csmith=无毒进主仓，gcc c-torture=GPL 留 fork，haoel/leetcode 无 license 排除）+ **许可分流格局**（无毒→主仓 corpus 目录五步义务链 / GPL→fork 孤儿分支 / 无主→排除）+ **gcc 分桶裁判**（fork 语料实测救回 ≥77 份 clang_red〔362 vs 285 绿〕——MinGW 头生态平台桶；golden 只来自 Clang 纪律不变，gcc 只改分桶）+ **cwd 注入解锁同目录 quote-include**（E1021 方法限制的同目录形态解法实证）+ chibicc 试金石（E2005×169=GNU 语句表达式教学边界确认） |
| [`current/07-质量与裁定/已知限制与差异.md`](current/07-质量与裁定/已知限制与差异.md) | **已知限制与差异（as-of S9 修复批 2026-10-07，主动披露）**：四分类清单——**①已知缺陷已清零**（9 条全部随 S9 修复批销案划线留档）/ 教学语义设计 6 条（受检访存·E3070 栈缓冲校验——有意的产品语义，Clang 同输入下是 UB）/ 与 C 标准·Clang 架构差异 8 条（32 位指针 4 字节模型等）/ 路线图缺口（单侧演化批候选等）/ 教学语义设计 6 条（受检访存·E3070 栈缓冲校验——有意的产品语义，Clang 同输入下是 UB）/ 与 C 标准·Clang 架构差异 8 条（32 位指针 4 字节模型等）/ 路线图缺口（S8 各项已落、S9 排期）；每条标注 Clang 对照状态；根 README 与 moonbit/README 双落点链接；差异台账机器单源 = `scripts/diff_ledger/ledger.json`（30 条，resolved-verified 12），本清单为台账人工导读层 |
| [`current/07-质量与裁定/demo实测样本库20261001/`](current/07-质量与裁定/demo实测样本库20261001/README.md) | **Demo 实测样本库（2026-10-01）**：九批真实 C 代码实测的**用户原码归档**（19 份逐字保留），每份均三方对拍（Clang 绿 / 引擎红 / Rust oracle 同病〔oracle 臂已随删区退役——历史时点事实〕），命中 issue **#3~#9（已全部随 S9 修复批销案关闭，转正待义务链执行——2026-10-07 状态回灌）**——const char\* decay 加宽 / 初始化列表尾逗号 / static 函数名作值 / long long 比较 / union 内联 body / E3036 不可达 / 三目类型统一；**暂不入测试体系**（语料扫描域外），转正条件与逐份映射见库内 README；全部两侧同病存量，修复挂 Rust 退役后单侧执行批 |
| [`current/07-质量与裁定/20260919_S2词法器执行记录.md`](current/07-质量与裁定/20260919_S2词法器执行记录.md) | **S2 词法器执行记录（2026-09-19）**：vitro/engine/lexer 收官——独立预处理 pass（续行拼接/注释剥离/指令/展开）+ LineMap + 宿主 IO（SourceProvider/Vfs）；L1/L2 双层 token TSV 差分逐字节一致（随机 2400 例 4800 TSV + 真实语料 444 例）；已知差异清单 13 条（MoonBit 修复项）+ 故意复刻的 oracle 缺陷 3 项登记；vitro/engine@0.2.0 上架 |
| [`current/07-质量与裁定/20260919_S3解析器执行记录.md`](current/07-质量与裁定/20260919_S3解析器执行记录.md) | **S3 解析器执行记录（2026-09-19）**：vitro/engine/parser 收官——六文件平移（瀑布/声明符螺旋/语句/声明/C++）；防护形态改造（depth 参数化 8 壳同构 + 声明符 Array 链迭代化 1250 层存活 + 回滚七字段全量快照 + stall_count 活性观测）；E1/E2 差分 597 样本逐字节一致 + E3 病态 12 样本同等拒绝 + E4 反向锚；差异驱动 parser_diff（--selftest J9）；未发布（随 0.4.0）；**§7 审阅修复批（09-20）**：offsetof depth 透传 + enum 常量求值迭代化 + 声明符折叠按 C 语义（有意分叉登记）+ --threshold 阈值锚 + 熔断守卫 + 顶层前瞻判定收口 + CI 接线 |
| [`current/07-质量与裁定/20260922_性能探究实录.md`](current/07-质量与裁定/20260922_性能探究实录.md) | **性能探究实录（2026-09-22 首轮四轮 §1–§4；其后 §8/§9 复跑与归因、§10 遗留、§11 S6 后复跑、§12 S7 wasm-gc 单出口后复跑、§13 S8 收官批全量复跑 + HEAD vs 0.7.0 同时段 A/B〔2026-10-04，判「无回归」〕、§14 时间旅行优化现状 + JIT 正交性、§15 S8 交付面全量实测（CLI 口径 + 库级对照，2026-10-04）、§16 wasm-gc 出口全场景实测（Node 宿主 + gateway；与 native CLI 同请求对照）、§17 跨实现执行对照（Clang/CPython/V8）**：①native 管线基线（四层 dump baseline 365 例全跑 1.2s/单文件 12.3ms/冷构建 6.2s）；②用户场景 + Rust oracle 对比（compile/run 中位 8–10ms；同层 1.4–1.6×；压力 6 维度随规模恶化至 ~3×，locals 最差；设计性拒绝两侧同构——expr 深度 512/全局区 60KB，**moon dump rc=0 须查产物 ok 字段**）；③时间旅行性能裁定（**累赘实锤**：每步全量快照 21μs=全速 320×、vs CPython 慢 3–4 数量级、bubble/nested 60s 跑不完；病灶=每步 CPU 非内存〔曾误判 OOM 已修正〕；优化=按需物化+checkpoint+写集 undo，StepPayload 协议冻结不动）；④wasm-gc 全面测试（**6/7 场景持平或反超 native**：lexer 1.7×/GC 2.3×；体积 -54%；唯一弱项=大批量超线性）+ 路线裁定（**bytecode→wasm 生成器为全速正解**〔栈式→栈式/1MB→memory 16 页/trap 白送〕，**模板超级指令搬运退役**）。含方法学坑 6 条与探针资产清单（`tmp/perf_probe/` 忽略区） |
| [`current/07-质量与裁定/20261007_jsonmbt真相源迁移.md`](current/07-质量与裁定/20261007_jsonmbt真相源迁移.md) | **.json.mbt 真相源迁移（jsonmbt 批②，2026-10-07；2026-10-08 合流勘正 + CI 复绿）**：11 张 `rules.json` 翻转为 `.json.mbt` 唯一真相源（`.json` 由 `jsonmbt build --pretty` 在 CI 再生、不入仓，**消费方零改动**）+ **moon 静态门禁**（类型/字段错编译期红——写坏的 `.json` 照样过下游 Go 闸门，"不接 moon = 只换载体不换保护"）；含 11 张消费方闸门表 / 本地三步纪律（`moon fmt scripts` → `cd scripts && moon check` → 再生）/ 逐张注入覆盖度与红牙证据；**勘正**：仓根 `moon.work` → `scripts/` 自立 workspace（根级会让 moonbit 产物搬仓根、`vitro/engine/` 前缀致消费面全断）；**复绿**（run 37733072522）：CI 补 `moon update`（干净 runner registry index 未初始化 ⇒ parser·lexer·x not found rc=127）、再生清单改自枚举 + 计数断言 11（原手抄 10 张漏 `perf_budget`） |
| [`current/01-定位与路线/架构设计.md`](current/01-定位与路线/架构设计.md) | 架构总纲（编译器管线 / VitroVM / 内存模型 / 时间旅行 / 诊断 / 协议 / 关键决策）——**主体描述删区前的 Rust 实现〔2026-10-05 退役〕，语义章节仍为 MoonBit 侧同语义参照，头部有现状横幅；按 MoonBit 目标架构重写已列待办**（原 `DESIGN.md`） |
| [`current/01-定位与路线/项目路线图.md`](current/01-定位与路线/项目路线图.md) | 项目路线图：当前状态、已完成里程碑、下一步、已知缺口 G1~G13（诚实记录）（原 `ROADMAP.md`） |
| [`current/01-定位与路线/结构重构与C23锚定决议.md`](current/01-定位与路线/结构重构与C23锚定决议.md) | 结构重构决议（R1~R4，已全部交付）+ C23 语言锚定 + E2 模块化预处理器 + E3 C23 语义级（原 `VITRO_RESTRUCTURE_PLAN.md`） |
| [`current/01-定位与路线/工程债务维护方案.md`](current/01-定位与路线/工程债务维护方案.md) | 工程债务偿还与长期维护方案（`#DXX` 债务编号体系的事实源）（原 `MAINTENANCE_PLAN.md`） |
| [`current/01-定位与路线/唯一依赖清除路线.md`](current/01-定位与路线/唯一依赖清除路线.md) | **唯一依赖清除路线（2026-09-27 实测；**✅ 路线 B 已拍板执行并落地〔2026-09-28 批〕**——vendor 搬迁 + 漂移探针 + moon.mod 依赖块清空）**：`moonbitlang/x@0.5.5` 形状实测（消费面 = 5 个 cmd 包 × 7 函数，引擎核心零消费）+ 四条结构性成本 + 七条硬约束 + 五条路线对比 + 探针双层口径（内容哈希主 + 版本号辅，`toolchain_probe` 同构）；**实测新发现**：上游 `fs_native.mbt` 曾漂移而版本号未 bump（版本号口径探针会漏报——探针设计直接动因） |
| [`current/01-定位与路线/内存安全规范.md`](current/01-定位与路线/内存安全规范.md) | 内存安全规范（Rust 边界、线性内存、堆隔离与检查清单）（原 `MEMORY_SAFETY.md`） |

#### 构建与上手

| 文档 | 说明 |
|------|------|
| [`current/02-构建与上手/快速入门.md`](current/02-构建与上手/快速入门.md) | 快速入门：命令行 / JSON-lines 会话 / wasm32 三条主路径（原 `QUICKSTART.md`） |
| [`current/02-构建与上手/构建指南.md`](current/02-构建与上手/构建指南.md) | 构建指南：引擎、CLI、wasm32、测试防线与排障（原 `BUILD.md`；脚本清单已拆分至下方专册） |
| [`current/02-构建与上手/脚本总清单与必跑防线.md`](current/02-构建与上手/脚本总清单与必跑防线.md) | **脚本总清单与必跑防线（2026-09-22 建册）**：`scripts/` 全量脚本入册（CI 门禁驱动 / 差分对拍 / 探针 / 生成器 / Python 残留处置）；CI 门禁全表与**本地提交前按改动区域的必跑矩阵**；用法权威源=各脚本头注，本册为一级索引与入册义务 |
| [`current/02-构建与上手/CLI使用手册.md`](current/02-构建与上手/CLI使用手册.md) | CLI 使用指南：**统一入口 launcher `scripts/bin/vitro`（默认 wasm 臂自动降级 native，#49）** + MoonBit 侧 `vitro` 总入口（run/compile/step/api 四子命令）+ serve 会话与 `icons.get`/`memory.dump` 方法面（2026-10-07 对齐 #27；Rust `vitro_cli` 章节已随删区整体退役）（协议契约单源在 [`spec/CLI_PROTOCOL_V1.md`](spec/CLI_PROTOCOL_V1.md)）（原 `VITRO_CLI.md`） |

#### 语言子集规范（行为契约）

| 文档 | 说明 |
|------|------|
| [`current/03-语言子集/C语言子集规范.md`](current/03-语言子集/C语言子集规范.md) | C 教学子集规范（支持语法 / C23 锚定 §2.10~2.12 / 排除清单 / 与 Clang 的已记录差异）（原 `C_SUBSET_SPEC.md`） |
| [`current/03-语言子集/CSharp前端引入计划.md`](current/03-语言子集/CSharp前端引入计划.md) | **C# 教学子集前端引入计划**（v4：砍 C++ 裁定后 MoonBit 四包重设计——原生类模型 / ARC / 异常栈展开 / 插值 host func 语义核 / 双 oracle 语料格局；SharpTutor 锚定；**设计稿**——CS 批挂 MoonBit 1.0 后语言版图窗口，未开工，2026-10-04 状态注记）（原 `CSHARP_EXTENSION_PLAN.md`） |

> C++ 子集两份文档（规范 + 拓展实施计划）已随砍 C++ 裁定（2026-09-20）归档至 [`archive/`](archive/)，见下方归档记录。

#### 标准库与测试防线

| 文档 | 说明 |
|------|------|
| [`current/04-标准库与防线/标准库支持矩阵.md`](current/04-标准库与防线/标准库支持矩阵.md) | 标准库支持矩阵（头文件 × 函数 × 实现层 × 验证状态）（原 `SUPPORTED_LIBC.md`） |
| [`current/04-标准库与防线/标准库架构与测试防线.md`](current/04-标准库与防线/标准库架构与测试防线.md) | 标准库四层架构（VM Builtin / Rust Host / Bytecode Libc）与测试设计（原 `STDLIB_AND_TEST_DESIGN.md`） |
| [`current/04-标准库与防线/Clang直拍门禁.md`](current/04-标准库与防线/Clang直拍门禁.md) | **Clang 直拍门禁（clang_direct，CI 硬门禁）**：真值源 = Clang 本尊、被测物 = MoonBit `cmd/run`，全量语料逐例对照；`known_direct.json` 白名单 digest 锁定；吸收 shadow 防线（2026-10-05 删区批，语料差量 0；前身已归档 [`ARCHIVE_影子验证框架.md`](archive/ARCHIVE_影子验证框架.md)） |
| [`current/04-标准库与防线/学生错误用例集.md`](current/04-标准库与防线/学生错误用例集.md) | 学生常见错误测试用例集（⚠️ 人工整理的假想清单，未接防线；真实失败路径语料见裁定 G1）（原 `STUDENT_ERROR_TEST_CASES.md`） |
| [`current/04-标准库与防线/TODO注释规范.md`](current/04-标准库与防线/TODO注释规范.md) | 代码内 TODO/FIXME/HACK/SAFETY 标签与 `#DXX` 编号约定（原 `TODO_CONVENTION.md`） |

#### 统一模式、可视化与教学体验

| 文档 | 说明 |
|------|------|
| [`current/05-教学体验/S8时间旅行与教学智能总览.md`](current/05-教学体验/S8时间旅行与教学智能总览.md) | **S8 四域收官总览（单一导读）**：时间旅行帧语义与检查点体系 / teaching 43 族识别与推断 / diagnostics 教学七元组 / analysis 裁定边界 + demo 展示面与已知边界（2026-10-04） |
| [`current/05-教学体验/统一模式设计.md`](current/05-教学体验/统一模式设计.md) | 统一模式 / 时间旅行设计（状态机、检查点、帧缓存、seek 契约）（原 `UNIFIED_MODE_DESIGN.md`） |
| [`current/05-教学体验/VM教学体验优势.md`](current/05-教学体验/VM教学体验优势.md) | 自研 VM 的体验优势（热力图 / 语义进度条 / 变量历史 / 异常回退）（原 `VM_EXPERIENCE_ADVANTAGE.md`） |
| [`current/05-教学体验/算法与数据结构教学设计.md`](current/05-教学体验/算法与数据结构教学设计.md) | 算法与数据结构支持总设计（模式识别 / 运行时验证 / 轨迹分析；G9 缺口权威证据源 §7）（原 `ALGORITHM_DATASTRUCTURE_DESIGN.md`） |
| [`current/05-教学体验/认知推理系统设计.md`](current/05-教学体验/认知推理系统设计.md) | 认知推理系统（根因分析 / 认知误区 / 知识图谱 / 意图推断，P0~P3 全部落地）（原 `COGNITIVE_REASONING_ROADMAP.md`） |
| [`current/05-教学体验/模板维护指南.md`](current/05-教学体验/模板维护指南.md) | 算法模板维护指南（目录结构、meta.yaml、占位符；**生成链路 2026-10-05 删区后转存量产物态**——sync_templates.py 已退役、82 生成用例存量于 corpus/template_generated，防线由 clang_direct 承接）（原 `TEMPLATE_GUIDE.md`） |
| [`current/05-教学体验/模板与验证解耦设计.md`](current/05-教学体验/模板与验证解耦设计.md) | 模板与验证解耦方案（模板即合法 C + Clang Golden + 双重验证）（原 `TEMPLATE_AND_VERIFICATION_DECOUPLING.md`） |
| [`current/05-教学体验/算法标注golden人审清单.md`](current/05-教学体验/算法标注golden人审清单.md) | **算法标注 golden 人审清单（防线 6 · U1#1①，v5 2026-09-14）**：82 模板（37 有标注 311 条首现 + 45 零标注）人审主册，基线 v3 golden 已接 CI；**S8 承接（2026-10-04）**：golden 体系已进 MoonBit teaching/steps（311/311 对拍 + `teaching_annotation_diff` 入 CI + compile 帧 `algorithm_matches` 出口）；三份审阅过程记录已归档 |

#### 出口、协议与引擎决议

| 文档 | 说明 |
|------|------|
| [`spec/STEP_PAYLOAD_SCHEMA_V0_1.md`](spec/STEP_PAYLOAD_SCHEMA_V0_1.md) | **StepPayload v0.1 语言中立协议 schema**（已冻结，S1–S5 签字回放 61/61；§9 v0.2 激活轨道、附录 B 受控词汇表） |
| [`spec/CLI_PROTOCOL_V1.md`](spec/CLI_PROTOCOL_V1.md) | **CLI 输出协议 v1**（agent/shell/防线消费契约：标记行六前缀 + 退出码五值表 + `--json` NDJSON 事件流 + argv 偏移约定；帧语义引用 StepPayload 单源；CLI 出口总账 #37 三批随批冻结，2026-10-04） |
| [`current/06-出口与协议/下游需求处置回执.md`](current/06-出口与协议/下游需求处置回执.md) | 下游需求清单处置与窗口表态（A/B/C/D 逐项回执；第二批 capi 窗口、三段式内存地图、会话语义；capi 后续已由 U2 拍板裁不做）（原 `VITRO_DOWNSTREAM_REQUESTS_RESPONSE.md`） |
| [`current/06-出口与协议/堆有界隔离决议.md`](current/06-出口与协议/堆有界隔离决议.md) | 堆内存决议：bump 分配 + 有界隔离（三道墙；已拍板已实施，U2 不可破坏项）（原 `VITRO_HEAP_QUARANTINE_DECISION.md`） |
| [`current/06-出口与协议/wasm多实例并发模型与U2拍板.md`](current/06-出口与协议/wasm多实例并发模型与U2拍板.md) | 宿主并发模型裁定：N 线程 × N 实例构造性隔离（三宿主形态 + 1实例=1线程=1会话铁律）+ U2 拍板（19 声明冻结现状、第二批 capi 裁不做、下游改道 wasm/serve）（2026-09-19） |
| [`current/06-出口与协议/出口分档与宿主策略.md`](current/06-出口与协议/出口分档与宿主策略.md) | **出口承诺面口径契约 + 宿主接入策略**（F-5 展开）：三分档（承诺=wasm-gc 制品/冻结协议/生成 SDK/.mbti ｜ 可用不承诺=native/js ｜ **不提供=C ABI** 三条硬理由+触发线）、四通道宿主矩阵（WebView=图形宿主首选/协议 sidecar/mooncakes 源码级/生成 SDK）、数据源单源论（引擎画数据、下游画像素）、SharpTutor 三段迁移路径、**§6 TS 层职责三层拆解 + 待命时序 + 语言版图终态**（双核 MoonBit+Go、TS 待命、UI 主体=下游/社区，2026-09-25） |

#### 质量、裁定与工作记录

| 文档 | 说明 |
|------|------|
| [`current/07-质量与裁定/统一整备路线图.md`](current/07-质量与裁定/统一整备路线图.md) | **统一整备路线图 U0~U7**〔**排期权威已让位**：2026-09-18 起实际排期载体为 [MoonBit 迁移总计划](current/01-定位与路线/MoonBit迁移总计划.md) 的 S 系列；本表保留为 U 批次历史口径与未闭环项索引〕：三语化 S 系列与重构评估 Phase 系列的合并执行方案（波次总览 / CS 硬门禁 / 防伪绿机制）（原 `VITRO_OVERHAUL_ROADMAP.md`） |
| [`current/07-质量与裁定/核心资产重构裁定.md`](current/07-质量与裁定/核心资产重构裁定.md) | **核心资产重构裁定 v1（独立裁定）+ 重构执行方案**：分区裁定 / 判据 J1~J10 / 候选对比 / 中止条件 / §13 五域执行方案（D1 防线自身、D5 工具链语言 Python→Go 迁移边界与双轨纪律）；**§14 JIT trace 路径 P0 静默错值**（嵌套纯计数循环被外层 trace 穿透；**归因修正为与 `long long` 无关**；根因 = JIT fast path 在录制期间未禁用；含四组双向验证实验与 `vm_bench` 两处方法学缺陷）；**§14.11 对重构范围的影响**：新增子域 **D6（JIT 加速器存废重裁：先校正 `vm_bench` 重测加速比 → 删 JIT 或收缩作用域）**、D1b 形状对抗生成、J10 前置到 W1。**现状注记（2026-10-04）**：裁定①已被 MoonBit 绞杀者迁移实践超越、D5 已收官、D6 已由总计划 F-3 承接——本文保留为裁定过程与判据体系档案（native 冻结区防线仍引用）。实测脚本与证据 JSON 原在 `scripts/core_asset_verdict/`——**已随 2026-10-05 删区退役**（探针对象为 Rust 冻结区；git 历史 / tag `rust-oracle-freeze` 可回溯）（原 `VITRO_CORE_ASSET_RECONSTRUCTION_VERDICT.md`） |
| [`current/07-质量与裁定/Vitro架构审阅报告v2.md`](current/07-质量与裁定/Vitro架构审阅报告v2.md) | **Vitro 架构审阅报告 v2·整合版（2026-09-21，含修正批 b）**：12+ 轮对话收敛——技术终局（一门语言做核心 + 协议做契约 + 主进程掌控实例边界 + 任意语言做插件两档隔离）/ 15 处认知修正台账 / 对外面实测 200 符号 vs "只暴露三面"硬约束（收窄路径：未发布包零成本窗口 + 签名闭包单位 + 白名单 -check 先证红）/ SLOT_STRATEGY_VERSION 三态分档方案（含 global_data_end 交叉点）/ 插件架构终局裁决 / 最紧三条待办与依赖排序（v1 时序累积版已归档） |
| [`current/07-质量与裁定/kimicc外部参考调查报告20260926.md`](current/07-质量与裁定/kimicc外部参考调查报告20260926.md) | **kimicc 外部参考调查报告（2026-09-26）**：moonbitlang 官方 MoonBit C 编译器（bobzhang 主理，1467 commits 极活跃，SQLite 3.49.1 conformance 水平）五维度深挖（预处理器/解析器 AST/MIR ctype/后端 JIT/测试防线）+ 主会话亲读交叉验证，全部结论带 file:line 证据；**总裁定 = 参考方法学/惯用法/防线形态/架构决策样本，不搬实现**（kimicc 不能当 oracle、bobzhang/cfront 依赖禁入核心链、覆盖面是上界非追赶目标）；**Vitro 自查三产出**（codegen 成员偏移两份 inline 拷贝 / printf 事实三处分居 / BytecodeGen 不依赖 typeck——前两项已排版进总计划 §10.5 G-5/G-6）；后续工作项排版：§10.5 增补 G-5/G-6、§7.1 层 2 参照注记+防线增量五件、§10 S9 JIT 复核 W^X 先例注记 |
| [`current/07-质量与裁定/列号口径冻结.md`](current/07-质量与裁定/列号口径冻结.md) | 列号现状口径冻结（词法 +1 / 解析非 ASCII −4 / make_token 量纲混算根因）+ MoonBit vitro/source 双坐标契约输入 + 10 形状防漂移锚（2026-09-19） |
| [`current/07-质量与裁定/脚本埋雷验证记录.md`](current/07-质量与裁定/脚本埋雷验证记录.md) | **J9 台账**：五个判定型脚本（shadow_verify / ci_three_tier_check / serve_smoke / facts / precompile_bytecode_libc）的"注入→必须红"埋雷实证台账——判定型脚本埋雷记录 = 0 时其全绿不得作为结论依据（W0-1 / U0#8 验收达成）；MoonBit 迁移期新增闸（diff_ledger / teaching_annotation_diff / protocol_frames 等 20+）的证红以各脚本头注与提交为权威源（覆盖面演化注记） |
| [`current/07-质量与裁定/INCIDENTS/README.md`](current/07-质量与裁定/INCIDENTS/README.md) | **事故归档制度与索引**（模板 + 归档规则：任何 GB 级资源事故必须归档，与 CHANGELOG 分工；在档：[seek 重放泄漏](current/07-质量与裁定/INCIDENTS/事故202609_Seek重放泄漏.md)） |
| [`current/07-质量与裁定/协作纪律与事故档案.md`](current/07-质量与裁定/协作纪律与事故档案.md) | **协作纪律与事故档案（as_of 2026-10-09）**：回答"**这条纪律是哪次事故换来的**"——①审阅方式（突变测试 3/3 检出起源、**渗出证据链**〔09-06~09-12 九次"防线加压照出存量"：门禁化 4 例 / 外部审查 12 项全成立 / **保险丝从未生效** / **29 个 `.in` 从未使用致虚假 match** / 浮点语义错存活全部防线 / 词汇闭合首日 3 条不可达〕、J9 防线的防线、**人审位置在机器盲区**〔两次公开实锤：覆盖面质询照出 4 条注释 Rust 病入 [#47](https://github.com/rustin-beep/Vitro/issues/47)、`int main{` 抓出 parse error recovery 缺失立案 [#48](https://github.com/rustin-beep/Vitro/issues/48)〕）②**纪律 ↔ 来源事故对照表**（AGENTS 13 条逐条溯源 + 事故留痕 / 规模 realism / 保险丝可触发性 / 合成靶料效力边界 / 双向对账防僵尸条目等来自事故但按"不堆时点事实"留在本档者）③权限与授权（AI 无独立落案权、授权逐次且可细分）④**否决与撤回档案**（整体 C 重写多轮驳回 / 分而自治降级"已评估暂不采纳" / 语言选型三条结论全撤回 / 独立成仓立项当日改判废弃 / 3D 截图方案否决）⑤查证指引 + **残留缺口**（素材主要来自不入库的工作日志，已诚实登记）——与 `04-工具链与踩坑`（确定性坑）/ `INCIDENTS/`（GB 级资源事故）/ `统一整备路线图.md` §4（机制表）三处归口互补不重复 |
| [`current/07-质量与裁定/moonc警告全表20261009.md`](current/07-质量与裁定/moonc警告全表20261009.md) | **moonc 警告全表（2026-10-09 留档）**：`moonc check -warn-help` 官方 93 项警告 id/mnemonic/三态（warn/error/off）对照表——警告债清理与严格度开启总账 [#54](https://github.com/rustin-beep/Vitro/issues/54) 的 Part B `@<spec>` 升错误配方的查表底册；含 `--warn-list` 语法五形态与 A1 批后基线快照（--target all 310 条分布） |

#### 发布档案（mooncakes 版本史）

每版一份发布说明：版本语义裁定 / 包清单 / 主题 / 验收与外部影响；与根 [`CHANGELOG.md`](../CHANGELOG.md)（Keep-a-Changelog 累计格式）互为经纬。

| 文档 | 说明 |
|------|------|
| [`current/08-发布档案/0.1.0.md`](current/08-发布档案/0.1.0.md) | **0.1.0（2026-09-19）**：S1 基础片首发——source/opcode/diag/ast 四包；发布身份插曲（vitro 账号） |
| [`current/08-发布档案/0.1.1.md`](current/08-发布档案/0.1.1.md) | **0.1.1（2026-09-19）**：source 点修复版 |
| [`current/08-发布档案/0.2.0.md`](current/08-发布档案/0.2.0.md) | **0.2.0（2026-09-19）**：S2 词法器收官——lexer + 4 子包 + dump_tokens，差分 2400 例逐字节一致 |
| [`current/08-发布档案/0.3.0.md`](current/08-发布档案/0.3.0.md) | **0.3.0（2026-09-19）**：lexer 审阅修复批——real_line 归属通道 + 打包卫生 |
| [`current/08-发布档案/0.4.0.md`](current/08-发布档案/0.4.0.md) | **0.4.0（2026-09-21）**：编译层全链在架——names/libc/typeck/codegen/bytecode + parser + 3 工具；收面 27 符号 + 双面闸 |
| [`current/08-发布档案/0.5.0.md`](current/08-发布档案/0.5.0.md) | **0.5.0（2026-09-23）**：README 英文化 + 接口面三处实变（+compile_library/+LibcSig/−template_arg_eq）；外部用户证实（25 下载） |
| [`current/08-发布档案/0.6.0.md`](current/08-发布档案/0.6.0.md) | **0.6.0（2026-09-26 发版件 · 09-27 线上发布）**：执行层收官——memory/host/vm 三包 + util + cmd/run；HostMemReply.value 加宽 UInt?→UInt64?；兼容义务建册 + 性能披露双语落档 |
| [`current/08-发布档案/0.7.0.md`](current/08-发布档案/0.7.0.md) | **0.7.0（2026-09-29 发版件 · 09-30 线上发布）**：协议层与 wasm-gc 单出口——fs/protocol/session/gateway/gateway-wasm 五新包（L0–L8 共 20 包）；module 依赖清零（vendored）；彩排 + 线上验收全绿实录 |
| [`current/08-发布档案/0.8.0.md`](current/08-发布档案/0.8.0.md) | **0.8.0（S8 收官版 · 2026-10-04 发版件 · 2026-10-05 线上发布；实录全文已回填〔彩排 registry 投放法四件 + publish + 线上验收三件，search 在架 35 downloads〕）**：时间旅行与教学智能四域（time_travel/teaching/steps/diagnostics）+ CLI 出口总账（vitro 总入口/cmd/lib/cli/api 万能单帧/协议契约 spec）+ compile 帧 algorithm_matches（净增 4 包共 24 包） |

---
### 📁 [spec/](spec/) — 语言中立协议

对外承诺的 wire format 定义，与任何前端实现解耦。当前：

| 文档 | 说明 |
|------|------|
| [`spec/STEP_PAYLOAD_SCHEMA_V0_1.md`](spec/STEP_PAYLOAD_SCHEMA_V0_1.md) | StepPayload v0.1（**已冻结**，2026-09-12，S1–S5 签字回放 61/61）；§9 v0.2 激活轨道、附录 B 受控词汇表 |
| [`spec/CLI_PROTOCOL_V1.md`](spec/CLI_PROTOCOL_V1.md) | CLI 输出协议 v1（标记行六前缀 / 退出码五值 / `--json` NDJSON 事件流 / argv 偏移约定——CLI 出口总账 #37 三批随批冻结，2026-10-04） |

---

### 📁 [archive/](archive/) — 历史归档文档

存放**已完成、已废弃或对象已不在本仓库**的历史文档，仅供追溯：

> 命名约定：2026-09-11 起新归档统一加 `ARCHIVE_` 前缀并在标题下写入归档横幅（含归档原因与日期）；
> 2026-09-13 起归档名同样中文化；更早期的归档文件保留原名（如 `FLUTTER_MIGRATION_PLAN.md`、`REVIEW_2026-06-14.md`）。

- 前端时代的迁移与构建（MAUI → Flutter、Flutter 构建脚本、web 部署、前端 UI 设计）
- 历史代码审查报告与事故复盘
- 已完成的实现计划（double / 函数指针 / 多文件编译 / 内存扩容 / 递归类型重构 / 指针复合赋值等）
- 一次性评估报告与工作记录

**2026-10-05 本次归档**（S9 工序④删区批文档翻新，逐个取证后判定；2 份——全部加归档横幅，current 区 9 处活引用已改指现役/归档）：

| 归档文件 | 原名（docs/current/） | 原因 |
|------|------|------|
| `ARCHIVE_影子验证框架.md` | `04-标准库与防线/影子验证框架.md` | 对象已退役——shadow 驱动 `scripts/shadow_verify.go` 随 2026-10-05 删区物理删除，防线由 clang_direct 吸收（语料差量 0）；机制章节失效，§七演化史（45→685 例）留档；现役文档《Clang直拍门禁》承接 |
| `ARCHIVE_MoonBit迁移第一阶段计划.md` | `01-定位与路线/MoonBit迁移第一阶段计划.md` | 双使命终局——S0.5 Rust 止血批（P1–P7/U1/U2）修复对象随删区物理删除；S1 基础片已落地随 0.1.0 发布，工程约定由总计划与 moonbit/AGENTS.md 承接；迁移史追溯留档 |

**2026-10-04 本次归档**（全库逐份翻新第三轮，逐个取证后判定；10 份——全部加归档横幅，current 区 15 处活引用已改指 archive）：

| 归档文件 | 原名（docs/current/） | 原因 |
|------|------|------|
| `ARCHIVE_算法标注golden机器初审20260913.md` | `05-教学体验/算法标注golden审阅意见.md` | 过程记录·已闭环（2026-09-27 注）——发现经二审/三审与主册 v5 第三批全部消化，终态 113 键全 ✅ 由主册承载 |
| `ARCHIVE_算法标注golden审阅意见二审20260913.md` | `05-教学体验/算法标注golden审阅意见二审20260913.md` | 同上（P0/P1 经主册附录 A.3/A.4 收口） |
| `ARCHIVE_算法标注golden审阅意见三审20260914.md` | `05-教学体验/算法标注golden审阅意见三审20260914.md` | 同上（§5 最小处置清单 8 项经主册 §0.1 处置完毕） |
| `ARCHIVE_工作记录20260912_突变测试.md` | `07-质量与裁定/工作记录20260912_突变测试.md` | 一次性工作记录（3/3 检出已实证）；J9 制度由《脚本埋雷验证记录》台账持续承载 |
| `ARCHIVE_Vitro架构审阅报告v1_20260921.md` | `07-质量与裁定/Vitro架构审阅报告20260921.md` | 被同日 v2 整合版（含修正批 b）取代，v1 仅时序保留 |
| `ARCHIVE_实测发现登记20260913_性能与头文件.md` | `07-质量与裁定/实测发现登记20260913_性能与头文件.md` | 登记使命已尽——H 域/D 域随 U1#11 修复闭环、P-1 随 G6 关闭、性能域被《性能探究实录》（§1–§17 持续复跑）全面超越 |
| `ARCHIVE_重构评估报告20260912.md` | `07-质量与裁定/重构评估报告20260912.md` | §5 已并入 U 系列路线图；§1~§4 证据由 INCIDENTS 事故档案与 MoonBit 逐包勘察承接 |
| `ARCHIVE_三语化整备审计计划.md` | `07-质量与裁定/三语化整备审计计划.md` | 三语化整备路线已被 MoonBit 迁移全面取代落地（S0.5–S8 收官）；§5 批次表早已并入 U 系列 |
| `ARCHIVE_CAPI评审回复与实现状态.md` | `06-出口与协议/CAPI评审回复与实现状态.md` | 对象已终局——capi 后续批次经 U2 拍板裁不做、出口分档锁定「不提供 C ABI」；首批 13 入口为冻结区存量随 1.0 退役 |
| `ARCHIVE_代码审阅与修复追踪20260906.md` | `07-质量与裁定/代码审阅与修复追踪20260906.md` | 追踪使命终局——前端条目随切割关闭、Rust 条目随冻结转登记态、E-P1 落点已整删；活跃缺陷由 GitHub issue 承接 |

**2026-09-23 本次归档**（MoonBit 迁移现状对齐翻新）：

| 归档文件 | 原名（docs/current/03-语言子集/） | 原因 |
|------|------|------|
| `ARCHIVE_C++子集规范.md` | `C++子集规范.md` | 砍 C++ 裁定（2026-09-20，总计划 F-2）后 C++ 零迁移；Rust 冻结区语义参考价值在横幅中注明（cpp shadow 99 防线跑到 Rust 区退役） |
| `ARCHIVE_C++拓展实施计划.md` | `C++拓展实施计划.md` | 同上；Phase 31~42 历史记录，语义参考价值保留在 git 历史 |

**2026-09-13 本次归档**（归类翻新，逐个取证后判定）：

| 归档文件 | 原名（docs/current/） | 原因 |
|------|------|------|
| `ARCHIVE_数据结构模板路线图.md` | `DATASTRUCTURE_TEMPLATE_ROADMAP.md` | P0/P1/P2 三批次全部完成，使命耗尽；维护现状由《模板维护指南》承担 |
| `ARCHIVE_零侵入可视化设计.md` | `ZERO_INTRUSIVE_VISUALIZATION.md` | 检测器从未在后端实施、渲染层已随前端切割迁出；缺口记录见路线图 G9 |
| `ARCHIVE_C++容器模板迁移笔记.md` | `STAGE2B_CPP_CONTAINER_TEMPLATE_NOTES.md` | 迁移已完成（Phase 34/41）；两条活约束已回填《C++子集规范》§4.4（G13） |
| `ARCHIVE_BytecodeLibc产品化.md` | `BYTECODE_LIBC_PRODUCTIZATION.md` | §九验收标准 7/7 全部实现，项目完结；已知限制可入内追溯 |
| `ARCHIVE_代码审查复核20260911.md` | `code_review_report_2026-09-11.md` | 外部 PR 12 项复核与批次 A~H 修复全部收口；留痕由 CHANGELOG 承接 |
| `ARCHIVE_工作记录20260911_Shadow提速与Phase1.md` | `WORKLOG_2026-09-11_SHADOW_SPEEDUP_AND_PHASE1.md` | 四项工作全部合入 CHANGELOG / spec / CLI 手册，遗留项闭环 |
| `ARCHIVE_语义单源审计20260912.md` | `R3_MULTI_TRUTH_AUDIT.md` | R3 批次验收线即本清单归档；保留项已归属 CS0/CS5/R4 |

**2026-09-11 归档**（前端切割后）：

| 归档文件 | 原因 |
|------|------|
| `ARCHIVE_BUILD_SCRIPTS.md` | 所描述的 Flutter 构建脚本已全部移除 |
| `ARCHIVE_CI_FAILURES.md` | FRB / Android CI 故障载体已随 CI 收缩消失 |
| `ARCHIVE_code_review_report_2026-06-13.md` | 审阅范围含前端，已被 09-06 / 09-11 报告取代 |
| `ARCHIVE_CIDE_MOBILE_TEACHING_THREE_LANGUAGE_PLAN.md` | "移动端优先"定位已被后端主计划取代 |
| `ARCHIVE_CPP_BUILTIN_LAYOUT_DECOUPLING_PLAN.md` | 布局解耦已完成（Phase 41） |
| `ARCHIVE_DATASTRUCTURE_SYNTAX_ROADMAP.md` | 语法拓展已完成（Phase 27） |
| `ARCHIVE_IMAGE_INPUT_INTEGRATION_PLAN.md` | 依赖已移除的前端与 OCR 能力 |
| `ARCHIVE_LOCAL_PERSISTENCE_PLAN.md` | 方案载体（Dart 运行时）已迁出 |
| `ARCHIVE_M7_BETA_READINESS.md` | 里程碑评估已被 Phase 34~42 超越 |
| `ARCHIVE_PANEL_DRAG_GESTURE_DESIGN.md` | 前端交互设计，宿主已迁出 |
| `ARCHIVE_PHASE_KR_LEETCODE_TEST_PLAN.md` | 计划已达成（K&R 69 绿 / LeetCode 138 通过） |
| `ARCHIVE_POINTER_COMPOUND_ASSIGN_PLAN.md` | 已全链路支持（2026-06-28） |
| `ARCHIVE_RECURSIVE_TYPE_SYSTEM_REFACTOR.md` | 重构已落地于 `vitro_ast` |
| `ARCHIVE_S6_READINESS_ASSESSMENT.md` | 阶段评估已被后续里程碑覆盖 |
| `ARCHIVE_SHADOW_VS_CI.md` | 立论前提（特性缺失期）已消失 |
| `ARCHIVE_WEB_DEPLOYMENT_CLOUDFLARE_AND_WASM_INTEGRATION.md` | Flutter Web 部署路径作废 |
| `ARCHIVE_WEB_DEPLOYMENT_GITHUB_AND_GITEE_PAGES.md` | 双 Pages 部署围绕已删除产物构建 |

> ⚠️ **archive/ 中的文档仅供追溯参考，内容可能已严重过时，且不再维护。**
> 英文文档（`README_EN.md` / `BUILD_EN.md` / `VITRO_CLI_EN.md` / `QUICKSTART_EN.md` 等）已于 2026-09-11 删除，
> 仓库中仅保留 [`AGENTS_EN.md`](../AGENTS_EN.md)；翻译工作后续再议。
