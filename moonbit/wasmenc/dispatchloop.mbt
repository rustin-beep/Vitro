///|
/// **dispatch-loop 语义模块组装器（REHOST 批 4a）**——组序列 → V8/
/// wasmtime 可执行 wasm 模块（设计单 §2.5 单函数 dispatch-loop + 软件
/// 栈；PoC `tmp/jit_survey/poc/wasm_poc.mjs::bodyDispatch` 实测 299×
/// 形态的通用化）。
///
/// **与往返路径的关系（两条发射路径分离，2026-11-14 拍板）**：
/// `build_group_table` 的产物字节（微缩形态——C 类只设 pc）是批 2/3
/// 已验收的往返对象，**锁死不动**；本组装器独立发射「执行形态」——
/// A/B 类组字节与往返路径同源（`emit_group` 单源复用）、C 类组展开
/// 完整执行协议（Call 参数搬运/帧管理/Jump 族深度重编）。
///
/// **骨架**（PoC bodyDispatch 同构）：
/// ```
/// main(start_ip) -> i32:
///   入口初始化（pc=start_ip、哨兵帧头、SPT/FB/DEPTH 复位）
///   loop $L:
///     block × n
///       global.get $pc
///       br_table T[0..N]  default=unreachable   ;; T[ip]=块索引、T[EXIT]=出口块
///     end; body_0; …; end; body_{n-1}; end      ;; body_k 后恢复（br 深度 n-1-k）
///     出口块（global.get $rv; return）
///   end; unreachable
/// ```
/// 块体 = 组序列直落 + 块首步锚（steps += 块长——组粒度恒等的批量形态）
/// + 块尾预算检查（`if steps >= max: return -1`——overshoot ≤1 块的
/// 已知分叉，预算 trap 语料的 steps 对拍面由 4b 闸登记豁免）。
///
/// **软件调用栈（方案 B'，2026-11-14）**：帧头 12B 内嵌帧底
/// `[return_ip | orig_top | caller_fb] @ locals_base-12`——单指针 SPT
/// （=VM mem_stack_top 同步语义）、Ret 可静态定位帧头；代价 = 局部变量
/// 地址较 VM 差 12×深度（`&x`/%p/VLA 语料进已知分叉豁免面，R4 残余
/// 风险同族登记——结果级三锚不含地址）。
///
/// **返回值通道**：Ret 存 G_RV、返回点块开头 `global.get G_RV` 压回
/// wasm 栈（void 调用不 load——块边界栈空由该约定保持，blocks.mbt 头注）。
///
/// **首版边界**：CallPtr fail loud（partition 拦）；i64 参数的双 word
/// 搬运形态待 4b 全语料对拍锚定（4a 锚先覆盖 i32 参数）；堆碰撞检查
/// 不做（NULL 下界 + 深度上限双保险，堆碰撞语料归 4b 对拍实测定）。

///|
/// 组装错误（全部 fail loud——禁译面归 4b 闸登记，不静默）。
#derive(Debug, Eq)
pub(all) enum DispatchError {
  /// 块划分失败（透传——含 CallPtr 禁译）
  Blocks(BlocksError)
  /// 组发射失败（透传）
  Emit(String)
  /// 效应复核失败（指令流级栈平衡——组装器自产流的第二道闸）
  Effect(EffectError)
  /// 返回点信息不自洽（Call gip+1 越界等结构性不可达）
  BadReturnPoint(Int32, Int32)
}

///|
pub extend DispatchError with Debug::{to_repr}

///|
pub extend DispatchError with Eq::{not_equal, equal}

///|
/// Call/CallVar 组的调用点元数据（组装方按 func_table 侧车算好供给——
/// 静态调用点的目标信息编译期全知）。
pub(all) struct CallSiteMeta {
  /// 目标函数入口 ip（重定位后）
  pub target_ip : Int32
  /// 参数 word 数（param_sizes 总和 + 变参——VM do_call 搬运量同源）
  arg_words : Int32
  /// 目标帧字节数（FuncMeta.local_count——字节口径）
  frame_bytes : Int32
  /// 逐参 word 数（逆序搬运发射用——声明序）
  param_words : Array[Int32]
  /// void 函数（返回点不 load G_RV）
  is_void : Bool
}

