///|
/// #130 批① 装载门（2026-10-17）：三表可覆盖化的引擎侧半边。
///
/// 形态（#130 七轮收敛裁定 + #120 补充节切分线）：
/// - `texts_json()`——三表现值 → 规范 JSON（键 str_cmp 字典序、字段序
///   固定、compact 无空白）——未来语言包 js 模块（foreign_library
///   --target js）的导出载体，浏览器懒加载注入的内容形态。
/// - `install_texts(payload)`——解析 + 三段校验（schema 严格 / suggestions
///   值域闸 / trap 占位符双向契约）全过后**原子换装**：三 Map 原地
///   clear+refill（`pub let` 绑定对象同一性保持——steps/typeck/
///   trace_analyzer 全部消费面零改动即见覆盖结果）。
/// - 烘焙启动态不变：本批 native/CLI 仍走 `*_gen.mbt` 烘焙表；install
///   是覆盖通道（#130「装载门」），lean 双形态拆包（数据包分离 +
///   DCE）随后续批。
///
/// 值域闸（#120 补充节闸 3 形态）：known_suggestion_keys 是引擎侧
/// **结构事实**（43 族算法 id 名单——非文案，按切分线留引擎），lean
/// 形态下它仍约束装载键域；`install_wbtest` 对账此名单 ↔ 烘焙表防漂移。

///|
/// suggestions 值域名单（43 族算法 id——map.mbt 43 臂穷尽 match 的
/// 键集镜像；增删族须三处同步：真源 suggestions.md / map.mbt match /
/// 此名单，install_wbtest 对账锚兜底）。
pub let known_suggestion_keys : Array[String] = [
  "avl_tree", "bfs", "binary_search", "bst_delete", "bst_insert", "bst_search", "bst_validate",
  "bubble_sort", "circular_linked_list", "circular_queue", "counting_sort", "dijkstra",
  "dp", "dfs", "floyd", "gcd", "hash_table", "hanoi", "heap_sort", "huffman_tree",
  "insertion_sort", "is_prime", "josephus", "kruskal_mst", "level_order", "linked_list_append",
  "linked_list_delete", "linked_queue", "linked_stack", "merge_sort", "prim_mst",
  "quick_sort", "radix_sort", "selection_sort", "seq_list", "shell_sort", "static_linked_list",
  "string_match_bf", "string_match_kmp", "string_reverse", "threaded_binary_tree",
  "topological_sort", "union_find",
]

///|
/// 装载失败（fail loud 三族：解析失败 / 形态不符 / 值域或契约不符）。
/// 拒绝即整体不装（禁半装——校验全过才动表）。
pub suberror InstallTextsError {
  SchemaFail(message~ : String)
}

///|
/// Map 键字典序排序（String 内置 compare 非字典序——陷阱 #29，
/// @util.str_cmp 单源；发射确定性依赖此序）。
fn[V] sorted_map_keys(m : Map[String, V]) -> Array[String] {
  let keys : Array[String] = []
  for k, _v in m {
    keys.push(k)
  }
  keys.sort_by(@util.str_cmp)
  keys
}

///|
/// 三表规范 JSON 发射（字段序固定：顶层 suggestions/builtin_notes/
/// trap_messages；builtin 条目 count_note→param_notes；trap 条目
/// placeholders→template；全键字典序；compact 无空白——install_texts
/// 的往返幂等锚锁此形态）。
pub fn texts_json() -> String {
  let buf = StringBuilder()
  buf.write_string("{\"suggestions\":{")
  let sk = sorted_map_keys(suggestion_map)
  for i, k in sk {
    if i > 0 {
      buf.write_string(",")
    }
    buf.write_string("\"")
    @util.json_escape_into(k, buf)
    buf.write_string("\":\"")
    @util.json_escape_into(suggestion_map.get(k).unwrap_or(""), buf)
    buf.write_string("\"")
  }
  buf.write_string("},\"builtin_notes\":{")
  let bk = sorted_map_keys(builtin_notes)
  for i, k in bk {
    if i > 0 {
      buf.write_string(",")
    }
    buf.write_string("\"")
    @util.json_escape_into(k, buf)
    buf.write_string("\":{\"count_note\":\"")
    let note = builtin_notes
      .get(k)
      .unwrap_or({ count_note: "", param_notes: [], })
    @util.json_escape_into(note.count_note, buf)
    buf.write_string("\",\"param_notes\":[")
    for j, p in note.param_notes {
      if j > 0 {
        buf.write_string(",")
      }
      buf.write_string("\"")
      @util.json_escape_into(p, buf)
      buf.write_string("\"")
    }
    buf.write_string("]}")
  }
  buf.write_string("},\"trap_messages\":{")
  let tk = sorted_map_keys(trap_messages)
  for i, k in tk {
    if i > 0 {
      buf.write_string(",")
    }
    buf.write_string("\"")
    @util.json_escape_into(k, buf)
    buf.write_string("\":{\"placeholders\":[")
    let msg = trap_messages
      .get(k)
      .unwrap_or({ template: "", placeholders: [], })
    for j, p in msg.placeholders {
      if j > 0 {
        buf.write_string(",")
      }
      buf.write_string("\"")
      @util.json_escape_into(p, buf)
      buf.write_string("\"")
    }
    buf.write_string("],\"template\":\"")
    @util.json_escape_into(msg.template, buf)
    buf.write_string("\"}")
  }
  buf.write_string("}}")
  buf.to_string()
}

