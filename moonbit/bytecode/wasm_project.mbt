///|
/// REHOST 批 1c（L6 投影层）：CompileOutput → wasm 载体产物的投影与发射
/// 上下文装配——「双发」的 wasm 侧**按需消费**单源入口。
///
/// **批 1 形态（零扰动设计）**：本投影不进 CompileOutput schema、不进
/// dump/CLI——legacy `code` 字段照发不动，A 级 14 键 dump 面与 digest 闸
/// 零触碰（铁律 1 的批 1 最强形态）；仅 `cmd/dump_wasm` 与产物闸
/// （`scripts/wasmenc_emitgate`）消费。批 2 run 态装载接线时再升 schema
/// 增量字段（迁移期双发，设计单 §3.3）。
///
/// EmitCtx 装配口径（逐项登记批 2 精化点——近似值只进发射字节，不影响
/// 「合法 wasm + 组表核对」两类批 1 验收）：
/// - f64/i64 常量池：CompileOutput 同名字段直填（唯一无近似项）；
/// - symbol_sizes：symbols 逐条 `compute_type_size`（struct/union 定义表
///   直供；TrapBounds operand ≥ 0 = 符号下标查本表，< 0 取 -operand——
///   `codegen/index_member.mbt` 发射口径）；
/// - argc/argv_addr：填 0（空 argv 面）——argv 铺设在运行层（VM
///   `setup_argv`），批 2 装载协议与运行层对齐后由消费方传入；
/// - fallthrough_pc：填 0（单值近似）——真实块后继是基块划分器产物
///   （批 2 C 类控制流完整协议）；C 类组身份由组表侧车给定
///   （CtxI32 槽解码不还原，近似值不参与装载核对）；
/// - host_argv_ptr：`global_data_end` 4 对齐值（H2 单一 ABI 参数窗口的
///   约定地址——批 2 窗口铺设时本值即窗口地址单源）。

///|
/// wasm 载体产物（组表侧车 + 单函数体字节流）。
#derive(Debug)
pub(all) struct WasmProduct {
  /// 组表侧车（装载核对/观测元数据——C 类身份权威）。
  table : @wasmenc.GroupTable
  /// 指令区字节（单函数体线性拼接，不含段结构——段拼装归批 2 模块组装）。
  bytes : Array[Byte]
}

///|
pub extend WasmProduct with Debug::{to_repr}

///|
/// 投影失败（禁译面/操作数域非法——fail loud，禁静默兜底）。
#derive(Debug, Eq)
pub(all) enum WasmProjectError {
  /// 组 gip（op 名携带）发射失败——Err 翻译自 EmitError；组序号由本侧
  /// 定位循环补齐（`build_group_table` 的 Err 不带位置——定位循环仅在
  /// 失败路径跑第二遍，非主路径孪生）。
  EmitFailed(Int32, String, String)
}

///|
pub extend WasmProjectError with Debug::{to_repr}

///|
pub extend WasmProjectError with Eq::{not_equal, equal}

///|
/// CompileOutput.code → 组序列三元组（op/operand/loc 直投影——零重排，
/// Instruction 字段与 `wasmenc.build_group_table` 入参同构）。
pub fn wasm_triples(
  output : CompileOutput,
) -> Array[(@opcode.OpCode, Int32, @source.SourceLoc)] {
  let out : Array[(@opcode.OpCode, Int32, @source.SourceLoc)] = []
  for ins in output.code {
    out.push((ins.op, ins.operand, ins.loc))
  }
  out
}

///|
/// CompileOutput → 发射上下文（装配口径见文件头注）。
pub fn wasm_emit_ctx(output : CompileOutput) -> @wasmenc.EmitCtx {
  // symbol_sizes：符号尺寸表（TrapBounds 的 operand ≥ 0 索引此表）
  let symbol_sizes : Array[Int32] = []
  for sym in output.symbols {
    symbol_sizes.push(
      @ast.compute_type_size(
        sym.ty,
        output.struct_defs,
        output.union_defs,
        Map([]),
      ),
    )
  }
  // host_argv_ptr：global_data_end 4 对齐（H2 参数窗口约定地址）
  let host_argv_ptr = ((output.global_data_end + 3U) & 0xFFFFFFFCU).reinterpret_as_int()
  {
    f64_constants: output.f64_constants,
    i64_constants: output.i64_constants,
    argc: 0,
    argv_addr: 0,
    fallthrough_pc: 0,
    host_argv_ptr,
    symbol_sizes,
  }
}

///|
/// CompileOutput → wasm 载体产物（组表 + 字节流一体构建——
/// `wasmenc.build_group_table` 单源驱动；失败定位循环补 gip）。
pub fn build_wasm_product(
  output : CompileOutput,
) -> Result[WasmProduct, WasmProjectError] {
  let ctx = wasm_emit_ctx(output)
  match @wasmenc.build_group_table(wasm_triples(output), ctx) {
    Ok((table, bytes)) => Ok({ table, bytes, })
    Err(e) => {
      // 失败定位（仅错误路径第二遍）：找到首个发射失败的组序号与身份
      let reason = match e {
        NotImplemented(s) => "NotImplemented: " + s
        BadOperand(s) => "BadOperand: " + s
      }
      let triples = wasm_triples(output)
      let mut gip = -1
      let mut op_name = "?"
      for i = 0; i < triples.length(); i = i + 1 {
        let (op, operand, _loc) = triples[i]
        match @wasmenc.emit_group_bytes(op, operand, ctx) {
          Ok(_) => continue
          Err(_) => {
            gip = i
            op_name = op.name()
            break
          }
        }
      }
      Err(EmitFailed(gip, op_name, reason))
    }
  }
}
