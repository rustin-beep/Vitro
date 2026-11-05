///|
/// wasmenc 白盒·**mini wasm 栈机**（soft-stack 双实现的 wasm 侧）：
/// 分型值栈（WVal）执行发射的 WInstr 序列——饱和转换**独立手写**
/// （sat_*，不依赖内建 to_int），与 Vitro 位模式域参照
/// （softstack_wbtest.mbt）形成双实现对拍（红线②：栈序/错值类错误
/// wasm 验证器不拦，字节往返不证明执行语义正确，必须模拟跑）。
/// 消费面：softstack_wbtest.mbt 的 expect_sem + anchors_wbtest.mbt。
///
/// 批 1b 扩面：block/br/br_if/end/unreachable 控制流（检查序列的
/// trap 面）+ local/global 槽（装载约定六槽）+ 访存族（NULL 区外的
/// OOB=机器硬检查）+ memory.copy/fill（memmove 语义）+ call(0) host 桩
/// （CallHost 的 H2 ABI 微缩——记录调用序 + 固定返回值）。

///|
/// 载体分型值（Vitro u64 位模式栈 ↔ wasm 分型栈的桥接域）。
enum WVal {
  VI32(Int32)
  VI64(Int64)
  VF32(Float)
  VF64(Double)
} derive(Eq, Debug)

///|
pub extend WVal with Eq::{not_equal, equal}

///|
pub extend WVal with Debug::{to_repr}

///|
/// WVal → Vitro 位模式（i32 符号扩展 = push_i32 同形〔trap.mbt:44 亲读〕；
/// f32 低 32 位位模式零扩展 = exec_float PushConstF 同形；i64/f64 直通）。
fn wval_bits(v : WVal) -> UInt64 {
  match v {
    VI32(x) => x.to_int64().reinterpret_as_uint64()
    VI64(x) => x.reinterpret_as_uint64()
    VF32(f) => f.reinterpret_as_uint().to_uint64()
    VF64(d) => d.reinterpret_as_uint64()
  }
}

///|
/// soft-stack 机错误（下溢/类型错 = 模板栈序破坏；trap = 检查序列/
/// unreachable/机器硬检查——payload 携带定位信息供断言失败文案）。
enum RunErr {
  Underflow
  TypeError
  Trap(String)
}

///|
/// pop 栈顶。
fn wv_pop(st : Array[WVal]) -> Result[WVal, RunErr] {
  if st.length() < 1 {
    return Err(Underflow)
  }
  Ok(st.remove(st.length() - 1))
}

///|
/// pop 两条（返回 (a, b)——a 在下 b 在顶，= wasm 弹序 = Vitro 先弹 b）。
fn wv_pop2(st : Array[WVal]) -> Result[(WVal, WVal), RunErr] {
  if st.length() < 2 {
    return Err(Underflow)
  }
  let b = st.remove(st.length() - 1)
  let a = st.remove(st.length() - 1)
  Ok((a, b))
}

///|
/// i32.trunc_sat_f32_s 的**独立手写饱和**（不依赖内建 to_int——与参照侧
/// 双实现；NaN→0 / ≥2^31→MAX / <-2^31→MIN；f32 可精确表示 ±2^31）。
fn sat_i32_of_f32(f : Float) -> Int32 {
  if f.is_nan() {
    return 0
  }
  if f >= 2147483648.0 {
    return 2147483647
  }
  if f < -2147483648.0 {
    return -2147483648
  }
  f.to_int()
}

///|
/// i32.trunc_sat_f64_s 独立饱和（f64 可精确表示 2^31-1 与 -2^31）。
fn sat_i32_of_f64(d : Double) -> Int32 {
  if d.is_nan() {
    return 0
  }
  if d >= 2147483647.0 {
    return 2147483647
  }
  if d < -2147483648.0 {
    return -2147483648
  }
  d.to_int()
}

///|
/// i64.trunc_sat_f64_s 独立饱和（±2^63 边界——f64 可精确表示）。
fn sat_i64_of_f64(d : Double) -> Int64 {
  if d.is_nan() {
    return 0L
  }
  if d >= 9223372036854775808.0 {
    return 9223372036854775807L
  }
  if d < -9223372036854775808.0 {
    return -9223372036854775808L
  }
  d.to_int64()
}

///|
/// 机器状态（批 1b：控制流/local/global/访存/host 桩的执行域）。
struct MachState {
  stack : Array[WVal]
  /// local 槽 0..5（装载约定：0/1/2=i32、3=i64、4=f64、5=f32）
  locals : Array[WVal]
  /// global 槽 0..5（0..4=i32、5=i64）
  globals : Array[WVal]
  /// 线性内存（引用共享——外部构造预置、终态在外部断言）
  mem : Array[Byte]
  /// 块入口栈深（block 入/end 出；br 按 label 深度回卷）
  labels : Array[Int32]
  /// host 桩调用记录 (route_id, argv_ptr)——CallHost 断言面
  host_calls : Array[(Int32, Int32)]
  /// host 桩固定返回值
  host_ret : Int64
}

