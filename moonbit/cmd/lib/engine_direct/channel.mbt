// engine_direct：EngineChannel 的 gateway 直连构造（native/js 臂缺省
// 通道——行为与直连时代零变化；挪出 lib/cli 的理由见 moon.pkg 头注）。

///|
/// 直连通道（gateway 库函数直调——invoke NDJSON 单口 + 会话周边）。
pub fn direct_channel() -> @cli.EngineChannel {
  {
    invoke: fn(line : String) -> String { @gateway.invoke(line) },
    invoke_parsed: fn(line : String) -> Json? { @gateway.invoke_parsed(line) },
    reset: fn() -> Unit { @gateway.reset() },
    set_clock: fn(c : () -> UInt64) -> Unit { @gateway.set_clock_source(c) },
    set_include_reader: fn(r : (String) -> String?) -> Unit {
      @gateway.set_include_reader(r)
    },
    compile_params: fn(file : String, src : String) -> String {
      // filename 装配（BUG-A 修复语义保留）：`-`（stdin 源）不传 filename；
      // 其余传全路径——gateway 侧 base_dir 语义（同目录 include）
      if file == "-" {
        "{\"source\":\"\{@util.json_escape(src)}\"}"
      } else {
        "{\"source\":\"\{@util.json_escape(src)}\",\"filename\":\"\{@util.json_escape(file)}\"}"
      }
    },
  }
}
