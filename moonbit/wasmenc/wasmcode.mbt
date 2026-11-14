///|
/// wasm 子集指令面（L0 机械件）：`WInstr` 枚举 + 字节编码/解码。
///
/// 覆盖面 = A 类（完全一致直映）84 条（批 1a 基线 83 + CastD2UQ）opcode 映射到的全部
/// wasm 指令 + 模块级闭环所需最小控制流（block/loop/br/end/unreachable）
/// + 变量族（local/global）+ **批 1b 扩面**：访存族（i32/i64/f32/f64 的
/// load/store 全宽度 + 1 字节粒度——自然对齐 + 静态 offset=0 形态，地址
/// 全动态在栈上）/ i64 移位族 / i64.reinterpret_f64 / memory.copy·fill
/// （bulk-memory，wasm 2.0 基线）/ call（CallHost 的 H2 import 面）。
/// **不在面内的指令解码即 `UnknownOpcode`**——折叠侧 fail loud 的
/// 「非本发射器产物」判据（探针 2 [三]：库外指令/同型未实现指令拒载）。
///
/// 码位以 wasm MVP + sign-extension-ops + nontrapping trunc + bulk-memory
/// （均并入 wasm 2.0 基线）为准；`wasmenc_wbtest` 的 spec 码位断言锚定
/// 发射/折叠共享枚举的自洽盲区（码位写错往返仍绿——双实现税的最低成本
/// 防线），批 1a/1b 开发期另经探针工程 wabt 外部验证（报告 §外部证人）。
#derive(Eq, Compare, Debug)
pub(all) enum WInstr {
  // ── 控制流（模块级闭环最小集；C 类 dispatch-loop 模板批 1b/1c）──
  WUnreachable
  WNop
  WBlock // block void（嵌套深度由发射器 label 栈管——折叠侧解码不还原）
  WLoop
  WIf // if void（批 4a dispatch 骨架：预算/深度检查的 trap 出口）——解码不跟（同 WBrTable 边界）
  WReturn // 0x0F（批 4a 骨架：出口块 return G_RV / 预算 return -1）——解码不跟
  WEnd
  WBr(Int32) // 相对深度（uleb）
  WBrIf(Int32)
  // br_table（REHOST 批 4a——dispatch-loop 分发骨架专用）：标签向量 +
  // default 深度。**解码器不跟**（dispatch 模块字节是执行产物、非折叠
  // 管线对象——winstr_decode 遇 0x0E fail loud 即边界；垫收证人模块
  // 〔assemble_witness_module〕不产此指令）。
  WBrTable(Array[Int32], Int32)
  // ── 参数 ──
  WDrop
  // ── 调用（CallHost 的 H2 单一 ABI 面：批 1b 约定函数索引 0 =
  // `env.vitro_host_call(route_id, argv_ptr) -> i64` import）──
  WCall(Int32)
  // ── 变量（批 1b 预留：Dup/Swap 暂存重排、$steps/$pc/$fb 专用槽）──
  WLocalGet(Int32)
  WLocalSet(Int32)
  WLocalTee(Int32)
  WGlobalGet(Int32)
  WGlobalSet(Int32)
  // ── 访存（批 1b：自然对齐 + 静态 offset=0——地址全动态在栈上，
  // NULL 区检查由模板序列显式发射，上界=16 页 memory 白送）──
  WI32Load
  WI64Load
  WF32Load
  WF64Load
  WI32Load8S
  WI32Load8U
  WI32Store
  WI64Store
  WF32Store
  WF64Store
  WI32Store8
  // ── 常量 ──
  WI32Const(Int32) // sleb 立即数（i32 域）
  WI64Const(Int64) // sleb 立即数（i64 域）
  WF32Const(Float) // 4 字节小端 IEEE754 位（位模式无损往返）
  WF64Const(Double) // 8 字节小端
  // ── i32 数值 ──
  WI32Eqz
  WI32Eq
  WI32Ne
  WI32LtS
  WI32LtU
  WI32GtS
  WI32GtU
  WI32LeS
  WI32LeU
  WI32GeS
  WI32GeU
  WI32Add
  WI32Sub
  WI32Mul
  WI32DivS // trap 面：除零 + INT_MIN/-1（与现役 Div 同构——A 类直映依据）
  WI32DivU
  WI32RemS
  WI32RemU
  WI32And
  WI32Or
  WI32Xor
  WI32Extend8S // sign-extension-ops（0xC0——wabt wat→wasm 编译实证；TruncByte 直映）
  // 移位族（B 类 Shl/Shr/LShr 域检查模板的域内指令——面内可解，批 1b 接模板）
  WI32Shl
  WI32ShrS
  WI32ShrU
  // i64 移位族（批 1b：ShlQ/ShrQ/LShrQ 域检查模板的域内指令）
  WI64Shl
  WI64ShrS
  WI64ShrU
  // ── i64 数值 ──
  WI64Eq
  WI64Ne
  WI64LtS
  WI64LtU
  WI64GtS
  WI64GtU
  WI64LeS
  WI64LeU
  WI64GeS
  WI64GeU
  WI64Add
  WI64Sub
  WI64Mul
  WI64DivS
  WI64DivU
  WI64RemS
  WI64RemU
  WI64And
  WI64Or
  WI64Xor
  // ── f32 数值 ──
  WF32Eq
  WF32Ne
  WF32Lt
  WF32Gt
  WF32Le
  WF32Ge
  WF32Add
  WF32Sub
  WF32Mul
  WF32Div // IEEE 除零 = ±inf/NaN 不 trap（#163 与现役 DivF 同口径）
  WF32Neg // 保留 -0.0 位（现役 NegF 一元负同语义）
  // ── f64 数值 ──
  WF64Eq
  WF64Ne
  WF64Lt
  WF64Gt
  WF64Le
  WF64Ge
  WF64Add
  WF64Sub
  WF64Mul
  WF64Div
  WF64Neg
  // ── 转换 ──
  WI32WrapI64 // CastQ2I
  WI64ExtendI32S // CastI2Q
  WI64ExtendI32U // CastU2Q
  WF32ConvertI32S // CastI2F
  WF32ConvertI32U // CastU2F
  WF32ConvertI64U // CastUQ2F
  WF64ConvertI32S // CastI2D
  WF64ConvertI32U // CastU2D
  WF64ConvertI64S // CastQ2D
  WF64ConvertI64U // CastUQ2D
  WF32DemoteF64 // CastD2F
  WF64PromoteF32 // CastF2D
  WI32TruncSatF32S // CastF2I（饱和——NaN→0/inf→±MAX，现役同语义）
  WI32TruncSatF64S // CastD2I
  WI64TruncSatF64S // CastD2Q
  WI64TruncSatF64U // CastD2UQ（#471 饱和无符号——负→0/≥2^64→MAX，随 #485 连坐）
  WI64ReinterpretF64 // SplitD 首步（位拆——f64 位模式直转 i64）
  // ── 批量内存（批 1b：Memcpy/Memset——wasm 2.0 bulk-memory 基线；
  // memory.copy 为 memmove 语义，与现役临时缓冲实现等价〔O3 亲读对账〕）──
  WMemoryCopy
  WMemoryFill
}