///|

///|
/// dispatch-loop 组装输入。
pub(all) struct DispatchInput {
  /// 全程序组序列 op（gip = 下标；重定位后——libc+用户拼接形态由消费
  /// 方〔4b〕供给，本组装器只认 ip 域自洽）
  pub ops : Array[@opcode.OpCode]
  /// 重定位后 operand（Jump/Call 目标 = 绝对 ip；CallVar 已重写为目标 ip）
  pub operands : Array[Int32]
  /// 函数头 ip 集
  pub func_entry_ips : Array[Int32]
  /// 程序入口 ip
  pub entry_ip : Int32
  /// 静态调用点元数据（gip → meta；Call/CallVar 必有、其余不查）
  pub call_sites : Map[Int32, CallSiteMeta]
  /// 初始 mem_stack_top（= STACK_START；宿主装载语义同 VM setup）
  pub stack_start : Int32
  /// 调用深度上限（VM call_depth_limit 同源——教学 trap 语义）
  pub call_depth_limit : Int32
  /// 步数预算（块尾安全点——超限 return -1）
  pub max_steps : Int32
  /// A/B 类组发射上下文（常量池/符号尺寸等——build_group_table 同源）
  pub ctx : EmitCtx
}

///|

///|
/// 组装主体（WInstr 层）——独立 pub 供锚测试（骨架/深度/步锚/G_RV 通道
/// 的结构断言面；段拼装归 assemble_dispatch_module）。
pub fn assemble_dispatch_body(
  input : DispatchInput,
) -> Result[Array[WInstr], DispatchError] {
  let ops = input.ops
  let n = ops.length()
  // 1. 块划分 + 组序列粗验（栈空闸前置）
  let blocks = match
    partition_blocks(ops, input.operands, input.func_entry_ips, input.entry_ip) {
    Ok(b) => b
    Err(e) => return Err(Blocks(e))
  }
  let arg_words_of = fn(gip : Int32) -> Int32 {
    match input.call_sites.get(gip) {
      Some(m) => m.arg_words
      None => 0
    }
  }
  match
    blocks_exit_stacks_empty(
      ops,
      input.operands,
      blocks,
      arg_words_of,
      input.ctx,
    ) {
    Ok(_) => ()
    Err(e) => return Err(Blocks(e))
  }
  // 2. 返回点映射（Call gip → gip+1 是返回点块首；非 void 前插 G_RV load）
  let ret_points : Map[Int32, Bool] = Map([]) // 返回点 gip → 是否 load G_RV
  for gip = 0; gip < n; gip = gip + 1 {
    match ops[gip] {
      Call | CallVar => {
        let is_void = match input.call_sites.get(gip) {
          Some(m) => m.is_void
          None => return Err(BadReturnPoint(gip, -1))
        }
        if gip + 1 >= n + 1 {
          return Err(BadReturnPoint(gip, n))
        }
        ret_points.set(gip + 1, !is_void)
      }
      _ => ()
    }
  }
  // 3. 常量：EXIT_IP（哨兵 return_ip）= 组数（合法 ip 域外唯一哨兵值）
  let exit_ip = n
  // 块索引表（ip → 块索引——br_table 标签向量）；starts 升序
  let starts = blocks.starts
  let nblocks = starts.length()
  // 标签向量：逐 ip（0..exit_ip）填块索引；非 leader 填 default 臂
  //（不可达域——只有 leader 可被跳到；default = unreachable 兜底）
  let default_label = nblocks // 出口块前专用 trap 块索引？——出口块独立追加（索引 nblocks）
  let labels : Array[Int32] = []
  let mut bi = 0
  for ip = 0; ip <= exit_ip; ip = ip + 1 {
    if ip == exit_ip {
      labels.push(nblocks) // 出口块
    } else {
      // ip 所在块：starts 升序找（双指针——ip 递增单调）
      while bi + 1 < nblocks && starts[bi + 1] <= ip {
        bi = bi + 1
      }
      if bi < nblocks && starts[bi] == ip {
        labels.push(bi)
      } else {
        labels.push(default_label) // 非 leader：不可达域 → default
      }
    }
  }
  // 4. 逐块生成指令
  let bodies : Array[Array[WInstr]] = []
  for k = 0; k < nblocks; k = k + 1 {
    let start = starts[k]
    let end = if k + 1 < nblocks { starts[k + 1] } else { n }
    let depth = nblocks - 1 - k // br 回 loop 的深度（body 顶层）
    let body : Array[WInstr] = []
    // 块首步锚（steps += 块长——组粒度恒等的批量形态）
    push_step_add(body, end - start)
    // 返回点 load（非 void 调用的返回点——G_RV → wasm 栈）
    if ret_points.get(start) == Some(true) {
      body.push(WGlobalGet(G_RV))
    }
    // 组序列
    let mut ended_by_control = false
    for gip = start; gip < end; gip = gip + 1 {
      let op = ops[gip]
      let operand = input.operands[gip]
      match op {
        Jump | JumpIfZero | JumpIfNotZero => {
          // 微缩模板形态 + BrAny 深度重编（执行语义同构——探针 3 结论）
          push_jump_with_depth(body, op, operand, input.ctx, depth)
          ended_by_control = true
        }
        Call | CallVar => {
          let meta = match input.call_sites.get(gip) {
            Some(m) => m
            None => return Err(BadReturnPoint(gip, n))
          }
          push_call_expand(body, meta, gip, input.call_depth_limit, depth)
          ended_by_control = true
        }
        Ret | RetVoid => {
          push_ret_expand(body, op, depth)
          ended_by_control = true
        }
        // CallHost：微缩模板即执行语义（H2 import + 返回值压栈同块消费）
        CallHost => {
          let g = match emit_group(op, operand, input.ctx) {
            Ok(g) => g
            Err(NotImplemented(m)) => return Err(Emit("NotImplemented: " + m))
            Err(BadOperand(m)) => return Err(Emit("BadOperand: " + m))
          }
          for w in g {
            body.push(w)
          }
        }
        _ => {
          // A/B 类组：往返路径同源字节
          let g = match emit_group(op, operand, input.ctx) {
            Ok(g) => g
            Err(NotImplemented(m)) => return Err(Emit("NotImplemented: " + m))
            Err(BadOperand(m)) => return Err(Emit("BadOperand: " + m))
          }
          for w in g {
            body.push(w)
          }
        }
      }
      if ended_by_control {
        break
      }
    }
    if !ended_by_control {
      // 块尾：预算检查 + fallthrough（pc = 下一块 leader ip）
      push_budget_check(body, input.max_steps)
      let next_ip = if k + 1 < nblocks { starts[k + 1] } else { exit_ip }
      body.push(WI32Const(next_ip))
      body.push(WGlobalSet(G_PC))
      body.push(WBr(depth))
    }
    bodies.push(body)
  }
  // 5.（指令流级栈平衡的静态复核撤——WBr 骨架深度依赖拼装上下文，
  //    独立块体模拟会 BadBrDepth 假红；**最终裁判 = 4b 闸的
  //    wasm-validate（类型级，比效应模拟器强）+ V8/wasmtime 实跑对拍**。
  //    组序列粗验（步骤 1 的 blocks_exit_stacks_empty）仍是装载期前置。）
  // 6. 骨架拼装（PoC bodyDispatch 同构）
  let main_body : Array[WInstr] = []
  // 入口初始化：pc = start_ip；哨兵帧头 [exit_ip | stack_start | 0]
  // @ stack_start-12；SPT/FB/DEPTH 复位
  main_body.push(WLocalGet(0)) // start_ip 参数（local 0）
  main_body.push(WGlobalSet(G_PC))
  main_body.push(WI32Const(input.stack_start - 12))
  main_body.push(WGlobalSet(G_SPT))
  // 哨兵帧头三 word（地址全动态——模板同款 offset=0 store）
  main_body.push(WI32Const(input.stack_start - 12))
  main_body.push(WI32Const(exit_ip))
  main_body.push(WI32Store)
  main_body.push(WI32Const(input.stack_start - 8))
  main_body.push(WI32Const(input.stack_start))
  main_body.push(WI32Store)
  main_body.push(WI32Const(input.stack_start - 4))
  main_body.push(WI32Const(0))
  main_body.push(WI32Store)
  main_body.push(WI32Const(0))
  main_body.push(WGlobalSet(G_FB))
  main_body.push(WI32Const(0))
  main_body.push(WGlobalSet(G_DEPTH))
  // loop + n blocks + br_table
  main_body.push(WLoop)
  for k = 0; k < nblocks; k = k + 1 {
    main_body.push(WBlock)
  }
  main_body.push(WGlobalGet(G_PC))
  main_body.push(WBrTable(labels, default_label))
  for k = 0; k < nblocks; k = k + 1 {
    main_body.push(WEnd)
    for w in bodies[k] {
      main_body.push(w)
    }
  }
  main_body.push(WEnd) // 关 loop
  // 出口块（br_table T[exit_ip] 目标 = nblocks 标签——落在最后一个
  // block 的 end 之后：出口块体在 loop 内、全部块结构外）
  main_body.push(WGlobalGet(G_RV))
  main_body.push(WReturn)
  main_body.push(WUnreachable) // loop 尾防御（出口块 return 后不可达）
  Ok(main_body)
}

