///| L7 执行层·VM 域：**教学观测面**（S8 批一号三段-a，2026-10-01）——
/// 照搬 Rust `crates/vitro_vm/src/core/{state,memory}.rs` 的观测方法族
/// （get_current_line/get_call_stack/take_vis_events/get_variable_snapshot/
/// find_variable_name_at_addr/get_array_snapshots）——time_travel collector
/// （批一号三段-b）的 VM 调用面，StepPayload 十四字段的引擎侧数据源。
///
/// **与 Rust 的实现差登记（2026-10-01）**：
/// - Rust 侧观测裸读 `self.memory[...]`（前置地址检查后直接索引）；MoonBit
///   载体 `bytes` priv（memory 包白箱纪律），本侧走受检 `load_*`——Err
///   （freed 堆窗口等）防御跳过该符号。活作用域变量的地址经前置过滤
///   （NULL 区/上界）后 Err 概率≈0；Rust 裸读 freed 区展示陈旧值的形态
///   在此路径不可达（残值展示走 pointer_snapshots，批三段-b）。
/// - `get_call_stack` 不暴露整表句柄（MoonBit struct 引用语义——陷阱
///   #30：返回内部 Array = 暴露可写句柄），改 `call_stack_len` +
///   `call_stack_at` 索引读口；Rust `&[CallFrame]` 借用天然只读，本侧
///   以窄口等价。
///
/// 依赖件登记：type_display_name/base_element_type 上提 ast（本批触发，
/// gateway 私有 → ast pub）；format_fixed pub 化（host，{:.2} 语义单源）。

///|
/// 变量快照（Rust vitro_runtime::VariableSnapshotData 照搬）——ty 保持
/// ast 形态（文本化在消费方 collector：L9 可 import ast+protocol）。
pub(all) struct VariableSnapshotData {
  name : String
  addr : UInt
  is_local : Bool
  ty : @ast.Type
  /// 位模式值（Rust `u64 as i64`：Double 按位重解释，其余按 i32 符号扩展）。
  value : Int64
} derive(Debug)

///|
pub extend VariableSnapshotData with Debug::{to_repr}

///|
/// 数组元素快照（Rust vitro_runtime::ArraySnapshotData 照搬）。
pub(all) struct ArraySnapshotData {
  name : String
  /// 元素类型显示名（type_display_name(base_element_type(ty))——与
  /// local_vars 的 ty 渲染同一来源，防两处手写映射漂移）。
  element_ty : String
  /// 元素值文本（Char 可打印 `'c'` 形态 / 数值 to_string / Float·Double
  /// 定点两位 {:.2}——host format_fixed half-even 同语义）。
  elements : Array[String]
  /// U2#10：超出 256 截断标记（payload 级可见，消费方不得当全量）。
  truncated : Bool
}

///|
/// 数组快照元素上限（Rust MAX_ARRAY_SNAPSHOT_ELEMENTS = 256——`int
/// a[50000]` × 2000 帧窗口 5~20GB 形态的截断锚，协议字段级标记）。
const MAX_ARRAY_SNAPSHOT_ELEMENTS : Int = 256

///|
/// 当前执行行（state.rs:566 照搬——读口）。
pub fn VitroVM::get_current_line(self : VitroVM) -> Int {
  self.current_line
}

///|
/// 调用栈深度（观测窄口之一）。
pub fn VitroVM::call_stack_len(self : VitroVM) -> Int {
  self.call_stack.length()
}

///|
/// 调用栈按层读（观测窄口之二——0 = 最外层，len-1 = 当前帧）。
pub fn VitroVM::call_stack_at(self : VitroVM, idx : Int) -> CallFrame {
  self.call_stack[idx]
}

///|
/// 取走队列中累积的可视化事件（state.rs:352 std::mem::take 同义——取出
/// 即清空，消费方幂等）。
pub fn VitroVM::take_vis_events(self : VitroVM) -> Array[VisEventData] {
  let out = self.vis_event_queue
  self.vis_event_queue = []
  out
}

