// 工具表（design.md v2 §3/§4 单源）：12 条动词化工具——L0 永驻 5（animate /
// diagnose / capabilities / sessions / session_open）+ L1 会话解锁 7
// （frames_summary / frames_query / annotations / run_to / step_next / render /
// session_close）。**勘误登记**：design.md 自计「11 工具 / L0 4」——但
// session_open 是解锁触发器，无会话时必须可见才能被调用（§3.3 的
// available_now 4 项 + unlocked_by session_open 即此拆分），故 L0 可见集 5、
// 总计 12；§3.3 的 unlocks 列表（7 项）即 L1 集，逐字对齐。
// 命名契约：DeepSeek function-name 限 [A-Za-z0-9_-]，一律下划线。
// readOnlyHint（MCP ToolAnnotations）：只读探查工具标 true——DSH
// tools/pre-execute allow/deny/ask 门据此放行；frames_*/annotations 的惰性
// 采集是内部实现细节（从 agent 视角幂等），按设计 §5.4 计只读。

///|
priv struct ToolDef {
  name : String
  level : Int32
  read_only : Bool
  description : String
  input_schema : Json
}

///|
fn p_str(desc : String) -> Json {
  ob().s("type", "string").s("description", desc).done()
}

///|
fn p_int(desc : String) -> Json {
  ob().s("type", "integer").s("description", desc).done()
}

///|
fn p_bool(desc : String) -> Json {
  ob().s("type", "boolean").s("description", desc).done()
}

///|
fn p_enum(desc : String, vals : Array[String]) -> Json {
  ob().s("type", "string").j("enum", jstrs(vals)).s("description", desc).done()
}

///|
fn p_str_arr(desc : String) -> Json {
  ob()
  .s("type", "array")
  .j("items", ob().s("type", "string").done())
  .s("description", desc)
  .done()
}

///|
fn p_obj(desc : String, props : Array[(String, Json)]) -> Json {
  let pm : Map[String, Json] = Map([])
  for p in props {
    pm.set(p.0, p.1)
  }
  ob()
  .s("type", "object")
  .j("properties", Json::object(pm))
  .s("description", desc)
  .done()
}

///|
fn schema(props : Array[(String, Json)], required : Array[String]) -> Json {
  let pm : Map[String, Json] = Map([])
  for p in props {
    pm.set(p.0, p.1)
  }
  let o = ob().s("type", "object").j("properties", Json::object(pm))
  if required.length() > 0 {
    ignore(o.sa("required", required))
  }
  o.done()
}

///|
/// 会话寻址参数（L1 共用——缺省 = 最近使用的会话）。
fn p_session() -> (String, Json) {
  (
    "session_id",
    p_str("会话 id（session_open 返回；缺省 = 最近使用的会话）"),
  )
}

///|
/// 配色主题枚举值：auto/light/dark 语义别名 + StylePack 全族 id（单源 @style）。
fn theme_values() -> Array[String] {
  let out : Array[String] = ["auto", "light", "dark"]
  for p in @style.style_packs() {
    out.push(p.id)
  }
  out
}

///|
/// render/animate 共用的渲染选项族。
fn render_props() -> Array[(String, Json)] {
  [
    (
      "mode",
      p_enum(
        "static=预计算帧嵌入（默认，离线可播）；interactive=页内 wasm 引擎（可单步/断点，~1.4MB）",
        ["static", "interactive"],
      ),
    ),
    ("budget", p_int("关键帧预算（默认 400，16..4000）")),
    (
      "focus",
      p_str_arr("聚焦数组名（默认自动：按出现频次取前 4）"),
    ),
    (
      "viz",
      p_str(
        "视图声明（多行；每行 `series <名…> -> <投影器> [k=v …]`，与课源 vitri-viz 同形；缺省 = 全按 cells 索引格）",
      ),
    ),
    (
      "theme",
      p_enum(
        "配色主题（默认 auto；light/dark 为 ice/soft 简写，亦可直接给 StylePack 主题 id）",
        theme_values(),
      ),
    ),
    (
      "audio_description",
      p_bool("无障碍朗读字幕开关（默认 false）"),
    ),
    (
      "preview_png",
      p_bool(
        "生成 PNG 预览（static 模式，默认 true；需本机 Edge/Chrome）",
      ),
    ),
    ("title", p_str("页面标题（默认算法名）")),
    ("out_dir", p_str("产物目录（默认 <cwd>/vitro-out）")),
  ]
}

