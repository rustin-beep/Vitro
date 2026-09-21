///|
/// 类型转换与编译期尺寸生成（S5 表达式核心批·Cast 28 例 + sizeof 17 例）
/// ——Rust `expr/cast.rs` 全量照搬：10 向转换分派（I2D/F2D/Q2D/I2F/D2F/
/// I2Q/D2Q/D2I/F2I/Q2I）、VLA 的 sizeof 维度展开、alignof（type_align
/// 纯函数随迁——struct/union 成员最大自然对齐 + 自含环检测）、offsetof
/// 编译期偏移、gen_expr_with_cast（赋值/传参侧的隐式转换收口）。
fn BytecodeGen::gen_cast_expr(
  self : BytecodeGen,
  inner : @ast.Expr,
  target_type : @ast.Type,
  loc : @source.SourceLoc,
) -> Unit {
  self.gen_expr(inner)
  let tk = target_type.kind()
  let ik = inner.ty().kind()
  if tk is TK_Double &&
    !(ik is TK_Float) &&
    !(ik is TK_Double) &&
    !(ik is TK_LongLong) {
    self.emit(@opcode.OpCode::CastI2D, 0, loc)
  } else if tk is TK_Double && ik is TK_Float {
    self.emit(@opcode.OpCode::CastF2D, 0, loc)
  } else if tk is TK_Double && ik is TK_LongLong {
    self.emit(@opcode.OpCode::CastQ2D, 0, loc)
  } else if tk is TK_Float &&
    !(ik is TK_Float) &&
    !(ik is TK_Double) &&
    !(ik is TK_LongLong) {
    self.emit(@opcode.OpCode::CastI2F, 0, loc)
  } else if tk is TK_Float && ik is TK_Double {
    self.emit(@opcode.OpCode::CastD2F, 0, loc)
  } else if tk is TK_LongLong &&
    !(ik is TK_LongLong) &&
    !(ik is TK_Double) &&
    !(ik is TK_Float) {
    self.emit(@opcode.OpCode::CastI2Q, 0, loc)
  } else if tk is TK_LongLong && ik is TK_Double {
    self.emit(@opcode.OpCode::CastD2Q, 0, loc)
  } else if !(tk is TK_Float) &&
    !(tk is TK_Double) &&
    !(tk is TK_LongLong) &&
    ik is TK_Double {
    self.emit(@opcode.OpCode::CastD2I, 0, loc)
  } else if !(tk is TK_Float) &&
    !(tk is TK_Double) &&
    !(tk is TK_LongLong) &&
    ik is TK_Float {
    self.emit(@opcode.OpCode::CastF2I, 0, loc)
  } else if !(tk is TK_Float) &&
    !(tk is TK_Double) &&
    !(tk is TK_LongLong) &&
    ik is TK_LongLong {
    self.emit(@opcode.OpCode::CastQ2I, 0, loc)
  }
}

///|
fn BytecodeGen::gen_sizeof_expr(
  self : BytecodeGen,
  target_type : @ast.Type?,
  operand : @ast.Expr?,
  loc : @source.SourceLoc,
) -> Unit {
  let is_vla = (match target_type {
      Some(t) => t.is_vla()
      None => false
    }) ||
    (match operand {
      Some(op) => op.ty().is_vla()
      None => false
    })
  if is_vla {
    // VLA sizeof：运行时维度乘积展开（与 emit_vla_alloc 同构）
    let array_info : (Array[Int], Array[@ast.Expr], Int)? = match operand {
      Some(op) =>
        match op.ty() {
          Array(_, _, d2, _, _, vd2) =>
            Some((d2, vd2, self.elem_type_size(op.ty())))
          _ => None
        }
      None =>
        match target_type {
          Some(Array(_, _, d2, _, _, vd2)) => {
            let t = target_type.unwrap()
            Some((d2, vd2, self.elem_type_size(t)))
          }
          _ => None
        }
    }
    match array_info {
      Some((dims, vla_dims, elem_size)) =>
        if dims.length() == 0 {
          self.emit(@opcode.OpCode::PushConst, 0, loc)
        } else {
          let mut vla_idx = 0
          for dim in dims {
            if dim > 0 {
              self.emit(@opcode.OpCode::PushConst, dim, loc)
            } else {
              match vla_dims.get(vla_idx) {
                Some(dim_expr) => {
                  self.gen_expr(dim_expr)
                  vla_idx += 1
                }
                None => self.emit(@opcode.OpCode::PushConst, 0, loc)
              }
            }
          }
          for _j in 1..<dims.length() {
            self.emit(@opcode.OpCode::Mul, 0, loc)
          }
          if elem_size > 1 {
            self.emit(@opcode.OpCode::PushConst, elem_size, loc)
            self.emit(@opcode.OpCode::Mul, 0, loc)
          }
        }
      None => self.emit(@opcode.OpCode::PushConst, 4, loc)
    }
  } else {
    let size = match target_type {
      Some(t) => self.type_size(t)
      None =>
        match operand {
          Some(op) => self.type_size(op.ty())
          None => 0
        }
    }
    self.emit(@opcode.OpCode::PushConst, size, loc)
  }
}