///|
/// 组装：输入 → 可执行模块字节（body = assemble_dispatch_body 单源 +
/// 段结构：type (i32)->i32 main / host ABI import / memory{16,16} /
/// globals 七槽（批 1b 六槽 + G_DEPTH）/ locals 四 runs / export
/// main+memory+steps）。
pub fn assemble_dispatch_module(
  input : DispatchInput,
) -> Result[Array[Byte], DispatchError] {
  let main_body = match assemble_dispatch_body(input) {
    Ok(b) => b
    Err(e) => return Err(e)
  }
  let b = ModuleBuilder::new()
  let t_main = b.add_type([WT_I32], [WT_I32])
  let t_host = b.add_type([WT_I32, WT_I32], [WT_I64])
  let _ = b.add_import("env", "vitro_host_call", 0, t_host)
  let main_idx = b.add_func(t_main, {
    locals: [(3, WT_I32), (1, WT_I64), (1, WT_F64), (1, WT_F32)],
    body: main_body,
  })
  let _ = b.add_memory(16, Some(16))
  // globals：批 1b 六槽 + G_DEPTH（i32 mut——帧深度计数）
  let _ = b.add_global(WT_I32, true, WI32Const(0)) // 0: G_PC
  let _ = b.add_global(WT_I32, true, WI32Const(0)) // 1: G_FB
  let _ = b.add_global(WT_I32, true, WI32Const(0)) // 2: G_STEPS
  let _ = b.add_global(WT_I32, true, WI32Const(0)) // 3: G_SPT
  let _ = b.add_global(WT_I32, true, WI32Const(0)) // 4: G_RET
  let _ = b.add_global(WT_I64, true, WI64Const(0L)) // 5: G_RV
  let _ = b.add_global(WT_I32, true, WI32Const(0)) // 6: G_DEPTH
  b.add_export("main", 0, main_idx)
  b.add_export("memory", 2, 0)
  b.add_export("steps", 3, G_STEPS) // 预算/对拍观测（result 级三锚）
  Ok(b.build())
}