///|
/// 机器初值构造（globals 六槽 i32/i64 零基 + mem 外置 + host 返回）。
fn mach_init(
  globals : Array[(Int32, WVal)],
  mem : Array[Byte],
  host_ret : Int64,
) -> MachState {
  let m = {
    stack: [],
    locals: [VI32(0), VI32(0), VI32(0), VI64(0L), VF64(0.0), VF32(0.0)],
    globals: [VI32(0), VI32(0), VI32(0), VI32(0), VI32(0), VI64(0L)],
    mem,
    labels: [],
    host_calls: [],
    host_ret,
  }
  for pair in globals {
    m.globals[pair.0] = pair.1
  }
  m
}

///|
/// 机器读内存小端（i32/u32 域）。
fn mach_load_u32(m : MachState, addr : Int32) -> Result[UInt32, RunErr] {
  if addr < 0 || addr + 4 > m.mem.length() {
    return Err(Trap("memory OOB: \{addr}+4 > \{m.mem.length()}"))
  }
  let mut v = 0U
  for i = 0; i < 4; i = i + 1 {
    v = v | (m.mem[addr + i].to_uint() << (i * 8))
  }
  Ok(v)
}

///|
/// 机器写内存小端。
fn mach_store_u32(
  m : MachState,
  addr : Int32,
  v : UInt32,
) -> Result[Unit, RunErr] {
  if addr < 0 || addr + 4 > m.mem.length() {
    return Err(Trap("memory OOB: \{addr}+4 > \{m.mem.length()}"))
  }
  for i = 0; i < 4; i = i + 1 {
    m.mem[addr + i] = ((v >> (i * 8)) & 0xFFU).reinterpret_as_int().to_byte()
  }
  Ok(())
}

///|
/// 机器读 i8。
fn mach_load_i8(m : MachState, addr : Int32) -> Result[Int32, RunErr] {
  if addr < 0 || addr + 1 > m.mem.length() {
    return Err(Trap("memory OOB: \{addr}"))
  }
  Ok(m.mem[addr].to_int() << 24 >> 24) // 低 8 位符号扩展
}

///|
/// 机器写 i8。
fn mach_store_i8(
  m : MachState,
  addr : Int32,
  v : Int32,
) -> Result[Unit, RunErr] {
  if addr < 0 || addr + 1 > m.mem.length() {
    return Err(Trap("memory OOB: \{addr}"))
  }
  m.mem[addr] = (v & 0xFF).to_byte()
  Ok(())
}

///|
/// u64 域访存（8 字节）。
fn mach_load_u64(m : MachState, addr : Int32) -> Result[UInt64, RunErr] {
  if addr < 0 || addr + 8 > m.mem.length() {
    return Err(Trap("memory OOB: \{addr}+8 > \{m.mem.length()}"))
  }
  let mut v = 0UL
  for i = 0; i < 8; i = i + 1 {
    v = v | (m.mem[addr + i].to_uint64() << (i * 8))
  }
  Ok(v)
}

///|
fn mach_store_u64(
  m : MachState,
  addr : Int32,
  v : UInt64,
) -> Result[Unit, RunErr] {
  if addr < 0 || addr + 8 > m.mem.length() {
    return Err(Trap("memory OOB: \{addr}+8 > \{m.mem.length()}"))
  }
  for i = 0; i < 8; i = i + 1 {
    m.mem[addr + i] = ((v >> (i * 8)) & 0xFFUL)
      .to_uint()
      .reinterpret_as_int()
      .to_byte()
  }
  Ok(())
}

///|
/// 弹 i32 地址（访存指令的地址槽——错型即 TypeError）。
fn mach_pop_addr(m : MachState) -> Result[Int32, RunErr] {
  match wv_pop(m.stack) {
    Ok(VI32(a)) => Ok(a)
    Ok(_) => Err(TypeError)
    Err(e) => Err(e)
  }
}

///|
/// 从 ip 起找匹配的 End（块深度计数——br/br_if 跳转目标定位）。
fn find_matching_end(instrs : Array[WInstr], from : Int32) -> Int32? {
  let mut depth = 0
  let mut i = from
  while i < instrs.length() {
    match instrs[i] {
      WBlock | WLoop => depth = depth + 1
      WEnd => if depth == 0 { return Some(i) } else { depth = depth - 1 }
      _ => ()
    }
    i = i + 1
  }
  None
}

