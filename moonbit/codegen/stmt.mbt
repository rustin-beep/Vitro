///|
/// 语句与表达式分派（S5 骨架最小集）——Rust `stmt/mod.rs` + `expr.rs`
/// 照搬的分派形态：gen_stmt 入口先发 StepEvent（loc.line > 0 时），
/// 再按语句族分派。**本批只接线 Block/Expr(stmt)/Return 三族**（骨架
/// 端到端通路：全局变量 + main{return 常量/空}），其余语句族
/// report_error fail loud（S5 后续扩展批逐族接线，接线前差分面表现为
/// MoonBit 侧错误——诚实优先，禁静默跳过产半截产物）。
fn BytecodeGen::gen_stmt(self : BytecodeGen, stmt : @ast.Stmt) -> Unit {
  let loc = stmt_loc(stmt)
  if loc.line > 0 {
    self.emit(@opcode.OpCode::StepEvent, loc.line, loc)
  }
  match stmt {
    Block(stmts, _) => self.gen_block(stmts)
    Expr(expr, _) => self.gen_expr_stmt(expr, loc)
    Return(value, ret_loc) => self.gen_return(value, ret_loc)
    VarDecl(var_type, name, init, extra_vars, is_static, _) =>
      self.gen_var_decl(var_type, name, init, extra_vars, is_static, loc)
    If(_, _, _, _) =>
      self.report_error(
        "if 语句的字节码生成未实现（S5 在途）", loc,
      )
    While(_, _, _) =>
      self.report_error(
        "while 语句的字节码生成未实现（S5 在途）", loc,
      )
    DoWhile(_, _, _) =>
      self.report_error(
        "do-while 语句的字节码生成未实现（S5 在途）", loc,
      )
    For(_, _, _, _, _) =>
      self.report_error(
        "for 语句的字节码生成未实现（S5 在途）", loc,
      )
    Break(b_loc) => {
      // Rust gen_break：无 RAII 析构（C only）时即占位 Jump 入 break_patches
      let ip = self.current_ip()
      self.emit(@opcode.OpCode::Jump, 0, b_loc)
      self.break_patches.push(ip)
    }
    Continue(c_loc) => {
      let ip = self.current_ip()
      self.emit(@opcode.OpCode::Jump, 0, c_loc)
      self.continue_patches.push(ip)
    }
    Switch(_, _, _) =>
      self.report_error(
        "switch 语句的字节码生成未实现（S5 在途）", loc,
      )
    Case(_, _, _) => ()
    Goto(label, g_loc) =>
      // Rust gen_goto 照搬（C only 无 RAII 携带语义）
      match self.label_ips.get(label) {
        Some(target_ip) => self.emit(@opcode.OpCode::Jump, target_ip, g_loc)
        None => {
          let ip = self.current_ip()
          self.emit(@opcode.OpCode::Jump, 0, g_loc)
          match self.goto_patches.get(label) {
            Some(patches) => patches.push(ip)
            None => self.goto_patches.set(label, [ip])
          }
        }
      }
    Label(label, inner, _) => {
      let ip = self.current_ip()
      self.label_ips.set(label, ip)
      match self.goto_patches.get(label) {
        Some(patches) => {
          for patch_ip in patches {
            self.patch_jump(patch_ip, ip)
          }
          ignore(self.goto_patches.remove(label))
        }
        None => ()
      }
      self.gen_stmt(inner)
    }
    RangeFor(_, _, _, _, _) =>
      self.report_error(
        "range-for 是 C++ 路径（已随砍 C++ 裁定退役）", loc,
      )
    Try(_, _, _) =>
      self.report_error(
        "try 语句保留给 C# 批（reserved-for-csharp）", loc,
      )
  }
}

///|
fn BytecodeGen::gen_block(self : BytecodeGen, stmts : Array[@ast.Stmt]) -> Unit {
  self.enter_scope()
  for s in stmts {
    self.gen_stmt(s)
  }
  self.exit_scope()
}

