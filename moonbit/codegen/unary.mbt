///|
/// 一元运算生成（S5 表达式核心批·一元——剩余首错第 3 位 44 例）——Rust
/// `expr/unary.rs` 的 C only 子集照搬：
/// - Neg/Not/BitNot/Deref 全量（Deref 用 immediate_base_kind 只解一层——
///   事故 #20 的修复形态）；
/// - Addr：Identifier（含 static 局部——Rust 此臂有 static 分支，与
///   gen_addr 的勘察 #29 缺失互补）+ Deref/复合字面量/struct 返回透传 +
///   rvalue 物化兜底照搬；Index/Member 子臂随 Index/Member 批接线；
/// - ++/--：Identifier 子臂全量（T-P0-3 按类型分派 + float 的 F2D/D2F
///   转换链）+ Deref 子臂（步长恒 1——指针自增 vs pointee 自增区分）+
///   gen_mem_inc_dec（T-P0-3/T-P0-5 按元素类型 D/Q/Byte 分派）；Index/
///   Member 子臂随其批接线。

///|
/// ++/-- 的类型分派键（本包私有——跨包 TypeKind 构造器只读，int 兜底
/// 无法在包外构造 TK_Int；从 @ast.Type 提取为本地枚举）。
enum IncDecKind {
  IDD_Int
  IDD_Float
  IDD_Double
  IDD_LongLong
}

///|
fn incdec_kind_of(ty : @ast.Type?) -> IncDecKind {
  match ty {
    Some(t) =>
      match t.kind() {
        TK_Float => IDD_Float
        TK_Double => IDD_Double
        TK_LongLong => IDD_LongLong
        _ => IDD_Int
      }
    None => IDD_Int
  }
}

///|
/// 只解一层指针的基类型（Rust `immediate_base_kind`——事故 #20 修复形态：
/// `base_kind` 递归到底对 char*[]/char** 会错步长/宽度）。
fn immediate_base_kind(ty : @ast.Type) -> @ast.TypeKind {
  match ty {
    Pointer(pointee, _) => pointee.kind()
    _ => ty.kind()
  }
}