///|
/// G_DEPTH global 索引（批 1b 六槽之后第 7——垫收证人模块不含本槽）。
pub const G_DEPTH : Int32 = 6

///|
/// 块首步锚：`steps += len`（global.get/const/add/set）。
fn push_step_add(body : Array[WInstr], len : Int32) -> Unit {
  body.push(WGlobalGet(G_STEPS))
  body.push(WI32Const(len))
  body.push(WI32Add)
  body.push(WGlobalSet(G_STEPS))
}

///|
/// 块尾预算检查：`if steps >= max_steps: return -1`（overshoot ≤1 块
/// 的已知分叉——预算 trap 语料 steps 对拍面由 4b 闸登记豁免）。
fn push_budget_check(body : Array[WInstr], max_steps : Int32) -> Unit {
  body.push(WGlobalGet(G_STEPS))
  body.push(WI32Const(max_steps))
  body.push(WI32GeS)
  body.push(WIf)
  body.push(WI32Const(-1))
  body.push(WReturn)
  body.push(WEnd)
}

///|
/// Jump 族执行展开：微缩模板形态 + BrAny 深度重编（探针 3：深度是发射
/// 上下文参数——折叠不还原、执行侧重编）。if 内 br 深度 +1（微缩模板
/// 的块内 br 结构）。
fn push_jump_with_depth(
  body : Array[WInstr],
  op : @opcode.OpCode,
  operand : Int32,
  ctx : EmitCtx,
  depth : Int32,
) -> Unit {
  // 逐 SeqItem 发射（模板单源）——BrAny → WBr(depth 调整)
  let s = template_spec(op)
  guard s.pat is Some(pat) else { return }
  let items = match pat {
    Seq(items) => items
    _ => return
  }
  for item in items {
    let w : WInstr? = match item {
      Fixed(w) => Some(w)
      OpI32 => Some(WI32Const(operand))
      BrAny => None // 下面特判（深度重编）
      CtxI32(slot) => Some(WI32Const(ctx_slot_value(ctx, slot)))
      _ => None // Jump 族模板只用 Fixed/OpI32/BrAny/CtxI32 四形态
    }
    match w {
      Some(w) => body.push(w)
      None =>
        if item is BrAny {
          // 顶层 br 深度 = depth；微缩模板的块内 br（JumpIf 族）不变
          // ——微缩形态 br 均在顶层或块外，块内只有 br_if（Fixed 形态）
          body.push(WBr(depth))
        }
    }
  }
}

