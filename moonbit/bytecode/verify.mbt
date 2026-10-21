///|
/// bytecode 结构验证器（#200 P0，2026-10-21）——「每个变换层的产物都应
/// 有独立验证器」的第一件。回答「对不对」，与五家 golden digest 的
/// 「变没变」互补：digest 红之后人工二分语料，验证器直接指出
/// 「第几条指令违反什么不变量」。
///
/// 四类不变量（issue #200 §P0）：
///  1. 栈效应签名——每 OpCode 的 pop/push word 数 + 全函数栈深度守恒
///     （Ret 前深 1 / RetVoid 前深 0 / 跳转汇合点深一致 / 无下溢）；
///  2. 跳转目标落在指令边界且不跨函数段（code 是 Array[Instruction]，
///     ip 即下标——「边界」落实为值域 + 段隔离双检）；
///  3. FuncMeta 与指令流自洽（键集一致 / arg_count=Σparam_sizes /
///     param_count=length / local_count 覆盖参数区 / 段无缝覆盖）；
///  4. 引用可达（f64/i64 常量池 / symbols 下标 / 局部偏移不越帧 /
///     全局偏移不越 global_data_end / Call 目标在 func_index 值域）。
///
/// 栈深模型（诚实边界，P0 形态）：
///  - **Unknown 传染**——CallHost（host 弹参自管且含 printf/scanf 变参
///    族，静态不知 arity）、CallVar/CallPtr（运行期定目标与字数）三处
///    置 Unknown，之后守恒判定放弃但不假绿；host id → (pop,push) 全表
///    是 #200 P1（双路径互拍）的配套件，届时一并落地；
///  - **线性扫描 + 汇合点登记**——非 worklist dataflow：Jump 的
///    fallthrough 深度被保守地延续到后续块（结构化 codegen 的块入口深
///    == 前驱出口深，该假设成立时无漏报；不成立处由汇合点冲突检查兜
///    底）。已知漏报面：Jump 后死路的深度不参与汇合判定——只漏报不
///    假绿，P1 升级 worklist 时消除；
///  - **libc 段深未知**——Call 到固定索引段 [1000,1088)（预编译
///    Bytecode Libc，不在本产物 func_table 内）弹参字数无静态源，同置
///    Unknown。
///
/// 不做（登记）：PushConst 立即数的值域（无法区分整数与字符串地址）；
/// source_map 地址单调性（观察面非执行契约）。
///
/// 消费面：cmd/dump_compile 出口外层 `verify` 字段（不进 14 键 dump 对拍
/// 面——零 digest 扰动）→ scripts/codegen_diff 读该字段计红（verify 失败
/// = CONTENT 级真红；字段缺失 = 协议缺位红，同 slot_strategy 空集红逻辑）。
/// J9：verify_wbtest.mbt 逐类注入违约证红。

///|
/// 验证违约（结构化——kind 稳定字符串供 Go 侧与测试锚定）。
pub(all) struct VerifyViolation {
  /// 不变量类别码（stack-underflow / stack-unbalanced-ret /
  /// jump-cross-segment / jump-out-of-range / meta-inconsistent /
  /// ref-out-of-range / call-unknown-target / segment-fallthrough /
  /// reserved-opcode / wrapper-shape / data-overlap）。
  kind : String
  /// 所在函数段名（产物级检查 = "<output>"，wrapper 段 = "<wrapper>"）。
  func : String
  /// 指令下标（产物级检查 = -1）。
  ip : Int32
  detail : String
} derive(Debug, Eq)

///|
pub extend VerifyViolation with Debug::{to_repr}

///|
pub extend VerifyViolation with Eq::{not_equal, equal}

///|
/// 栈深三态：Known(相对函数入口深度) / Unknown（动态点后放弃判定）。
priv enum VDepth {
  VKnown(Int32)
  VUnknown
}