///|
/// **mini wasm 栈机主循环**（批 1b 扩面版）：执行指令序列至尾/br 跳出
/// 顶层块/trap。控制流（block/br_if/end/unreachable）、变量（local/
/// global 六槽）、访存族、memory.copy/fill、call(0) host 桩全支持；
/// A 类数值面沿用 wasm_binop。
fn wasm_exec(
  instrs : Array[WInstr],
  init : Array[WVal],
  m : MachState,
) -> Result[Unit, RunErr] {
  for v in init {
    m.stack.push(v)
  }
  let mut ip = 0
  while ip < instrs.length() {
    let instr = instrs[ip]
    let next = ip + 1
    match instr {
      WNop => ()
      WBlock => {
        m.labels.push(m.stack.length())
        ()
      }
      WLoop => return Err(TypeError) // 模板面不用 loop（dispatch 骨架批 2）
      WEnd =>
        if m.labels.length() > 0 {
          ignore(m.labels.remove(m.labels.length() - 1))
        } else {
          return Err(TypeError) // 裸 end——结构坏
        }
      WBrIf(depth) => {
        let cond = match wv_pop(m.stack) {
          Ok(VI32(c)) => c
          Ok(_) => return Err(TypeError)
          Err(e) => return Err(e)
        }
        if cond != 0 {
          match br_jump(m, instrs, ip, depth) {
            Some(jump_to) => {
              ip = jump_to
              continue
            }
            None => return Err(TypeError)
          }
        }
      }
      WBr(depth) =>
        match br_jump(m, instrs, ip, depth) {
          Some(jump_to) => {
            ip = jump_to
            continue
          }
          None => return Err(TypeError)
        }
      WUnreachable =>
        return Err(
          Trap("unreachable（检查序列命中——模板 trap 面）"),
        )
      WDrop =>
        match wv_pop(m.stack) {
          Ok(_) => ()
          Err(e) => return Err(e)
        }
      WCall(0) => {
        // host 桩（H2 ABI：(route_id, argv_ptr) -> i64——压序 route 先
        // argv 后，弹序 argv（顶）先 route）
        let argv = match wv_pop(m.stack) {
          Ok(VI32(a)) => a
          Ok(_) => return Err(TypeError)
          Err(e) => return Err(e)
        }
        let route = match wv_pop(m.stack) {
          Ok(VI32(r)) => r
          Ok(_) => return Err(TypeError)
          Err(e) => return Err(e)
        }
        m.host_calls.push((route, argv))
        m.stack.push(VI64(m.host_ret))
      }
      WCall(_) => return Err(TypeError) // 仅 import 0 桩在面
      WLocalGet(idx) =>
        match m.locals.get(idx) {
          Some(v) => m.stack.push(v)
          None => return Err(TypeError)
        }
      WLocalSet(idx) =>
        match wv_pop(m.stack) {
          Ok(v) =>
            match m.locals.get(idx) {
              Some(_) => m.locals[idx] = v
              None => return Err(TypeError)
            }
          Err(e) => return Err(e)
        }
      WLocalTee(idx) => {
        if m.stack.length() < 1 {
          return Err(Underflow)
        }
        match m.locals.get(idx) {
          Some(_) => m.locals[idx] = m.stack[m.stack.length() - 1]
          None => return Err(TypeError)
        }
      }
      WGlobalGet(idx) =>
        match m.globals.get(idx) {
          Some(v) => m.stack.push(v)
          None => return Err(TypeError)
        }
      WGlobalSet(idx) =>
        match wv_pop(m.stack) {
          Ok(v) =>
            match m.globals.get(idx) {
              Some(_) => m.globals[idx] = v
              None => return Err(TypeError)
            }
          Err(e) => return Err(e)
        }
      WI32Const(v) => m.stack.push(VI32(v))
      WI64Const(v) => m.stack.push(VI64(v))
      WF32Const(v) => m.stack.push(VF32(v))
      WF64Const(v) => m.stack.push(VF64(v))
      WI32Load => {
        let addr = match mach_pop_addr(m) {
          Ok(a) => a
          Err(e) => return Err(e)
        }
        match mach_load_u32(m, addr) {
          Ok(v) => m.stack.push(VI32(v.reinterpret_as_int()))
          Err(e) => return Err(e)
        }
      }
      WI64Load => {
        let addr = match mach_pop_addr(m) {
          Ok(a) => a
          Err(e) => return Err(e)
        }
        match mach_load_u64(m, addr) {
          Ok(v) => m.stack.push(VI64(v.reinterpret_as_int64()))
          Err(e) => return Err(e)
        }
      }
      WF32Load => {
        let addr = match mach_pop_addr(m) {
          Ok(a) => a
          Err(e) => return Err(e)
        }
        match mach_load_u32(m, addr) {
          Ok(v) => m.stack.push(VF32(Float::reinterpret_from_uint(v)))
          Err(e) => return Err(e)
        }
      }
      WF64Load => {
        let addr = match mach_pop_addr(m) {
          Ok(a) => a
          Err(e) => return Err(e)
        }
        match mach_load_u64(m, addr) {
          Ok(v) => m.stack.push(VF64(UInt64::reinterpret_as_double(v)))
          Err(e) => return Err(e)
        }
      }
      WI32Load8S => {
        let addr = match mach_pop_addr(m) {
          Ok(a) => a
          Err(e) => return Err(e)
        }
        match mach_load_i8(m, addr) {
          Ok(v) => m.stack.push(VI32(v))
          Err(e) => return Err(e)
        }
      }
      WI32Load8U => {
        let addr = match mach_pop_addr(m) {
          Ok(a) => a
          Err(e) => return Err(e)
        }
        match mach_load_i8(m, addr) {
          Ok(v) => {
            m.stack.push(VI32(v & 0xFF))
            ()
          }
          Err(e) => return Err(e)
        }
      }
      WI32Store => {
        let val = match wv_pop(m.stack) {
          Ok(VI32(v)) => v.reinterpret_as_uint()
          Ok(_) => return Err(TypeError)
          Err(e) => return Err(e)
        }
        let addr = match mach_pop_addr(m) {
          Ok(a) => a
          Err(e) => return Err(e)
        }
        match mach_store_u32(m, addr, val) {
          Ok(_) => ()
          Err(e) => return Err(e)
        }
      }
      WI64Store => {
        let val = match wv_pop(m.stack) {
          Ok(VI64(v)) => v.reinterpret_as_uint64()
          Ok(_) => return Err(TypeError)
          Err(e) => return Err(e)
        }
        let addr = match mach_pop_addr(m) {
          Ok(a) => a
          Err(e) => return Err(e)
        }
        match mach_store_u64(m, addr, val) {
          Ok(_) => ()
          Err(e) => return Err(e)
        }
      }
      WF32Store => {
        let val = match wv_pop(m.stack) {
          Ok(VF32(f)) => f.reinterpret_as_uint()
          Ok(_) => return Err(TypeError)
          Err(e) => return Err(e)
        }
        let addr = match mach_pop_addr(m) {
          Ok(a) => a
          Err(e) => return Err(e)
        }
        match mach_store_u32(m, addr, val) {
          Ok(_) => ()
          Err(e) => return Err(e)
        }
      }
      WF64Store => {
        let val = match wv_pop(m.stack) {
          Ok(VF64(d)) => d.reinterpret_as_uint64()
          Ok(_) => return Err(TypeError)
          Err(e) => return Err(e)
        }
        let addr = match mach_pop_addr(m) {
          Ok(a) => a
          Err(e) => return Err(e)
        }
        match mach_store_u64(m, addr, val) {
          Ok(_) => ()
          Err(e) => return Err(e)
        }
      }
      WI32Store8 => {
        let val = match wv_pop(m.stack) {
          Ok(VI32(v)) => v
          Ok(_) => return Err(TypeError)
          Err(e) => return Err(e)
        }
        let addr = match mach_pop_addr(m) {
          Ok(a) => a
          Err(e) => return Err(e)
        }
        match mach_store_i8(m, addr, val) {
          Ok(_) => ()
          Err(e) => return Err(e)
        }
      }
      WMemoryCopy => {
        // 弹序 [dst, src, n]（n 在顶）——memmove 语义
        let n = match wv_pop(m.stack) {
          Ok(VI32(v)) => v
          Ok(_) => return Err(TypeError)
          Err(e) => return Err(e)
        }
        let src = match mach_pop_addr(m) {
          Ok(a) => a
          Err(e) => return Err(e)
        }
        let dst = match mach_pop_addr(m) {
          Ok(a) => a
          Err(e) => return Err(e)
        }
        if n < 0 ||
          src < 0 ||
          dst < 0 ||
          src + n > m.mem.length() ||
          dst + n > m.mem.length() {
          return Err(Trap("memory.copy OOB"))
        }
        // memmove：重叠安全经临时缓冲
        if n > 0 {
          let tmp : Array[Byte] = []
          for i = 0; i < n; i = i + 1 {
            tmp.push(m.mem[src + i])
          }
          for i = 0; i < n; i = i + 1 {
            m.mem[dst + i] = tmp[i]
          }
        }
      }
      WMemoryFill => {
        let n = match wv_pop(m.stack) {
          Ok(VI32(v)) => v
          Ok(_) => return Err(TypeError)
          Err(e) => return Err(e)
        }
        let val = match wv_pop(m.stack) {
          Ok(VI32(v)) => v & 0xFF
          Ok(_) => return Err(TypeError)
          Err(e) => return Err(e)
        }
        let dst = match mach_pop_addr(m) {
          Ok(a) => a
          Err(e) => return Err(e)
        }
        if n < 0 || dst < 0 || dst + n > m.mem.length() {
          return Err(Trap("memory.fill OOB"))
        }
        for i = 0; i < n; i = i + 1 {
          m.mem[dst + i] = val.to_byte()
        }
      }
      _ => {
        // 数值族：一元/转换/二元（A 类面 + 批 1b 域内指令 i64 移位/包装/
        // reinterpret）——沿用批 1a 的分派结构
        let handled = match instr {
          WI64Shl | WI64ShrS | WI64ShrU => {
            let (a, b) = match wv_pop2(m.stack) {
              Ok(p) => p
              Err(e) => return Err(e)
            }
            match wasm_binop(instr, a, b) {
              Ok(v) => {
                m.stack.push(v)
                true
              }
              Err(e) => return Err(e)
            }
          }
          WI64ReinterpretF64 =>
            match wv_pop(m.stack) {
              Ok(VF64(d)) => {
                m.stack.push(
                  VI64(d.reinterpret_as_uint64().reinterpret_as_int64()),
                )
                true
              }
              Ok(_) => return Err(TypeError)
              Err(e) => return Err(e)
            }
          _ => false
        }
        if !handled {
          // A 类单指令族（wasm_run 老分派复用——见 wasm_run_simple）
          match wasm_step_simple(instr, m) {
            Ok(true) => ()
            Ok(false) => return Err(TypeError) // 面外指令
            Err(e) => return Err(e)
          }
        }
      }
    }
    ip = next
  }
  Ok(())
}

