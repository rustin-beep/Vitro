// wasmoon 臂宿主（#199 五方对拍批，2026-10-20）：跑 gateway 零导入风味
// wasm-gc 产物。import=0 ⇒ 无需注册任何宿主函数；String ABI = moonc 零导入
// 降级的 (ref (array (mut i16)))——type index 由 --string-type 给出
// （gateway/wasm_nojs 当前为 1）。协议：命令行逐条请求或 stdin 逐行
// NDJSON 请求，stdout 逐行响应（String → UTF-16 array 构造/读回）。
// 用法: wasmoon_arm <wasm> [--string-type N] [request-line ...]

///|
fn main raise {
  let args = @env.args()
  let mut wasm_path = ""
  let mut string_type = 1
  let mut cases_file = ""
  let requests : Array[String] = []
  let mut i = 1
  while i < args.length() {
    let a = args[i]
    if a == "--string-type" && i + 1 < args.length() {
      let parsed : Result[Int, _] = try {
        Ok(@string.parse_int(args[i + 1]))
      } catch {
        _ => Err(0)
      }
      string_type = match parsed {
        Ok(n) => n
        Err(_) => 1
      }
      i += 2
    } else if a == "--cases" && i + 1 < args.length() {
      cases_file = args[i + 1]
      i += 2
    } else if wasm_path == "" {
      wasm_path = a
      i += 1
    } else {
      requests.push(a)
      i += 1
    }
  }
  if cases_file != "" {
    let text = @fs.read_file_to_string(cases_file) catch {
      _ => {
        eprintln("ARM read-cases-failed path=\{cases_file}")
        return
      }
    }
    for line in text.split("\n") {
      let l = line.trim_space().to_string()
      if l != "" {
        requests.push(l)
      }
    }
  }
  guard wasm_path != "" else {
    eprintln("usage: wasmoon_arm <wasm> [--string-type N] [request-line ...]")
    return
  }
  let wasm_bytes = @fs.read_file_to_bytes(wasm_path) catch {
    e => {
      eprintln("ARM read-wasm-failed path=\{wasm_path}")
      return
    }
  }
  let linker = @runtime.Linker::Linker()
  let store = linker.get_store()
  let wasm_mod = store.decode_module(wasm_bytes) catch {
    e => {
      eprintln("ARM decode-failed err=\{e}")
      return
    }
  }
  let inst = @executor.instantiate_with_linker(linker, "gateway", wasm_mod) catch {
    e => {
      eprintln("ARM instantiate-failed err=\{e}")
      return
    }
  }
  eprintln("ARM stage=instantiated")
    let mut probe_only = false
  let r2 : Array[String] = []
  for r in requests {
    if r == "--probe" {
      probe_only = true
    } else {
      r2.push(r)
    }
  }
  if r2.length() == 0 && !probe_only {
    eprintln("ARM no-requests")
    return
  }
  let out = @buffer.new()
  if probe_only {
    let ret = @executor.call_exported_func(store, inst, "engine_version", [])
    guard ret.length() == 1 && ret[0] is @types.Value::ArrayRef(vref) else {
      eprintln("ARM probe: non-string result")
      return
    }
    out.write_string(read_string(store, vref))
    out.write_string("\n")
  }
  for line in r2 {
    let resp = invoke_line(store, inst, string_type, line)
    out.write_string(resp)
    out.write_string("\n")
  }
  println(out.to_string())
}

///|
fn invoke_line(
  store : @runtime.Store,
  inst : @runtime.ModuleInstance,
  string_type : Int,
  line : String,
) -> String raise {
  // String -> (ref (array (mut i16)))。runtime Value 无 I16：i16 数组元素
  // 以 I32 承载（store 解码路径 Packed(I16) => I32 同款口径）。
  let units : Array[@types.Value] = []
  for u in line.code_units() {
    units.push(@types.Value::I32(u.to_int()))
  }
  let arg_ref = store.alloc_array(string_type, units)
  let ret = @executor.call_exported_func(
    store,
    inst,
    "invoke",
    [@types.Value::ArrayRef(arg_ref)],
  )
  guard ret.length() == 1 && ret[0] is @types.Value::ArrayRef(out_ref) else {
    return "{\"error\":\"invoke returned non-string\"}"
  }
  read_string(store, out_ref)
}

///|
fn read_string(
  store : @runtime.Store,
  out_ref : Int,
) -> String raise {
  let n = store.array_len(out_ref)
  let sb = StringBuilder::new()
  for k in 0..<n {
    let v = store.array_get(out_ref, k)
    guard v is @types.Value::I32(u) else {
      return "{\"error\":\"non-i16 element in result string\"}"
    }
    sb.write_char(Char::from_int(u))
  }
  sb.to_string()
}
