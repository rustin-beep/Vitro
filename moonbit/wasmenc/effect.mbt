///|
/// **模板栈效应推导器（L1，REHOST 批 2a）**——垫收（组独立 block + 前垫
/// + drop 收）的类型化栈效应单源：对模板发射的 WInstr 流做线性栈模拟，
/// 推导「前垫类型串 + 尾剩余数」——与 `witness_dump_wbtest` 的人工核对表
/// （wabt wat 编译合法性背书）逐行对拍锁定（`effect_wbtest`），组装层
/// （assemble.mbt）与批 1c watcheck 的 `.mts` 垫收约定（PUSHERS/drop）
/// 同型。**人工表是 150 行快照**（新增 opcode 不会自动进表——PR #505
/// 审阅 P2-2 形态）；本推导器自 `template_spec` 枚举驱动（穷尽 match
/// `WInstr`——指令增删两侧同红），wbtest 另断言「全可发射 opcode 推导
/// 成功」兜住新增面。
///
/// **模拟语义**（模板序列从空栈跑，预置一个**虚拟根帧**——垫收壳的组
/// block；模板内 BrAny(0) 的 depth 0 即跳出根帧，批 1b 微缩约定）：
/// - pop 栈空 → 记前垫（欠的类型），继续模拟（虚拟垫入）；
/// - `WBlock/WLoop` 入帧（记录入口高度）；`WEnd` 弹帧并截栈到入口高
///   （void 块出口 0 值——块内残留丢弃；wasm 验证器对 void 块 end 要求
///   恰好入口高度，模板形状合法时线性 fallthrough 路径天然满足，
///   watcheck wat 对拍锁）；
/// - `WBr(d)`：截栈到深度 d 目标帧高度 + 进入 unreachable（其后 d+1
///   个 end 内的指令不产生垫需求）；`WBrIf(d)`：只弹条件 i32
///   （fallthrough 路径继续——分支路径在目标帧出口汇合，出口 0 值
///   截断无损，不新增垫）；
/// - `WUnreachable`：unreachable 直到全部帧关闭；
/// - unreachable 区内结构指令（WBlock/WLoop/WEnd）仍维护帧计数，数据
///   指令跳过。

///|
/// 效应推导错误（模板/指令形状缺陷——fail loud；面内不可达时由
/// watcheck wat 对拍先行暴露，此处是第二道闸）。
#derive(Debug, Eq)
pub(all) enum EffectError {
  /// 指令索引处 pop 类型不符（期望/实际——模板形状与效应表分叉形态）
  TypeMismatch(Int32, Byte, Byte)
  /// 指令索引处 br/br_if 深度越界（携带深度与可用帧数）
  BadBrDepth(Int32, Int32, Int32)
  /// local/global 槽越界（携带指令索引与槽号）
  BadSlot(Int32, Int32)
  /// 非约定函数索引的 call（面内只有 0 = env.vitro_host_call import）
  BadCallIdx(Int32, Int32)
}

///|
pub extend EffectError with Debug::{to_repr}

///|
pub extend EffectError with Eq::{not_equal, equal}

///|
/// local 槽类型（装载约定单源——templates.mbt 槽表：L_V/L_A/L_N = i32、
/// L_T64 = i64、L_TF = f64、L_TF32 = f32）。
fn local_slot_type(idx : Int32) -> Byte? {
  match idx {
    0 | 1 | 2 => Some(WT_I32)
    3 => Some(WT_I64)
    4 => Some(WT_F64)
    5 => Some(WT_F32)
    _ => None
  }
}

///|
/// global 槽类型（G_PC..G_RET = i32〔0..4〕、G_RV = i64〔5〕）。
fn global_slot_type(idx : Int32) -> Byte? {
  match idx {
    0 | 1 | 2 | 3 | 4 => Some(WT_I32)
    5 => Some(WT_I64)
    _ => None
  }
}