///|
pub extend WInstr with Eq::{not_equal, equal}

///|
pub extend WInstr with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend WInstr with Debug::{to_repr}

///|
/// wasm 值类型字节（段结构用：0x7F=i32 / 0x7E=i64 / 0x7D=f32 / 0x7C=f64 /
/// 0x40=void）。
pub const WT_I32 : Byte = 0x7F

///|
pub const WT_I64 : Byte = 0x7E

///|
pub const WT_F32 : Byte = 0x7D

///|
pub const WT_F64 : Byte = 0x7C

///|
pub const WT_VOID : Byte = 0x40

///|
/// f32 位模式小端 4 字节（wasm f32.const 立即数形态——位模式无损，
/// PushConstF 的 operand 即此位模式）。
fn f32_le_bytes(v : Float) -> Array[Byte] {
  let bits = v.reinterpret_as_uint()
  [
    (bits & 0xFFU).reinterpret_as_int().to_byte(),
    ((bits >> 8) & 0xFFU).reinterpret_as_int().to_byte(),
    ((bits >> 16) & 0xFFU).reinterpret_as_int().to_byte(),
    ((bits >> 24) & 0xFFU).reinterpret_as_int().to_byte(),
  ]
}

///|
/// f64 位模式小端 8 字节。
fn f64_le_bytes(v : Double) -> Array[Byte] {
  let bits = v.reinterpret_as_uint64()
  let out : Array[Byte] = []
  for i = 0; i < 8; i = i + 1 {
    let shift = i * 8
    out.push(
      ((bits >> shift) & 0xFFUL).to_uint().reinterpret_as_int().to_byte(),
    )
  }
  out
}

