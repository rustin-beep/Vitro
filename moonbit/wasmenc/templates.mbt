///|
/// **153 码表语义表（L1 唯一真源）**——一条 opcode 一臂（穷尽 match 无
/// 兜底，编码纪律 1：opcode 增删直接编译红），每臂同时携带**四态标注 +
/// 栈效应 + 发射模板**——发射器（emit.mbt）与折叠器（fold.mbt）共享本表
/// 驱动（探针报告 §5.1 实证：表驱动是把批 1 工程量控制在估算内的必要
/// 形态，手写双实现膨胀 ~1.7×）。
///
/// 四态（REHOST 批 1a 对账口径，逐条账目见 tmp/batch_REHOST_1a_REPORT.md；
/// 语义依据 = vm executor 现状亲读，非设计单计数）：
/// - **Exact 完全一致**（83）：1:1 单 wasm 指令精确直映（含 trap 面同构的
///   div/rem 族与饱和 trunc_sat 族）——字节层模板唯一可逆、零歧义；
/// - **Composed 组合可逆**（50）：多条组合展开（检查序列/上下文编址/常量
///   池索引），单组「发射→折叠」往返成立（批 1b 接线）；**跨组重叠区**
///   （TruncUByte=[i32.const 255; i32.and] 与两组合 [PushConst(255);BitAnd]
///   字节恒等）由盲折叠的贪心最长匹配规范化 + 组表侧车终裁；
/// - **Ambiguous 歧义需侧车**（13）：字节序列与其他组序列恒等或含上下文
///   编码（br depth/dispatch-loop pc/argc 编译期值），盲折叠必错其一——
///   **组表侧车是折叠完备性的必要条件**（探针 2 [四] 实锤：`[PushConst(-1);
///   BitXor]` 与 `[BitNot]` 字节恒等 `41 7f 73`）。批 1b 起携带模板但**不入
///   盲折叠匹配表**（fold 的 build 只收 Exact+Composed）——模板仅供组表
///   引导裁决（grouptable 的 verify_fold_with_table）与发射消费；
/// - **Reserved 不可映射**（7）：零发射保留（发射器穷尽 match 显式拒载，
///   码表编号冻结不删）——C# 异常三件 / Strlen/TrapBoundsVla 死码 /
///   And/Or（codegen 短路结构下的不可达占位，binary.mbt:380-382 亲读，
///   设计单漏计——批 1a 对账修正）。
///
/// 计数闭合：83+50+13+7=153。**表不变量（测试锁，J9 面）**：
/// `state ≠ Reserved ⇔ pat is Some`——发射与折叠共享同一 pat，改坏任一臂
/// （态改了模板没改/模板改了态没改）往返闸必红；盲折叠表内形状唯一
/// （同形双模板 = 永久歧义 = 表设计缺陷，装载即红）。
///
/// 栈效应（pops/pushes，-1=上下文相关不可静态）是发射模板的**栈序不变量
/// 锚**——白盒测试断言发射序列的 wasm 栈净效应与此处一致（探针报告
/// §5.2：栈序类错误验证器不拦，本会话级最高频坑）。
pub(all) enum FoldState {
  Exact
  Composed
  Ambiguous
  Reserved
} derive(Eq, Compare, Debug)

///|
pub extend FoldState with Eq::{not_equal, equal}

///|
pub extend FoldState with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend FoldState with Debug::{to_repr}

///|
/// Exact/Composed/Ambiguous 态发射模板形态：
/// - `Instr`：零操作数恒等单指令（Exact 82 条）；
/// - `I32Slot`：`i32.const`——立即数 = operand 直映（PushConst）；
/// - `F32Slot`：`f32.const`——立即数 4 字节 = operand 位模式小端（PushConstF，
///   位模式无损往返）；
/// - `Seq`：多指令组合模板（批 1b——B 类 50 + C 类 13；C 类 Seq 不入盲
///   折叠匹配表，仅供组表引导裁决）。
pub(all) enum ExactPat {
  Instr(WInstr)
  I32Slot
  F32Slot
  Seq(Array[SeqItem])
} derive(Debug, Eq)

///|
pub extend ExactPat with Eq::{not_equal, equal}

///|
pub extend ExactPat with Debug::{to_repr}

///|
/// 组合模板项（Seq 元素）：`Fixed` 严格比对，其余为**可变槽**——发射侧
/// 由 operand/EmitCtx 填值，折叠侧按槽语义还原（或不还原）。
pub(all) enum SeqItem {
  /// 固定指令（含 local/global/br 的立即数——值严格比对）
  Fixed(WInstr)
  /// i32.const <operand>（折叠还原 operand = 立即数值）
  OpI32
  /// i32.const <base + operand 无符号>（折叠还原 = 值 − base；全局族
  /// base=GLOBAL_START——「编译期地址已知」的编码形态）
  OpBase(Int32)
  /// f64.const <ctx.f64_constants[operand]>（折叠还原 = 池反查首索引；
  /// 同值多索引歧义面由组表终裁——表注「索引经侧车核对」）
  F64Of
  /// i64.const <ctx.i64_constants[operand]>（同上）
  I64Of
  /// i32.const <ctx 上下文槽>（不还原——argc/argv/fallthrough/ret_pc/
  /// 参数区地址均为发射上下文参数，探针 2 结论 4 同款「解码消费不还原」）
  CtxI32(CtxSlot)
  /// i32.const <符号尺寸>（TrapBounds：operand ≥ 0 查 ctx.symbol_sizes、
  /// < 0 取 -operand——符号表在侧车，字节只携带尺寸值，不还原）
  SymSize
  /// br <任意深度>（dispatch-loop 的 label 深度是发射上下文参数——折叠
  /// 消费任意值不还原，探针 2 结论 4 实测坑位：硬编码 depth 折叠必红）
  BrAny
} derive(Debug, Eq)

///|
pub extend SeqItem with Eq::{not_equal, equal}

///|
pub extend SeqItem with Debug::{to_repr}

///|
/// CtxI32 的上下文槽（EmitCtx 字段——发射侧取值，折叠侧不还原）。
pub(all) enum CtxSlot {
  /// argc 编译期已知（PushArgc）
  Argc
  /// argv 区地址（PushArgv——argv 区由 data 段/侧车铺设）
  ArgvAddr
  /// 块 fallthrough 后继 pc（JumpIf 族落空分支 / Call 族返回 pc——块
  /// 结构信息，组操作只带 taken 目标，探针 3 工程坑记录）
  FallthroughPc
  /// CallHost 参数区约定地址（H2 ABI 的 argv_ptr）
  HostArgvPtr
} derive(Debug, Eq)

///|
pub extend CtxSlot with Eq::{not_equal, equal}

