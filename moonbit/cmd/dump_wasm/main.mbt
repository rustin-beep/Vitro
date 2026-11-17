///|
/// REHOST 批 1c 出口（开发工具，native only）：wasm 载体产物全量 dump——
/// 管线（Lexer→Parser→TypeChecker→BytecodeGen）成功后接 `@bytecode.
/// build_wasm_product`（组表 + 单函数体字节）+ `@wasmenc.
/// verify_fold_with_table`（组表引导裁决装载核对——产物闸的机检核心），
/// JSONL 逐行 stdout（产物闸 `scripts/wasmenc_emitgate` 消费）。
/// 批 4b-2（2026-11-15）：成功行追加 `dispatch` 段——`@vm.
/// build_dispatch_product`（全程序投影 + dispatch-loop 组装：可执行
/// 载体模块/data 铺设 hex + 装载协议元数据；argv[0] 真值精化=path 同
/// 串），对拍闸 `scripts/wasmenc_dispatchdiff` 的 V8/wasmtime 胶水消费；
/// 旧消费面（emitgate 判定字段）零扰动。
///
/// 用法：moon run cmd/dump_wasm -- <corpus_dir|file.c>
///
/// 每输入一行：
/// - 成功：{"file":"x.c","ok":true,"groups":N,"bytes":M,"verify":"ok","hex":"...","module":"...","dispatch":{...}}
///   （hex = 指令区字节；module = 垫收证人模块字节——批 2a 起 node 侧
///   wabt `m.validate()` **内容级**真验证消费；组表数字段供统计；
///   dispatch = 批 4b-2 可执行载体：{ok,module,data,base,entry,groups,
///   host_calls,max_steps} 或 {ok:false,reason}——禁译面单行理由归闸登记）
/// - 编译失败：{"file":"x.c","ok":false,"stage":"lex|parse|type|gen","errors":[...]}
///   （与 dump_compile 的 stage 口径同构——编译失败面不是本闸验收对象，
///   由 codegen_diff 既有防线管）
/// - 发射失败：{"file":"x.c","ok":false,"stage":"emit","gip":N,"op":"...","reason":"..."}
///   （禁译面登记/Reserved 拒载——产物闸判红主体）
/// - 装载核对失败：{"file":"x.c","ok":false,"stage":"verify","detail":"..."}
///
/// **零扰动设计**（设计单 §3.2 批 1）：本出口不碰 CompileOutput schema、
/// dump_compile 的 A 级 14 键面与 CLI 协议——legacy code 字段照发，wasm
/// 面按需消费（批 2 run 态装载接线时再升 schema 增量字段）。
extern "C" fn c_exit(code : Int32) -> Unit = "exit"

///|
fn main raise {
  @content_data.install_baked() // #130 批③a：烘焙教学表装载（与 dump_compile 同口径）
  let args = @env.args()
  if args.length() != 2 {
    println("用法: dump_wasm <corpus_dir|file.c>")
    c_exit(4)
  }
  let target = args[1]
  let files : Array[String] = []
  let target_is_dir = @fs.is_dir(target) catch { _ => false }
  let shared_vfs : Map[String, String] = if target_is_dir {
    let vfs : Map[String, String] = Map([])
    collect_files(target, vfs)
    vfs
  } else {
    Map([])
  }
  if target_is_dir {
    // 递归收 .c（PR #505 审阅 P3-1：dump_compile 族只扫顶层而 VFS 递归——
    // 子目录 .c 静默漏扫；本出口与 VFS 收集同口径递归。dump 四包同病，
    // 随下次触达连坐）
    collect_c_files(target, files)
    // 字典序排序（内置 String sort 非字典序——陷阱 #29；dump 四包同款）
    sort_files_lex(files)
  } else {
    files.push(target)
  }
  for path in files {
    // 输入不可读 fail loud（dump_compile #445 C1 同款；目录模式此面不可达）
    let src = read_source_or_exit(path)
    let name = basename_keep_ext(path)
    // 目录模式 VFS 键带目录前缀、解析走 base_dir（dump_compile BUG-C 同款）
    let lexed = if target_is_dir {
      @lexer.tokenize_with_vfs(src, files=shared_vfs, base_dir=dir_of(path))
    } else {
      let v : Map[String, String] = Map([])
      collect_files(dir_of(path), v)
      @lexer.tokenize_with_vfs(src, files=v, base_dir=dir_of(path))
    }
    println(dump_one(path, name, lexed))
  }
}

