// S7 批三号三段：serve memory.regions——内存地图三段式（C2）导出 +
// 堆统计。照搬源：native/src/session_api.rs::memory_regions +
// global_region_entries/stack_region_entries（合成口径的注释一并照搬：
// 栈/全局不写回 mem_map.regions——该清单是堆统计单源，混入栈帧会让
// "已分配堆内存"把栈算进去；全局/栈区域只在导出层合成）。
//
// `type_display_name`（Rust vitro_runtime/type_utils.rs 照搬——Type 的
// 人类可读全形态渲染，含 const/unsigned/指针星号/数组维度/函数签名）：
// serve 私有实现——首个引擎侧消费者出现时上提 ast 包（变量快照的 ty
// 渲染是 S8 analysis 批的既定消费点）；ast 的 Type::name 是去修饰基础
// 名（符号表口径），形态不同不互替。

///|
/// const 前缀（Rust cst 同形）。
fn cst_prefix(is_const : Bool) -> String {
  if is_const {
    "const "
  } else {
    ""
  }
}

///|
/// Type 的显示名（Rust type_display_name 逐变体照搬）。
fn type_display_name(ty : @ast.Type) -> String {
  match ty {
    Void(is_const) => "\{cst_prefix(is_const)}void"
    Int(is_unsigned, is_const) => {
      let n = if is_unsigned { "unsigned int" } else { "int" }
      "\{cst_prefix(is_const)}\{n}"
    }
    Char(is_unsigned, is_const) => {
      let n = if is_unsigned { "unsigned char" } else { "char" }
      "\{cst_prefix(is_const)}\{n}"
    }
    Float(is_const) => "\{cst_prefix(is_const)}float"
    Double(is_const) => "\{cst_prefix(is_const)}double"
    LongLong(is_unsigned, is_const) => {
      let n = if is_unsigned { "unsigned long long" } else { "long long" }
      "\{cst_prefix(is_const)}\{n}"
    }
    Pointer(pointee, is_const) =>
      if is_const {
        "\{type_display_name(pointee)}* const"
      } else {
        "\{type_display_name(pointee)}*"
      }
    Array(element, array_size, dims, _, is_vla, _) => {
      let base = type_display_name(element)
      let mut all_pos = !dims.is_empty()
      for d in dims {
        if d <= 0 {
          all_pos = false
        }
      }
      if all_pos {
        let buf = StringBuilder()
        buf.write_string(base)
        for d in dims {
          buf.write_string("[\{d}]")
        }
        buf.to_string()
      } else if is_vla || array_size <= 0 {
        "\{base}[]"
      } else {
        "\{base}[\{array_size}]"
      }
    }
    Function(return_type, param_types, is_variadic, _) => {
      let buf = StringBuilder()
      buf.write_string(type_display_name(return_type))
      buf.write_string(" (*)(")
      let mut first = true
      for p in param_types {
        if !first {
          buf.write_string(", ")
        }
        buf.write_string(type_display_name(p))
        first = false
      }
      if is_variadic {
        if !first {
          buf.write_string(", ")
        }
        buf.write_string("...")
      }
      buf.write_string(")")
      buf.to_string()
    }
    Struct(name, is_const) => "\{cst_prefix(is_const)}struct \{name}"
    Union(name, is_const) => "\{cst_prefix(is_const)}union \{name}"
    Class(name, is_const) => "\{cst_prefix(is_const)}\{name}"
    Reference(base, is_const) =>
      "\{cst_prefix(is_const)}\{type_display_name(base)}&"
    RValueRef(base) => "\{type_display_name(base)}&&"
    Auto => "auto"
    // C 子集不可达（names/typeck 的 C 路径零产出）；渲染取基础名——
    // Rust 侧 {:?} Debug 形态在 MoonBit 无同源单点，登记形状差异
    TemplateId(base, _, is_const) => "\{cst_prefix(is_const)}\{base}"
    Typeof(_, is_const, _) => "\{cst_prefix(is_const)}typeof(...)"
  }
}

///|
/// 区域条目 emitter（Rust MemoryRegionData 的 serde 字段序照搬）。
fn region_json(
  addr : UInt,
  size : Int,
  name : String,
  ty : String,
  is_heap : Bool,
  is_freed : Bool,
  alloc_line : Int,
  alloc_by : String,
  kind : String,
) -> Json {
  let m : Map[String, Json] = Map([])
  m.set("addr", addr.to_json())
  m.set("size", size.to_json())
  m.set("name", Json::string(name))
  m.set("ty", Json::string(ty))
  m.set("is_heap", is_heap.to_json())
  m.set("is_freed", is_freed.to_json())
  m.set("alloc_line", alloc_line.to_json())
  m.set("alloc_by", Json::string(alloc_by))
  m.set("kind", Json::string(kind))
  Json::object(m)
}