///|
/// 访存宽度（局部/全局偏移检查用）。
fn op_access_width(op : @opcode.OpCode) -> Int32? {
  match op {
    LoadLocal | StoreLocal | LoadGlobal | StoreGlobal => Some(4)
    LoadLocalD
    | StoreLocalD
    | LoadLocalQ
    | StoreLocalQ
    | LoadGlobalD
    | StoreGlobalD
    | LoadGlobalQ
    | StoreGlobalQ => Some(8)
    LoadGlobalByte | LoadGlobalUByte | StoreGlobalByte => Some(1)
    _ => None
  }
}

///|
/// OpCode 栈效应签名（pop/push word 数；真值源 = vm executor 各族弹参/
/// 压参，2026-10-21 逐臂核对）。返回 None = 动态栈效应（调用族——模拟器
/// 特判）。**穷尽无兜底**：新 opcode 入表必须显式归类，漏归类即编译红。
fn v_effect(op : @opcode.OpCode) -> (Int32, Int32)? {
  match op {
    // —— 零效应：观测/死码/保留段 + Swap（原位交换）——
    Nop
    | Swap
    | Jump
    | StepEvent
    | TrapBounds
    | TrapBoundsVla
    | Strlen
    | TryBegin
    | TryEnd
    | Throw
    | RetVoid => Some((0, 0))
    // —— 纯压栈：常量/参数/取址/读局部/读全局/帧基 ——
    PushConst
    | PushArgc
    | PushArgv
    | PushConstF
    | PushConstD
    | PushConstQ
    | Dup
    | LoadLocal
    | LoadLocalD
    | LoadLocalQ
    | LoadGlobal
    | LoadGlobalD
    | LoadGlobalQ
    | LoadGlobalByte
    | LoadGlobalUByte
    | GetFrameBase => Some((0, 1))
    // —— 弹地址压值 / 弹尺寸压地址：读内存族 + 栈分配 ——
    LoadMem | LoadMemD | LoadMemQ | LoadMemByte | LoadMemUByte | StackAlloc =>
      Some((1, 1))
    // —— 单弹：写局部/写全局/丢弃 ——
    Pop
    | StoreLocal
    | StoreLocalD
    | StoreLocalQ
    | StoreGlobal
    | StoreGlobalD
    | StoreGlobalQ
    | StoreGlobalByte => Some((1, 0))
    // —— 双弹：写内存（值+地址）——
    StoreMem | StoreMemD | StoreMemQ | StoreMemByte => Some((2, 0))
    // —— 一拆二：64 位位模式劈半 ——
    SplitD | SplitQ => Some((1, 2))
    // —— 三弹一压：块操作（dest/src/n 或 ptr/value/size）——
    Memcpy | Memset => Some((3, 1))
    // —— 二元算术/比较/逻辑/移位（i32/F/D/Q/U 全族）——
    Add
    | Sub
    | Mul
    | Div
    | Mod
    | Eq
    | Ne
    | Lt
    | Le
    | Gt
    | Ge
    | And
    | Or
    | BitAnd
    | BitOr
    | BitXor
    | Shl
    | Shr
    | LShr
    | AddF
    | SubF
    | MulF
    | DivF
    | EqF
    | NeF
    | LtF
    | LeF
    | GtF
    | GeF
    | AddD
    | SubD
    | MulD
    | DivD
    | EqD
    | NeD
    | LtD
    | LeD
    | GtD
    | GeD
    | AddQ
    | SubQ
    | MulQ
    | DivQ
    | ModQ
    | EqQ
    | NeQ
    | LtQ
    | LeQ
    | GtQ
    | GeQ
    | UAdd
    | USub
    | UMul
    | UDiv
    | UMod
    | ULt
    | ULe
    | UGt
    | UGe
    | BitAndQ
    | BitOrQ
    | BitXorQ
    | ShlQ
    | ShrQ
    | LShrQ
    | UDivQ
    | UModQ
    | ULtQ
    | ULeQ
    | UGtQ
    | UGeQ => Some((2, 1))
    // —— 一元：取负/逻辑非/位反/转型/窄化 ——
    Neg
    | Not
    | BitNot
    | NegF
    | NegD
    | NegQ
    | CastI2F
    | CastF2I
    | CastI2D
    | CastF2D
    | CastD2I
    | CastD2F
    | CastI2Q
    | CastQ2I
    | CastQ2D
    | CastD2Q
    | BitNotQ
    | CastU2Q
    | CastU2D
    | CastU2F
    | TruncByte
    | TruncUByte
    | UNeg
    | UNegQ => Some((1, 1))
    // —— 条件跳转：弹条件值（主路径不跳转；taken 时深在目标汇合判定）——
    JumpIfZero | JumpIfNotZero => Some((1, 0))
    // —— Ret：弹返回值（守恒检查在模拟器特判——wrapper 顶层 Ret 不弹）——
    Ret => Some((1, 0))
    // —— 动态族：模拟器特判（Call 查 func_table；三调用族 Unknown）——
    Call | CallHost | CallVar | CallPtr => None
  }
}

