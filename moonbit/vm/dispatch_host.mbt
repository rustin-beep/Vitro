// 蓝本注记：文内 Rust 源引用（`*.rs` 路径/行号/符号）均为档案态蓝本——tag rust-oracle-freeze（2026-10-05 删区），现为本仓自主基线。

///| L7 执行层·VM 域·**REHOST 批 4′：CallHost 窗口调用点构造**——
/// 拼接后组序列（libc live 段 + 用户段）逐 CallHost 组 →
/// `@wasmenc.HostCallMeta`（arg_kinds + ret）。
///
/// **argc 供给三源**（单源 = `host_window_sig`）：
/// - 固定参路由：`sig.argc`（C 原型参数个数——弹参序不进表，窗口序
///   透传免疫蓝本杂态）；
/// - 变参路由（printf/sprintf/snprintf/sscanf）：**AST 侧车**
///   （`variadic_argc~`——dump_wasm 管线扫 typed AST 的调用序实参个数，
///   codegen 按 AST 实参压栈同源）；
/// - libc 段：全走固定参表（18 点 = malloc×6/free×12 摸底实锤——
///   libc 无变参路由调用点；若未来 libc 预编译产物引入变参 CallHost，
///   侧车序对账红即 fail loud 拦截）。
///
/// **arg_kinds 定型**（块内类型模拟——producer 定型扩展）：
/// - 块相对栈（顶 = 尾）逐组推进：A/B 类组按 `template_spec` 弹压 +
///   Dup/Swap/Split/Cast 特判（产出类型按 `producer_val_kind`——
///   f32 word 流统一域恒 VkWordI32）；
/// - Call/CallVar：弹 arg_words、非 void 压 ret_kind 1 项（返回点
///   load 项同型——`\|\|`/`&&` 短路条件消费 Call 返回值的实锤形态）；
/// - **块首留值降级**：跨块留值（短路 Dup 形态）不参与本块参数位时
///   模拟栈深足额直接取顶；不足（参数序列跨 Call 返回点/块边界——
///   `printf("%d", a, f(b))` 形态）降级全 VkWordI32（word 主导域近似
///   ——f64 实参位错型由 V8 编译红/对拍红显式暴露，不静默）。
///
/// **窗口空间机判**（fail loud）：win = align4(global_data_end)、
/// win+8+8·argc_max ≤ heap_base（`compute_heap_base` 同源——越界即
/// NotSupported，堆基下方空洞被挤出形态登记禁译不猜）。

