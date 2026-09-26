///| L7 执行层·VM 域：**Bytecode Libc 装载器 + setup 组装**（批四号——
/// 照搬 Rust `bytecode_libc_loader.rs` + `compile_pipeline.rs::setup_vm`
/// 的 12 步协议）。
///
/// 数据源 = `libc_data_gen.mbt`（`scripts/moonbit/gen_libc_data` 从 Rust
/// `include_str!` 的同一份 JSON 派生——**单一真相源不变**，生成器带
/// sha 落款 + `-check` 幂等闸；MoonBit 侧不走 @json：551KB 字符串字面量
/// 与 moon fmt 互踩，且 wasm 后端无文件系统）。
///
/// **运行时校验照搬**：Rust 侧 `version`/`source_digest` 运行时不比对
/// （§0-2：结构体无字段、serde 静默忽略）——MoonBit 侧同口径不校验；
/// 加载后**无条件把 libc 指令的 loc.file_id 置 1**（把 libc 排除出用户
/// 覆盖率——Rust `loader.rs:49-51` 同款）。

///|
/// 装载后的 libc 产物（code 已组装 + file_id 置 1 + func 注册表）。
pub(all) struct LibcArtifact {
  code : Array[@opcode.Instruction]
  /// name → (固定索引, meta)
  funcs : Array[(String, Int, @bytecode.FuncMeta)]
  globals_32 : Array[(UInt, Int)]
  globals_64 : Array[(UInt, UInt64)]
  f64_constants : Array[Double]
  i64_constants : Array[Int64]
}

///|
/// 组装 libc 产物（扁平数据 → Instruction/FuncMeta）。
pub fn load_libc_artifact() -> LibcArtifact {
  let code : Array[@opcode.Instruction] = []
  let n = libc_code_flat.length() / 5
  for i = 0; i < n; i = i + 1 {
    let b = i * 5
    let op = match @opcode.OpCode::from_u8(libc_code_flat[b]) {
      Some(o) => o
      None =>
        abort(
          "libc_data_gen: 非法 opcode \{libc_code_flat[b]}（生成器与 opcode 表漂移）",
        )
    }
    // file_id 置 1（覆盖率排除——照搬 loader.rs:49-51）
    code.push(
      @opcode.Instruction::new(
        op,
        libc_code_flat[b + 1],
        @source.SourceLoc::with_file(
          libc_code_flat[b + 2],
          libc_code_flat[b + 3],
          1, // file_id 置 1（覆盖率排除）
        ),
      ),
    )
  }
  // func meta 组装（扁平 6 元头 + param_sizes 尾随；游标随 ps_count 前进）
  let funcs : Array[(String, Int, @bytecode.FuncMeta)] = []
  let mut mi = 0
  for fi = 0; fi < libc_func_names.length(); fi = fi + 1 {
    let name = libc_func_names[fi]
    let idx = libc_func_index[fi]
    let ip = libc_func_meta[mi]
    let arg_count = libc_func_meta[mi + 1]
    let param_count = libc_func_meta[mi + 2]
    let local_count = libc_func_meta[mi + 3]
    let variadic = libc_func_meta[mi + 4] == 1
    let ps_count = libc_func_meta[mi + 5]
    let param_sizes : Array[Int] = []
    for k = 0; k < ps_count; k = k + 1 {
      param_sizes.push(libc_func_meta[mi + 6 + k])
    }
    mi = mi + 6 + ps_count
    funcs.push(
      (
        name,
        idx,
        @bytecode.FuncMeta::{
          ip,
          arg_count,
          param_count,
          local_count,
          param_sizes,
          return_type: @ast.Type::Void(false),
          is_variadic: variadic,
          local_buffers: [],
        },
      ),
    )
  }
  // 完整性断言：游标恰走完 meta 表
  if mi != libc_func_meta.length() {
    abort(
      "libc_data_gen: func meta 游标失配（\{mi} != \{libc_func_meta.length()}）——生成器漂移",
    )
  }
  LibcArtifact::{
    code,
    funcs,
    globals_32: libc_globals_32,
    globals_64: libc_globals_64,
    f64_constants: libc_f64_constants,
    i64_constants: libc_i64_constants,
  }
}