///|
/// br/br_if 跳转目标计算（弹 labels 到块外 + 栈回卷 + End 之后 ip）。
fn br_jump(
  m : MachState,
  instrs : Array[WInstr],
  ip : Int32,
  depth : Int32,
) -> Int32? {
  let idx = m.labels.length() - 1 - depth
  if idx < 0 || idx >= m.labels.length() {
    return None
  }
  let target = m.labels[idx]
  let end_at = match find_matching_end(instrs, ip) {
    Some(e) => e
    None => return None
  }
  let mut k = m.labels.length() - idx
  while k > 0 {
    ignore(m.labels.remove(m.labels.length() - 1))
    k = k - 1
  }
  while m.stack.length() > target {
    ignore(m.stack.remove(m.stack.length() - 1))
  }
  Some(end_at + 1)
}

///|
/// A 类单指令步进（const/一元/转换/二元族——wasm_binop/内建饱和消费）。
/// 返回 Ok(false) = 指令不在执行面。
fn wasm_step_simple(instr : WInstr, m : MachState) -> Result[Bool, RunErr] {
  match instr {
    WI32Eqz =>
      match wv_pop(m.stack) {
        Ok(VI32(x)) => {
          m.stack.push(VI32(if x == 0 { 1 } else { 0 }))
          return Ok(true)
        }
        Ok(_) => return Err(TypeError)
        Err(e) => return Err(e)
      }
    WI32Extend8S =>
      match wv_pop(m.stack) {
        Ok(VI32(x)) => {
          let b = x & 0xFF
          m.stack.push(VI32(if b >= 128 { b - 256 } else { b }))
          return Ok(true)
        }
        Ok(_) => return Err(TypeError)
        Err(e) => return Err(e)
      }
    WI32WrapI64 =>
      match wv_pop(m.stack) {
        Ok(VI64(x)) => {
          m.stack.push(VI32(x.to_int()))
          return Ok(true)
        }
        Ok(_) => return Err(TypeError)
        Err(e) => return Err(e)
      }
    WI64ExtendI32S =>
      match wv_pop(m.stack) {
        Ok(VI32(x)) => {
          m.stack.push(VI64(x.to_int64()))
          return Ok(true)
        }
        Ok(_) => return Err(TypeError)
        Err(e) => return Err(e)
      }
    WI64ExtendI32U =>
      match wv_pop(m.stack) {
        Ok(VI32(x)) => {
          m.stack.push(
            VI64(x.reinterpret_as_uint().to_uint64().reinterpret_as_int64()),
          )
          return Ok(true)
        }
        Ok(_) => return Err(TypeError)
        Err(e) => return Err(e)
      }
    WI32TruncSatF32S =>
      match wv_pop(m.stack) {
        Ok(VF32(f)) => {
          m.stack.push(VI32(sat_i32_of_f32(f)))
          return Ok(true)
        }
        Ok(_) => return Err(TypeError)
        Err(e) => return Err(e)
      }
    WI32TruncSatF64S =>
      match wv_pop(m.stack) {
        Ok(VF64(d)) => {
          m.stack.push(VI32(sat_i32_of_f64(d)))
          return Ok(true)
        }
        Ok(_) => return Err(TypeError)
        Err(e) => return Err(e)
      }
    WI64TruncSatF64S =>
      match wv_pop(m.stack) {
        Ok(VF64(d)) => {
          m.stack.push(VI64(sat_i64_of_f64(d)))
          return Ok(true)
        }
        Ok(_) => return Err(TypeError)
        Err(e) => return Err(e)
      }
    WF32ConvertI32S =>
      match wv_pop(m.stack) {
        Ok(VI32(x)) => {
          m.stack.push(VF32(Float::from_double(x.to_double())))
          return Ok(true)
        }
        Ok(_) => return Err(TypeError)
        Err(e) => return Err(e)
      }
    WF32ConvertI32U =>
      match wv_pop(m.stack) {
        Ok(VI32(x)) => {
          m.stack.push(
            VF32(Float::from_double(x.reinterpret_as_uint().to_double())),
          )
          return Ok(true)
        }
        Ok(_) => return Err(TypeError)
        Err(e) => return Err(e)
      }
    WF32ConvertI64U =>
      match wv_pop(m.stack) {
        Ok(VI64(x)) => {
          m.stack.push(
            VF32(Float::from_double(x.reinterpret_as_uint64().to_double())),
          )
          return Ok(true)
        }
        Ok(_) => return Err(TypeError)
        Err(e) => return Err(e)
      }
    WF64ConvertI32S =>
      match wv_pop(m.stack) {
        Ok(VI32(x)) => {
          m.stack.push(VF64(x.to_double()))
          return Ok(true)
        }
        Ok(_) => return Err(TypeError)
        Err(e) => return Err(e)
      }
    WF64ConvertI32U =>
      match wv_pop(m.stack) {
        Ok(VI32(x)) => {
          m.stack.push(VF64(x.reinterpret_as_uint().to_double()))
          return Ok(true)
        }
        Ok(_) => return Err(TypeError)
        Err(e) => return Err(e)
      }
    WF64ConvertI64S =>
      match wv_pop(m.stack) {
        Ok(VI64(x)) => {
          m.stack.push(VF64(x.to_double()))
          return Ok(true)
        }
        Ok(_) => return Err(TypeError)
        Err(e) => return Err(e)
      }
    WF64ConvertI64U =>
      match wv_pop(m.stack) {
        Ok(VI64(x)) => {
          m.stack.push(VF64(x.reinterpret_as_uint64().to_double()))
          return Ok(true)
        }
        Ok(_) => return Err(TypeError)
        Err(e) => return Err(e)
      }
    WF32DemoteF64 =>
      match wv_pop(m.stack) {
        Ok(VF64(d)) => {
          m.stack.push(VF32(Float::from_double(d)))
          return Ok(true)
        }
        Ok(_) => return Err(TypeError)
        Err(e) => return Err(e)
      }
    WF64PromoteF32 =>
      match wv_pop(m.stack) {
        Ok(VF32(f)) => {
          m.stack.push(VF64(f.to_double()))
          return Ok(true)
        }
        Ok(_) => return Err(TypeError)
        Err(e) => return Err(e)
      }
    WF32Neg =>
      match wv_pop(m.stack) {
        Ok(VF32(f)) => {
          m.stack.push(VF32(-f))
          return Ok(true)
        }
        Ok(_) => return Err(TypeError)
        Err(e) => return Err(e)
      }
    WF64Neg =>
      match wv_pop(m.stack) {
        Ok(VF64(d)) => {
          m.stack.push(VF64(-d))
          return Ok(true)
        }
        Ok(_) => return Err(TypeError)
        Err(e) => return Err(e)
      }
    _ => {
      // 二元族
      let is_binary = match instr {
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
        | WI32ShrU
        | WI64Eq
        | WI64Ne
        | WI64LtS
        | WI64LtU
        | WI64GtS
        | WI64GtU
        | WI64LeS
        | WI64LeU
        | WI64GeS
        | WI64GeU
        | WI64Add
        | WI64Sub
        | WI64Mul
        | WI64DivS
        | WI64DivU
        | WI64RemS
        | WI64RemU
        | WI64And
        | WI64Or
        | WI64Xor
        | WF32Eq
        | WF32Ne
        | WF32Lt
        | WF32Gt
        | WF32Le
        | WF32Ge
        | WF32Add
        | WF32Sub
        | WF32Mul
        | WF32Div
        | WF64Eq
        | WF64Ne
        | WF64Lt
        | WF64Gt
        | WF64Le
        | WF64Ge
        | WF64Add
        | WF64Sub
        | WF64Mul
        | WF64Div => true
        _ => false
      }
      if is_binary {
        let (a, b) = match wv_pop2(m.stack) {
          Ok(p) => p
          Err(e) => return Err(e)
        }
        match wasm_binop(instr, a, b) {
          Ok(v) => {
            m.stack.push(v)
            return Ok(true)
          }
          Err(e) => return Err(e)
        }
      } else {
        return Ok(false)
      }
    }
  }
  return Ok(false)
}

