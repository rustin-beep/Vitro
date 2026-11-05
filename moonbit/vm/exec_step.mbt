// 蓝本注记：文内 Rust 源引用（`*.rs` 路径/行号/符号）均为档案态蓝本——tag rust-oracle-freeze（2026-10-05 删区），现为本仓自主基线。

///| L7 执行层·VM 域·executor：**step 循环 + 单层穷尽分发**。
///
/// **新设计要点（相对 Rust `executor/mod.rs`）**：
/// - **JIT 全砍**（F-3）——`run` 无 fast path、step 无热点计数/录制；
/// - **无 `VmContext`**——Rust 侧 `RuntimeState` 由 Session 持有并随步传入
///   （借用检查器形式产物）；MoonBit 宿主域三态（输出/输入/VFS/rand）内聚
///   在 `VitroVM`，step 无参；
/// - **单层穷尽 match**（勘察 §5.3：Rust 两级分发〔外层族 match + 族内
///   二次 match，族函数必带 `_ => {}` 兜底〕合并为一级 135 臂——MoonBit
///   穷尽检查使 opcode 增删直接编译红，兜底臂消失）；
/// - 错误协议照搬：族函数写 `error` 字段，dispatch 尾判非空转 `Trap`
///   （首错优先）。
///
/// 段二已接线：F/D/Q 三族 + 控制流族（Call/CallPtr/CallVar/Ret 的完整
/// 调用协议 + do_call 四重栈溢出防护）。fail loud 剩余面：CallHost 的
/// host 分发（批三号——110 路由 host 侧已就绪）与 C# 异常三件（CS 批）。

///|
/// 执行单条指令（Rust `step`，`executor/mod.rs:255-355` 砍 JIT 段）。
pub fn VitroVM::step(self : VitroVM) -> StepResult {
  if self.finished {
    return Finished
  }
  if !self.error.is_empty() {
    return Trap
  }
  if self.ip >= self.code.length() {
    return Finished
  }
  self.step_count = self.step_count + 1
  // #314（2026-10-26）：超限判定必须先于快照刷新——max_steps 为
  // SNAPSHOT_INTERVAL 整数倍时（默认 10^7 必中），同一步「先刷新后
  // 比较」会把快照刷成当前值 ⇒ stale/changed 分组恒全 stale（i 每步
  // 自增也判「没有变化」，与 [cause] 指引自相矛盾）。trap 出口不刷新：
  // 刷了也不会被消费；非倍数形态比较基线不变（仍是最近一次刷新）。
  if self.step_count >= self.max_steps {
    let msg = self.format_infinite_loop_error()
    self.trap(msg, 0, 0)
    return Trap
  }
  // 每 SNAPSHOT_INTERVAL 步刷新变量快照（无限循环诊断的对比基线——
  // 与检查点间隔是两个频率，坑 14）
  if self.step_count % SNAPSHOT_INTERVAL == 0 {
    self.snapshot_vars.clear()
    for sym in self.symbols {
      if sym.ty.is_array() {
        continue
      }
      self.snapshot_vars.set(
        sym.name,
        self.read_variable(sym).reinterpret_as_uint64(),
      )
    }
    self.last_snapshot_step = self.step_count
  }
  if self.cancelled {
    self.trap("执行已取消。", 0, 0)
    return Trap
  }
  let inst = self.code[self.ip]
  self.ip = self.ip + 1
  // P0 观测落闸（#176，2026-11-02）：`observe` 为 false（run 全速态）则
  // 短路热力图与变量访问记录——两件在 run 态零消费方；step 态恒 true，
  // 下方逻辑逐字保留。
  if self.observe {
    // 热力图：只统计用户主文件（file_id == 0）的行号，避免 Bytecode Libc
    // 行号混入导致覆盖率超 100%（Rust 同口径）。P0b-1：定长数组自增免
    // 哈希（#176 micro：native 37.8→0.67ns / wasm-gc 11.5→2.2ns），
    // 惰性扩容见 ensure_heat；快照时整组深拷贝
    if inst.loc.line > 0 && inst.loc.file_id == 0 {
      self.ensure_heat(inst.loc.line)
      self.heatmap[inst.loc.line] = self.heatmap[inst.loc.line] + 1UL
    }
    // 清空上一步的变量访问记录（瞬时观测）
    self.last_accessed_vars.clear()
  }
  let r = self.dispatch_single(
    inst.op,
    inst.operand,
    inst.loc.line,
    inst.loc.column,
    inst.loc.file_id,
  )
  match r {
    Some(result) => result
    None => if self.error.is_empty() { Ok } else { Trap }
  }
}

///|
/// 完整运行（Rust `run` 砍 JIT fast path；宿主域内聚故无 session 参数）。
///
/// **P0 观测落闸**（#176，2026-11-02）：全速态入口置 `observe = false`
/// ——heatmap / last_accessed_vars / StepEvent vis 事件队列三件在此态
/// 零消费方（run 出口八字段不含三件；消费面全在 step 态 engine/collector）
/// ——任意出口恢复 true（`run_loop` 单出口包裹，Finished/Trap/Paused/
/// WaitingInput 四形态无遗漏）。断点暂停 / current_line / 步数预算 /
/// 无限循环快照诊断不在落闸面——run 态 trap 文案与 Paused 协议原样。
/// **入口清一次 last_accessed_vars**（PR #439 审阅 P3-6：clear 移进 observe
/// 分支后 run 态「既不清也不记」，step 态残留会越过 run——零成本归零，
/// run 后三件恒空的语义对 pub 字段读者成立）。
pub fn VitroVM::run(self : VitroVM) -> Int32 {
  self.last_accessed_vars.clear()
  self.observe = false
  let rc = self.run_loop()
  self.observe = true
  rc
}

