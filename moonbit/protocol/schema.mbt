// schema 版本轨道与行为契约（照搬 native/src/unified/contracts.rs，
// 2026-09-27）。三个问题的答案都在代码里（非只在文档里）：
// 1. v0.1 冻结了什么：SCHEMA_VERSION + STEP_PAYLOAD_FIELDS_V0_1（14 字段
//    白名单，与 scripts/replay/v01_payload_fields.json 单源对账）+
//    RESERVED_FIELDS_V0_2（预留位，激活前不得出现在任何 payload）；
// 2. v0.2 要装什么：V0_2_FIELD_LEDGER（字段台账）+ 激活清单——激活提交
//    必须走完清单，冻结测试主动失败提醒（tripwire）；
// 3. 哪些行为不许被性能优化毁掉：BEHAVIOR_CONTRACTS + 可执行判据
//    check_unwinding_granularity（"UNWINDING 不得合并单步"）。
// 文档锚点：docs/spec/STEP_PAYLOAD_SCHEMA_V0_1.md §7.x/§9/附录 B；
// 契约出处：CSharp前端引入计划.md §6-B、SharpTutor S4 §5。

///|
/// 当前已冻结的 schema 版本。
pub const SCHEMA_VERSION : String = "v0.1"

///|
/// v0.1 冻结时间与签字依据（S1–S5 签字回放 61/61）。
pub const SCHEMA_V0_1_FROZEN_AT : String = "2026-09-12"

///| StepPayload v0.1 顶层字段白名单（14 字段，顺序 = schema §字段表）。

///| 对账单源：scripts/replay/v01_payload_fields.json 的 v01_payload_fields

///| （Go/Python 回放驱动共读同一份；本表为 MoonBit 侧等价物，白盒测试

///|
/// 逐条对账锚锁定，两侧漂移即红）。
pub fn step_payload_fields_v0_1() -> Array[String] {
  [
    "step_index", "code_line", "func_name", "semantic_label", "algorithm_step", "local_vars",
    "call_stack", "vis_events", "heatmap_line", "heatmap_count", "accessed_vars",
    "array_snapshots", "pointer_snapshots", "root_cause_hint",
  ]
}

///| v0.2 预留位字段（异常域，随 v0.1 冻结以"预留位"写入，激活前不得出现

///| 在任何 payload 中）。顺序与 schema §7.x 表格一致；冻结测试按此断言

///|
/// "预留位缺省"。对账单源：v01_payload_fields.json 的 reserved_fields。
pub fn reserved_fields_v0_2() -> Array[String] {
  ["handler_depth", "unwinding", "unwind_frames_left", "current_exception"]
}

///| v0.2 激活清单（激活提交必须逐条走完）。这不是"建议流程"——预留位

///| 断言一旦发现 payload 里出现预留位字段就会失败并把本清单打印出来，

///|
/// 迫使激活者显式改测试；改测试的同时必须完成清单第 2–4 条。
pub fn v0_2_activation_checklist() -> Array[String] {
  [
    "① 只增事件：不得改动 v0.1 既有 14 字段的名称/类型/语义；预留位激活一律以新增字段形态落地（消费方须忽略未知字段）",
    "② 同步更新 docs/spec/STEP_PAYLOAD_SCHEMA_V0_1.md：§9 台账状态 active + §7 校验表追加 v0.2 历史行",
    "③ 重跑引擎侧 C1–C3：cargo test --test step_payload_schema_v0_1_test / --test unified_engine_window_test + go run ./scripts/serve_smoke",
    "④ 重跑签字回放 S1–S5：go run ./scripts/replay/replay_s1_s5.go --anchor <新短哈希>（异常域还需 S4 §5 激活契约 A1–A8）",
    "⑤ 解除冻结测试中的预留位断言（v0.1 断言 → v0.2 断言），并知会下游按容忍矩阵回归 T4 投影",
  ]
}

///|
/// v0.2 字段台账一条（文档 §9 的机器可读单源条目）。
pub(all) struct SchemaFieldPlan {
  /// 字段名（或字段路径形态如 "call_stack[].return_line"）
  field : String
  /// "reserve"（v0.1 已预留，激活即刻可用）/"add"（v0.2 新增字段）
  kind : String
  /// "pending"（未激活）/"active"（已落地）
  status : String
  /// 激活批次
  batch : String
  note : String
} derive(Debug)

