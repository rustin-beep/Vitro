// 蓝本注记：文内 Rust 源引用（`*.rs` 路径/行号/符号）均为档案态蓝本——tag rust-oracle-freeze（2026-10-05 删区），现为本仓自主基线。

///|
/// 类型转换与编译期尺寸生成（S5 表达式核心批·Cast 28 例 + sizeof 17 例）
/// ——Rust `expr/cast.rs` 全量照搬：10 向转换分派（I2D/F2D/Q2D/I2F/
/// D2F/I2Q/D2Q/D2I/F2I/Q2I）、VLA 的 sizeof 维度展开、alignof（type_align
/// 纯函数随迁——struct/union 成员最大自然对齐 + 自含环检测）、offsetof
/// 编译期偏移、gen_expr_with_cast（赋值/传参侧的隐式转换收口）。
/// #471（2026-11-05）：转换分派单源化——gen_cast_expr 与
/// gen_expr_with_cast 原为两份同构 if-else 链（B1 类冗余，后者还缺
/// LL←D/LL←int 防御臂——typeck insert_implicit_cast 前置插节点使其
/// 不可达，实测零扰动），合一为 emit_conversion 供四处路径共用
///（cast 双链 + var_decl 防御收口 + emit_compound_narrow 域参形态），
/// 并补 fp→**无符号**整型分支（C11 6.3.1.4 域内定义行为——旧一律走
/// 饱和 CastD2I/CastD2Q/F2I 把域内值截成 INT_MAX/INT64_MAX）。
fn BytecodeGen::gen_cast_expr(
  self : BytecodeGen,
  inner : @ast.Expr,
  target_type : @ast.Type,
  loc : @source.SourceLoc,
) -> Unit {
  self.gen_expr(inner)
  let tk = target_type.kind()
  let ik = inner.ty().kind()
  // #238（2026-10-21 千行语料 llm_scale_shell.c 暴露）：`(void)expr` 显式
  // 丢弃值——inner 求值已压栈 1 值，而 gen_expr_stmt 按 `ty is TK_Void`
  // 判「无需 Pop」⇒ 值永久留栈（函数栈不守恒，循环体内无界增长；#200
  // 验证器在 3 个函数上抓到净增 2+2+4 = (void) 个数）。此处求值后立即弹
  // 栈（inner 本身 void 时无值可弹）。
  if tk is TK_Void {
    if !(ik is TK_Void) {
      self.emit(@opcode.OpCode::Pop, 0, loc)
    }
    return
  }
  self.emit_conversion(
    ik,
    tk,
    inner.ty().is_unsigned(),
    target_type.is_unsigned(),
    loc,
  )
}

