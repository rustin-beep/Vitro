///|
/// **块划分器（REHOST 批 4a）**——dispatch-loop 语义模块的前置件：
/// 组序列 → 基本块表（leader 集），块边界值栈为空假设的**机检入口**
/// （jit_survey PoC 对 15 产物的人工假设〔translate.mjs:127「块出口栈
/// 非空」throw〕在此升格为装载期闸——出口栈非空 = 该程序进禁译面，
/// fail loud 不静默）。
///
/// **leader 规则**（VM 控制流语义对齐 `vm/exec_control.mbt`）：
/// - 程序入口 + 函数表全部入口 ip（CallPtr 运行期目标域 + Call 静态
///   目标必居其中）；
/// - Jump/JumpIfZero/JumpIfNotZero 的 taken 目标（operand = 重定位后
///   绝对 ip——消费方〔dispatchloop 组装器〕供给全程序组序列）；
/// - 控制流组（Jump 族/Call/CallVar/Ret/RetVoid）的后继（gip+1——
///   Call 返回点/Ret 后函数边界）。
///
/// **块出口栈空判据**（`blocks_exit_stacks_empty`）：逐块用效应模拟器
/// （effect.mbt 同源）从空栈模拟组序列（A/B 类模板字节 + C 类「执行
/// 形态效应」——C 类组的模板是微缩形态〔批 1b：只设 pc〕，执行形态
/// 的效应由本模块显式声明〔Call 消费 param_words 个 i32 之类〕），块
/// 尾净高非零 → Err（该程序非块化可执行形态，进禁译面登记）。
///
/// **返回值通道（批 4a 架构决策，2026-11-14）**：函数调用的返回值
/// **不经 wasm 栈跨块存续**（Call 后继是块边界、br_table 要求块入口
/// 栈一致——跨块值破坏分发骨架）——Ret 存 `G_RV`、返回点块开头
/// `global.get G_RV` 压回 wasm 栈（void 调用不 load——func metas 侧车
/// 带 void 位）；块边界栈空由该约定保持。返回值正路径的**指令流级**
/// 验证（含 load/store 展开）随 dispatchloop 组装器锚（组装器产完整
/// 执行形态指令流后以效应模拟器逐块复核——本函数的组序列口径是它的
/// 粗前置）。

///|
/// 块划分错误。
#derive(Debug, Eq)
pub(all) enum BlocksError {
  /// 入口/跳转目标/函数入口越界（组序列外的 ip——组序列与元数据不符）
  BadTarget(Int32, Int32)
  /// 块出口值栈非空（块 gip 区间 + 残留高度——块化执行前提破坏：
  /// PoC 假设升格的机检形态；该程序进禁译面，不静默）
  ExitStackNonEmpty(Int32, Int32, Int32)
  /// CallPtr 出现在组序列（首版禁译——运行期 func meta 查表的搬运
  /// 序列无法静态展开，fail loud 归 4b 闸的禁译登记）
  CallPtrUnsupported(Int32)
  /// 效应模拟失败（模板形状缺陷透传）
  Effect(EffectError)
  /// 组发射失败（禁译面/操作数域非法——单行文本形态：EmitError 无
  /// Debug/Eq derive，装 String 保持本枚举可 derive）
  Emit(String)
}

///|
pub extend BlocksError with Debug::{to_repr}

///|
pub extend BlocksError with Eq::{not_equal, equal}

///|
/// 块表（升序起点；块 k = [starts[k], starts[k+1])，末块到组总数）。
pub(all) struct BlockTable {
  /// 块起点 gip 集（升序、去重；块 0 起点恒 0 或入口所在组——由调用方
  /// 保证入口 ip 在 leader 集内）
  starts : Array[Int32]
}

///|
/// 组序列（op/operand 投影）+ 函数入口集 → 块表。
/// `ops`/`operands` 等长（gip = 下标）；`func_entry_ips` = 函数表全部
/// 入口（重定位后绝对 ip 域）；`entry_ip` = 程序入口。
pub fn partition_blocks(
  ops : Array[@opcode.OpCode],
  operands : Array[Int32],
  func_entry_ips : Array[Int32],
  entry_ip : Int32,
) -> Result[BlockTable, BlocksError] {
  let n = ops.length()
  if operands.length() != n {
    return Err(BadTarget(-1, operands.length()))
  }
  // leader 集：入口 + 函数入口 + 跳转目标 + 控制流后继
  let leader : Set[Int32] = Set([])
  // 内嵌 fn 无 raise 面——越界以 false 返回、调用点统一 fail loud
  fn add_leader(ip : Int32) -> Bool {
    if ip < 0 || ip >= n {
      return false
    }
    leader.add(ip)
    true
  }
  if !add_leader(entry_ip) {
    return Err(BadTarget(entry_ip, n))
  }
  for ip in func_entry_ips {
    if !add_leader(ip) {
      return Err(BadTarget(ip, n))
    }
  }
  for gip = 0; gip < n; gip = gip + 1 {
    let op = ops[gip]
    let operand = operands[gip]
    match op {
      Jump | JumpIfZero | JumpIfNotZero => {
        if !add_leader(operand) {
          return Err(BadTarget(operand, n))
        }
        if gip + 1 < n {
          leader.add(gip + 1)
        }
      }
      // Call 静态目标 = 函数头（已在 func_entry_ips leader 集内，此处
      // 补越界防御）；后继 = 返回点
      Call => {
        if !func_entry_ips.contains(operand) {
          return Err(BadTarget(operand, n))
        }
        if gip + 1 < n {
          leader.add(gip + 1)
        }
      }
      // CallVar 静态可解（operand = 函数下标——目标 ip 由调用方重定位
      // 进 operands？批 4a 约定：CallVar 的 operand 在执行形态输入里
      // **已重写为目标 ip**〔与 Call 同域〕——组装器预处理职责）
      CallVar => {
        if !func_entry_ips.contains(operand) {
          return Err(BadTarget(operand, n))
        }
        if gip + 1 < n {
          leader.add(gip + 1)
        }
      }
      Ret | RetVoid => if gip + 1 < n { leader.add(gip + 1) }
      // 首版禁译（运行期目标——meta 查表搬运不可静态展开）
      CallPtr => return Err(CallPtrUnsupported(gip))
      _ => ()
    }
  }
  let starts : Array[Int32] = []
  for ip in leader {
    starts.push(ip)
  }
  // Set 无序——排序（块表升序不变量）
  for i = 1; i < starts.length(); i = i + 1 {
    let key = starts[i]
    let mut j = i - 1
    while j >= 0 && starts[j] > key {
      starts[j + 1] = starts[j]
      j = j - 1
    }
    starts[j + 1] = key
  }
  Ok({ starts, })
}

