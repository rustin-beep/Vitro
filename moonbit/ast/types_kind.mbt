///|
/// 类型形状判别枚举（16 变体，照搬 Rust `TypeKind`——vitro_ast types.rs:9-28）。
///
/// **S4 裁定引入**（S3 决策登记"TypeKind 待 typeck 大面积 kind 消费再独立
/// 裁定"——typeck 包 convert/expr/decl/init 全程 kind 分派，消费面成立）：
/// 变体取 `TK_` 前缀而非与 `Type` 构造器同名——同名形态在 MoonBit 需要
/// 全程 `TypeKind::Int` 双重限定（陷阱 4），前缀式在模式匹配里更直接
///（Rust 的 `TypeKind::Int` 消费点对应本包 `TK_Int`——名字变形登记，
/// 语义逐臂照搬）。
///
/// **Typeof 投影为 Auto**（Rust kind() 现状照搬）：两者在 kind 层共享
/// 形状（"待定型"），语义区分发生在 typeck 的 typeof 解析期。
pub enum TypeKind {
  TK_Void
  TK_Int
  TK_Char
  TK_Float
  TK_Double
  TK_LongLong
  TK_Pointer
  TK_Array
  TK_Struct
  TK_Union
  TK_Function
  TK_Class
  TK_Reference
  TK_RValueRef
  TK_Auto
  TK_TemplateId
} derive(Eq, Compare, Hash)

///|
/// Type → TypeKind 投影（穷尽 17 臂无兜底——加 Type 变体必须表态 kind，
/// 编译期强制；Rust kind() 同构，Typeof → TK_Auto）。
pub fn Type::kind(self : Type) -> TypeKind {
  match self {
    Void(_) => TK_Void
    Int(_, _) => TK_Int
    Char(_, _) => TK_Char
    Float(_) => TK_Float
    Double(_) => TK_Double
    LongLong(_, _) => TK_LongLong
    Pointer(_, _) => TK_Pointer
    Array(_, _, _, _, _, _) => TK_Array
    Function(_, _, _, _) => TK_Function
    Struct(_, _) => TK_Struct
    Union(_, _) => TK_Union
    Class(_, _) => TK_Class
    Reference(_, _) => TK_Reference
    RValueRef(_) => TK_RValueRef
    Auto => TK_Auto
    Typeof(_, _, _) => TK_Auto
    TemplateId(_, _, _) => TK_TemplateId
  }
}

///|
/// 是否带 unsigned 修饰（Int/Char/LongLong 三变体；其余恒 false——
/// Rust `to.is_unsigned()` 口径）。
pub fn Type::is_unsigned(self : Type) -> Bool {
  match self {
    Int(is_unsigned, _) | Char(is_unsigned, _) | LongLong(is_unsigned, _) =>
      is_unsigned
    _ => false
  }
}

///|
/// `base_kind`（Rust `type_utils::base_kind` 逐字照搬：Pointer 只解
/// **一层**取 pointee.kind()、Array 递归剥层）——与 `immediate_base_kind`
/// 的差异仅在 Array：base_kind(char[3]) = Char 递归到底；
/// base_kind(char**) = Pointer（不再解第二层）。
///
/// **单源上提登记（S6 vm 批二号，2026-09-25）**：原 priv 在 L6 codegen
/// （func.mbt）；vm 执行器的 trap 文案渲染（数组越界的元素步长）与 codegen
/// 的 elem_type_size 需同一口径，跨 L6/L7 复用故上提至本包（Type 谓词面
/// 的伴生方法）——Rust 侧同名函数在 `vitro_runtime::type_utils`，同为
/// codegen/host/vm 三方共用单源。
pub fn Type::base_kind(self : Type) -> TypeKind {
  match self {
    Pointer(pointee, _) => pointee.kind()
    Array(element, _, _, _, _, _) => Type::base_kind(element)
    _ => self.kind()
  }
}
