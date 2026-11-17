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
  module_bytes : Array[Byte]
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
  /// 窗口装载参数（批 4′ host 回接——中继 INIT 帧消费；堆基/argv 引擎
  /// 侧同源铺设的布局输入）
  win_data_end : Int32
  win_argc : Int32
  win_argv0 : String
  /// CallHost 组数（静态计数）。**PR #526 审阅 P3 注记：当前恒 0 死字段**
  ///——build_dispatch_input 遇 CallHost 直接 NotSupported（host 回接批
  /// 前禁译），成功产物的本字段无判定力；保留为 host 回接批的产物面
  /// 预留（届时禁译撤除后复权），dispatchdiff 的零 host 过滤恒真即此
  /// 边界的体现。
  host_calls : Int32
  /// 步数预算（预算安全点常量——对拍臂预算判定须同值）
  max_steps : Int32
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
/// `argv0~`：进程 argv[0] 真值（dispatch 真执行面——PushArgc/PushArgv 模板
/// 的 CtxI32 槽从批 1c 的 0 近似升真值；空串 = 不精化保近似〔wbtest 旧
/// 锚口径〕。引擎臂 cmd/run 恒以完整文件路径作 argv[0] 下发——对拍闸须
/// 同串调用本参数，argv 区字节（data 铺设）才与引擎臂 1MB 映像逐位对齐）。
/// `variadic_argc~`（批 4′）：变参 host 路由（printf/sprintf/snprintf/
/// sscanf）的调用序实参个数——dump_wasm 管线扫 typed AST 供给（codegen
/// 按 AST 实参压栈同源）；缺省空表 = 无变参调用点（含变参的产物对账红）。

///|
/// libc 段定位（idx → (start, end)——make_site_old 扁平 meta 回退扫描用）。
fn libc_span_of(
  spans : Array[(Int32, Int32, Int32)],
  idx : Int32,
) -> (Int32, Int32)? {
  for sp in spans {
    if sp.0 == idx {
      return Some((sp.1, sp.2))
    }
  }
  None
}

