///|
/// **垫收模块组装器（L1，REHOST 批 2a）**——产物指令区字节 → 完整合法
/// wasm 模块（`wasm-validate` 内容级真验证的证人载体——PR #505 审阅
/// P1-2 的升级件：批 1c 证人壳直塞指令片段只过 `readWasm` 解码级验证
/// （类型错/栈下溢均放行），本组装器按组栈效应垫收后过 `m.validate()`
/// 真验证）。**证人模块，非产物**——dispatch-loop 语义模块（V8/wasmtime
/// 可执行形态）是批 5 的面；本模块只证「产物指令区字节在合法模块语境
/// 下过标准验证器」。
///
/// **垫收协议**（watcheck 的 PUSHERS/drop 约定机器化——批 1c 人工 150
/// 行表的自动化形态）：
/// - 每组独立包裹 `block void` + 按效应前垫（零值常量：i32/i64/f32/f64）
///   + 组原始指令 + `drop`×尾剩余 + `end`——组间互不影响（每组净效应
///   归零，拼接任意组序列恒平衡）；
/// - 组边界 = 组表侧车（`instr_offset`/`instr_len`——覆盖不完整/越界
///   fail loud，与 `verify_fold_with_table` 的 GroupGap/TrailingInstrs
///   同族防线）；
/// - 效应推导 = `seq_net_effect`（effect.mbt——WInstr 穷尽 match 单源，
///   与 witness 人工表逐行对拍锁定）。
///
/// **装载约定镜像**（templates.mbt 槽表同源）：type 段两型（`()->()`
/// main + `(i32,i32)->i64` host ABI）；import 段唯一 `env.vitro_host_call`
/// @ 函数索引 0（CallHost 模板 `call 0` 的解析目标——批 1c 证人壳缺
/// import 段镜像的审阅遗留在此补齐）；memory `{16,16}` 恰 1MB；globals
/// 6 槽（G_PC..G_RET = i32 mut ×5 + G_RV = i64 mut）；locals 4 runs
/// （3×i32 + i64 + f64 + f32）；export main/memory。

///|
/// 组装错误（全部 fail loud）。
#derive(Debug)
pub(all) enum AssembleError {
  /// 指令区解码失败（携带字节偏移与原因——非本发射器字节形态）
  Decode(Int32, DecodeError)
  /// 组 gip 边界越界（offset/len 超出指令流——组表与字节流不符）
  BadBoundary(Int32, Int32, Int32)
  /// 组表未覆盖整段指令流（首组前/组间/尾随——expected/actual 偏移）
  NotCovered(Int32, Int32)
  /// 效应推导失败（模板/指令形状缺陷——透传）
  Effect(EffectError)
}

///|
pub extend AssembleError with Debug::{to_repr}

///|
/// 效应前垫指令（零值常量——witness 壳 PUSHERS 同款：i=[i32.const 0]、
/// I=[i64.const 0]、f=[f32.const 0]、d=[f64.const 0]）。
fn pad_instr(t : Byte) -> WInstr {
  match t {
    WT_I32 => WI32Const(0)
    WT_I64 => WI64Const(0L)
    WT_F32 => WF32Const(0.0)
    _ => WF64Const(0.0)
  }
}

///|
/// 单组垫收包裹：`block + 前垫 + 组指令 + drop×n + end`（净效应归零——
/// 组间拼接恒平衡的单元形态）。
fn wrap_group(group : Array[WInstr]) -> Result[Array[WInstr], EffectError] {
  let (pad, drops) = match seq_net_effect(group) {
    Ok(t) => t
    Err(e) => return Err(e)
  }
  let out : Array[WInstr] = [WBlock]
  for t in pad {
    out.push(pad_instr(t))
  }
  for w in group {
    out.push(w)
  }
  for k = 0; k < drops; k = k + 1 {
    out.push(WDrop)
  }
  out.push(WEnd)
  Ok(out)
}

///|
/// 组表 + 指令区字节 → 完整证人模块（垫收协议见文件头注；组表为空 =
/// 空程序——单 `end` 体，合法最小模块）。
pub fn assemble_witness_module(
  table : GroupTable,
  bytes : Array[Byte],
) -> Result[Array[Byte], AssembleError] {
  // 1. 解码全量（产物字节 → 指令流）
  let instrs = match winstr_decode_all(bytes) {
    Ok(instrs) => instrs
    Err(e) => {
      // 解码错误定位（fold.mbt 同款重扫——诊断对位产物字节）
      let mut pos = 0
      while pos < bytes.length() {
        match winstr_decode(bytes, pos) {
          Ok((_, n)) => pos = pos + n
          Err(_) => return Err(Decode(pos, e))
        }
      }
      return Err(Decode(bytes.length(), e))
    }
  }
  // 2. 逐组切分 + 垫收包裹（连续性游标——组表覆盖完整性独立防线，
  //    与 verify_fold_with_table 同族：装载核对先行时恒绿，此处是组装
  //    作为独立 pub API 的第二道）
  let body : Array[WInstr] = []
  let mut expected = 0
  for g in table.groups {
    if g.instr_offset != expected {
      return Err(NotCovered(expected, g.instr_offset))
    }
    if g.instr_offset < 0 ||
      g.instr_len < 0 ||
      g.instr_offset + g.instr_len > instrs.length() {
      return Err(BadBoundary(g.gip, g.instr_offset, g.instr_len))
    }
    let group : Array[WInstr] = []
    for k = 0; k < g.instr_len; k = k + 1 {
      group.push(instrs[g.instr_offset + k])
    }
    match wrap_group(group) {
      Ok(wrapped) =>
        for w in wrapped {
          body.push(w)
        }
      Err(e) => return Err(Effect(e))
    }
    expected = g.instr_offset + g.instr_len
  }
  if expected != instrs.length() {
    return Err(NotCovered(expected, instrs.length()))
  }
  // 3. 段拼装（装载约定镜像——文件头注）
  let b = ModuleBuilder::new()
  let t_main = b.add_type([], [])
  let t_host = b.add_type([WT_I32, WT_I32], [WT_I64])
  // import 唯一：env.vitro_host_call @ 函数索引 0（H2 单一 ABI）
  let _ = b.add_import("env", "vitro_host_call", 0, t_host)
  // locals：L_V/L_A/L_N(i32) + L_T64(i64) + L_TF(f64) + L_TF32(f32)
  //（4 runs——批 1b 装载约定，emitgate 证人壳同款）
  let main_idx = b.add_func(t_main, {
    locals: [(3, WT_I32), (1, WT_I64), (1, WT_F64), (1, WT_F32)],
    body,
  })
  let _ = b.add_memory(16, Some(16))
  // globals：G_PC/G_FB/G_STEPS/G_SPT/G_RET（i32 mut）+ G_RV（i64 mut）
  let _ = b.add_global(WT_I32, true, WI32Const(0)) // 0: G_PC
  let _ = b.add_global(WT_I32, true, WI32Const(0)) // 1: G_FB
  let _ = b.add_global(WT_I32, true, WI32Const(0)) // 2: G_STEPS
  let _ = b.add_global(WT_I32, true, WI32Const(0)) // 3: G_SPT
  let _ = b.add_global(WT_I32, true, WI32Const(0)) // 4: G_RET
  let _ = b.add_global(WT_I64, true, WI64Const(0L)) // 5: G_RV
  b.add_export("main", 0, main_idx) // 本地函数索引（import 占 0）
  b.add_export("memory", 2, 0)
  Ok(b.build())
}
