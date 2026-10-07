///|
/// 数组索引与成员访问（S5 扩展批四号·Index/Member——剩余面主要拦截者）
/// ——Rust `expr.rs` 的 gen_index/gen_vla_stride/gen_member_addr 与
/// `expr/struct_.rs::gen_member_expr`、`lib.rs::get_member_offset` 的
/// C only 子集照搬。C only 裁剪：lambda by-ref 捕获段 / Class /
/// Reference 分支不迁移。~~Rust 现状缺口照搬登记：gen_member_addr 的
/// Identifier 分支无 static_local_indices~~ **static 分支已补（批四
/// 2026-10-07，DIFF-CODEGEN-STATIC-ADDR-01 销案——与 gen_addr 同族）**。

///|
/// 成员字节偏移（Rust lib.rs:761-808 的 C only 子集：union 全 0 /
/// struct 顺序累加 / 指针到 struct 一步解引用——只解一层）。
fn BytecodeGen::get_member_offset(
  self : BytecodeGen,
  object_type : @ast.Type,
  mname : String,
) -> Int {
  match object_type.kind() {
    TK_Union => 0 // union 成员全在偏移 0
    TK_Struct => self.struct_field_offset_by_name(object_type.name(), mname)
    TK_Pointer =>
      if @ast.Type::base_kind(object_type) is TK_Struct {
        self.struct_field_offset_by_name(object_type.name(), mname)
      } else {
        0
      }
    _ => 0
  }
}

// ── 成员偏移单源（G-5，总计划 §10.5；kimicc FieldLayout/offset_of_path
// 单点先例）——消三份独立累加：get_member_offset 的 struct/pointer 双臂
// 与 addr.mbt gen_nested_init 初始化器前缀和。行为等价重构（原「累加
// 遍历命中返回」≡「按位前缀和」），A 级对拍全量兜底。 ──

///|
/// 按结构体名取成员偏移（字段表缺失返 0——照搬原分支语义）。
fn BytecodeGen::struct_field_offset_by_name(
  self : BytecodeGen,
  struct_name : String,
  mname : String,
) -> Int {
  match self.struct_defs.get(struct_name) {
    Some(fields) => self.struct_fields_offset_by_name(fields, mname)
    None => 0
  }
}

///|
/// 字段表内按名定位并返回其前缀偏移；直查未命中时经匿名字段
///（name == ""，C11 匿名成员）穿透——外层前缀偏移 + 内层偏移递归
///（issue #7 销案，2026-10-06；内层 union 成员偏移恒 0）。
fn BytecodeGen::struct_fields_offset_by_name(
  self : BytecodeGen,
  fields : Array[@ast.StructField],
  mname : String,
) -> Int {
  for i, field in fields {
    if field.name == mname {
      return self.struct_fields_prefix_offset(fields, i)
    }
  }
  match self.anon_field_offset(fields, mname, 0) {
    Some(off) => off
    None => 0
  }
}

///|
/// 匿名成员穿透偏移（codegen 侧，与 typeck find_anonymous_member 同语义）：
/// 在匿名字段的聚合内递归查找 mname，返回 相对 fields 的绝对偏移；
/// depth 上限 8 防循环定义。Option 区分命中与「偏移恰为 0」。
fn BytecodeGen::anon_field_offset(
  self : BytecodeGen,
  fields : Array[@ast.StructField],
  mname : String,
  depth : Int,
) -> Int? {
  if depth >= 8 {
    return None
  }
  for i, field in fields {
    if field.name != "" {
      continue
    }
    let base = self.struct_fields_prefix_offset(fields, i)
    let k = field.ty.kind()
    if k is TK_Struct {
      match self.struct_defs.get(field.ty.name()) {
        Some(inner) =>
          // 内层直查 + 内层再匿名，同一递归入口（struct_fields_offset_by_name
          // 已含直查与穿透）
          match
            self.struct_fields_offset_by_name_with_hit(inner, mname, depth + 1) {
            Some(off) => return Some(base + off)
            None => ()
          }
        None => ()
      }
    } else if k is TK_Union {
      match self.union_defs.get(field.ty.name()) {
        Some(inner) => {
          // union 成员偏移恒 0：内层直名命中即 base；内层匿名字段再穿透
          for f2 in inner {
            if f2.name == mname {
              return Some(base)
            }
          }
          match self.anon_field_offset(inner, mname, depth + 1) {
            Some(off) => return Some(base + off)
            None => ()
          }
        }
        None => ()
      }
    }
  }
  None
}