///|
/// 12 工具全表（顺序 = tools/list 发射序）。
fn tool_table() -> Array[ToolDef] {
  let anim_props = render_props()
  anim_props.insert(
    0,
    ("source", p_str("C 源码字符串（必填，≤64KB，单文件）")),
  )
  let render_p = render_props()
  render_p.insert(0, p_session())
  render_p.push(("from", p_int("渲染区间起始帧下标（缺省 0）")))
  render_p.push(
    ("to", p_int("渲染区间结束帧下标（不含；缺省全部）")),
  )
  [
    {
      name: "animate",
      level: 0,
      read_only: false,
      description: "一次性出动画（编排糖 = 临时会话 + 全量采集 + render 预设）：C 源码 → 自包含可播放 HTML（数组格高亮/交换指示、当前行、变量表、调用栈、时间轴、算法语义字幕）。编译有错时产诊断卡片动画。返回 html_path——在 DSH 里再用 present 工具交付。需要教学引导/质量调优/批量编排请改用 session_open 走会话工具。",
      input_schema: schema(anim_props, ["source"]),
    },
    {
      name: "diagnose",
      level: 0,
      read_only: true,
      description: "纯诊断（无会话、无产物）：编译错误/警告全集（code/行列/fix_suggestion）+ 算法识别。agent 先探后画。",
      input_schema: schema(
        [("source", p_str("C 源码字符串（必填）"))],
        ["source"],
      ),
    },
    {
      name: "capabilities",
      level: 0,
      read_only: true,
      description: "本 server 支持面自述：引擎/协议版本、工具分层与渐进披露引导（当前可用/解锁方式/解锁后出现什么）、限制、DSH 消费建议。",
      input_schema: schema([], []),
    },
    {
      name: "sessions",
      level: 0,
      read_only: true,
      description: "列出活跃会话：session_id / 源码首行 / 已采帧数 / 停止原因 / 剩余寿命（秒）。",
      input_schema: schema([], []),
    },
    {
      name: "session_open",
      level: 0,
      read_only: false,
      description: "打开有状态会话（只编译不运行）：返回 session_id、编译诊断、算法识别、程序概览（函数/符号/行数）。首个会话入池即解锁 L1 工具（frames_summary / frames_query / annotations / run_to / step_next / render / session_close——编译失败会话同样解锁：render 可出诊断卡；design §1.2「成功后解锁」按此收窄修正），并发 tools/list_changed 通知——请重拉 tools/list。",
      input_schema: schema(
        [
          (
            "source",
            p_str(
              "C 源码字符串（与 files 二选一——都给报错；≤64KB）",
            ),
          ),
          (
            "files",
            ob()
            .s("type", "array")
            .j(
              "items",
              p_obj("虚拟工程文件", [
                ("filename", p_str("文件名（如 util.c / util.h）")),
                ("source", p_str("文件内容")),
              ]),
            )
            .s(
              "description", "多文件虚拟工程（与 source 互斥：给 files 则 source 可省；集合内文件可互相 quote-include，透传引擎 compile{files}）",
            )
            .done(),
          ),
          ("argv", p_str_arr("程序参数（argv[1..]，run 时生效）")),
          (
            "config_hint",
            p_enum(
              "引擎预算档：default=语法教学缺省 / algo=算法作业大搜索 / tiny=微演示",
              ["default", "algo", "tiny"],
            ),
          ),
          ("title", p_str("会话标题（render 默认页面标题）")),
        ],
        // PR #457 审阅 v2 P2-4：required 不含 source——「给 files 则 source
        // 可省」与 required:["source"] 自相矛盾（严格校验客户端拒纯 files
        // 调用）；二选一由 arg_source 校验兜底（都缺报错、都给报错）
        [],
      ),
    },
    {
      name: "frames_summary",
      level: 1,
      read_only: true,
      description: "帧结构索引（下钻入口，只读；首次调用触发惰性全量采集）：总帧数、字幕频次、可视事件计数（swap/compare）、交换对序列、数组及其变更次数、热点行、停止原因。",
      input_schema: schema([p_session()], []),
    },
    {
      name: "frames_query",
      level: 1,
      read_only: true,
      description: "分页拉帧（只读）。默认紧凑投影 {i:步号,l:行,f:函数,s:字幕}，limit≤50/页；fields 显式要求才给 r=数组快照 / v=变量 / c=调用栈 / e=可视事件 / a=算法步 / h=根因提示。filter 支持 label_prefix / line / func / has_vis_event。",
      input_schema: schema(
        [
          p_session(),
          ("from", p_int("起始帧下标（缺省 0）")),
          ("to", p_int("结束帧下标（不含；缺省 from+limit）")),
          ("limit", p_int("每页上限（缺省 50，最大 50）")),
          (
            "fields",
            p_str_arr(
              "额外字段：r / v / c / e / a / h（缺省只给 i,l,f,s）",
            ),
          ),
          (
            "filter",
            p_obj("帧过滤（先过滤后分页）", [
              ("label_prefix", p_str("字幕前缀，如「交换」")),
              ("line", p_int("源码行号")),
              ("func", p_str("函数名")),
              (
                "has_vis_event",
                p_bool(
                  "true=只要含可视事件的帧；false/缺省=不过滤（非「只要不含」）",
                ),
              ),
            ]),
          ),
        ],
        [],
      ),
    },
    {
      name: "annotations",
      level: 1,
      read_only: true,
      description: "语义事件流（只读）：交换/比较/调用/返回事件的时序列表（帧号+行+细节）——「哪些帧值得看」的索引，供挑区间再 render。kind 可过滤。",
      input_schema: schema(
        [
          p_session(),
          (
            "kind",
            p_enum("事件类型过滤（缺省全部）", [
              "swap", "compare", "call", "return",
            ]),
          ),
        ],
        [],
      ),
    },
    {
      name: "run_to",
      level: 1,
      read_only: false,
      description: "推进式采集（导游模式）：推进到断点行 / 首个指定事件 / 最多 N 帧后暂停，返回 advanced / paused_at / stopped。已终局则提示用 frames_query 回看。三参数任选其一；都缺省 = 推进到终局。",
      input_schema: schema(
        [
          p_session(),
          ("breakpoint_line", p_int("推进到该源码行暂停")),
          (
            "stop_event",
            p_enum("推进到首个此类可视事件暂停", [
              "swap", "compare", "any",
            ]),
          ),
          ("max_frames", p_int("最多推进的原始帧数（1..20000）")),
        ],
        [],
      ),
    },
    {
      name: "step_next",
      level: 1,
      read_only: false,
      description: "推进 n 个关键帧（细粒度档，缺省 1，最大 100）：返回新到的关键帧（紧凑投影）与停止原因。",
      input_schema: schema(
        [p_session(), ("n", p_int("关键帧个数（缺省 1）"))],
        [],
      ),
    },
    {
      name: "render",
      level: 1,
      read_only: false,
      description: "渲染会话缓冲的帧为自包含 HTML（与执行分离，不重跑引擎；可区间 from/to）。首次调用触发惰性全量采集。返回同 animate 的产物字段。",
      input_schema: schema(render_p, []),
    },
    {
      name: "session_close",
      level: 1,
      read_only: false,
      description: "关闭会话（缺省关最近使用的）。末会话关闭后 L1 工具收回并发 tools/list_changed。",
      input_schema: schema([p_session()], []),
    },
  ]
}

///|
/// 按披露态过滤的 tools/list 发射。
fn tools_list_json(l1_visible : Bool) -> Json {
  let arr : Array[Json] = []
  for t in tool_table() {
    if t.level == 0 || l1_visible {
      arr.push(
        ob()
        .s("name", t.name)
        .s("description", t.description)
        .j("inputSchema", t.input_schema)
        .j("annotations", ob().b("readOnlyHint", t.read_only).done())
        .done(),
      )
    }
  }
  ob().a("tools", arr).done()
}

///|
fn find_tool(name : String) -> ToolDef? {
  for t in tool_table() {
    if t.name == name {
      return Some(t)
    }
  }
  None
}

///|
fn tool_names(level : Int32) -> Array[String] {
  let out : Array[String] = []
  for t in tool_table() {
    if t.level == level {
      out.push(t.name)
    }
  }
  out
}