///|
/// v0.2 字段台账（照搬 contracts.rs V0_2_FIELD_LEDGER，7 条）。
pub fn v0_2_field_ledger() -> Array[SchemaFieldPlan] {
  [
    {
      field: "handler_depth",
      kind: "reserve",
      status: "pending",
      batch: "CS3b",
      note: "当前受几层 try 保护；与 unwinding 正交（finally 步 handler_depth==0 但仍在展开）",
    },
    {
      field: "unwinding",
      kind: "reserve",
      status: "pending",
      batch: "CS3b",
      note: "展开态显式标记；每帧一 step，不得合并（见 BEHAVIOR_CONTRACTS）",
    },
    {
      field: "unwind_frames_left",
      kind: "reserve",
      status: "pending",
      batch: "CS3b",
      note: "剩余待展开帧数，展开动画驱动字段",
    },
    {
      field: "current_exception",
      kind: "reserve",
      status: "pending",
      batch: "CS3b",
      note: "{type_name, message, addr, origin_line}|null；origin_line 为原始抛点（`throw;` 保留 / `throw e;` 改写）",
    },
    {
      field: "code_file",
      kind: "add",
      status: "pending",
      batch: "v0.2",
      note: "多文件行号归位（§8 #9）：code_line 保持全局行号语义，另附文件名，避免破坏断点/heatmap 口径",
    },
    {
      field: "call_stack[].return_line",
      kind: "add",
      status: "pending",
      batch: "v0.2",
      note: "补全既有字段值（§8 #1）：字段已在 v0.1 中恒为 0，激活 = 记录 VM 帧返回行，属**补值不改字段**",
    },
    {
      field: "func_display_name / func_mangled_name",
      kind: "add",
      status: "pending",
      batch: "v0.2",
      note: "§8 #2：C++/C# 内部名（`__ctor__Vec`）与源码可读名双字段，保留 func_name 作 display 语义",
    },
  ]
}

///|
/// 行为契约：不得被性能优化破坏的可观测行为（CSharp前端引入计划 §6-B）。
pub(all) struct BehaviorContract {
  id : String
  statement : String
  /// "active"（当前即生效并已有防线）/"reserved"（随批次激活）
  status : String
  batch : String
  /// 防线载体（可执行的判据所在）
  enforced_by : String
} derive(Debug)

///|
/// 行为契约清单（照搬 contracts.rs BEHAVIOR_CONTRACTS，5 条）。
pub fn behavior_contracts() -> Array[BehaviorContract] {
  [
    {
      id: "step_granularity",
      statement: "一步 = 一条字节码指令（含透明的 StepEvent 调试指令）；同一步不被合并",
      status: "active",
      batch: "-",
      enforced_by: "step_payload_schema_v0_1_test::test_step_payload_top_level_fields_frozen（step_index 连续递增）",
    },
    {
      id: "payload_additive_only",
      statement: "StepPayload 字段只增不改语义；新增字段必须可空/有默认值；v0.1 阶段不得携带未发布字段",
      status: "active",
      batch: "-",
      enforced_by: "step_payload_schema_v0_1_test（键集合冻结 + contracts::RESERVED_FIELDS_V0_2 缺省断言）",
    },
    {
      id: "jit_breakpoint_integrity",
      statement: "含断点的循环排除出 JIT trace —— 断点语义不被 trace 优化吞掉",
      status: "active",
      batch: "-",
      enforced_by: "jit_unit_test / e2e 断点用例",
    },
    {
      id: "unwinding_step_granularity",
      statement: "UNWINDING 每弹一帧 / 执行一个 finally 块 = 一个 VM step，**不得合并单步**（展开动画的根基）",
      status: "reserved",
      batch: "CS3b",
      enforced_by: "contracts::check_unwinding_granularity（单测合成序列）+ SharpTutor S4 §5 A2/A5 回放",
    },
    {
      id: "try_excludes_jit",
      statement: "含 TryBegin 的函数排除出 JIT trace 编译（与断点排除同一模式）",
      status: "reserved",
      batch: "CS3a",
      enforced_by: "CS3a 批次 jit 用例（激活时落库）",
    },
  ]
}

///|
/// 展开步样本（"UNWINDING 不得合并单步"判据的输入）。
pub(all) struct UnwindSample {
  step_index : Int
  unwinding : Bool
  unwind_frames_left : Int
} derive(Debug, Eq, Compare)

///| 校验一批步数据是否违反 unwinding_step_granularity 契约。

///|

///| 判据（对相邻两步）：

///| 1. step_index 严格递增；

///| 2. unwind_frames_left >= 0（负数是"展开已结束"的错误编码，空值语义用

///|    null/不动字段表达）；

///| 3. 展开区间内 unwind_frames_left 的下降幅度 <= 1——一次弹多帧 = 合并

///|    单步 = 违反契约。允许为 0：finally 块执行步不弹帧（handler_depth==0

///|    但 unwinding==true），允许回增则为错误（展开方向不可逆）；

///| 4. 进入展开（false -> true）时剩余帧数 >= 1（从栈深 N 递减至 1）；

///| 5. 离开展开（true -> false）时剩余帧数必须归零（异常被吞/捕获后 ==0）。

///|

