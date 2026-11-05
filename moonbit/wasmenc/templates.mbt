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
///   池索引），模板唯一可逆但非单指令；发射模板批 1b 接线（本批 pat=None）；
/// - **Ambiguous 歧义需侧车**（13）：字节序列与其他组序列恒等或含上下文
///   编码（br depth/dispatch-loop pc），盲折叠必错其一——**组表侧车是
///   折叠完备性的必要条件**（探针 2 [四] 实锤：`[PushConst(-1);BitXor]`
///   与 `[BitNot]` 字节恒等 `41 7f 73`），批 1b/1c 接线；
/// - **Reserved 不可映射**（7）：零发射保留（发射器穷尽 match 显式拒载，
///   码表编号冻结不删）——C# 异常三件 / Strlen/TrapBoundsVla 死码 /
///   **And/Or（codegen 短路结构下的不可达占位，binary.mbt:380-382 亲读，
///   设计单漏计——本批对账修正）**。
///
/// 计数闭合：83+50+13+7=153（初版 84/49——批 1a 外部证人实锤 i32.extend8_u 不存在后 TruncUByte 移 B，见报告 §对账修正）。**表不变量（测试锁，J9 面）**：
/// `state is Exact ⇔ pat is Some`——发射与折叠共享同一 pat，改坏任一臂
/// （态改了模板没改/模板改了态没改）往返闸必红。
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
/// Exact 态发射模板形态（批 1a 三形状；批 1b 扩 Seq 组合形态与上下文槽）：
/// - `Instr`：零操作数恒等单指令（82 条）；
/// - `I32Slot`：`i32.const`——立即数 = operand 直映（PushConst）；
/// - `F32Slot`：`f32.const`——立即数 4 字节 = operand 位模式小端（PushConstF，
///   位模式无损往返）。
pub(all) enum ExactPat {
  Instr(WInstr)
  I32Slot
  F32Slot
} derive(Debug, Eq)

///|
pub extend ExactPat with Eq::{not_equal, equal}

///|
pub extend ExactPat with Debug::{to_repr}