///|
/// 表达式语句：值非 void 时弹栈（Rust expr_stmt.rs 照搬；is_class 随
/// 砍 C++ 裁定剔除——C only 下 class 类型零出现）。
fn BytecodeGen::gen_expr_stmt(
  self : BytecodeGen,
  expr : @ast.Expr,
  loc : @source.SourceLoc,
) -> Unit {
  self.gen_expr(expr)
  let ty = expr.ty()
  if !(ty.kind() is TK_Void) && !(ty.kind() is TK_Struct) {
    self.emit(@opcode.OpCode::Pop, 0, loc)
  }
}

///|
/// return 生成（Rust control.rs:113-190 的 C only 子集照搬：
/// ret_is_struct 走 __ret_ptr 拷贝——C 的 struct 返回值同款；引用/
/// 拷贝构造/RAII 析构三段是 C++ 路径不迁移；浮点↔整型返回位隐式
/// Cast 补插照搬）。
fn BytecodeGen::gen_return(
  self : BytecodeGen,
  value : @ast.Expr?,
  loc : @source.SourceLoc,
) -> Unit {
  match value {
    Some(v) => {
      let ret_is_struct = match self.func_table.get(self.current_func) {
        Some(m) => m.return_type.kind() is TK_Struct
        None => false
      }
      if ret_is_struct {
        let ret_ptr_offset = self.resolve_local("__ret_ptr")
        let size = self.type_size(v.ty())
        if size > 0 {
          // struct 返回值经 __ret_ptr 逐字拷贝（Rust 的 C 子集路径：
          // GetFrameBase+PushConst(ret_ptr)+Add → 元素循环 Load/Store。
          // 本骨架批未接线 gen_addr/copy 循环——fail loud，扩展批补）
          self.report_error(
            "struct 返回值的拷贝生成未实现（S5 在途）", loc,
          )
        }
        self.emit(@opcode.OpCode::RetVoid, 0, loc)
      } else {
        self.gen_expr(v)
        let ret_is_float = match self.func_table.get(self.current_func) {
          Some(m) =>
            m.return_type.kind() is TK_Float ||
            m.return_type.kind() is TK_Double
          None => false
        }
        if ret_is_float &&
          !(v.ty().kind() is TK_Float) &&
          !(v.ty().kind() is TK_Double) {
          self.emit(@opcode.OpCode::CastI2F, 0, loc)
        } else if !ret_is_float &&
          (v.ty().kind() is TK_Float || v.ty().kind() is TK_Double) {
          self.emit(@opcode.OpCode::CastF2I, 0, loc)
        }
        self.emit(@opcode.OpCode::Ret, 0, loc)
      }
    }
    None => self.emit(@opcode.OpCode::RetVoid, 0, loc)
  }
}

