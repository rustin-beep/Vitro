///|
/// 折叠器（L1）：wasm 字节 → 组操作序列——发射的逆函数，**与发射器共享
/// template_spec 单源**（匹配表自 opcode 编号空间穷举构建，非手写第二份：
/// `OpCode::from_u8` 0..255 穷举 → Exact+Composed 态收表——opcode 增删
/// 两侧同变）。
///
/// **盲折叠 vs 组表引导裁决**（批 1b 定形的双层）：
/// - **盲折叠**（本文件 `fold_bytes`）：贪心最长匹配，**只含 Exact +
///   Composed**——Ambiguous 态（C 类 13 条）不入表：其字节与其他组的
///   合法序列恒等（探针 2 [四] 实锤），盲折叠必错其一，入表反而污染
///   A/B 的可解释面。C 类组的身份由组表引导裁决（grouptable.mbt 的
///   `verify_fold_with_table`——按组表声明的 op/边界匹配模板）；
/// - **贪心最长 = 规范化约定**：跨组重叠区（TruncUByte 的
///   [i32.const 255; i32.and] 与两组合 [PushConst(255);BitAnd] 字节恒等）
///   盲折叠恒取长模板——真实分组由组表终裁，本层只承诺「确定性可解释」。
///
/// **fail loud 契约**（探针 2 [三] 实证形态）：字节可被本模板库解释才折叠；
/// 库外面外指令（UnknownOpcode）/ 面内无模板序列（NoTemplate）/ 操作数截断
/// 一律拒载不静默。**精确边界**（探针报告 §2 结论 2）：模板库内的合法
/// 字节序列不能证明是自家发射产物——「产物身份」=字节可解释 + **组表
/// 侧车逐组核对**双层。

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
  /// 字节偏移处无任何 Exact/Composed 模板匹配（非本发射器产物或
  /// Ambiguous 态序列——**位置口径=字节偏移**（批 1b 起，原 WInstr 流
  /// 索引已改——装载期诊断直接对位产物字节））
  NoTemplate(Int32)
  /// 盲折叠表内两模板在同一位置同时最长匹配（表形状缺陷——同形双模板
  /// = 永久歧义，装载即红；携带字节偏移与两个候选 op）
  TableShapeConflict(Int32, @opcode.OpCode, @opcode.OpCode)
}

///|
/// 匹配表项（op + 其模板）。
priv struct ExactEntry {
  op : @opcode.OpCode
  pat : ExactPat
}

///|
/// 构建盲折叠匹配表（自编号空间穷举——from_u8 单源消费；**Exact +
/// Composed 两态**收表，Ambiguous 不入（防歧义污染 A/B 可解释面——
/// C 类经组表引导裁决）；表不变量 `state ≠ Reserved ⇔ pat is Some`
/// 在此信任，wbtest 另锁）。
fn build_exact_entries() -> Array[ExactEntry] {
  let entries : Array[ExactEntry] = []
  for code = 0; code <= 255; code = code + 1 {
    match @opcode.OpCode::from_u8(code) {
      Some(op) =>
        match template_spec(op) {
          { state: Exact, pat: Some(pat), .. } => entries.push({ op, pat, })
          { state: Composed, pat: Some(pat), .. } => entries.push({ op, pat, })
          _ => ()
        }
      None => ()
    }
  }
  entries
}

///|
/// 盲折叠匹配表（进程内单次构建——153 码表穷举 256 值的产物，幂等）。
fn exact_entries() -> Array[ExactEntry] {
  // MoonBit 无 lazy 全局可变惯用形态：匹配表构建 ~256 次表查
  //（微秒级），折叠为装载期一次性动作，直构即可
  build_exact_entries()
}

///|
/// SeqItem 在 WInstr 流 pos 处匹配：成功返回 (operand 是否还原, operand
/// 值, 消费指令数)。**不还原**（false）= CtxI32/SymSize/BrAny 槽——operand
/// 由组表侧车携带。
fn seq_item_match(
  item : SeqItem,
  instrs : Array[WInstr],
  pos : Int32,
  ctx : EmitCtx,
) -> (Bool, Int32, Int32)? {
  if pos >= instrs.length() {
    return None
  }
  let i = instrs[pos]
  match item {
    Fixed(w) => if i == w { Some((false, 0, 1)) } else { None }
    OpI32 =>
      match i {
        WI32Const(v) => Some((true, v, 1))
        _ => None
      }
    OpBase(base) =>
      match i {
        WI32Const(v) =>
          // 还原 = 值 − base（i32 正域：发射值 ∈ [base, base+2^31)）
          Some((true, v - base, 1))
        _ => None
      }
    F64Of =>
      match i {
        WF64Const(v) => {
          // 池反查首索引（同值多索引歧义面——组表终裁，表注契约）
          let mut found : Int32 = -1
          for k = 0; k < ctx.f64_constants.length(); k = k + 1 {
            if ctx.f64_constants[k] == v {
              found = k
              break
            }
          }
          if found >= 0 {
            Some((true, found, 1))
          } else {
            None // 池外值——非本发射器产物形态
          }
        }
        _ => None
      }
    I64Of =>
      match i {
        WI64Const(v) => {
          let mut found : Int32 = -1
          for k = 0; k < ctx.i64_constants.length(); k = k + 1 {
            if ctx.i64_constants[k] == v {
              found = k
              break
            }
          }
          if found >= 0 {
            Some((true, found, 1))
          } else {
            None
          }
        }
        _ => None
      }
    CtxI32(_) =>
      match i {
        WI32Const(_) => Some((false, 0, 1)) // 上下文槽——任意值匹配不还原
        _ => None
      }
    SymSize =>
      match i {
        WI32Const(_) => Some((false, 0, 1)) // 尺寸值在字节——operand 侧车
        _ => None
      }
    BrAny =>
      match i {
        WBr(_) => Some((false, 0, 1)) // 深度任意——探针 2 结论 4
        _ => None
      }
  }
}

