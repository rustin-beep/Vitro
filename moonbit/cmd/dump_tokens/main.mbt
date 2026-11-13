///|
/// S2 差分出口（开发工具，native only）：批量产出 L1/L2 token TSV——
/// 与 Rust `vitro_cli dump-tokens` 逐字节同构，供 Go 差分驱动比对。
///
/// 用法：moon run cmd/dump_tokens -- <corpus_dir|file.c> <out_dir> <raw|pp|both>
/// 用法错（缺参/模式非法/参数过多/输出目录与语料目录相同）= 原因行 + rc=4
///（#230 治理，2026-10-27——旧走未捕获 Failure 的 PanicError 栈 + rc=127，
/// 对脚本与 IDE 都是噪声；参数过多与 out==target 门禁 B3 批 2026-11-02
/// 四家连坐补齐，模板 = dump_compile 既有防御形态，见 dump_ast 头注）。
/// 产物名 `<name>.l1.tsv` / `<name>.l2.tsv`（stem **去扩展名**——两段式
/// basename_no_ext，裸名与带目录同果；与 ast/typeck/compile 三家「stem 含
/// .c」的 F11 口径不同，系本工具既定契约，B3 批 basename 正名面不含此处）。
/// 输入不可读（不存在/无权限）= 原因行 + rc=4（#445 C1，2026-11-12——
/// #230 治理在 dump 族读文件面的收尾，详见 dump_ast 头注）。
/// **api 对拍面缺口声明（#445 C5，2026-11-12）**：dump 族中本工具无 gateway
/// api 对拍方法（api help 的 dump 族 = ast/codegen/memory/symbols/typeck
/// 五个，无 tokens.dump）——L1/L2 TSV 是差分驱动内部格式而非下游面，单源
/// 验证只剩 @lexer 包内测试（dump_raw_tsv/dump_lex_tsv 锚），**有意不补**
/// api 方法（补齐须协议面 +1 + api_help 再生 + 方法数连坐五处）。
extern "C" fn c_exit(code : Int32) -> Unit = "exit"

///|
fn main raise {
  let args = @env.args()
  if args.length() < 4 {
    println("用法: dump_tokens <corpus_dir|file.c> <out_dir> <raw|pp|both>")
    c_exit(4)
  }
  if args.length() > 4 {
    println(
      "参数过多：期望 <corpus_dir|file.c> <out_dir> <raw|pp|both>（实测 \{args.length() - 1} 个位置参数）",
    )
    c_exit(4)
  }
  let target = args[1]
  let out_dir = args[2]
  let mode = args[3]
  if norm_path(target) == norm_path(out_dir) {
    println("输出目录与语料目录相同——拒绝写入门禁")
    c_exit(4)
  }
  let want_raw = mode == "raw" || mode == "both"
  let want_pp = mode == "pp" || mode == "both"
  if !want_raw && !want_pp {
    println("模式必须是 raw|pp|both，得到 '\{mode}'")
    c_exit(4)
  }
  if !@fs.path_exists(out_dir) {
    @fs.create_dir(out_dir)
  }
  let files : Array[String] = []
  let target_is_dir = @fs.is_dir(target) catch { _ => false }
  // Vfs 目录级收集**一次**共享（性能修复 2026-09-19：此前 dump_one 对每个
  // 文件都重新 collect_files 整个目录——2400 例语料 O(N²) ≈ 576 万次文件
  // 操作，MoonBit 侧 dump 实测 4m43s vs Rust 2.5s；修复后按目录收集一次）
  let shared_vfs : Map[String, String] = if target_is_dir {
    let vfs : Map[String, String] = Map([])
    collect_files(target, vfs)
    vfs
  } else {
    Map([])
  }
  if target_is_dir {
    for name in @fs.read_dir(target) {
      if name.length() > 2 && name[name.length() - 2:] == ".c" {
        files.push("\{target}/\{name}")
      }
    }
    // 码元字典序（#445 B2，2026-11-12：自内置 files.sort() 迁入——内置序是
    // 长度优先 + 等长码元序（util 探针实测 cmp("e2_x.c","e10_y.c")=-1 而字典
    // 序应 +1）；旧注「行为债登记 R1b W1-3 待修」就此销案——四壳处理序
    // 同形（与 compile 壳 sort_files_lex 统一））
    sort_files_lex(files)
  } else {
    files.push(target)
  }
  for path in files {
    // 不可读输入 = 原因行 + rc=4（#445 C1，2026-11-12：#230 治理收口——旧
    // 裸调 read_file_to_string，不存在路径走未捕获 IOError 的 PanicError 栈
    // + rc=127，差分驱动传错路径时拿栈噪声而非一行原因）
    let src = match read_input_or_reason(path) {
      Ok(s) => s
      Err(reason) => {
        println(reason)
        c_exit(4)
        abort("unreachable：c_exit 已退出")
      }
    }
    let stem = basename_no_ext(path)
    if want_raw {
      let r = @lexer.tokenize_raw(src)
      @fs.write_string_to_file(
        "\{out_dir}/\{stem}.l1.tsv",
        @lexer.dump_raw_tsv(r),
      )
    }
    if want_pp {
      // 自定义 include：语料目录文件注入 Vfs（对齐 Rust 真实 fs 语义——
      // quote 候选链在"源文件目录"可见同名头文件）。目录模式用共享收集；
      // 单文件模式现场收集其所在目录
      let vfs = if target_is_dir {
        shared_vfs
      } else {
        let v : Map[String, String] = Map([])
        collect_files(dir_of(path), v)
        v
      }
      let r = @lexer.tokenize_with_vfs(src, files=vfs, base_dir=dir_of(path))
      @fs.write_string_to_file(
        "\{out_dir}/\{stem}.l2.tsv",
        @lexer.dump_lex_tsv(r),
      )
    }
  }
  println("dump-tokens: \{files.length()} 个 .c 文件 -> \{out_dir}")
}