///|
fn BytecodeGen::gen_unary(
  self : BytecodeGen,
  op : @ast.UnaryOp,
  operand : @ast.Expr,
  loc : @source.SourceLoc,
) -> Unit {
  match op {
    Neg => {
      self.gen_expr(operand)
      let ok = operand.ty().kind()
      if ok is TK_Double {
        self.emit(@opcode.OpCode::NegD, 0, loc)
      } else if ok is TK_Float {
        self.emit(@opcode.OpCode::NegF, 0, loc)
      } else if ok is TK_LongLong {
        self.emit(@opcode.OpCode::NegQ, 0, loc)
      } else if operand.ty().is_unsigned() {
        self.emit(@opcode.OpCode::UNeg, 0, loc)
      } else {
        self.emit(@opcode.OpCode::Neg, 0, loc)
      }
    }
    Not => {
      self.gen_expr(operand)
      self.emit(@opcode.OpCode::Not, 0, loc)
    }
    BitNot => {
      self.gen_expr(operand)
      // E1 B 档：long long 操作数走 64 位取反
      if operand.ty().kind() is TK_LongLong {
        self.emit(@opcode.OpCode::BitNotQ, 0, loc)
      } else {
        self.emit(@opcode.OpCode::BitNot, 0, loc)
      }
    }
    Addr =>
      match operand {
        Identifier(name, _, _) =>
          match self.local_indices.get(name) {
            Some(offset) => {
              self.emit(@opcode.OpCode::GetFrameBase, 0, loc)
              self.emit(@opcode.OpCode::PushConst, offset, loc)
              self.emit(@opcode.OpCode::Add, 0, loc)
            }
            None =>
              match self.static_local_indices.get(name) {
                Some(offset) =>
                  self.emit(
                    @opcode.OpCode::PushConst,
                    @bytecode.GLOBAL_START.reinterpret_as_int() + offset,
                    loc,
                  )
                None =>
                  match self.global_indices.get(name) {
                    Some(offset) =>
                      self.emit(
                        @opcode.OpCode::PushConst,
                        @bytecode.GLOBAL_START.reinterpret_as_int() + offset,
                        loc,
                      )
                    None =>
                      match self.func_index.get(name) {
                        // &func_name —— 取函数地址（函数索引即地址）
                        Some(idx) =>
                          self.emit(@opcode.OpCode::PushConst, idx, loc)
                        None => {
                          self.report_error(
                            "取地址暂不支持此表达式", loc,
                          )
                          self.emit(@opcode.OpCode::PushConst, 0, loc)
                        }
                      }
                  }
              }
          }
        Index(array, index, _, ty) =>
          self.gen_index(array, index, ty, loc, true)
        Member(object, mname, _, _) => self.gen_member_addr(object, mname, loc)
        Unary(@ast.UnaryOp::Deref, inner, _, _) =>
          // &*p === p
          self.gen_expr(inner)
        CompoundLiteral(_, _, _, _) =>
          // 复合字面量是 lvalue，gen_expr 已在栈顶留下临时对象地址
          self.gen_expr(operand)
        _ => {
          // rvalue 物化兜底（Rust 照搬——C 输入下 &rvalue 不可达，防御面
          // 保留）：标量临时槽化后取址
          let operand_ty = operand.ty()
          let can_materialize = operand_ty.kind() is TK_Int ||
            operand_ty.kind() is TK_Char ||
            operand_ty.kind() is TK_Float ||
            operand_ty.kind() is TK_Double ||
            operand_ty.kind() is TK_LongLong ||
            operand_ty.kind() is TK_Pointer
          if can_materialize {
            let sz = self.type_size(operand_ty)
            let offset = self.next_local_offset
            let aligned = if sz % 4 == 0 { sz } else { sz + 4 - sz % 4 }
            self.next_local_offset += aligned
            self.gen_expr(operand)
            match operand_ty.kind() {
              TK_Double => self.emit(@opcode.OpCode::StoreLocalD, offset, loc)
              TK_LongLong => self.emit(@opcode.OpCode::StoreLocalQ, offset, loc)
              _ => self.emit(@opcode.OpCode::StoreLocal, offset, loc)
            }
            self.emit(@opcode.OpCode::GetFrameBase, 0, loc)
            self.emit(@opcode.OpCode::PushConst, offset, loc)
            self.emit(@opcode.OpCode::Add, 0, loc)
          } else {
            self.report_error("取地址暂不支持此表达式", loc)
            self.emit(@opcode.OpCode::PushConst, 0, loc)
          }
        }
      }
    Deref => {
      self.gen_expr(operand)
      // 跨包 enum 构造器只读（TK_Int 不能在 ast 包外构造）——非指针的
      // int 兜底用 None 表达
      let base_kind : @ast.TypeKind? = if operand.ty().kind() is TK_Pointer {
        Some(immediate_base_kind(operand.ty()))
      } else {
        None
      }
      match base_kind {
        Some(TK_Function) => ()
        // 函数指针解引用：*fp 即函数本身，随即退化回同一指针——无 load
        Some(TK_Char) => self.emit(@opcode.OpCode::LoadMemByte, 0, loc)
        Some(TK_Double) => self.emit(@opcode.OpCode::LoadMemD, 0, loc)
        Some(TK_LongLong) => self.emit(@opcode.OpCode::LoadMemQ, 0, loc)
        _ => self.emit(@opcode.OpCode::LoadMem, 0, loc)
      }
    }
    PreInc | PreDec | PostInc | PostDec => {
      let is_inc = op is PreInc || op is PostInc
      let is_pre = op is PreInc || op is PreDec
      match operand {
        Identifier(name, _, _) => {
          // T-P0-3：浮点/long long 变量的 ++/-- 按变量类型分派；float 槽
          // 存 f32 位模式，算术经 CastF2D/CastD2F 转换链在 double 值域进行
          let var_ty = match self.local_types.get(name) {
            Some(t) => Some(t)
            None =>
              match self.static_local_types.get(name) {
                Some(t) => Some(t)
                None => self.global_types.get(name)
              }
          }
          let step = match var_ty {
            Some(t) => self.ptr_step_size(t)
            None => 1
          }
          // 统一序列：load →(float: CastF2D)→ postDup → ±step →
          // (float: CastD2F)→ preDup → store（Rust emit_seq 闭包展开）
          match self.static_local_indices.get(name) {
            Some(static_idx) =>
              self.emit_incdec_seq(
                load_op=incdec_global_load(incdec_kind_of(var_ty)),
                idx=static_idx,
                store_op=incdec_global_store(incdec_kind_of(var_ty)),
                is_inc~,
                is_pre~,
                step~,
                kind=incdec_kind_of(var_ty),
                loc~,
              )
            None => {
              let local_idx = self.resolve_local(name)
              if local_idx >= 0 {
                self.emit_incdec_seq(
                  load_op=incdec_local_load(incdec_kind_of(var_ty)),
                  idx=local_idx,
                  store_op=incdec_local_store(incdec_kind_of(var_ty)),
                  is_inc~,
                  is_pre~,
                  step~,
                  kind=incdec_kind_of(var_ty),
                  loc~,
                )
              } else {
                let global_idx = self.resolve_global(name)
                if global_idx >= 0 {
                  self.emit_incdec_seq(
                    load_op=incdec_global_load(incdec_kind_of(var_ty)),
                    idx=global_idx,
                    store_op=incdec_global_store(incdec_kind_of(var_ty)),
                    is_inc~,
                    is_pre~,
                    step~,
                    kind=incdec_kind_of(var_ty),
                    loc~,
                  )
                } else {
                  self.report_error(
                    "自增/自减暂只支持简单变量", loc,
                  )
                  self.emit(@opcode.OpCode::PushConst, 0, loc)
                }
              }
            }
          }
        }
        Index(array, index, _, ty) => {
          let step = self.ptr_step_size(ty)
          self.gen_index(array, index, ty, loc, true)
          self.gen_mem_inc_dec(is_inc, is_pre, step, ty.kind(), loc)
        }
        Member(object, mname, _, ty) => {
          let step = self.ptr_step_size(ty)
          self.gen_member_addr(object, mname, loc)
          self.gen_mem_inc_dec(is_inc, is_pre, step, ty.kind(), loc)
        }
        Unary(@ast.UnaryOp::Deref, inner, _, _) => {
          // (*p)++ 是对 pointee 标量自增，步长恒 1（指针自身的 p++ 走
          // Identifier 分支才按 pointee 大小缩放；此前误传 ptr_step_size
          // 导致 (*double_p)++ 加 8）
          // 非指针兜底（int）经 None 表达（跨包构造器只读）
          let elem_kind : @ast.TypeKind? = if inner.ty().kind() is TK_Pointer {
            Some(immediate_base_kind(inner.ty()))
          } else {
            None
          }
          self.gen_expr(inner)
          match elem_kind {
            Some(k) => self.gen_mem_inc_dec(is_inc, is_pre, 1, k, loc)
            None => self.gen_mem_inc_dec_int(is_inc, is_pre, 1, loc)
          }
        }
        _ => {
          self.report_error("自增/自减暂只支持简单变量", loc)
          self.emit(@opcode.OpCode::PushConst, 0, loc)
        }
      }
    }
  }
}