///|
/// 表达式生成（最小集）：四字面量族 + Identifier（static local/local/
/// global 的数组/D/Q/word 分派）——Rust expr.rs:48-145 与 expr/literal.rs
/// 照搬。其余表达式族 report_error（扩展批逐族接线；typeck 产出的
/// implicit Cast 包裹沿 Rust 现状由各表达式族内消费——Cast 本体生成
/// 随二元/赋值批接线）。
fn BytecodeGen::gen_expr(self : BytecodeGen, expr : @ast.Expr) -> Unit {
  let loc = expr.loc()
  match expr {
    Literal(value, _, _) => self.emit(@opcode.OpCode::PushConst, value, loc)
    FloatLiteral(value, _, ty) =>
      if ty.kind() is TK_Double {
        let idx = self.push_f64_constant(value)
        self.emit(@opcode.OpCode::PushConstD, idx, loc)
      } else {
        let bits = Float::from_double(value) |> f32_bits_i32
        self.emit(@opcode.OpCode::PushConstF, bits, loc)
      }
    LongLiteral(value, _, _) => {
      let idx = self.push_i64_constant(value)
      self.emit(@opcode.OpCode::PushConstQ, idx, loc)
    }
    StringLiteral(value, _, _) => {
      // 字符串字面量：全局区 bump 分配 + 地址入栈（Rust literal.rs:22-31）
      let aligned = ((cstring_len(value) + 1).reinterpret_as_uint() + 3) &
        @bytecode.ALIGN4_MASK
      let addr = @bytecode.GLOBAL_START +
        self.next_global_offset.reinterpret_as_uint()
      match
        self.bump_global_offset(aligned.to_int(), "字符串字面量", loc) {
        Some(_) => self.string_data.push((addr, value))
        None => ()
      }
      self.emit(@opcode.OpCode::PushConst, addr.to_int(), loc)
    }
    Identifier(name, _, _) => {
      // C99 __func__（E1 B 档）：预定义标识符 → 当前函数名字符串字面量
      // （Rust expr.rs 同臂照搬；typeck/expr.mbt 已支持其定型）
      if name == "__func__" {
        self.gen_expr(
          @ast.Expr::StringLiteral(
            self.current_func,
            loc,
            @ast.Type::pointer_to(@ast.Type::char()),
          ),
        )
        return
      }
      // 函数名作值（函数指针）
      match self.func_index.get(name) {
        Some(idx) => {
          self.emit(@opcode.OpCode::PushConst, idx, loc)
          return
        }
        None => ()
      }
      // C++ reference 自动解引用：C only 不迁移（Reference 类型零出现）
      // static local 变量
      match self.static_local_indices.get(name) {
        Some(static_offset) => {
          match self.static_local_types.get(name) {
            Some(ty) =>
              if ty.is_array() {
                self.emit(
                  @opcode.OpCode::PushConst,
                  @bytecode.GLOBAL_START.to_int() + static_offset,
                  loc,
                )
              } else if ty.kind() is TK_Double {
                self.emit(@opcode.OpCode::LoadGlobalD, static_offset, loc)
              } else if ty.kind() is TK_LongLong {
                self.emit(@opcode.OpCode::LoadGlobalQ, static_offset, loc)
              } else {
                self.emit(@opcode.OpCode::LoadGlobal, static_offset, loc)
              }
            None => self.emit(@opcode.OpCode::LoadGlobal, static_offset, loc)
          }
          return
        }
        None => ()
      }
      let local_offset = self.resolve_local(name)
      if local_offset >= 0 {
        match self.local_types.get(name) {
          Some(ty) =>
            if ty.is_array() {
              if ty.is_vla() {
                // VLA 以指针形态存栈
                self.emit(@opcode.OpCode::LoadLocal, local_offset, loc)
              } else if local_offset < self.current_func_arg_bytes {
                // 数组参数退化为指针
                self.emit(@opcode.OpCode::LoadLocal, local_offset, loc)
              } else {
                // 局部数组：算基址
                self.emit(@opcode.OpCode::GetFrameBase, 0, loc)
                self.emit(@opcode.OpCode::PushConst, local_offset, loc)
                self.emit(@opcode.OpCode::Add, 0, loc)
              }
            } else if ty.kind() is TK_Double {
              self.emit(@opcode.OpCode::LoadLocalD, local_offset, loc)
            } else if ty.kind() is TK_LongLong {
              self.emit(@opcode.OpCode::LoadLocalQ, local_offset, loc)
            } else {
              self.emit(@opcode.OpCode::LoadLocal, local_offset, loc)
            }
          None => self.emit(@opcode.OpCode::LoadLocal, local_offset, loc)
        }
      } else {
        let global_offset = self.resolve_global(name)
        if global_offset >= 0 {
          match self.global_types.get(name) {
            Some(ty) =>
              if ty.is_array() {
                self.emit(
                  @opcode.OpCode::PushConst,
                  @bytecode.GLOBAL_START.to_int() + global_offset,
                  loc,
                )
              } else if ty.kind() is TK_Double {
                self.emit(@opcode.OpCode::LoadGlobalD, global_offset, loc)
              } else if ty.kind() is TK_LongLong {
                self.emit(@opcode.OpCode::LoadGlobalQ, global_offset, loc)
              } else {
                self.emit(@opcode.OpCode::LoadGlobal, global_offset, loc)
              }
            None => self.emit(@opcode.OpCode::LoadGlobal, global_offset, loc)
          }
        } else {
          self.report_error("未声明的标识符 '\{name}'", loc)
          self.emit(@opcode.OpCode::PushConst, 0, loc)
        }
      }
    }
    // —— 以下未接线族显式分派（穷尽 26 变体无兜底臂——编码纪律 #1；
    //    新增 Expr 变体必须让本 match 编译红）——
    // C 子集待接线（14 族，扩展批逐族收敛）：
    Binary(_, _, _, _, _) =>
      self.report_error(
        "二元运算的字节码生成未实现（S5 在途）", loc,
      )
    Unary(_, _, _, _) =>
      self.report_error(
        "一元运算的字节码生成未实现（S5 在途）", loc,
      )
    Call(_, _, _, _) =>
      self.report_error(
        "内部错误：Expr::Call 仅 C++ ctor 路径构造（parser 后缀位统一产 CallPtr——两侧同构，MoonBit expr.mbt 与 Rust postfix.rs 同臂），砍 C++ 后 C 输入不可达；用户侧函数调用见 CallPtr 臂",
        loc,
      )
    // C 的直接调用与函数指针调用统一在本臂发射（2026-09-21 扩展批接线）
    CallPtr(callee, args, _, ret_ty) =>
      self.gen_call_ptr(callee, args, ret_ty, loc)
    Index(_, _, _, _) =>
      self.report_error(
        "数组索引的字节码生成未实现（S5 在途）", loc,
      )
    Member(_, _, _, _) =>
      self.report_error(
        "成员访问的字节码生成未实现（S5 在途）", loc,
      )
    Ternary(_, _, _, _, _) =>
      self.report_error(
        "三目运算的字节码生成未实现（S5 在途）", loc,
      )
    Assign(_, _, _, _, _) =>
      self.report_error(
        "赋值表达式的字节码生成未实现（S5 在途）", loc,
      )
    Sizeof(_, _, _, _) =>
      self.report_error(
        "sizeof 的字节码生成未实现（S5 在途）", loc,
      )
    Alignof(_, _, _, _) =>
      self.report_error(
        "alignof 的字节码生成未实现（S5 在途）", loc,
      )
    Cast(_, _, _, _) =>
      self.report_error(
        "类型转换的字节码生成未实现（S5 在途）", loc,
      )
    Offsetof(_, _, _, _) =>
      self.report_error(
        "offsetof 的字节码生成未实现（S5 在途）", loc,
      )
    Generic(_, _, _, _, _) =>
      self.report_error(
        "_Generic 的字节码生成未实现（S5 在途）", loc,
      )
    CompoundLiteral(_, _, _, _) =>
      self.report_error(
        "复合字面量的字节码生成未实现（S5 在途）", loc,
      )
    // 既定错误文案照搬（Rust expr.rs:160）——非"未实现"：
    InitList(_, _, _) => {
      self.report_error("初始化列表只能在变量声明中使用", loc)
      self.emit(@opcode.OpCode::PushConst, 0, loc)
    }
    // C++ 专有（6 族）：已随砍 C++ 裁定退役（F-2），永不接线——
    // 文案不得写"未实现"（对后来者是假承诺）：
    This(_, _) =>
      self.report_error(
        "'this' 是 C++ 专有表达式（已随砍 C++ 裁定退役）", loc,
      )
    MemberCall(_, _, _, _, _, _, _) =>
      self.report_error(
        "成员调用是 C++ 专有表达式（已随砍 C++ 裁定退役）", loc,
      )
    New(_, _, _, _, _) =>
      self.report_error(
        "new 是 C++ 专有表达式（已随砍 C++ 裁定退役）", loc,
      )
    Delete(_, _, _, _) =>
      self.report_error(
        "delete 是 C++ 专有表达式（已随砍 C++ 裁定退役）", loc,
      )
    Move(_, _, _) =>
      self.report_error(
        "std::move 是 C++ 专有表达式（已随砍 C++ 裁定退役）", loc,
      )
    Lambda(_, _, _, _, _, _) =>
      self.report_error(
        "lambda 是 C++ 专有表达式（已随砍 C++ 裁定退役）", loc,
      )
  }
}

///|
/// Float 位模式 → i32（f32 通道的 PushConstF 立即数）。
fn f32_bits_i32(f : Float) -> Int {
  Float::reinterpret_as_uint(f).reinterpret_as_int()
}