///|
/// 小端 4 字节 → f32（f32_le_bytes 逆）。
fn f32_from_le_bytes(b : Array[Byte], pos : Int32) -> Float {
  let mut bits = 0U
  for i = 0; i < 4; i = i + 1 {
    bits = bits | (b[pos + i].to_uint() << (i * 8))
  }
  Float::reinterpret_from_uint(bits)
}

///|
/// 小端 8 字节 → f64。
fn f64_from_le_bytes(b : Array[Byte], pos : Int32) -> Double {
  let mut bits = 0UL
  for i = 0; i < 8; i = i + 1 {
    bits = bits | (b[pos + i].to_uint64() << (i * 8))
  }
  UInt64::reinterpret_as_double(bits)
}

///|
/// 单指令编码（追加到 out；失败=未知构造器——穷尽 match 保零遗漏）。
fn winstr_encode_into(instr : WInstr, out : Array[Byte]) -> Unit {
  fn pushOp(op : Int32, out : Array[Byte]) -> Unit {
    out.push(op.to_byte())
  }
  match instr {
    WUnreachable => pushOp(0x00, out)
    WNop => pushOp(0x01, out)
    WBlock => {
      pushOp(0x02, out)
      out.push(WT_VOID)
    }
    WLoop => {
      pushOp(0x03, out)
      out.push(WT_VOID)
    }
    WEnd => pushOp(0x0B, out)
    WBr(depth) => {
      pushOp(0x0C, out)
      for b in uleb_encode(depth.to_uint64()) {
        out.push(b)
      }
    }
    WBrIf(depth) => {
      pushOp(0x0D, out)
      for b in uleb_encode(depth.to_uint64()) {
        out.push(b)
      }
    }
    WIf => {
      pushOp(0x04, out)
      out.push(WT_VOID)
    }
    WReturn => pushOp(0x0F, out)
    WBrTable(labels, default) => {
      // 0x0E + vec(labels: uleb 深度) + default（uleb）——dispatch-loop
      // 分发骨架：标签逐 ip 填块索引、default = 出口/unreachable
      pushOp(0x0E, out)
      for b in uleb_encode(labels.length().to_uint64()) {
        out.push(b)
      }
      for l in labels {
        for b in uleb_encode(l.to_uint64()) {
          out.push(b)
        }
      }
      for b in uleb_encode(default.to_uint64()) {
        out.push(b)
      }
    }
    WDrop => pushOp(0x1A, out)
    WCall(idx) => {
      pushOp(0x10, out)
      for b in uleb_encode(idx.to_uint64()) {
        out.push(b)
      }
    }
    WLocalGet(idx) => {
      pushOp(0x20, out)
      for b in uleb_encode(idx.to_uint64()) {
        out.push(b)
      }
    }
    WLocalSet(idx) => {
      pushOp(0x21, out)
      for b in uleb_encode(idx.to_uint64()) {
        out.push(b)
      }
    }
    WLocalTee(idx) => {
      pushOp(0x22, out)
      for b in uleb_encode(idx.to_uint64()) {
        out.push(b)
      }
    }
    WGlobalGet(idx) => {
      pushOp(0x23, out)
      for b in uleb_encode(idx.to_uint64()) {
        out.push(b)
      }
    }
    WGlobalSet(idx) => {
      pushOp(0x24, out)
      for b in uleb_encode(idx.to_uint64()) {
        out.push(b)
      }
    }
    WI32Const(v) => {
      pushOp(0x41, out)
      for b in sleb_encode(v.to_int64()) {
        out.push(b)
      }
    }
    // 访存族（批 1b）：自然对齐 uleb + 静态 offset=0——两立即数形态
    // （align = log2(访问宽度)：load8/store8=0 / i32·f32=2 / i64·f64=3）
    WI32Load => mem_access(0x28, 2, out)
    WI64Load => mem_access(0x29, 3, out)
    WF32Load => mem_access(0x2A, 2, out)
    WF64Load => mem_access(0x2B, 3, out)
    WI32Load8S => mem_access(0x2C, 0, out)
    WI32Load8U => mem_access(0x2D, 0, out)
    WI32Store => mem_access(0x36, 2, out)
    WI64Store => mem_access(0x37, 3, out)
    WF32Store => mem_access(0x38, 2, out)
    WF64Store => mem_access(0x39, 3, out)
    WI32Store8 => mem_access(0x3A, 0, out)
    WI64Const(v) => {
      pushOp(0x42, out)
      for b in sleb_encode(v) {
        out.push(b)
      }
    }
    WF32Const(v) => {
      pushOp(0x43, out)
      for b in f32_le_bytes(v) {
        out.push(b)
      }
    }
    WF64Const(v) => {
      pushOp(0x44, out)
      for b in f64_le_bytes(v) {
        out.push(b)
      }
    }
    // i32 比较/算术/位（0x45-0x4F / 0x6A-0x76 / 0xC4-0xC5）
    WI32Eqz => pushOp(0x45, out)
    WI32Eq => pushOp(0x46, out)
    WI32Ne => pushOp(0x47, out)
    WI32LtS => pushOp(0x48, out)
    WI32LtU => pushOp(0x49, out)
    WI32GtS => pushOp(0x4A, out)
    WI32GtU => pushOp(0x4B, out)
    WI32LeS => pushOp(0x4C, out)
    WI32LeU => pushOp(0x4D, out)
    WI32GeS => pushOp(0x4E, out)
    WI32GeU => pushOp(0x4F, out)
    WI32Add => pushOp(0x6A, out)
    WI32Sub => pushOp(0x6B, out)
    WI32Mul => pushOp(0x6C, out)
    WI32DivS => pushOp(0x6D, out)
    WI32DivU => pushOp(0x6E, out)
    WI32RemS => pushOp(0x6F, out)
    WI32RemU => pushOp(0x70, out)
    WI32And => pushOp(0x71, out)
    WI32Or => pushOp(0x72, out)
    WI32Xor => pushOp(0x73, out)
    WI32Shl => pushOp(0x74, out)
    WI32ShrS => pushOp(0x75, out)
    WI32ShrU => pushOp(0x76, out)
    // i64 移位（0x86-0x88）
    WI64Shl => pushOp(0x86, out)
    WI64ShrS => pushOp(0x87, out)
    WI64ShrU => pushOp(0x88, out)
    WI32Extend8S => pushOp(0xC0, out)
    // i64 比较/算术（0x51-0x5A / 0x7C-0x85）
    WI64Eq => pushOp(0x51, out)
    WI64Ne => pushOp(0x52, out)
    WI64LtS => pushOp(0x53, out)
    WI64LtU => pushOp(0x54, out)
    WI64GtS => pushOp(0x55, out)
    WI64GtU => pushOp(0x56, out)
    WI64LeS => pushOp(0x57, out)
    WI64LeU => pushOp(0x58, out)
    WI64GeS => pushOp(0x59, out)
    WI64GeU => pushOp(0x5A, out)
    WI64Add => pushOp(0x7C, out)
    WI64Sub => pushOp(0x7D, out)
    WI64Mul => pushOp(0x7E, out)
    WI64DivS => pushOp(0x7F, out)
    WI64DivU => pushOp(0x80, out)
    WI64RemS => pushOp(0x81, out)
    WI64RemU => pushOp(0x82, out)
    WI64And => pushOp(0x83, out)
    WI64Or => pushOp(0x84, out)
    WI64Xor => pushOp(0x85, out)
    // f32 比较/算术（0x5B-0x60 / 0x8C / 0x92-0x95）
    WF32Eq => pushOp(0x5B, out)
    WF32Ne => pushOp(0x5C, out)
    WF32Lt => pushOp(0x5D, out)
    WF32Gt => pushOp(0x5E, out)
    WF32Le => pushOp(0x5F, out)
    WF32Ge => pushOp(0x60, out)
    WF32Add => pushOp(0x92, out)
    WF32Sub => pushOp(0x93, out)
    WF32Mul => pushOp(0x94, out)
    WF32Div => pushOp(0x95, out)
    WF32Neg => pushOp(0x8C, out)
    // f64 比较/算术（0x61-0x66 / 0x9A / 0xA0-0xA3）
    WF64Eq => pushOp(0x61, out)
    WF64Ne => pushOp(0x62, out)
    WF64Lt => pushOp(0x63, out)
    WF64Gt => pushOp(0x64, out)
    WF64Le => pushOp(0x65, out)
    WF64Ge => pushOp(0x66, out)
    WF64Add => pushOp(0xA0, out)
    WF64Sub => pushOp(0xA1, out)
    WF64Mul => pushOp(0xA2, out)
    WF64Div => pushOp(0xA3, out)
    WF64Neg => pushOp(0x9A, out)
    // 转换（0xA7/0xAC-0xAD/0xB2-0xBB + trunc_sat 0xfc 前缀子码）
    WI32WrapI64 => pushOp(0xA7, out)
    WI64ExtendI32S => pushOp(0xAC, out)
    WI64ExtendI32U => pushOp(0xAD, out)
    WF32ConvertI32S => pushOp(0xB2, out)
    WF32ConvertI32U => pushOp(0xB3, out)
    WF32ConvertI64U => pushOp(0xB5, out)
    WF64ConvertI32S => pushOp(0xB7, out)
    WF64ConvertI32U => pushOp(0xB8, out)
    WF64ConvertI64S => pushOp(0xB9, out)
    WF64ConvertI64U => pushOp(0xBA, out)
    WF32DemoteF64 => pushOp(0xB6, out)
    WF64PromoteF32 => pushOp(0xBB, out)
    WI32TruncSatF32S => trunc_sat(0x00, out)
    WI32TruncSatF64S => trunc_sat(0x02, out)
    WI64TruncSatF64S => trunc_sat(0x06, out)
    WI64TruncSatF64U => trunc_sat(0x07, out)
    WI64ReinterpretF64 => pushOp(0xBD, out)
    // bulk-memory（0xFC 前缀子码）：copy=0x0A 双 memidx（dst/src）、
    // fill=0x0B 单 memidx（规范形态——fill 只操作一个 memory；watcheck
    // 逐字节对拍实锤本处曾多发一个 0x00：validate 不拦的字节错位面，
    // 多余 0x00 被验证器当下一条指令解析）
    WMemoryCopy => bulk_mem(0x0A, out)
    WMemoryFill => bulk_fill(0x0B, out)
  }
}

