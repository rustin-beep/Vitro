// gateway 核心（S7 批五号，2026-09-29）：NDJSON 帧协议的会话承载
// （拆包 2026-09-29：4 函数在本包为普通 pub——wasm 导出面在外壳包 gateway/wasm）
// （F-5 裁定）——invoke 单口承载 21 方法表，session 全局单例（单活跃
// 会话语义 D2，与 cmd/serve 进程模型同构）。
// 宿主契约（Node/浏览器）：
//   const mod = new WebAssembly.Module(buf,
//     { builtins: ['js-string'], importedStringConstants: '_' });
//   const inst = await WebAssembly.instantiate(mod, {});
//   inst.exports.invoke(line)  // String → String 直传（js-string builtins）
// shutdown 语义：invoke 返回的响应帧携带 "shutdown":true 时宿主自行停
// 止发下一行（无 stdio 循环的等价物——cmd/serve 壳同判据）。
// engine_version 分叉登记：F-5 语义含构建期 git 短哈希（产物自检），
// MoonBit 无编译期注入通道（数据装载选型裁定——大数据进源码同为人工
// 维护）——v1 为手维护版本常量，随发版更新；构建自检由 mooncakes 版本
// 承担（capabilities 的 engine_version 分叉同源，已在 CHANGELOG 登记）。

///|
/// 引擎版本常量（发版批随 moon.mod 版本连坐更新——0.7.0 首值）。
pub const ENGINE_VERSION : String = "0.8.0"

///|
/// 会话全局单例（模块级——一实例一引擎，多实例由宿主起多模块实例承担，
// 浏览器 Worker 多实例先例同理）。
let session : @session.Session = @session.Session::new()

///|
/// 单行请求 → 响应串（NDJSON 帧；未知方法回 protocol 错误帧——读不懂
/// 的请求必须报错，协议演化纪律 ②）。
pub fn invoke(line : String) -> String {
  serve_handle(session, line).0
}

///|
/// invoke 的结构化形态（#70 第二步，2026-10-11）：同一 NDJSON 帧通道，
/// 返回解析后的 Json 树（响应由本包构造——json_parse 恒成功；解析失败
/// 返回 None 供调用方 fail loud）。CLI 文本模式的帧→标记行渲染消费
///（json_parse 升序裁定注记的「第二个消费者」——本函数即上提点，独占
/// 导出、parse 本体仍居包内）。
pub fn invoke_parsed(line : String) -> Json? {
  let resp = invoke(line)
  let v = json_parse(resp) catch { _ => return None }
  Some(v)
}

///|
/// 会话重置（R3 语义：清空编译/运行态，保留会话级配置——与
/// session.reset 方法同语义，供宿主在无方法帧场景下直调）。
pub fn reset() -> Unit {
  reset_session_preserving_config(session)
}

///|
/// 协议版本（StepPayload schema 轨道——与 capabilities.schema.version
/// 同单源 @protocol.SCHEMA_VERSION）。
pub fn protocol_version() -> String {
  @protocol.SCHEMA_VERSION
}

///|
/// 引擎版本（手维护常量——见文件头分叉登记）。
pub fn engine_version() -> String {
  ENGINE_VERSION
}

///|
/// 宿主注入的 quote-include 读取器（2026-09-29 审阅 P2 修复）：native
/// 壳（cmd/serve）启动时注册文件系统读取；wasm-gc 无文件系统、不注册
/// ⇒ include 家族解析为 E1021 not found（正当教学诊断；宿主注入文件表
/// 是将来扩展位）。**此前批五号上提时统一换成 vfs 空表，双宿主共用使
/// native 静默丢掉文件系统解析**（审阅实锤：oracle 同请求出宏展开链
/// 返 7、本侧 E1021）——回调注入消掉 fs 依赖（wasm-gc 构建图不兼容
/// native-only 包），native 语义经注册恢复。
let include_reader : Ref[((String) -> String?)?] = Ref(None)

///|
/// 注册 include 读取器（返回 None = 该路径不存在，词法层报 E1021）。
pub fn set_include_reader(read : (String) -> String?) -> Unit {
  include_reader.val = Some(read)
}

///|
/// 注册墙钟源（native 壳启动时调用——time/clock 非确定性模式的真值通道；
/// wasm-gc 宿主不注册 ⇒ 恒 0〔无熵源 F5/R12〕）。2026-10-02 deterministic
/// 分叉销案接线：oracle serve 的 time/clock 走 current_time_millis 真值，
/// 本侧此前 dispatch 恒传 0UL 占位。
pub fn set_clock_source(f : () -> UInt64) -> Unit {
  session.vm.set_clock_source(f)
}

///|
/// include 读取 provider（把注入回调包装成 SourceProvider）。
priv enum HostIncludeProvider {
  P
}

///|
impl @token.SourceProvider for HostIncludeProvider with fn read(
  _self : HostIncludeProvider,
  path : String,
) -> String raise @token.SourceError {
  match include_reader.val {
    Some(read) =>
      match read(path) {
        Some(s) => s
        None => raise @token.SourceError::NotFound(path~)
      }
    None => raise @token.SourceError::NotFound(path~)
  }
}

///|
/// quote-include 词法入口（宿主形态经注册状态分叉——见 include_reader）。
fn lex_full_source(
  full_source : String,
  units : Array[@session.CompileUnit],
) -> @token.LexResult {
  // 首个非空文件名的目录段作候选链 base_dir（Rust base_path 语义
  // 的行为级等价——cmd/run/main.mbt dir_of 头注的 7 形态探针）
  let mut base_dir = "."
  for u in units {
    if !u.filename.is_empty() {
      base_dir = dir_of(u.filename)
      break
    }
  }
  match include_reader.val {
    Some(_) =>
      @lexer.tokenize_with(
        full_source,
        provider=HostIncludeProvider::P,
        base_dir~,
      )
    None => {
      // wasm-gc：units 全量注入内存 vfs（打开本地文件夹批 2026-10-05
      // 前置）——集合内文件互相 quote-include 可解析（浏览器端多文件
      // include 的能力载体，tokenize_with_vfs 头注的既定语义）；集合外
      // 仍 E1021（无 fs，宁诊断不静默——勘察 H-5）。key 为规范 posix
      // 相对路径：`\` → `/`（resolver.normalize_path 语义的前置对齐）
      let files : Map[String, String] = Map([])
      for u in units {
        let key = u.filename.replace(old="\\", new="/")
        if !key.is_empty() {
          files[key] = u.source
        }
      }
      @lexer.tokenize_with_vfs(full_source, files~, base_dir~)
    }
  }
}

///|
/// 路径目录段（cmd/run/main.mbt dir_of 的复制件——等价性经 7 形态
/// 端到端探针实证，见彼处头注；修改须两处同步）。
fn dir_of(path : String) -> String {
  let mut last = -1
  for i = 0; i < path.length(); i = i + 1 {
    let c = path[i]
    if c.to_int() == 47 || c.to_int() == 92 {
      last = i
    }
  }
  if last <= 0 {
    "."
  } else {
    let buf = StringBuilder()
    for i = 0; i < last; i = i + 1 {
      let c = path[i]
      if c.to_int() == 92 {
        buf.write_char('/')
      } else {
        buf.write_char(c.to_int().unsafe_to_char())
      }
    }
    buf.to_string()
  }
}