///|
/// 当前帧可见变量的快照（memory.rs:268-336 照搬）。
///
/// 作用域过滤与择优规则（逐条照搬）：
/// - 函数归属：局部符号 func_name ≠ 当前函数 → 跳过（全局符号恒入）；
/// - 无有效执行位置（预热步 current_line ≤ 0）：**保守不输出局部变量**
/// （同名变量退化为"取声明最晚者"会误导消费方）；
/// - 声明行晚于当前行（decl_line > current_line）→ 未进作用域，跳过；
/// - 局部地址 = 帧 locals_base + sym.addr；全局 = GLOBAL_START + addr；
/// - 越界（vaddr+4/8 > MEM_SIZE 或 < NULL_TRAP_SIZE）跳过；
/// - 同名择优：**声明行更晚者胜**（shadow 规则），等行后者覆盖。
pub fn VitroVM::get_variable_snapshot(
  self : VitroVM,
) -> Array[VariableSnapshotData] {
  let frame : CallFrame? = if self.call_stack.length() > 0 {
    Some(self.call_stack[self.call_stack.length() - 1])
  } else {
    None
  }
  let current_func = match frame {
    Some(f) => f.func_name
    None => ""
  }
  let current_line = self.get_current_line()
  let result : Array[VariableSnapshotData] = []
  // 名字 → (已选条目声明行, result 下标)
  let chosen : Map[String, (Int, Int)] = Map([])
  for sym in self.symbols {
    if sym.func_name != "" && sym.func_name != current_func {
      continue
    }
    if sym.is_local && current_line <= 0 {
      continue
    }
    if sym.decl_line > 0 && current_line > 0 && sym.decl_line > current_line {
      continue
    }
    let vaddr : UInt = if sym.is_local {
      match frame {
        Some(f) => f.locals_base + sym.addr
        None => continue
      }
    } else {
      @bytecode.GLOBAL_START + sym.addr
    }
    if vaddr + 4U > @bytecode.MEM_SIZE || vaddr < @bytecode.NULL_TRAP_SIZE {
      continue
    }
    // Double 宽读（8 字节）；其余 4 字节 i32 符号扩展（Rust `as i64`）
    let val : Int64 = if sym.ty.kind() is TK_Double {
      if vaddr + 8U > @bytecode.MEM_SIZE {
        continue
      }
      match self.memory.load_u64(self.mem_map, vaddr) {
        Ok(bits) => bits.reinterpret_as_int64()
        Err(_) => continue // 受检读防御跳过（见模块头注实现差登记）
      }
    } else {
      match self.memory.load_u32(self.mem_map, vaddr) {
        Ok(bits) => bits.reinterpret_as_int().to_int64()
        Err(_) => continue
      }
    }
    let snap : VariableSnapshotData = {
      name: sym.name,
      addr: vaddr,
      is_local: sym.is_local,
      ty: sym.ty,
      value: val,
    }
    match chosen.get(sym.name) {
      Some((prev_line, idx)) =>
        if sym.decl_line >= prev_line {
          result[idx] = snap
          chosen.set(sym.name, (sym.decl_line, idx))
        }
      None => {
        chosen.set(sym.name, (sym.decl_line, result.length()))
        result.push(snap)
      }
    }
  }
  result
}