///|
/// 栈模拟器状态。
priv struct EffectSim {
  /// 值类型栈（字节 = WT_* 值类型）
  stack : Array[Byte]
  /// 块入口高度栈（含预置根帧——垫收壳组 block）
  frames : Array[Int32]
  /// unreachable 剩余 end 数（0 = 可达）
  mut unreach_ends : Int32
  /// 前垫欠记（栈空时 pop 的期望类型，底→顶序）
  pad : Array[Byte]
}

///|
/// pop 一个期望类型值：栈空记前垫，否则弹栈顶并断言类型一致。
/// 类型不符 = 模板形状与指令效应表分叉（理论不可达——模板发射单源 +
/// watcheck wat 对拍先行锁定；abort fail loud 是第二道闸的形态）。
fn EffectSim::sim_pop(self : EffectSim, want : Byte, at : Int32) -> Unit {
  if self.stack.length() == 0 {
    self.pad.push(want)
  } else {
    let got = self.stack[self.stack.length() - 1]
    let _ = self.stack.remove(self.stack.length() - 1)
    if got != want {
      abort(
        "效应模拟类型错 @指令 \{at}：期望 0x\{want.to_int()} 实得 0x\{got.to_int()}（模板/效应表分叉——watcheck 对拍应先行红）",
      )
    }
  }
}

///|
/// pop 任意类型值（drop 语义——垫记 i32，witness 壳 PUSHERS 的 i 型同源）。
fn EffectSim::sim_pop_any(self : EffectSim) -> Unit {
  if self.stack.length() == 0 {
    self.pad.push(WT_I32)
  } else {
    let _ = self.stack.remove(self.stack.length() - 1)
  }
}

///|
/// 截栈到高度 h（void 块出口/br 目标帧——多余值丢弃）。
fn EffectSim::sim_trunc(self : EffectSim, h : Int32) -> Unit {
  while self.stack.length() > h {
    let _ = self.stack.remove(self.stack.length() - 1)
  }
}