///|
/// 零发射保留面（C 前端）：产物中出现即产物契约破坏（executor 到达即
/// fail loud 的静态前置版）。
fn v_reserved(op : @opcode.OpCode) -> Bool {
  match op {
    TryBegin | TryEnd | Throw | Strlen | TrapBoundsVla => true
    _ => false
  }
}

///|
/// 入口：验证 CompileOutput（编译成功产物）。返回违约清单（空 = 通过）。
/// `library_mode` 仅影响段布局预期——library 模式 Call 域是 [0,N) 用户
/// 段（无 libc 预注册）；全局编址两模式同公式（GLOBAL_START 基址恒加）。
pub fn verify_compile_output(
  o : CompileOutput,
  library_mode : Bool,
) -> Array[VerifyViolation] {
  let v : Array[VerifyViolation] = []
  let code = o.code
  // ---- 产物级：字符串区/全局初始化数据自洽 ----
  verify_data_layout(o, v)
  // ---- idx → meta 构建 + 键集一致性 ----
  let idx2meta : Map[Int32, FuncMeta] = Map([])
  for name in sorted_keys(o.func_table) {
    match o.func_index.get(name) {
      Some(idx) =>
        match o.func_table.get(name) {
          Some(m) => idx2meta.set(idx, m)
          None => ()
        }
      None =>
        v.push({
          kind: "meta-inconsistent",
          func: name,
          ip: -1,
          detail: "func_table 有而 func_index 无（键集分叉）",
        })
    }
  }
  for name in sorted_keys(o.func_index) {
    if o.func_table.get(name) is None {
      // func_index ⊃ func_table 是设计形态：常规模式 libc 预注册段只进
      // func_index（meta 在预编译 Bytecode Libc 产物内，不在本产物）——
      // 多余键的值落在 libc 固定段为合法；library 模式无预注册，多余键
      // 任意值都是键集分叉
      match o.func_index.get(name) {
        Some(idx) => {
          let libc_prereg = !library_mode &&
            idx >= BYTECODE_LIBC_BASE_INDEX &&
            idx < BYTECODE_LIBC_BASE_INDEX + BYTECODE_LIBC_FUNC_COUNT
          if !libc_prereg {
            v.push({
              kind: "meta-inconsistent",
              func: name,
              ip: -1,
              detail: "func_index 有而 func_table 无（键集分叉且非 libc 预注册段）",
            })
          }
        }
        None => ()
      }
    }
  }
  // ---- Call 值域集（func_index 值集；常规模式含 libc 预注册段）----
  let call_targets : Set[Int32] = Set([])
  o.func_index.each((_, idx) => call_targets.add(idx))
  // ---- 函数段划分（func_table 键 → meta，按 ip 升序）----
  let metas : Array[(String, FuncMeta)] = []
  for name in sorted_keys(o.func_table) {
    match o.func_table.get(name) {
      Some(m) => metas.push((name, m))
      None => ()
    }
  }
  let mut i = 1
  while i < metas.length() {
    let key = metas[i]
    let mut j = i - 1
    while j >= 0 && metas[j].1.ip > key.1.ip {
      metas[j + 1] = metas[j]
      j -= 1
    }
    metas[j + 1] = key
    i += 1
  }
  // ---- wrapper 定位：code[0] 必为 Jump（main 存在时被改写；生成面保证）----
  if code.length() == 0 {
    v.push({
      kind: "segment-fallthrough",
      func: "<output>",
      ip: -1,
      detail: "code 段为空",
    })
    return v
  }
  if code[0].op is Jump {
    let wrapper_ip = code[0].operand
    // 段边界链：1 → 各函数 ip → wrapper_ip（无缝 + 递增）
    if metas.length() > 0 && metas[0].1.ip != 1 {
      v.push({
        kind: "segment-fallthrough",
        func: metas[0].0,
        ip: metas[0].1.ip,
        detail: "首个函数段未从 ip=1 起（code[0] 后有游离指令）",
      })
    }
    let mut expected_ip = 1
    for idx = 0; idx < metas.length(); idx = idx + 1 {
      let (fname, meta) = metas[idx]
      let ip = meta.ip
      // FuncMeta 自洽（类 3）
      verify_func_meta(fname, meta, v)
      if ip != expected_ip {
        v.push({
          kind: "segment-fallthrough",
          func: fname,
          ip,
          detail: "函数段起点 \{ip} ≠ 期望 \{expected_ip}（段间有游离指令或 ip 乱序）",
        })
      }
      let seg_end = if idx + 1 < metas.length() {
        metas[idx + 1].1.ip
      } else {
        wrapper_ip
      }
      verify_function_segment(
        o, fname, meta, ip, seg_end, idx2meta, call_targets, library_mode, v,
      )
      expected_ip = seg_end
    }
    if metas.length() > 0 && expected_ip != wrapper_ip {
      v.push({
        kind: "segment-fallthrough",
        func: "<wrapper>",
        ip: wrapper_ip,
        detail: "wrapper 起点 \{wrapper_ip} ≠ 最后函数段尾 \{expected_ip}",
      })
    }
    // ---- wrapper 段专项（类 1/2 的顶层形态）----
    verify_wrapper_segment(o, wrapper_ip, v)
  } else {
    v.push({
      kind: "wrapper-shape",
      func: "<wrapper>",
      ip: 0,
      detail: "code[0] 不是 Jump（入口 wrapper 缺失——生成面保证 code[0]=Jump wrapper_ip）",
    })
  }
  v
}