///|
/// struct_fields_offset_by_name 的命中可判版（Option 区分命中与 0 偏移）。
fn BytecodeGen::struct_fields_offset_by_name_with_hit(
  self : BytecodeGen,
  fields : Array[@ast.StructField],
  mname : String,
  depth : Int,
) -> Int? {
  for i, field in fields {
    if field.name == mname {
      return Some(self.struct_fields_prefix_offset(fields, i))
    }
  }
  self.anon_field_offset(fields, mname, depth)
}

///|
/// 前 index 个字段的尺寸和（初始化器按位取偏移的共用单点）。
fn BytecodeGen::struct_fields_prefix_offset(
  self : BytecodeGen,
  fields : Array[@ast.StructField],
  index : Int,
) -> Int {
  let mut offset = 0
  for j in 0..<index {
    offset += self.type_size(fields[j].ty)
  }
  offset
}

///|
/// 成员访问表达式（读）：地址 + 按成员类型 load（数组成员不 load——
/// 地址即值，供后续索引）。
fn BytecodeGen::gen_member_expr(
  self : BytecodeGen,
  object : @ast.Expr,
  mname : String,
  ty : @ast.Type,
  loc : @source.SourceLoc,
) -> Unit {
  self.gen_member_addr(object, mname, loc)
  // lambda by-ref 捕获指针解引用段不迁移（C only）
  if !ty.is_array() {
    if ty.kind() is TK_Char {
      self.emit(@opcode.OpCode::LoadMemByte, 0, loc)
    } else if ty.kind() is TK_Double {
      self.emit(@opcode.OpCode::LoadMemD, 0, loc)
    } else if ty.kind() is TK_LongLong {
      self.emit(@opcode.OpCode::LoadMemQ, 0, loc)
    } else {
      self.emit(@opcode.OpCode::LoadMem, 0, loc)
    }
  }
}

///|
/// 成员地址：指针对象先求值（p->x 的 p）→ 数组元素/嵌套成员递归 →
/// 变量取址（local/global；**static 缺口照搬**——见文件头注释）→
/// struct 返回值透传 → 偏移加法。
fn BytecodeGen::gen_member_addr(
  self : BytecodeGen,
  object : @ast.Expr,
  mname : String,
  loc : @source.SourceLoc,
) -> Unit {
  if object.ty().kind() is TK_Pointer {
    self.gen_expr(object)
  } else {
    match object {
      Index(array, index, _, result_ty) =>
        self.gen_index(array, index, result_ty, loc, true)
      Member(inner, m, _, _) => self.gen_member_addr(inner, m, loc)
      Identifier(name, _, _) =>
        match self.local_indices.get(name) {
          Some(offset) => {
            self.emit(@opcode.OpCode::GetFrameBase, 0, loc)
            self.emit(@opcode.OpCode::PushConst, offset, loc)
            self.emit(@opcode.OpCode::Add, 0, loc)
          }
          None =>
            match self.global_indices.get(name) {
              Some(offset) =>
                self.emit(
                  @opcode.OpCode::PushConst,
                  @bytecode.GLOBAL_START.reinterpret_as_int() + offset,
                  loc,
                )
              None =>
                match self.static_local_indices.get(name) {
                  // static 局部分支（批四 2026-10-07 销案——同 gen_addr）
                  Some(offset) =>
                    self.emit(
                      @opcode.OpCode::PushConst,
                      @bytecode.GLOBAL_START.reinterpret_as_int() + offset,
                      loc,
                    )
                  None => {
                    self.report_error("未声明的结构体变量", loc)
                    self.emit(@opcode.OpCode::PushConst, 0, loc)
                  }
                }
            }
        }
      _ =>
        if object.ty().kind() is TK_Struct {
          // 函数按值返回 struct 等复杂表达式：gen_expr 留下地址
          self.gen_expr(object)
        } else {
          self.report_error("复杂结构体表达式暂不支持", loc)
          self.emit(@opcode.OpCode::PushConst, 0, loc)
        }
    }
  }
  let offset = self.get_member_offset(object.ty(), mname)
  if offset > 0 {
    self.emit(@opcode.OpCode::PushConst, offset, loc)
    self.emit(@opcode.OpCode::Add, 0, loc)
  }
}