///|
/// Call/CallVar 执行展开（软件调用栈完整协议——VM do_call 同构）：
/// ①深度上限检查（G_DEPTH——教学 trap：超限 unreachable）；
/// ②NULL 下界检查（SPT − (12+frame) < 0x1000 → unreachable——堆碰撞
/// 检查首版不做，blocks 头注登记）；
/// ③参数搬运（param_words 声明序逆序逐 word 弹出——wasm 栈 LIFO 对齐
/// VM do_call 弹序；i64 双 word 形态待 4b 锚）；
/// ④帧头三 word（return_ip=gip+1 | orig_top=SPT | caller_fb=FB）@
/// 新帧底 −12；
/// ⑤指针更新（SPT −= 12+frame；FB = 新 locals_base；DEPTH += 1）；
/// ⑥pc = target_ip；br 回分发。
fn push_call_expand(
  body : Array[WInstr],
  meta : CallSiteMeta,
  gip : Int32,
  depth_limit : Int32,
  br_depth : Int32,
) -> Unit {
  // ①深度上限（教学 trap——unreachable 形态，文案不比对〔结果级三锚〕）
  body.push(WGlobalGet(G_DEPTH))
  body.push(WI32Const(depth_limit))
  body.push(WI32GeS)
  body.push(WIf)
  body.push(WUnreachable)
  body.push(WEnd)
  // ②NULL 下界（SPT - (12+frame) < NULL_TRAP_SIZE → trap）
  body.push(WGlobalGet(G_SPT))
  body.push(WI32Const(12 + meta.frame_bytes))
  body.push(WI32Sub)
  body.push(WI32Const(0x1000))
  body.push(WI32LtS)
  body.push(WIf)
  body.push(WUnreachable)
  body.push(WEnd)
  // ③参数搬运（逆序：最后参最后 word 先弹）——地址 = SPT - frame + off*4
  //   （压帧前用旧 SPT；新 locals_base = SPT - frame_bytes）
  // 计算总 word 偏移（声明序累计），再逆序发射
  let total : Array[Int32] = []
  let mut acc : Int32 = 0
  for w in meta.param_words {
    total.push(acc)
    acc = acc + w
  }
  for pi = meta.param_words.length() - 1; pi >= 0; pi = pi - 1 {
    let base_off = total[pi]
    let words = meta.param_words[pi]
    // 参数内 word 逆序（栈顶 = 最后 word）
    for k = words - 1; k >= 0; k = k - 1 {
      let woff = base_off + k
      body.push(WLocalSet(L_A)) // 弹 1 word（i32 形态）
      body.push(WGlobalGet(G_SPT))
      body.push(WI32Const(meta.frame_bytes - woff * 4))
      body.push(WI32Sub)
      body.push(WLocalGet(L_A))
      body.push(WI32Store)
    }
  }
  // ④帧头三 word @ SPT - frame_bytes - 12（压帧前旧 SPT；帧头布局
  //   return_ip@+0 | orig_top@+4 | caller_fb@+8）
  body.push(WGlobalGet(G_SPT))
  body.push(WI32Const(meta.frame_bytes + 12))
  body.push(WI32Sub)
  body.push(WI32Const(gip + 1))
  body.push(WI32Store)
  body.push(WGlobalGet(G_SPT))
  body.push(WI32Const(meta.frame_bytes + 8)) // 帧头+4（orig_top）
  body.push(WI32Sub)
  body.push(WGlobalGet(G_SPT))
  body.push(WI32Store)
  body.push(WGlobalGet(G_SPT))
  body.push(WI32Const(meta.frame_bytes + 4)) // 帧头+8（caller_fb）
  body.push(WI32Sub)
  body.push(WGlobalGet(G_FB))
  body.push(WI32Store)
  // ⑤指针更新
  body.push(WGlobalGet(G_SPT))
  body.push(WI32Const(meta.frame_bytes + 12))
  body.push(WI32Sub)
  body.push(WGlobalSet(G_SPT))
  body.push(WGlobalGet(G_SPT))
  body.push(WI32Const(12))
  body.push(WI32Add)
  body.push(WGlobalSet(G_FB)) // FB = SPT_new + 12（= 旧 SPT - frame）
  body.push(WGlobalGet(G_DEPTH))
  body.push(WI32Const(1))
  body.push(WI32Add)
  body.push(WGlobalSet(G_DEPTH))
  // ⑥pc + br（分发循环回边——骨架深度由调用方供给）
  body.push(WI32Const(meta.target_ip))
  body.push(WGlobalSet(G_PC))
  body.push(WBr(br_depth))
}

