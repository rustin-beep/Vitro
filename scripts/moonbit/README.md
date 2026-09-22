# 开发工具目录

本目录是仓库开发工具（从 Rust oracle 源生成 diag 码表），默认入参指向仓库内 ../native/...——**包消费者无需也不应运行**；生成物（diag/*_gen.mbt）已随包分发并带源 sha256 落款。

## S2 新增工具（2026-09-19）

- `gen_stubs/`（Go）：从 `native/runtime_libc/include/*.h`（14 存根）生成 `lexer/internal/host/stubs_gen.mbt`——sha 落款 + `--check` 幂等门禁；包消费者无需运行（生成物随包分发）。
- `gen_corpus.mbtx`（MoonBit 脚本）**已移至 module 外** `scripts/lexer_diff/gen_corpus.mbtx`（2026-09-19 审阅 P1-2：moon publish 打包整个 module 且不读 .gitignore——脚本在 module 内运行会产生 `scripts/_build/` 构建产物并被打进发布包，0.2.0 曾混入 176KB）；用法 `moon run scripts/lexer_diff/gen_corpus.mbtx -- <out_dir> <count> [seed]`（仓库根运行）。

## S5 收尾批新增工具（2026-09-22）

- `libc_single_source/`（Go）：**libc 三名单单源对账闸**——校验
  `libc.builtin_all == host 路由名 ∪ bytecode 索引名 − excluded`，并核对交集
  计数与 PURE 子集（**空集不得绿**）。规则外置 `rules.json`（改锚点/期望值
  只改 JSON），`--selftest` 为 J9 证红入口。用法（**仓库根**）：
  `go run ./scripts/moonbit/libc_single_source -check`；CI 已接线。
  背景：三表此前零对账，已致 `libc.mbt` 包注释出现事实错误（称 Rust
  `host_func_id` 无 `print_int`，实测有别名臂）。
- `pkg_deps/`（Go）：**包依赖方向断言**——按外置分层表（`rules.json`，源 =
  总计划 §4 的 L0–L9 包图）断言每个模块内依赖指向低层或同层，并 DFS 查环；
  **新包未登记分层即红**，解析出 0 包 / 0 依赖亦红（空集不得绿）。`cmd/*`
  为工具层豁免方向检查（仍参与环检测）。用法（**仓库根**）：
  `go run ./scripts/moonbit/pkg_deps -check`；CI 已接线。
  背景：总计划 §4「依赖严格单向无环」此前**零 CI 校验**——越层/成环可静默
  进来。J9 证红：注入 `opcode(L0)→bytecode(L6)` 同时触发越层与成环两条判据。
- `libc_boot_diff/`（Go）：**libc 自举对拍闸**（S5 尾项）——命题是「MoonBit 引擎
  能否编译自己的标准库 C 源，且产物与 Rust oracle 逐字节一致」。两侧形态不同
  （Rust `export` 11 键 / MoonBit `dump_compile` 14 键），故按 Rust export 的
  「stub main → wrapper 截断 → 删 main」口径过滤 MoonBit 产物后，投影到 9 个
  交集字段比对（含 code 段逐指令）。用法（**仓库根**，需先 `cargo build
  --release --bin vitro_cli`）：`go run ./scripts/moonbit/libc_boot_diff`；
  CI 已接线；J9 证红（注入 `code[1].operand +1` 必红）。
  **注入口径坑**：stub 必须直接接在主源末尾换行之后（不前插空行）——Rust 多
  unit 拼接等价 `src1 + src2`，前插空行会让 stub 区 `loc.line` 差 1（实测踩过，
  非引擎差异）。
- `single_source/`（Go）：**单一真相源清单校验器**（架构审阅 v2 A 组 #7 / 判据
  C-04）。项目 L1 判据「同一概念多真相来源」只覆盖**仓内同语言重复**，不覆盖
  **跨语言孪生**（迁移期每个单源在 MoonBit 侧都有孪生，同步义务纯人工）。
  两类条目：`enforced`（全仓扫 def_pattern，定义点**文件集**必须 == `allowed_def_files`
  ——多一份实现即红、少一份即单源缺失红）、`registered`（单源是生成物或另有
  专用闸门，本闸校验两侧路径存在并登记检测锚点）。清单见 `rules.json`（8 条，
  含 `compute_type_size` / opcode 表 / 错误码表 / catalog / host 路由 / bytecode
  libc 索引 / libc 放行集 / slot 策略版本）。用法（**仓库根**）：
  `go run ./scripts/moonbit/single_source -check`；CI 已接线；`--selftest` J9 证红。
  **支持 `exclude_line_pattern`**：排掉含 `self` 的**方法**定义行——实测撞出的
  案例：`vitro_typeck/src/context.rs` 有个与单源**同名**的方法
  `pub fn compute_type_size(&self, ty)`（语义上是委托，但同名会造成"看起来有
  两份实现"的误读，已作为命名债登记在 rules.json 的 `_exclude_note`）。
- `mbti_sync/`（Go）：**接口面同步闸**——断言 `moonbit/**/pkg.generated.mbti`
  与 `.mbt` 实现一致。moon info 无 `--check` 子命令（实测 moon 0.1.20260920），
  故取**跑前后快照 sha256 不变量**形态：快照 → 跑 `moon info` → 再快照 → 比对，
  不等即红并列出全部变化文件（新增 / 消失 / 内容脱节三类）。0 个 `.mbti` 亦红。
  背景：一致性此前纯靠人工跑 moon info，本仓已漏过一次（`libc/pkg.generated.mbti`
  缺 `type LibcSig`，下一轮才补登）。用法（**仓库根**）：
  `go run ./scripts/moonbit/mbti_sync -check`；CI 已接线；`--selftest` J9 证红
  （注入脱节内容必红）+ 真实场景已验（改 `.mbt` 的 pub 面不跑 moon info 必红）。
  **自愈特性**：闸判红时会顺手把 `.mbti` 同步到当前实现——本地红完直接提交即可；
  再跑即绿。与 `moonbit_surface` 的分工：本闸判「接口面是否跟上实现」，
  surface 判「接口面是否该收窄」，互补不可互替。

> **调用约定（2026-09-22 勘误）**：本目录下所有脚本均须**从仓库根**调用
> （`./scripts/moonbit/<name>`）——`moonbit/` 下既无 `go.mod` 也无 `scripts/`；
> `moonbit_surface.go` 等内部自带 `os.Chdir("moonbit")`。`moonbit/AGENTS.md`
> 的旧写法（`cd moonbit && go run ./scripts/<name>`）已同批修正。