///|
/// 单输入 dump：管线逐层 fail loud——stage 标注失败层（编译失败面不是
/// 本闸验收对象，emit/verify 两 stage 才是）。`path` = 输入完整路径
/// （dispatch 载体的 argv[0] 真值——与引擎臂 cmd/run 同串跑才逐位对齐）。
fn dump_one(path : String, name : String, lexed : @lexer.LexResult) -> String {
  if !lexed.errors.is_empty() {
    return fail_json(
      name,
      "lex",
      lexed.errors.length().to_string() + " 个词法错误",
    )
  }
  let r = @parser.parse(lexed.tokens)
  if !r.errors.is_empty() || r.program is None {
    let count = if r.program is None && r.errors.is_empty() {
      "1"
    } else {
      r.errors.length().to_string()
    }
    return fail_json(name, "parse", count + " 个解析错误")
  }
  let p = match r.program {
    Some(p) => p
    None => abort("unreachable：None 已在上方拦截")
  }
  let tc = @typeck.TypeChecker::new()
  let (typed, type_errors, _w, _h) = tc.check(p)
  if type_errors.length() > 0 {
    return fail_json(
      name,
      "type",
      type_errors.length().to_string() + " 个类型错误",
    )
  }
  let (output, gen_errors) = @codegen.compile(typed)
  match output {
    Some(o) => emit_json(path, name, o, scan_variadic_host_argc(typed))
    None =>
      // #223：gen_errors 结构化（GenError）——join 消费面取 message 域
      fail_json(name, "gen", gen_errors.map(fn(e) { e.message }).join("\n"))
  }
}

///|
/// 发射 + 装载核对 + 垫收组装 + dispatch 载体产物 → JSON 行（成功行五段
/// /emit/verify/assemble 四态）。`module` = 垫收证人模块字节 hex（批 2a：
/// 组独立 block + 效应垫收 + 段拼装——emitgate 消费过 `wasm-validate`
/// **内容级**真验证；批 1c 的 `hex` 指令区直塞壳只过解码级，审阅 P1-2
/// 的升级件）。`dispatch` = 批 4b-2 可执行载体（vm 投影层 + wasmenc
/// dispatch-loop 组装——dispatchdiff 胶水/对拍闸消费；禁译面 ok:false
/// reason 单行，fail loud 归闸登记不静默）。
fn emit_json(
  path : String,
  name : String,
  o : @bytecode.CompileOutput,
  variadic_argc : Array[Int32],
) -> String {
  let ctx = @bytecode.wasm_emit_ctx(o)
  match @bytecode.build_wasm_product(o) {
    Ok(p) =>
      // 组表引导裁决（装载核对——产物闸机检核心；C 类组唯一可裁决通道）
      match @wasmenc.verify_fold_with_table(p.table, p.bytes, ctx) {
        Ok(_groups) =>
          // 垫收模块组装（批 2a 第三级验证的载体）
          match @wasmenc.assemble_witness_module(p.table, p.bytes) {
            Ok(mod_bytes) => {
              let buf = StringBuilder()
              buf.write_string("{\"file\":")
              buf.write_string(@ast.json_escape_string(name))
              buf.write_string(",\"ok\":true,\"groups\":")
              buf.write_string(p.table.groups.length().to_string())
              buf.write_string(",\"bytes\":")
              buf.write_string(p.bytes.length().to_string())
              buf.write_string(",\"verify\":\"ok\",\"hex\":\"")
              buf.write_string(hex_bytes(p.bytes))
              buf.write_string("\",\"module\":\"")
              buf.write_string(hex_bytes(mod_bytes))
              buf.write_string("\",\"dispatch\":")
              buf.write_string(dispatch_json(path, o, variadic_argc))
              buf.write_string("}")
              buf.to_string()
            }
            Err(e) => {
              let (kind, detail) = assemble_err_text(e)
              "{\"file\":\{@ast.json_escape_string(name)},\"ok\":false,\"stage\":\"verify\",\"kind\":\"\{kind}\",\"detail\":\{@ast.json_escape_string(detail)}}"
            }
          }
        Err(e) => {
          let (kind, detail) = verify_err_text(e)
          "{\"file\":\{@ast.json_escape_string(name)},\"ok\":false,\"stage\":\"verify\",\"kind\":\"\{kind}\",\"detail\":\{@ast.json_escape_string(detail)}}"
        }
      }
    Err(@bytecode.EmitFailed(gip, op_name, reason)) =>
      "{\"file\":\{@ast.json_escape_string(name)},\"ok\":false,\"stage\":\"emit\",\"gip\":\{gip},\"op\":\{@ast.json_escape_string(op_name)},\"reason\":\{@ast.json_escape_string(reason)}}"
  }
}

