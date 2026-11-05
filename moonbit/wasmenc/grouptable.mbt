///|
/// 组表侧车（L1）——**一等公民，非可选调试信息**（探针报告 §5.2 红线 3：
/// 盲折叠在歧义对上必错且 re-emit 自校验不能检出——组边界是折叠完备性
/// 的必要条件；设计单 §3.1 载体定义「+ 侧车：组表（组号→op/operand/loc）」）。
///
/// **职责分划（批 1b 定形的双层裁决）**：
/// - **盲折叠**（fold.mbt）：产出「字节可解释」的组序列（Exact+Composed
///   贪心最长——跨组重叠区的规范化约定）；
/// - **`verify_group_table`**（盲折叠终裁）：折叠产物 ↔ 组表逐组比对
///   （op + operand）——A/B 类产物的装载核对（批 1a 形态原样保留；字节
///   边界字段 `instr_offset`/`instr_len` 在此路径只随表携带不参与核对，
///   比对接线在批 1c 装载协议——#493 审阅 P3 勘正登记）；
/// - **`verify_fold_with_table`**（组表引导裁决，批 1b 新增）：**按组表
///   声明的 op/边界逐组匹配模板**——C 类（Ambiguous）组的唯一裁决路径：
///   同一段字节（如 `i32.const argc`）在不同组表下分别裁决为 PushArgc /
///   PushConst，双双成立——歧义消解的机检形态即「侧车给定身份」。
///   Reserved 态组 = 装载即拒载；
/// - **CompileOutput 增量字段设计**（批 1c 接线，结构已定形）：
///   `wasm_groups : GroupTable` 与 legacy `code` 字段并存（迁移期双发，
///   设计单 §3.3；批 4 收口时 code 退役）。
///
/// 探针 3 [5] 装载核对预演的机检形态：18 组全互逆 + 篡改拒载——本包
/// `verify_group_table`/`verify_fold_with_table` 即该协议的核心原语。

///|
/// 组表条目（组号 → op/operand/loc + 字节边界）。
#derive(Debug, Eq)
pub(all) struct GroupEntry {
  /// 组序号（=折叠执行器 gip——设计单 §2.4「组=原子执行单元」）
  gip : Int32
  op : @opcode.OpCode
  operand : Int32
  /// 组首在 wasm 指令流的位置（指令索引口径；批 1c 接线时扩字节偏移）
  instr_offset : Int32
  /// 组指令数（A 类恒 1；B/C 类组合模板多条）
  instr_len : Int32
  loc_line : Int32
  loc_column : Int32
  loc_file_id : Int32
}

///|
pub extend GroupEntry with Debug::{to_repr}

///|
pub extend GroupEntry with Eq::{not_equal, equal}

///|
/// 组表（CompileOutput 增量字段的载体结构）。
#derive(Debug, Eq)
pub(all) struct GroupTable {
  groups : Array[GroupEntry]
}

///|
pub extend GroupTable with Eq::{not_equal, equal}

///|
pub extend GroupTable with Debug::{to_repr}

///|
pub fn GroupTable::new() -> GroupTable {
  { groups: [], }
}

///|
/// 发射侧构建组表（与 emit_groups 同步消费——组边界在发射期产生）。
/// 四态全发射（A/B/C 类模板产字节；Reserved 拒载——与 emit_group 同拒）。
pub fn build_group_table(
  groups : Array[(@opcode.OpCode, Int32, @source.SourceLoc)],
  ctx : EmitCtx,
) -> Result[(GroupTable, Array[Byte]), EmitError] {
  let table = GroupTable::new()
  let bytes : Array[Byte] = []
  let mut instr_offset = 0
  for gip = 0; gip < groups.length(); gip = gip + 1 {
    let (op, operand, loc) = groups[gip]
    match emit_group(op, operand, ctx) {
      Ok(instrs) => {
        table.groups.push({
          gip,
          op,
          operand,
          instr_offset,
          instr_len: instrs.length(),
          loc_line: loc.line,
          loc_column: loc.column,
          loc_file_id: loc.file_id,
        })
        for instr in instrs {
          winstr_encode_into(instr, bytes)
        }
        instr_offset = instr_offset + instrs.length()
      }
      Err(e) => return Err(e)
    }
  }
  Ok((table, bytes))
}

