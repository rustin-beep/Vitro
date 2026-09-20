///|
/// CompileOutput → dump JSON emitter（S5，A 级产物对拍面）。
///
/// 与 Rust `vitro_cli dump-compile` 的 `CompileDump`（serde derive，14 键）
/// 逐字段同构——显式 emitter 纪律（B 级锚）：键名/字段序/元组数组形态/
/// Type externally-tagged（经 `@ast.type_json` 单源）/浮点文本化（经
/// `@ast.double_to_json_text` 单源）/字符串转义（经 `@ast.json_escape_string`
/// 单源）在此对齐；两侧产物各过 Go canonicalize 后 diff。
///
/// 确定性（F6 / 勘察 §⑤-5）：`func_table`/`func_index`/`struct_defs`/
/// `union_defs` 的 Map 键序 unspecified——emit 前按键升序排序（本 emitter
/// 产物天然 canonical，不依赖 canonicalizer 补排序；Rust 侧 HashMap 键序
/// 随机，仍须 canonicalize 归一）。

///|
/// 字典序比较（负/零/正）。**禁用 `String::compare` / `<` `>`**——MoonBit
/// 内置 String 比较实测非字典序（`"delta" > "charlie"` 为 false，疑似
/// 长度优先；2026-09-20 bytecode 白盒实测），与 Go canonicalize 的键排序
/// （sort.Strings，字节字典序）不一致。本函数按 UTF-16 码元逐位比较 +
/// 短者小——键域为 C 标识符（ASCII），与 UTF-8 字节字典序在此域等价。
fn str_cmp(a : String, b : String) -> Int {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<n {
    let x = a[i].to_int()
    let y = b[i].to_int()
    if x != y {
      return if x < y { -1 } else { 1 }
    }
  }
  if a.length() == b.length() {
    0
  } else if a.length() < b.length() {
    -1
  } else {
    1
  }
}

///|
/// 键升序排序（插入排序——Map 规模为函数/结构体数十级，无需快排；
/// 字典序见 `str_cmp`）。
fn[V] sorted_keys(m : Map[String, V]) -> Array[String] {
  let keys : Array[String] = []
  m.each((k, _) => keys.push(k))
  let mut i = 1
  while i < keys.length() {
    let k = keys[i]
    let mut j = i - 1
    while j >= 0 && str_cmp(keys[j], k) > 0 {
      keys[j + 1] = keys[j]
      j -= 1
    }
    keys[j + 1] = k
    i += 1
  }
  keys
}

///|
fn emit_loc(loc : @source.SourceLoc, buf : StringBuilder) -> Unit {
  buf.write_string(
    "{\"line\":\{loc.line},\"column\":\{loc.column},\"file_id\":\{loc.file_id}}",
  )
}

///|
fn emit_instruction(ins : @opcode.Instruction, buf : StringBuilder) -> Unit {
  buf.write_string("{\"op\":")
  buf.write_string(@ast.json_escape_string(ins.op.name()))
  buf.write_string(",\"operand\":\{ins.operand},\"loc\":")
  emit_loc(ins.loc, buf)
  buf.write_string("}")
}

///|
fn emit_local_buffer(b : LocalBuffer, buf : StringBuilder) -> Unit {
  buf.write_string(
    "{\"offset\":\{b.offset},\"size\":\{b.size},\"name\":\{@ast.json_escape_string(b.name)}}",
  )
}

///|
fn emit_func_meta(m : FuncMeta, buf : StringBuilder) -> Unit {
  buf.write_string(
    "{\"ip\":\{m.ip},\"arg_count\":\{m.arg_count},\"param_count\":\{m.param_count},\"local_count\":\{m.local_count},\"param_sizes\":[",
  )
  for i, s in m.param_sizes {
    if i > 0 {
      buf.write_string(",")
    }
    buf.write_string("\{s}")
  }
  buf.write_string("],\"return_type\":")
  buf.write_string(@ast.type_json(m.return_type))
  buf.write_string(",\"is_variadic\":")
  buf.write_string(if m.is_variadic { "true" } else { "false" })
  buf.write_string(",\"local_buffers\":[")
  for i, b in m.local_buffers {
    if i > 0 {
      buf.write_string(",")
    }
    emit_local_buffer(b, buf)
  }
  buf.write_string("]}")
}

