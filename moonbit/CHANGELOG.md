# Changelog

自 0.6.0 起本 module 的对外面变更携带兼容义务（mooncakes checksum 不可覆盖，
修复只能递增版本；弃用须给出迁移路径与移除版本）。版本语义：修复已发布内容 →
patch；新增包 / 公共 API → minor。

## [Unreleased]（0.7.0 开发期）

### Fixed

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