///|
/// 模板在 WInstr 流 pos 处匹配：成功返回 (operand, 消费指令数)。
/// operand 还原规则：**首个还原槽生效**（OpI32/OpBase/F64Of/I64Of——
/// 现表模板每条至多一个还原槽；无还原槽的模板（StepEvent/TrapBounds/
/// Dup/Swap 纯固定序列）operand=0 占位，真实 operand 由组表侧车携带。
fn pat_match_at(
  pat : ExactPat,
  instrs : Array[WInstr],
  pos : Int32,
  ctx : EmitCtx,
) -> (Int32, Int32)? {
  match pat {
    Instr(w) =>
      if pos < instrs.length() && instrs[pos] == w {
        Some((0, 1))
      } else {
        None
      }
    I32Slot =>
      if pos < instrs.length() {
        match instrs[pos] {
          WI32Const(v) => Some((v, 1))
          _ => None
        }
      } else {
        None
      }
    F32Slot =>
      if pos < instrs.length() {
        match instrs[pos] {
          WF32Const(f) =>
            Some((f.reinterpret_as_uint().reinterpret_as_int(), 1))
          _ => None
        }
      } else {
        None
      }
    Seq(items) => {
      let mut operand : Int32 = 0
      let mut has_operand = false
      let mut p = pos
      for item in items {
        match seq_item_match(item, instrs, p, ctx) {
          Some((restorable, v, n)) => {
            if restorable {
              operand = v
              has_operand = true
            }
            p = p + n
          }
          None => return None
        }
      }
      ignore(has_operand) // 消费侧（组表引导裁决）经 pat_has_operand_slot 判定
      Some((operand, p - pos))
    }
  }
}

///|
/// 字节流折叠（发射的逆）：decode 全量 → 逐位置贪心最长匹配 → 组操作
/// 序列。任一位置无匹配即拒载（fail loud）；同长双匹配 = 表形状缺陷
/// 即红（TableShapeConflict——永久歧义面装载期暴露）。
pub fn fold_bytes(
  bytes : Array[Byte],
  ctx : EmitCtx,
) -> Result[Array[FoldedGroup], FoldError] {
  let instrs = match winstr_decode_all(bytes) {
    Ok(instrs) => instrs
    Err(e) => return Err(fold_decode_err(bytes, e))
  }
  fold_instrs(instrs, ctx)
}

///|
/// 解码错误定位（winstr_decode_all 不带偏移——重扫定位首错位置，供
/// 错误信息；流短线性重扫可接受）。
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
/// WInstr 流的逐指令字节偏移表（编码长度单源——winstr_encode 逐条累计）。
fn instr_byte_offsets(instrs : Array[WInstr]) -> Array[Int32] {
  let offsets : Array[Int32] = []
  let mut off = 0
  for instr in instrs {
    offsets.push(off)
    off = off + winstr_encode(instr).length()
  }
  offsets
}

///|
/// WInstr 流折叠（组表核对侧消费同一入口——装载协议先解码一次、
/// 逐组核对与折叠共享）。**位置口径**：NoTemplate/TableShapeConflict
/// 携带**字节偏移**（批 1b 起——装载诊断直接对位产物字节）。
pub fn fold_instrs(
  instrs : Array[WInstr],
  ctx : EmitCtx,
) -> Result[Array[FoldedGroup], FoldError] {
  let entries = exact_entries()
  let offsets = instr_byte_offsets(instrs)
  let out : Array[FoldedGroup] = []
  let mut pos = 0
  while pos < instrs.length() {
    let byte_off = offsets[pos]
    let mut matched : (Int32, Int32, @opcode.OpCode)? = None
    for entry in entries {
      match pat_match_at(entry.pat, instrs, pos, ctx) {
        Some((operand, len)) =>
          match matched {
            Some((_, best, best_op)) =>
              if len > best {
                matched = Some((operand, len, entry.op))
              } else if len == best && best_op != entry.op {
                // 同长双匹配且 op 不同 = 表形状缺陷（同形模板永久歧义）
                return Err(TableShapeConflict(byte_off, best_op, entry.op))
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
      None => return Err(NoTemplate(byte_off))
    }
  }
  Ok(out)
}
