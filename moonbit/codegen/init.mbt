///|
/// C 字符串字节通道（P4 口径照搬——Rust `vitro_shared::cstring`）：
/// **码点 ≤ 0xFF 的字符按 Latin-1 单字节写出，> 0xFF 的按 UTF-8 编码写出**。
/// 无歧义依据：源文件按 UTF-8 解码，多字节源字符码点必然 > 0xFF；码点
/// 落在 U+0080..=U+00FF 的只可能来自 `\xHH` 转义。已知差异（诚实记录）：
/// 源内直接书写的高位单字节字符写单字节，与 clang UTF-8 execution
/// charset 不同；中文等多字节源字符不受影响，按 UTF-8 写。
fn cstring_bytes(s : String) -> Array[Byte] {
  let out : Array[Byte] = []
  for c in s {
    let cp = c.to_int()
    if cp <= 0xFF {
      out.push(cp.to_byte())
    } else {
      // 码点 > 0xFF：按 UTF-8 编码写出（2~4 字节）
      for b in @utf8.encode(c.to_string()) {
        out.push(b)
      }
    }
  }
  out
}

///|
/// C 语义字节长度（不含结尾 NUL）——分配/对齐计算用。与 MoonBit
/// `String::length()`（UTF-16 码元数）在含 `\xHH ≥ 0x80` 转义时不同（F2）。
fn cstring_len(s : String) -> Int {
  let mut total = 0
  for c in s {
    let cp = c.to_int()
    if cp <= 0xFF {
      total += 1
    } else {
      total += @utf8.encode(c.to_string()).length()
    }
  }
  total
}

///|
/// 字面量的数值形态：整数走 Int64（f64 只有 53 位尾数丢精度），浮点走 Double。
enum LitNum {
  LN_I(Int64)
  LN_F(Double)
}

///|
fn lit_num(expr : @ast.Expr) -> LitNum? {
  match expr {
    // typeck 的 insert_implicit_cast 会把初始化元素包装为 Cast{Literal}，
    // 剥开后按内层字面量取值（Cast 语义 = 转换为目标类型，与本函数编码一致）
    Cast(inner, _, _, _) => lit_num(inner)
    Literal(value, _, _) => Some(LN_I(value.to_int64()))
    LongLiteral(value, _, _) => Some(LN_I(value))
    FloatLiteral(value, _, _) => Some(LN_F(value))
    Unary(@ast.UnaryOp::Neg, operand, _, _) =>
      match lit_num(operand) {
        Some(LN_I(v)) => Some(LN_I(v.neg()))
        Some(LN_F(v)) => Some(LN_F(-v))
        None => None
      }
    _ => None
  }
}

///|
/// T-P0-1/T-P0-2：初始化字面量按**目标类型**编码为全局初始化位模式。
/// 返回 `(位模式, 是否 8 字节槽)`；非字面量返回 None。
///
/// Rust 侧 `(v as i64) as u64` / `(v as f64).to_bits()` 等位模式转换，
/// MoonBit 对应：Int64→UInt64 位重解释 `reinterpret_as_uint64`；Double
/// →UInt64 `reinterpret_as_uint64`；f32 位模式 Float::from_double +
/// reinterpret_as_uint。
fn literal_init_bits(
  expr : @ast.Expr,
  target_kind : @ast.TypeKind,
) -> (UInt64, Bool)? {
  let num = match lit_num(expr) {
    Some(n) => n
    None => return None
  }
  Some(
    match (num, target_kind) {
      (LN_I(v), TK_Double) => (v.to_double().reinterpret_as_uint64(), true)
      (LN_I(v), TK_Float) =>
        (f32_bits_u64(Float::from_double(v.to_double())), false)
      // T-P0-2 根因：long long 目标必须写 i64 位模式，而非 f64 位模式
      (LN_I(v), TK_LongLong) => (v.reinterpret_as_uint64(), true)
      (LN_I(v), _) =>
        (v.to_int32_bits().reinterpret_as_uint().to_uint64(), false)
      (LN_F(v), TK_Double) => (v.reinterpret_as_uint64(), true)
      (LN_F(v), TK_Float) => (f32_bits_u64(Float::from_double(v)), false)
      (LN_F(v), TK_LongLong) => (v.to_int64().reinterpret_as_uint64(), true)
      (LN_F(v), _) => (v.to_int().reinterpret_as_uint().to_uint64(), false)
    },
  )
}