///|
/// 变量 ++/-- 的 load/store opcode 对（局部侧，按类型分派）。
fn incdec_local_load(kind : IncDecKind) -> @opcode.OpCode {
  match kind {
    IDD_Double => @opcode.OpCode::LoadLocalD
    IDD_LongLong => @opcode.OpCode::LoadLocalQ
    _ => @opcode.OpCode::LoadLocal
  }
}

///|
fn incdec_local_store(kind : IncDecKind) -> @opcode.OpCode {
  match kind {
    IDD_Double => @opcode.OpCode::StoreLocalD
    IDD_LongLong => @opcode.OpCode::StoreLocalQ
    _ => @opcode.OpCode::StoreLocal
  }
}

///|
fn incdec_global_load(kind : IncDecKind) -> @opcode.OpCode {
  match kind {
    IDD_Double => @opcode.OpCode::LoadGlobalD
    IDD_LongLong => @opcode.OpCode::LoadGlobalQ
    _ => @opcode.OpCode::LoadGlobal
  }
}

///|
fn incdec_global_store(kind : IncDecKind) -> @opcode.OpCode {
  match kind {
    IDD_Double => @opcode.OpCode::StoreGlobalD
    IDD_LongLong => @opcode.OpCode::StoreGlobalQ
    _ => @opcode.OpCode::StoreGlobal
  }
}