///|
/// 数组索引：边界检查（TrapBounds 携符号索引或负界）+ 步长缩放 + 地址
/// 加法；is_assign=true 时留地址不 load（赋值左值/取址共用）。
fn BytecodeGen::gen_index(
  self : BytecodeGen,
  array : @ast.Expr,
  index : @ast.Expr,
  result_ty : @ast.Type,
  loc : @source.SourceLoc,
  is_assign : Bool,
) -> Unit {
  let mut bound_size = -1
  let mut sym_idx = -1
  match array {
    Identifier(name, _, _) => {
      let ty_opt = match self.local_types.get(name) {
        Some(t) => Some(t)
        None => self.global_types.get(name)
      }
      match ty_opt {
        Some(ty) =>
          if ty.is_array() {
            bound_size = if ty.dims().length() == 0 {
              ty.array_size()
            } else {
              ty.dims()[0]
            }
            sym_idx = self.resolve_symbol_index(name)
          }
        None => ()
      }
    }
    Index(_, _, _, _) =>
      if array.ty().is_array() && array.ty().dims().length() > 0 {
        bound_size = array.ty().dims()[0]
      }
    _ => ()
  }
  let stride = compute_stride(array.ty(), self.elem_type_size(array.ty()))
  if stride == 0 && !array.ty().is_vla() {
    self.report_error(
      "数组索引步长计算失败：存在无效维度", loc,
    )
  }
  self.gen_expr(array)
  self.gen_expr(index)
  if bound_size > 0 {
    if sym_idx >= 0 {
      self.emit(@opcode.OpCode::TrapBounds, sym_idx, loc)
    } else {
      self.emit(@opcode.OpCode::TrapBounds, -bound_size, loc)
    }
  }
  if stride > 0 {
    self.emit(@opcode.OpCode::PushConst, stride, loc)
  } else if array.ty().is_vla() {
    self.gen_vla_stride(array.ty(), loc)
  } else {
    self.emit(@opcode.OpCode::PushConst, self.elem_type_size(array.ty()), loc)
  }
  self.emit(@opcode.OpCode::Mul, 0, loc)
  self.emit(@opcode.OpCode::Add, 0, loc)
  if !is_assign && !result_ty.is_array() {
    if result_ty.kind() is TK_Char {
      self.emit(@opcode.OpCode::LoadMemByte, 0, loc)
    } else if result_ty.kind() is TK_Double {
      self.emit(@opcode.OpCode::LoadMemD, 0, loc)
    } else if result_ty.kind() is TK_LongLong {
      self.emit(@opcode.OpCode::LoadMemQ, 0, loc)
    } else {
      self.emit(@opcode.OpCode::LoadMem, 0, loc)
    }
  }
}

///|
/// VLA 步长运行时求值：首维后的维度乘积 × 元素尺寸（首维不计——
/// 步长是"跨一个首维元素"的字节数）。
fn BytecodeGen::gen_vla_stride(
  self : BytecodeGen,
  arr_type : @ast.Type,
  loc : @source.SourceLoc,
) -> Unit {
  match arr_type {
    Array(_, _, dims, _, _, vla_dims) => {
      let mut vla_idx = 0
      let take = if 1 < dims.length() { 1 } else { dims.length() }
      for j in 0..<take {
        if dims[j] == 0 {
          vla_idx += 1
        }
      }
      let mut first = true
      for k in 1..<dims.length() {
        if !first {
          self.emit(@opcode.OpCode::Mul, 0, loc)
        }
        if dims[k] > 0 {
          self.emit(@opcode.OpCode::PushConst, dims[k], loc)
        } else {
          match vla_dims.get(vla_idx) {
            Some(dim_expr) => {
              self.gen_expr(dim_expr)
              vla_idx += 1
            }
            None => self.emit(@opcode.OpCode::PushConst, 0, loc)
          }
        }
        first = false
      }
      let elem_size = self.elem_type_size(arr_type)
      if first {
        self.emit(@opcode.OpCode::PushConst, elem_size, loc)
      } else {
        self.emit(@opcode.OpCode::PushConst, elem_size, loc)
        self.emit(@opcode.OpCode::Mul, 0, loc)
      }
    }
    _ =>
      self.emit(@opcode.OpCode::PushConst, self.elem_type_size(arr_type), loc)
  }
}