///|
/// 模板占位符名合法性（contract_wbtest 原位收编——装载校验与契约锚
/// 同一判据单源；[A-Za-z_]+[A-Za-z_0-9]*）。
fn is_id_name(view : String) -> Bool {
  let n = view.length()
  if n == 0 {
    return false
  }
  let first = view[0]
  if !((first >= 97 && first <= 122) ||
    (first >= 65 && first <= 90) ||
    first == 95) {
    return false
  }
  for k in 1..<n {
    let c = view[k]
    let idc = (c >= 97 && c <= 122) ||
      (c >= 65 && c <= 90) ||
      (c >= 48 && c <= 57) ||
      c == 95
    if !idc {
      return false
    }
  }
  true
}

///|
/// 模板正文实际 `{name}` 占位符集（集合语义——同名多次出现计一次；
/// 非法名/未闭合段不计）。contract_wbtest 与 install 校验共用单源。
fn extract_template_placeholders(t : String) -> Array[String] {
  let actual : Array[String] = []
  let n = t.length()
  let mut i = 0
  while i < n {
    if t[i] == 123 {
      let mut j = i + 1
      let mut closed = false
      while j < n {
        if t[j] == 125 {
          closed = true
          break
        }
        j = j + 1
      }
      if closed && j > i + 1 && is_id_name(t[i + 1:j].to_owned()) {
        let nm = t[i + 1:j].to_owned()
        // 同名占位符多次出现（如 bounds_array 的 {name}×2）按集合语义计
        if !actual.contains(nm) {
          actual.push(nm)
        }
        i = j + 1
      } else {
        i = i + 1
      }
    } else {
      i = i + 1
    }
  }
  actual
}

///|
/// 占位符双向契约（声明集 == 模板实际集）——单条判true/false；
/// 拒绝理由拼装留给调用方（契约锚收集全量坏例、装载校验首错即拒）。
fn placeholders_contract_ok(
  template : String,
  declared : Array[String],
) -> Bool {
  let actual = extract_template_placeholders(template)
  if actual.length() != declared.length() {
    return false
  }
  for p in declared {
    if !actual.contains(p) {
      return false
    }
  }
  true
}

///|
/// 装载门：payload = texts_json 同 schema 的 JSON——顶层恰三键
/// （suggestions/builtin_notes/trap_messages），校验全过原子换装三表。
/// 空对象合法（三键皆可空——lean/空文案诚实暴露形态的装载通道）；
/// 未知 suggestion 键 / 形态不符 / 占位符契约不符一律 raise 整体不装。
pub fn install_texts(payload : String) -> Unit raise InstallTextsError {
  let top = @util.json_parse(payload) catch {
    _ => raise InstallTextsError::SchemaFail(message="载荷不是合法 JSON")
  }
  let top_map = match top {
    Object(m) => m
    _ => raise InstallTextsError::SchemaFail(message="顶层须为 JSON 对象")
  }
  // schema 严格：两必到键 + trap 段可选（批③a 语义：trap 模板留引擎
  // 烘焙——#120 切分线；段缺席 = 不碰引擎烘焙 trap，在场 = 校验后整体
  // 替换。host 侧 trap 消费是 .unwrap() 语义，缺席段防语言包误清空）
  if top_map.length() != 2 && top_map.length() != 3 {
    raise InstallTextsError::SchemaFail(
      message="顶层须含 suggestions/builtin_notes（trap_messages 可选），实得 \{top_map.length()} 键",
    )
  }
  let sugg_j = get_object_field(top_map, "suggestions")
  let note_j = get_object_field(top_map, "builtin_notes")
  let trap_j : Map[String, Json]? = match top_map.get("trap_messages") {
    Some(Object(m)) => Some(m)
    Some(_) =>
      raise InstallTextsError::SchemaFail(
        message="顶层 'trap_messages' 须为对象",
      )
    None => None
  }
  // —— 收集与校验（未动表）——
  let new_suggestions : Map[String, String] = Map([])
  for k, v in sugg_j {
    match v {
      String(s) => {
        if !known_suggestion_keys.contains(k) {
          raise InstallTextsError::SchemaFail(
            message="suggestions 未知键 '\{k}'（值域 = KNOWN_SUGGESTION_KEYS 43 族）",
          )
        }
        new_suggestions.set(k, s)
      }
      _ =>
        raise InstallTextsError::SchemaFail(
          message="suggestions['\{k}'] 须为字符串",
        )
    }
  }
  let new_notes : Map[String, BuiltinNote] = Map([])
  for k, v in note_j {
    let note = parse_builtin_note(k, v)
    new_notes.set(k, note)
  }
  let new_traps : Map[String, TrapMessage] = Map([])
  match trap_j {
    Some(tj) =>
      for k, v in tj {
        let msg = parse_trap_message(k, v)
        new_traps.set(k, msg)
      }
    None => ()
  }
  // —— 原子换装（三 Map 原地 clear+refill：pub let 对象同一性保持，
  //    消费面零改动即见覆盖）——
  suggestion_map.clear()
  for k, v in new_suggestions {
    suggestion_map.set(k, v)
  }
  builtin_notes.clear()
  for k, v in new_notes {
    builtin_notes.set(k, v)
  }
  match trap_j {
    Some(_) => {
      trap_messages.clear()
      for k, v in new_traps {
        trap_messages.set(k, v)
      }
    }
    None => ()
  }
}

