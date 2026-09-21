///|
/// 控制流语句生成（S5 扩展批三号·控制流——if 17 / while 12 / do-while 4 /
/// for 30 / switch 5 例）——Rust `stmt/control.rs` + `stmt/switch.rs` 照搬。
/// C only 裁剪：loop_scope_depths / loop_break_has_init_frame 的 push/pop
/// 不迁移（RAII 析构范围跟踪，砍 C++ 后零消费——MoonBit 侧未建该字段）；
/// 指令序其余逐条一致（跳转补丁的 base 截断语义保持）。
fn BytecodeGen::gen_if(
  self : BytecodeGen,
  cond : @ast.Expr,
  then_stmt : @ast.Stmt,
  else_stmt : @ast.Stmt?,
  loc : @source.SourceLoc,
) -> Unit {
  self.gen_expr(cond)
  let else_jump = self.current_ip()
  self.emit(@opcode.OpCode::JumpIfZero, 0, loc)
  self.gen_stmt(then_stmt)
  let skip_else_jump = self.current_ip()
  self.emit(@opcode.OpCode::Jump, 0, loc)
  let else_ip = self.current_ip()
  self.patch_jump(else_jump, else_ip)
  match else_stmt {
    Some(e) => self.gen_stmt(e)
    None => ()
  }
  let end_ip = self.current_ip()
  self.patch_jump(skip_else_jump, end_ip)
}

///|
fn BytecodeGen::gen_while(
  self : BytecodeGen,
  cond : @ast.Expr,
  body : @ast.Stmt,
  loc : @source.SourceLoc,
) -> Unit {
  let start_ip = self.current_ip()
  self.gen_expr(cond)
  let end_jump = self.current_ip()
  self.emit(@opcode.OpCode::JumpIfZero, 0, loc)
  self.loop_start_ips.push(start_ip)
  let break_base = self.break_patches.length()
  let continue_base = self.continue_patches.length()
  self.gen_stmt(body)
  self.emit(@opcode.OpCode::Jump, start_ip, loc)
  let end_ip = self.current_ip()
  self.patch_jump(end_jump, end_ip)
  self.patch_loop_patches(end_ip, start_ip, break_base, continue_base)
  ignore(self.loop_start_ips.pop())
}

///|
fn BytecodeGen::gen_do_while(
  self : BytecodeGen,
  body : @ast.Stmt,
  cond : @ast.Expr,
  loc : @source.SourceLoc,
) -> Unit {
  let start_ip = self.current_ip()
  self.loop_start_ips.push(start_ip)
  let break_base = self.break_patches.length()
  let continue_base = self.continue_patches.length()
  self.gen_stmt(body)
  let cond_ip = self.current_ip()
  self.gen_expr(cond)
  self.emit(@opcode.OpCode::JumpIfNotZero, start_ip, loc)
  let end_ip = self.current_ip()
  self.patch_loop_patches(end_ip, cond_ip, break_base, continue_base)
  ignore(self.loop_start_ips.pop())
}

///|
fn BytecodeGen::gen_for(
  self : BytecodeGen,
  init : @ast.Stmt?,
  cond : @ast.Expr?,
  step : Array[@ast.Expr],
  body : @ast.Stmt,
  loc : @source.SourceLoc,
) -> Unit {
  self.enter_scope()
  match init {
    Some(i) => self.gen_stmt(i)
    None => ()
  }
  let start_ip = self.current_ip()
  let mut cond_jump = 0
  match cond {
    Some(c) => {
      self.gen_expr(c)
      cond_jump = self.current_ip()
      self.emit(@opcode.OpCode::JumpIfZero, 0, loc)
    }
    None => ()
  }
  self.loop_start_ips.push(start_ip)
  let break_base = self.break_patches.length()
  let continue_base = self.continue_patches.length()
  self.gen_stmt(body)
  let continue_ip = self.current_ip()
  for s in step {
    self.gen_expr(s)
    self.emit(@opcode.OpCode::Pop, 0, loc)
  }
  self.emit(@opcode.OpCode::Jump, start_ip, loc)
  let end_ip = self.current_ip()
  self.exit_scope()
  if cond is Some(_) {
    self.patch_jump(cond_jump, end_ip)
  }
  self.patch_loop_patches(end_ip, continue_ip, break_base, continue_base)
  ignore(self.loop_start_ips.pop())
}

