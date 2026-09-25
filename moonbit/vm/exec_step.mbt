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
/// 段二待接线（本批 fail loud 到达即 trap）：F/D/Q 浮点三族、控制流族
/// （Jump/Call/CallPtr/CallVar/CallHost/Ret）、C# 异常三件（TryBegin/
/// TryEnd/Throw——CS 批语义）。

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
  if self.step_count >= self.max_steps {
    let msg = self.format_infinite_loop_error()
    self.trap(msg, 0, 0)
    return Trap
  }
  if self.cancelled {
    self.trap("执行已取消。", 0, 0)
    return Trap
  }
  let inst = self.code[self.ip]
  self.ip = self.ip + 1
  // 热力图：只统计用户主文件（file_id == 0）的行号，避免 Bytecode Libc
  // 行号混入导致覆盖率超 100%（Rust 同口径；MoonBit 直更可变 Map——
  // 无 Arc COW 克隆点，快照时整表拷贝）
  if inst.loc.line > 0 && inst.loc.file_id == 0 {
    let cur = match self.heatmap.get(inst.loc.line) {
      Some(v) => v
      None => 0UL
    }
    self.heatmap.set(inst.loc.line, cur + 1UL)
  }
  // 清空上一步的变量访问记录（瞬时观测）
  self.last_accessed_vars.clear()
  let r = self.dispatch_single(
    inst.op,
    inst.operand,
    inst.loc.line,
    inst.loc.column,
  )
  match r {
    Some(result) => result
    None => if self.error.is_empty() { Ok } else { Trap }
  }
}

///|
/// 完整运行（Rust `run` 砍 JIT fast path；宿主域内聚故无 session 参数）。
pub fn VitroVM::run(self : VitroVM) -> Int {
  while true {
    let result = self.step()
    match result {
      Finished =>
        return if self.finished {
          self.exit_code
        } else if self.stack.length() > 0 {
          self.stack[self.stack.length() - 1].to_int()
        } else {
          0
        }
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
  operand : Int,
  line : Int,
  column : Int,
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
    | StoreGlobalQ => self.execute_global(op, operand, line, column)
    // ── 内存 ──
    LoadMem
    | StoreMem
    | LoadMemD
    | StoreMemD
    | LoadMemByte
    | StoreMemByte
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
    | UMul => self.execute_arithmetic(op, operand, line, column)
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
    // ── F/D/Q 浮点与长整型族（段二接线，本批 fail loud）──
    PushConstF
    | AddF
    | SubF
    | MulF
    | DivF
    | NegF
    | CastI2F
    | CastF2I
    | EqF
    | NeF
    | LtF
    | LeF
    | GtF
    | GeF
    | PushConstD
    | AddD
    | SubD
    | MulD
    | DivD
    | NegD
    | CastI2D
    | CastF2D
    | CastD2I
    | CastD2F
    | EqD
    | NeD
    | LtD
    | LeD
    | GtD
    | GeD
    | PushConstQ
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
    | EqQ
    | NeQ
    | LtQ
    | LeQ
    | GtQ
    | GeQ =>
      self.trap(
        "执行器批二段二待接线：浮点/长整型族（\{op.name()}）——F/D/Q 三族随 float 批落地",
        line,
        column,
      )
    // ── 控制流族（段二接线，本批 fail loud）──
    Jump
    | JumpIfZero
    | JumpIfNotZero
    | Call
    | CallVar
    | CallPtr
    | CallHost
    | Ret
    | RetVoid =>
      self.trap(
        "执行器批二段二待接线：控制流族（\{op.name()}）——Jump/Call/Ret 随 control 批落地",
        line,
        column,
      )
    // ── C# 异常三件（CS 批语义；C 前端零发射）──
    TryBegin | TryEnd | Throw =>
      self.trap(
        "C# 异常指令被执行（\{op.name()}）——C 前端零发射契约破坏（CS 批接线前不可达）",
        line,
        column,
      )
    // ── 教学观测 ──
    StepEvent | TrapBounds | TrapBoundsVla =>
      return self.execute_debug(op, operand, line, column)
  }
  if !self.error.is_empty() {
    Some(Trap)
  } else {
    None
  }
}

///|
/// 无限循环诊断的变量快照刷新间隔（照搬 Rust `SNAPSHOT_INTERVAL = 100_000`）。
pub const SNAPSHOT_INTERVAL : Int = 100_000