///|
/// CallHost 组扫描 + 元数据构造（build_dispatch_input 的批 4′ 主体）。
/// `variadic_argc` = 变参路由调用序的实参个数（AST 侧车——**只覆盖
/// 用户段 CallHost**；对账：侧车长度 == 拼接序列中变参 CallHost 数）。
fn build_host_sites(
  ops : Array[@opcode.OpCode],
  operands : Array[Int32],
  func_entry_ips : Array[Int32],
  entry_ip : Int32,
  ctx : @wasmenc.EmitCtx,
  global_data_end : UInt32,
  argc_main : Int32,
  argv_main : Array[String],
  variadic_argc : Array[Int32],
  call_sites : Map[Int32, @wasmenc.CallSiteMeta],
) -> Result[Map[Int32, @wasmenc.HostCallMeta], String] {
  // 空序列短路（DCE 全剪形态——空用户程序的 libc 全剪：partition 对
  // 空序列的结构性报错不适用，直接空表）
  if ops.length() == 0 {
    return Ok(Map([]))
  }
  // ── 块划分（组装器同源——块内模拟的块界）──
  let blocks = match
    @wasmenc.partition_blocks(ops, operands, func_entry_ips, entry_ip) {
    Ok(b) => b
    Err(e) => return Err("host-sites partition: \{e.to_repr()}") // 块划分失败交主流程同款红
  }
  let n = ops.length()
  let starts = blocks.starts
  // ── 变参侧车游标（拼接序——libc 无变参，游标只在用户段推进）──
  let mut va_cursor = 0
  let sites : Map[Int32, @wasmenc.HostCallMeta] = Map([])
  let mut win_end : Int32 = 0 // 窗口需求上界（含头的绝对末址）
  for k = 0; k < starts.length(); k = k + 1 {
    let start = starts[k]
    let end = if k + 1 < starts.length() { starts[k + 1] } else { n }
    // 块内类型模拟（块相对栈——顶 = 尾）
    let stack : Array[@wasmenc.WValKind] = []
    for gip = start; gip < end; gip = gip + 1 {
      let op = ops[gip]
      match op {
        CallHost => {
          let sig = match host_window_sig(operands[gip]) {
            Some(s) => s
            None =>
              return Err(
                "callhost-unknown-route gip=\{gip} id=\{operands[gip]}",
              )
          }
          // 分组禁译（reason = 桶名——dispatchdiff 细分口径）
          if !(sig.group is Ready) {
            return Err(
              "callhost-\{sig.group.to_repr()} gip=\{gip} id=\{operands[gip]}",
            )
          }
          // argc：固定参表 / 变参侧车
          let argc = match sig.argc {
            Some(a) => a
            None => {
              if va_cursor >= variadic_argc.length() {
                return Err(
                  "callhost-variadic-sidecar-missing gip=\{gip} id=\{operands[gip]}",
                )
              }
              let a = variadic_argc[va_cursor]
              va_cursor = va_cursor + 1
              a
            }
          }
          // arg_kinds：模拟栈顶 argc 项（深不足降级全 word）
          let kinds : Array[@wasmenc.WValKind] = []
          if stack.length() >= argc {
            for j = stack.length() - argc; j < stack.length(); j = j + 1 {
              kinds.push(stack[j])
            }
          } else {
            for j = 0; j < argc; j = j + 1 {
              kinds.push(@wasmenc.VkWordI32) // 降级近似（头注——错型显式红）
            }
          }
          sites.set(gip, { arg_kinds: kinds, ret: sig.ret, })
          let need = 8 + 8 + argc * 8 // trap+argc 头 + 参数槽
          if ctx.host_argv_ptr + need > win_end {
            win_end = ctx.host_argv_ptr + need
          }
          // 返回值入模拟栈（同块后续 CallHost 的参数位——`printf("%f",
          // atof(s))` 形态：atof 返回 f64 项直传 printf 窗口写 VkF64）
          match sig.ret {
            Some(k) => stack.push(k)
            None => ()
          }
        }
        Call | CallVar => {
          // 弹目标值 + 参数（宽度口径块图一致）；ret 型从 call_sites 精确
          //（libc 扁平 meta 的 ret_kind 已由 make_site_old 段扫描回退定型
          //——atof 族 f64/i64 直传 printf 变参位的形态不再降级）
          ignore(stack.pop()) // 目标值（CallVar 变参 argc 弹穿近似——降级域）
          match call_sites.get(gip) {
            Some(m) => {
              let w = m.arg_words
              for j = 0; j < w; j = j + 1 {
                ignore(stack.pop())
              }
              if !m.is_void {
                stack.push(m.ret_kind)
              }
            }
            None => stack.push(@wasmenc.VkWordI32)
          }
        }
        Jump => break // 块尾
        JumpIfZero | JumpIfNotZero => {
          ignore(stack.pop()) // 判定值
          break // 块尾（两侧同型——留值经溢出池，块首默认 word 域）
        }
        Ret | RetVoid => break
        StepEvent => () // dispatch 零发射（计步单源块锚）
        _ => {
          // A/B 类组：效应表弹压 + 类型规则
          let spec = @wasmenc.template_spec(op)
          let pops = spec.pops
          let pushes = spec.pushes
          if pops < 0 || pushes < 0 {
            return Err(
              "callhost-type-sim-ctx gip=\{gip} op=\{op.name()}（上下文相关组进模拟域）",
            )
          }
          // 弹（Dup/Swap 特判在压侧处理源型）
          let popped : Array[@wasmenc.WValKind] = []
          for j = 0; j < pops; j = j + 1 {
            match stack.pop() {
              Some(t) => popped.push(t)
              None => () // 块首留值下探（跨块域）——近似丢弃
            }
          }
          // 压（类型规则）
          for j = 0; j < pushes; j = j + 1 {
            stack.push(push_kind_of(op, popped))
          }
        }
      }
    }
  }
  // 变参侧车对账（长度一致——libc 段无变参 ⇒ 侧车只覆盖用户段等长）
  if va_cursor != variadic_argc.length() {
    return Err(
      "callhost-variadic-sidecar-mismatch consumed=\{va_cursor} supplied=\{variadic_argc.length()}",
    )
  }
  // 窗口空间机判（win = ctx.host_argv_ptr；win_end ≤ heap_base 同源）
  let heap_base = @bytecode.compute_heap_base(
    global_data_end, argc_main, argv_main,
  )
  if win_end > 0 && win_end > heap_base.reinterpret_as_int() {
    return Err(
      "callhost-window-overflow win_end=\{win_end} heap_base=\{heap_base}（全局数据挤出堆基下方空洞）",
    )
  }
  Ok(sites)
}

///|
/// 组产出的栈值形态（producer 定型——dispatch_setup 的 producer_val_kind
/// 同源扩展为逐 push 项规则；popped = 本组弹出的源型〔逆序——popped[0]
/// = 栈顶〕）。
fn push_kind_of(
  op : @opcode.OpCode,
  popped : Array[@wasmenc.WValKind],
) -> @wasmenc.WValKind {
  match op {
    // 栈操作族：源型透传/交换（弹穿块首留值时 popped 不足——降级 word）
    Dup => if popped.length() > 0 { popped[0] } else { @wasmenc.VkWordI32 } // 复制源顶型（短路留值）
    Swap =>
      // 弹 [顶,次] 压回逆序——push j 的型 ≈ popped[1-j]；组内逐 push
      // 调用共享 popped 快照，近似取次顶（两型一致的常态域）
      if popped.length() > 1 {
        popped[1]
      } else if popped.length() > 0 {
        popped[0]
      } else {
        @wasmenc.VkWordI32
      }
    // 拆分族：i64/f64 → 双 word（word 流——无合成对偶 opcode，Split 单向）
    SplitD | SplitQ => @wasmenc.VkWordI32
    _ => producer_val_kind(op)
  }
}