///|
/// 产物级数据自洽（类 4 的数据段半边）：string_data 地址升序无重叠；
/// globals_init/globals_init_64 落在 [GLOBAL_START, global_data_end)。
fn verify_data_layout(o : CompileOutput, v : Array[VerifyViolation]) -> Unit {
  let mut prev_end : UInt32 = GLOBAL_START
  for k = 0; k < o.string_data.length(); k = k + 1 {
    let (addr, s) = o.string_data[k]
    if addr < prev_end {
      v.push({
        kind: "data-overlap",
        func: "<output>",
        ip: -1,
        detail: "string_data[\{k}] 地址 \{addr} 与前段末尾 \{prev_end} 重叠/乱序",
      })
    }
    prev_end = addr + cstring_len(s).reinterpret_as_uint() + 1U
  }
  if prev_end > o.global_data_end {
    v.push({
      kind: "data-overlap",
      func: "<output>",
      ip: -1,
      detail: "字符串区末尾 \{prev_end} 越 global_data_end \{o.global_data_end}",
    })
  }
  for pair in o.globals_init_32 {
    // 第一元是相对偏移（装载 = store_u32(GLOBAL_START+off)——受检写、越
    // MEM_SIZE 被静默丢）。条目允许重叠（char[] 逐字节初始化用相邻覆盖
    // 手法——mini_char_array 形态）也允许越 global_data_end（紧排），病界
    // 只有物理可写域
    let addr = GLOBAL_START + pair.0
    if addr + 4U > MEM_SIZE {
      v.push({
        kind: "ref-out-of-range",
        func: "<output>",
        ip: -1,
        detail: "globals_init_32 偏移 \{pair.0}（绝对 \{addr}+4）越 MEM_SIZE——装载时被静默丢弃",
      })
    }
  }
  for pair in o.globals_init_64 {
    let addr = GLOBAL_START + pair.0
    if addr + 8U > MEM_SIZE {
      v.push({
        kind: "ref-out-of-range",
        func: "<output>",
        ip: -1,
        detail: "globals_init_64 偏移 \{pair.0}（绝对 \{addr}+8）越 MEM_SIZE——装载时被静默丢弃",
      })
    }
  }
}

