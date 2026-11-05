///|
/// 发射器（L1）：组操作 → WInstr 序列 → wasm 字节。**批 1a 只实装 Exact
/// 态 84 条**；Composed/Ambiguous/Reserved 态显式 fail loud（模板批 1b/1c
/// 接线——不静默不兜底）。
///
/// **栈序不变量 API**（探针报告 §5.2 红线）：消费 Vitro 值栈的组，其 wasm
/// 序列的取数序必须与 Vitro 弹栈序同构——二元指令 Vitro「先弹 b（顶）再
/// 弹 a」= wasm 栈消费序 [a 在下, b 在顶]（同构天然成立）；**访存类**
/// 「先弹值再弹地址」= wasm 栈 [addr, value]（探针会话 3 次执行错误全是
/// 此序拼反）。批 1a 的 Exact 态均为单指令（无拼序面）；批 1b 组合模板
/// 逐组进 `wasm_stack_effect` 断言（白盒锁）。

///|
/// 发射上下文（CompileOutput 派生——常量池/装载约定；批 1a 的 Exact 态
/// 零消费，**结构先定形**：批 1b 的 PushConstD/Q 索引解析与批 1c 的
/// argc/argv/全局地址表接线在此扩）。
pub(all) struct EmitCtx {
  /// f64 常量池（PushConstD 的 operand 索引真源——schema.f64_constants）
  f64_constants : Array[Double]
  /// i64 常量池（PushConstQ 同上）
  i64_constants : Array[Int64]
} derive(Debug, Eq)

///|
pub extend EmitCtx with Eq::{not_equal, equal}

///|
pub extend EmitCtx with Debug::{to_repr}

///|
pub fn EmitCtx::empty() -> EmitCtx {
  { f64_constants: [], i64_constants: [], }
}

///|
/// 发射错误。
pub(all) enum EmitError {
  /// B/C/D 态在批 1a 的显式拒载（非静默——携带态名与接线批次）
  NotImplemented(String)
  /// 操作数域非法（批 1b 常量池索引越界等）
  BadOperand(String)
}

///|
/// 单组发射：组操作 → WInstr 序列（模板表驱动——ExactPat 单源）。
pub fn emit_group(
  op : @opcode.OpCode,
  operand : Int32,
  _ctx : EmitCtx,
) -> Result[Array[WInstr], EmitError] {
  let s = template_spec(op)
  match s.pat {
    Some(pat) =>
      match pat {
        Instr(w) => Ok([w])
        I32Slot => Ok([WI32Const(operand)])
        // operand = f32 位模式（exec_float.mbt PushConstF 同口径：
        // 位模式经 i32 operand 携带，低 32 位零扩展压栈）
        F32Slot =>
          Ok([
            WF32Const(
              Float::reinterpret_from_uint(operand.reinterpret_as_uint()),
            ),
          ])
      }
    None =>
      match s.state {
        // pat=None 且 Exact = 表不变量破坏（template_spec 的 Exact 臂
        // 必带 pat——此分支理论上不可达，防手改表漏带）
        Exact =>
          Err(
            NotImplemented(
              "表不变量破坏：\{op.name()} 标 Exact 但无模板",
            ),
          )
        Composed =>
          Err(
            NotImplemented(
              "\{op.name()}（组合可逆）——发射模板批 1b 接线",
            ),
          )
        Ambiguous =>
          Err(
            NotImplemented(
              "\{op.name()}（歧义需侧车）——发射模板批 1b/1c 接线（组表侧车随行）",
            ),
          )
        Reserved =>
          Err(
            NotImplemented(
              "\{op.name()}（不可映射·零发射保留）——永久拒载：\{s.hint}",
            ),
          )
      }
  }
}

///|
/// 组序列发射（混编序列→字节流；任一组失败即整体失败——不部分发射）。
pub fn emit_groups(
  groups : Array[(@opcode.OpCode, Int32)],
  ctx : EmitCtx,
) -> Result[Array[Byte], EmitError] {
  let out : Array[Byte] = []
  for pair in groups {
    let (op, operand) = pair
    match emit_group(op, operand, ctx) {
      Ok(instrs) =>
        for instr in instrs {
          winstr_encode_into(instr, out)
        }
      Err(e) => return Err(e)
    }
  }
  Ok(out)
}

///|
/// 单组发射并直接字节化（往返闸消费口）。
pub fn emit_group_bytes(
  op : @opcode.OpCode,
  operand : Int32,
  ctx : EmitCtx,
) -> Result[Array[Byte], EmitError] {
  match emit_group(op, operand, ctx) {
    Ok(instrs) => Ok(winstr_encode_all(instrs))
    Err(e) => Err(e)
  }
}