///|
/// 访存指令编码（opcode + 对齐 uleb + 静态 offset=0 uleb）。
fn mem_access(op : Int32, align : Int32, out : Array[Byte]) -> Unit {
  out.push(op.to_byte())
  for b in uleb_encode(align.to_uint64()) {
    out.push(b)
  }
  out.push((0x00).to_byte())
}

///|
/// bulk-memory copy 前缀编码（0xFC + 子码 uleb + dst/src memidx 各 0x00
/// ——单 memory 模块两索引恒 0）。
fn bulk_mem(sub : Int32, out : Array[Byte]) -> Unit {
  out.push((0xFC).to_byte())
  for b in uleb_encode(sub.to_uint64()) {
    out.push(b)
  }
  out.push((0x00).to_byte())
  out.push((0x00).to_byte())
}

///|
/// bulk-memory fill 前缀编码（0xFC + 子码 uleb + 单 memidx 0x00——
/// 规范形态 fill 只操作一个 memory，单索引）。
fn bulk_fill(sub : Int32, out : Array[Byte]) -> Unit {
  out.push((0xFC).to_byte())
  for b in uleb_encode(sub.to_uint64()) {
    out.push(b)
  }
  out.push((0x00).to_byte())
}

///|
/// trunc_sat 前缀编码（0xfc + uleb 子码；nontrapping conversions 提案，
/// wasm 2.0 基线）。子码：i32.trunc_sat_f32_s=0 / f64_s=2；i64.f64_s=6 /
/// f64_u=7（CastD2UQ——#471 饱和无符号对偶）。
fn trunc_sat(sub : Int32, out : Array[Byte]) -> Unit {
  out.push((0xFC).to_byte())
  for b in uleb_encode(sub.to_uint64()) {
    out.push(b)
  }
}