///|
/// 返回 Err(说明) 即违反契约；空输入与单样本（无相邻对）恒通过。
pub fn check_unwinding_granularity(
  steps : Array[UnwindSample],
) -> Result[Unit, String] {
  let mut prev : UnwindSample? = None
  for step in steps {
    if step.unwind_frames_left < 0 {
      return Err(
        "step \{step.step_index}：unwind_frames_left=\{step.unwind_frames_left} 为负 —— 展开结束应以 0 + unwinding=false 表达",
      )
    }
    match prev {
      Some(p) =>
        if step.step_index <= p.step_index {
          return Err(
            "step_index 未严格递增：\{p.step_index} → \{step.step_index}",
          )
        } else if (!p.unwinding && step.unwinding) &&
          step.unwind_frames_left < 1 {
          return Err(
            "step \{step.step_index}：进入展开态时 unwind_frames_left=\{step.unwind_frames_left} 应 ≥ 1（栈深 N 起算）",
          )
        } else if p.unwinding && step.unwinding {
          let delta = p.unwind_frames_left - step.unwind_frames_left
          if delta > 1 {
            return Err(
              "step \{p.step_index} → \{step.step_index}：一次展开 \{delta} 帧（\{p.unwind_frames_left} → \{step.unwind_frames_left}）—— UNWINDING 不得合并单步，每帧必须独立成步",
            )
          }
          if delta < 0 {
            return Err(
              "step \{p.step_index} → \{step.step_index}：unwind_frames_left 回增（\{p.unwind_frames_left} → \{step.unwind_frames_left}）—— 展开方向不可逆",
            )
          }
        } else if p.unwinding && !step.unwinding && step.unwind_frames_left != 0 {
          return Err(
            "step \{step.step_index}：离开展开态但 unwind_frames_left=\{step.unwind_frames_left} ≠ 0",
          )
        }
      None => ()
    }
    prev = Some(step)
  }
  Ok(())
}

///| 契约表 JSON（capabilities.behavior_contracts / 文档自检共用）。

///| 显式 emitter（B 级锚纪律：禁 ToJson 派生）。**键序 = serde_json 字典序**

///| （Rust 侧 serde_json::json! 宏先落 Value::Object，native/Cargo.toml 未启

///| preserve_order ⇒ Map = BTreeMap，to_string 按键字典序输出；条目内 struct

///| 字段同样被重排）——顶层 behavior_contracts/frozen_at/reserved_fields_v0_2/

///| schema/v0_2_activation_checklist/v0_2_field_ledger，BehaviorContract 条目

///| batch/enforced_by/id/statement/status，SchemaFieldPlan 条目

///| batch/field/kind/note/status。紧凑无空格。与 Rust 真值的**逐字节对拍锚**

///| 在 schema_wbtest（探针 tmp/review_20260927/json_order，serde_json ~1.0.149

///| 同 native，2026-09-27 用户审阅 P2-1 实测锁定）。值域全部来自本包常量表

///| （受控词表，无引号/反斜杠/控制字符，直拼安全；任意值 emitter 随 gateway

///|
/// serve 批）。
pub fn contracts_json() -> String {
  let buf = StringBuilder()
  buf.write_string("{\"behavior_contracts\":[")
  for i, c in behavior_contracts() {
    if i > 0 {
      buf.write_char(',')
    }
    buf.write_string(
      "{\"batch\":\"\{c.batch}\",\"enforced_by\":\"\{c.enforced_by}\",\"id\":\"\{c.id}\",\"statement\":\"\{c.statement}\",\"status\":\"\{c.status}\"}",
    )
  }
  buf.write_string("],\"frozen_at\":\"")
  buf.write_string(SCHEMA_V0_1_FROZEN_AT)
  buf.write_string("\",\"reserved_fields_v0_2\":[")
  write_json_string_array(buf, reserved_fields_v0_2())
  buf.write_string("],\"schema\":\"")
  buf.write_string(SCHEMA_VERSION)
  buf.write_string("\",\"v0_2_activation_checklist\":[")
  write_json_string_array(buf, v0_2_activation_checklist())
  buf.write_string("],\"v0_2_field_ledger\":[")
  for i, plan in v0_2_field_ledger() {
    if i > 0 {
      buf.write_char(',')
    }
    buf.write_string(
      "{\"batch\":\"\{plan.batch}\",\"field\":\"\{plan.field}\",\"kind\":\"\{plan.kind}\",\"note\":\"\{plan.note}\",\"status\":\"\{plan.status}\"}",
    )
  }
  buf.write_string("]}")
  buf.to_string()
}

///|
/// 紧凑 JSON 字符串数组 emitter（内部共用）。
fn write_json_string_array(buf : StringBuilder, items : Array[String]) -> Unit {
  for i, s in items {
    if i > 0 {
      buf.write_char(',')
    }
    buf.write_string("\"\{s}\"")
  }
}
