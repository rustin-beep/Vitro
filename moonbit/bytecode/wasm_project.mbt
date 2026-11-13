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
/// - symbol_sizes：symbols 逐条 `Type::array_size`（**元素数**口径、非数组
///   恒 0——TrapBounds operand ≥ 0 = 符号下标查本表、< 0 取 -operand，与
///   `vm/exec_debug.mbt` / `codegen/index_member.mbt` 两真值侧同源）；
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
  // symbol_sizes：符号尺寸表（TrapBounds 的 operand ≥ 0 索引此表）——
  // **元素数**口径（非数组恒 0）：真值侧 `vm/exec_debug.mbt:96`
  // （`sym.ty.array_size()`）与 `codegen/index_member.mbt:284-288`（负形态
  // `-bound_size` 同为元素数）三处同源。PR #505 审阅 P1-1 实锤：首版误用
  // `compute_type_size`（字节数）——`double g[3]` 发 24 而 VM 比 3，wasm
  // 产物内数组越界不 trap。
  let symbol_sizes : Array[Int32] = []
  for sym in output.symbols {
    symbol_sizes.push(sym.ty.array_size())
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

///|
/// **装载往返原语（REHOST 批 2b）**——run 态装载协议的核心：code →
/// 发射（wasm 字节）→ 组表引导裁决折叠（`verify_fold_with_table`）→
/// 重建 Instruction（op/operand 来自折叠产物、loc 来自组表侧车）→
/// **与原 code 逐位恒等断言**（op/operand/loc 三元组）。设计单 §3.1
/// 「装载期把 wasm 字节按发射模板折叠回组操作」的机检形态——恒等即
/// 「语义冻结最强形态」：折叠重建产物驱动执行与 legacy code 同构，
/// digest 零漂移的机制根基。
///
/// Err（String = 单行诊断）= 装载失败面：发射失败（禁译面/域非法）、
/// 装载核对红（非自家产物形态）、往返失配（发射↔折叠互逆性破坏——
/// 理论不可达，装载协议必须显式拦）。消费方（`setup_from_output`）
/// 过渡期按设计单回退 legacy code 执行并携带状态——fail loud 归双跑
/// 对拍闸（wasm 臂标记行非 ok 即红）。
pub fn rehost_round_trip(
  output : CompileOutput,
) -> Result[Array[@opcode.Instruction], String] {
  let ctx = wasm_emit_ctx(output)
  let p = match build_wasm_product(output) {
    Ok(p) => p
    Err(EmitFailed(gip, op_name, reason)) =>
      return Err("emit-failed gip=\{gip} op=\{op_name} \{reason}")
  }
  let folded = match @wasmenc.verify_fold_with_table(p.table, p.bytes, ctx) {
    Ok(folded) => folded
    Err(e) => return Err("verify-failed \{verify_err_one_line(e)}")
  }
  if folded.length() != output.code.length() {
    return Err(
      "roundtrip-count groups=\{folded.length()} code=\{output.code.length()}",
    )
  }
  let out : Array[@opcode.Instruction] = []
  for i = 0; i < folded.length(); i = i + 1 {
    let g = folded[i]
    let e = p.table.groups[i]
    let want = output.code[i]
    // loc 恒等先比（重建物从侧车来——侧车发射时由原 loc 直填，理论恒等；
    // 失配 = 侧车/重建双实现分叉，装载协议拦）
    if e.loc_line != want.loc.line ||
      e.loc_column != want.loc.column ||
      e.loc_file_id != want.loc.file_id {
      return Err(
        "roundtrip-loc gip=\{i} sidecar=\{e.loc_line}:\{e.loc_column}:\{e.loc_file_id} code=\{want.loc.line}:\{want.loc.column}:\{want.loc.file_id}",
      )
    }
    // op/operand 恒等（verify 的还原槽比对只覆盖可还原槽——这里是全量
    // 双侧断言：侧车声明与折叠产物都必须与原 code 一致）
    if g.op != want.op || g.operand != want.operand {
      return Err(
        "roundtrip-op gip=\{i} folded=\{g.op.name()}(\{g.operand}) code=\{want.op.name()}(\{want.operand})",
      )
    }
    out.push(
      @opcode.Instruction::new(
        g.op,
        g.operand,
        @source.SourceLoc::with_file(e.loc_line, e.loc_column, e.loc_file_id),
      ),
    )
  }
  Ok(out)
}

///|
/// VerifyError → 单行文本（装载失败诊断——cmd/dump_wasm 的
/// verify_err_text 是 cmd 层复制件，本函数是 bytecode 装载通道侧的
/// 简短形态）。
fn verify_err_one_line(e : @wasmenc.VerifyError) -> String {
  match e {
    GroupCountMismatch(want, got) => "GroupCountMismatch \{want} vs \{got}"
    GroupMismatch(gip, a, b, x, y) =>
      "GroupMismatch gip=\{gip} \{a.name()}(\{x}) vs \{b.name()}(\{y})"
    FoldFailed(fe) =>
      match fe {
        Decode(off, _) => "FoldDecode @\{off}"
        NoTemplate(off) => "NoTemplate @\{off}"
        TableShapeConflict(off, a, b) =>
          "TableShapeConflict @\{off} \{a.name()}/\{b.name()}"
      }
    TemplateMismatch(gip, op, off) =>
      "TemplateMismatch gip=\{gip} \{op.name()} @\{off}"
    BoundaryMismatch(gip, op, got, want) =>
      "BoundaryMismatch gip=\{gip} \{op.name()} \{got} vs \{want}"
    GroupGap(gip, prev, off) => "GroupGap gip=\{gip} \{prev}→\{off}"
    TrailingInstrs(at, left) => "TrailingInstrs @\{at} +\{left}"
    ReservedGroup(gip, op) => "ReservedGroup gip=\{gip} \{op.name()}"
  }
}
