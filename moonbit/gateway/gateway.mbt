// gateway 核心（S7 批五号，2026-09-29）：NDJSON 帧协议的 4 函数导出面
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
pub const ENGINE_VERSION : String = "0.7.0"

///|
/// 会话全局单例（模块级——一实例一引擎，多实例由宿主起多模块实例承担，
// 浏览器 Worker 多实例先例同理）。
let session : @session.Session = @session.Session::new()

///|
/// 单行请求 → 响应串（NDJSON 帧；未知方法回 protocol 错误帧——读不懂
/// 的请求必须报错，协议演化纪律 ②）。
#export_name("invoke")
pub fn invoke(line : String) -> String {
  serve_handle(session, line).0
}

///|
/// 会话重置（R3 语义：清空编译/运行态，保留会话级配置——与
/// session.reset 方法同语义，供宿主在无方法帧场景下直调）。
#export_name("reset")
pub fn reset() -> Unit {
  reset_session_preserving_config(session)
}

///|
/// 协议版本（StepPayload schema 轨道——与 capabilities.schema.version
/// 同单源 @protocol.SCHEMA_VERSION）。
#export_name("protocol_version")
pub fn protocol_version() -> String {
  @protocol.SCHEMA_VERSION
}

///|
/// 引擎版本（手维护常量——见文件头分叉登记）。
#export_name("engine_version")
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
let include_reader : Ref[((String) -> String?)?] = Ref::new(None)

///|
/// 注册 include 读取器（返回 None = 该路径不存在，词法层报 E1021）。
pub fn set_include_reader(read : (String) -> String?) -> Unit {
  include_reader.val = Some(read)
}

///|
/// include 读取 provider（把注入回调包装成 SourceProvider）。
enum HostIncludeProvider {
  P
}

///|
impl @token.SourceProvider for HostIncludeProvider with fn read(
  self : HostIncludeProvider,
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
  match include_reader.val {
    Some(_) => {
      // 首个非空文件名的目录段作候选链 base_dir（Rust base_path 语义
      // 的行为级等价——cmd/run/main.mbt dir_of 头注的 7 形态探针）
      let mut base_dir = "."
      for u in units {
        if !u.filename.is_empty() {
          base_dir = dir_of(u.filename)
          break
        }
      }
      @lexer.tokenize_with(
        full_source,
        provider=HostIncludeProvider::P,
        base_dir~,
      )
    }
    None => {
      // wasm-gc：内存 vfs 空表（include → E1021）
      let files : Map[String, String] = Map([])
      @lexer.tokenize_with_vfs(full_source, files~)
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