///|
/// Rust `emit_seq` 闭包展开（指令序逐条等价）：
/// load →(float: CastF2D)→ [post: Dup] → ±step →(float: CastD2F)→
/// [pre: Dup] → store。
fn BytecodeGen::emit_incdec_seq(
  self : BytecodeGen,
  load_op~ : @opcode.OpCode,
  idx~ : Int,
  store_op~ : @opcode.OpCode,
  is_inc~ : Bool,
  is_pre~ : Bool,
  step~ : Int,
  kind~ : IncDecKind,
  loc~ : @source.SourceLoc,
) -> Unit {
  self.emit(load_op, idx, loc)
  if kind is IDD_Float {
    self.emit(@opcode.OpCode::CastF2D, 0, loc)
  }
  if !is_pre {
    self.emit(@opcode.OpCode::Dup, 0, loc)
  }
  match kind {
    IDD_Double | IDD_Float => {
      let ci = self.push_f64_constant(step.to_double())
      self.emit(@opcode.OpCode::PushConstD, ci, loc)
      self.emit(
        if is_inc {
          @opcode.OpCode::AddD
        } else {
          @opcode.OpCode::SubD
        },
        0,
        loc,
      )
    }
    IDD_LongLong => {
      let ci = self.push_i64_constant(step.to_int64())
      self.emit(@opcode.OpCode::PushConstQ, ci, loc)
      self.emit(
        if is_inc {
          @opcode.OpCode::AddQ
        } else {
          @opcode.OpCode::SubQ
        },
        0,
        loc,
      )
    }
    _ => {
      self.emit(@opcode.OpCode::PushConst, step, loc)
      self.emit(
        if is_inc {
          @opcode.OpCode::Add
        } else {
          @opcode.OpCode::Sub
        },
        0,
        loc,
      )
    }
  }
  if kind is IDD_Float {
    self.emit(@opcode.OpCode::CastD2F, 0, loc)
  }
  if is_pre {
    self.emit(@opcode.OpCode::Dup, 0, loc)
  }
  self.emit(store_op, idx, loc)
}

///|
/// gen_mem_inc_dec 的 int 兜底入口（elem_kind None 路径——非指针解引用
/// 按普通 word；跨包 TK_Int 不可构造，经本包装传 TK_Int 的等价判定：走
/// _ 默认臂即 int 形态。**tk_int 的合法获取**：@ast.Type::int().kind()）。
fn BytecodeGen::gen_mem_inc_dec_int(
  self : BytecodeGen,
  is_inc : Bool,
  is_pre : Bool,
  step : Int,
  loc : @source.SourceLoc,
) -> Unit {
  let int_kind = @ast.Type::int().kind()
  self.gen_mem_inc_dec(is_inc, is_pre, step, int_kind, loc)
}