///|
/// dispatch 载体产物段（批 4b-2）：vm 投影层 + dispatch-loop 组装一体——
/// 成功携模块/data hex 与装载协议元数据（胶水实例化消费）；禁译/组装失败
/// `ok:false` + reason 单行（对拍闸按 reason 分类登记 skip 面，不静默）。
/// `max_steps` 钉 10,000,000（引擎臂 cmd/run 默认同值——对拍臂预算判定
/// 须同源；升参需求随 host 回接批评估）。
fn dispatch_json(
  path : String,
  o : @bytecode.CompileOutput,
  variadic_argc : Array[Int32],
) -> String {
  match @vm.build_dispatch_product(o, 10000000, argv0=path, variadic_argc~) {
    Ok(p) => {
      let buf = StringBuilder()
      buf.write_string("{\"ok\":true,\"module\":\"")
      buf.write_string(hex_bytes(p.module_bytes))
      buf.write_string("\",\"data\":\"")
      buf.write_string(hex_bytes(p.data_blob))
      buf.write_string("\",\"base\":")
      buf.write_string(p.data_base.to_string())
      buf.write_string(",\"entry\":")
      buf.write_string(p.entry_ip.to_string())
      buf.write_string(",\"groups\":")
      buf.write_string(p.group_count.to_string())
      buf.write_string(",\"host_calls\":")
      buf.write_string(p.host_calls.to_string())
      buf.write_string(",\"max_steps\":")
      buf.write_string(p.max_steps.to_string())
      // 窗口装载参数（批 4′ host 回接——中继 INIT 帧：堆基/argv 同源）
      buf.write_string(",\"win_data_end\":")
      buf.write_string(p.win_data_end.to_string())
      buf.write_string(",\"win_argc\":")
      buf.write_string(p.win_argc.to_string())
      buf.write_string(",\"win_argv0\":")
      buf.write_string(@ast.json_escape_string(p.win_argv0))
      buf.write_string("}")
      buf.to_string()
    }
    Err(reason) =>
      "{\"ok\":false,\"reason\":\{@ast.json_escape_string(reason)}}"
  }
}

