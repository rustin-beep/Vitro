///|
/// 折叠器（L1）：wasm 字节 → 组操作序列——发射的逆函数，**与发射器共享
/// template_spec 单源**（匹配表自 opcode 编号空间穷举构建，非手写第二份：
/// `OpCode::from_u8` 0..255 穷举 → Exact 态收表——opcode 增删两侧同变）。
///
/// **fail loud 契约**（探针 2 [三] 实证形态）：字节可被本模板库解释才折叠；
/// 库外面外指令（UnknownOpcode）/ 面内未接线（B/C/D 态模板）/ 操作数截断
/// 一律拒载不静默。**精确边界**（探针报告 §2 结论 2）：模板库内的合法
/// 字节序列不能证明是自家发射产物——「产物身份」=字节可解释 + **组表
/// 侧车逐组核对**双层（grouptable.mbt），批 1c 装载协议接线。
///
/// **批 1a 折叠面 = Exact 态 84 条**。A 类内部零歧义（WInstr→op 单射
/// + 槽位形态互斥）——歧义对（BitNot vs PushConst(-1)+BitXor 等 C 类）
/// 批 1b 入表后由组表裁决，本批 Ambiguous 态拒载即防误折叠。

///|
/// 折叠产物：一组操作（op + operand）。
pub(all) struct FoldedGroup {
  op : @opcode.OpCode
  operand : Int32
} derive(Debug, Eq)

///|
pub extend FoldedGroup with Debug::{to_repr}

///|
pub extend FoldedGroup with Eq::{not_equal, equal}

///|
/// 折叠错误（全部 fail loud——装载期拒载的外部形态）。
pub(all) enum FoldError {
  /// 字节解码失败（面外 opcode / 操作数截断——携带字节偏移）
  Decode(Int32, DecodeError)
  /// 指令流位置处无任何 Exact 模板匹配（非本发射器产物或 B/C/D 态序列
  /// ——批 1a 位置口径=WInstr 流索引；1b 组合模板入表时改字节偏移）
  NoTemplate(Int32)
}

///|
/// Exact 态匹配表项（op + 其模板）。
priv struct ExactEntry {
  op : @opcode.OpCode
  pat : ExactPat
}

///|
/// 构建 Exact 态匹配表（自编号空间穷举——from_u8 单源消费；表不变量
/// `state is Exact ⇔ pat is Some` 在此信任，wbtest 另锁）。排序按
/// pat_operand_max_len 降序——批 1a 恒单指令无序效，结构为批 1b
/// 组合模板的贪心最长预留（探针 fold 同款）。
fn build_exact_entries() -> Array[ExactEntry] {
  let entries : Array[ExactEntry] = []
  for code = 0; code <= 255; code = code + 1 {
    match @opcode.OpCode::from_u8(code) {
      Some(op) =>
        match template_spec(op) {
          { state: Exact, pat: Some(pat), .. } => entries.push({ op, pat, })
          _ => ()
        }
      None => ()
    }
  }
  entries
}

///|
/// Exact 匹配表（进程内单次构建——153 码表穷举 256 值的产物，幂等）。
fn exact_entries() -> Array[ExactEntry] {
  // MoonBit 无 lazy 全局可变惯用形态：批 1a 匹配表构建 ~256 次表查
  //（微秒级），折叠为装载期一次性动作，直构即可；批 1b 若进热路径再议
  build_exact_entries()
}

///|
/// 模板在 WInstr 流 pos 处匹配：成功返回 (operand, 消费指令数)。
fn pat_match_at(
  pat : ExactPat,
  instrs : Array[WInstr],
  pos : Int32,
) -> (Int32, Int32)? {
  if pos >= instrs.length() {
    return None
  }
  match pat {
    Instr(w) => if instrs[pos] == w { Some((0, 1)) } else { None }
    I32Slot =>
      match instrs[pos] {
        WI32Const(v) => Some((v, 1))
        _ => None
      }
    F32Slot =>
      match instrs[pos] {
        WF32Const(f) => Some((f.reinterpret_as_uint().reinterpret_as_int(), 1))
        _ => None
      }
  }
}

///|
/// 字节流折叠（发射的逆）：decode 全量 → 逐位置贪心最长匹配 Exact 表 →
/// 组操作序列。任一位置无匹配即拒载（fail loud）。
pub fn fold_bytes(bytes : Array[Byte]) -> Result[Array[FoldedGroup], FoldError] {
  let instrs = match winstr_decode_all(bytes) {
    Ok(instrs) => instrs
    Err(e) => return Err(fold_decode_err(bytes, e))
  }
  fold_instrs(instrs)
}

///|
/// 解码错误定位（winstr_decode_all 不带偏移——重扫定位首错位置，供
/// 错误信息；批 1a 流短线性重扫可接受）。
fn fold_decode_err(bytes : Array[Byte], e : DecodeError) -> FoldError {
  let mut pos = 0
  while pos < bytes.length() {
    match winstr_decode(bytes, pos) {
      Ok((_, n)) => pos = pos + n
      Err(_) => return Decode(pos, e)
    }
  }
  Decode(bytes.length(), e)
}

///|
/// WInstr 流折叠（组表核对侧消费同一入口——装载协议先解码一次、
/// 逐组核对与折叠共享）。
pub fn fold_instrs(
  instrs : Array[WInstr],
) -> Result[Array[FoldedGroup], FoldError] {
  let entries = exact_entries()
  let out : Array[FoldedGroup] = []
  let mut pos = 0
  while pos < instrs.length() {
    let mut matched : (Int32, Int32, @opcode.OpCode)? = None
    for entry in entries {
      match pat_match_at(entry.pat, instrs, pos) {
        Some((operand, len)) =>
          match matched {
            // 贪心最长：批 1a 全 len=1，首个命中即终局；1b 组合模板
            // 入表后此处成为真最长优先（探针 fold 同款）
            Some((_, best, _)) =>
              if len > best {
                matched = Some((operand, len, entry.op))
              }
            None => matched = Some((operand, len, entry.op))
          }
        None => ()
      }
    }
    match matched {
      Some((operand, len, op)) => {
        out.push({ op, operand, })
        pos = pos + len
      }
      None =>
        // WInstr 流无匹配：报位置（批 1a 口径=指令流索引）
        return Err(NoTemplate(pos))
    }
  }
  Ok(out)
}
