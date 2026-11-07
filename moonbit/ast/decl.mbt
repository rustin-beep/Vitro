// 蓝本注记：文内 Rust 源引用（`*.rs` 路径/行号/符号）均为档案态蓝本——tag rust-oracle-freeze（2026-10-05 删区），现为本仓自主基线。

///|
/// 函数参数（C++ 默认参数表达式仅用于函数/方法/构造函数声明）。
#derive(Debug, Default)
pub(all) struct Param {
  ty : Type
  name : String
  loc : @source.SourceLoc
  default : Expr?
}

///|
pub extend Param with Debug::{to_repr}

///|
pub extend Param with Default::{default}

///|
/// 函数声明。
#derive(Debug, Default)
pub(all) struct FuncDecl {
  loc : @source.SourceLoc
  return_type : Type
  name : String
  params : Array[Param]
  body : Stmt?
  is_static : Bool
  is_extern : Bool
  source_file : String
  is_variadic : Bool
}

///|
pub extend FuncDecl with Debug::{to_repr}

///|
pub extend FuncDecl with Default::{default}

///|
/// struct 字段。
#derive(Debug)
pub(all) struct StructField {
  ty : Type
  name : String
}

///|
pub extend StructField with Debug::{to_repr}

///|
/// struct 声明（union 复用本结构——历史蓝本同形，ProgramNode.unions
/// 同承载 StructDecl）。`is_forward`：`struct S;` 前向声明位（#145，
/// 2026-10-18）——parser 前向分支置 true、完整定义 false；E1/E4
/// 投影 emitter 不输出该位（#134 is_arrow 同款——golden 零翻）。
#derive(Debug, Default)
pub(all) struct StructDecl {
  loc : @source.SourceLoc
  name : String
  fields : Array[StructField]
  is_forward : Bool
}

///|
pub extend StructDecl with Debug::{to_repr}

///|
pub extend StructDecl with Default::{default}

///|
/// 全局变量声明。
#derive(Debug, Default)
pub(all) struct GlobalDecl {
  loc : @source.SourceLoc
  ty : Type
  name : String
  init : Expr?
  is_static : Bool
  is_extern : Bool
  source_file : String
}

///|
pub extend GlobalDecl with Debug::{to_repr}

///|
pub extend GlobalDecl with Default::{default}

// ============================================================================
// C++ 声明节点
// ============================================================================

///|
/// C++ 访问段位。
#derive(Debug, Eq, Compare)
pub(all) enum AccessSpec {
  Public
  Private
  Protected
}

///|
pub extend AccessSpec with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend AccessSpec with Debug::{to_repr}

///|
pub extend AccessSpec with Eq::{not_equal, equal}

///|
/// 类成员（6 变体，照搬 Rust ClassMember）。
#derive(Debug)
pub(all) enum ClassMember {
  Field(String, Type, AccessSpec, Bool) // name, ty, access, is_static
  Method(String, Type, Array[Param], Stmt?, Bool, AccessSpec, Bool, Bool) // name, ret, params, body, is_virtual, access, is_static, is_const
  Constructor(Array[Param], Stmt?, Bool, AccessSpec, Bool) // params, body, is_default, access, is_explicit
  Destructor(Stmt?, AccessSpec, Bool) // body, access, is_virtual
  NestedStruct(StructDecl, AccessSpec)
  NestedClass(ClassDecl, AccessSpec)
}

///|
pub extend ClassMember with Debug::{to_repr}

///|
/// 虚表（(method_name, function_type) 条目表）。
#derive(Debug)
pub(all) struct VTable {
  entries : Array[(String, Type)]
}

///|
pub extend VTable with Debug::{to_repr}

///|
/// 类声明。
#derive(Debug)
pub(all) struct ClassDecl {
  loc : @source.SourceLoc
  name : String
  base : String?
  members : Array[ClassMember]
  vtable : VTable?
}

///|
pub extend ClassDecl with Debug::{to_repr}

///|
/// 模板形参（类型形参 / 非类型形参）。
#derive(Debug)
pub(all) enum TemplateParam {
  TypeParam(String, @source.SourceLoc) // name（Type 为 MoonBit 类型名冲突，加 Param 后缀）
  NonType(String, Type, @source.SourceLoc) // name, ty
}

///|
pub extend TemplateParam with Debug::{to_repr}

///|
/// 模板实参（3 变体；判等见 types_eq.mbt——Expr 形态不参与判等）。
#derive(Debug)
pub(all) enum TemplateArg {
  TArg(Type)
  TExpr(Expr)
  TInt(Int32)
}

///|
pub extend TemplateArg with Debug::{to_repr}

///|
/// 模板载体（函数模板 / 类模板）。
#derive(Debug)
pub(all) enum Templateable {
  TFunc(FuncDecl)
  TClass(ClassDecl)
}

///|
pub extend Templateable with Debug::{to_repr}

///|
/// 模板声明。
#derive(Debug)
pub(all) struct TemplateDecl {
  loc : @source.SourceLoc
  params : Array[TemplateParam]
  decl : Templateable
}

///|
pub extend TemplateDecl with Debug::{to_repr}

///|
/// 模板实例化点。
#derive(Debug)
pub(all) struct TemplateInstantiation {
  loc : @source.SourceLoc
  base : String
  args : Array[TemplateArg]
}

///|
pub extend TemplateInstantiation with Debug::{to_repr}

///|
/// lambda 捕获模式（3 变体）。
#derive(Debug, Eq, Compare)
pub(all) enum CaptureMode {
  ByValue(String)
  ByReference(String)
  Implicit
}

///|
pub extend CaptureMode with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend CaptureMode with Debug::{to_repr}

///|
pub extend CaptureMode with Eq::{not_equal, equal}

// ============================================================================
// 程序根
// ============================================================================

///|
/// 编译单元根（七集合；unions 复用 StructDecl——历史蓝本同形）。
#derive(Debug)
pub(all) struct ProgramNode {
  structs : Array[StructDecl]
  unions : Array[StructDecl]
  globals : Array[GlobalDecl]
  funcs : Array[FuncDecl]
  // === C++ 新增 ===
  classes : Array[ClassDecl]
  templates : Array[TemplateDecl]
  template_instantiations : Array[TemplateInstantiation]
}

///|
pub extend ProgramNode with Debug::{to_repr}

///|
/// 空程序根。
pub fn ProgramNode::empty() -> ProgramNode {
  {
    structs: [],
    unions: [],
    globals: [],
    funcs: [],
    classes: [],
    templates: [],
    template_instantiations: [],
  }
}