///|
/// 转换发射单源（#471）：栈顶已压源值，按 (源 kind × 目标 kind × 源
/// unsigned × 目标 unsigned) 发射转换指令序列。unsigned 目标的 fp 源
/// 走 **CastD2UQ**（opcode 156，f64→u64 饱和：域内 [0,2^64) 无损——
/// CastD2Q 在 [2^63,2^64) 段饱和 INT64_MAX 即旧病灶；负值→0、越上界
/// →UINT64_MAX 为 UB 域安全降级）；uint 目标再 CastQ2I 低 32 位截断
///（位模式对 signed/unsigned 通用）。float 源先 CastF2D 归一。signed
/// 目标维持 Rust as 饱和语义（CastD2I/D2Q/F2I）不变。
fn BytecodeGen::emit_conversion(
  self : BytecodeGen,
  ik : @ast.TypeKind,
  tk : @ast.TypeKind,
  inner_u : Bool,
  target_u : Bool,
  loc : @source.SourceLoc,
) -> Unit {
  // u32 源零符号位（病 31）：unsigned int/char 转 Q/D/F 走 U 系对偶
  if tk is TK_Double && ik is TK_Float {
    self.emit(@opcode.OpCode::CastF2D, 0, loc)
  } else if tk is TK_Double && ik is TK_LongLong {
    // #345 审阅 P1（2026-10-28）：u64 位模式无符号源走 UQ 系对偶——旧
    // 无条件 CastQ2D 按有符号解释，(double)18446744073709551615 产 -1
    if inner_u {
      self.emit(@opcode.OpCode::CastUQ2D, 0, loc)
    } else {
      self.emit(@opcode.OpCode::CastQ2D, 0, loc)
    }
  } else if tk is TK_Double && !(ik is TK_Double) {
    // ik ∈ {Int/Char/Pointer}：u32 源走 U 系；ik 已是 Double 则零转换
    if inner_u {
      self.emit(@opcode.OpCode::CastU2D, 0, loc)
    } else {
      self.emit(@opcode.OpCode::CastI2D, 0, loc)
    }
  } else if tk is TK_Float && ik is TK_Double {
    self.emit(@opcode.OpCode::CastD2F, 0, loc)
  } else if tk is TK_Float && ik is TK_LongLong {
    // u64 源 f32 对偶（同 #345 P1）；signed 源经 Q2D+D2F 双跳（#471
    // B 轮连坐：速查表 C1/C11——旧 CastI2F 直喂 i64 栈低 32 位，
    // (float)5000000000LL 产 705032704 位模式值；无 F 直连指令，先
    // Q2D 再 D2F 与 (float)ll 同值路径，尾数舍入差 1ulp 形态登记
    // M12-A2 族的指令面缺口就此闭合）
    if inner_u {
      self.emit(@opcode.OpCode::CastUQ2F, 0, loc)
    } else {
      self.emit(@opcode.OpCode::CastQ2D, 0, loc)
      self.emit(@opcode.OpCode::CastD2F, 0, loc)
    }
  } else if tk is TK_Float && !(ik is TK_Float) {
    // ik ∈ {Int/Char/Pointer}：u32 源走 U 系；ik 已是 Float 则零转换
    if inner_u {
      self.emit(@opcode.OpCode::CastU2F, 0, loc)
    } else {
      self.emit(@opcode.OpCode::CastI2F, 0, loc)
    }
  } else if tk is TK_LongLong && ik is TK_Double {
    // #471：无符号 LL 目标走 D2UQ（1.8e19 ∈ [2^63,2^64) 域内无损）
    if target_u {
      self.emit(@opcode.OpCode::CastD2UQ, 0, loc)
    } else {
      self.emit(@opcode.OpCode::CastD2Q, 0, loc)
    }
  } else if tk is TK_LongLong && ik is TK_Float {
    // #471：F→LL 双跳（F2D 后 D2Q/D2UQ 分符号）——B 轮连坐速查表
    // C2/C10：旧零发射致 f32 位模式直塞 i64 槽（-2.5f 产 -1071644672）
    if target_u {
      self.emit(@opcode.OpCode::CastF2D, 0, loc)
      self.emit(@opcode.OpCode::CastD2UQ, 0, loc)
    } else {
      self.emit(@opcode.OpCode::CastF2D, 0, loc)
      self.emit(@opcode.OpCode::CastD2Q, 0, loc)
    }
  } else if tk is TK_LongLong && !(ik is TK_LongLong) {
    if inner_u {
      self.emit(@opcode.OpCode::CastU2Q, 0, loc)
    } else {
      self.emit(@opcode.OpCode::CastI2Q, 0, loc)
    }
  } else if tk is TK_Char {
    // char 窄化（病 33）：低 8 位按目标 signedness 截断——任意更宽整型
    // 源一律 Trunc（幂等：源 char 已按自身符号扩展，重复截断不变值；
    // (char)200 与 (char)(unsigned char)200 都得 -56）；fp/Q 源先归 i32
    //（uchar 域 [0,256) ⊆ CastD2I 饱和域内段——无需 D2UQ）
    if ik is TK_LongLong {
      self.emit(@opcode.OpCode::CastQ2I, 0, loc)
    } else if ik is TK_Double {
      self.emit(@opcode.OpCode::CastD2I, 0, loc)
    } else if ik is TK_Float {
      self.emit(@opcode.OpCode::CastF2I, 0, loc)
    }
    if target_u {
      self.emit(@opcode.OpCode::TruncUByte, 0, loc)
    } else {
      self.emit(@opcode.OpCode::TruncByte, 0, loc)
    }
  } else if !(tk is TK_Float) &&
    !(tk is TK_Double) &&
    !(tk is TK_LongLong) &&
    ik is TK_Double {
    // #471：uint 目标走 D2UQ+Q2I（3e9 域内无损；CastD2I 饱和 2^31-1
    // 即旧病灶）；signed 目标维持 CastD2I 饱和（Rust as i32 语义）
    if target_u {
      self.emit(@opcode.OpCode::CastD2UQ, 0, loc)
      self.emit(@opcode.OpCode::CastQ2I, 0, loc)
    } else {
      self.emit(@opcode.OpCode::CastD2I, 0, loc)
    }
  } else if !(tk is TK_Float) &&
    !(tk is TK_Double) &&
    !(tk is TK_LongLong) &&
    ik is TK_Float {
    if target_u {
      self.emit(@opcode.OpCode::CastF2D, 0, loc)
      self.emit(@opcode.OpCode::CastD2UQ, 0, loc)
      self.emit(@opcode.OpCode::CastQ2I, 0, loc)
    } else {
      self.emit(@opcode.OpCode::CastF2I, 0, loc)
    }
  } else if !(tk is TK_Float) &&
    !(tk is TK_Double) &&
    !(tk is TK_LongLong) &&
    ik is TK_LongLong {
    // int/uint 目标：低 32 位截断（位模式对 signed/unsigned 通用）
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
    let array_info : (Array[Int32], Array[@ast.Expr], Int32)? = match operand {
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
fn BytecodeGen::type_align(self : BytecodeGen, ty : @ast.Type) -> Int32 {
  type_align_impl(ty, self.struct_defs, self.union_defs, Set([]))
}

///|
fn type_align_impl(
  ty : @ast.Type,
  struct_defs : Map[String, Array[@ast.StructField]],
  union_defs : Map[String, Array[@ast.StructField]],
  visiting : Set[String],
) -> Int32 {
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
      let next_visiting = Set([])
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
/// 消费）。#471 起与 gen_cast_expr 共用 emit_conversion 单源（原两份
/// 同构 if-else 链合一；本链原缺 LL←D / LL←int 防御臂——typeck
/// insert_implicit_cast 前置插节点使其不可达，单源化后自然补齐）。
fn BytecodeGen::gen_expr_with_cast(
  self : BytecodeGen,
  expr : @ast.Expr,
  target_ty : @ast.Type,
  loc : @source.SourceLoc,
) -> Unit {
  self.gen_expr(expr)
  self.emit_conversion(
    expr.ty().kind(),
    target_ty.kind(),
    expr.ty().is_unsigned(),
    target_ty.is_unsigned(),
    loc,
  )
}