///|
/// FuncMeta 数值自洽（类 3）：ip 非零（0 = 未注册陷阱位）；param_count ==
/// param_sizes.length；arg_count == Σparam_sizes；local_count 覆盖参数区
/// （变参另含 64 字节预留区——enter_function 的固定预留）。
fn verify_func_meta(
  fname : String,
  meta : FuncMeta,
  v : Array[VerifyViolation],
) -> Unit {
  if meta.ip == 0 {
    v.push({
      kind: "meta-inconsistent",
      func: fname,
      ip: -1,
      detail: "ip=0（未注册陷阱位——executor do_call 判 ip==0 为未知函数）",
    })
  }
  let mut total : Int32 = 0
  for w in meta.param_sizes {
    if w <= 0 {
      v.push({
        kind: "meta-inconsistent",
        func: fname,
        ip: -1,
        detail: "param_sizes 含非正 word 数 \{w}",
      })
    } else {
      total += w
    }
  }
  if meta.param_count != meta.param_sizes.length() {
    v.push({
      kind: "meta-inconsistent",
      func: fname,
      ip: -1,
      detail: "param_count \{meta.param_count} ≠ param_sizes 长度 \{meta.param_sizes.length()}",
    })
  }
  if meta.arg_count != total {
    v.push({
      kind: "meta-inconsistent",
      func: fname,
      ip: -1,
      detail: "arg_count \{meta.arg_count} ≠ Σparam_sizes \{total}（Call 弹栈字数失锚）",
    })
  }
  let arg_bytes = total * 4
  let need = if meta.is_variadic { arg_bytes + 64 } else { arg_bytes }
  if meta.local_count < need {
    v.push({
      kind: "ref-out-of-range",
      func: fname,
      ip: -1,
      detail: "local_count \{meta.local_count} 不覆盖参数区 \{need} 字节（变参含 64 预留）",
    })
  }
  for b in meta.local_buffers {
    if b.offset < 0 || b.offset + b.size > meta.local_count {
      v.push({
        kind: "ref-out-of-range",
        func: fname,
        ip: -1,
        detail: "local_buffer '\{b.name}' [\{b.offset},\{b.offset + b.size}) 越帧 \{meta.local_count}",
      })
    }
  }
}