///|
/// setup 组装（12 步照搬 `compile_pipeline.rs:243-372`）：
/// reset → 装载 libc → 用户 Jump 重定位（operand += libc_code_len）→
/// 合并 code → 注册 libc 函数（固定索引）→ 注册用户函数（IP 偏移）→
/// globals 初始化（libc 先、用户后——同地址后写覆盖）→ 常量池合并 →
/// max_steps **不设**（会话配置）→ 符号表 → vis 行 → 字符串写入 →
/// 入口 ip = libc_code_len → argv。
///
/// `output` = 用户编译产物（CompileOutput）；`argv`/`argc` 命令行参数。
pub fn VitroVM::setup_from_output(
  self : VitroVM,
  output : @bytecode.CompileOutput,
  argc : Int,
  argv : Array[String],
) -> Unit {
  self.reset()
  // ── 1. 装载 libc ──
  let libc = load_libc_artifact()
  let libc_code_len = libc.code.length()
  // ── 2. 用户 Jump 重定位 ──
  let user_code : Array[@opcode.Instruction] = []
  for instr in output.code {
    match instr.op {
      Jump | JumpIfZero | JumpIfNotZero => {
        let rel = @opcode.Instruction::new(
          instr.op,
          instr.operand + libc_code_len,
          @source.SourceLoc::with_file(
            instr.loc.line,
            instr.loc.column,
            instr.loc.file_id,
          ),
        )
        user_code.push(rel)
      }
      _ => user_code.push(instr)
    }
  }
  // ── 3. 合并 code ──
  let full : Array[@opcode.Instruction] = []
  for i in libc.code {
    full.push(i)
  }
  for i in user_code {
    full.push(i)
  }
  self.load_program(full)
  // ── 4. 注册 libc 函数（固定索引；超上限静默跳过——编译器侧防御口径）──
  for entry in libc.funcs {
    let _ = self.register_function(entry.1, entry.2)
    let _ = self.register_function_name(entry.1, entry.0)
  }
  // ── 5. 注册用户函数（IP 偏移 libc_code_len）──
  let ft_names : Array[String] = []
  for k in output.func_table.keys() {
    ft_names.push(k)
  }
  ft_names.sort_by(fn(a, b) { a.compare(b) })
  for name in ft_names {
    guard output.func_index.get(name) is Some(idx) else { continue }
    guard output.func_table.get(name) is Some(m) else { continue }
    let _ = self.register_function(idx, @bytecode.FuncMeta::{
      ip: m.ip + libc_code_len,
      arg_count: m.arg_count,
      param_count: m.param_count,
      local_count: m.local_count,
      param_sizes: m.param_sizes,
      return_type: m.return_type,
      is_variadic: m.is_variadic,
      local_buffers: m.local_buffers,
    })
    let _ = self.register_function_name(idx, name)
  }
  // ── 6. globals（libc 先、用户后）──
  self.set_globals_32(libc.globals_32)
  self.set_globals_64(libc.globals_64)
  self.set_globals_32(output.globals_init_32)
  self.set_globals_64(output.globals_init_64)
  // ── 7. 常量池合并 ──
  let f64s : Array[Double] = []
  for c in libc.f64_constants {
    f64s.push(c)
  }
  for c in output.f64_constants {
    f64s.push(c)
  }
  self.set_f64_constants(f64s)
  let i64s : Array[Int64] = []
  for c in libc.i64_constants {
    i64s.push(c)
  }
  for c in output.i64_constants {
    i64s.push(c)
  }
  self.set_i64_constants(i64s)
  // （max_steps 不设——会话配置由调用方 set_max_steps）
  // ── 8. 符号表 ──
  self.set_symbols(output.symbols)
  // ── 9. vis 行（algorithm_matches 的投影——CompileOutput 无此字段时空）──
  // ── 10. 字符串数据 ──
  for pair in output.string_data {
    self.write_cstring(pair.0, pair.1)
  }
  // ── 11. 入口 = libc_code_len ──
  self.ip = libc_code_len
  // ── 12. argv ──
  self.setup_argv(argc, argv, output.global_data_end)
}

///|
/// 1MB 内存映像导出（**cmd 层特权通道**——D 级三联 diff 第三通道；
/// 只读 dump 不写——受检面不受影响。Bytes 输出便于 @fs 直接落盘）。
pub fn VitroVM::dump_memory_raw(self : VitroVM) -> Bytes {
  let raw = self.memory.clone_raw()
  Bytes::from_fixedarray(raw)
}
