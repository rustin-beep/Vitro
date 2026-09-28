// 会话骨架（S7 批二号，2026-09-27）：Session 状态聚合 + 会话级保险丝
// 单一写入口 + 多文件安全的源码行定位。
// 照搬 native/src/session.rs 的 Session/CompileState/source_line_at/
// set_max_steps/set_call_depth_limit；形态差异（MoonBit 侧设计红利）：
// ① vm 非 Option——Rust 的 `vm: Option<VitroVM>` + get_or_insert 语义
// 本质是「确保有 VM」，MoonBit 直接持有（构造即建，配置永有所宿）；
// ② CompileState 聚合 @bytecode.CompileOutput 而非散装复制 17 产物字段；
// ③ 统一模式（unified）帧缓冲族字段照搬，引擎本体（UnifiedEngine）
// 属 S8 时间旅行片，此处仅承载 serve step.next 的发布缓冲状态。

///|
/// 编译单元（多文件会话的源文件——Rust CompileUnit 的会话侧形态）。
pub(all) struct CompileUnit {
  filename : String
  source : String
} derive(Debug)

///|
/// 多文件会话的全局行号 → 文件映射条目（merge_compile_units 产出；
/// P0-4：合并编译后字节码行号是全局行号，单文件管线为空——此时全局
/// 行号即文件内行号）。
pub(all) struct FileRange {
  filename : String
  start_line : Int
  end_line : Int
} derive(Debug)

///|
/// 编译状态（Rust CompileState 的聚合重构形态）：编译产物整体持
/// CompileOutput，会话侧只附加产物之外的状态（诊断/算法匹配/多文件
/// 映射/预处理追踪/错误串）。
pub(all) struct CompileState {
  /// 错误串（编译失败原因——serve compile 出口消费）。
  mut errors : String
  /// 编译单元（源文件集）。
  mut compile_units : Array[CompileUnit]
  /// 是否已成功编译。
  mut compiled : Bool
  /// 编译产物（13 字段整体——code/func_table/string_data/source_map/
  /// symbols/常量池/globals_init/global_data_end 等；未编译为 None）。
  mut output : @bytecode.CompileOutput?
  /// 编译诊断（协议形态——含修复建议字段族）。
  mut diagnostics : Array[Diagnostic]
  /// 算法匹配（语义标注批产出；S8 analysis 消费）。
  mut algorithm_matches : Array[AlgorithmMatch]
  /// 结构体字段元数据（`名 → [(字段名, 偏移)]`——变量快照的 ty 渲染用）。
  mut struct_fields : Map[String, Array[(String, Int)]]
  /// 多文件会话的全局行号映射（空 = 单文件）。
  mut file_ranges : Array[FileRange]
  /// E2 白箱教学层：预处理追踪（宏展开链 + `#if` 分支原因，容量封顶）。
  mut preprocessor_trace : Array[String]
} derive(Debug)

///|
/// 会话（编译 + 执行 + 统一模式状态聚合）。
pub(all) struct Session {
  /// 会话级配置（**单一真相源**——serve config.get/set 的对象）。
  mut config : SessionConfig
  /// 编译状态。
  mut compile : CompileState
  /// VM（**非 Option**——设计红利：配置永有所宿，消 get_or_insert 形态；
  /// compile → run 由 serve 批接线 reset+装载，reset 保留会话级配置）。
  vm : @vm.VitroVM
  /// 统一模式一帧发布缓冲（U1#1 P0-1：流式协议下「行末帧」判定需要
  /// 未来信息，当前帧暂存、下一帧到来时回改后再发布——serve 批消费）。
  mut unified_pending : @protocol.StepPayload?
  /// U1#1 管道批：上一帧 code_line（行变化时把上一行末帧的变量存入
  /// row_entry_vars——「展示运算过程」取语句执行前操作数）。
  mut unified_last_line : Int
  /// 行入口变量快照的维护状态（S8 时间旅行片深水区，字段先行照搬）。
  mut unified_last_frame_vars : Array[@protocol.ApiVariableSnapshot]
  mut unified_row_entry_vars : Array[@protocol.ApiVariableSnapshot]
  /// 运行态参数域的最小承载（Rust `session.runtime` 的 argv/input_mode 两角；
  /// stdin 行本体在 `vm.input`——vm reset 不清，跨 run 存活同 Rust
  /// reset_runtime 不碰输入的口径）。argv 跨 run 存活：run 帧未带 argv
  /// 参数时沿用上次值（Rust serve run 语义）。
  mut runtime_argv : Array[String]
  /// 输入模式跨 run 存活（Rust `InputMode` 默认 **Interactive**——
  /// `#[default]` 取首变体，serve 出口 waiting_input 语义的前提；
  /// MoonBit `vm` 构造默认 batch=true 是 `vm` 包形态，serve 层以此
  /// 字段为准在 run 时重建 `InputState`）。
  mut runtime_batch : Bool
} //（Debug 不派生：VitroVM 无 Debug impl；会话调试走字段级访问）

