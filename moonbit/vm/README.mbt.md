# vitro/engine/vm

C 教学引擎的执行器状态机与快照体系（S6 批一号：状态定形；executor 穷尽
match 随批二号）。

## 职责

- **`VitroVM` 执行器状态机**：值栈（u64 位模式）/ 调用栈 / 1MB 线性内存
  （经 `vitro/engine/memory` 受检单入口）/ 堆元数据 / 教学观测（断点、热力图、
  可视化事件）/ 宿主域三态（输出、输入、VFS——经 `vitro/engine/host`）。
- **快照体系**：`VMSnapshot` = 执行状态的全量真相（`snapshot`/`restore` 两端
  单点，字段增删由 struct 字面量构造的编译错强制同步）；`MemoryImage`
  Full/Delta 二分（Delta 是检查点层存储形态，随门 3 集成批接线）。
- **C# 异常三执行状态**（CS 批硬前置，v1 设计输入非事后补丁）：handler 栈、
  当前异常寄存器、UNWINDING 状态机（含展开中间态三件，一等进快照——时间
  旅行免费安全）；对应 opcode `TryBegin`=44 / `TryEnd`=45 / `Throw`=46 已进
  `vitro/engine/opcode` 历史空号（C 前端零发射）。
- **ARC 帧退出清理机制占位**（region `refcount` 在 `vitro/engine/memory`
  v1 入形；retain/release host id 与发射侧随 CS 批）。

## 新设计裁剪（相对 Rust oracle 的 36 字段 vm）

砍：JIT 全族（F-3）、`global_count`（恒 0 死字段）、C++ `new[]` 构造守卫、
`dirty_pages`/`freed_logs`（并入 memory 包）、`trace`（死路径）、
`local_sym_map`/`global_sym_map` 常驻索引（改装载期派生索引，结构性消除
每次 Call/Ret 全量重建的热点）。宿主回调哨兵 `usize::MAX` 换
`CallFrame.return_ip : Int?`。

## 快照纪律

- 编译期产物（code / func_table / symbols / 常量池 / 派生索引 / arc_cleanup /
  vis_event_lines）**不入快照**——Session 重建；
- 会话级配置（max_steps / call_depth_limit / deterministic）**不入快照、
  reset 保留**——「先设上限再运行」不变量；
- 拷贝即快照：snapshot 与 restore 两侧各深拷一次，快照持有者与运行态
  互不渗透。

## 最小示例

```mbt nocheck
let vm = @vm.VitroVM::new()
vm.set_max_steps(2000) // 会话配置：reset 保留
let snap = vm.snapshot()
vm.reset()
vm.restore(snap)
```