///|
pub extend CtxSlot with Debug::{to_repr}

// ══ 装载约定（批 1b 定形——模块段结构的发射器侧契约，wabt 外部证人
//    按此组装模块骨架）══
// 全局槽表（主函数 wasm global 段索引——单主函数 dispatch-loop 形态，
// 设计单 §2.1 global 段用途 + 批 1b 增补软栈指针/返回槽）：

///|
/// dispatch pc（i32 mut）——Jump/CallIf 族的目标载体。
pub const G_PC : Int32 = 0

///|
/// 帧基址 $fb（i32 mut）= CallFrame.locals_base——LoadLocal 族编址基。
pub const G_FB : Int32 = 1

///|
/// 步数计数器 $steps（i32 mut）——StepEvent 静态计数（组前计步）。
pub const G_STEPS : Int32 = 2

///|
/// 软栈指针 $sp（i32 mut）= mem_stack_top——StackAlloc/调用栈帧几何。
pub const G_SPT : Int32 = 3

///|
/// 返回 pc 槽（i32 mut）——软件调用栈的 return_ip 载体（微缩形态：
/// 单层返回地址，批 2 折叠执行器扩完整 CallFrame 协议时评估升格内存栈）。
pub const G_RET : Int32 = 4

///|
/// 返回值槽（i64 mut）——Ret 的值回传（u64 位模式域）。
pub const G_RV : Int32 = 5

///|
/// i32 值暂存（local 0）——Store 族值重排 / Neg·移位检查 / Swap·Dup。
pub const L_V : Int32 = 0

///|
/// i32 地址暂存（local 1）——NULL 区检查 tee 的 addr 载体 / Swap 第二槽。
pub const L_A : Int32 = 1

///|
/// i32 第三暂存（local 2）——Memcpy 的 n / Memset 的 size。
pub const L_N : Int32 = 2

///|
/// i64 暂存（local 3）——Q/D 族值重排 / 移位量 / Split 位拆源。
pub const L_T64 : Int32 = 3

///|
/// f64 暂存（local 4）——StoreLocalD/StoreMemD 的值重排。
pub const L_TF : Int32 = 4

///|
/// f32 暂存（local 5，预留——批 1b 模板面未消费）。
pub const L_TF32 : Int32 = 5

///|
pub(all) struct TemplateSpec {
  state : FoldState
  /// Vitro 值栈弹出数（-1 = 上下文相关/不可静态——控制流与 CallHost 族）
  pops : Int32
  /// Vitro 值栈压入数
  pushes : Int32
  /// 发射模板（非 Reserved 态必有——表不变量测试锁）
  pat : ExactPat?
  /// 模板要点/歧义对/保留原因（语义注记）
  hint : String
} derive(Debug, Eq)

///|
pub extend TemplateSpec with Eq::{not_equal, equal}

///|
pub extend TemplateSpec with Debug::{to_repr}

///|
fn exact(
  pops : Int32,
  pushes : Int32,
  pat : ExactPat,
  hint : String,
) -> TemplateSpec {
  { state: Exact, pops, pushes, pat: Some(pat), hint, }
}

///|
/// 组合/歧义态模板臂（批 1b：B/C 类全量接线——pat 入表共享发射/折叠）。
fn seq(
  state : FoldState,
  pops : Int32,
  pushes : Int32,
  items : Array[SeqItem],
  hint : String,
) -> TemplateSpec {
  { state, pops, pushes, pat: Some(Seq(items)), hint, }
}

///|
fn later(
  state : FoldState,
  pops : Int32,
  pushes : Int32,
  hint : String,
) -> TemplateSpec {
  { state, pops, pushes, pat: None, hint, }
}

