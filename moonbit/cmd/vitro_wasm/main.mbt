// wasm 臂 CLI 胶水（main.js 退役批，2026-10-16）：取代 scripts/vitro_cli/
// main.js（597 行手写 Node 宿主壳——三后端统一进程的对照评估件，双臂
// 分叉 issue #94~#118 销案后使命完成）。承载面逐项迁移：
//
//   - MIN_NODE=22 哨兵（rc=5，#106：3 与步数超限撞号；22 = V8 wasm-gc/
//     js-string builtins 支持下界——#132 降版批实测 node 24.22 全通，
//     #126 修后 25 的硬依赖已不存在）+ backend 标注
//     stderr 行（`[vitro] backend=wasm (node <ver>)`——downstream 判臂
//     通道，launcher 降级臂对称发 backend=native）；
//   - wasm 装载：同步 `new WebAssembly.Instance` + "_" 常量显式供给
//     （#126 形态——import 名即常量值；常量清单从无选项裸编译枚举，
//     node>=23 自动供给与显式供给等价）；
//   - 子命令分派与 cmd/vitro_js **整表同构**（P1-② 教训：分派表不同构
//     即 C5 形态）；逻辑全走 cmd/lib/cli（channel 注入）；
//   - quote-include：wasm 产物无 include_reader 导出 → compile{files}
//     多文件通道（main.js collectFiles 同语义的 MoonBit 复刻）；
//   - serve：node readline 流式逐行 invoke（行长无上限——与 cmd/serve
//     的 65535 定长差异系 CLI 手册「已知形态差」在册条目）；shutdown
//     判停 = 响应含 "shutdown":true（gateway 单口语义）。
//
// 墙钟/set_include_reader 在 wasm 形态 no-op（gateway wasm 外壳 F-5 四
// 导出面无此二口——time() 恒 0 系分臂登记形态，main.js 时代同款）。
//
// json 模式差异登记：main.js 事件行带 backend 字段、lib/cli 不带——
// 本壳随 lib/cli（三臂 json 同形；backend 判臂走 stderr 标注行），spec
// §6 的 backend 字段句随批修订。

///|
fn main {
  // MIN_NODE 哨兵（main.js:30 语义照搬——js-string builtins 的 V8 下界）
  if !js_node_ok() {
    js_write_stderr(
      "[vitro] node \{js_node_version()} < 22（js-string builtins 需要）\n",
    )
    js_exit(5)
  }
  js_write_stderr("[vitro] backend=wasm (node \{js_node_version()})\n")
  let g = js_load_gateway()
  // #130 批②（2026-10-17）：语言包启动注入——烘焙内容经 texts.install
  // 协议方法装载进 wasm 引擎（浏览器宿主同一条注入路径；CLI 臂烘焙
  // 语义保持）。今日与产物内烘焙幂等（内容相同零行为差），批③ lean
  // 拆包后本通道承重。失败 stderr 明示不阻断（lean 语义=空文案诚实暴露）
  @content_data.install_baked() // #130 批③a：壳本地烘焙表装载（inject payload 源头）
  ignore(inject_texts_at_startup(g))
  let channel : @cli.EngineChannel = wasm_channel(g)
  let args = js_args()
  if args.length() < 1 {
    @cli.print_usage(true) // #215：无参用法错（rc=4）走 stderr
    js_exit(4)
  }
  let cmd = args[0]
  let rest : Array[String] = []
  for i = 1; i < args.length(); i = i + 1 {
    rest.push(args[i])
  }
  let code = match cmd {
    "run" =>
      @cli.run(rest, wasm_clock, js_read_stdin, js_write_stdout, channel~)
    "compile" => @cli.compile(rest, js_read_stdin, channel~)
    "step" => @cli.step(rest, js_read_stdin, js_write_stdout, channel~)
    "api" => @cli.api(rest, js_read_stdin, channel~)
    "serve" => {
      // NDJSON 流式会话：main 返回后 node 事件循环由 readline 持续
      //（shutdown 判停后自然退——此臂不调 js_exit）
      js_serve_loop(fn(line : String) -> String { (g.invoke)(line) })
      return
    }
    "dump-tokens" | "dump-ast" | "dump-typeck" | "dump-compile" => {
      // #215：rc=4 用法错语境的指引走 stderr（stdout 恒空不变式）
      @cli.usage_err(
        "vitro: '\{cmd}' 走独立 exe（moonbit/_build/native/release/build/cmd/<name>/——防线调用面，暂不收拢；见 issue #37 B1）；一次性脚本化用 'vitro api <method> <params>' 覆盖全部协议方法",
      )
      4
    }
    "help" | "--help" | "-h" => {
      @cli.print_usage(false)
      0
    }
    _ => {
      @cli.usage_err("vitro: 未知命令 '\{cmd}'")
      @cli.print_usage(true)
      4
    }
  }
  js_exit(code)
}

