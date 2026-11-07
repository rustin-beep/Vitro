// 蓝本注记：文内 Rust 源引用（`*.rs` 路径/行号/符号）均为档案态蓝本——tag rust-oracle-freeze（2026-10-05 删区），现为本仓自主基线。

///|
/// 二元运算符（19 个，照搬 Rust BinaryOp）。
#derive(Debug, Eq, Compare)
pub(all) enum BinaryOp {
  Add
  Sub
  Mul
  Div
  Mod
  Eq
  Ne
  Lt
  Le
  Gt
  Ge
  And
  Or
  BitAnd
  BitOr
  BitXor
  Shl
  Shr
  Comma
}

///|
pub extend BinaryOp with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend BinaryOp with Debug::{to_repr}

///|
pub extend BinaryOp with Eq::{not_equal, equal}

///|
/// 一元运算符（9 个，照搬 Rust UnaryOp）。
#derive(Debug, Eq, Compare)
pub(all) enum UnaryOp {
  Neg
  /// 一元 +（#71 病 39，2026-10-11——恒等操作数：类型/值原样，仅词法合法化）
  Pos
  Not
  BitNot
  Addr
  Deref
  PreInc
  PreDec
  PostInc
  PostDec
}

///|
pub extend UnaryOp with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend UnaryOp with Debug::{to_repr}

///|
pub extend UnaryOp with Eq::{not_equal, equal}

///|
/// 赋值运算符（11 个，照搬 Rust AssignOp）。
#derive(Debug, Eq, Compare)
pub(all) enum AssignOp {
  Assign
  AddAssign
  SubAssign
  MulAssign
  DivAssign
  ModAssign
  AndAssign
  OrAssign
  XorAssign
  ShlAssign
  ShrAssign
}

///|
pub extend AssignOp with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend AssignOp with Debug::{to_repr}

///|
pub extend AssignOp with Eq::{not_equal, equal}

///|
/// 初始化器指派符（designated initializer）。
#derive(Debug)
pub(all) enum Designator {
  Field(String)
  Index(Expr)
}

///|
pub extend Designator with Debug::{to_repr}

///|
/// 初始化列表元素（指派符序列 + 值）。
#derive(Debug)
pub(all) struct InitElement {
  designators : Array[Designator]
  value : Expr
}

///|
pub extend InitElement with Debug::{to_repr}

///|
/// 表达式节点（26 变体，历史蓝本 Rust `vitro_ast/src/expr.rs`，tag
/// rust-oracle-freeze；每节点携带 `@source.SourceLoc` 与推导后 `Type`——
/// typeck 前的 ty 为 Void 默认值）。
///
/// 字段序即 E1 dump 键序（Binary: op, left, right, loc, ty；沿用历史蓝本
/// serde 字段序，canonicalize 归一后锁 golden）。
#derive(Debug)
pub(all) enum Expr {
  Binary(BinaryOp, Expr, Expr, @source.SourceLoc, Type)
  Unary(UnaryOp, Expr, @source.SourceLoc, Type)
  Literal(Int32, @source.SourceLoc, Type) // value
  FloatLiteral(Double, @source.SourceLoc, Type) // value
  LongLiteral(Int64, @source.SourceLoc, Type) // value
  // value 承载契约（B6 批 #429 起）：**码元=字节**（Latin-1 双射）——
  // 解码层（scanner/string.mbt）产码元=字节值（hex/八进制转义）或按
  // UTF-8 字节拆装（非转义源字符），码元数即 C 字节数（NUL 终止符
  // 不含）；计长（typeck/parser）、装载（bytecode/cstring）、E1 dump
  // 三层同口径消费。码元 > 0xFF 属越约定输入（引擎路径不可达）。
  StringLiteral(String, @source.SourceLoc, Type) // value
  Identifier(String, @source.SourceLoc, Type) // name
  Call(String, Array[Expr], @source.SourceLoc, Type) // name, args
  CallPtr(Expr, Array[Expr], @source.SourceLoc, Type) // callee, args
  Index(Expr, Expr, @source.SourceLoc, Type) // array, index
  Member(Expr, String, Bool, @source.SourceLoc, Type) // object, member, is_arrow（#134：. 与 -> 运算符位）
  Assign(AssignOp, Expr, Expr, @source.SourceLoc, Type)
  Ternary(Expr, Expr, Expr, @source.SourceLoc, Type) // cond, then, else
  Sizeof(Type?, Expr?, @source.SourceLoc, Type) // target_type, operand
  /// C23 `_Alignof` / `alignof`：取成员最大自然对齐（packed 布局差异
  /// 已在 spec 记录——照搬 Rust 侧注释语义）。
  Alignof(Type?, Expr?, @source.SourceLoc, Type)
  Cast(Expr, Type, @source.SourceLoc, Type) // expr, target_type
  InitList(Array[InitElement], @source.SourceLoc, Type)
  Offsetof(Type, String, @source.SourceLoc, Type) // target_type, field
  Generic(Expr, Array[(Type, Expr)], Expr?, @source.SourceLoc, Type) // control, associations, default
  CompoundLiteral(Type, Expr, @source.SourceLoc, Type) // target_type, init
  // === C++ 新增 ===
  This(@source.SourceLoc, Type)
  MemberCall(Expr, String, Array[Expr], Bool, String?, @source.SourceLoc, Type) // object, method, args, is_virtual, resolved_mangled
  New(Type, Expr?, Expr?, @source.SourceLoc, Type) // elem_type, size_expr, init
  Delete(Expr, Bool, @source.SourceLoc, Type) // expr, is_array
  Lambda(
    Array[CaptureMode],
    Array[Param],
    Stmt,
    UInt32,
    @source.SourceLoc,
    Type
  ) // capture, params, body, unique_id
  Move(Expr, @source.SourceLoc, Type)
}

