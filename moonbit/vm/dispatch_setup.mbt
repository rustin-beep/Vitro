// 蓝本注记：文内 Rust 源引用（`*.rs` 路径/行号/符号）均为档案态蓝本——tag rust-oracle-freeze（2026-10-05 删区），现为本仓自主基线。

///| L7 执行层·VM 域·**REHOST 批 4b-1：dispatch-loop 载体投影层**——
/// 全程序（live libc + 用户）→ `@wasmenc.DispatchInput`（可执行载体的
/// 组装输入；设计单 §3.2 批 4〔2026-11-14 修订版〕）。
///
/// **投影协议**（与 `setup_from_output` 的 12 步装载同源对齐——同一次
/// 重定位、同一套 func meta；差异 = 产物是 wasm 模块字节而非 VM code）：
/// - **DCE**（死代码剔除）：libc 只拼**被用户程序引用的函数闭包**——
///   全拼 3485 组死代码既撑大产物又让个别函数的形态缺陷全程序传染
///   （批 4b-1 实锤：短路链块图问题让「全 libc 拼接」全红，DCE 后
///   局部化到实际调用者）；ip 重映射表统一重写 Jump/Call 目标；
/// - **Call/CallVar operand 重写**：VM 语义 operand = func_idx（do_call
///   经 func_table 查 meta.ip）——载体块划分器按 ip 域工作，投影层
///   重写为目标 ip（经 remap）；
/// - call_sites：静态调用点 → `CallSiteMeta`（target_ip/arg_words/
///   param_words/frame_bytes/is_void）；**变参目标禁译**（CallVar 的
///   运行期 argc 栈值语义不在静态域）；
/// - data 铺设 blob：`globals_init_32/64` + `string_data` 稀疏写集 →
///   稠密 blob（宿主实例化后写 memory——与 VM 装载期 set_globals_*/
///   write_cstring 同语义）。
///
/// **首版边界（诚实登记）**：CallPtr 禁译（wasmenc 侧拦）；变参禁译
/// （本层拦）；host 调用（CallHost）可组装不回接——4b 胶水遇 import
/// 调用即该语料 skip（零 host 子集对拍，host 回接协议随后续批）。

///|
/// 投影失败（fail loud——禁译面归 4b 闸登记不静默）。
#derive(Debug, Eq)
pub(all) enum DispatchProjectError {
  /// 禁译面（变参/CallPtr/跳死码等静态不可展开形态——携带定位）
  NotSupported(String)
  /// func_table 缺失（Call/CallVar 目标索引查无——结构性不可达）
  FuncMissing(Int32)
}

///|
pub extend DispatchProjectError with Debug::{to_repr}

///|
pub extend DispatchProjectError with Eq::{not_equal, equal}

///|
/// 载体产物：模块字节 + 装载协议元数据（宿主〔4b 胶水〕消费面）。
pub(all) struct DispatchProduct {
  /// 可执行 wasm 模块（dispatch-loop 骨架）
  module : Array[Byte]
  /// 程序入口 ip（全程序域）
  entry_ip : Int32
  /// 初始 mem_stack_top（STACK_START——模块入口自置）
  stack_start : Int32
  /// 组数（步数预算对账面）
  group_count : Int32
  /// 数据铺设 blob（稀疏写集稠密投影——宿主写 memory）
  data_blob : Array[Byte]
  /// data_blob 铺设基址（blob 首字节对应的全程序地址）
  data_base : Int32
}

///|
/// libc 函数段表（(idx, start, end) 升序——funcs ip 排序 + 段尾 =
/// 下一函数 ip；DCE 与拼接共用）。
fn libc_spans(libc : LibcArtifact) -> Array[(Int32, Int32, Int32)] {
  let sorted : Array[(Int32, Int32)] = []
  for entry in libc.funcs {
    sorted.push((entry.1, entry.2.ip))
  }
  sorted.sort_by(fn(a, b) { a.1.compare(b.1) })
  let spans : Array[(Int32, Int32, Int32)] = []
  for fi = 0; fi < sorted.length(); fi = fi + 1 {
    let s0 = sorted[fi].1
    let e0 = if fi + 1 < sorted.length() {
      sorted[fi + 1].1
    } else {
      libc.code.length()
    }
    spans.push((sorted[fi].0, s0, e0))
  }
  spans
}