///|
/// Ret/RetVoid 执行展开（方案 B' 帧头 @ locals_base − 12）：
/// 非 void：栈顶返回值 → G_RV；帧头三读（return_pc → G_PC、orig_top →
/// SPT、caller_fb → FB）；DEPTH −= 1；br 回分发（调用方深度）。
fn push_ret_expand(
  body : Array[WInstr],
  op : @opcode.OpCode,
  br_depth : Int32,
) -> Unit {
  if op is Ret {
    body.push(WGlobalSet(G_RV))
  }
  // return_ip @ FB-12
  body.push(WGlobalGet(G_FB))
  body.push(WI32Const(12))
  body.push(WI32Sub)
  body.push(WI32Load)
  body.push(WGlobalSet(G_PC))
  // orig_top @ FB-8
  body.push(WGlobalGet(G_FB))
  body.push(WI32Const(8))
  body.push(WI32Sub)
  body.push(WI32Load)
  body.push(WGlobalSet(G_SPT))
  // caller_fb @ FB-4
  body.push(WGlobalGet(G_FB))
  body.push(WI32Const(4))
  body.push(WI32Sub)
  body.push(WI32Load)
  body.push(WGlobalSet(G_FB))
  body.push(WGlobalGet(G_DEPTH))
  body.push(WI32Const(-1))
  body.push(WI32Add)
  body.push(WGlobalSet(G_DEPTH))
  body.push(WBr(br_depth))
}