///|
/// 单函数段验证（类 1/2/4 的指令流半边）：[seg_start, seg_end)。
fn verify_function_segment(
  o : CompileOutput,
  fname : String,
  meta : FuncMeta,
  seg_start : Int32,
  seg_end : Int32,
  idx2meta : Map[Int32, FuncMeta],
  call_targets : Set[Int32],
  library_mode : Bool,
  v : Array[VerifyViolation],
) -> Unit {
  let code = o.code
  // 空段（ip 冲突/乱序已由段链检查红）——无指令可验，直接返回
  if seg_end <= seg_start {
    return
  }
  // 段尾控制指令（防 fallthrough 穿段——生成面兜底发射 Ret/RetVoid 保证）
  let last_op = code[seg_end - 1].op
  match last_op {
    Ret | RetVoid | Jump | JumpIfZero | JumpIfNotZero => ()
    _ =>
      v.push({
        kind: "segment-fallthrough",
        func: fname,
        ip: seg_end - 1,
        detail: "段尾指令 \{last_op.name()} 非控制类（顺序执行将穿入下一段）",
      })
  }
  // 栈深模拟 + 引用检查
  let mut depth : VDepth = VKnown(0)
  // 块入口期望深（跳转 taken 目标 + 条件跳转 fallthrough；两次登记不等 =
  // 汇合分叉红）。线性扫描到有登记的入口时以登记值为权威（else 块头
  // 只被 JumpIfZero 到达——其线性前驱是无条件 Jump 的死路，深不可继承）
  let jump_depths : Map[Int32, Int32] = Map([])
  for ip = seg_start; ip < seg_end; ip = ip + 1 {
    // 入口深权威化：有登记则采用（Unknown 恢复 / Known 冲突即真分叉——
    // 登记时的冲突检查已红，此处只切值防级联）
    match jump_depths.get(ip) {
      Some(e) => depth = VKnown(e)
      None => ()
    }
    let ins = code[ip]
    let op = ins.op
    // 零发射保留面
    if v_reserved(op) {
      v.push({
        kind: "reserved-opcode",
        func: fname,
        ip,
        detail: "\{op.name()} 是零发射保留位（C 前端契约——executor 到达即 fail loud）",
      })
    }
    // 引用域检查（类 4）
    verify_operand_range(o, fname, meta, ip, op, ins.operand, v)
    // 跳转目标域 + 段隔离（类 2；汇合深度登记在效应应用后——JumpIfZero
    // 到达目标的深是弹条件值之后的深）
    let is_jump = op is Jump || op is JumpIfZero || op is JumpIfNotZero
    if is_jump {
      let target = ins.operand
      if target < seg_start || target >= seg_end {
        v.push({
          kind: if target >= 0 && target < code.length() {
            "jump-cross-segment"
          } else {
            "jump-out-of-range"
          },
          func: fname,
          ip,
          detail: "\{op.name()} 目标 \{target} 越本函数段 [\{seg_start},\{seg_end})",
        })
      }
    }
    // 栈效应应用（类 1）
    match op {
      Call => {
        // 目标值域（类 4 的 Call 半边）
        if !call_targets.contains(ins.operand) {
          v.push({
            kind: "call-unknown-target",
            func: fname,
            ip,
            detail: "Call 目标 \{ins.operand} 不在 func_index 值域（用户段 ∪ libc 预注册段）",
          })
        }
        match depth {
          VKnown(d) =>
            // libc 段（>=1000 且非 library）无本产物 meta——深 Unknown；
            // 用户段弹 arg_count（含 __ret_ptr 首位）
            if !library_mode && ins.operand >= BYTECODE_LIBC_BASE_INDEX {
              depth = VUnknown
            } else {
              match idx2meta.get(ins.operand) {
                Some(m) =>
                  if d < m.arg_count {
                    v.push({
                      kind: "stack-underflow",
                      func: fname,
                      ip,
                      detail: "Call 弹 \{m.arg_count} word 但栈深仅 \{d}",
                    })
                    depth = VUnknown
                  } else {
                    // 非 void 的返回值由被调方 Ret 压回：调用点净效应 =
                    // -arg_count + 1（短路求值 || 的 Dup/JumpIfNotZero
                    // 形态依赖此语义；void 走 RetVoid 不压）
                    depth = if m.return_type.kind() is TK_Void {
                      VKnown(d - m.arg_count)
                    } else {
                      VKnown(d - m.arg_count + 1)
                    }
                  }
                None => depth = VUnknown
              }
            }
          VUnknown => ()
        }
      }
      CallHost | CallVar | CallPtr =>
        // 动态栈效应（host 变参族/运行期目标）——Unknown 保守
        depth = VUnknown
      Ret =>
        match depth {
          VKnown(d) => {
            if d != 1 {
              v.push({
                kind: "stack-unbalanced-ret",
                func: fname,
                ip,
                detail: "Ret 前栈深 \{d} ≠ 1（函数栈不守恒——净增 \{d - 1}）",
              })
            }
            depth = VKnown(d - 1)
          }
          VUnknown => ()
        }
      RetVoid =>
        match depth {
          VKnown(d) =>
            if d != 0 {
              v.push({
                kind: "stack-unbalanced-ret",
                func: fname,
                ip,
                detail: "RetVoid 前栈深 \{d} ≠ 0（函数栈不守恒——净增 \{d}）",
              })
            }
          VUnknown => ()
        }
      _ =>
        match (depth, v_effect(op)) {
          (VKnown(d), Some((pop, push))) =>
            if d < pop {
              v.push({
                kind: "stack-underflow",
                func: fname,
                ip,
                detail: "\{op.name()} 弹 \{pop} word 但栈深仅 \{d}",
              })
              depth = VUnknown
            } else {
              depth = VKnown(d - pop + push)
            }
          (VUnknown, _) | (_, None) => ()
        }
    }
    // 汇合深度登记（效应应用后——JumpIfZero 到达目标的深 = 弹条件值后）：
    // taken 目标 + 条件跳转的 fallthrough 都登记为块入口；同点两次登记
    // 不等 = 真分叉红。无条件 Jump 的 fallthrough 是死路——cur 置
    // Unknown（后续有登记的入口会恢复）
    if is_jump {
      match depth {
        VKnown(d) => {
          register_entry(fname, ip, ins.operand, d, jump_depths, v)
          if op is Jump {
            depth = VUnknown
            // JumpIfZero/NotZero 的 fallthrough 与 taken 弹同一条件值——同深
          } else if ip + 1 < seg_end {
            register_entry(fname, ip, ip + 1, d, jump_depths, v)
          }
        }
        VUnknown => ()
      }
    }
  }
}