///|
/// pub 编码口（黑盒/测试消费）。
pub fn winstr_encode(instr : WInstr) -> Array[Byte] {
  let out : Array[Byte] = []
  winstr_encode_into(instr, out)
  out
}

///|
/// WInstr 序列整体编码。
pub fn winstr_encode_all(instrs : Array[WInstr]) -> Array[Byte] {
  let out : Array[Byte] = []
  for instr in instrs {
    winstr_encode_into(instr, out)
  }
  out
}

///|
/// 单指令解码错误（与 LebError 分立——decode 语境不同：前者是数值截断，
/// 此处是本指令面外/操作数非法）。
#derive(Debug)
pub(all) enum DecodeError {
  /// 面外 opcode 字节（折叠侧翻译为 fail loud「非本发射器产物」）
  UnknownOpcode(Byte)
  /// 面内 opcode 但操作数解码失败（截断/超长）
  BadOperand(LebError)
  /// 字节流在 opcode 位耗尽
  Eof
}

///|
pub extend DecodeError with Debug::{to_repr}

///|
/// uleb 解码并收窄 i32（uleb 值域=索引/长度（< 2^31 实域），低 32 位
/// 位模式收窄等价截断）——winstr_decode/mem_decode 共用。
fn ulebAt(
  bytes : Array[Byte],
  at : Int32,
) -> Result[(Int32, Int32), DecodeError] {
  match uleb_decode(bytes, at) {
    Ok((v, n)) => Ok((v.to_int(), n))
    Err(e) => Err(BadOperand(e))
  }
}

