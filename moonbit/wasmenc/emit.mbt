///|
/// 发射器（L1）：组操作 → WInstr 序列 → wasm 字节。**批 1b 起 Exact/
/// Composed/Ambiguous 三态全接线**（A 直映 / B 组合模板 / C 侧车随行——
/// C 类发射供组表引导裁决消费字节）；**Reserved 态显式 fail loud**（永久
/// 拒载，不静默不兜底）。
///
/// **栈序不变量 API**（探针报告 §5.2 红线）：消费 Vitro 值栈的组，其 wasm
/// 序列的取数序必须与 Vitro 弹栈序同构——二元指令 Vitro「先弹 b（顶）再
/// 弹 a」= wasm 栈消费序 [a 在下, b 在顶]（同构天然成立）；**访存类**
/// 「先弹值再弹地址」= wasm 栈 [addr, value]（探针会话 3 次执行错误全是
/// 此序拼反）。组合模板的形态由 templates.mbt 声明、经暂存槽重排固化
/// （Store 族值先行 set、addr 序列垫底），白盒断言每模板 wasm 栈净效应
/// = 表声明（softstack_wbtest 锁）。

///|
/// 发射上下文（CompileOutput 派生——常量池/装载约定/上下文槽）。
/// 批 1b 定形：常量池两数组（PushConstD/Q 的 operand 索引真源）+
/// C 类上下文槽四件（argc/argv/fallthrough/host 参数区）+ TrapBounds
/// 符号尺寸表。批 1c codegen 接线时由 CompileOutput 实字段填充；本批
/// 测试与 wabt 证人按装载约定构造。
pub(all) struct EmitCtx {
  /// f64 常量池（PushConstD 的 operand 索引真源——schema.f64_constants）
  f64_constants : Array[Double]
  /// i64 常量池（PushConstQ 同上）
  i64_constants : Array[Int64]
  /// argc 编译期已知（PushArgc 的 CtxI32(Argc) 槽）
  argc : Int32
  /// argv 区地址（PushArgv 的 CtxI32(ArgvAddr) 槽——data 段/侧车铺设）
  argv_addr : Int32
  /// 块 fallthrough 后继 pc（JumpIf 族落空分支 / Call 族返回 pc——
  /// 块结构信息，批 1c codegen 的基块划分器填充；微缩默认 0）
  fallthrough_pc : Int32
  /// CallHost 参数区约定地址（H2 ABI 的 argv_ptr）
  host_argv_ptr : Int32
  /// 符号尺寸表（TrapBounds：operand ≥ 0 = 下标 → 数组长度；批 1c 由
  /// symbols 填充）。
  symbol_sizes : Array[Int32]
} derive(Debug, Eq)

///|
pub extend EmitCtx with Eq::{not_equal, equal}

///|
pub extend EmitCtx with Debug::{to_repr}

///|
pub fn EmitCtx::empty() -> EmitCtx {
  {
    f64_constants: [],
    i64_constants: [],
    argc: 0,
    argv_addr: 0,
    fallthrough_pc: 0,
    host_argv_ptr: 0,
    symbol_sizes: [],
  }
}

///|
/// 发射错误。
pub(all) enum EmitError {
  /// Reserved 态的显式拒载（非静默——携带态名与保留原因）
  NotImplemented(String)
  /// 操作数域非法（常量池/符号尺寸表索引越界等）
  BadOperand(String)
}

///|
/// CtxI32 槽取值（发射侧）。
fn ctx_slot_value(ctx : EmitCtx, slot : CtxSlot) -> Int32 {
  match slot {
    Argc => ctx.argc
    ArgvAddr => ctx.argv_addr
    FallthroughPc => ctx.fallthrough_pc
    HostArgvPtr => ctx.host_argv_ptr
  }
}

///|
/// SeqItem → WInstr（发射侧填槽；operand/ctx 消费单源）。
fn seq_item_emit(
  item : SeqItem,
  operand : Int32,
  ctx : EmitCtx,
) -> Result[WInstr, EmitError] {
  match item {
    Fixed(w) => Ok(w)
    OpI32 => Ok(WI32Const(operand))
    OpBase(base) =>
      // base + operand（u32 域加法——exec_global 的 GLOBAL_START+off 镜像）
      Ok(
        WI32Const(
          (base.reinterpret_as_uint() + operand.reinterpret_as_uint()).reinterpret_as_int(),
        ),
      )
    F64Of =>
      match ctx.f64_constants.get(operand) {
        Some(v) => Ok(WF64Const(v))
        None =>
          Err(
            BadOperand(
              "f64 常量池索引越界: \{operand}（池深 \{ctx.f64_constants.length()}）",
            ),
          )
      }
    I64Of =>
      match ctx.i64_constants.get(operand) {
        Some(v) => Ok(WI64Const(v))
        None =>
          Err(
            BadOperand(
              "i64 常量池索引越界: \{operand}（池深 \{ctx.i64_constants.length()}）",
            ),
          )
      }
    CtxI32(slot) => Ok(WI32Const(ctx_slot_value(ctx, slot)))
    SymSize =>
      // TrapBounds 尺寸（exec_debug.mbt:93-100 镜像）：operand ≥ 0 = 符号
      // 下标查表；< 0 = -operand 字面量形状
      if operand >= 0 {
        match ctx.symbol_sizes.get(operand) {
          Some(sz) if sz >= 0 => Ok(WI32Const(sz))
          Some(_) =>
            Err(
              BadOperand(
                "TrapBounds 符号尺寸为负（下标 \{operand}）——表契约破坏",
              ),
            )
          None =>
            Err(
              BadOperand(
                "符号尺寸表越界: \{operand}（表长 \{ctx.symbol_sizes.length()}）",
              ),
            )
        }
      } else {
        Ok(WI32Const(-operand))
      }
    BrAny =>
      // 微缩约定 depth=0（批 1b 模板级：br 跳出所在块——真实 label 栈
      // 由批 1c codegen 的 dispatch-loop 骨架重建，折叠侧消费任意值）
      Ok(WBr(0))
  }
}

///|
/// 单组发射：组操作 → WInstr 序列（模板表驱动——ExactPat 单源）。
pub fn emit_group(
  op : @opcode.OpCode,
  operand : Int32,
  ctx : EmitCtx,
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
        Seq(items) => {
          let out : Array[WInstr] = []
          for item in items {
            match seq_item_emit(item, operand, ctx) {
              Ok(w) => out.push(w)
              Err(e) => return Err(e)
            }
          }
          Ok(out)
        }
      }
    None =>
      // pat=None ⇔ Reserved（表不变量；此处不可达形态防手改表漏带）
      match s.state {
        Reserved =>
          Err(
            NotImplemented(
              "\{op.name()}（不可映射·零发射保留）——永久拒载：\{s.hint}",
            ),
          )
        _ =>
          Err(
            NotImplemented(
              "表不变量破坏：\{op.name()} 非 Reserved 态但无模板（态序号 \{s.state.compare(Reserved)}）",
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