///|
/// 块入口深登记：同点两次登记不等 = 路径守恒破坏（真红）。
fn register_entry(
  fname : String,
  at_ip : Int32,
  entry_ip : Int32,
  d : Int32,
  jump_depths : Map[Int32, Int32],
  v : Array[VerifyViolation],
) -> Unit {
  match jump_depths.get(entry_ip) {
    Some(prev) =>
      if prev != d {
        v.push({
          kind: "stack-underflow",
          func: fname,
          ip: at_ip,
          detail: "块入口 \{entry_ip} 栈深分叉：\{prev} ≠ \{d}（路径守恒破坏）",
        })
      }
    None => jump_depths.set(entry_ip, d)
  }
}

///|
/// 指令 operand 引用域（类 4）：常量池 / symbols 下标 / 局部偏移越帧 /
/// 全局偏移越 global_data_end。
fn verify_operand_range(
  o : CompileOutput,
  fname : String,
  meta : FuncMeta,
  ip : Int32,
  op : @opcode.OpCode,
  operand : Int32,
  v : Array[VerifyViolation],
) -> Unit {
  match op {
    PushConstD =>
      // （PushConstF 是 f32 位模式立即数非索引——exec_float PushConstF 臂，
      // 无域检查）
      if operand < 0 || operand >= o.f64_constants.length() {
        v.push({
          kind: "ref-out-of-range",
          func: fname,
          ip,
          detail: "PushConstD 常量索引 \{operand} 越 f64_constants [\{o.f64_constants.length()}]",
        })
      }
    PushConstQ =>
      if operand < 0 || operand >= o.i64_constants.length() {
        v.push({
          kind: "ref-out-of-range",
          func: fname,
          ip,
          detail: "PushConstQ 常量索引 \{operand} 越 i64_constants [\{o.i64_constants.length()}]",
        })
      }
    TrapBounds =>
      if operand >= 0 && operand >= o.symbols.length() {
        v.push({
          kind: "ref-out-of-range",
          func: fname,
          ip,
          detail: "TrapBounds 符号下标 \{operand} 越 symbols [\{o.symbols.length()}]",
        })
      }
    LoadLocal
    | LoadLocalD
    | LoadLocalQ
    | StoreLocal
    | StoreLocalD
    | StoreLocalQ => {
      let w = op_access_width(op).unwrap()
      if operand < 0 || operand + w > meta.local_count {
        v.push({
          kind: "ref-out-of-range",
          func: fname,
          ip,
          detail: "\{op.name()} 偏移 \{operand}(+\{w}) 越帧 \{meta.local_count}",
        })
      }
    }
    LoadGlobal
    | LoadGlobalD
    | LoadGlobalQ
    | LoadGlobalByte
    | LoadGlobalUByte
    | StoreGlobal
    | StoreGlobalD
    | StoreGlobalQ
    | StoreGlobalByte => {
      let w = op_access_width(op).unwrap()
      let addr = GLOBAL_START + operand.reinterpret_as_uint()
      if operand < 0 || addr + w.reinterpret_as_uint() > o.global_data_end {
        v.push({
          kind: "ref-out-of-range",
          func: fname,
          ip,
          detail: "\{op.name()} 偏移 \{operand}(+\{w}) 越全局区（末 \{o.global_data_end}）",
        })
      }
    }
    _ => ()
  }
}