///|
/// 语言包启动注入（#130 批②）：assets 烘焙内容 → texts.install 协议帧
/// → ok 则静默；error 帧 stderr 明示（不阻断——表保持产物内现状）。
fn inject_texts_at_startup(g : JsGateway) -> Bool {
  let params : Map[String, Json] = Map([])
  params.set("payload", Json::string(@content_data.baked_payload_json()))
  let req : Map[String, Json] = Map([])
  req.set("id", Json::number(0.0))
  req.set("method", Json::string("texts.install"))
  req.set("params", Json::object(params))
  let resp = (g.invoke)(Json::object(req).stringify())
  // 「抛错即不可解析」直落 Option（原 `try?` + `match Ok/Err` 形态已随
  // moonc nightly 删 try? 迁移；迁移时曾误留 Ok/Err 分支 → Json? 与
  // Result 构造器类型不匹配，js target 编译红 2 错）
  let parsed : Json? = Some(@util.json_parse(resp)) catch { _ => None }
  match parsed {
    Some(Object(top)) =>
      match top.get("ok") {
        Some(Json::True) => true
        _ => {
          js_write_stderr(
            "[vitro] 语言包注入失败（引擎表保持产物内现状）：\{resp}\n",
          )
          false
        }
      }
    _ => {
      js_write_stderr("[vitro] 语言包注入响应不可解析：\{resp}\n")
      false
    }
  }
}

///|
/// wasm 臂 EngineChannel：invoke/reset = wasm 产物导出；clock/include
/// no-op（F-5 四导出面）；compile_params = files 多文件（collect 复刻）。
fn wasm_channel(g : JsGateway) -> @cli.EngineChannel {
  {
    invoke: fn(line : String) -> String { (g.invoke)(line) },
    invoke_parsed: fn(line : String) -> Json? {
      let resp = (g.invoke)(line)
      let v = @util.json_parse(resp) catch { _ => return None }
      Some(v)
    },
    reset: fn() -> Unit { (g.reset)() },
    set_clock: fn(_c : () -> UInt64) -> Unit { () },
    set_include_reader: fn(_r : (String) -> String?) -> Unit { () },
    compile_params: fn(file : String, src : String) -> String {
      wasm_compile_params(file, src)
    },
  }
}

///|
/// 墙钟恒 0（wasm 形态无 set_clock 导出——time() 分臂登记形态）。
fn wasm_clock() -> UInt64 {
  0UL
}

// ── files 多文件 compile 装配（main.js collectFiles 的 MoonBit 复刻）────

///|
fn wasm_compile_params(file : String, src : String) -> String {
  // stdin 源（`-`）与读失败退单条（filename 保留原值——main.js stdin 形态
  // filename 即 "-"）；主文件条目直接用 lib/cli 预读的 src（免重读）
  if file == "-" {
    return files_json([("-", src)])
  }
  let entries : Array[(String, String)] = []
  let seen : Array[String] = []
  // 登记名 = basename（main.js path.basename 语义——gateway 的 include
  // 查找相对「当前文件目录」，主文件带目录路径会让 include 键错位）
  collect_walk(file, base_name(file), src, entries, seen)
  if entries.is_empty() {
    return files_json([(file, src)])
  }
  files_json(entries)
}

///|
/// 递归收集：p = 磁盘路径（include 相对基准）、name = 登记文件名
///（basename——gateway vfs 键）。读失败跳过（主文件必读成功——lib/cli
/// 已预读非空 src）；seen 防守卫环的合法自引用库。
fn collect_walk(
  p : String,
  name : String,
  src : String,
  entries : Array[(String, String)],
  seen : Array[String],
) -> Unit {
  if seen.contains(name) {
    return
  }
  seen.push(name)
  entries.push((name, src))
  for inc in scan_quote_includes(src) {
    let inc_path = join_dir(dir_of(p), inc)
    let inc_src = @fs.read_file_to_string(inc_path) catch { _ => "" }
    if inc_src != "" {
      // 病 111（#71，2026-10-16）：登记名归一——gateway resolver 对
      // include 键剥 `./` 段后查找，include 原文（`./x.h`）作 vfs 键即
      // 失配 E1021（native 臂经 fs reader 无此问题）
      collect_walk(inc_path, strip_dot_segments(inc), inc_src, entries, seen)
    }
  }
}