///|
/// 循环补丁回填：break → end_ip、continue → continue_ip；处理完截断到
/// base（Rust resize 语义 = pop 到 base 长度）。
fn BytecodeGen::patch_loop_patches(
  self : BytecodeGen,
  end_ip : Int,
  continue_ip : Int,
  break_base : Int,
  continue_base : Int,
) -> Unit {
  let mut i = break_base
  while i < self.break_patches.length() {
    self.patch_jump(self.break_patches[i], end_ip)
    i += 1
  }
  while self.break_patches.length() > break_base {
    ignore(self.break_patches.pop())
  }
  let mut j = continue_base
  while j < self.continue_patches.length() {
    self.patch_jump(self.continue_patches[j], continue_ip)
    j += 1
  }
  while self.continue_patches.length() > continue_base {
    ignore(self.continue_patches.pop())
  }
}

///|
/// case 收集器（Rust collect_cases 嵌套 fn 的可变参数形态——MoonBit 闭包
/// 不能捕获可变外层，改经 struct 字段携带）。
priv struct CaseCollector {
  cases : Array[(@ast.Expr?, @ast.Stmt)]
  mut default_case : @ast.Stmt?
}

///|
/// Block 递归展开收集 Case 子语句（label Some → cases；None → default，
/// 后遇覆盖——Rust 同语义）。
fn collect_cases(stmt : @ast.Stmt, collector : CaseCollector) -> Unit {
  match stmt {
    Block(stmts, _) =>
      for s in stmts {
        collect_cases(s, collector)
      }
    Case(label, inner, _) =>
      match label {
        Some(l) => collector.cases.push((Some(l), inner))
        None => collector.default_case = Some(inner)
      }
    _ => ()
  }
}

///|
/// switch 生成（Rust `stmt/switch.rs` 照搬）：cond 存 temp_slot0 → 逐 case
/// Eq+JumpIfNotZero 分派 → default/落空尾跳 → body 顺序生成（fall-through
/// 语义：各 case body 首尾相接）→ break 补丁统一回填 end_ip。
fn BytecodeGen::gen_switch(
  self : BytecodeGen,
  cond : @ast.Expr,
  body : @ast.Stmt,
  loc : @source.SourceLoc,
) -> Unit {
  let collector = { cases: [], default_case: None, }
  collect_cases(body, collector)
  let cases = collector.cases
  if cases.length() == 0 && collector.default_case is None {
    self.gen_expr(cond)
    self.emit(@opcode.OpCode::Pop, 0, loc)
    return
  }
  self.gen_expr(cond)
  let cond_temp = self.get_temp_slot(0)
  self.emit(@opcode.OpCode::StoreLocal, cond_temp, loc)
  let case_jump_ips : Array[Int] = []
  for entry in cases {
    self.emit(@opcode.OpCode::LoadLocal, cond_temp, loc)
    match entry.0 {
      Some(l) => {
        self.gen_expr(l)
        let lloc = l.loc()
        if lloc.line > 0 {
          self.emit(@opcode.OpCode::StepEvent, lloc.line, lloc)
        }
      }
      None => ()
    }
    self.emit(@opcode.OpCode::Eq, 0, loc)
    let jump_ip = self.current_ip()
    self.emit(@opcode.OpCode::JumpIfNotZero, 0, loc)
    case_jump_ips.push(jump_ip)
  }
  let default_or_end_jump = self.current_ip()
  self.emit(@opcode.OpCode::Jump, 0, loc)
  let break_base = self.break_patches.length()
  for i, entry in cases {
    self.patch_jump(case_jump_ips[i], self.current_ip())
    self.gen_stmt(entry.1)
  }
  self.patch_jump(default_or_end_jump, self.current_ip())
  match collector.default_case {
    Some(d) => self.gen_stmt(d)
    None => ()
  }
  let end_ip = self.current_ip()
  let mut k = break_base
  while k < self.break_patches.length() {
    self.patch_jump(self.break_patches[k], end_ip)
    k += 1
  }
  while self.break_patches.length() > break_base {
    ignore(self.break_patches.pop())
  }
}