///|
/// 全局/静态区域的导出条目（C2）：从 VM 符号表合成，kind == "global"。
/// `size` 口径：优先取符号表槽位跨度（下一全局符号偏移 − 本符号偏移，
/// 与 codegen 实际分配一致含填充）；末位符号退化为 compute_type_size
/// （空布局表 = 只算标量与数组——struct/union 返 0 再退化 1 字节）。
/// `alloc_line` 取声明行。
fn global_region_entries(s : @session.Session) -> Array[(UInt, Json)] {
  // 全局符号（is_local == false）按 addr 升序
  let globals : Array[@bytecode.Symbol] = []
  for sym in s.vm.symbols {
    if !sym.is_local {
      globals.push(sym)
    }
  }
  globals.sort_by(fn(a, b) { a.addr.compare(b.addr) })
  let empty_structs : Map[String, Array[@ast.StructField]] = Map([])
  let empty_unions : Map[String, Array[@ast.StructField]] = Map([])
  let empty_class : Map[String, Int] = Map([])
  let out : Array[(UInt, Json)] = []
  for i, sym in globals {
    let addr = @bytecode.GLOBAL_START + sym.addr
    let size = if i + 1 < globals.length() {
      // 槽位跨度（下一全局符号偏移 − 本符号偏移；非正退化为类型尺寸）
      let next_addr = globals[i + 1].addr
      if next_addr > sym.addr {
        (next_addr - sym.addr).to_int()
      } else {
        global_size_fallback(sym, empty_structs, empty_unions, empty_class)
      }
    } else {
      global_size_fallback(sym, empty_structs, empty_unions, empty_class)
    }
    out.push(
      (
        addr,
        region_json(
          addr,
          size,
          sym.name,
          type_display_name(sym.ty),
          false,
          false,
          sym.decl_line,
          "static",
          "global",
        ),
      ),
    )
  }
  out
}

///|
/// 末位/无后继全局符号的尺寸退化（compute_type_size 空 表口径；
/// 0 → 1 最小字节——Rust 同形）。
fn global_size_fallback(
  sym : @bytecode.Symbol,
  structs : Map[String, Array[@ast.StructField]],
  unions : Map[String, Array[@ast.StructField]],
  class_sizes : Map[String, Int],
) -> Int {
  let n = @ast.compute_type_size(sym.ty, structs, unions, class_sizes)
  if n == 0 {
    1
  } else {
    n
  }
}

///|
/// 栈帧区域的导出条目（C2）：从活跃调用帧合成，kind == "stack"。
/// `name` = 函数名；`alloc_line` = 进入该帧的调用行（caller_line；
/// main 的帧为 0——它不是被调用出来的）；`size` = 帧跨度
/// （original_stack_top − locals_base，与 VM 的 mem_stack_top 同源）。
fn stack_region_entries(s : @session.Session) -> Array[(UInt, Json)] {
  let out : Array[(UInt, Json)] = []
  for f in s.vm.call_stack {
    let size = if f.original_stack_top > f.locals_base {
      (f.original_stack_top - f.locals_base).to_int()
    } else {
      0
    }
    out.push(
      (
        f.locals_base,
        region_json(
          f.locals_base,
          size,
          f.func_name,
          "frame",
          false,
          false,
          f.caller_line,
          "call",
          "stack",
        ),
      ),
    )
  }
  out
}

///|
/// memory.regions 方法帧（Rust memory_regions 照搬）：三段式区域 +
/// 分段计数 + free_list + quarantine 三件 + 堆统计四件；地址升序
/// （全局 → 堆 → 栈自高地址向下）。
fn serve_memory_regions_frame(
  s : @session.Session,
  id : Json,
) -> (String, Bool) {
  let entries : Array[(UInt, Json)] = []
  let heap_count = s.vm.mem_map.regions_len()
  for pair in s.vm.mem_map.regions_to_array() {
    let (addr, r) = pair
    entries.push(
      (
        addr,
        region_json(
          addr,
          r.size,
          r.name,
          r.ty,
          r.is_heap,
          r.is_freed,
          r.alloc_line,
          r.alloc_by,
          r.kind,
        ),
      ),
    )
  }
  let globals = global_region_entries(s)
  let global_count = globals.length()
  for e in globals {
    entries.push(e)
  }
  let stacks = stack_region_entries(s)
  let stack_count = stacks.length()
  for e in stacks {
    entries.push(e)
  }
  entries.sort_by(fn(a, b) { a.0.compare(b.0) })
  let regions : Array[Json] = []
  for e in entries {
    regions.push(e.1)
  }
  let free_list : Array[Json] = []
  for i = 0; i < s.vm.mem_map.free_list_len(); i = i + 1 {
    let b = s.vm.mem_map.free_list_at(i)
    let m : Map[String, Json] = Map([])
    m.set("addr", b.addr.to_json())
    m.set("size", b.size.to_json())
    free_list.push(Json::object(m))
  }
  let counts : Map[String, Json] = Map([])
  counts.set("global", global_count.to_json())
  counts.set("stack", stack_count.to_json())
  counts.set("heap", heap_count.to_json())
  let quarantine : Map[String, Json] = Map([])
  quarantine.set("bytes", s.vm.mem_map.quarantine_bytes().to_json())
  quarantine.set("budget", s.vm.mem_map.quarantine_budget().to_json())
  quarantine.set("blocks", s.vm.mem_map.quarantine_len().to_json())
  let m : Map[String, Json] = Map([])
  m.set("regions", Json::array(regions))
  m.set("region_counts", Json::object(counts))
  m.set("free_list", Json::array(free_list))
  m.set("quarantine", Json::object(quarantine))
  m.set("heap_base", s.vm.mem_map.heap_base().to_json())
  m.set("heap_offset", s.vm.mem_map.heap_offset().to_json())
  m.set("alloc_counter", s.vm.mem_map.alloc_counter().to_json())
  (serve_ok(id, Json::object(m)).stringify(), false)
}