///|
/// VerifyError → (kind, detail) 文本翻译（装载核对失败的诊断面）。
fn verify_err_text(e : @wasmenc.VerifyError) -> (String, String) {
  match e {
    GroupCountMismatch(want, got) =>
      ("GroupCountMismatch", "组数不符：侧车 \{want} vs 折叠 \{got}")
    GroupMismatch(gip, want_op, got_op, want_operand, got_operand) =>
      (
        "GroupMismatch",
        "组 \{gip}：op \{want_op.name()} vs \{got_op.name()}，operand \{want_operand} vs \{got_operand}",
      )
    FoldFailed(fe) =>
      (
        "FoldFailed",
        match fe {
          Decode(off, _) => "折叠解码失败 @字节偏移 \{off}"
          NoTemplate(off) => "无模板匹配 @字节偏移 \{off}"
          TableShapeConflict(off, a, b) =>
            "同长双匹配 \{a.name()}/\{b.name()} @\{off}"
        },
      )
    TemplateMismatch(gip, op, off) =>
      (
        "TemplateMismatch",
        "组 \{gip}（\{op.name()}）模板匹配失败 @字节偏移 \{off}",
      )
    BoundaryMismatch(gip, op, got, want) =>
      (
        "BoundaryMismatch",
        "组 \{gip}（\{op.name()}）消费 \{got} 字节 ≠ 侧车声明 \{want}",
      )
    GroupGap(gip, prev_end, off) =>
      (
        "GroupGap",
        "组 \{gip} 与前组边界留隙：前组止于 \{prev_end}、本组起于 \{off}（字节流有组表未覆盖的空洞）",
      )
    TrailingInstrs(gip, left) =>
      (
        "TrailingInstrs",
        "组 \{gip} 后仍有 \{left} 字节尾随（组表未覆盖）",
      )
    ReservedGroup(gip, op) =>
      (
        "ReservedGroup",
        "组 \{gip} 为 Reserved（\{op.name()}）——装载即拒载",
      )
  }
}

///|
/// AssembleError → (kind, detail) 文本翻译（垫收组装失败的诊断面——
/// 批 2a 第四态）。
fn assemble_err_text(e : @wasmenc.AssembleError) -> (String, String) {
  match e {
    Decode(off, _) =>
      ("AssembleDecode", "组装解码失败 @字节偏移 \{off}")
    BadBoundary(gip, off, len) =>
      (
        "AssembleBadBoundary",
        "组 \{gip} 边界越界：offset=\{off} len=\{len}",
      )
    NotCovered(want, got) =>
      (
        "AssembleNotCovered",
        "组表未覆盖指令流：期待 \{want} 实得 \{got}",
      )
    Effect(inner) =>
      (
        "AssembleEffect",
        match inner {
          TypeMismatch(at, w, g) =>
            "效应类型错 @\{at}：期望 0x\{w.to_int()} 实得 0x\{g.to_int()}"
          BadBrDepth(at, d, n) => "br 深度越界 @\{at}：d=\{d} 帧数=\{n}"
          BadSlot(at, i) => "槽越界 @\{at}：idx=\{i}"
          BadCallIdx(at, n) =>
            "call 索引非法 @\{at}：idx=\{n}（面内仅 0）"
        },
      )
  }
}

///|
/// errors 数组单元素（json_escape_string 返回带引号的完整 JSON 串——
/// dump_compile 同形）。
fn fail_json(name : String, stage : String, msg : String) -> String {
  "{\"file\":\{@ast.json_escape_string(name)},\"ok\":false,\"stage\":\"\{stage}\",\"errors\":[\{@ast.json_escape_string(msg)}]}"
}

///|
/// 字节数组 → 两位小写十六进制串（node 侧 wabt validate 的消费形态；
/// wasmenc witness_dump 的 DUMP1B 行格式是另一用途——互不为孪生；digit
/// if-else 链与 witness_dump bytes_to_hex 同形，避开 String 索引类型坑）。
fn hex_bytes(bytes : Array[Byte]) -> String {
  fn digit(x : UInt32) -> String {
    if x < 10U {
      x.to_string()
    } else if x == 10U {
      "a"
    } else if x == 11U {
      "b"
    } else if x == 12U {
      "c"
    } else if x == 13U {
      "d"
    } else if x == 14U {
      "e"
    } else {
      "f"
    }
  }
  let buf = StringBuilder()
  for b in bytes {
    let v = b.to_uint() & 0xFFU
    buf.write_string(digit(v / 16U))
    buf.write_string(digit(v % 16U))
  }
  buf.to_string()
}