///|
/// 顶层字段取对象形态（缺键/非对象即拒）。
fn get_object_field(
  top : Map[String, Json],
  name : String,
) -> Map[String, Json] raise InstallTextsError {
  match top.get(name) {
    Some(Object(m)) => m
    Some(_) =>
      raise InstallTextsError::SchemaFail(
        message="顶层 '\{name}' 须为对象",
      )
    None =>
      raise InstallTextsError::SchemaFail(message="顶层缺 '\{name}' 键")
  }
}

///|
/// builtin_notes 条目解析：{count_note: string, param_notes: [string]}
///（字段恰两个；param_notes 元素须字符串——与生成物 BuiltinNote 同构）。
fn parse_builtin_note(
  key : String,
  v : Json,
) -> BuiltinNote raise InstallTextsError {
  let m = match v {
    Object(o) => o
    _ =>
      raise InstallTextsError::SchemaFail(
        message="builtin_notes['\{key}'] 须为对象",
      )
  }
  if m.length() != 2 {
    raise InstallTextsError::SchemaFail(
      message="builtin_notes['\{key}'] 须恰含 count_note/param_notes 两字段",
    )
  }
  let count_note = match m.get("count_note") {
    Some(String(s)) => s
    Some(_) =>
      raise InstallTextsError::SchemaFail(
        message="builtin_notes['\{key}'].count_note 须为字符串",
      )
    None =>
      raise InstallTextsError::SchemaFail(
        message="builtin_notes['\{key}'] 缺 count_note",
      )
  }
  let param_notes : Array[String] = []
  match m.get("param_notes") {
    Some(Array(items)) =>
      for item in items {
        match item {
          String(s) => param_notes.push(s)
          _ =>
            raise InstallTextsError::SchemaFail(
              message="builtin_notes['\{key}'].param_notes 元素须为字符串",
            )
        }
      }
    Some(_) =>
      raise InstallTextsError::SchemaFail(
        message="builtin_notes['\{key}'].param_notes 须为数组",
      )
    None =>
      raise InstallTextsError::SchemaFail(
        message="builtin_notes['\{key}'] 缺 param_notes",
      )
  }
  { count_note, param_notes, }
}

///|
/// trap_messages 条目解析：{template: string, placeholders: [string]} +
/// 占位符双向契约（contract_wbtest 同判据单源——声明集 == 模板实际集）。
fn parse_trap_message(
  key : String,
  v : Json,
) -> TrapMessage raise InstallTextsError {
  let m = match v {
    Object(o) => o
    _ =>
      raise InstallTextsError::SchemaFail(
        message="trap_messages['\{key}'] 须为对象",
      )
  }
  if m.length() != 2 {
    raise InstallTextsError::SchemaFail(
      message="trap_messages['\{key}'] 须恰含 template/placeholders 两字段",
    )
  }
  let template = match m.get("template") {
    Some(String(s)) => s
    Some(_) =>
      raise InstallTextsError::SchemaFail(
        message="trap_messages['\{key}'].template 须为字符串",
      )
    None =>
      raise InstallTextsError::SchemaFail(
        message="trap_messages['\{key}'] 缺 template",
      )
  }
  let placeholders : Array[String] = []
  match m.get("placeholders") {
    Some(Array(items)) =>
      for item in items {
        match item {
          String(s) => placeholders.push(s)
          _ =>
            raise InstallTextsError::SchemaFail(
              message="trap_messages['\{key}'].placeholders 元素须为字符串",
            )
        }
      }
    Some(_) =>
      raise InstallTextsError::SchemaFail(
        message="trap_messages['\{key}'].placeholders 须为数组",
      )
    None =>
      raise InstallTextsError::SchemaFail(
        message="trap_messages['\{key}'] 缺 placeholders",
      )
  }
  if !placeholders_contract_ok(template, placeholders) {
    raise InstallTextsError::SchemaFail(
      message="trap_messages['\{key}'] 占位符声明集与模板实际集不符",
    )
  }
  { template, placeholders, }
}