///|
/// 153 臂穷尽语义表（发射器/折叠器共享单源入口）。
pub fn template_spec(op : @opcode.OpCode) -> TemplateSpec {
  match op {
    // ══ A 类·完全一致（83）——批 1a 全量往返面 ══
    // 栈顶三件
    Nop => exact(0, 0, Instr(WNop), "wasm nop（零栈效应）")
    PushConst => exact(0, 1, I32Slot, "i32.const sleb(operand) 直映")
    Pop => exact(1, 0, Instr(WDrop), "drop")
    // i32 直映族（回绕/trap 面同构/位运算）
    Div =>
      exact(
        2,
        1,
        Instr(WI32DivS),
        "i32.div_s——trap 面（除零+INT_MIN/-1）与现役同构",
      )
    Mod =>
      exact(
        2,
        1,
        Instr(WI32RemS),
        "i32.rem_s——wasm 对 INT_MIN/-1 亦 trap，同构",
      )
    TruncByte =>
      exact(
        1,
        1,
        Instr(WI32Extend8S),
        "i32.extend8_s（低 8 位符号扩展）",
      )
    TruncUByte =>
      // wasm 无 extend8_u（sign-extension-ops 仅 _s 族——wabt parseWat 实证）；
      // 归 B 类：i32.const 0xFF; i32.and 规范化（低 8 位零扩展）。跨组重叠：
      // [PushConst(255); BitAnd] 字节恒等——盲折叠贪心规范化收 TruncUByte，
      // 组表终裁真实分组
      seq(
        Composed,
        1,
        1,
        [Fixed(WI32Const(255)), Fixed(WI32And)],
        "i32.const 0xFF; i32.and 规范化（低 8 位零扩展）",
      )
    Eq => exact(2, 1, Instr(WI32Eq), "i32.eq")
    Ne => exact(2, 1, Instr(WI32Ne), "i32.ne")
    Lt => exact(2, 1, Instr(WI32LtS), "i32.lt_s")
    Le => exact(2, 1, Instr(WI32LeS), "i32.le_s")
    Gt => exact(2, 1, Instr(WI32GtS), "i32.gt_s")
    Ge => exact(2, 1, Instr(WI32GeS), "i32.ge_s")
    Not =>
      exact(
        1,
        1,
        Instr(WI32Eqz),
        "i32.eqz（逻辑非——Not 有发射：unary.mbt:85）",
      )
    ULt => exact(2, 1, Instr(WI32LtU), "i32.lt_u")
    ULe => exact(2, 1, Instr(WI32LeU), "i32.le_u")
    UGt => exact(2, 1, Instr(WI32GtU), "i32.gt_u")
    UGe => exact(2, 1, Instr(WI32GeU), "i32.ge_u")
    UDiv =>
      exact(
        2,
        1,
        Instr(WI32DivU),
        "i32.div_u（trap 面：仅除零，同构）",
      )
    UMod => exact(2, 1, Instr(WI32RemU), "i32.rem_u")
    UAdd => exact(2, 1, Instr(WI32Add), "i32.add（U32 域回绕同构）")
    USub => exact(2, 1, Instr(WI32Sub), "i32.sub（回绕）")
    UMul => exact(2, 1, Instr(WI32Mul), "i32.mul（回绕）")
    BitAnd => exact(2, 1, Instr(WI32And), "i32.and")
    BitOr => exact(2, 1, Instr(WI32Or), "i32.or")
    BitXor => exact(2, 1, Instr(WI32Xor), "i32.xor")
    BitAndQ =>
      exact(
        2,
        1,
        Instr(WI64And),
        "i64.and（u64 位模式——与符号无关）",
      )
    BitOrQ => exact(2, 1, Instr(WI64Or), "i64.or")
    BitXorQ =>
      exact(
        2,
        1,
        Instr(WI64Xor),
        "i64.xor（BitNotQ 的歧义对位：i64.const -1;i64.xor——C 类侧车）",
      )
    // f32 族（Vitro 栈=u64 低 32 位位模式 ↔ wasm 栈 f32 型——载体分型约定）
    PushConstF =>
      exact(
        0,
        1,
        F32Slot,
        "f32.const（operand=位模式，4 字节小端无损）",
      )
    AddF => exact(2, 1, Instr(WF32Add), "f32.add")
    SubF => exact(2, 1, Instr(WF32Sub), "f32.sub")
    MulF => exact(2, 1, Instr(WF32Mul), "f32.mul")
    DivF =>
      exact(
        2,
        1,
        Instr(WF32Div),
        "f32.div（IEEE 除零=±inf/NaN 不 trap，#163 同口径）",
      )
    NegF => exact(1, 1, Instr(WF32Neg), "f32.neg（一元负保留 -0.0 位）")
    CastI2F => exact(1, 1, Instr(WF32ConvertI32S), "f32.convert_i32_s")
    CastF2I =>
      exact(
        1,
        1,
        Instr(WI32TruncSatF32S),
        "i32.trunc_sat_f32_s（饱和：NaN→0/inf→±MAX）",
      )
    EqF => exact(2, 1, Instr(WF32Eq), "f32.eq")
    NeF => exact(2, 1, Instr(WF32Ne), "f32.ne")
    LtF => exact(2, 1, Instr(WF32Lt), "f32.lt")
    LeF => exact(2, 1, Instr(WF32Le), "f32.le")
    GtF => exact(2, 1, Instr(WF32Gt), "f32.gt")
    GeF => exact(2, 1, Instr(WF32Ge), "f32.ge")
    CastU2F =>
      exact(
        1,
        1,
        Instr(WF32ConvertI32U),
        "f32.convert_i32_u（u32 零符号位，病 31）",
      )
    CastUQ2F =>
      exact(1, 1, Instr(WF32ConvertI64U), "f32.convert_i64_u（#345）")
    // f64 族
    AddD => exact(2, 1, Instr(WF64Add), "f64.add")
    SubD => exact(2, 1, Instr(WF64Sub), "f64.sub")
    MulD => exact(2, 1, Instr(WF64Mul), "f64.mul")
    DivD => exact(2, 1, Instr(WF64Div), "f64.div（IEEE 同口径）")
    NegD => exact(1, 1, Instr(WF64Neg), "f64.neg")
    CastI2D => exact(1, 1, Instr(WF64ConvertI32S), "f64.convert_i32_s")
    CastF2D => exact(1, 1, Instr(WF64PromoteF32), "f64.promote_f32")
    CastD2I =>
      exact(1, 1, Instr(WI32TruncSatF64S), "i32.trunc_sat_f64_s（饱和）")
    CastD2F => exact(1, 1, Instr(WF32DemoteF64), "f32.demote_f64")
    EqD => exact(2, 1, Instr(WF64Eq), "f64.eq")
    NeD => exact(2, 1, Instr(WF64Ne), "f64.ne")
    LtD => exact(2, 1, Instr(WF64Lt), "f64.lt")
    LeD => exact(2, 1, Instr(WF64Le), "f64.le")
    GtD => exact(2, 1, Instr(WF64Gt), "f64.gt")
    GeD => exact(2, 1, Instr(WF64Ge), "f64.ge")
    CastU2D =>
      exact(1, 1, Instr(WF64ConvertI32U), "f64.convert_i32_u（病 31）")
    CastUQ2D =>
      exact(1, 1, Instr(WF64ConvertI64U), "f64.convert_i64_u（#345）")
    // Q 族（回绕态——exec_float.mbt:216 亲读：I64 四则无故障面；设计单
    // §2.2 行 92「AddQ/SubQ/MulQ 归溢出检查」系误记，批 1a 对账修正归 A）
    AddQ => exact(2, 1, Instr(WI64Add), "i64.add（Q 族回绕不 trap）")
    SubQ => exact(2, 1, Instr(WI64Sub), "i64.sub（回绕）")
    MulQ => exact(2, 1, Instr(WI64Mul), "i64.mul（回绕）")
    DivQ =>
      exact(2, 1, Instr(WI64DivS), "i64.div_s（除零+LLONG_MIN/-1 同构）")
    ModQ => exact(2, 1, Instr(WI64RemS), "i64.rem_s（同构）")
    CastI2Q => exact(1, 1, Instr(WI64ExtendI32S), "i64.extend_i32_s")
    CastQ2I =>
      exact(1, 1, Instr(WI32WrapI64), "i32.wrap_i64（低 32 位截断）")
    CastQ2D =>
      exact(1, 1, Instr(WF64ConvertI64S), "f64.convert_i64_s（有符号）")
    CastD2Q =>
      exact(
        1,
        1,
        Instr(WI64TruncSatF64S),
        "i64.trunc_sat_f64_s（饱和——现役 to_int64 同语义）",
      )
    EqQ => exact(2, 1, Instr(WI64Eq), "i64.eq")
    NeQ => exact(2, 1, Instr(WI64Ne), "i64.ne")
    LtQ => exact(2, 1, Instr(WI64LtS), "i64.lt_s")
    LeQ => exact(2, 1, Instr(WI64LeS), "i64.le_s")
    GtQ => exact(2, 1, Instr(WI64GtS), "i64.gt_s")
    GeQ => exact(2, 1, Instr(WI64GeS), "i64.ge_s")
    CastU2Q =>
      exact(
        1,
        1,
        Instr(WI64ExtendI32U),
        "i64.extend_i32_u（u32 零扩展，病 31）",
      )
    UDivQ => exact(2, 1, Instr(WI64DivU), "i64.div_u（仅除零 trap）")
    UModQ => exact(2, 1, Instr(WI64RemU), "i64.rem_u")
    ULtQ => exact(2, 1, Instr(WI64LtU), "i64.lt_u（病 34）")
    ULeQ => exact(2, 1, Instr(WI64LeU), "i64.le_u")
    UGtQ => exact(2, 1, Instr(WI64GtU), "i64.gt_u")
    UGeQ => exact(2, 1, Instr(WI64GeU), "i64.ge_u")
    // ══ B 类·组合可逆（50）——批 1b 模板接线（单组往返 + 组表终裁）══
    // 局部族（基线全留内存=帧布局不变——设计单 §2.2 B 类/O4；地址 =
    // $fb + operand（u32 域，exec_stack.mbt execute_local 镜像）
    LoadLocal =>
      seq(
        Composed,
        0,
        1,
        [Fixed(WGlobalGet(G_FB)), OpI32, Fixed(WI32Add), Fixed(WI32Load)],
        "global.get $fb; i32.const off; i32.add; i32.load（locals 内存编址，基线不提升）",
      )
    StoreLocal =>
      // 栈序红线：值已在 wasm 栈顶，addr 序列须垫底——local.set 暂存重排
      seq(
        Composed,
        1,
        0,
        [
          Fixed(WLocalSet(L_V)),
          Fixed(WGlobalGet(G_FB)),
          OpI32,
          Fixed(WI32Add),
          Fixed(WLocalGet(L_V)),
          Fixed(WI32Store),
        ],
        "值暂存 + fb+off 编址 + i32.store（栈序 [addr,value]——API 封装不变量）",
      )
    LoadLocalD =>
      seq(
        Composed,
        0,
        1,
        [Fixed(WGlobalGet(G_FB)), OpI32, Fixed(WI32Add), Fixed(WF64Load)],
        "fb+off; f64.load（8 字节，f64 位模式）",
      )
    StoreLocalD =>
      seq(
        Composed,
        1,
        0,
        [
          Fixed(WLocalSet(L_TF)),
          Fixed(WGlobalGet(G_FB)),
          OpI32,
          Fixed(WI32Add),
          Fixed(WLocalGet(L_TF)),
          Fixed(WF64Store),
        ],
        "f64 暂存重排 + fb+off; f64.store",
      )
    LoadLocalQ =>
      seq(
        Composed,
        0,
        1,
        [Fixed(WGlobalGet(G_FB)), OpI32, Fixed(WI32Add), Fixed(WI64Load)],
        "fb+off; i64.load",
      )
    StoreLocalQ =>
      seq(
        Composed,
        1,
        0,
        [
          Fixed(WLocalSet(L_T64)),
          Fixed(WGlobalGet(G_FB)),
          OpI32,
          Fixed(WI32Add),
          Fixed(WLocalGet(L_T64)),
          Fixed(WI64Store),
        ],
        "i64 暂存重排 + fb+off; i64.store",
      )
    // 全局族（GLOBAL_START=0x1000 + operand（u32）——execute_global 镜像；
    // 编码形态 i32.const <0x1000+off>（编译期地址已知）
    LoadGlobal =>
      seq(
        Composed,
        0,
        1,
        [OpBase(0x1000), Fixed(WI32Load)],
        "i32.const <GLOBAL_START+off>; i32.load（编译期地址已知）",
      )
    StoreGlobal =>
      seq(
        Composed,
        1,
        0,
        [
          Fixed(WLocalSet(L_V)),
          OpBase(0x1000),
          Fixed(WLocalGet(L_V)),
          Fixed(WI32Store),
        ],
        "i32.const <addr>; i32.store",
      )
    LoadGlobalD =>
      seq(
        Composed,
        0,
        1,
        [OpBase(0x1000), Fixed(WF64Load)],
        "addr; f64.load（8 字节全局）",
      )
    StoreGlobalD =>
      seq(
        Composed,
        1,
        0,
        [
          Fixed(WLocalSet(L_TF)),
          OpBase(0x1000),
          Fixed(WLocalGet(L_TF)),
          Fixed(WF64Store),
        ],
        "addr; f64.store",
      )
    LoadGlobalQ =>
      seq(Composed, 0, 1, [OpBase(0x1000), Fixed(WI64Load)], "addr; i64.load")
    StoreGlobalQ =>
      seq(
        Composed,
        1,
        0,
        [
          Fixed(WLocalSet(L_T64)),
          OpBase(0x1000),
          Fixed(WLocalGet(L_T64)),
          Fixed(WI64Store),
        ],
        "addr; i64.store",
      )
    StoreGlobalByte =>
      seq(
        Composed,
        1,
        0,
        [
          Fixed(WLocalSet(L_V)),
          OpBase(0x1000),
          Fixed(WLocalGet(L_V)),
          Fixed(WI32Store8),
        ],
        "addr; i32.store8（char 1 字节粒度，#177——只落低 8 位不越权抹邻居）",
      )
    LoadGlobalByte =>
      seq(
        Composed,
        0,
        1,
        [OpBase(0x1000), Fixed(WI32Load8S)],
        "addr; i32.load8_s（char 符号扩展读）",
      )
    LoadGlobalUByte =>
      seq(
        Composed,
        0,
        1,
        [OpBase(0x1000), Fixed(WI32Load8U)],
        "addr; i32.load8_u（u8 零扩展读）",
      )
    GetFrameBase =>
      seq(
        Composed,
        0,
        1,
        [Fixed(WGlobalGet(G_FB))],
        "global.get $fb（专用 global 槽约定）",
      )
    // 栈操作（wasm 无 dup/swap——专用暂存槽重排；批 1b i32 域规范形，
    // 跨类型参数化留批 2 codegen 接线）
    Dup =>
      seq(
        Composed,
        1,
        2,
        [Fixed(WLocalTee(L_V)), Fixed(WLocalGet(L_V))],
        "local.tee $t; local.get $t（专用暂存槽无碰撞）",
      )
    Swap =>
      seq(
        Composed,
        2,
        2,
        [
          Fixed(WLocalSet(L_V)),
          Fixed(WLocalSet(L_A)),
          Fixed(WLocalGet(L_V)),
          Fixed(WLocalGet(L_A)),
        ],
        "local.set×2 + local.get×2 反序重排",
      )
    // 访存族（NULL 区 <0x1000 显式检查 + 上界=16 页 memory 白送；
    // 块出口栈回卷语义：addr 经 local 暂存，br 跳出后 local.get 复取——
    // 探针坑位 1（store 栈序）+ wasm br 到 void label 弹栈到块入口深度的
    // 双重陷阱一并规避）
    LoadMem =>
      seq(
        Composed,
        1,
        1,
        [
          Fixed(WLocalSet(L_A)),
          Fixed(WBlock),
          Fixed(WLocalGet(L_A)),
          Fixed(WI32Const(0x1000)),
          Fixed(WI32GeU),
          Fixed(WBrIf(0)),
          Fixed(WUnreachable),
          Fixed(WEnd),
          Fixed(WLocalGet(L_A)),
          Fixed(WI32Load),
        ],
        "NULL 区（<0x1000）检查 + i32.load——vm_load_u32 受检语义镜像",
      )
    StoreMem =>
      seq(
        Composed,
        2,
        0,
        [
          Fixed(WLocalSet(L_V)),
          Fixed(WLocalSet(L_A)),
          Fixed(WBlock),
          Fixed(WLocalGet(L_A)),
          Fixed(WI32Const(0x1000)),
          Fixed(WI32GeU),
          Fixed(WBrIf(0)),
          Fixed(WUnreachable),
          Fixed(WEnd),
          Fixed(WLocalGet(L_A)),
          Fixed(WLocalGet(L_V)),
          Fixed(WI32Store),
        ],
        "NULL 检查 + i32.store（栈序 [addr,value]——探针最高频坑位，API 封装）",
      )
    LoadMemByte =>
      seq(
        Composed,
        1,
        1,
        [
          Fixed(WLocalSet(L_A)),
          Fixed(WBlock),
          Fixed(WLocalGet(L_A)),
          Fixed(WI32Const(0x1000)),
          Fixed(WI32GeU),
          Fixed(WBrIf(0)),
          Fixed(WUnreachable),
          Fixed(WEnd),
          Fixed(WLocalGet(L_A)),
          Fixed(WI32Load8S),
        ],
        "NULL 检查 + i32.load8_s",
      )
    StoreMemByte =>
      seq(
        Composed,
        2,
        0,
        [
          Fixed(WLocalSet(L_V)),
          Fixed(WLocalSet(L_A)),
          Fixed(WBlock),
          Fixed(WLocalGet(L_A)),
          Fixed(WI32Const(0x1000)),
          Fixed(WI32GeU),
          Fixed(WBrIf(0)),
          Fixed(WUnreachable),
          Fixed(WEnd),
          Fixed(WLocalGet(L_A)),
          Fixed(WLocalGet(L_V)),
          Fixed(WI32Store8),
        ],
        "NULL 检查 + i32.store8",
      )
    LoadMemUByte =>
      seq(
        Composed,
        1,
        1,
        [
          Fixed(WLocalSet(L_A)),
          Fixed(WBlock),
          Fixed(WLocalGet(L_A)),
          Fixed(WI32Const(0x1000)),
          Fixed(WI32GeU),
          Fixed(WBrIf(0)),
          Fixed(WUnreachable),
          Fixed(WEnd),
          Fixed(WLocalGet(L_A)),
          Fixed(WI32Load8U),
        ],
        "NULL 检查 + i32.load8_u（病 32：unsigned char 零扩展）",
      )
    LoadMemD =>
      seq(
        Composed,
        1,
        1,
        [
          Fixed(WLocalSet(L_A)),
          Fixed(WBlock),
          Fixed(WLocalGet(L_A)),
          Fixed(WI32Const(0x1000)),
          Fixed(WI32GeU),
          Fixed(WBrIf(0)),
          Fixed(WUnreachable),
          Fixed(WEnd),
          Fixed(WLocalGet(L_A)),
          Fixed(WF64Load),
        ],
        "NULL 检查 + f64.load",
      )
    StoreMemD =>
      seq(
        Composed,
        2,
        0,
        [
          Fixed(WLocalSet(L_TF)),
          Fixed(WLocalSet(L_A)),
          Fixed(WBlock),
          Fixed(WLocalGet(L_A)),
          Fixed(WI32Const(0x1000)),
          Fixed(WI32GeU),
          Fixed(WBrIf(0)),
          Fixed(WUnreachable),
          Fixed(WEnd),
          Fixed(WLocalGet(L_A)),
          Fixed(WLocalGet(L_TF)),
          Fixed(WF64Store),
        ],
        "NULL 检查 + f64.store",
      )
    LoadMemQ =>
      seq(
        Composed,
        1,
        1,
        [
          Fixed(WLocalSet(L_A)),
          Fixed(WBlock),
          Fixed(WLocalGet(L_A)),
          Fixed(WI32Const(0x1000)),
          Fixed(WI32GeU),
          Fixed(WBrIf(0)),
          Fixed(WUnreachable),
          Fixed(WEnd),
          Fixed(WLocalGet(L_A)),
          Fixed(WI64Load),
        ],
        "NULL 检查 + i64.load",
      )
    StoreMemQ =>
      seq(
        Composed,
        2,
        0,
        [
          Fixed(WLocalSet(L_T64)),
          Fixed(WLocalSet(L_A)),
          Fixed(WBlock),
          Fixed(WLocalGet(L_A)),
          Fixed(WI32Const(0x1000)),
          Fixed(WI32GeU),
          Fixed(WBrIf(0)),
          Fixed(WUnreachable),
          Fixed(WEnd),
          Fixed(WLocalGet(L_A)),
          Fixed(WLocalGet(L_T64)),
          Fixed(WI64Store),
        ],
        "NULL 检查 + i64.store",
      )
    SplitD =>
      seq(
        Composed,
        1,
        2,
        [
          Fixed(WI64ReinterpretF64),
          Fixed(WLocalSet(L_T64)),
          Fixed(WLocalGet(L_T64)),
          Fixed(WI32WrapI64),
          Fixed(WLocalGet(L_T64)),
          Fixed(WI64Const(32)),
          Fixed(WI64ShrU),
          Fixed(WI32WrapI64),
        ],
        "i64.reinterpret_f64; 拆半各符号扩展压栈（exec_memory.mbt:76 同构——low 先 high 后）",
      )
    SplitQ =>
      seq(
        Composed,
        1,
        2,
        [
          Fixed(WLocalSet(L_T64)),
          Fixed(WLocalGet(L_T64)),
          Fixed(WI32WrapI64),
          Fixed(WLocalGet(L_T64)),
          Fixed(WI64Const(32)),
          Fixed(WI64ShrU),
          Fixed(WI32WrapI64),
        ],
        "i64 拆半（low/high 各 i32 符号扩展）",
      )
    StackAlloc =>
      // 三重检查全保形（exec_memory.mbt:85-99 镜像）：负数（ge_s 0）/
      // 对齐后溢出（le_u $sp）/保留区（sp−aligned ≥ 0x1000）——u32 域
      // 比较使负 size 天然落入非法侧
      seq(
        Composed,
        1,
        1,
        [
          Fixed(WLocalSet(L_V)),
          Fixed(WBlock),
          Fixed(WLocalGet(L_V)),
          Fixed(WI32Const(0)),
          Fixed(WI32GeS),
          Fixed(WBrIf(0)),
          Fixed(WUnreachable),
          Fixed(WEnd),
          Fixed(WLocalGet(L_V)),
          Fixed(WI32Const(3)),
          Fixed(WI32Add),
          Fixed(WI32Const(-4)),
          Fixed(WI32And),
          Fixed(WLocalSet(L_V)),
          Fixed(WBlock),
          Fixed(WLocalGet(L_V)),
          Fixed(WGlobalGet(G_SPT)),
          Fixed(WI32LeU),
          Fixed(WBrIf(0)),
          Fixed(WUnreachable),
          Fixed(WEnd),
          Fixed(WBlock),
          Fixed(WGlobalGet(G_SPT)),
          Fixed(WLocalGet(L_V)),
          Fixed(WI32Sub),
          Fixed(WI32Const(0x1000)),
          Fixed(WI32GeU),
          Fixed(WBrIf(0)),
          Fixed(WUnreachable),
          Fixed(WEnd),
          Fixed(WGlobalGet(G_SPT)),
          Fixed(WLocalGet(L_V)),
          Fixed(WI32Sub),
          Fixed(WGlobalSet(G_SPT)),
          Fixed(WGlobalGet(G_SPT)),
        ],
        "负数/溢出/保留区检查 + $sp 下移 + 新顶压栈（exec_memory.mbt:85 镜像）",
      )
    Memcpy =>
      // NULL 检查（dest/src 起址）+ memory.copy（memmove——现役临时缓冲
      // 同语义，O3 对账亲读 exec_memory.mbt:125）；区间上界=OOB trap 白送；
      // 检查失败即终局（render_mem_fault=trap 亲读 trap.mbt:408——后续
      // push 不可达），检查后压回 dest 保栈形
      seq(
        Composed,
        3,
        1,
        [
          Fixed(WLocalSet(L_V)),
          Fixed(WLocalSet(L_A)),
          Fixed(WLocalSet(L_N)),
          Fixed(WBlock),
          Fixed(WLocalGet(L_V)),
          Fixed(WI32Const(0x1000)),
          Fixed(WI32GeU),
          Fixed(WBrIf(0)),
          Fixed(WUnreachable),
          Fixed(WEnd),
          Fixed(WBlock),
          Fixed(WLocalGet(L_A)),
          Fixed(WI32Const(0x1000)),
          Fixed(WI32GeU),
          Fixed(WBrIf(0)),
          Fixed(WUnreachable),
          Fixed(WEnd),
          Fixed(WLocalGet(L_V)),
          Fixed(WLocalGet(L_A)),
          Fixed(WLocalGet(L_N)),
          Fixed(WMemoryCopy),
          Fixed(WLocalGet(L_V)),
        ],
        "check 面 + memory.copy（memmove——exec_memory.mbt:125 等价亲读）",
      )
    Memset =>
      // value 低 8 位（&0xFF）——u64 位模式经 i64 暂存 wrap 收窄
      seq(
        Composed,
        3,
        1,
        [
          Fixed(WLocalSet(L_V)),
          Fixed(WLocalSet(L_T64)),
          Fixed(WLocalSet(L_N)),
          Fixed(WBlock),
          Fixed(WLocalGet(L_V)),
          Fixed(WI32Const(0x1000)),
          Fixed(WI32GeU),
          Fixed(WBrIf(0)),
          Fixed(WUnreachable),
          Fixed(WEnd),
          Fixed(WLocalGet(L_V)),
          Fixed(WLocalGet(L_T64)),
          Fixed(WI32WrapI64),
          Fixed(WI32Const(0xFF)),
          Fixed(WI32And),
          Fixed(WLocalGet(L_N)),
          Fixed(WMemoryFill),
          Fixed(WLocalGet(L_V)),
        ],
        "check 面 + memory.fill（value 低 8 位）",
      )
    // 有符号溢出检查算术（i64 中间值法——教学 trap 面；检查形态 =
    // wrap 后符号扩展回比较（i64.eq）等价判定，jit_survey §4.2 同款）
    Add =>
      seq(
        Composed,
        2,
        1,
        [
          Fixed(WLocalSet(L_A)),
          Fixed(WI64ExtendI32S),
          Fixed(WLocalGet(L_A)),
          Fixed(WI64ExtendI32S),
          Fixed(WI64Add),
          Fixed(WLocalSet(L_T64)),
          Fixed(WBlock),
          Fixed(WLocalGet(L_T64)),
          Fixed(WI32WrapI64),
          Fixed(WI64ExtendI32S),
          Fixed(WLocalGet(L_T64)),
          Fixed(WI64Eq),
          Fixed(WBrIf(0)),
          Fixed(WUnreachable),
          Fixed(WEnd),
          Fixed(WLocalGet(L_T64)),
          Fixed(WI32WrapI64),
        ],
        "i64.extend×2; i64.add; 域检查越界 br trap 出口; i32.wrap",
      )
    Sub =>
      seq(
        Composed,
        2,
        1,
        [
          Fixed(WLocalSet(L_A)),
          Fixed(WI64ExtendI32S),
          Fixed(WLocalGet(L_A)),
          Fixed(WI64ExtendI32S),
          Fixed(WI64Sub),
          Fixed(WLocalSet(L_T64)),
          Fixed(WBlock),
          Fixed(WLocalGet(L_T64)),
          Fixed(WI32WrapI64),
          Fixed(WI64ExtendI32S),
          Fixed(WLocalGet(L_T64)),
          Fixed(WI64Eq),
          Fixed(WBrIf(0)),
          Fixed(WUnreachable),
          Fixed(WEnd),
          Fixed(WLocalGet(L_T64)),
          Fixed(WI32WrapI64),
        ],
        "同 Add 的 i64 中间值法（i64.sub）",
      )
    Mul =>
      seq(
        Composed,
        2,
        1,
        [
          Fixed(WLocalSet(L_A)),
          Fixed(WI64ExtendI32S),
          Fixed(WLocalGet(L_A)),
          Fixed(WI64ExtendI32S),
          Fixed(WI64Mul),
          Fixed(WLocalSet(L_T64)),
          Fixed(WBlock),
          Fixed(WLocalGet(L_T64)),
          Fixed(WI32WrapI64),
          Fixed(WI64ExtendI32S),
          Fixed(WLocalGet(L_T64)),
          Fixed(WI64Eq),
          Fixed(WBrIf(0)),
          Fixed(WUnreachable),
          Fixed(WEnd),
          Fixed(WLocalGet(L_T64)),
          Fixed(WI32WrapI64),
        ],
        "同 Add 的 i64 中间值法（i64.mul）",
      )
    Neg =>
      seq(
        Composed,
        1,
        1,
        [
          Fixed(WLocalSet(L_V)),
          Fixed(WBlock),
          Fixed(WLocalGet(L_V)),
          Fixed(WI32Const(-2147483648)),
          Fixed(WI32Ne),
          Fixed(WBrIf(0)),
          Fixed(WUnreachable),
          Fixed(WEnd),
          Fixed(WI32Const(0)),
          Fixed(WLocalGet(L_V)),
          Fixed(WI32Sub),
        ],
        "INT_MIN 检查 + 0−a 取反（教学 trap；sub 操作数序经暂存重排保 0 在下）",
      )
    NegQ =>
      seq(
        Composed,
        1,
        1,
        [
          Fixed(WLocalSet(L_T64)),
          Fixed(WBlock),
          Fixed(WLocalGet(L_T64)),
          Fixed(WI64Const(-9223372036854775808L)),
          Fixed(WI64Ne),
          Fixed(WBrIf(0)),
          Fixed(WUnreachable),
          Fixed(WEnd),
          Fixed(WI64Const(0L)),
          Fixed(WLocalGet(L_T64)),
          Fixed(WI64Sub),
        ],
        "LLONG_MIN 检查（exec_float.mbt:267 教学 trap）+ 取反",
      )
    UNeg =>
      seq(
        Composed,
        1,
        1,
        [
          Fixed(WLocalSet(L_V)),
          Fixed(WI32Const(0)),
          Fixed(WLocalGet(L_V)),
          Fixed(WI32Sub),
        ],
        "0−a 回绕（规范化暂存重排——避开 [const -1;mul] 与 UMul 歧义）",
      )
    UNegQ =>
      seq(
        Composed,
        1,
        1,
        [
          Fixed(WLocalSet(L_T64)),
          Fixed(WI64Const(0L)),
          Fixed(WLocalGet(L_T64)),
          Fixed(WI64Sub),
        ],
        "0−a i64 回绕（规范化形态）",
      )
    // 移位域检查（0~31/0~63 越界 trap——exec_arith.mbt 镜像；le_u 使
    // 负移位量天然非法；移位量暂存后复取保 [value, shift] 栈序）
    Shl =>
      seq(
        Composed,
        2,
        1,
        [
          Fixed(WLocalSet(L_A)),
          Fixed(WBlock),
          Fixed(WLocalGet(L_A)),
          Fixed(WI32Const(31)),
          Fixed(WI32LeU),
          Fixed(WBrIf(0)),
          Fixed(WUnreachable),
          Fixed(WEnd),
          Fixed(WLocalGet(L_A)),
          Fixed(WI32Shl),
        ],
        "域检查 0~31 + i32.shl",
      )
    Shr =>
      seq(
        Composed,
        2,
        1,
        [
          Fixed(WLocalSet(L_A)),
          Fixed(WBlock),
          Fixed(WLocalGet(L_A)),
          Fixed(WI32Const(31)),
          Fixed(WI32LeU),
          Fixed(WBrIf(0)),
          Fixed(WUnreachable),
          Fixed(WEnd),
          Fixed(WLocalGet(L_A)),
          Fixed(WI32ShrS),
        ],
        "域检查 + i32.shr_s",
      )
    LShr =>
      seq(
        Composed,
        2,
        1,
        [
          Fixed(WLocalSet(L_A)),
          Fixed(WBlock),
          Fixed(WLocalGet(L_A)),
          Fixed(WI32Const(31)),
          Fixed(WI32LeU),
          Fixed(WBrIf(0)),
          Fixed(WUnreachable),
          Fixed(WEnd),
          Fixed(WLocalGet(L_A)),
          Fixed(WI32ShrU),
        ],
        "域检查 + i32.shr_u",
      )
    ShlQ =>
      seq(
        Composed,
        2,
        1,
        [
          Fixed(WLocalSet(L_T64)),
          Fixed(WBlock),
          Fixed(WLocalGet(L_T64)),
          Fixed(WI64Const(63)),
          Fixed(WI64LeU),
          Fixed(WBrIf(0)),
          Fixed(WUnreachable),
          Fixed(WEnd),
          Fixed(WLocalGet(L_T64)),
          Fixed(WI64Shl),
        ],
        "域检查 0~63 + i64.shl",
      )
    ShrQ =>
      seq(
        Composed,
        2,
        1,
        [
          Fixed(WLocalSet(L_T64)),
          Fixed(WBlock),
          Fixed(WLocalGet(L_T64)),
          Fixed(WI64Const(63)),
          Fixed(WI64LeU),
          Fixed(WBrIf(0)),
          Fixed(WUnreachable),
          Fixed(WEnd),
          Fixed(WLocalGet(L_T64)),
          Fixed(WI64ShrS),
        ],
        "域检查 + i64.shr_s",
      )
    LShrQ =>
      seq(
        Composed,
        2,
        1,
        [
          Fixed(WLocalSet(L_T64)),
          Fixed(WBlock),
          Fixed(WLocalGet(L_T64)),
          Fixed(WI64Const(63)),
          Fixed(WI64LeU),
          Fixed(WBrIf(0)),
          Fixed(WUnreachable),
          Fixed(WEnd),
          Fixed(WLocalGet(L_T64)),
          Fixed(WI64ShrU),
        ],
        "域检查 + i64.shr_u",
      )
    // 常量池索引（值可逆；同值多索引歧义面由组表终裁——池反查取首索引）
    PushConstD =>
      seq(
        Composed,
        0,
        1,
        [F64Of],
        "f64.const（operand=常量池索引→位模式；池反查还原，索引经侧车终裁）",
      )
    PushConstQ =>
      seq(
        Composed,
        0,
        1,
        [I64Of],
        "i64.const（常量池索引→值；同上）",
      )
    // 教学观测（operand=行号/符号下标不进字节——current_line/断点/vis
    // /E3086 文案渲染全留权威侧，组表侧车携带 operand）
    StepEvent =>
      seq(
        Composed,
        0,
        0,
        [
          Fixed(WGlobalGet(G_STEPS)),
          Fixed(WI32Const(1)),
          Fixed(WI32Add),
          Fixed(WGlobalSet(G_STEPS)),
        ],
        "步锚 $steps+=1 四条序列（组前计步——探针 3：组后发射遇 br 死代码永不计步）；operand 不进字节经侧车",
      )
    TrapBounds =>
      // 检查形态：合法 ⇔ (unsigned)idx < size——负 idx 的 u32 解释 ≥2^31
      // > size（size < 2^31）天然落非法侧，一比较覆盖两分支
      //（exec_debug.mbt:102 `index < 0 || index >= size` 镜像）
      seq(
        Composed,
        1,
        1,
        [
          Fixed(WLocalSet(L_A)),
          Fixed(WBlock),
          Fixed(WLocalGet(L_A)),
          SymSize,
          Fixed(WI32LtU),
          Fixed(WBrIf(0)),
          Fixed(WUnreachable),
          Fixed(WEnd),
          Fixed(WLocalGet(L_A)),
        ],
        "索引域检查（(u)idx<size 一比较双分支）；operand（符号下标/负长度）不进字节、经侧车",
      )
    // ══ C 类·歧义需侧车（13）——模板入表但不入盲折叠匹配表；
    //     组表引导裁决（verify_fold_with_table）消费，盲折叠遇其字节
    //     按 A/B 解释（歧义事实锚固化）══
    Jump =>
      seq(
        Ambiguous,
        -1,
        -1,
        [OpI32, Fixed(WGlobalSet(G_PC)), BrAny],
        "dispatch-loop：pc 赋值 + br（depth=发射上下文参数，折叠不还原——探针 2 结论 4）",
      )
    JumpIfZero =>
      // taken ⇔ cond==0：br_if 出块 = 落空（fallthrough 体在后），块内
      // 落入 = taken 体（target=operand 可还原；fallthrough=上下文槽）
      seq(
        Ambiguous,
        1,
        -1,
        [
          Fixed(WLocalSet(L_A)),
          Fixed(WBlock),
          Fixed(WLocalGet(L_A)),
          Fixed(WBrIf(0)),
          OpI32,
          Fixed(WGlobalSet(G_PC)),
          BrAny,
          Fixed(WEnd),
          CtxI32(FallthroughPc),
          Fixed(WGlobalSet(G_PC)),
          BrAny,
        ],
        "条件 br（taken=target；fallthrough 需发射期填——块后继是块结构信息）",
      )
    JumpIfNotZero =>
      // taken ⇔ cond≠0：镜像形态——taken 体移块外（br_if 出块即 taken）
      seq(
        Ambiguous,
        1,
        -1,
        [
          Fixed(WLocalSet(L_A)),
          Fixed(WBlock),
          Fixed(WLocalGet(L_A)),
          Fixed(WBrIf(0)),
          CtxI32(FallthroughPc),
          Fixed(WGlobalSet(G_PC)),
          BrAny,
          Fixed(WEnd),
          OpI32,
          Fixed(WGlobalSet(G_PC)),
          BrAny,
        ],
        "同上镜像（taken 体在块外）",
      )
    Call =>
      seq(
        Ambiguous,
        -1,
        -1,
        [
          CtxI32(FallthroughPc),
          Fixed(WGlobalSet(G_RET)),
          OpI32,
          Fixed(WGlobalSet(G_PC)),
          BrAny,
        ],
        "软件调用栈微缩：返回 pc 存 $ret + 块首 pc 赋值（批 2 折叠执行器扩完整 do_call 四重防护同构协议）",
      )
    CallPtr =>
      seq(
        Ambiguous,
        -1,
        -1,
        [
          Fixed(WLocalSet(L_V)),
          CtxI32(FallthroughPc),
          Fixed(WGlobalSet(G_RET)),
          Fixed(WLocalGet(L_V)),
          Fixed(WGlobalSet(G_PC)),
          BrAny,
        ],
        "同上（指针目标运行期——pc 来自栈值非立即数）",
      )
    CallVar =>
      seq(
        Ambiguous,
        -1,
        -1,
        [
          Fixed(WLocalSet(L_V)),
          CtxI32(FallthroughPc),
          Fixed(WGlobalSet(G_RET)),
          OpI32,
          Fixed(WGlobalSet(G_PC)),
          BrAny,
        ],
        "同上（弹变参计数 argc 后静态目标）",
      )
    CallHost =>
      seq(
        Ambiguous,
        -1,
        -1,
        [OpI32, CtxI32(HostArgvPtr), Fixed(WCall(0))],
        "import env.vitro_host_call(route_id,argv_ptr)->i64（H2 单一 ABI——函数索引 0 约定）+返回值压栈",
      )
    Ret =>
      seq(
        Ambiguous,
        -1,
        -1,
        [
          Fixed(WGlobalSet(G_RV)),
          Fixed(WGlobalGet(G_RET)),
          Fixed(WGlobalSet(G_PC)),
          BrAny,
        ],
        "返回值入 $rv + pc 回跳（回调哨兵上下文批 2 接线）",
      )
    RetVoid =>
      seq(
        Ambiguous,
        -1,
        -1,
        [Fixed(WGlobalGet(G_RET)), Fixed(WGlobalSet(G_PC)), BrAny],
        "同上无值（与 Ret 差首指令——形状可分）",
      )
    BitNot =>
      seq(
        Ambiguous,
        1,
        1,
        [Fixed(WI32Const(-1)), Fixed(WI32Xor)],
        "i32.const -1; i32.xor——与 [PushConst(-1);BitXor] 字节恒等（探针实锤 41 7f 73），裁决靠组表",
      )
    BitNotQ =>
      seq(
        Ambiguous,
        1,
        1,
        [Fixed(WI64Const(-1L)), Fixed(WI64Xor)],
        "i64.const -1; i64.xor——同上（与 PushConstQ(-1);BitXorQ 恒等）",
      )
    PushArgc =>
      seq(
        Ambiguous,
        0,
        1,
        [CtxI32(Argc)],
        "i32.const argc——与 PushConst(argc) 字节同形（argc 编译期已知），侧车消歧",
      )
    PushArgv =>
      seq(
        Ambiguous,
        0,
        1,
        [CtxI32(ArgvAddr)],
        "i32.const argv_addr——与 PushConst 同形，侧车消歧",
      )
    // ══ D 类·不可映射（7）：零发射保留（显式拒载，编号冻结不删）══
    TryBegin =>
      later(
        Reserved,
        -1,
        -1,
        "C# 异常三件 reserved-for-csharp（C 前端零发射）",
      )
    TryEnd => later(Reserved, -1, -1, "同上")
    Throw => later(Reserved, -1, -1, "同上")
    Strlen =>
      later(
        Reserved,
        -1,
        -1,
        "零发射死码（strlen 走 Bytecode Libc 固定索引 1015）",
      )
    TrapBoundsVla =>
      later(
        Reserved,
        -1,
        -1,
        "零发射死码（VLA 边界检查随死 opcode 裁撤）",
      )
    And =>
      later(
        Reserved,
        -1,
        -1,
        "codegen 短路结构不可达占位（binary.mbt:380-382）——零发射，与 Strlen 同款保留",
      )
    Or => later(Reserved, -1, -1, "同上")
  }
}