///|
/// 剥路径的 `.` 段（"./x.h"→"x.h"、"a/./b.h"→"a/b.h"——gateway resolver
/// 同款归一，键/查找两侧对齐）。
fn strip_dot_segments(p : String) -> String {
  if !p.contains("./") {
    return p
  }
  let parts : Array[String] = []
  for seg in p.split("/") {
    let s : String = seg.to_owned()
    if s != "." && s != "" {
      parts.push(s)
    }
  }
  if parts.is_empty() {
    return p
  }
  let b = StringBuilder()
  for i, seg in parts {
    if i > 0 {
      b.write_string("/")
    }
    b.write_string(seg)
  }
  b.to_string()
}

///|
/// quote-include 扫描（main.js 正则 /^[ \t]*#[ \t]*include[ \t]*"([^"]+)"/
/// 的逐行等价复刻）。
fn scan_quote_includes(src : String) -> Array[String] {
  let out : Array[String] = []
  for line in src.split("\n") {
    let l : String = line.to_owned()
    let cs = l.to_array()
    let mut i = 0
    // 行首空白
    while i < cs.length() && (cs[i] == ' ' || cs[i] == '\t') {
      i += 1
    }
    if i >= cs.length() || cs[i] != '#' {
      continue
    }
    i += 1
    while i < cs.length() && (cs[i] == ' ' || cs[i] == '\t') {
      i += 1
    }
    // include 关键字
    let kw = "include"
    let kc = kw.to_array()
    if i + kc.length() > cs.length() {
      continue
    }
    let mut ok = true
    for j = 0; j < kc.length(); j = j + 1 {
      if cs[i + j] != kc[j] {
        ok = false
        break
      }
    }
    if !ok {
      continue
    }
    i += kc.length()
    while i < cs.length() && (cs[i] == ' ' || cs[i] == '\t') {
      i += 1
    }
    if i >= cs.length() || cs[i] != '"' {
      continue
    }
    i += 1
    let start = i
    while i < cs.length() && cs[i] != '"' {
      i += 1
    }
    if i > start && i < cs.length() {
      out.push(l[start:i].to_owned())
    }
  }
  out
}

///|
/// 目录段（最后 / 或 \ 之前；无分隔符 = "."——cwd 相对）。#373 审阅
/// P2-1（2026-10-29）：唯一分隔符在 0 位 = POSIX 根级文件（"/main.c"）
/// 取 "/"——与 gateway dir_of 同修（否则根级主文件的 include 磁盘
/// 读取按 cwd 相对拼接）。
fn dir_of(p : String) -> String {
  let cs = p.to_array()
  let mut idx = -1
  for i = 0; i < cs.length(); i = i + 1 {
    if cs[i] == '/' || cs[i] == '\\' {
      idx = i
    }
  }
  if idx == 0 {
    "/"
  } else if idx < 0 {
    "."
  } else {
    p[:idx].to_owned()
  }
}

///|
/// 文件名段（最后 / 或 \ 之后；无分隔符 = 原文）。
fn base_name(p : String) -> String {
  let cs = p.to_array()
  let mut idx = -1
  for i = 0; i < cs.length(); i = i + 1 {
    if cs[i] == '/' || cs[i] == '\\' {
      idx = i
    }
  }
  if idx < 0 {
    p
  } else {
    p[idx + 1:].to_owned()
  }
}

///|
/// include 相对路径拼接（posix 形态——node readFileSync 双分隔符兼容）。
fn join_dir(dir : String, name : String) -> String {
  if dir == "." {
    name
  } else {
    "\{dir}/\{name}"
  }
}

///|
fn files_json(entries : Array[(String, String)]) -> String {
  let b = StringBuilder()
  b.write_string("{\"files\":[")
  for i, e in entries {
    if i > 0 {
      b.write_string(",")
    }
    b.write_string(
      "{\"filename\":\"\{@util.json_escape(e.0)}\",\"source\":\"\{@util.json_escape(e.1)}\"}",
    )
  }
  b.write_string("]}")
  b.to_string()
}