///|
/// `run` 的步进循环本体（出口语义不变——拆出仅为 `observe` 进出单点包裹）。
fn VitroVM::run_loop(self : VitroVM) -> Int32 {
  while true {
    let result = self.step()
    match result {
      Finished => return self.final_return_value()
      Trap => return 0
      Paused => {
        self.trap(
          "完整运行模式下遇到暂停状态（可能是断点配置不一致）",
          0, 0,
        )
        return 0
      }
      WaitingInput => return 0
      Ok => continue
    }
  }
  0
}

///|
/// 单指令分发（一级穷尽 match，135 臂无兜底——opcode 增删即编译红）。
fn VitroVM::dispatch_single(
  self : VitroVM,
  op : @opcode.OpCode,
  operand : Int32,
  line : Int32,
  column : Int32,
  file_id : Int32,
) -> StepResult? {
  match op {
    Nop => ()
    // ── 栈顶 ──
    PushConst | PushArgc | PushArgv | Pop | Dup | Swap =>
      self.execute_stack(op, operand, line, column)
    // ── 局部 / 全局 ──
    LoadLocal
    | StoreLocal
    | LoadLocalD
    | StoreLocalD
    | LoadLocalQ
    | StoreLocalQ
    | GetFrameBase => self.execute_local(op, operand, line, column)
    LoadGlobal
    | StoreGlobal
    | LoadGlobalD
    | StoreGlobalD
    | LoadGlobalQ
    | StoreGlobalQ
    | LoadGlobalByte
    | LoadGlobalUByte
    | StoreGlobalByte => self.execute_global(op, operand, line, column)
    // ── 内存 ──
    LoadMem
    | StoreMem
    | LoadMemD
    | StoreMemD
    | LoadMemByte
    | StoreMemByte
    | LoadMemUByte
    | LoadMemQ
    | StoreMemQ
    | SplitD
    | SplitQ
    | StackAlloc
    | Memcpy
    | Memset
    | Strlen => self.execute_memory(op, operand, line, column)
    // ── 算术 ──
    Add
    | Sub
    | Mul
    | Div
    | Mod
    | Neg
    | UDiv
    | UMod
    | USub
    | UNeg
    | UAdd
    | UMul
    | TruncByte
    | TruncUByte => self.execute_arithmetic(op, operand, line, column)
    // ── 比较与逻辑 ──
    Eq | Ne | Lt | Le | Gt | Ge | And | Or | Not | ULt | ULe | UGt | UGe =>
      self.execute_comparison(op, operand, line, column)
    // ── 位运算 ──
    BitAnd
    | BitOr
    | BitXor
    | BitNot
    | Shl
    | Shr
    | LShr
    | BitAndQ
    | BitOrQ
    | BitXorQ
    | BitNotQ
    | ShlQ
    | ShrQ
    | LShrQ => self.execute_bitwise(op, operand, line, column)
    // ── F（f32）族 ──
    PushConstF
    | AddF
    | SubF
    | MulF
    | DivF
    | NegF
    | CastI2F
    | CastU2F
    | CastUQ2F
    | CastF2I
    | EqF
    | NeF
    | LtF
    | LeF
    | GtF
    | GeF => self.execute_float(op, operand, line, column)
    // ── D（f64）族 ──
    PushConstD
    | AddD
    | SubD
    | MulD
    | DivD
    | NegD
    | CastI2D
    | CastU2D
    | CastUQ2D
    | CastF2D
    | CastD2I
    | CastD2F
    | EqD
    | NeD
    | LtD
    | LeD
    | GtD
    | GeD => self.execute_double(op, operand, line, column)
    // ── Q（i64）族 ──
    PushConstQ
    | AddQ
    | SubQ
    | MulQ
    | DivQ
    | ModQ
    | NegQ
    | CastI2Q
    | CastQ2I
    | CastQ2D
    | CastD2Q
    | CastD2UQ
    | EqQ
    | NeQ
    | LtQ
    | LeQ
    | GtQ
    | GeQ
    | CastU2Q
    | UDivQ
    | UModQ
    | UNegQ
    | ULtQ
    | ULeQ
    | UGtQ
    | UGeQ => self.execute_longlong(op, operand, line, column)
    // ── 控制流族（CallHost 的 host 分发随批三号——其臂内 fail loud）──
    Jump
    | JumpIfZero
    | JumpIfNotZero
    | Call
    | CallVar
    | CallPtr
    | CallHost
    | Ret
    | RetVoid => return self.execute_control_flow(op, operand, line, column)
    // ── C# 异常三件（CS 批语义；C 前端零发射）──
    TryBegin | TryEnd | Throw =>
      self.trap(
        "C# 异常指令被执行（\{op.name()}）——C 前端零发射契约破坏（CS 批接线前不可达）",
        line,
        column,
      )
    // ── 教学观测 ──
    StepEvent | TrapBounds | TrapBoundsVla =>
      return self.execute_debug(op, operand, line, column, file_id)
  }
  if !self.error.is_empty() {
    Some(Trap)
  } else {
    None
  }
}

///|
/// 无限循环诊断的变量快照刷新间隔（照搬 Rust `SNAPSHOT_INTERVAL = 100_000`）。
pub const SNAPSHOT_INTERVAL : Int32 = 100_000
