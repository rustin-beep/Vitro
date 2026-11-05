///|
/// 组表侧车（L1）——**一等公民，非可选调试信息**（探针报告 §5.2 红线 3：
/// 盲折叠在歧义对上必错且 re-emit 自校验不能检出——组边界是折叠完备性
/// 的必要条件；设计单 §3.1 载体定义「+ 侧车：组表（组号→op/operand/loc）」）。
///
/// **职责分划**：
/// - 折叠器（fold.mbt）产出「字节可解释」的组序列；
/// - 组表核对（本文件）裁决「确为自家发射产物」——逐组比对 op/operand/
///   字节边界，任一不符即拒载。歧义对（BitNot vs PushConst(-1)+BitXor）
///   在此形态下天然消歧（组表给出组边界与 op）；
/// - **CompileOutput 增量字段设计**（批 1c 接线，结构本批定形）：
///   `wasm_groups : GroupTable` 与 legacy `code` 字段并存（迁移期双发，
///   设计单 §3.3；批 4 收口时 code 退役）。
///
/// 探针 3 [5] 装载核对预演的机检形态：18 组全互逆 + 篡改拒载——本包
/// `verify_group_table` 即该协议的核心原语。

///|
/// 组表条目（组号 → op/operand/loc + 字节边界）。
pub(all) struct GroupEntry {
  /// 组序号（=折叠执行器 gip——设计单 §2.4「组=原子执行单元」）
  gip : Int32
  op : @opcode.OpCode
  operand : Int32
  /// 组首在 wasm 指令流的位置（指令索引口径；批 1c 接线时扩字节偏移）
  instr_offset : Int32
  /// 组指令数（A 类恒 1；B 类组合模板多条）
  instr_len : Int32
  loc_line : Int32
  loc_column : Int32
  loc_file_id : Int32
} derive(Debug, Eq)

///|
pub extend GroupEntry with Debug::{to_repr}

///|
pub extend GroupEntry with Eq::{not_equal, equal}

///|
/// 组表（CompileOutput 增量字段的载体结构）。
pub(all) struct GroupTable {
  groups : Array[GroupEntry]
} derive(Debug, Eq)

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
/// 批 1a 形态：每组恒 1 条指令（Exact 模板）；批 1b 组合模板时 instr_len
/// 取模板实际长度。
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
}

///|
/// **装载核对协议核心原语**：折叠产物 ↔ 组表逐组比对（op + operand）。
/// 歧义消解的机检形态——即使模板库含歧义对（批 1b 的 BitNot 入表后），
/// 组表给出的组边界使折叠结果可被裁决，错折叠在此红。
pub fn verify_group_table(
  table : GroupTable,
  bytes : Array[Byte],
) -> Result[Unit, VerifyError] {
  let folded = match fold_bytes(bytes) {
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