///|
/// CompileOutput → DispatchInput（全程序组装输入；投影协议见文件头注）。
pub fn build_dispatch_input(
  output : @bytecode.CompileOutput,
  max_steps : Int32,
) -> Result[@wasmenc.DispatchInput, DispatchProjectError] {
  // ── libc 装载（与 setup_from_output 第 1 步同源）──
  let libc = load_libc_artifact()
  let libc_len = libc.code.length()
  // ── 函数索引 → 入口 ip / meta 全表（libc 先注册、用户后写覆盖）──
  let entry_of : Map[Int32, Int32] = Map([])
  let meta_of : Map[Int32, @bytecode.FuncMeta] = Map([])
  for entry in libc.funcs {
    entry_of.set(entry.1, entry.2.ip)
    meta_of.set(entry.1, entry.2)
  }
  let names : Array[String] = []
  for k in output.func_table.keys() {
    names.push(k)
  }
  names.sort_by(fn(a, b) { a.compare(b) })
  for name in names {
    guard output.func_index.get(name) is Some(idx) else { continue }
    guard output.func_table.get(name) is Some(m) else { continue }
    entry_of.set(idx, m.ip + libc_len)
    meta_of.set(idx, m)
  }
  // call_sites 构造子（Call/CallVar 共用——旧 ip 域，target 由调用方 remap）
  fn make_site_old(
    func_idx : Int32,
    gip : Int32,
  ) -> Result[@wasmenc.CallSiteMeta, DispatchProjectError] {
    guard entry_of.get(func_idx) is Some(target) else {
      return Err(FuncMissing(func_idx))
    }
    guard meta_of.get(func_idx) is Some(m) else {
      return Err(FuncMissing(func_idx))
    }
    if m.is_variadic {
      return Err(
        NotSupported(
          "variadic target func_idx=" +
          func_idx.to_string() +
          " gip=" +
          gip.to_string(),
        ),
      )
    }
    // PR #520 审阅 P2-1：word/value 口径混用禁译——Call 搬运按 word 逐个
    // local.set（i32 槽），i64/double 参数（word=2、wasm 值=1）必错位且
    // 静默产非法字节；任何 word 数 >1 的参数即 NotSupported（fail loud）。
    // 全 1 word 的参数仍可能是 f32（FuncMeta 无参数类型——4b-2 胶水全语料
    // 实测兜底，登记）
    for pw in m.param_sizes {
      if pw > 1 {
        return Err(
          NotSupported(
            "wide-param func_idx=" +
            func_idx.to_string() +
            " word=" +
            pw.to_string() +
            " gip=" +
            gip.to_string(),
          ),
        )
      }
    }
    let param_words : Array[Int32] = []
    let mut arg_words = 0
    for w in m.param_sizes {
      param_words.push(w)
      arg_words = arg_words + w
    }
    Ok({
      target_ip: target,
      arg_words,
      frame_bytes: m.local_count,
      param_words,
      is_void: m.return_type is Void(_),
    })
  }
  let spans = libc_spans(libc)
  // ── DCE 根集（用户静态调用）+ libc 内部闭包 ──
  let live_funcs : Set[Int32] = Set([])
  let work : Array[Int32] = []
  for ins in output.code {
    if ins.op is Call || ins.op is CallVar {
      if !live_funcs.contains(ins.operand) {
        live_funcs.add(ins.operand)
        work.push(ins.operand)
      }
    }
  }
  while work.length() > 0 {
    let idx = match work.pop() {
      Some(v) => v
      None => 0
    }
    for sp in spans {
      let (fidx, s0, e0) = sp
      if fidx == idx {
        for i = s0; i < e0; i = i + 1 {
          let ins = libc.code[i]
          if ins.op is Call || ins.op is CallVar {
            if !live_funcs.contains(ins.operand) {
              live_funcs.add(ins.operand)
              work.push(ins.operand)
            }
          }
        }
        break
      }
    }
  }
  // ── ip 重映射表（旧全程序 ip → 新 ip；先建表后重写——Jump 目标
  //    可指向任何 live 段）──
  let remap : Map[Int32, Int32] = Map([])
  let mut live_len = 0
  for sp in spans {
    let (fidx, s0, e0) = sp
    if !live_funcs.contains(fidx) {
      continue
    }
    for i = s0; i < e0; i = i + 1 {
      remap.set(i, live_len + (i - s0))
    }
    live_len = live_len + (e0 - s0)
  }
  // 用户 code 段映射（用户函数 ip 同步映射）
  let user_base = live_len
  for i = 0; i < output.code.length(); i = i + 1 {
    remap.set(libc_len + i, user_base + i)
  }
  for name in names {
    guard output.func_index.get(name) is Some(idx) else { continue }
    guard output.func_table.get(name) is Some(m) else { continue }
    remap.set(m.ip + libc_len, user_base + m.ip)
  }
  // ── 拼接（libc live 段 + 用户段，逐组重写目标）──
  let full_ops : Array[@opcode.OpCode] = []
  let full_operands : Array[Int32] = []
  let call_sites : Map[Int32, @wasmenc.CallSiteMeta] = Map([])
  fn remap_tgt(ip : Int32) -> Result[Int32, DispatchProjectError] {
    match remap.get(ip) {
      Some(t) => Ok(t)
      None => Err(NotSupported("jump-to-dead ip=" + ip.to_string()))
    }
  }
  for sp in spans {
    let (fidx, s0, e0) = sp
    if !live_funcs.contains(fidx) {
      continue
    }
    for i = s0; i < e0; i = i + 1 {
      let ins = libc.code[i]
      let new_gip = full_ops.length()
      match ins.op {
        Jump | JumpIfZero | JumpIfNotZero => {
          full_ops.push(ins.op)
          match remap_tgt(ins.operand) {
            Ok(t) => full_operands.push(t)
            Err(e) => return Err(e)
          }
        }
        Call | CallVar =>
          match make_site_old(ins.operand, new_gip) {
            Ok(site) =>
              match remap_tgt(site.target_ip) {
                Ok(t) => {
                  call_sites.set(new_gip, { ..site, target_ip: t, })
                  full_ops.push(ins.op)
                  full_operands.push(t)
                }
                Err(e) => return Err(e)
              }
            Err(e) => return Err(e)
          }
        _ => {
          full_ops.push(ins.op)
          full_operands.push(ins.operand)
        }
      }
    }
  }
  for i = 0; i < output.code.length(); i = i + 1 {
    let ins = output.code[i]
    let new_gip = full_ops.length()
    match ins.op {
      Jump | JumpIfZero | JumpIfNotZero => {
        full_ops.push(ins.op)
        match remap_tgt(ins.operand + libc_len) {
          Ok(t) => full_operands.push(t)
          Err(e) => return Err(e)
        }
      }
      Call | CallVar =>
        match make_site_old(ins.operand, new_gip) {
          Ok(site) =>
            match remap_tgt(site.target_ip) {
              Ok(t) => {
                call_sites.set(new_gip, { ..site, target_ip: t, })
                full_ops.push(ins.op)
                full_operands.push(t)
              }
              Err(e) => return Err(e)
            }
          Err(e) => return Err(e)
        }
      _ => {
        full_ops.push(ins.op)
        full_operands.push(ins.operand)
      }
    }
  }
  // ── 函数入口 ip 集（live 域——块划分 leader 判定）──
  let entry_ips : Array[Int32] = []
  for sp in spans {
    let (fidx, s0, _) = sp
    if live_funcs.contains(fidx) {
      match remap.get(s0) {
        Some(t) => entry_ips.push(t)
        None => ()
      }
    }
  }
  for name in names {
    guard output.func_index.get(name) is Some(idx) else { continue }
    guard output.func_table.get(name) is Some(m) else { continue }
    match remap.get(m.ip + libc_len) {
      Some(t) => entry_ips.push(t)
      None => ()
    }
  }
  // ── EmitCtx（bytecode 投影件同源）──
  let ctx = @bytecode.wasm_emit_ctx(output)
  Ok({
    ops: full_ops,
    operands: full_operands,
    func_entry_ips: entry_ips,
    entry_ip: user_base,
    call_sites,
    stack_start: 1048576,
    call_depth_limit: 10000,
    max_steps,
    ctx,
  })
}