///|
/// wrapper 段专项：形态 = [PushArgv? PushArgc? Call main Ret]（main 带
/// argc/argv 时四条、无参时两条）；顶层 Ret 是 Finished 语义（不弹栈——
/// executor call_stack 空即 Finished），守恒不判、只判形态与 Call 目标。
fn verify_wrapper_segment(
  o : CompileOutput,
  wrapper_ip : Int32,
  v : Array[VerifyViolation],
) -> Unit {
  let code = o.code
  let seg_end = code.length()
  if wrapper_ip < 1 || wrapper_ip >= seg_end {
    v.push({
      kind: "wrapper-shape",
      func: "<wrapper>",
      ip: wrapper_ip,
      detail: "wrapper 起点 \{wrapper_ip} 越界（code 长 \{seg_end}）",
    })
    return
  }
  // 形态：可选 PushArgv+PushArgc 前缀，然后 Call，段尾 Ret
  let mut ip = wrapper_ip
  let mut main_two_args = false
  if ip + 1 < seg_end && code[ip].op is PushArgv && code[ip + 1].op is PushArgc {
    main_two_args = true
    ip += 2
  }
  if ip >= seg_end || !(code[ip].op is Call) {
    v.push({
      kind: "wrapper-shape",
      func: "<wrapper>",
      ip,
      detail: "wrapper 段缺 Call main（\{wrapper_ip} 起）",
    })
    return
  }
  let main_idx = code[ip].operand
  match o.func_index.get("main") {
    Some(idx) =>
      if idx != main_idx {
        v.push({
          kind: "wrapper-shape",
          func: "<wrapper>",
          ip,
          detail: "wrapper Call 目标 \{main_idx} ≠ func_index[main]=\{idx}",
        })
      }
    None =>
      v.push({
        kind: "wrapper-shape",
        func: "<wrapper>",
        ip,
        detail: "func_index 无 main",
      })
  }
  // PushArgv/PushArgc 前缀 ⇔ main 两参（codegen 生成面约定）
  let main_params : Int32 = match o.func_table.get("main") {
    Some(m) => m.param_sizes.length()
    None => -1
  }
  if (main_params == 2) != main_two_args {
    v.push({
      kind: "wrapper-shape",
      func: "<wrapper>",
      ip: wrapper_ip,
      detail: "PushArgv/PushArgc 前缀(\{main_two_args}) 与 main 参数数(\{main_params}) 不匹配",
    })
  }
  if ip + 1 != seg_end - 1 || !(code[seg_end - 1].op is Ret) {
    v.push({
      kind: "wrapper-shape",
      func: "<wrapper>",
      ip: seg_end - 1,
      detail: "wrapper 段尾非 Ret 或 Call 后有多余指令",
    })
  }
}

///|
/// 违约清单 → JSON（dump_compile 外层 verify 字段的 violations 数组；
/// 显式 emitter——字段序 kind/func/ip/detail 固定，Go 侧按序消费）。
pub fn verify_violations_json(vs : Array[VerifyViolation]) -> String {
  let buf = StringBuilder()
  buf.write_string("[")
  for i = 0; i < vs.length(); i = i + 1 {
    if i > 0 {
      buf.write_string(",")
    }
    let x = vs[i]
    buf.write_string(
      "{\"kind\":\{@ast.json_escape_string(x.kind)},\"func\":\{@ast.json_escape_string(x.func)},\"ip\":\{x.ip},\"detail\":\{@ast.json_escape_string(x.detail)}}",
    )
  }
  buf.write_string("]")
  buf.to_string()
}