///|
/// 路径归一（纯字符串域、零 fs 依赖——PR #450 审阅 P2-3，2026-11-02）：`\` 折叠为
/// `/`、剥 `.` 与空段、`..` 弹栈（栈空或栈顶已是 `..` 则保留——相对上溯语义）、
/// 尾分隔符忽略。out==target 门禁旧形态是裸字符串相等——`corpus` vs `./corpus` vs
/// `corpus/` vs `a/../corpus` 同义路径全放行，实测产物仍写进语料目录（审阅亲踩）。
/// **与 realpath 的差异**：不触盘、不解析符号链接/盘符大小写/当前目录——教学工具
/// 本地调用域足够，真要绝对化需 fs 层 realpath（本包 vendored fs 无此 API）。
/// dir_of 族同义复制件——修改须与其余 dump 三包同步。
fn norm_path(p : String) -> String {
  // 反斜杠折叠：String::replace 只替换首个（陷阱 #37），循环到不含为止——先例
  // host_io.mbt from_stdin_text 的 CRLF 规整
  let mut unified = p
  while unified.contains("\\") {
    unified = unified.replace(old="\\", new="/")
  }
  let segs : Array[String] = []
  for seg in unified.split("/") {
    let s : String = seg.to_owned()
    if s == "" || s == "." {
      continue
    }
    if s == ".." {
      if segs.length() > 0 && segs[segs.length() - 1] != ".." {
        ignore(segs.remove(segs.length() - 1))
      } else {
        segs.push("..")
      }
      continue
    }
    segs.push(s)
  }
  segs.join("/")
}

///|
/// 路径目录段（dir_of 族同义复制件——cmd 层互不可 import；唯一分隔符
/// 在 0 位 = POSIX 根级文件（"/x.c"）返回 "/"——#378：旧 dirname_of 返回
/// "" 作 base_dir ⇒ 根级主文件 quote-include 候选链失配；无分隔符返回
/// "."（collect_files 裸名键约定依赖此值）。**中段原文透传不归一**——
/// 目录模式 VFS 键 = target 参数原文拼装（Windows 反斜杠形态），base_dir
/// 须与其同源；归一会让候选键与 VFS 键结构性失配 ⇒ include 恒 miss
/// （2026-10-29 diff_gate typeck 五案例回归实证后回退，与 gateway 系
/// dir_of 的归一形态有意分叉：gateway 侧候选键经 normalize_path 消费）。
/// 修改须与其余 dump 三包的 dir_of 同步）。
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
    path[0:last].to_owned()
  }
}