///|
/// C23 alignof（E1）：类型的自然对齐（成员最大自然对齐；VLA 本体按指针
/// 4 字节；packed struct 差异已登记 AGENTS 已知差异清单）。
fn BytecodeGen::gen_alignof_expr(
  self : BytecodeGen,
  target_type : @ast.Type?,
  operand : @ast.Expr?,
  loc : @source.SourceLoc,
) -> Unit {
  let align = match target_type {
    Some(t) => self.type_align(t)
    None =>
      match operand {
        Some(op) => self.type_align(op.ty())
        None => 4
      }
  }
  self.emit(@opcode.OpCode::PushConst, align, loc)
}

///|
fn BytecodeGen::gen_offsetof_expr(
  self : BytecodeGen,
  target_type : @ast.Type,
  field : String,
  loc : @source.SourceLoc,
) -> Unit {
  let mut offset = 0
  let mut found = false
  match self.struct_defs.get(target_type.name()) {
    Some(fields) =>
      for f in fields {
        if f.name == field {
          found = true
          break
        }
        offset += self.type_size(f.ty)
      }
    None =>
      match self.union_defs.get(target_type.name()) {
        Some(fields) =>
          for f in fields {
            if f.name == field {
              found = true
              offset = 0
              break
            }
          }
        None => ()
      }
  }
  if !found {
    self.report_error(
      "offsetof: 未知的结构体/联合体 '\{target_type.name()}' 或字段 '\{field}'",
      loc,
    )
  }
  self.emit(@opcode.OpCode::PushConst, offset, loc)
}

///|
/// Rust `type_align_impl` 照搬：成员最大自然对齐，自含 struct（T-P0-8
/// 同源环）以 visiting 集防递归。
fn BytecodeGen::type_align(self : BytecodeGen, ty : @ast.Type) -> Int {
  type_align_impl(ty, self.struct_defs, self.union_defs, Set::new())
}

///|
fn type_align_impl(
  ty : @ast.Type,
  struct_defs : Map[String, Array[@ast.StructField]],
  union_defs : Map[String, Array[@ast.StructField]],
  visiting : Set[String],
) -> Int {
  match ty.kind() {
    TK_Char => 1
    TK_Double | TK_LongLong => 8
    TK_Array => {
      if ty.is_vla() {
        return 4 // VLA 变量本体按指针存储
      }
      type_align_impl(ty.base_element_type(), struct_defs, union_defs, visiting)
    }
    TK_Struct | TK_Union => {
      let name = ty.name()
      if visiting.contains(name) {
        return 1 // 自含 struct（T-P0-8 同源环）：兜底最小对齐防递归
      }
      let next_visiting = Set::new()
      visiting.each(k => next_visiting.add(k))
      next_visiting.add(name)
      let fields = if ty.kind() is TK_Struct {
        struct_defs.get(name)
      } else {
        union_defs.get(name)
      }
      let align = match fields {
        Some(f) => {
          let mut max = 1
          for field in f {
            let a = type_align_impl(
              field.ty,
              struct_defs,
              union_defs,
              next_visiting,
            )
            if a > max {
              max = a
            }
          }
          if max == 1 {
            4
          } else {
            max
          }
        }
        None => 4
      }
      align
    }
    _ => 4 // Int/Float/Pointer/Function 等
  }
}

///|
/// 赋值/传参侧的隐式转换收口（Rust `gen_expr_with_cast`——二元/赋值批
/// 消费）。
fn BytecodeGen::gen_expr_with_cast(
  self : BytecodeGen,
  expr : @ast.Expr,
  target_ty : @ast.Type,
  loc : @source.SourceLoc,
) -> Unit {
  self.gen_expr(expr)
  let tk = target_ty.kind()
  let ek = expr.ty().kind()
  let target_is_fp = tk is TK_Float || tk is TK_Double
  if tk is TK_Double &&
    !(ek is TK_Float) &&
    !(ek is TK_Double) &&
    !(ek is TK_LongLong) {
    self.emit(@opcode.OpCode::CastI2D, 0, loc)
  } else if tk is TK_Double && ek is TK_Float {
    self.emit(@opcode.OpCode::CastF2D, 0, loc)
  } else if tk is TK_Double && ek is TK_LongLong {
    self.emit(@opcode.OpCode::CastQ2D, 0, loc)
  } else if target_is_fp &&
    !(ek is TK_Float) &&
    !(ek is TK_Double) &&
    !(ek is TK_LongLong) {
    self.emit(@opcode.OpCode::CastI2F, 0, loc)
  } else if !target_is_fp && !(tk is TK_LongLong) && ek is TK_Double {
    self.emit(@opcode.OpCode::CastD2I, 0, loc)
  } else if !target_is_fp && !(tk is TK_LongLong) && ek is TK_Float {
    self.emit(@opcode.OpCode::CastF2I, 0, loc)
  } else if !target_is_fp && !(tk is TK_LongLong) && ek is TK_LongLong {
    self.emit(@opcode.OpCode::CastQ2I, 0, loc)
  }
}