///|
pub(all) struct TemplateSpec {
  state : FoldState
  /// Vitro 值栈弹出数（-1 = 上下文相关/不可静态——控制流与 CallHost 族）
  pops : Int32
  /// Vitro 值栈压入数
  pushes : Int32
  /// 发射模板（Exact 态必有——表不变量测试锁）
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
    // ══ A 类·完全一致（84）——批 1a 全量往返面 ══
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
      // 归 B 类：i32.const 0xFF; i32.and 规范化 local 重排（消歧约定②）
      later(
        Composed,
        1,
        1,
        "i32.const 0xFF; i32.and 规范化重排（低 8 位零扩展）",
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
    // §2.2 行 92「AddQ/SubQ/MulQ 归溢出检查」系误记，本批对账修正归 A）
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
    // ══ B 类·组合可逆（49）——模板批 1b 接线（pat 扩 Seq/上下文槽）══
    // 局部/全局（基线全留内存=帧布局不变——设计单 §2.2 B 类/O4）
    LoadLocal =>
      later(
        Composed,
        0,
        1,
        "global.get $fb; i32.const off; i32.add; i32.load（locals 内存编址，基线不提升）",
      )
    StoreLocal =>
      later(
        Composed,
        1,
        0,
        "地址序列 + i32.store（栈序：addr 先行 value 后压——发射器 API 封装不变量）",
      )
    LoadLocalD =>
      later(Composed, 0, 1, "fb+off; 8 字节读（f64 位模式）")
    StoreLocalD => later(Composed, 1, 0, "fb+off; 8 字节写")
    LoadLocalQ => later(Composed, 0, 1, "fb+off; i64.load")
    StoreLocalQ => later(Composed, 1, 0, "fb+off; i64.store")
    LoadGlobal =>
      later(
        Composed,
        0,
        1,
        "i32.const <GLOBAL_START+off>; i32.load（编译期地址已知）",
      )
    StoreGlobal => later(Composed, 1, 0, "i32.const <addr>; i32.store")
    LoadGlobalD =>
      later(Composed, 0, 1, "i32.const addr; f64.load（8 字节全局）")
    StoreGlobalD => later(Composed, 1, 0, "i32.const addr; f64.store")
    LoadGlobalQ => later(Composed, 0, 1, "i32.const addr; i64.load")
    StoreGlobalQ => later(Composed, 1, 0, "i32.const addr; i64.store")
    StoreGlobalByte =>
      later(
        Composed,
        1,
        0,
        "i32.const addr; i32.store8（char 1 字节粒度，#177）",
      )
    LoadGlobalByte => later(Composed, 0, 1, "i32.const addr; i32.load8_s")
    LoadGlobalUByte => later(Composed, 0, 1, "i32.const addr; i32.load8_u")
    GetFrameBase =>
      later(Composed, 0, 1, "global.get $fb（专用 global 槽约定）")
    // 栈操作（wasm 无 dup/swap——专用暂存槽重排，形态与 locals 序列区分）
    Dup =>
      later(
        Composed,
        1,
        2,
        "local.tee $t; local.get $t（专用暂存槽无碰撞）",
      )
    Swap => later(Composed, 2, 2, "local.set×2 + local.get×2 反序重排")
    // 访存（受检：NULL 区显式检查 + 上界=16 页 memory 白送）
    LoadMem =>
      later(
        Composed,
        1,
        1,
        "NULL 区（<0x1000）检查 + i32.load——现役 vm_load_u32 受检语义镜像",
      )
    StoreMem =>
      later(
        Composed,
        2,
        0,
        "NULL 检查 + i32.store（栈序 [addr,value]——探针最高频坑位，API 封装）",
      )
    LoadMemByte => later(Composed, 1, 1, "NULL 检查 + i32.load8_s")
    StoreMemByte => later(Composed, 2, 0, "NULL 检查 + i32.store8")
    LoadMemUByte => later(Composed, 1, 1, "NULL 检查 + i32.load8_u")
    LoadMemD => later(Composed, 1, 1, "NULL 检查 + f64.load")
    StoreMemD => later(Composed, 2, 0, "NULL 检查 + f64.store")
    LoadMemQ => later(Composed, 1, 1, "NULL 检查 + i64.load")
    StoreMemQ => later(Composed, 2, 0, "NULL 检查 + i64.store")
    SplitD =>
      later(
        Composed,
        1,
        2,
        "i64.reinterpret_f64; 拆半各符号扩展压栈（exec_memory.mbt:76 同构）",
      )
    SplitQ =>
      later(Composed, 1, 2, "i64 拆半（low/high 各 i32 符号扩展）")
    StackAlloc =>
      later(
        Composed,
        1,
        1,
        "负数/溢出/保留区检查 + mem_stack_top 下移 + 地址压栈",
      )
    Memcpy =>
      later(
        Composed,
        3,
        1,
        "check 面 + memory.copy（memmove——现役已是临时缓冲 memmove，O3 语义等价亲读 exec_memory.mbt:125；与 oracle 软截断差异同款保留）",
      )
    Memset => later(Composed, 3, 1, "check 面 + memory.fill")
    // 有符号溢出检查算术（i64 中间值法——教学 trap 面）
    Add =>
      later(
        Composed,
        2,
        1,
        "i64.extend×2; i64.add; 域检查越界 br trap 出口; i32.wrap",
      )
    Sub => later(Composed, 2, 1, "同上 i64 中间值法")
    Mul => later(Composed, 2, 1, "同上")
    Neg => later(Composed, 1, 1, "-INT_MIN 检查 + 取反（教学 trap）")
    NegQ =>
      later(
        Composed,
        1,
        1,
        "LLONG_MIN 检查（exec_float.mbt:267 教学 trap）+ 取反",
      )
    UNeg =>
      later(
        Composed,
        1,
        1,
        "0-sub 回绕（规范化 local 重排形态——避开 [const -1;mul] 与 UMul 歧义）",
      )
    UNegQ => later(Composed, 1, 1, "0-sub i64 回绕（规范化形态）")
    // 移位域检查（0~31/0~63 越界 trap——exec_arith.mbt 镜像）
    Shl => later(Composed, 2, 1, "域检查 0~31 + i32.shl")
    Shr => later(Composed, 2, 1, "域检查 + i32.shr_s")
    LShr => later(Composed, 2, 1, "域检查 + i32.shr_u")
    ShlQ => later(Composed, 2, 1, "域检查 0~63 + i64.shl")
    ShrQ => later(Composed, 2, 1, "域检查 + i64.shr_s")
    LShrQ => later(Composed, 2, 1, "域检查 + i64.shr_u")
    // 常量池索引（值可逆；operand 索引经组表侧车核对——同值多索引歧义面）
    PushConstD =>
      later(
        Composed,
        0,
        1,
        "f64.const（operand=常量池索引→位模式；索引经侧车核对）",
      )
    PushConstQ =>
      later(Composed, 0, 1, "i64.const（常量池索引→值；同上）")
    // 教学观测
    StepEvent =>
      later(
        Composed,
        0,
        0,
        "步锚 $steps+=1 四条序列——**组前计步**（探针 3：组后发射遇 br 死代码永不计步）；current_line/断点/vis 语义留权威侧",
      )
    TrapBounds =>
      later(
        Composed,
        1,
        1,
        "索引域检查（idx<0||idx>=size→unreachable）；operand（符号下标/负长度）不进字节、经侧车",
      )
    // ══ C 类·歧义需侧车（13）——组表给组边界/上下文，盲折叠必错其一 ══
    Jump =>
      later(
        Ambiguous,
        -1,
        -1,
        "dispatch-loop：pc 赋值 + br（depth=发射上下文参数，折叠不还原——探针 2 结论 4）",
      )
    JumpIfZero =>
      later(
        Ambiguous,
        1,
        -1,
        "条件 br（fallthrough 需发射期填——块后继是块结构信息）",
      )
    JumpIfNotZero => later(Ambiguous, 1, -1, "同上")
    Call =>
      later(
        Ambiguous,
        -1,
        -1,
        "软件调用栈：压帧内存写+$fb 更新+块首 pc（与 do_call 四重防护同构）",
      )
    CallPtr => later(Ambiguous, -1, -1, "同上（指针目标运行期）")
    CallVar => later(Ambiguous, -1, -1, "同上")
    CallHost =>
      later(
        Ambiguous,
        -1,
        -1,
        "import env.vitro_host_call(route_id,argv_ptr)->i64（H2 单一 ABI）+参数区写+返回压栈",
      )
    Ret =>
      later(
        Ambiguous,
        -1,
        -1,
        "清帧+pc 回跳+$fb 恢复（回调哨兵上下文）",
      )
    RetVoid => later(Ambiguous, -1, -1, "同上无值")
    BitNot =>
      later(
        Ambiguous,
        1,
        1,
        "i32.const -1; i32.xor——与 [PushConst(-1);BitXor] 字节恒等（探针实锤 41 7f 73），折叠靠组表",
      )
    BitNotQ =>
      later(
        Ambiguous,
        1,
        1,
        "i64.const -1; i64.xor——同上（与 PushConstQ(-1);BitXorQ 恒等）",
      )
    PushArgc =>
      later(
        Ambiguous,
        0,
        1,
        "i32.const argc——与 PushConst(argc) 字节同形（argc 编译期已知），侧车消歧",
      )
    PushArgv =>
      later(
        Ambiguous,
        0,
        1,
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