///|
fn basename_no_ext(path : String) -> String {
  let mut name = path
  let mut i = path.length() - 1
  while i >= 0 {
    match path[i].to_int() {
      c if c == '/' || c == '\\' => {
        name = path[i + 1:].to_owned()
        break
      }
      c if c == '.' => if name == path { name = path[0:i].to_owned() }
      _ => ()
    }
    i -= 1
  }
  let mut dot : Int32? = None
  let mut k = name.length() - 1
  while k >= 0 {
    if name[k] == '.' {
      dot = Some(k)
      break
    }
    k -= 1
  }
  match dot {
    Some(d) if d > 0 => name[0:d].to_owned()
    _ => name
  }
}

///|
/// IOError 的一行文本（#445 C1：输入不可读原因行——suberror IOError(String)
/// 单字段形态）。四 dump 同形复制件——cmd 层互不可 import。
fn io_error_text(e : @fs.IOError) -> String {
  let IOError(msg) = e
  msg
}

///|
/// 输入不可读的退出决策文案（#445 C1，纯函数——wbtest 锚打此面）：一行
/// 原因 + rc=4 与用法错同档；#230 治理收尾（旧走未捕获 raise 的
/// PanicError 栈 + rc=127，对脚本与 IDE 都是噪声——native 侧子进程锚在
/// scripts/vitro_cli_smoke D 组）。目录模式此面不可达（文件名来自
/// read_dir 快照、collect_files 侧已 catch），单文件模式 typo 路径直达。
fn unreadable_reason(path : String, e : @fs.IOError) -> String {
  "输入不可读：\{path}（\{io_error_text(e)}）"
}

///|
/// 字典序排序（内置 String sort 是**长度优先序**——陷阱 #29；SWEEP1
/// #445 B2 探针实锤：ASCII 域亦分叉〔corpus 1176 文件名内置序 vs 字典序
/// 逐位全异，定向样本 `b.c < aa.c`——长度优先铁证〕，非「非 ASCII 域才
/// 需裁定」）。与 codegen_diff 的 Go sort.Strings 对齐（报告序稳定）；
/// 四 dump 同形复制件——cmd 层互不可 import。
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

///|
/// 递归收集目录下文本文件（含子目录——e2_has_include_nest 形态；不可读项
/// 跳过）。
fn collect_files(dir : String, vfs : Map[String, String]) -> Unit raise {
  for name in @fs.read_dir(dir) {
    let full = vfs_join(dir, name)
    let is_dir = @fs.is_dir(full) catch { _ => false }
    if is_dir {
      collect_files(full, vfs)
    } else {
      let content = @fs.read_file_to_string(full) catch { _ => continue }
      vfs[full] = content
    }
  }
}

///|
/// collect_files 的 VFS 键拼装（PR #380 审阅 P2-1 从内联提取单点锚定）：
/// "." 裸名（与 resolver 候选键 normalize_path 丢 "." 段一致——2026-10-06
/// 审阅 P2-b，旧 "./hdr.h" 键结构性失配致同目录 include 恒 lex-fail）；
/// "/"（dir_of 根级产物）直拼 "/"+name——中段风格拼装会产 "//x.h"，与
/// 候选键经 normalize_path 折叠的 "/x.h" 失配（VfsProvider 纯内存精确
/// 匹配无回落）⇒ 根级 include 恒 E1021；其余 dir+"/"+name 原文（中段
/// 原文透传——与目录模式 VFS 收集键=target 原文同源约束，#378 回归实证）。
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
/// 输入读取单点出口（#445 C1，2026-11-12）：不可读输入（不存在/无权限/
/// 目录形态）→ Err(原因行文案)，main 侧 println + c_exit(4)——与用法错
/// 门禁同构（#230 治理面）。四 dump 壳同义复制件——修改须与其余三家同步。
fn read_input_or_reason(path : String) -> Result[String, String] {
  Ok(
    @fs.read_file_to_string(path) catch {
      IOError(msg) => return Err("输入不可读：\{path}（\{msg}）")
    },
  )
}