///|
/// CompileOutput → 载体产物（投影 + 组装 + data blob 一体）。
pub fn build_dispatch_product(
  output : @bytecode.CompileOutput,
  max_steps : Int32,
) -> Result[DispatchProduct, String] {
  let input = match build_dispatch_input(output, max_steps) {
    Ok(i) => i
    Err(NotSupported(m)) => return Err("dispatch-not-supported: " + m)
    Err(FuncMissing(idx)) =>
      return Err("dispatch-func-missing: " + idx.to_string())
  }
  let group_count = input.ops.length()
  let entry_ip = input.entry_ip
  // ── data blob（稀疏写集 → 稠密投影）──
  let writes : Map[Int32, Int32] = Map([]) // 4 对齐地址 → word
  for pair in output.globals_init_32 {
    writes.set(pair.0.reinterpret_as_int(), pair.1)
  }
  for pair in output.globals_init_64 {
    let a = pair.0.reinterpret_as_int()
    let v = pair.1
    let lo = @util.i64_to_i32_bits(v.reinterpret_as_int64() & 0xFFFFFFFFL)
    let hi = @util.i64_to_i32_bits(v.reinterpret_as_int64() >> 32)
    writes.set(a, lo)
    writes.set(a + 4, hi)
  }
  for pair in output.string_data {
    // C 字符串逐字节（含 NUL 终止——write_cstring 同语义）
    let addr = pair.0.reinterpret_as_int()
    let bytes = pair.1.to_array()
    for k = 0; k < bytes.length(); k = k + 1 {
      let b = bytes[k].to_int()
      let pos = addr + k
      let wa = pos - pos % 4
      let sh = pos % 4 * 8
      let old = match writes.get(wa) {
        Some(v) => v
        None => 0
      }
      let mask = 255 << sh
      let keep = old ^ (old & mask)
      writes.set(wa, keep | (b << sh))
    }
  }
  let addrs : Array[Int32] = []
  for a in writes.keys() {
    addrs.push(a)
  }
  addrs.sort_by(fn(a, b) { a.compare(b) })
  let data_blob : Array[Byte] = []
  let data_base = if addrs.length() > 0 { addrs[0] } else { 0 }
  if addrs.length() > 0 {
    // 稠密投影：首末 word 间逐 word 连续（空洞 word 零铺——blob 与
    // data_base 的连续覆盖语义）
    let last_a = addrs[addrs.length() - 1]
    for a = addrs[0]; a <= last_a; a = a + 4 {
      let w = match writes.get(a) {
        Some(v) => v
        None => 0
      }
      data_blob.push((w & 0xFF).to_byte())
      data_blob.push(((w >> 8) & 0xFF).to_byte())
      data_blob.push(((w >> 16) & 0xFF).to_byte())
      data_blob.push(((w >> 24) & 0xFF).to_byte())
    }
  }
  // ── 组装（wasmenc 单源）──
  match @wasmenc.assemble_dispatch_module(input) {
    Ok(bytes) =>
      Ok({
        module: bytes,
        entry_ip,
        stack_start: 1048576,
        group_count,
        data_blob,
        data_base,
      })
    Err(@wasmenc.Blocks(@wasmenc.CallPtrUnsupported(gip))) =>
      Err("dispatch-not-supported: callptr gip=" + gip.to_string())
    Err(@wasmenc.Blocks(@wasmenc.ExitStackNonEmpty(gip, h, k))) =>
      Err(
        "dispatch-not-supported: exit-stack-nonempty gip=" +
        gip.to_string() +
        " height=" +
        h.to_string() +
        " block=" +
        k.to_string(),
      )
    Err(@wasmenc.Blocks(@wasmenc.BadTarget(ip, n))) =>
      Err("dispatch-bad-target ip=" + ip.to_string() + " of " + n.to_string())
    Err(@wasmenc.NotSupportedHeight(h)) =>
      Err("dispatch-not-supported: spill-height " + h.to_string())
    Err(@wasmenc.BadReturnPoint(b, h)) =>
      Err(
        "dispatch-bad-return-point block=" +
        b.to_string() +
        " height=" +
        h.to_string(),
      )
    Err(@wasmenc.Blocks(@wasmenc.Emit(m))) =>
      Err("dispatch-not-supported: " + m)
    Err(_) => Err("dispatch-assemble-failed: unclassified")
  }
}