///|
/// C 类组「执行形态」的净效应（栈消费 word 数——i32 口径；批 4a 协议：
/// Call/CallVar 消费全部参数 word（param_sizes+变参——调用方按 meta 算
/// 好）、Ret 消费返回值、JumpIf 族消费条件 1 word、Jump/RetVoid/CallHost
/// 零消费〔CallHost 的参数走内存约定区不走值栈——H2 ABI〕）。
/// i64/f64 参数按 2 word 计（param_sizes 本身是 word 数口径——真值侧
/// `do_call` 的 param_sizes 逐参 word 数同源）。
pub fn control_pop_words(op : @opcode.OpCode) -> Int32 {
  match op {
    Jump | RetVoid => 0
    JumpIfZero | JumpIfNotZero => 1
    Ret => 1
    _ => 0
  }
}

///|
/// 块出口栈空验证（装载期闸——PoC 假设的机检升格）：逐块从空值栈模拟，
/// 块尾净高非零 → Err。模拟口径：
/// - A/B 类组：模板字节真效应（emit_group + 效应模拟器——与垫收组装
///   同源单源）；
/// - C 类组：`control_pop_words` 显式声明（微缩模板的效应与执行形态
///   不一致〔批 1b 微缩只设 pc 不消费参数〕——执行形态口径在本侧）。
/// `call_arg_words(gip)` = Call/CallVar 组的参数 word 数（调用方按
/// func_table meta 算好供给——组装器职责域）。
pub fn blocks_exit_stacks_empty(
  ops : Array[@opcode.OpCode],
  operands : Array[Int32],
  blocks : BlockTable,
  call_arg_words : (Int32) -> Int32,
  ctx : EmitCtx,
) -> Result[Unit, BlocksError] {
  let n = ops.length()
  let ns = blocks.starts.length()
  for k = 0; k < ns; k = k + 1 {
    let start = blocks.starts[k]
    let end = if k + 1 < ns { blocks.starts[k + 1] } else { n }
    // 块内逐组模拟（高水位计数——i32/i64/f64 统一按「项」计，块尾判
    // 归零；项计数比类型计数弱的形态登记：类型混排错序的块越界形态
    // 由 wasm-validate 兜底〔4b 闸〕，本闸只锁「高度」不变量）
    let mut height = 0
    for gip = start; gip < end; gip = gip + 1 {
      let op = ops[gip]
      match op {
        Jump | JumpIfZero | JumpIfNotZero | Call | CallVar | Ret | RetVoid => {
          let pops = control_pop_words(op) +
            (match op {
              Call | CallVar => call_arg_words(gip)
              _ => 0
            })
          height = height - pops
          if height < 0 {
            return Err(ExitStackNonEmpty(gip, height, 0))
          }
        }
        _ => {
          // A/B 类组：模板真效应（模拟器单源）——净效应 = drops − pads
          //（垫收协议：前垫 p + 组体 + drop d 恰平衡 ⇒ 净产 = d − p；
          // 连续拼接形态：入口高 ≥ p 即合法直落，欠垫形态〔入口高不足〕
          // 由 wasm-validate 兜底〔4b 闸〕，本闸只锁「高度」不变量）
          let group = match emit_group(op, operands[gip], ctx) {
            Ok(g) => g
            Err(NotImplemented(m)) => return Err(Emit("NotImplemented: " + m))
            Err(BadOperand(m)) => return Err(Emit("BadOperand: " + m))
          }
          let (pads, drops) = match seq_net_effect(group) {
            Ok(t) => t
            Err(e) => return Err(Effect(e))
          }
          height = height + drops - pads.length()
        }
      }
      if height < 0 {
        return Err(ExitStackNonEmpty(gip, height, 0))
      }
    }
    if height != 0 {
      return Err(ExitStackNonEmpty(start, height, k))
    }
  }
  Ok(())
}