///|
/// 跨帧解析：addr 归属的变量名（memory.rs:351-379 照搬——指针快照
/// target_name 源：`swap(int*, int*)` 体内取调用者 `x` 的名字，当前帧
/// 符号表里没有，需扩到全局 + 全部活跃帧，由内向外"最近定义优先"）。
///
/// 可见性判定与 get_variable_snapshot 同源；命中 = 地址等于变量起始，
/// 或落在数组的元素区间内（&arr[2] 归属 arr——slot_covers）；其他复合
/// 类型无布局信息只精确匹配（schema §2.5 已知限制）。
pub fn VitroVM::find_variable_name_at_addr(
  self : VitroVM,
  addr : UInt,
) -> String? {
  // 全局先行（Rust 同序）
  for sym in self.symbols {
    if sym.is_local {
      continue
    }
    if slot_covers(sym, @bytecode.GLOBAL_START + sym.addr, addr) {
      return Some(sym.name)
    }
  }
  // 活跃帧由内向外
  let n = self.call_stack.length()
  let mut idx = n - 1
  while idx >= 0 {
    let frame = self.call_stack[idx]
    // 帧的"当前执行行"：顶层帧取 current_line，其余取被调帧记录的
    // caller_line（call_stack[i+1].caller_line 正是帧 i 的当前行）
    let frame_line = if idx + 1 < n {
      self.call_stack[idx + 1].caller_line
    } else {
      self.current_line
    }
    for sym in self.symbols {
      if !sym.is_local || sym.func_name != frame.func_name {
        continue
      }
      if sym.decl_line > 0 && frame_line > 0 && sym.decl_line > frame_line {
        continue
      }
      if slot_covers(sym, frame.locals_base + sym.addr, addr) {
        return Some(sym.name)
      }
    }
    idx = idx - 1
  }
  None
}

///|
/// 变量槽 base 是否覆盖 addr（memory.rs:479-497 slot_covers 照搬）：
/// 精确命中恒真；数组类型额外接受元素区间（开区间 base < addr <
/// base + count×elem_size）；元素宽度按 `base_kind` 判定（审阅 P1 修复
/// 2026-10-01：原误用 `sym.ty.kind()`——数组自身恒落默认臂 4，double/char
/// 数组区间归属双向出错；oracle memory.rs:490 用 `base_kind`，与
/// get_array_snapshots 取值口径同源——char 1 / double·long long 8 / 其余 4）。
fn slot_covers(sym : @bytecode.Symbol, base : UInt, addr : UInt) -> Bool {
  if base == addr {
    return true
  }
  if !(sym.ty.kind() is TK_Array) {
    return false
  }
  let count = sym.ty.array_size()
  if count <= 0 {
    return false
  }
  let elem_size : UInt = match sym.ty.base_kind() {
    TK_Char => 1U
    TK_Double | TK_LongLong => 8U
    _ => 4U
  }
  addr > base && addr < base + count.reinterpret_as_uint() * elem_size
}

///|
/// 全部数组变量的元素快照（memory.rs:379-463 照搬——算法可视化条形图
/// 数据源）。逐元素文本化（Char 可打印形态 / Int·LongLong 位模式 /
/// Float·Double 定点两位 {:.2}）；256 截断置 truncated。
pub fn VitroVM::get_array_snapshots(self : VitroVM) -> Array[ArraySnapshotData] {
  let result : Array[ArraySnapshotData] = []
  let frame : CallFrame? = if self.call_stack.length() > 0 {
    Some(self.call_stack[self.call_stack.length() - 1])
  } else {
    None
  }
  for sym in self.symbols {
    if !(sym.ty.kind() is TK_Array) {
      continue
    }
    let vaddr : UInt = if sym.is_local {
      match frame {
        Some(f) => f.locals_base + sym.addr
        None => continue
      }
    } else {
      @bytecode.GLOBAL_START + sym.addr
    }
    let array_size = sym.ty.array_size()
    if array_size <= 0 {
      continue
    }
    // 审阅 P2 修复（2026-10-01）：宽度与取值按 `base_kind`（先解一层指针、
    // 数组递归剥层——oracle memory.rs:398 同源）；element_ty 显示名仍走
    // `base_element_type`（只剥数组不解指针，oracle 显示层同款）。原误用
    // base_element_type 兼任语义宽度：int*[2] 落 "?"、char*[2] 步长 4。
    let bk = sym.ty.base_kind()
    let elem_size : UInt = match bk {
      TK_Char => 1U
      TK_Int | TK_Pointer | TK_Float => 4U
      TK_Double | TK_LongLong => 8U
      _ => 4U
    }
    // U2#10：声明长度超 256 → 截断 + 标记
    let truncated = array_size > MAX_ARRAY_SNAPSHOT_ELEMENTS
    let take_elems = if array_size > MAX_ARRAY_SNAPSHOT_ELEMENTS {
      MAX_ARRAY_SNAPSHOT_ELEMENTS
    } else {
      array_size
    }
    let elements : Array[String] = []
    for i = 0; i < take_elems; i = i + 1 {
      let addr = vaddr + i.reinterpret_as_uint() * elem_size
      // NULL 区检查；上界在后续读的 Err 防御兜底（Rust break 同位）
      if addr < @bytecode.NULL_TRAP_SIZE {
        break
      }
      match bk {
        TK_Char => {
          let b = match self.memory.load_i8(self.mem_map, addr) {
            Ok(v) => v
            Err(_) => break
          }
          if b >= 32 && b <= 126 {
            // 可打印：'c' 形态（b 已是码点；unsafe_to_char——域内已判）
            elements.push("'\{b.unsafe_to_char()}'")
          } else {
            elements.push("\{b}")
          }
        }
        TK_Int => {
          let v = match self.memory.load_u32(self.mem_map, addr) {
            Ok(bits) => bits.reinterpret_as_int()
            Err(_) => break
          }
          elements.push("\{v}")
        }
        TK_Float => {
          let v = match self.memory.load_u32(self.mem_map, addr) {
            Ok(bits) => Float::reinterpret_from_uint(bits)
            Err(_) => break
          }
          elements.push(@host.format_fixed(v.to_double(), 2))
        }
        TK_Double => {
          let v = match self.memory.load_u64(self.mem_map, addr) {
            Ok(bits) => bits.reinterpret_as_double()
            Err(_) => break
          }
          elements.push(@host.format_fixed(v, 2))
        }
        TK_LongLong => {
          let v = match self.memory.load_u64(self.mem_map, addr) {
            Ok(bits) => bits.reinterpret_as_int64()
            Err(_) => break
          }
          elements.push("\{v}")
        }
        _ => elements.push("?")
      }
    }
    result.push({
      name: sym.name,
      element_ty: @ast.type_display_name(@ast.base_element_type(sym.ty)),
      elements,
      truncated,
    })
  }
  result
}

