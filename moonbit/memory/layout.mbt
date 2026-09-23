///| S6 执行层·内存域（`vitro/engine/memory`）——**常量视图与归属声明**。
///
/// **常量归属（单源，禁止双写）**：
/// - 地址布局常量（`MEM_SIZE` / `NULL_TRAP_SIZE` / `GLOBAL_START` /
///   `HEAP_START` / `GLOBAL_REGION_LIMIT` / `STACK_START` / `ALIGN4_MASK` /
///   `align4` / `argv_region_footprint` / `compute_heap_base`）的**定义点在
///   `vitro/engine/bytecode`**（L6，S5 已落并有对账锚）。本包一律写
///   `@bytecode.` 前缀引用，不复制第二份——R1 ② 当初收掉的就是"codegen 与 VM
///   各一套全局区判据魔数"这一病灶，本包再抄一份等于把它请回来。
/// - 本包自有：**页几何**与**隔离预算**——载体与堆状态机专属，bytecode
///   （编译期布局口径）不该知道它们。
///
/// 本文件是 package 内唯一的"常量面板"：读代码先看这里，避免在实现里翻找魔数。

///|
/// 页定位移位量。`PAGE_SIZE` 是 2 的幂 ⇒ **页号用移位而非除法**
/// （勘察 §5.1：wasm-gc 无硬件除法指令；Rust 现版是 `addr as usize / PAGE_SIZE`）。
pub const PAGE_SHIFT : Int = 12

///|
/// 载体页尺寸（字节）= 4096。Rust `snapshot.rs:46` `PAGE_SIZE`。
pub const PAGE_SIZE : Int = 1 << PAGE_SHIFT

///|
/// 页数（1MB / 4KB = 256）。Rust `snapshot.rs:47` `PAGE_COUNT`。
pub const PAGE_COUNT : Int = 256

///|
/// 脏页位图字数（256 页 / 64 位 = 4）。Rust `state.rs:128` `dirty_pages: [u64; 4]`。
pub const DIRTY_WORD_COUNT : Int = 4

///|
/// 隔离区默认字节预算：堆上限的 1/4 = 256KB。
///
/// 依据 [`堆有界隔离决议`] §1：采用 ASAN 原版的**有界隔离**——隔离窗口保证
/// UAF / Double-Free 必被检出，超预算时 FIFO 驱逐最老块复用，保证合法 churn
/// （分配-释放循环）不误伤；只分配不释放的 leak 块根本不进隔离区，由 bump
/// 持续推进直至撞 1MB 墙（教学信号）。预算可按会话调整，**不是**编译期常量语义。
///
/// [`堆有界隔离决议`]: ../../docs/current/06-出口与协议/堆有界隔离决议.md
pub const DEFAULT_QUARANTINE_BUDGET : Int = 1024 * 1024 / 4