///|
/// 内存位置的 ++/--（栈顶地址的读-改-写，T-P0-3/T-P0-5 按元素类型分派
/// D/Q/Byte；64 位位模式经 8 字节专用槽中转）。
fn BytecodeGen::gen_mem_inc_dec(
  self : BytecodeGen,
  is_inc : Bool,
  is_pre : Bool,
  step : Int,
  elem_kind : @ast.TypeKind,
  loc : @source.SourceLoc,
) -> Unit {
  // 栈顶：地址
  let addr_temp = self.get_temp_slot(2)
  self.emit(@opcode.OpCode::StoreLocal, addr_temp, loc)
  let load_op = match elem_kind {
    TK_Double => @opcode.OpCode::LoadMemD
    // float 内存元素按 4 字节 f32 位模式存取，算术经 CastF2D/CastD2F
    TK_Float => @opcode.OpCode::LoadMem
    TK_LongLong => @opcode.OpCode::LoadMemQ
    TK_Char => @opcode.OpCode::LoadMemByte
    _ => @opcode.OpCode::LoadMem
  }
  let store_op = match elem_kind {
    TK_Double => @opcode.OpCode::StoreMemD
    TK_Float => @opcode.OpCode::StoreMem
    TK_LongLong => @opcode.OpCode::StoreMemQ
    TK_Char => @opcode.OpCode::StoreMemByte
    _ => @opcode.OpCode::StoreMem
  }
  self.emit(@opcode.OpCode::LoadLocal, addr_temp, loc)
  self.emit(load_op, 0, loc)
  if !is_pre {
    self.emit(@opcode.OpCode::Dup, 0, loc)
  }
  if elem_kind is TK_Float {
    self.emit(@opcode.OpCode::CastF2D, 0, loc)
  }
  match elem_kind {
    TK_Double | TK_Float => {
      let ci = self.push_f64_constant(step.to_double())
      self.emit(@opcode.OpCode::PushConstD, ci, loc)
      self.emit(
        if is_inc {
          @opcode.OpCode::AddD
        } else {
          @opcode.OpCode::SubD
        },
        0,
        loc,
      )
    }
    TK_LongLong => {
      let ci = self.push_i64_constant(step.to_int64())
      self.emit(@opcode.OpCode::PushConstQ, ci, loc)
      self.emit(
        if is_inc {
          @opcode.OpCode::AddQ
        } else {
          @opcode.OpCode::SubQ
        },
        0,
        loc,
      )
    }
    _ => {
      self.emit(@opcode.OpCode::PushConst, step, loc)
      self.emit(
        if is_inc {
          @opcode.OpCode::Add
        } else {
          @opcode.OpCode::Sub
        },
        0,
        loc,
      )
    }
  }
  if elem_kind is TK_Float {
    self.emit(@opcode.OpCode::CastD2F, 0, loc)
  }
  // 新值存 temp 槽：double/long long 的 64 位位模式必须用 8 字节专用槽
  let val_temp = if elem_kind is TK_Double || elem_kind is TK_LongLong {
    self.get_temp_slot_64()
  } else {
    self.get_temp_slot(3)
  }
  if elem_kind is TK_Double || elem_kind is TK_LongLong {
    self.emit(@opcode.OpCode::StoreLocalD, val_temp, loc)
    self.emit(@opcode.OpCode::LoadLocal, addr_temp, loc)
    self.emit(@opcode.OpCode::LoadLocalD, val_temp, loc)
  } else {
    self.emit(@opcode.OpCode::StoreLocal, val_temp, loc)
    self.emit(@opcode.OpCode::LoadLocal, addr_temp, loc)
    self.emit(@opcode.OpCode::LoadLocal, val_temp, loc)
  }
  self.emit(store_op, 0, loc)
  if is_pre {
    self.emit(@opcode.OpCode::LoadLocal, addr_temp, loc)
    self.emit(load_op, 0, loc)
  }
  // post：旧值已在栈上
}
