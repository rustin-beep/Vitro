///| 调用形态单一路由表（勘察 §5.5「三实现合一」）。
///
/// **要解决的问题**：现版同一函数最多三条实现路径（VM opcode 内联 / Rust host /
/// Bytecode Libc），而路由分叉**不可见**——`vitro_codegen/src/lib.rs:136-143` 把
/// 88 个 Bytecode Libc 名预注册进 `func_index`（只跳过 `strcpy`/`strcat`），调用点
/// 先查 `func_index` 命中即发 `Call <固定索引>`，未命中才查 `by_user_name` 发
/// `CallHost`。结果：**110 个 host handler 里有 20 个在"用户按名调用"路径上被
/// 静默遮蔽**（两者各写一张表，无一处能列出这 20 个名字）。同族分裂也由此而来
/// （`atoi` 走 Bytecode 而 `atof/atol` 走 Host；`memcpy` 走 Bytecode 而 `memset` 走 Host）。
///
/// **本表把隐式覆盖变成显式声明**：`call_route(name)` 对每个名字给出**唯一**形态，
/// 派生规则只有一条 + 一个显式例外集，`shadowed_host_names()` 把那 20 个名字
/// 列成可断言清单。
///
/// **落点裁定（与总计划 L7 行字面表述相左，已登记）**：总计划写"host(110 路由表
/// 单源)"，但 §4 的硬约束"依赖严格单向"禁止 codegen(L6) → host(L7)，而 codegen
/// 在**编译期**就必须回答"发 `Call <固定索引>` 还是 `CallHost <id>`"——路由表是
/// L6 的必需品。又因派生需要 `bytecode_libc_all_funcs`（88 名单源在 L6），
/// libc(L5) 也无法反向 import L6。⇒ 定义点落 **bytecode（L6）**，与固定索引同层
/// 同域（"调用形态由产物层决定"）；codegen 与 host 各自向 L6 消费。

///|
/// 一个名字的调用形态。
pub(all) enum CallRoute {
  /// 走 `Call <固定索引>`——Bytecode Libc 预编译产物（`libc_index.mbt` 的 88 名）。
  BytecodeLibc(Int)
  /// 走 `CallHost <id>`——host handler（`host_func_id_gen.mbt` 的 110 名）。
  Host(Int)
} derive(Debug, Eq)

///|
/// host 名表规模（Rust `host_func_id.rs`：110 常量 / 110 名映射，**含别名**——
/// `print_int`/`__vitro_output` 同指 OUTPUT、`labs` 同指 ABS）。
pub const HOST_FUNC_NAME_COUNT : Int = 110

///|
/// 被固定索引段遮蔽的 host 名数（= 两表交集 22 − 改判集 2）。
///
/// 这 20 个名字**有 host handler 但按名调用到不了**（`func_index` 先命中）：
/// `isdigit isalpha islower isupper tolower toupper isspace isalnum isprint
/// iscntrl isxdigit abs atoi srand rand strlen strcmp strncpy memcpy memmove`。
pub const SHADOWED_HOST_NAME_COUNT : Int = 20

///|
/// 从固定索引段**改判回 Host** 的显式例外集。
///
/// 唯一两条，理由在 Rust 侧有明文：Host 版 `strcpy`/`strcat` 带 **E3070 栈缓冲区
/// 校验**（`vitro_codegen/src/lib.rs:136-143` 只跳过这两个名字的预注册）。
/// 本函数是该例外的**单点定义**（2026-09-23 审阅批 P3 接线后真正收口）：
/// codegen 的消费点是 `with_mode` 预注册跳过（`gen.mbt` 调本函数），新增例外
/// 只改这里——预注册自动跳过、`call.mbt` 的 func_index 判定自动落 CallHost、
/// `shadowed_host_names()` 清单与锚随之变红逼登记。
pub fn is_host_rerouted(name : String) -> Bool {
  name == "strcpy" || name == "strcat"
}

///|
/// 原始 host 表查询（**全表**，不做 PURE 短路）。
///
/// 与 `host_func_id_by_user_name` 的区别是刻意的：后者照搬 Rust `by_user_name`
/// 语义，对 14 个 PURE 名**短路返回 None**，因此**不能**用来回答"这个名字在不在
/// host 表里"——路由派生要的正是原始成员关系。
fn host_id_raw(name : String) -> Int? {
  for pair in host_func_pairs {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  None
}

///|
/// 该名字是否登记在 host 表（含 PURE 名与别名）。
pub fn is_host_func_name(name : String) -> Bool {
  host_id_raw(name) is Some(_)
}

///|
/// 名字 → 调用形态；`None` 表示**不是内置**（即用户函数，走直接调用）。
///
/// 派生规则（全表唯一）：
/// 1. 在 Bytecode Libc 88 名表内：
///    - 命中改判集（`strcpy`/`strcat`）→ `Host`；
///    - 否则 → `BytecodeLibc(固定索引)`；
/// 2. 不在 88 名表内但在 host 110 名表内 → `Host(id)`；
/// 3. 两表都不在 → `None`。
pub fn call_route(name : String) -> CallRoute? {
  match bytecode_libc_index(name) {
    Some(idx) =>
      if is_host_rerouted(name) {
        match host_id_raw(name) {
          Some(h) => Some(CallRoute::Host(h))
          None => None
        }
      } else {
        Some(CallRoute::BytecodeLibc(idx))
      }
    None =>
      match host_id_raw(name) {
        Some(h) => Some(CallRoute::Host(h))
        None => None
      }
  }
}

///|
/// 被固定索引段遮蔽的 host 名清单（升序，序 = 88 名表序）。
///
/// **显式登记的意义**：这 20 个 handler 是"写了但按名调用到不了"的死面——现版
/// 无一处能列出它们。声明成本清单后，"遮蔽面扩大/缩小"变成可断言的事实。
pub fn shadowed_host_names() -> Array[String] {
  let out : Array[String] = []
  for name in bytecode_libc_all_funcs {
    if is_host_func_name(name) && !is_host_rerouted(name) {
      out.push(name)
    }
  }
  out
}

///|
/// 两表名并集（去重后升序）：即"按名可达的内置函数全集"。`None` 路由的补集。
///
/// 与 `vitro/engine/libc` 的放行名全集（175）差一个 `print_int`——后者是
/// `by_user_name` 里的别名而非 libc 放行名（`libc.mbt` 有明文）。该关系由
/// 黑盒锚 `bytecode_test.mbt` 逐名对账。
pub fn builtin_name_union() -> Array[String] {
  let out : Array[String] = []
  for name in bytecode_libc_all_funcs {
    out.push(name)
  }
  for pair in host_func_pairs {
    if !out.contains(pair.0) {
      out.push(pair.0)
    }
  }
  out
}