///|
/// 单指令解码：`bytes[pos..]` 视角 → (指令, 消费字节数)。
/// 面内全部 opcode 可解（含模板未接线面——折叠器先认识字节才能给出
/// 「同型未实现指令」的准确 fail loud 信息，探针 2 [三] 形态）。
pub fn winstr_decode(
  bytes : Array[Byte],
  pos : Int32,
) -> Result[(WInstr, Int32), DecodeError] {
  if pos >= bytes.length() {
    return Err(Eof)
  }
  let op = bytes[pos]
  let p = pos + 1
  fn slebI32(
    bytes : Array[Byte],
    at : Int32,
  ) -> Result[(Int32, Int32), DecodeError] {
    match sleb_decode(bytes, at) {
      // i32 域收窄：低 32 位符号解释（wasm 验证器同口径——超域值非法，
      // 但解码层不代行验证（批 1c wabt 闸职责），仅按发射侧同域收窄）
      Ok((v, n)) => Ok((@util.i64_to_i32_bits(v), n))
      Err(e) => Err(BadOperand(e))
    }
  }
  match op {
    0x00 => Ok((WUnreachable, 1))
    0x01 => Ok((WNop, 1))
    // block/loop 的 blocktype（本面恒 void 0x40）随 opcode 一并消费
    0x02 =>
      if p < bytes.length() && bytes[p] == WT_VOID {
        Ok((WBlock, 2))
      } else {
        Err(UnknownOpcode(op))
      }
    0x03 =>
      if p < bytes.length() && bytes[p] == WT_VOID {
        Ok((WLoop, 2))
      } else {
        Err(UnknownOpcode(op))
      }
    0x0B => Ok((WEnd, 1))
    0x0C =>
      match ulebAt(bytes, p) {
        Ok((depth, n)) => Ok((WBr(depth), 1 + n))
        Err(e) => Err(e)
      }
    0x0D =>
      match ulebAt(bytes, p) {
        Ok((depth, n)) => Ok((WBrIf(depth), 1 + n))
        Err(e) => Err(e)
      }
    0x1A => Ok((WDrop, 1))
    0x10 =>
      match ulebAt(bytes, p) {
        Ok((idx, n)) => Ok((WCall(idx), 1 + n))
        Err(e) => Err(e)
      }
    0x20 =>
      match ulebAt(bytes, p) {
        Ok((idx, n)) => Ok((WLocalGet(idx), 1 + n))
        Err(e) => Err(e)
      }
    0x21 =>
      match ulebAt(bytes, p) {
        Ok((idx, n)) => Ok((WLocalSet(idx), 1 + n))
        Err(e) => Err(e)
      }
    0x22 =>
      match ulebAt(bytes, p) {
        Ok((idx, n)) => Ok((WLocalTee(idx), 1 + n))
        Err(e) => Err(e)
      }
    0x23 =>
      match ulebAt(bytes, p) {
        Ok((idx, n)) => Ok((WGlobalGet(idx), 1 + n))
        Err(e) => Err(e)
      }
    0x24 =>
      match ulebAt(bytes, p) {
        Ok((idx, n)) => Ok((WGlobalSet(idx), 1 + n))
        Err(e) => Err(e)
      }
    0x41 =>
      match slebI32(bytes, p) {
        Ok((v, n)) => Ok((WI32Const(v), 1 + n))
        Err(e) => Err(e)
      }
    0x42 =>
      match sleb_decode(bytes, p) {
        Ok((v, n)) => Ok((WI64Const(v), 1 + n))
        Err(e) => Err(BadOperand(e))
      }
    0x43 => {
      if p + 4 > bytes.length() {
        return Err(BadOperand(Truncated))
      }
      Ok((WF32Const(f32_from_le_bytes(bytes, p)), 5))
    }
    0x44 => {
      if p + 8 > bytes.length() {
        return Err(BadOperand(Truncated))
      }
      Ok((WF64Const(f64_from_le_bytes(bytes, p)), 9))
    }
    0x45 => Ok((WI32Eqz, 1))
    // 访存族（批 1b）：解码只认「自然对齐 + offset 0」的发射器形态——
    // 其他对齐/静态 offset 变体属面外（非本发射器产物），拒载
    0x28 => mem_decode(bytes, p, 2, WI32Load, op)
    0x29 => mem_decode(bytes, p, 3, WI64Load, op)
    0x2A => mem_decode(bytes, p, 2, WF32Load, op)
    0x2B => mem_decode(bytes, p, 3, WF64Load, op)
    0x2C => mem_decode(bytes, p, 0, WI32Load8S, op)
    0x2D => mem_decode(bytes, p, 0, WI32Load8U, op)
    0x36 => mem_decode(bytes, p, 2, WI32Store, op)
    0x37 => mem_decode(bytes, p, 3, WI64Store, op)
    0x38 => mem_decode(bytes, p, 2, WF32Store, op)
    0x39 => mem_decode(bytes, p, 3, WF64Store, op)
    0x3A => mem_decode(bytes, p, 0, WI32Store8, op)
    0x46 => Ok((WI32Eq, 1))
    0x47 => Ok((WI32Ne, 1))
    0x48 => Ok((WI32LtS, 1))
    0x49 => Ok((WI32LtU, 1))
    0x4A => Ok((WI32GtS, 1))
    0x4B => Ok((WI32GtU, 1))
    0x4C => Ok((WI32LeS, 1))
    0x4D => Ok((WI32LeU, 1))
    0x4E => Ok((WI32GeS, 1))
    0x4F => Ok((WI32GeU, 1))
    0x51 => Ok((WI64Eq, 1))
    0x52 => Ok((WI64Ne, 1))
    0x53 => Ok((WI64LtS, 1))
    0x54 => Ok((WI64LtU, 1))
    0x55 => Ok((WI64GtS, 1))
    0x56 => Ok((WI64GtU, 1))
    0x57 => Ok((WI64LeS, 1))
    0x58 => Ok((WI64LeU, 1))
    0x59 => Ok((WI64GeS, 1))
    0x5A => Ok((WI64GeU, 1))
    0x5B => Ok((WF32Eq, 1))
    0x5C => Ok((WF32Ne, 1))
    0x5D => Ok((WF32Lt, 1))
    0x5E => Ok((WF32Gt, 1))
    0x5F => Ok((WF32Le, 1))
    0x60 => Ok((WF32Ge, 1))
    0x61 => Ok((WF64Eq, 1))
    0x62 => Ok((WF64Ne, 1))
    0x63 => Ok((WF64Lt, 1))
    0x64 => Ok((WF64Gt, 1))
    0x65 => Ok((WF64Le, 1))
    0x66 => Ok((WF64Ge, 1))
    0x6A => Ok((WI32Add, 1))
    0x6B => Ok((WI32Sub, 1))
    0x6C => Ok((WI32Mul, 1))
    0x6D => Ok((WI32DivS, 1))
    0x6E => Ok((WI32DivU, 1))
    0x6F => Ok((WI32RemS, 1))
    0x70 => Ok((WI32RemU, 1))
    0x71 => Ok((WI32And, 1))
    0x72 => Ok((WI32Or, 1))
    0x73 => Ok((WI32Xor, 1))
    // 移位/旋转族：面内可解（折叠侧给出准确 fail loud；B 类模板批 1b 接线）
    0x74 => Ok((WI32Shl, 1))
    0x75 => Ok((WI32ShrS, 1))
    0x76 => Ok((WI32ShrU, 1))
    0x86 => Ok((WI64Shl, 1))
    0x87 => Ok((WI64ShrS, 1))
    0x88 => Ok((WI64ShrU, 1))
    0x7C => Ok((WI64Add, 1))
    0x7D => Ok((WI64Sub, 1))
    0x7E => Ok((WI64Mul, 1))
    0x7F => Ok((WI64DivS, 1))
    0x80 => Ok((WI64DivU, 1))
    0x81 => Ok((WI64RemS, 1))
    0x82 => Ok((WI64RemU, 1))
    0x83 => Ok((WI64And, 1))
    0x84 => Ok((WI64Or, 1))
    0x85 => Ok((WI64Xor, 1))
    0x8C => Ok((WF32Neg, 1))
    0x92 => Ok((WF32Add, 1))
    0x93 => Ok((WF32Sub, 1))
    0x94 => Ok((WF32Mul, 1))
    0x95 => Ok((WF32Div, 1))
    0x9A => Ok((WF64Neg, 1))
    0xA0 => Ok((WF64Add, 1))
    0xA1 => Ok((WF64Sub, 1))
    0xA2 => Ok((WF64Mul, 1))
    0xA3 => Ok((WF64Div, 1))
    0xA7 => Ok((WI32WrapI64, 1))
    0xAC => Ok((WI64ExtendI32S, 1))
    0xAD => Ok((WI64ExtendI32U, 1))
    0xB2 => Ok((WF32ConvertI32S, 1))
    0xB3 => Ok((WF32ConvertI32U, 1))
    0xB7 => Ok((WF64ConvertI32S, 1))
    0xB8 => Ok((WF64ConvertI32U, 1))
    0xB6 => Ok((WF32DemoteF64, 1))
    0xB9 => Ok((WF64ConvertI64S, 1))
    0xBA => Ok((WF64ConvertI64U, 1))
    0xB5 => Ok((WF32ConvertI64U, 1))
    0xBB => Ok((WF64PromoteF32, 1))
    0xC0 => Ok((WI32Extend8S, 1))
    0xBD => Ok((WI64ReinterpretF64, 1))
    0xFC =>
      // 前缀族：trunc_sat（子码 0..7）+ bulk-memory（子码 0x0A 双 memidx/
      // 0x0B 单 memidx，恒 0——面外变体拒载）
      match ulebAt(bytes, p) {
        Ok((sub, sn)) =>
          match sub {
            0x00 => Ok((WI32TruncSatF32S, 1 + sn))
            0x02 => Ok((WI32TruncSatF64S, 1 + sn))
            0x06 => Ok((WI64TruncSatF64S, 1 + sn))
            0x07 => Ok((WI64TruncSatF64U, 1 + sn))
            0x0A => bulk_decode(bytes, p + sn, 1 + sn + 2, 2, WMemoryCopy, op)
            0x0B => bulk_decode(bytes, p + sn, 1 + sn + 1, 1, WMemoryFill, op)
            _ => Err(UnknownOpcode(op))
          }
        Err(e) => Err(e)
      }
    _ => Err(UnknownOpcode(op))
  }
}