///|
/// 构造（全默认：config=默认 / vm=new / 空编译态）。
pub fn Session::new() -> Session {
  {
    config: SessionConfig::default(),
    compile: CompileState::new(),
    vm: @vm.VitroVM::new(),
    unified_pending: None,
    unified_last_line: 0,
    unified_last_frame_vars: [],
    unified_row_entry_vars: [],
    runtime_argv: [],
    runtime_batch: false,
  }
}

///|
/// 编译状态构造（空态）。
pub fn CompileState::new() -> CompileState {
  {
    errors: "",
    compile_units: [],
    compiled: false,
    output: None,
    diagnostics: [],
    algorithm_matches: [],
    struct_fields: Map([]),
    file_ranges: [],
    preprocessor_trace: [],
  }
}

///|
/// 步数保险丝（会话级，单一写入口）：写 config 后**立即**应用到 VM——
/// 与 VM 是否已装载解耦（Rust 事故：编译前设置被静默丢弃，见
/// session_config_test.rs 头注；本侧 vm 非 Option，配置永有所宿）。
/// 下限 1（Rust `max.max(1)` 同）。
pub fn Session::set_max_steps(self : Session, max : Int) -> Unit {
  self.config.max_steps = if max < 1 { 1 } else { max }
  self.config.apply_to_vm(self.vm)
}

///|
/// 调用深度保险丝（会话级，单一写入口）——同 set_max_steps。
pub fn Session::set_call_depth_limit(self : Session, limit : Int) -> Unit {
  self.config.call_depth_limit = limit
  self.config.apply_to_vm(self.vm)
}

///|
/// 按全局行号取源码行（P0-4 多文件安全——Rust source_line_at 照搬）：
/// file_ranges 命中区间 → 定位对应编译单元取行；单文件（file_ranges
/// 空）保持「全局行号 == 文件内行号」原语义。越界/非正数返回 None。
pub fn Session::source_line_at(self : Session, global_line : Int) -> String? {
  if global_line <= 0 {
    return None
  }
  match self.find_file_range(global_line) {
    Some(range) => {
      let in_file = global_line - range.start_line
      let unit = self.find_unit(range.filename)
      match unit {
        Some(u) => nth_line(u.source, in_file)
        None => None
      }
    }
    None =>
      // 单文件会话：file_ranges 空 → 首单元按 1 基行号取
      if self.compile.file_ranges.is_empty() &&
        self.compile.compile_units.length() > 0 {
        nth_line(self.compile.compile_units[0].source, global_line - 1)
      } else {
        None
      }
  }
}

///|
fn Session::find_file_range(self : Session, line : Int) -> FileRange? {
  for r in self.compile.file_ranges {
    if line >= r.start_line && line <= r.end_line {
      return Some(r)
    }
  }
  None
}

///|
fn Session::find_unit(self : Session, filename : String) -> CompileUnit? {
  for u in self.compile.compile_units {
    if u.filename == filename {
      return Some(u)
    }
  }
  None
}

///|
/// 取源码串第 n 行（0 基；越界 None）。Rust `lines()` 语义：尾随 `\n`
/// 不产生额外空行（split 会多出末空段——源以 `\n` 结尾且非空时弹掉；
/// 中间空行合法保留）。
fn nth_line(source : String, n : Int) -> String? {
  if n < 0 {
    return None
  }
  // Rust lines() 语义：空串 = 零行（"".lines().nth(0) = None——split
  // 形态会得 [""] 一行空串，审阅⑦字节级取证分叉点）
  if source.is_empty() {
    return None
  }
  let lines : Array[String] = []
  for line in source.split("\n") {
    lines.push(line.to_string())
  }
  if lines.length() > 1 && lines[lines.length() - 1] == "" {
    ignore(lines.pop())
  }
  if n >= lines.length() {
    return None
  }
  Some(lines[n])
}
