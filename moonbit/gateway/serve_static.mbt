// S7 批三号三段：serve 静态元数据族——capabilities（E2 机器可读能力
// 清单）/ error_catalog（B1）/ semantic_labels（B2-3）/ contracts（B2-1/2）。
// 照搬源：native/src/session_api.rs 的 capabilities/error_catalog_json/
// semantic_labels/contracts + vitro_cli.rs 对应分发臂。
//
// 登记分叉（capabilities 节选）：
// ① `abi_version`/`engine_version` 字段不出——MoonBit 侧无 capi 层
//    （.mbti 取代 ABI 版本化成对外义务载体，总计划 §4；构建期 git
//    短哈希通道不存在），版本协商走 mooncakes 版本号；
// ② `languages.cpp` 节不出——F-2 终局已裁 C++（cpp 子集规范文档随
//    Rust 冻结区退役）。
//
// error_catalog/semantic_labels/contracts 三方法走 json_parse(emitter
// String) 通道：emitter 是已对齐 Rust serde 的单源（批一号双显式
// emitter + diag gen_diag 三件套），parse 后对象内嵌 serve 帧——字段
// 序 = emitter 序 = Rust serde 序（对拍一致的前提不变）。

///|
/// capabilities 方法帧（E2：「版本宏当能力探测」三层配套之一）。
fn serve_capabilities_frame(id : Json) -> (String, Bool) {
  // schema 轨道（B2）
  let reserved : Array[Json] = []
  for f in @protocol.reserved_fields_v0_2() {
    reserved.push(Json::string(f))
  }
  let ledger : Array[Json] = []
  for p in @protocol.v0_2_field_ledger() {
    let lm : Map[String, Json] = Map([])
    lm.set("field", Json::string(p.field))
    lm.set("kind", Json::string(p.kind))
    lm.set("status", Json::string(p.status))
    lm.set("batch", Json::string(p.batch))
    lm.set("note", Json::string(p.note))
    ledger.push(Json::object(lm))
  }
  let schema : Map[String, Json] = Map([])
  schema.set("version", Json::string(@protocol.SCHEMA_VERSION))
  schema.set("frozen_at", Json::string(@protocol.SCHEMA_V0_1_FROZEN_AT))
  schema.set("reserved_fields_v0_2", Json::array(reserved))
  schema.set("v0_2_field_ledger", Json::array(ledger))
  // 行为契约（B2-2）
  let contracts : Array[Json] = []
  for c in @protocol.behavior_contracts() {
    let cm : Map[String, Json] = Map([])
    cm.set("id", Json::string(c.id))
    cm.set("statement", Json::string(c.statement))
    cm.set("status", Json::string(c.status))
    cm.set("batch", Json::string(c.batch))
    cm.set("enforced_by", Json::string(c.enforced_by))
    contracts.push(Json::object(cm))
  }
  // 预处理器能力清单（S2 lexer 与 Rust 预处理器差分对齐的描述面照搬）
  let preproc : Map[String, Json] = Map([])
  preproc.set("object_macros", Json::boolean(true))
  preproc.set("function_macros", Json::boolean(true))
  preproc.set("stringize", Json::boolean(true))
  preproc.set("token_paste", Json::boolean(true))
  preproc.set("paste_result_must_be_single_token", Json::boolean(true))
  let conditionals : Array[Json] = []
  for c in ["#if", "#ifdef", "#ifndef", "#elif", "#else", "#endif"] {
    conditionals.push(Json::string(c))
  }
  preproc.set("conditionals", Json::array(conditionals))
  preproc.set("defined", Json::boolean(true))
  preproc.set("has_include", Json::boolean(true))
  preproc.set("include_once", Json::boolean(true))
  preproc.set("include_cycle_detection", Json::boolean(true))
  preproc.set("expand_depth_fuse", Json::number(64))
  let teaching : Array[Json] = []
  for
    t in [
      "macro_shadowing_warning", "macro_arg_side_effect_warning", "expansion_trace",
      "branch_reason",
    ] {
    teaching.push(Json::string(t))
  }
  preproc.set("teaching_layer", Json::array(teaching))
  let dropped : Array[Json] = []
  for
    d in [
      "自引用宏 trick（展开栈查重直接停止）", "## 动态拼标识符的元编程（结果必须为单个合法 token）",
      "X-macro 高级用法", "宏拼接 include 路径",
    ] {
    dropped.push(Json::string(d))
  }
  preproc.set("dropped", Json::array(dropped))
  let macros : Map[String, Json] = Map([])
  macros.set("__STDC_VERSION__", Json::string("202311L"))
  macros.set("__VITRO_SUBSET__", Json::string("1"))
  let c_lang : Map[String, Json] = Map([])
  c_lang.set("anchor", Json::string("ISO C23 (ISO/IEC 9899:2024) 教学子集"))
  c_lang.set("stdc_version_macro_nominal", Json::string("202311L"))
  c_lang.set("spec", Json::string("C-语言子集/C语言子集规范.md"))
  c_lang.set("predefined_macros", Json::object(macros))
  c_lang.set("preprocessor", Json::object(preproc))
  let languages : Map[String, Json] = Map([])
  languages.set("c", Json::object(c_lang))
  // 内存模型（1MB 白箱布局常量单源 @bytecode）
  let memory_model : Map[String, Json] = Map([])
  memory_model.set("mem_size", @bytecode.MEM_SIZE.to_json())
  memory_model.set("null_trap_size", @bytecode.NULL_TRAP_SIZE.to_json())
  memory_model.set("global_start", @bytecode.GLOBAL_START.to_json())
  memory_model.set(
    "global_region_limit",
    @bytecode.GLOBAL_REGION_LIMIT.to_json(),
  )
  memory_model.set("heap_start_default", @bytecode.HEAP_START.to_json())
  memory_model.set(
    "heap_start",
    Json::string("动态：max(HEAP_START, align4(global_data_end))"),
  )
  let m : Map[String, Json] = Map([])
  m.set("engine", Json::string("vitro"))
  m.set("schema", Json::object(schema))
  m.set("behavior_contracts", Json::array(contracts))
  m.set(
    "semantic_label_kinds",
    @protocol.semantic_label_vocabulary().length().to_json(),
  )
  m.set("languages", Json::object(languages))
  m.set("memory_model", Json::object(memory_model))
  (serve_ok(id, Json::object(m)).stringify(), false)
}