///|
/// 最近访问变量条数（观测窄口——last_accessed_vars 每步重置、不随快照）。
pub fn VitroVM::accessed_len(self : VitroVM) -> Int {
  self.last_accessed_vars.length()
}

///|
/// 最近访问变量按序读（Rust get_last_accessed_vars → collector 消费面）。
pub fn VitroVM::accessed_at(self : VitroVM, idx : Int) -> VariableAccess {
  self.last_accessed_vars[idx]
}

///|
/// 执行热力图读口（窄口——`heatmap` 是可变 Map，字段直读会泄漏可写句柄，
/// call_stack_at 同款纪律）。行未命中返回 0（Rust `unwrap_or(0)` 同口径）。
pub fn VitroVM::heatmap_count_at(self : VitroVM, line : Int) -> UInt64 {
  match self.heatmap.get(line) {
    Some(v) => v
    None => 0UL
  }
}

///|
/// 清空断点集合（Rust vm.clear_breakpoints——serve breakpoints.set 先清后设）。
pub fn VitroVM::clear_breakpoints(self : VitroVM) -> Unit {
  self.breakpoints.clear()
}

///|
/// 加断点行号（Rust vm.add_breakpoint；非正行号由调用方过滤——serve 层口径）。
pub fn VitroVM::add_breakpoint(self : VitroVM, line : Int) -> Unit {
  self.breakpoints.add(line)
}

///|
/// 生效断点行号（升序读回——breakpoints.set 回显的真源；病 7 修复配套，
/// #47 2026-10-09：回显须与实际生效集一致——过滤/去重后的 Set 视图，
/// 而非请求原始数组）。
pub fn VitroVM::breakpoints_sorted(self : VitroVM) -> Array[Int] {
  let arr : Array[Int] = []
  for l in self.breakpoints {
    arr.push(l)
  }
  arr.sort()
  arr
}

///|
/// 恢复推进（Rust vm.resume——清空断点即恢复的 serve 出口语义；命名同
/// engine 侧 unpause 先例避免保留字）。
pub fn VitroVM::unpause(self : VitroVM) -> Unit {
  self.paused = false
}