///|
/// mini wasm 栈机（批 1a 兼容入口——A 类纯栈样本消费；带状态面走
/// wasm_exec + mach_init）。
fn wasm_run(
  instrs : Array[WInstr],
  init : Array[WVal],
) -> Result[Array[WVal], RunErr] {
  let m = mach_init([], Array::make(64, (0x00).to_byte()), 0L)
  match wasm_exec(instrs, init, m) {
    Ok(_) => Ok(m.stack)
    Err(e) => Err(e)
  }
}

///|
/// 二元指令求值（比较压 0/1 i32；除法 trap 面显式判——wasm 规范口径：
/// div_s/rem_s 除零+MIN/-1 双 trap；div_u/rem_u 仅除零）。
fn wasm_binop(instr : WInstr, a : WVal, b : WVal) -> Result[WVal, RunErr] {
  match instr {
    WI32Add =>
      match (a, b) {
        (VI32(x), VI32(y)) => Ok(VI32(x + y)) // MoonBit Int32 回绕（F1）
        _ => Err(TypeError)
      }
    WI32Sub =>
      match (a, b) {
        (VI32(x), VI32(y)) => Ok(VI32(x - y))
        _ => Err(TypeError)
      }
    WI32Mul =>
      match (a, b) {
        (VI32(x), VI32(y)) => Ok(VI32(x * y))
        _ => Err(TypeError)
      }
    WI32DivS =>
      match (a, b) {
        (VI32(x), VI32(y)) => {
          if y == 0 {
            return Err(Trap("i32.div_s: 除零"))
          }
          if x == -2147483648 && y == -1 {
            return Err(Trap("i32.div_s: INT_MIN/-1"))
          }
          Ok(VI32(x / y))
        }
        _ => Err(TypeError)
      }
    WI32DivU =>
      match (a, b) {
        (VI32(x), VI32(y)) => {
          if y == 0 {
            return Err(Trap("i32.div_u: 除零"))
          }
          Ok(
            VI32(
              (x.reinterpret_as_uint() / y.reinterpret_as_uint()).reinterpret_as_int(),
            ),
          )
        }
        _ => Err(TypeError)
      }
    WI32RemS =>
      match (a, b) {
        (VI32(x), VI32(y)) => {
          if y == 0 {
            return Err(Trap("i32.rem_s: 除零"))
          }
          if x == -2147483648 && y == -1 {
            return Err(Trap("i32.rem_s: INT_MIN/-1"))
          }
          Ok(VI32(x % y))
        }
        _ => Err(TypeError)
      }
    WI32RemU =>
      match (a, b) {
        (VI32(x), VI32(y)) => {
          if y == 0 {
            return Err(Trap("i32.rem_u: 除零"))
          }
          Ok(
            VI32(
              (x.reinterpret_as_uint() % y.reinterpret_as_uint()).reinterpret_as_int(),
            ),
          )
        }
        _ => Err(TypeError)
      }
    WI32And =>
      match (a, b) {
        (VI32(x), VI32(y)) => Ok(VI32(x & y))
        _ => Err(TypeError)
      }
    WI32Or =>
      match (a, b) {
        (VI32(x), VI32(y)) => Ok(VI32(x | y))
        _ => Err(TypeError)
      }
    WI32Xor =>
      match (a, b) {
        (VI32(x), VI32(y)) => Ok(VI32(x ^ y))
        _ => Err(TypeError)
      }
    WI32Shl =>
      match (a, b) {
        (VI32(x), VI32(y)) => Ok(VI32(x << (y & 31))) // wasm 移位量 mod 32
        _ => Err(TypeError)
      }
    WI32ShrS =>
      match (a, b) {
        (VI32(x), VI32(y)) => Ok(VI32(x >> (y & 31)))
        _ => Err(TypeError)
      }
    WI32ShrU =>
      match (a, b) {
        (VI32(x), VI32(y)) =>
          Ok(VI32((x.reinterpret_as_uint() >> (y & 31)).reinterpret_as_int()))
        _ => Err(TypeError)
      }
    WI32Eq =>
      match (a, b) {
        (VI32(x), VI32(y)) => Ok(VI32(if x == y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WI32Ne =>
      match (a, b) {
        (VI32(x), VI32(y)) => Ok(VI32(if x != y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WI32LtS =>
      match (a, b) {
        (VI32(x), VI32(y)) => Ok(VI32(if x < y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WI32LtU =>
      match (a, b) {
        (VI32(x), VI32(y)) =>
          Ok(
            VI32(
              if x.reinterpret_as_uint() < y.reinterpret_as_uint() {
                1
              } else {
                0
              },
            ),
          )
        _ => Err(TypeError)
      }
    WI32GtS =>
      match (a, b) {
        (VI32(x), VI32(y)) => Ok(VI32(if x > y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WI32GtU =>
      match (a, b) {
        (VI32(x), VI32(y)) =>
          Ok(
            VI32(
              if x.reinterpret_as_uint() > y.reinterpret_as_uint() {
                1
              } else {
                0
              },
            ),
          )
        _ => Err(TypeError)
      }
    WI32LeS =>
      match (a, b) {
        (VI32(x), VI32(y)) => Ok(VI32(if x <= y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WI32LeU =>
      match (a, b) {
        (VI32(x), VI32(y)) =>
          Ok(
            VI32(
              if x.reinterpret_as_uint() <= y.reinterpret_as_uint() {
                1
              } else {
                0
              },
            ),
          )
        _ => Err(TypeError)
      }
    WI32GeS =>
      match (a, b) {
        (VI32(x), VI32(y)) => Ok(VI32(if x >= y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WI32GeU =>
      match (a, b) {
        (VI32(x), VI32(y)) =>
          Ok(
            VI32(
              if x.reinterpret_as_uint() >= y.reinterpret_as_uint() {
                1
              } else {
                0
              },
            ),
          )
        _ => Err(TypeError)
      }
    WI64Add =>
      match (a, b) {
        (VI64(x), VI64(y)) => Ok(VI64(x + y))
        _ => Err(TypeError)
      }
    WI64Sub =>
      match (a, b) {
        (VI64(x), VI64(y)) => Ok(VI64(x - y))
        _ => Err(TypeError)
      }
    WI64Mul =>
      match (a, b) {
        (VI64(x), VI64(y)) => Ok(VI64(x * y))
        _ => Err(TypeError)
      }
    WI64DivS =>
      match (a, b) {
        (VI64(x), VI64(y)) => {
          if y == 0L {
            return Err(Trap("i64.div_s: 除零"))
          }
          if x == -9223372036854775808L && y == -1L {
            return Err(Trap("i64.div_s: LLONG_MIN/-1"))
          }
          Ok(VI64(x / y))
        }
        _ => Err(TypeError)
      }
    WI64DivU =>
      match (a, b) {
        (VI64(x), VI64(y)) => {
          if y == 0L {
            return Err(Trap("i64.div_u: 除零"))
          }
          Ok(
            VI64(
              (x.reinterpret_as_uint64() / y.reinterpret_as_uint64()).reinterpret_as_int64(),
            ),
          )
        }
        _ => Err(TypeError)
      }
    WI64RemS =>
      match (a, b) {
        (VI64(x), VI64(y)) => {
          if y == 0L {
            return Err(Trap("i64.rem_s: 除零"))
          }
          if x == -9223372036854775808L && y == -1L {
            return Err(Trap("i64.rem_s: LLONG_MIN/-1"))
          }
          Ok(VI64(x % y))
        }
        _ => Err(TypeError)
      }
    WI64RemU =>
      match (a, b) {
        (VI64(x), VI64(y)) => {
          if y == 0L {
            return Err(Trap("i64.rem_u: 除零"))
          }
          Ok(
            VI64(
              (x.reinterpret_as_uint64() % y.reinterpret_as_uint64()).reinterpret_as_int64(),
            ),
          )
        }
        _ => Err(TypeError)
      }
    WI64And =>
      match (a, b) {
        (VI64(x), VI64(y)) => Ok(VI64(x & y))
        _ => Err(TypeError)
      }
    WI64Or =>
      match (a, b) {
        (VI64(x), VI64(y)) => Ok(VI64(x | y))
        _ => Err(TypeError)
      }
    WI64Xor =>
      match (a, b) {
        (VI64(x), VI64(y)) => Ok(VI64(x ^ y))
        _ => Err(TypeError)
      }
    WI64Shl =>
      match (a, b) {
        (VI64(x), VI64(y)) => Ok(VI64(x << (y.to_int() & 63))) // wasm 移位量 mod 64
        _ => Err(TypeError)
      }
    WI64ShrS =>
      match (a, b) {
        (VI64(x), VI64(y)) => Ok(VI64(x >> (y.to_int() & 63)))
        _ => Err(TypeError)
      }
    WI64ShrU =>
      match (a, b) {
        (VI64(x), VI64(y)) =>
          Ok(
            VI64(
              (x.reinterpret_as_uint64() >> (y.to_int() & 63)).reinterpret_as_int64(),
            ),
          )
        _ => Err(TypeError)
      }
    WI64Eq =>
      match (a, b) {
        (VI64(x), VI64(y)) => Ok(VI32(if x == y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WI64Ne =>
      match (a, b) {
        (VI64(x), VI64(y)) => Ok(VI32(if x != y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WI64LtS =>
      match (a, b) {
        (VI64(x), VI64(y)) => Ok(VI32(if x < y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WI64LtU =>
      match (a, b) {
        (VI64(x), VI64(y)) =>
          Ok(
            VI32(
              if x.reinterpret_as_uint64() < y.reinterpret_as_uint64() {
                1
              } else {
                0
              },
            ),
          )
        _ => Err(TypeError)
      }
    WI64GtS =>
      match (a, b) {
        (VI64(x), VI64(y)) => Ok(VI32(if x > y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WI64GtU =>
      match (a, b) {
        (VI64(x), VI64(y)) =>
          Ok(
            VI32(
              if x.reinterpret_as_uint64() > y.reinterpret_as_uint64() {
                1
              } else {
                0
              },
            ),
          )
        _ => Err(TypeError)
      }
    WI64LeS =>
      match (a, b) {
        (VI64(x), VI64(y)) => Ok(VI32(if x <= y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WI64LeU =>
      match (a, b) {
        (VI64(x), VI64(y)) =>
          Ok(
            VI32(
              if x.reinterpret_as_uint64() <= y.reinterpret_as_uint64() {
                1
              } else {
                0
              },
            ),
          )
        _ => Err(TypeError)
      }
    WI64GeS =>
      match (a, b) {
        (VI64(x), VI64(y)) => Ok(VI32(if x >= y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WI64GeU =>
      match (a, b) {
        (VI64(x), VI64(y)) =>
          Ok(
            VI32(
              if x.reinterpret_as_uint64() >= y.reinterpret_as_uint64() {
                1
              } else {
                0
              },
            ),
          )
        _ => Err(TypeError)
      }
    WF32Add =>
      match (a, b) {
        (VF32(x), VF32(y)) => Ok(VF32(x + y))
        _ => Err(TypeError)
      }
    WF32Sub =>
      match (a, b) {
        (VF32(x), VF32(y)) => Ok(VF32(x - y))
        _ => Err(TypeError)
      }
    WF32Mul =>
      match (a, b) {
        (VF32(x), VF32(y)) => Ok(VF32(x * y))
        _ => Err(TypeError)
      }
    WF32Div =>
      match (a, b) {
        (VF32(x), VF32(y)) => Ok(VF32(x / y)) // IEEE：除零=±inf/NaN 不 trap
        _ => Err(TypeError)
      }
    WF32Eq =>
      match (a, b) {
        (VF32(x), VF32(y)) => Ok(VI32(if x == y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WF32Ne =>
      match (a, b) {
        (VF32(x), VF32(y)) => Ok(VI32(if x != y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WF32Lt =>
      match (a, b) {
        (VF32(x), VF32(y)) => Ok(VI32(if x < y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WF32Gt =>
      match (a, b) {
        (VF32(x), VF32(y)) => Ok(VI32(if x > y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WF32Le =>
      match (a, b) {
        (VF32(x), VF32(y)) => Ok(VI32(if x <= y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WF32Ge =>
      match (a, b) {
        (VF32(x), VF32(y)) => Ok(VI32(if x >= y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WF64Add =>
      match (a, b) {
        (VF64(x), VF64(y)) => Ok(VF64(x + y))
        _ => Err(TypeError)
      }
    WF64Sub =>
      match (a, b) {
        (VF64(x), VF64(y)) => Ok(VF64(x - y))
        _ => Err(TypeError)
      }
    WF64Mul =>
      match (a, b) {
        (VF64(x), VF64(y)) => Ok(VF64(x * y))
        _ => Err(TypeError)
      }
    WF64Div =>
      match (a, b) {
        (VF64(x), VF64(y)) => Ok(VF64(x / y))
        _ => Err(TypeError)
      }
    WF64Eq =>
      match (a, b) {
        (VF64(x), VF64(y)) => Ok(VI32(if x == y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WF64Ne =>
      match (a, b) {
        (VF64(x), VF64(y)) => Ok(VI32(if x != y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WF64Lt =>
      match (a, b) {
        (VF64(x), VF64(y)) => Ok(VI32(if x < y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WF64Gt =>
      match (a, b) {
        (VF64(x), VF64(y)) => Ok(VI32(if x > y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WF64Le =>
      match (a, b) {
        (VF64(x), VF64(y)) => Ok(VI32(if x <= y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WF64Ge =>
      match (a, b) {
        (VF64(x), VF64(y)) => Ok(VI32(if x >= y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    _ => Err(TypeError)
  }
}