///|
/// 单指令效应推进（可达区；at = 指令索引——错误定位）。
fn EffectSim::sim_step(
  self : EffectSim,
  w : WInstr,
  at : Int32,
) -> Result[Unit, EffectError] {
  match w {
    WNop => Ok(())
    WBlock | WLoop => {
      self.frames.push(self.stack.length())
      Ok(())
    }
    WEnd => {
      // frames 恒非空（根帧预置）——长度守恒由结构合法保证
      let h = self.frames[self.frames.length() - 1]
      let _ = self.frames.remove(self.frames.length() - 1)
      self.sim_trunc(h)
      if self.unreach_ends > 0 {
        self.unreach_ends = self.unreach_ends - 1
      }
      Ok(())
    }
    WBr(d) => {
      if d < 0 || d >= self.frames.length() {
        return Err(BadBrDepth(at, d, self.frames.length()))
      }
      let fi = self.frames.length() - 1 - d
      self.sim_trunc(self.frames[fi])
      self.unreach_ends = d + 1
      Ok(())
    }
    WBrIf(d) => {
      if d < 0 || d >= self.frames.length() {
        return Err(BadBrDepth(at, d, self.frames.length()))
      }
      self.sim_pop(WT_I32, at) // 条件 i32（fallthrough 路径继续）
      Ok(())
    }
    WUnreachable => {
      // unreachable 作用域 = 当前最内层块到其 end（非全部帧——LoadMem 的
      // NULL 检查块后指令仍可达；批 2a 对拍锚实锤修正）
      self.unreach_ends = 1
      Ok(())
    }
    WDrop => {
      self.sim_pop_any()
      Ok(())
    }
    WCall(0) => {
      // env.vitro_host_call(route_id:i32, argv_ptr:i32) -> i64（H2 单一
      // ABI——函数索引 0 约定，module.mbt 头注同源）
      self.sim_pop(WT_I32, at)
      self.sim_pop(WT_I32, at)
      self.stack.push(WT_I64)
      Ok(())
    }
    WCall(n) => Err(BadCallIdx(at, n))
    WLocalGet(i) =>
      match local_slot_type(i) {
        Some(t) => {
          self.stack.push(t)
          Ok(())
        }
        None => Err(BadSlot(at, i))
      }
    WLocalSet(i) =>
      match local_slot_type(i) {
        Some(t) => {
          self.sim_pop(t, at)
          Ok(())
        }
        None => Err(BadSlot(at, i))
      }
    WLocalTee(i) =>
      match local_slot_type(i) {
        Some(t) => {
          self.sim_pop(t, at)
          self.stack.push(t)
          Ok(())
        }
        None => Err(BadSlot(at, i))
      }
    WGlobalGet(i) =>
      match global_slot_type(i) {
        Some(t) => {
          self.stack.push(t)
          Ok(())
        }
        None => Err(BadSlot(at, i))
      }
    WGlobalSet(i) =>
      match global_slot_type(i) {
        Some(t) => {
          self.sim_pop(t, at)
          Ok(())
        }
        None => Err(BadSlot(at, i))
      }
    // ── 访存（地址全动态在栈上，静态 offset=0）──
    WI32Load => {
      self.sim_pop(WT_I32, at)
      self.stack.push(WT_I32)
      Ok(())
    }
    WI64Load => {
      self.sim_pop(WT_I32, at)
      self.stack.push(WT_I64)
      Ok(())
    }
    WF32Load => {
      self.sim_pop(WT_I32, at)
      self.stack.push(WT_F32)
      Ok(())
    }
    WF64Load => {
      self.sim_pop(WT_I32, at)
      self.stack.push(WT_F64)
      Ok(())
    }
    WI32Load8S | WI32Load8U => {
      self.sim_pop(WT_I32, at)
      self.stack.push(WT_I32)
      Ok(())
    }
    // store 族：栈 [addr, value]——先弹 value 再弹 addr（探针 §5.2 栈序
    // 红线，emit.mbt 头注同源）
    WI32Store => {
      self.sim_pop(WT_I32, at)
      self.sim_pop(WT_I32, at)
      Ok(())
    }
    WI64Store => {
      self.sim_pop(WT_I64, at)
      self.sim_pop(WT_I32, at)
      Ok(())
    }
    WF32Store => {
      self.sim_pop(WT_F32, at)
      self.sim_pop(WT_I32, at)
      Ok(())
    }
    WF64Store => {
      self.sim_pop(WT_F64, at)
      self.sim_pop(WT_I32, at)
      Ok(())
    }
    WI32Store8 => {
      self.sim_pop(WT_I32, at)
      self.sim_pop(WT_I32, at)
      Ok(())
    }
    // ── 常量 ──
    WI32Const(_) => {
      self.stack.push(WT_I32)
      Ok(())
    }
    WI64Const(_) => {
      self.stack.push(WT_I64)
      Ok(())
    }
    WF32Const(_) => {
      self.stack.push(WT_F32)
      Ok(())
    }
    WF64Const(_) => {
      self.stack.push(WT_F64)
      Ok(())
    }
    // ── i32 一元（eqz / extend8_s——TruncByte 直映是一元符号扩展）──
    WI32Eqz | WI32Extend8S => {
      self.sim_pop(WT_I32, at)
      self.stack.push(WT_I32)
      Ok(())
    }
    // ── i32 二元算术/位/移位（比较 push i32 布尔）──
    WI32Eq
    | WI32Ne
    | WI32LtS
    | WI32LtU
    | WI32GtS
    | WI32GtU
    | WI32LeS
    | WI32LeU
    | WI32GeS
    | WI32GeU
    | WI32Add
    | WI32Sub
    | WI32Mul
    | WI32DivS
    | WI32DivU
    | WI32RemS
    | WI32RemU
    | WI32And
    | WI32Or
    | WI32Xor
    | WI32Shl
    | WI32ShrS
    | WI32ShrU => {
      self.sim_pop(WT_I32, at)
      self.sim_pop(WT_I32, at)
      self.stack.push(WT_I32)
      Ok(())
    }
    // ── i64 移位（shift 操作数 i64 同型在顶——wasm 移位取模语义内建；
    //     批 2a 首版误记 [i64,i32] 签名，全语料 wabt validate 14 红
    //     （expected [i64, i64]）实锤勘正）──
    WI64Shl | WI64ShrS | WI64ShrU => {
      self.sim_pop(WT_I64, at)
      self.sim_pop(WT_I64, at)
      self.stack.push(WT_I64)
      Ok(())
    }
    // ── i64 比较（push i32 布尔）──
    WI64Eq
    | WI64Ne
    | WI64LtS
    | WI64LtU
    | WI64GtS
    | WI64GtU
    | WI64LeS
    | WI64LeU
    | WI64GeS
    | WI64GeU => {
      self.sim_pop(WT_I64, at)
      self.sim_pop(WT_I64, at)
      self.stack.push(WT_I32)
      Ok(())
    }
    // ── i64 二元算术/位 ──
    WI64Add
    | WI64Sub
    | WI64Mul
    | WI64DivS
    | WI64DivU
    | WI64RemS
    | WI64RemU
    | WI64And
    | WI64Or
    | WI64Xor => {
      self.sim_pop(WT_I64, at)
      self.sim_pop(WT_I64, at)
      self.stack.push(WT_I64)
      Ok(())
    }
    // ── f32 族（一元 neg / 二元算术 push f32，比较 push i32）──
    WF32Neg => {
      self.sim_pop(WT_F32, at)
      self.stack.push(WT_F32)
      Ok(())
    }
    WF32Add | WF32Sub | WF32Mul | WF32Div => {
      self.sim_pop(WT_F32, at)
      self.sim_pop(WT_F32, at)
      self.stack.push(WT_F32)
      Ok(())
    }
    WF32Eq | WF32Ne | WF32Lt | WF32Gt | WF32Le | WF32Ge => {
      self.sim_pop(WT_F32, at)
      self.sim_pop(WT_F32, at)
      self.stack.push(WT_I32)
      Ok(())
    }
    // ── f64 族 ──
    WF64Neg => {
      self.sim_pop(WT_F64, at)
      self.stack.push(WT_F64)
      Ok(())
    }
    WF64Add | WF64Sub | WF64Mul | WF64Div => {
      self.sim_pop(WT_F64, at)
      self.sim_pop(WT_F64, at)
      self.stack.push(WT_F64)
      Ok(())
    }
    WF64Eq | WF64Ne | WF64Lt | WF64Gt | WF64Le | WF64Ge => {
      self.sim_pop(WT_F64, at)
      self.sim_pop(WT_F64, at)
      self.stack.push(WT_I32)
      Ok(())
    }
    // ── 转换（直映/饱和/位拆）──
    WI32WrapI64 => {
      self.sim_pop(WT_I64, at)
      self.stack.push(WT_I32)
      Ok(())
    }
    WI64ExtendI32S | WI64ExtendI32U => {
      self.sim_pop(WT_I32, at)
      self.stack.push(WT_I64)
      Ok(())
    }
    WF32ConvertI32S | WF32ConvertI32U => {
      self.sim_pop(WT_I32, at)
      self.stack.push(WT_F32)
      Ok(())
    }
    WF32ConvertI64U => {
      self.sim_pop(WT_I64, at)
      self.stack.push(WT_F32)
      Ok(())
    }
    WF64ConvertI32S | WF64ConvertI32U => {
      self.sim_pop(WT_I32, at)
      self.stack.push(WT_F64)
      Ok(())
    }
    WF64ConvertI64S | WF64ConvertI64U => {
      self.sim_pop(WT_I64, at)
      self.stack.push(WT_F64)
      Ok(())
    }
    WF32DemoteF64 => {
      self.sim_pop(WT_F64, at)
      self.stack.push(WT_F32)
      Ok(())
    }
    WF64PromoteF32 => {
      self.sim_pop(WT_F32, at)
      self.stack.push(WT_F64)
      Ok(())
    }
    WI32TruncSatF32S => {
      self.sim_pop(WT_F32, at)
      self.stack.push(WT_I32)
      Ok(())
    }
    WI32TruncSatF64S => {
      self.sim_pop(WT_F64, at)
      self.stack.push(WT_I32)
      Ok(())
    }
    WI64TruncSatF64S | WI64TruncSatF64U => {
      self.sim_pop(WT_F64, at)
      self.stack.push(WT_I64)
      Ok(())
    }
    WI64ReinterpretF64 => {
      self.sim_pop(WT_F64, at)
      self.stack.push(WT_I64)
      Ok(())
    }
    // ── 批量内存（栈 [dst, src, n] / [dst, val, n] → 空）──
    WMemoryCopy => {
      self.sim_pop(WT_I32, at)
      self.sim_pop(WT_I32, at)
      self.sim_pop(WT_I32, at)
      Ok(())
    }
    WMemoryFill => {
      self.sim_pop(WT_I32, at)
      self.sim_pop(WT_I32, at)
      self.sim_pop(WT_I32, at)
      Ok(())
    }
  }
}