// ── extern "js" 绑定（node 宿主）──────────────────────────────────────

///|
/// wasm 产物句柄（invoke/reset = gateway wasm 外壳四导出中的两会话口）。
struct JsGateway {
  invoke : (String) -> String
  reset : () -> Unit
}

///|
extern "js" fn js_node_ok() -> Bool =
  #| function() {
  #|   return Number(process.versions.node.split(".")[0]) >= 22;
  #| }

///|
extern "js" fn js_node_version() -> String =
  #| function() {
  #|   return process.versions.node;
  #| }

///|
extern "js" fn js_write_stderr(s : String) -> Unit =
  #| function(s) {
  #|   process.stderr.write(s);
  #| }

///|
extern "js" fn js_args() -> Array[String] =
  #| function() {
  #|   return process.argv.slice(2);
  #| }

///|
extern "js" fn js_read_stdin() -> Bytes =
  #| function() {
  #|   const all = process.getBuiltinModule("fs").readFileSync(0);
  #|   const bytes = new Uint8Array(all.length);
  #|   bytes.set(all);
  #|   return bytes;
  #| }

///|
extern "js" fn js_write_stdout(b : Bytes) -> Unit =
  #| function(b) {
  #|   process.getBuiltinModule("fs").writeSync(1, Buffer.from(b));
  #| }

///|
extern "js" fn js_exit(code : Int32) -> Unit =
  #| function(code) {
  #|   process.exit(code);
  #| }

///|
/// 装载 gateway wasm 产物（同步 Instance + "_" 常量显式供给——#126 形态；
/// 与 scripts/wasm_load.mts 同形双处：闸宿主走 wasm_load.mts、CLI 胶水走本
/// 段，同形性由各自消费面的行为闸兜底）。产物路径 = 本 js 产物位置上溯
/// 7 层（…/_build/js/release/build/cmd/vitro_wasm → repo root）+ moonbit/
/// _build 标准位；VITRO_WASM_MOD 环境变量覆盖（本地调试改产物不动代码）。
extern "js" fn js_load_gateway() -> JsGateway =
  #| function() {
  #|   const fs = process.getBuiltinModule("fs");
  #|   const path = process.getBuiltinModule("path");
  #|   const override = process.env.VITRO_WASM_MOD;
  #|   const wasmPath = override && override.length > 0 ? override
  #|     : path.resolve(import.meta.dirname, "../../../../../../..",
  #|         "moonbit", "_build", "wasm-gc", "release", "build", "gateway", "wasm", "wasm.wasm");
  #|   const buf = fs.readFileSync(wasmPath);
  #|   const OPTS = { builtins: ["js-string"], importedStringConstants: "_" };
  #|   // "_" 常量显式供给：node>=23 自动容错（imports() 报空即其表现）、
  #|   // node 22 严格校验须供给——name→name 映射（import 名即常量值）。
  #|   // 清单从无选项裸编译枚举（标准行为，不依赖 V8 版本差异）。
  #|   const bare = new WebAssembly.Module(buf);
  #|   const consts = {};
  #|   for (const i of WebAssembly.Module.imports(bare)) if (i.module === "_") consts[i.name] = i.name;
  #|   const mod = new WebAssembly.Module(buf, OPTS);
  #|   const inst = new WebAssembly.Instance(mod, { _: consts });
  #|   return { invoke: inst.exports.invoke, reset: inst.exports.reset };
  #| }

///|
/// serve 流式通道（node readline——MoonBit 闭包进 JS 回调；空行不跳过：
/// 原文直传 invoke，gateway 对非法 JSON 回错误帧——跳过会造成响应行数
/// 错位 + id 对应雪崩，serve_smoke 实锤）。
extern "js" fn js_serve_loop(invoke_line : (String) -> String) -> Unit =
  #| function(invoke_line) {
  #|   const readline = process.getBuiltinModule("readline");
  #|   const rl = readline.createInterface({ input: process.stdin, terminal: false });
  #|   let stopped = false;
  #|   rl.on("line", (line) => {
  #|     if (stopped) return;
  #|     const resp = invoke_line(line);
  #|     process.stdout.write(resp + "\n");
  #|     if (resp.includes('"shutdown":true')) { stopped = true; rl.close(); }
  #|   });
  #| }