///|
/// error_catalog 方法帧（B1：错误码表机器可读导出——gen_diag 三件套
/// 的 catalog 出口 parse 通道）。
fn serve_error_catalog_frame(id : Json) -> (String, Bool) {
  let parsed = json_parse(@diag.export_catalog_json()) catch {
    _ =>
      return (
        serve_err(id, "internal", "error_catalog 导出解析失败").stringify(),
        false,
      )
  }
  (serve_ok(id, parsed).stringify(), false)
}

///|
/// semantic_labels 方法帧（B2-3：受控词汇表——protocol vocabulary emitter
/// 的 parse 通道）。
fn serve_semantic_labels_frame(id : Json) -> (String, Bool) {
  let parsed = json_parse(@protocol.vocabulary_json()) catch {
    _ =>
      return (
        serve_err(id, "internal", "semantic_labels 导出解析失败").stringify(),
        false,
      )
  }
  (serve_ok(id, parsed).stringify(), false)
}

///|
/// contracts 方法帧（B2-1/2：schema 轨道 + 行为契约——protocol contracts
/// emitter 的 parse 通道）。
fn serve_contracts_frame(id : Json) -> (String, Bool) {
  let parsed = json_parse(@protocol.contracts_json()) catch {
    _ =>
      return (
        serve_err(id, "internal", "contracts 导出解析失败").stringify(),
        false,
      )
  }
  (serve_ok(id, parsed).stringify(), false)
}
