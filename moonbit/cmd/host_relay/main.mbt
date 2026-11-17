///|
/// **REHOST 批 4′：host 窗口中继进程**（js 目标——node 直跑；V8/wasmtime
/// 臂的 `env.vitro_host_call` 回接**引擎单源** host 分发）。
///
/// **同步帧协议**（stdin ← 请求 / stdout → 应答——文本命令头 + 二进制段，
/// 全双工逐帧应答；胶水侧 `fs.writeSync(child.stdin.fd)` + `fs.readSync(
/// child.stdout.fd)` 同步驱动）：
/// ```
/// 请求  INIT <data_end> <argc_main> <argv0_hex>\n <1MB 镜像>
/// 应答  OK\n
/// 请求  CALL <id> <argc>\n <argc×8B 参数（小端 u64×argc）> <1MB 镜像>
/// 应答  RES <kind> <a0> <a1> <waiting> <code_len>\n <code> <delta> <1MB 镜像>
/// ```
/// - kind：0=返回值（a0=低 32 位 a1=高 32 位）| 1=trap（a0=0；code =
///   「E 码\u0000文案」UTF-8）| 2=停机（a0=exit_code）；
/// - waiting：1 = Stdin 族防御命中（协议破裂标记——白名单域不可达）；
/// - delta = 本次调用 stdout 增量；镜像 = 引擎侧最新 1MB（wasm 回写）。
///
/// EOF（stdin 断）= 会话终（rc 0）。

///|
extern "js" fn js_read_line() -> String =
  #| function() {
  #| const fs = process.getBuiltinModule("fs");
  #| const buf = [];
  #| while (true) {
  #|   const one = Buffer.alloc(1);
  #|   const r = fs.readSync(0, one, 0, 1);
  #|   if (r === 0) { process.exit(0); }
  #|   if (one[0] === 10) { break; }
  #|   buf.push(one[0]);
  #|   if (buf.length > 4096) { process.exit(8); }
  #|   }
  #| return Buffer.from(buf).toString("latin1");
  #| }

///|
extern "js" fn js_read_exact(n : Int32) -> Bytes =
  #| function(n) {
  #| const fs = process.getBuiltinModule("fs");
  #| const buf = Buffer.alloc(n);
  #| let off = 0;
  #| while (off < n) {
  #|   const r = fs.readSync(0, buf, off, n - off);
  #|   if (r === 0) { process.exit(0); }
  #|   off += r;
  #|   }
  #| return new Uint8Array(buf);
  #| }

///|
extern "js" fn js_write(b : Bytes) -> Unit =
  #| function(b) {
  #| process.getBuiltinModule("fs").writeSync(1, Buffer.from(b));
  #| }

///|
extern "js" fn js_hex_decode(s : String) -> Bytes =
  #| function(s) {
  #| return new Uint8Array(Buffer.from(s, "hex"));
  #| }

///|
fn bytes_to_fixed(b : Bytes) -> FixedArray[Byte] {
  let arr : FixedArray[Byte] = FixedArray::make(b.length(), b'\x00')
  for i = 0; i < b.length(); i = i + 1 {
    arr[i] = b[i]
  }
  arr
}

///|
fn write_line(s : String) -> Unit {
  js_write(@utf8.encode(s + "\n"))
}

///|
/// 小端 8 字节 → u64（窗口参数读取——@util.le_u64_at 同语义本地件）。
fn le_u64_at(b : Bytes, off : Int32) -> UInt64 {
  let mut v : UInt64 = 0UL
  for i = 7; i >= 0; i = i - 1 {
    v = (v << 8) | b[off + i].to_uint().to_uint64()
  }
  v
}

///|
/// 十六进制串（ASCII）→ String（argv0 通道——latin1 读行 + hex 解码免疫
/// 路径字符域）。
fn hex_to_string(s : String) -> String {
  let b = js_hex_decode(s)
  @utf8.decode(b) catch {
    _ => ""
  }
}

///|
/// 协议行切分（ASCII 域——按空格；String 索引 UInt16 码元陷阱 #24 域外）。
fn split_line(line : String) -> Array[String] {
  let out : Array[String] = []
  let cur = StringBuilder()
  for i = 0; i < line.length(); i = i + 1 {
    if line[i] == ' ' {
      out.push(cur.to_string())
      cur.reset()
    } else {
      cur.write_string(line[i:i + 1].to_owned())
    }
  }
  out.push(cur.to_string())
  out
}

///|
fn main {
  let mut relay : @vm.HostRelay? = None
  while true {
    let line = js_read_line()
    if line.length() >= 4 {
      if line.has_prefix("INIT") {
        // INIT <data_end> <argc_main> <argv0_hex>
        let parts : Array[String] = split_line(line)
        if parts.length() >= 4 {
          let data_end = (@string.parse_int(parts[1]) catch { _ => 0 }).reinterpret_as_uint()
          let argc_main = @string.parse_int(parts[2]) catch { _ => 0 }
          let argv0 = hex_to_string(parts[3])
          let argv : Array[String] = if argv0.is_empty() { [] } else { [argv0] }
          // 1MB 镜像（长度机判——异长即协议破裂 fail loud）
          let image = js_read_exact(1048576)
          relay = Some(
            @vm.HostRelay::setup(
              data_end,
              argc_main,
              argv,
              bytes_to_fixed(image),
            ),
          )
          write_line("OK")
        }
      } else if line.has_prefix("CALL") {
        // CALL <id> <argc>
        guard relay is Some(r) else {
          write_line("ERR no-init")
          continue
        }
        let parts : Array[String] = split_line(line)
        if parts.length() >= 3 {
          let id = @string.parse_int(parts[1]) catch { _ => -1 }
          let argc = @string.parse_int(parts[2]) catch { _ => 0 }
          let params = js_read_exact(argc * 8)
          // 窗口参数入栈（值栈序）
          for i = 0; i < argc; i = i + 1 {
            r.push_arg(le_u64_at(params, i * 8))
          }
          // wasm → 引擎内存同步（首版全量）
          let mem = js_read_exact(1048576)
          r.restore_memory(bytes_to_fixed(mem))
          // 分发（引擎单源）+ 应答
          let (outcome, delta, waiting) = r.call(id)
          let img = r.memory_raw()
          match outcome {
            Value(v, _) =>
              write_line(
                "RES 0 \{v & 0xFFFFFFFFUL} \{v >> 32} \{if waiting { 1 } else { 0 }} 0 \{delta.length()}",
              )
            Trap(code, msg) => {
              let payload = code + "\{(0).unsafe_to_char()}" + msg
              write_line(
                "RES 1 0 0 \{if waiting { 1 } else { 0 }} \{@utf8.encode(payload).length()} \{delta.length()}",
              )
              js_write(@utf8.encode(payload))
            }
            Halt(rc) =>
              write_line(
                "RES 2 \{rc} 0 \{if waiting { 1 } else { 0 }} 0 \{delta.length()}",
              )
          }
          js_write(delta)
          js_write(img)
        }
      }
    }
  }
}
