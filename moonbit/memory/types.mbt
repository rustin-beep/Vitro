///| S6 执行层·内存域的数据类型（Rust `vitro_runtime::memory_state` +
/// `vitro_vm::core::state` 的结构面照搬）。
///
/// **可见性纪律**：本文件只放"跨包要看见的数据壳"。逻辑一律在 `memory_map.mbt`
/// / `freed_logs.mbt` / `carrier.mbt`，且**内部字段保持 priv**（`pub struct`
/// 不带 `(all)`）——勘察 §9.2 约束 #1「`vitro_host` 不得直接访问字节载体」
/// 与坑 6「索引与 regions 失配」都靠"没有可绕过的写入口"实现，而不是靠纪律。
/// 需要构造记录的场景（host 建堆区域条目）走 `MemoryRegionData::heap_block`。

///|
/// 访问方向。检查链本身与方向无关；方向决定 NULL 陷阱文案的动词与
/// UAF 文案的"写入/读取"，故必须随故障一起上报（文案在 vm 侧渲染）。
pub(all) enum AccessKind {
  Read
  Write
} derive(Debug, Eq)

///|
/// 空闲内存块（`free_list` 元素；来源：隔离区 FIFO 驱逐归还，或首块分配）。
///
/// `addr` 与 `size` 都可变：`take_from_free_list` 的 first-fit 切分把块
/// 起点前移并缩小余量（Rust `memory_state.rs:280-286`）。
pub(all) struct FreeBlock {
  mut addr : UInt
  mut size : Int
} derive(Debug, Eq)

///|
/// 已释放块登记（UAF / Double-Free 检测窗口条目）。
///
/// - `addr` 是 `FreedLogs` 的**键**（严格升序、条目间互不重叠），故非 mut；
///   起点变化（部分重叠裁剪的后缀段）走"删旧插新 / 原地改键"，不改本字段。
/// - `size` 可被精确裁剪缩小 → mut。
/// - 四个"行号 / 步号"字段喂教学时间轴（`alloc → free → 继续访问`），
///   照搬 Rust `FreedRegionInfo`（`state.rs:22-32`）。
pub(all) struct FreedRegionInfo {
  addr : UInt
  mut size : Int
  alloc_line : Int
  freed_line : Int
  alloc_step : Int
  freed_step : Int
} derive(Debug, Eq)

///|
/// 受检访问失败的结构化事实。
///
/// **文案不在本包生成**：三条 trap 文案都要 VM 状态——UAF 要 `freed_step`
/// 与当前步数（"时间轴：分配 → 释放（第 N 步）→ 继续访问（第 M 步）"），
/// 上界要扫符号表找最近的数组名（Rust `core/trap.rs:6-61`）。勘察 §5.3
/// 对执行器给的同款建议是"执行器只发结构化事件，文案生成移出"——内存层
/// 同理：本包只发"哪一个判定失败、失败在哪"，`vm` 负责渲染。
///
/// **本枚举刻意不含的两类失败**：Double-Free（E3061）与无效 free（E3027）
/// 不是「访问」失败，而是 host 释放路径的判定结果——它们的输入是
/// `MemoryMap.freed_logs` 的精确命中与 `MemoryMap` 的区间查询，由 host 组合
/// 后自行渲染（Rust `host/memory.rs:60-137`）。
pub(all) enum MemFault {
  /// NULL 陷阱区（`addr < NULL_TRAP_SIZE`）。
  NullDeref(UInt, AccessKind)
  /// 上界：`addr + size` 越过 `MEM_SIZE`。
  OutOfBounds(UInt, UInt)
  /// Use-After-Free：命中 freed_logs 区间。
  UseAfterFree(FreedRegionInfo, AccessKind)
} derive(Debug, Eq)

///|
/// 堆区域条目（三段式内存地图的堆段）。
///
/// **`addr` 不在本结构里**——它是 `MemoryMap.regions` 的**键**，地址的
/// 唯一真相源。Rust 现版同时存两份冗余：`regions: Vec<MemoryRegionData>`
/// 的 `addr` 字段 + `region_index: HashMap<u32, usize>`（`#[serde(skip)]`，
/// 恢复时漏调 `rebuild_region_index()` 即全线失配，坑 6 点名的等价风险）。
/// 勘察 §⑤ 6 的建议是"取消索引字段，改为从 regions 派生的视图"；本实现把
/// **地址也交给键**，于是"同 addr 两条目""索引与 regions 失配"两族缺陷在
/// 类型层面不可表达。
///
/// `kind` 本清单恒为 `"heap"`（栈/全局区域由导出层从符号表与调用帧合成，
/// 不写回本清单——否则 `total_allocated` 会把栈帧算成已分配堆内存，
/// Rust `memory_state.rs:66-70` 有明文）。保留该字段是为了不擅自改 L8
/// 导出（`memory_regions`）的线格式与旧快照的向后兼容口径。
pub(all) struct MemoryRegionData {
  mut size : Int
  mut name : String
  mut ty : String
  is_heap : Bool
  mut is_freed : Bool
  mut alloc_line : Int
  mut alloc_by : String
  mut kind : String
} derive(Debug)

///|
/// 构造一条堆区域条目（host 分配路径的唯一构造点）。
///
/// `name` / `ty` 的取值口径照搬 Rust：`malloc`/`calloc` 的新块取
/// `heap_{alloc_counter}` 与 `"int"`，`realloc` 的新块两者皆空串
/// （`host/memory.rs:44-54` vs `:296-306`）。
pub fn MemoryRegionData::heap_block(
  size : Int,
  name : String,
  ty : String,
  alloc_line : Int,
  alloc_by : String,
) -> MemoryRegionData {
  MemoryRegionData::{
    size,
    name,
    ty,
    is_heap: true,
    is_freed: false,
    alloc_line,
    alloc_by,
    kind: "heap",
  }
}

///|
/// 堆统计（教学侧口径照搬 Rust `HeapStatsData`，`memory_state.rs:102-115`）。
pub(all) struct HeapStatsData {
  /// 本次运行的堆起点（R1 动态堆起点；原为常量 `HEAP_START`）。
  heap_base : Int
  /// 总堆空间（`heap_offset - heap_base`），字节。
  total_heap : Int
  /// 已分配且未释放的堆内存，字节。
  allocated : Int
  /// 外部碎片（`free_list` 中所有块之和），字节。
  fragmented : Int
  /// 碎片率（0~100）。
  fragmentation_rate : Int
} derive(Debug, Eq)