///|
/// WInstr 流线性栈模拟：返回 (前垫类型串〔底→顶〕, 尾剩余值数〔drop 数〕)。
/// 预置虚拟根帧 = 垫收壳组 block（BrAny(0) 的 depth 0 目标）；结果 pad
/// 恒为「让序列从空栈可跑」的最小前垫，residual = 结束时栈高（垫收后
/// drop 收走）——组独立包裹下每组净效应归零（block void + 前垫 + drop）。
fn seq_net_effect(
  instrs : Array[WInstr],
) -> Result[(Array[Byte], Int32), EffectError] {
  let sim : EffectSim = { stack: [], frames: [0], unreach_ends: 0, pad: [], }
  for i = 0; i < instrs.length(); i = i + 1 {
    let w = instrs[i]
    if sim.unreach_ends == 0 {
      match sim.sim_step(w, i) {
        Ok(_) => ()
        Err(e) => return Err(e)
      }
    } else {
      // unreachable 区：仅结构指令维护帧计数（br 的截断对垫需求无增益）
      match w {
        WBlock | WLoop => sim.frames.push(sim.stack.length())
        WEnd => {
          let h = sim.frames[sim.frames.length() - 1]
          let _ = sim.frames.remove(sim.frames.length() - 1)
          sim.sim_trunc(h)
          sim.unreach_ends = sim.unreach_ends - 1
        }
        _ => ()
      }
    }
  }
  // pad 反转成「底→顶」序（欠记序 = pop 序 = 顶→底；垫入与 witness 表
  // 语义都是底→顶——StoreMemD 族弹序「先值后址」的垫序「先址后值」，
  // 批 2a 对拍锚实锤）
  let ordered : Array[Byte] = []
  for k = sim.pad.length() - 1; k >= 0; k = k - 1 {
    ordered.push(sim.pad[k])
  }
  Ok((ordered, sim.stack.length()))
}

///|
/// 组操作模板效应（发射单源复用——`emit_group` 展开 + `seq_net_effect`
/// 模拟；效应与 operand 值无关（结构性的），仅取发射不失败的样值）。
fn template_net_effect(
  op : @opcode.OpCode,
  operand : Int32,
  ctx : EmitCtx,
) -> Result[(Array[Byte], Int32), EffectError] {
  match emit_group(op, operand, ctx) {
    Ok(instrs) => seq_net_effect(instrs)
    Err(_) =>
      // 发射失败（Reserved/域非法）不是效应面——空效应占位，消费方
      // （组装层）先行拒载 Reserved 组，不触达本形态
      Ok(([], 0))
  }
}