///|
/// 组表核对错误（装载期拒载形态——探针 3 [5] 篡改 fail loud 的结构化）。
pub(all) enum VerifyError {
  /// 组数不符（组表与折叠产物长度不一致）
  GroupCountMismatch(Int32, Int32)
  /// 组 gip 处 op/operand 不符（携带两侧值）
  GroupMismatch(Int32, @opcode.OpCode, @opcode.OpCode, Int32, Int32)
  /// 折叠本身失败（先折叠后核对，折叠红透传）
  FoldFailed(FoldError)
  /// 组表引导裁决：组 gip 的模板匹配失败（字节与组表声明的 op 模板
  /// 不符——发射折叠不同步/产物被改的检出形态）
  TemplateMismatch(Int32, @opcode.OpCode, Int32)
  /// 组表引导裁决：组 gip 的模板消费指令数 ≠ 组表声明边界
  BoundaryMismatch(Int32, @opcode.OpCode, Int32, Int32)
  /// 组表引导裁决：全部组消费后仍有尾随指令（组表未覆盖整段字节）
  TrailingInstrs(Int32, Int32)
  /// 组表声明了 Reserved 态组（零发射保留——装载即拒载）
  ReservedGroup(Int32, @opcode.OpCode)
}

///|
/// **装载核对协议原语一（盲折叠终裁）**：折叠产物 ↔ 组表逐组比对
/// （op + operand）。A/B 类产物的核对形态（批 1a 原样）；C 类歧义对
/// （同字节双身份）在此层不可区分——用 `verify_fold_with_table`。
pub fn verify_group_table(
  table : GroupTable,
  bytes : Array[Byte],
  ctx : EmitCtx,
) -> Result[Unit, VerifyError] {
  let folded = match fold_bytes(bytes, ctx) {
    Ok(groups) => groups
    Err(e) => return Err(FoldFailed(e))
  }
  if folded.length() != table.groups.length() {
    return Err(GroupCountMismatch(table.groups.length(), folded.length()))
  }
  for i = 0; i < folded.length(); i = i + 1 {
    let want = table.groups[i]
    let got = folded[i]
    if want.op != got.op || want.operand != got.operand {
      return Err(GroupMismatch(i, want.op, got.op, want.operand, got.operand))
    }
  }
  Ok(())
}

///|
/// **装载核对协议原语二（组表引导裁决）**——C 类歧义组的唯一裁决路径：
/// 逐组按**组表声明的 op** 在声明边界处匹配模板（不盲猜）。同段字节在
/// 不同组表下可裁决为不同 op（PushArgc vs PushConst）——「身份=侧车给定」
/// 的机检形态；四态全可裁决（Reserved 组 = 装载即拒载）。
///
/// operand 比对口径：**还原槽生效才比对**（OpI32/OpBase/F64Of/I64Of 还原
/// operand 与组表声明一致——发射折叠不同步的检出锚）；无还原槽的模板
/// （StepEvent/TrapBounds/Dup/Swap/C 类上下文槽）operand 由侧车自证，
/// 不比对（op + 边界已裁决身份）。
pub fn verify_fold_with_table(
  table : GroupTable,
  bytes : Array[Byte],
  ctx : EmitCtx,
) -> Result[Array[FoldedGroup], VerifyError] {
  let instrs = match winstr_decode_all(bytes) {
    Ok(instrs) => instrs
    Err(e) => return Err(FoldFailed(fold_decode_err(bytes, e)))
  }
  let out : Array[FoldedGroup] = []
  for g in table.groups {
    let spec = template_spec(g.op)
    if spec.state is Reserved {
      return Err(ReservedGroup(g.gip, g.op))
    }
    let pat = match spec.pat {
      Some(p) => p
      None => return Err(ReservedGroup(g.gip, g.op)) // 不变量破坏形态
    }
    match pat_match_at(pat, instrs, g.instr_offset, ctx) {
      Some((operand, len)) => {
        if len != g.instr_len {
          return Err(BoundaryMismatch(g.gip, g.op, len, g.instr_len))
        }
        // 还原槽判定：模板携带可还原槽 ⇔ 折叠 operand 语义可比
        if pat_has_operand_slot(pat) && operand != g.operand {
          return Err(GroupMismatch(g.gip, g.op, g.op, g.operand, operand))
        }
        out.push({ op: g.op, operand: g.operand, })
      }
      None => return Err(TemplateMismatch(g.gip, g.op, g.instr_offset))
    }
  }
  // 全组消费 = 整段覆盖（尾随指令 = 组表不完整——装载拒载）
  let consumed = if table.groups.length() > 0 {
    let last = table.groups[table.groups.length() - 1]
    last.instr_offset + last.instr_len
  } else {
    0
  }
  if consumed != instrs.length() {
    return Err(TrailingInstrs(consumed, instrs.length()))
  }
  Ok(out)
}

///|
/// 模板是否携带 operand 还原槽（OpI32/OpBase/F64Of/I64Of——比对组表
/// operand 才有意义；纯固定序列/上下文槽模板的 operand 由侧车自证）。
fn pat_has_operand_slot(pat : ExactPat) -> Bool {
  match pat {
    Instr(_) => false // A 类恒等指令 operand 恒 0（无槽）
    I32Slot => true
    F32Slot => true
    Seq(items) => {
      let mut has = false
      for item in items {
        match item {
          OpI32 | OpBase(_) | F64Of | I64Of => has = true
          _ => ()
        }
      }
      has
    }
  }
}