///|
/// basename 保留扩展名（dir_of 族同义复制件——cmd 层互不可 import；
/// 修改须与其余 dump 三包同步）。
fn basename_keep_ext(path : String) -> String {
  let mut name = path
  let mut i = path.length() - 1
  while i >= 0 {
    if path[i] == '/' || path[i].to_int() == 92 {
      name = path[i + 1:].to_owned()
      break
    }
    i -= 1
  }
  name
}

///|
/// 路径目录段（dir_of 族同义复制件——cmd 层互不可 import；中段原文
/// 透传不归一〔VFS 键同源〕，修改须与其余 dump 三包同步）。
fn dir_of(path : String) -> String {
  let mut last = -1
  for i = 0; i < path.length(); i = i + 1 {
    let c = path[i]
    if c.to_int() == 47 || c.to_int() == 92 {
      last = i
    }
  }
  if last == 0 {
    "/"
  } else if last < 0 {
    "."
  } else {
    path[:last].to_owned()
  }
}

///|
/// 递归收集目录下全部文件进 VFS（键 = 相对目录的路径原文；dump 四包同款）。
fn collect_files(dir : String, vfs : Map[String, String]) -> Unit raise {
  for name in @fs.read_dir(dir) {
    let full = vfs_join(dir, name)
    let sub_is_dir = @fs.is_dir(full) catch { _ => false }
    if sub_is_dir {
      collect_files(full, vfs)
    } else {
      // 同目录文件供 quote-include 候选（dump_compile B3 批同款：收全部
      // 文件，不可读跳过）
      let content = @fs.read_file_to_string(full) catch { _ => continue }
      vfs.set(full, content)
    }
  }
}

///|
/// 读源文件（不可读 fail loud：一行原因 + rc=4——dump_compile #445 C1 同款）。

///|
/// IOError 的一行文本（四 dump 同形复制件——cmd 层互不可 import）。
fn io_error_text(e : @fs.IOError) -> String {
  let IOError(msg) = e
  msg
}

///|
fn read_source_or_exit(path : String) -> String {
  @fs.read_file_to_string(path) catch {
    e => {
      println("输入不可读：\{path}（\{io_error_text(e)}）")
      c_exit(4)
      ""
    }
  }
}

///|
/// 递归收集目录下全部 .c 进 files（审阅 P3-1：与 collect_files 的 VFS
/// 递归同口径——顶层扫描会静默漏子目录 .c）。
fn collect_c_files(dir : String, files : Array[String]) -> Unit raise {
  for name in @fs.read_dir(dir) {
    let full = vfs_join(dir, name)
    let sub_is_dir = @fs.is_dir(full) catch { _ => false }
    if sub_is_dir {
      collect_c_files(full, files)
    } else if name.length() > 2 && name[name.length() - 2:] == ".c" {
      files.push(full)
    }
  }
}

///|
/// VFS 键拼装（四 dump 同形复制件："." 裸名 / "/" 根级 / 其余原文拼接）。
fn vfs_join(dir : String, name : String) -> String {
  if dir == "." {
    name
  } else if dir == "/" {
    "/" + name
  } else {
    "\{dir}/\{name}"
  }
}

///|
/// 字典序排序（内置 String sort 是长度优先序——陷阱 #29；dump 四包同款）。
fn sort_files_lex(files : Array[String]) -> Unit {
  let mut i = 1
  while i < files.length() {
    let k = files[i]
    let mut j = i - 1
    while j >= 0 && @util.str_cmp(files[j], k) > 0 {
      files[j + 1] = files[j]
      j -= 1
    }
    files[j + 1] = k
    i += 1
  }
}