///|
fn emit_symbol(s : Symbol, buf : StringBuilder) -> Unit {
  buf.write_string(
    "{\"name\":\{@ast.json_escape_string(s.name)},\"addr\":\{s.addr},\"is_local\":",
  )
  buf.write_string(if s.is_local { "true" } else { "false" })
  buf.write_string(",\"ty\":")
  buf.write_string(@ast.type_json(s.ty))
  buf.write_string(
    ",\"scope_depth\":\{s.scope_depth},\"func_name\":\{@ast.json_escape_string(s.func_name)},\"decl_line\":\{s.decl_line}}",
  )
}

///|
fn emit_struct_field(f : @ast.StructField, buf : StringBuilder) -> Unit {
  buf.write_string("{\"ty\":")
  buf.write_string(@ast.type_json(f.ty))
  buf.write_string(",\"name\":\{@ast.json_escape_string(f.name)}}")
}

///|
fn emit_struct_defs(
  defs : Map[String, Array[@ast.StructField]],
  buf : StringBuilder,
) -> Unit {
  buf.write_string("{")
  let keys = sorted_keys(defs)
  for i, k in keys {
    if i > 0 {
      buf.write_string(",")
    }
    buf.write_string(@ast.json_escape_string(k))
    buf.write_string(":[")
    let fields = defs.get(k).unwrap()
    for j, f in fields {
      if j > 0 {
        buf.write_string(",")
      }
      emit_struct_field(f, buf)
    }
    buf.write_string("]")
  }
  buf.write_string("}")
}

///|
/// CompileOutput 13 字段全量 dump（version=1 前缀键与 Rust CompileDump
/// 同序）。pretty-print 由 canonicalize 統一，本 emitter 输出紧凑形态。
pub fn compile_output_dump_json(o : CompileOutput) -> String {
  let buf = StringBuilder()
  buf.write_string("{\"version\":1,\"code\":[")
  for i, ins in o.code {
    if i > 0 {
      buf.write_string(",")
    }
    emit_instruction(ins, buf)
  }
  buf.write_string("],\"globals_init_32\":[")
  for i, pair in o.globals_init_32 {
    if i > 0 {
      buf.write_string(",")
    }
    buf.write_string("[\{pair.0},\{pair.1}]")
  }
  buf.write_string("],\"globals_init_64\":[")
  for i, pair in o.globals_init_64 {
    if i > 0 {
      buf.write_string(",")
    }
    buf.write_string("[\{pair.0},\{pair.1.to_string()}]")
  }
  buf.write_string("],\"func_table\":{")
  let ft_keys = sorted_keys(o.func_table)
  for i, k in ft_keys {
    if i > 0 {
      buf.write_string(",")
    }
    buf.write_string(@ast.json_escape_string(k))
    buf.write_string(":")
    emit_func_meta(o.func_table.get(k).unwrap(), buf)
  }
  buf.write_string("},\"func_index\":{")
  let fi_keys = sorted_keys(o.func_index)
  for i, k in fi_keys {
    if i > 0 {
      buf.write_string(",")
    }
    buf.write_string(@ast.json_escape_string(k))
    buf.write_string(":\{o.func_index.get(k).unwrap()}")
  }
  buf.write_string("},\"string_data\":[")
  for i, pair in o.string_data {
    if i > 0 {
      buf.write_string(",")
    }
    buf.write_string("[\{pair.0},\{@ast.json_escape_string(pair.1)}]")
  }
  buf.write_string("],\"source_map\":[")
  for i, pair in o.source_map {
    if i > 0 {
      buf.write_string(",")
    }
    buf.write_string("[\{pair.0},")
    emit_loc(pair.1, buf)
    buf.write_string("]")
  }
  buf.write_string("],\"symbols\":[")
  for i, s in o.symbols {
    if i > 0 {
      buf.write_string(",")
    }
    emit_symbol(s, buf)
  }
  buf.write_string("],\"struct_defs\":")
  emit_struct_defs(o.struct_defs, buf)
  buf.write_string(",\"union_defs\":")
  emit_struct_defs(o.union_defs, buf)
  buf.write_string(",\"f64_constants\":[")
  for i, v in o.f64_constants {
    if i > 0 {
      buf.write_string(",")
    }
    buf.write_string(@ast.double_to_json_text(v))
  }
  buf.write_string("],\"i64_constants\":[")
  for i, v in o.i64_constants {
    if i > 0 {
      buf.write_string(",")
    }
    buf.write_string("\{v.to_string()}")
  }
  buf.write_string("],\"global_data_end\":\{o.global_data_end}}")
  buf.to_string()
}