///|
pub extend Expr with Debug::{to_repr}

///|
/// 表达式的源位置（Rust expr_field! 宏的单点等价）。
pub fn Expr::loc(self : Expr) -> @source.SourceLoc {
  match self {
    Binary(_, _, _, loc, _)
    | Unary(_, _, loc, _)
    | Literal(_, loc, _)
    | FloatLiteral(_, loc, _)
    | LongLiteral(_, loc, _)
    | StringLiteral(_, loc, _)
    | Identifier(_, loc, _)
    | Call(_, _, loc, _)
    | CallPtr(_, _, loc, _)
    | Index(_, _, loc, _)
    | Member(_, _, _, loc, _)
    | Assign(_, _, _, loc, _)
    | Ternary(_, _, _, loc, _)
    | Sizeof(_, _, loc, _)
    | Alignof(_, _, loc, _)
    | Cast(_, _, loc, _)
    | InitList(_, loc, _)
    | Offsetof(_, _, loc, _)
    | Generic(_, _, _, loc, _)
    | CompoundLiteral(_, _, loc, _)
    | This(loc, _)
    | MemberCall(_, _, _, _, _, loc, _)
    | New(_, _, _, loc, _)
    | Delete(_, _, loc, _)
    | Lambda(_, _, _, _, loc, _)
    | Move(_, loc, _) => loc
  }
}

///|
/// 表达式的推导类型。
pub fn Expr::ty(self : Expr) -> Type {
  match self {
    Binary(_, _, _, _, ty)
    | Unary(_, _, _, ty)
    | Literal(_, _, ty)
    | FloatLiteral(_, _, ty)
    | LongLiteral(_, _, ty)
    | StringLiteral(_, _, ty)
    | Identifier(_, _, ty)
    | Call(_, _, _, ty)
    | CallPtr(_, _, _, ty)
    | Index(_, _, _, ty)
    | Member(_, _, _, _, ty)
    | Assign(_, _, _, _, ty)
    | Ternary(_, _, _, _, ty)
    | Sizeof(_, _, _, ty)
    | Alignof(_, _, _, ty)
    | Cast(_, _, _, ty)
    | InitList(_, _, ty)
    | Offsetof(_, _, _, ty)
    | Generic(_, _, _, _, ty)
    | CompoundLiteral(_, _, _, ty)
    | This(_, ty)
    | MemberCall(_, _, _, _, _, _, ty)
    | New(_, _, _, _, ty)
    | Delete(_, _, _, ty)
    | Lambda(_, _, _, _, _, ty)
    | Move(_, _, ty) => ty
  }
}