///|
/// Float 位模式 → UInt64（低 32 位）。
fn f32_bits_u64(f : Float) -> UInt64 {
  Float::reinterpret_as_uint(f).to_uint64()
}

///|
/// Int64 → 低 32 位 i32 截断（符号解释）——parser/decl.mbt `i64_to_i32_bits`
/// 同款语义；Rust `v as i32`。位模式：先重解释为 UInt64 取低 32 位。
fn Int64::to_int32_bits(v : Int64) -> Int {
  let low = v.reinterpret_as_uint64() & 0xFFFFFFFFUL
  if low >= 0x80000000UL {
    (low.to_int64() - 0x100000000L).to_int()
  } else {
    low.to_int64().to_int()
  }
}

///|
/// （Double→Int64 用 core 内置 `Double::to_int64`——js/wasm 后端实现；
/// 与 Rust `as i64` 的饱和语义在越界/NaN 边界可能有差，本函数仅服务
/// LN_F→TK_LongLong 罕见路径（double 字面量初始化 long long，值域小），/// 差异随差分对拍暴露再登记。）

///|
fn BytecodeGen::push_literal_init(
  self : BytecodeGen,
  offset : UInt,
  expr : @ast.Expr,
  target_ty : @ast.Type,
) -> Bool {
  match literal_init_bits(expr, target_ty.kind()) {
    Some(pair) => {
      let (bits, is64) = pair
      if is64 {
        self.globals_init_64.push((offset, bits))
      } else {
        self.globals_init_32.push((offset, bits.to_int64().to_int()))
      }
      true
    }
    None => false
  }
}

///|
/// 嵌套 InitList → globals_init_32/64 递归展开（全局变量初始化）。
/// C only：class 分支不迁移（Rust init.rs:74-89 对应段）。
fn BytecodeGen::flatten_global_init(
  self : BytecodeGen,
  target_ty : @ast.Type,
  init : @ast.Expr,
  base_offset : UInt,
) -> Unit {
  match init {
    InitList(elements, _, _) =>
      if target_ty.kind() is TK_Struct {
        let fields = match self.struct_defs.get(target_ty.name()) {
          Some(f) => f
          None => []
        }
        for i, elem in elements {
          if i >= fields.length() {
            break
          }
          let mut field_offset = 0
          for j in 0..<i {
            field_offset += self.type_size(fields[j].ty)
          }
          self.flatten_global_init(
            fields[i].ty,
            elem.value,
            base_offset + field_offset.reinterpret_as_uint(),
          )
        }
      } else if target_ty.is_array() {
        let inner_ty = target_ty.subscript_type()
        let elem_size = self.type_size(inner_ty)
        for i, elem in elements {
          self.flatten_global_init(
            inner_ty,
            elem.value,
            base_offset + (i * elem_size).reinterpret_as_uint(),
          )
        }
      } else if elements.length() > 0 {
        self.flatten_global_init(target_ty, elements[0].value, base_offset)
      }
    _ =>
      // T-P0-1/T-P0-2：标量字面量（含负字面量）统一按目标类型编码位模式
      if !self.push_literal_init(base_offset, init, target_ty) {
        match init {
          Identifier(name, _, _) =>
            match self.func_index.get(name) {
              Some(idx) => self.globals_init_32.push((base_offset, idx))
              None => ()
            }
          StringLiteral(value, _, _) =>
            // 延迟到 Pass 1 结束后分配地址，确保字符串区位于全局变量区之后
            self.pending_string_inits.push((base_offset, value))
          _ => ()
        }
      }
  }
}