///|
/// 访存指令解码：align uleb 必须等于自然对齐值、offset uleb 必须为 0——
/// 「本发射器形态」的字节级判据（其他变体 = 非本发射器产物）。
fn mem_decode(
  bytes : Array[Byte],
  p : Int32,
  natural_align : Int32,
  instr : WInstr,
  op : Byte,
) -> Result[(WInstr, Int32), DecodeError] {
  match ulebAt(bytes, p) {
    Ok((align, an)) =>
      if align == natural_align {
        match ulebAt(bytes, p + an) {
          Ok((0, on)) => Ok((instr, 1 + an + on))
          Ok(_) => Err(UnknownOpcode(op))
          Err(e) => Err(e)
        }
      } else {
        Err(UnknownOpcode(op))
      }
    Err(e) => Err(e)
  }
}

///|
/// bulk-memory 解码：子码后 memidx uleb 各恒 0（单 memory 模块）。
/// `at` = memidx[0] 位置；`total` = 指令总消费；`n_idx` = memidx 数
///（copy=2 / fill=1——规范形态）。
fn bulk_decode(
  bytes : Array[Byte],
  at : Int32,
  total : Int32,
  n_idx : Int32,
  instr : WInstr,
  op : Byte,
) -> Result[(WInstr, Int32), DecodeError] {
  if at + n_idx > bytes.length() {
    return Err(UnknownOpcode(op))
  }
  let mut k = 0
  while k < n_idx {
    if bytes[at + k] != (0x00).to_byte() {
      return Err(UnknownOpcode(op))
    }
    k = k + 1
  }
  Ok((instr, total))
}

///|
/// WInstr 序列整体解码（到流尾；中途错即返）。
pub fn winstr_decode_all(
  bytes : Array[Byte],
) -> Result[Array[WInstr], DecodeError] {
  let out : Array[WInstr] = []
  let mut pos = 0
  while pos < bytes.length() {
    match winstr_decode(bytes, pos) {
      Ok((instr, n)) => {
        out.push(instr)
        pos = pos + n
      }
      Err(e) => return Err(e)
    }
  }
  Ok(out)
}