///|
pub fn build_dispatch_input(
  output : @bytecode.CompileOutput,
  max_steps : Int32,
  argv0~ : String = "",
  variadic_argc~ : Array[Int32] = [],
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
  // call_sites 构造子（Call/CallVar 共用——旧 ip 域，target 由调用方 remap；
  // 闭包捕获 libc/spans——libc 扁平 meta 的 return_type 失真回退扫描用）
  let libc_code2 = libc.code
  let spans2 = libc_spans(libc)
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
    // 批 4b-4：wide-param 禁译撤除——「wasm 值=1 与 word 口径混用」系
    // 4b-1 误判（codegen call.mbt 亲读：i64/double 实参经 SplitD/SplitQ
    // **拆双 word 压栈**，与 do_call 的 word 流弹写全域同构——逐 word
    // i32 搬运正确；摸底 18 例 wide-param 全因此假禁译）。唯一真例外 =
    // f32 单值（原型 float 不提升——param_kinds 分派）。
    let param_words : Array[Int32] = []
    let param_kinds : Array[@wasmenc.WValKind] = []
    let mut arg_words = 0
    // param_types 与 param_sizes 同长对齐（codegen enter_function 同游标
    // 填——含 __ret_ptr 隐参）；libc 扁平产物空表 → 全 @wasmenc.VkWordI32（libc
    // 内部 Call 同一 codegen 产拆双压形态，word 流正确）
    for i = 0; i < m.param_sizes.length(); i = i + 1 {
      let w = m.param_sizes[i]
      param_words.push(w)
      arg_words = arg_words + w
      // f32 参数 word 流统一（PR #526 P1-2）——恒 VkWordI32；表保留为
      // 「与 param_words 同长」的类型源位（未来 wide 域扩展预留）
      param_kinds.push(@wasmenc.VkWordI32)
    }
    // libc 扁平产物（param_types 空）的 return_type 恒 Void 失真（探针
    // 实锤 88/88——批 4′ 解锁「libc Call 返回值被消费」形态暴露：返回点
    // rv1=0 → h_in 缺 1 → 块图 -1）。**静态回退**：段内控制流组扫描——
    // 出现 Ret（值返回组，RetVoid 除外）→ 非 void；ret_kind 按「段内
    // Ret 前一组」producer 定型（值生产者机制同源——用户段 ret_kinds
    // 表的 libc 段覆盖面）
    // 判据 = idx 命中 libc 段表（param_types 空会误伤无参用户函数——
    // `int main()` 的 param_types 同为空表）
    let span = libc_span_of(spans2, func_idx)
    let libc_flat = span is Some(_)
    let (is_void2, ret_kind2) : (Bool, @wasmenc.WValKind) = if libc_flat {
      let mut saw_ret = false
      let mut kind = @wasmenc.VkWordI32
      if span is Some((s0, e0)) {
        // span 上面已查（判据同源）
        for g = s0; g < e0; g = g + 1 {
          let ins2 = libc_code2[g]
          match ins2.op {
            Ret => {
              saw_ret = true
              if g > s0 {
                let k2 = producer_val_kind(libc_code2[g - 1].op)
                if k2 != @wasmenc.VkWordI32 {
                  kind = k2
                }
              }
            }
            _ => ()
          }
        }
      }
      (if saw_ret { false } else { true }, kind)
    } else {
      (m.return_type is Void(_), ret_kind_of(m.return_type))
    }
    Ok({
      target_ip: target,
      arg_words,
      frame_bytes: m.local_count,
      param_words,
      param_kinds,
      is_void: is_void2,
      ret_kind: ret_kind2,
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
    guard output.func_index.get(name) is Some(_) else { continue }
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
  // ── 函数入口 ip 集（live 域——块划分 leader 判定）+ 段头 meta 对
  //    （ret_kinds 段扫描的元数据源——批 4b-4）──
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
    guard output.func_index.get(name) is Some(_) else { continue }
    guard output.func_table.get(name) is Some(m) else { continue }
    match remap.get(m.ip + libc_len) {
      Some(t) => entry_ips.push(t)
      None => ()
    }
  }
  // ── EmitCtx（bytecode 投影件同源 + dispatch 真执行面精化）──
  // 往返路径（批 2/3）的 ctx 近似无碍——重建 Instruction 的 operand 取
  // 侧车原值；dispatch 是真 wasm 执行，CtxI32(Argc/ArgvAddr) 槽直接进
  // 字节——argc/argv_addr 须填真值（4b-2，设计单批 4「近似升真值」项）。
  // 布局单源 = VM setup_argv 的编址（R1 ③：argv 区自 GLOBAL_REGION_LIMIT
  // 向下——footprint 口径 @bytecode.argv_region_footprint）。
  let ctx = {
    ..@bytecode.wasm_emit_ctx(output),
    argc: if argv0.is_empty() {
      0
    } else {
      1
    },
    argv_addr: if argv0.is_empty() {
      0
    } else {
      let fp = @bytecode.argv_region_footprint(1, [argv0])
      (@bytecode.GLOBAL_REGION_LIMIT - fp).reinterpret_as_int()
    },
  }
  // ── ret_kinds（PR #526 审阅 P1-1 重设计：**值生产者定型**替代段状态机）──
  //    段扫描两轮实错（关段致多返回点第 2 个 Ret 失归属〔审阅复现：
  //    `double pick(int x){if(x>0) return 1.5; return 2.5;}` 组装非法
  //    wasm〕；不关段则 wrapper 段误归最后函数）的根因 = **同一函数的
  //    Ret 栈值类型本就不恒定**——隐式尾恒 `PushConst 0`（i32 域，哪怕
  //    f64 函数——C 无尾 return 是 UB 域，codegen 恒发 int 0，dump 实证
  //    mret/dno 探针）；显式 Ret 按返回表达式值域。正确语义 = 逐 Ret
  //    按**前一组 op**（值生产者）定型：PushConstD 族 → f64、
  //    PushConstQ 族 → i64、F 族算术 → f32、其余 → i32 word 流；
  //    紧邻 Call 的 Ret（wrapper/直接转发形态）→ 被调函数 ret_kind。──
  let ret_kinds : Map[Int32, @wasmenc.WValKind] = Map([])
  for gip = 0; gip < full_ops.length(); gip = gip + 1 {
    if full_ops[gip] is Ret && gip > 0 {
      let prev = full_ops[gip - 1]
      if prev is Call || prev is CallVar {
        match call_sites.get(gip - 1) {
          Some(cm) => ret_kinds.set(gip, cm.ret_kind)
          None => ()
        }
      } else {
        let k = producer_val_kind(prev)
        if k != @wasmenc.VkWordI32 {
          ret_kinds.set(gip, k)
        }
        // VkWordI32 = 主通道缺省（不入表——dispatchloop 侧缺省同值）
      }
    }
  }
  // ── CallHost 窗口调用点构造（批 4′——4b-2 的全禁译撤除：参数消费
  //    序列〔vitro 栈参数 → H2 窗口〕经 host_window_sig + AST 侧车 +
  //    块内类型模拟展开；禁译面按分组细分 reason〔Stdin/Vfs/Callback/
  //    VaList/Observe〕归 dispatchdiff 桶登记）──
  let host_sites = match
    build_host_sites(
      full_ops,
      full_operands,
      entry_ips,
      user_base,
      ctx,
      output.global_data_end,
      if argv0.is_empty() {
        0
      } else {
        1
      },
      if argv0.is_empty() {
        []
      } else {
        [argv0]
      },
      variadic_argc,
      call_sites,
    ) {
    Ok(s) => s
    Err(m) => return Err(NotSupported(m))
  }
  Ok({
    ops: full_ops,
    operands: full_operands,
    func_entry_ips: entry_ips,
    entry_ip: user_base,
    call_sites,
    host_sites,
    ret_kinds,
    stack_start: 1048576,
    call_depth_limit: 10000,
    max_steps,
    ctx,
  })
}

///|
/// CompileOutput → 载体产物（投影 + 组装 + data blob 一体）。
/// `argv0~` 语义同 `build_dispatch_input`（真执行精化 + argv 区铺设）。
pub fn build_dispatch_product(
  output : @bytecode.CompileOutput,
  max_steps : Int32,
  argv0~ : String = "",
  variadic_argc~ : Array[Int32] = [],
) -> Result[DispatchProduct, String] {
  let input = match
    build_dispatch_input(output, max_steps, argv0~, variadic_argc~) {
    Ok(i) => i
    Err(NotSupported(m)) => return Err("dispatch-not-supported: " + m)
    Err(FuncMissing(idx)) =>
      return Err("dispatch-func-missing: " + idx.to_string())
  }
  let group_count = input.ops.length()
  let entry_ip = input.entry_ip
  // ── CallHost 静态计数（零 host 对拍子集判据）──
  let mut host_calls = 0
  for op in input.ops {
    if op is CallHost {
      host_calls = host_calls + 1
    }
  }
  // ── data blob（稀疏写集 → 稠密投影）──
  let writes : Map[Int32, Int32] = Map([]) // 4 对齐地址 → word
  fn put_byte(pos : Int32, b : Int32) -> Unit {
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

  // globals_init_32/64 的 pair.0 是**相对 GLOBAL_START 的偏移**（VM
  // set_globals_* 与 LoadGlobal 模板 OpBase(0x1000) 同口径——绝对地址 =
  // GLOBAL_START + off）；string_data 的地址已是绝对值（codegen
  // intern_string_literal 产出 GLOBAL_START+off）
  for pair in output.globals_init_32 {
    writes.set((@bytecode.GLOBAL_START + pair.0).reinterpret_as_int(), pair.1)
  }
  for pair in output.globals_init_64 {
    let a = (@bytecode.GLOBAL_START + pair.0).reinterpret_as_int()
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
      put_byte(addr + k, bytes[k].to_int())
    }
  }
  // ── argv 区铺设（真执行精化——VM setup_argv 第 12 步的字节级投影：
  // 指针数组 [argv_addr] = 字符串地址 + UTF-8+NUL 串体；与 ctx.argv_addr
  // 同一编址单源。argc=0/空 argv0 时 VM 侧 argc=0/argv_addr=0——零写
  // 入即同形。字节口径 = @utf8.encode（write_cstring_utf8 同源——推进量
  // == 写入量，与 argv_region_footprint 计账一致）──
  if !argv0.is_empty() {
    let fp = @bytecode.argv_region_footprint(1, [argv0])
    let array_addr = @bytecode.GLOBAL_REGION_LIMIT - fp
    let string_addr = array_addr + 4U
    // 指针槽（小端 u32）
    writes.set(
      array_addr.reinterpret_as_int(),
      string_addr.reinterpret_as_int(),
    )
    // 串体：UTF-8 字节 + NUL 终止
    let base = string_addr.reinterpret_as_int()
    let mut k = 0
    for b in @utf8.encode(argv0) {
      put_byte(base + k, b.to_int())
      k = k + 1
    }
    put_byte(base + k, 0)
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
        module_bytes: bytes,
        entry_ip,
        stack_start: 1048576,
        group_count,
        data_blob,
        data_base,
        win_data_end: output.global_data_end.reinterpret_as_int(),
        win_argc: if argv0.is_empty() {
          0
        } else {
          1
        },
        win_argv0: argv0,
        host_calls,
        max_steps,
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
    Err(@wasmenc.BadReturnPoint(gip, h)) => {
      // 诊断增强（批 4′）：坏块首 gip 起的组序列（块图红的定位面）
      let mut seq = ""
      let mut g = gip
      while g < input.ops.length() && g < gip + 10 {
        seq = seq +
          " " +
          input.ops[g].name() +
          "/" +
          input.operands[g].to_string()
        g = g + 1
      }
      Err(
        "dispatch-bad-return-point gip=" +
        gip.to_string() +
        " height=" +
        h.to_string() +
        " ops:" +
        seq,
      )
    }
    Err(@wasmenc.Blocks(@wasmenc.Emit(m))) =>
      Err("dispatch-not-supported: " + m)
    Err(_) => Err("dispatch-assemble-failed: unclassified")
  }
}

///|
/// 返回类型 → 返回通道形态（批 4b-4 宽返回）：f64/i64 走 G_RV_W 位模式
/// 过桥、f32 走 G_RV + i32.reinterpret 过桥、其余 i32 主通道直存。
fn ret_kind_of(ty : @ast.Type) -> @wasmenc.WValKind {
  match ty.kind() {
    TK_Double => @wasmenc.VkF64
    // TK_Float 归主通道（f32 word 流统一——PR #526 P1-2，无 VkF32 专值）
    TK_LongLong => @wasmenc.VkI64
    _ => @wasmenc.VkWordI32
  }
}

///|
/// **值生产者定型**（PR #526 审阅 P1-1 重设计的核心件）：Ret 前一组
/// op → wasm 栈值域。比段归属精确的根据：隐式尾恒 `PushConst 0`（i32
/// 域——哪怕 f64 函数，codegen 恒发 int 0，mret/dno 探针 dump 实证）；
/// 显式 Ret 按返回表达式值域。映射按模板真值域（比较族产 i32 bool、
/// 算术/装载/常量/转换按目标型；CastQ2I/CastF2I 产 i32、Split 产拆后
/// i32）——**Ret 紧邻可达的生产者**才是本表消费面（Call 族在调用方
/// 特判，CallHost 已禁译不可达）。
fn producer_val_kind(op : @opcode.OpCode) -> @wasmenc.WValKind {
  match op {
    // f64 域（常量/装载/转换/算术；D 比较族产 i32 bool 不在此）
    PushConstD
    | LoadLocalD
    | LoadGlobalD
    | LoadMemD
    | CastF2D
    | CastD2F
    | CastI2D
    | CastQ2D
    | CastU2D
    | CastUQ2D
    | AddD
    | SubD
    | MulD
    | DivD
    | NegD => @wasmenc.VkF64
    // i64 域（Q 族；CastD2UQ 产 u64 位模式 = i64 域；Q 比较族产 i32）
    PushConstQ
    | LoadLocalQ
    | LoadGlobalQ
    | LoadMemQ
    | CastI2Q
    | CastU2Q
    | CastD2UQ
    | AddQ
    | SubQ
    | MulQ => @wasmenc.VkI64
    // 其余（i32/f32 全 word 流——**f32 经 PushConstF 臂 i32.reinterpret
    // 入流**〔PR #526 P1-2〕、算术/比较/逻辑/装载/转换收窄/栈操作）→
    // i32 word 流
    _ => @wasmenc.VkWordI32
  }
}