///|
/// 扁平化初始化列表为 i32 数组（char 数组 / 简单数组路径）。
/// **照搬含静默 0 兜底**（`_ => push(0)`——勘察事故 #17 登记的反模式，
/// Rust 现状如此，迁移期不私改；S5 后续批随"无条件 gen_expr"改造收口）。
fn flatten_init_list(
  elements : Array[@ast.InitElement],
  errors : Array[String],
) -> Array[Int] {
  let result : Array[Int] = []
  for elem in elements {
    if elem.designators.length() > 0 {
      errors.push("Designated initializer 不支持在此上下文中扁平化")
    }
    match elem.value {
      Literal(value, _, _) => result.push(value)
      LongLiteral(value, _, _) =>
        if value < -2147483648L || value > 2147483647L {
          errors.push(
            "初始化列表中的 long long 常量 \{value} 超出 int 范围，无法用于此上下文",
          )
          result.push(0)
        } else {
          result.push(value.to_int())
        }
      FloatLiteral(value, _, _) =>
        result.push(
          Float::from_double(value)
          |> Float::reinterpret_as_uint
          |> UInt::to_int,
        )
      InitList(inner, _, _) => {
        let sub = flatten_init_list(inner, errors)
        for v in sub {
          result.push(v)
        }
      }
      Unary(@ast.UnaryOp::Neg, operand, _, _) =>
        match operand {
          Literal(value, _, _) => result.push(-value)
          LongLiteral(value, _, _) =>
            if value < -2147483648L || value > 2147483647L {
              errors.push(
                "初始化列表中的 long long 常量 \{value} 超出 int 范围，无法用于此上下文",
              )
              result.push(0)
            } else {
              result.push((-value).to_int())
            }
          _ => result.push(0)
        }
      _ => result.push(0)
    }
  }
  result
}

///|
/// 数组 stride 计算（Rust init.rs:200 照搬：i32 溢出返 0 哨兵）。
fn compute_stride(arr_type : @ast.Type, elem_size : Int) -> Int {
  if arr_type.is_array() && arr_type.dims().length() > 0 {
    let mut stride = elem_size
    let dims = arr_type.dims()
    for i in 1..<dims.length() {
      let dim = dims[i]
      if dim <= 0 {
        // 非正维度 = VLA（运行时处理）或损坏 AST：0 哨兵
        return 0
      }
      let mul = stride.to_int64() * dim.to_int64()
      if mul > 2147483647L || mul < -2147483648L || mul == 0 {
        return 0
      }
      stride = mul.to_int()
    }
    stride
  } else {
    match arr_type {
      Pointer(pointee, _) =>
        if pointee.is_array() && pointee.dims().length() > 0 {
          let mut stride = elem_size
          let dims = pointee.dims()
          for i in 0..<dims.length() {
            let dim = dims[i]
            if dim <= 0 {
              return 0
            }
            let mul = stride.to_int64() * dim.to_int64()
            if mul > 2147483647L || mul < -2147483648L || mul == 0 {
              return 0
            }
            stride = mul.to_int()
          }
          stride
        } else {
          elem_size
        }
      _ => elem_size
    }
  }
}

///|
/// 语句源位置（Rust init.rs:131 照搬；C++ 变体在 C only 下走默认值）。
fn stmt_loc(stmt : @ast.Stmt) -> @source.SourceLoc {
  match stmt {
    Block(_, loc) => loc
    VarDecl(_, _, _, _, _, loc) => loc
    Expr(_, loc) => loc
    If(_, _, _, loc) => loc
    While(_, _, loc) => loc
    DoWhile(_, _, loc) => loc
    For(_, _, _, _, loc) => loc
    Return(_, loc) => loc
    Break(loc) => loc
    Continue(loc) => loc
    Switch(_, _, loc) => loc
    Case(_, _, loc) => loc
    Goto(_, loc) => loc
    Label(_, _, loc) => loc
    _ => default_loc()
  }
}
