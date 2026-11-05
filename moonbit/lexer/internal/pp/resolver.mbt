///|
/// include 嵌套深度上限（U1#11）：静态环检测 DFS 的深度封顶与动态拼接的
/// 嵌套深度保险丝**共用**此值（两个口径分叉会重演"保险丝口径错"失效形态）。
/// 量级对齐 clang `-fmax-include-depth=200` 的教学压缩。
const MAX_INCLUDE_DEPTH : Int32 = 64

///|
/// 静态环检测 DFS 的访问节点数封顶（U1#11）：防病态依赖图拖垮编译；
/// 覆盖教学项目级头文件群（20 文件环实测检出）。
const MAX_INCLUDE_GRAPH_NODES : Int32 = 512

///|
/// quote-include 候选链：当前文件目录（include 栈顶）→ 源文件目录（base_dir）。
/// 路径规范化为 `/` 分隔（VFS 语义纯字符串；差分驱动喂数统一正斜杠）。
/// #373 审阅 P2-2（2026-10-29）：**绝对路径操作数直接取**（C11 §6.10.2p3
/// ——clang/gcc 对 `#include "/abs/h.h"` 不走候选链搜索），不与
/// cur_dir/base_dir 拼接。
fn[P : @token.SourceProvider] Pp::resolve_path(
  self : Pp[P],
  path : String,
) -> String? {
  if path.length() > 0 && path[0] == '/' {
    let abs = normalize_path(path)
    match self.try_read(abs) {
      Some(_) => return Some(abs)
      None => return None
    }
  }
  let cur_dir : String = if self.include_stack.length() > 0 {
    self.include_stack[self.include_stack.length() - 1].dir
  } else {
    self.base_dir
  }
  if cur_dir != "" {
    let full = normalize_path(cur_dir + "/" + path)
    match self.try_read(full) {
      Some(_) => return Some(full)
      None => ()
    }
  }
  if self.base_dir != "" {
    let full = normalize_path(self.base_dir + "/" + path)
    match self.try_read(full) {
      Some(_) => return Some(full)
      None => ()
    }
  }
  None
}

///|
/// 试读（NotFound/UnsupportedHost 均为未命中；内容进缓存）。
fn[P : @token.SourceProvider] Pp::try_read(
  self : Pp[P],
  path : String,
) -> String? {
  if self.content_cache.contains(path) {
    return self.content_cache.get(path)
  }
  let content = self.provider.read(path) catch { _ => return None }
  self.content_cache[path] = content
  Some(content)
}

///|
/// 缓存读取（include 实际拼接用——与环检测/候选链共用一次读取）。
fn[P : @token.SourceProvider] Pp::read_cached(
  self : Pp[P],
  path : String,
) -> String? {
  self.try_read(path)
}

///|
/// 路径规范化：折叠 `//`、`.`；`..` 回退一层（超出根不回退——VFS 近似）。
/// #356（2026-10-29）：POSIX 绝对锚保留——前导 `/` 不随空段丢弃（修前
/// "/home/x/h.h" → "home/x/h.h"，绝对路径主文件的 quote-include 候选键
/// 与 reader/VFS 侧保留前导 `/` 的键永不相等 ⇒ Linux 宿主 100% E1021；
/// 普通 Windows 盘符路径首段 "D:" 非空本就不丢——绝对性由本锚显式保护，
/// 与普通盘符形态对称；越根例外（`D:/..` 的盘符段可被 `..` 弹掉、
/// `normalize_path("D:/..") == ""`——既有近似，修前修后一致）。
/// `..` 回退到根时锚不丢（"/a/../b.h" → "/b.h"）。
fn normalize_path(p : String) -> String {
  let abs = p.length() > 0 && p[0] == '/'
  let parts : Array[String] = []
  for seg in p.split("/") {
    match seg {
      "" | "." => ()
      ".." => if parts.length() > 0 { ignore(parts.pop()) }
      _ => parts.push(seg.to_owned())
    }
  }
  let joined = parts.join("/")
  if abs {
    "/" + joined
  } else {
    joined
  }
}

///|
/// 静态依赖环检测：从 `start_key`（规范路径）出发沿自定义头文件的
/// `#include "..."` 边 DFS；回到起点即返回环描述 `a.h -> b.h -> a.h`。
/// **visited 路径局部**（勘察 M2 修复：Rust 的 visited 从不移除，菱形依赖下
/// 漏报环——`visited.insert` 后在返回前撤销）。深度/规模双封顶。
fn[P : @token.SourceProvider] Pp::detect_cycle(
  self : Pp[P],
  start_key : String,
) -> String? {
  let visited : Array[String] = []
  self.walk_cycle(start_key, start_key, visited, 0)
}

///|
fn[P : @token.SourceProvider] Pp::walk_cycle(
  self : Pp[P],
  full : String,
  start_key : String,
  visited : Array[String],
  depth : Int32,
) -> String? {
  // DIFF-PREPROC-INCLUDE-DEPTH-01 终局（2026-10-05 批一曾改报环诊断，
  // 同日审阅 P2-2 修正回 None）：静态 DFS 封顶时**无法区分深环与无环深链**
  //（DFS 不完整即止）——报「依赖环」对无环深链是错误归因（Clang 对两形态
  // 统一报 `#include nested too deeply`，两侧拦截口径一致；归因正确的
  // 报点 = 动态保险丝「嵌套过深」，深环深链同由它承担）。visited.length()
  // 封顶与 depth 封顶在此实现下恒同时触发（路径局部栈 depth==length），
  // 保留双判据作防御性形态
  if depth > MAX_INCLUDE_DEPTH || visited.length() > MAX_INCLUDE_GRAPH_NODES {
    return None
  }
  if full == start_key && depth > 0 {
    // 守卫感知（stb 自 include 修复，2026-10-05）：回到起点的边不再一律
    // 判环——环上（visited = 当前 DFS 路径，即环经过的全部文件）任一
    // 文件带 include 守卫（#ifndef X + 同名 #define X）时，C 语义下环的
    // 有序展开中首个带守卫文件二次展开为空、递归断链，不会爆深
    //（include-once 终点；GCC/Clang 均支持，stb_image.h 自 include 同款；
    // 起点本身无守卫但环上他文件带守卫的互环同样终止）。环上全部无守卫
    // 才是真环（每圈 body 完整重复进入文本流，Clang 下
    // -fmax-include-depth 爆深 fatal——E1015 教学化提前拦截口径不变）。
    // 动态展开侧由 processed 集合（守卫语义内置）跳过重复 include 兜底
    let mut guarded = false
    for v in visited {
      match self.try_read(v) {
        Some(t) =>
          if has_include_guard(t) {
            guarded = true
            break
          }
        None => ()
      }
    }
    if guarded {
      return None
    }
    return Some("") // 回到起点（环闭合）——由调用链拼描述
  }
  if visited.contains(full) {
    return None
  }
  visited.push(full) // 路径局部：返回前撤销（修复 M2 菱形漏报）
  let text = match self.try_read(full) {
    Some(t) => t
    None => {
      ignore(visited.pop())
      return None
    }
  }
  let dir = dirname_of(full)
  let mut result : String? = None
  for dep in custom_includes_of(text) {
    // 相对"当前头文件目录"解析（与 quote-include 候选链一致），未命中跳过
    let dep_full : String? = if dir != "" {
      Some(normalize_path(dir + "/" + dep))
    } else {
      None
    }
    let dep_resolved = match dep_full {
      Some(f) =>
        if self.try_read(f) is Some(_) {
          Some(f)
        } else {
          self.resolve_path(dep)
        }
      None => self.resolve_path(dep)
    }
    match dep_resolved {
      Some(f) =>
        match self.walk_cycle(f, start_key, visited, depth + 1) {
          Some(rest) => {
            // 环闭合沿调用链向上拼接描述（路径分隔符跨平台，不做启发过滤）
            let desc = if rest == "" { dep } else { "\{dep} -> \{rest}" }
            result = Some(desc)
            break
          }
          None => ()
        }
      None => ()
    }
  }
  ignore(visited.pop())
  result
}

///|
/// 环检测/守卫检测共用的轻量行预处理（#432 A2/A3，2026-11-04；PR #481
/// 审阅 P1/P2 2026-11-05 组栈化重写）：物理行拆分 → `\` 续行拼接 →
/// 注释剥离（直接复用主管线 strip_comments_stateful——字符串感知、
/// 跨行块注释态）→ 轻量条件组栈。真值（Win/WSL gcc+clang -E 一致）：
/// 注释内与非激活分支内的 `#include` 不是依赖边——旧 custom_includes_of /
/// has_include_guard 对原始文本逐行扫描，注释与假分支内的 include 被当
/// 真边（E1015 依赖环误报拒编译）。
/// 条件求值口径（教学子集轻量版——只求值数字字面量，拿不到宏表）：
/// ①`#if 0`（归一后参数恰为 "0"）开假组；`#if <非零数字>` 开真组；
/// ②`#ifdef`/`#ifndef`/其余 `#if` 表达式无法求值——**保守按真**（出边）：
/// 漏报环 = 接受 clang 明确拒绝的程序（fail-open），比误报更坏（PR #481
/// 审阅 P1 拍板——旧版「#elif 维持跳过」即此症：`#if 0 … #elif 1` 分支
/// 内的自环 include 被整段丢弃，环检测失效）；
/// ③`#elif <arg>`：组内未 taken——arg=="0" 维持假，非零数字或不可求值
/// → 激活并 taken；已 taken → 本分支假（`#if 0/#elif 1/#else` 的 else
/// 假分支行不出流——两态跳过/不跳治不了，须组栈）；
/// ④`#else`：组内未 taken → 激活；已 taken → 假；
/// ⑤父组假时嵌套组整体不可达（压哨恒假组）；未闭合组行假到尾
/// （病态头文件由主管线 E1013 fail loud，此处只求保守）。
/// 指令行归一：`#` 与指令名间允许空白（C 标准；PR #481 审阅 P2——
/// `#  if 0` 形态曾因未归一漏检）。
fn preprocessed_lines(text : String) -> Array[String] {
  let physical = split_physical_lines(text, 0)
  let logical = splice_continuations(physical)
  let stripped = strip_comments_stateful(logical)
  let lines : Array[String] = []
  for l in stripped.lines {
    lines.push(l.text)
  }
  let out : Array[String] = []
  // (active, taken) 组栈：active=当前分支行出流；taken=组内已有分支激活过
  let stack : Array[(Bool, Bool)] = []
  for line in lines {
    let t = leading_trim(line)
    if t.length() > 0 && t[0].to_int() == '#' {
      let norm = "#" + leading_trim(t[1:].to_owned())
      let name = directive_name_of(norm)
      let arg = trailing_trim(leading_trim(norm[name.length() + 1:].to_owned()))
      let mut parent_off = false
      for s in stack {
        if !s.0 {
          parent_off = true
          break
        }
      }
      match name {
        "if" | "ifdef" | "ifndef" =>
          if parent_off {
            stack.push((false, true)) // 父组假：嵌套组不可达（taken=true 防后续激活）
          } else if name == "if" && arg == "0" {
            stack.push((false, false))
          } else {
            // #if 非零数字 / ifdef·ifndef·复杂表达式不可求值 → 保守按真
            stack.push((true, true))
          }
        "elif" =>
          if stack.length() > 0 {
            let top = stack[stack.length() - 1]
            if top.1 {
              stack[stack.length() - 1] = (false, top.1) // 已 taken：本分支假
            } else if arg == "0" {
              () // 维持 (false, false)
            } else {
              // 非零数字或不可求值 → 激活（fail-closed 方向，PR #481 审阅 P1）
              stack[stack.length() - 1] = (true, true)
            }
          }
        "else" =>
          if stack.length() > 0 {
            let top = stack[stack.length() - 1]
            if !top.1 {
              stack[stack.length() - 1] = (true, true)
            } else {
              stack[stack.length() - 1] = (false, top.1)
            }
          }
        "endif" => if stack.length() > 0 { ignore(stack.pop()) }
        _ => ()
      }
    }
    // 普通行与条件指令行统一组态过滤：任一组当前假 → 跳过（条件指令行
    // 同此规则——激活组内的 `#ifndef X` 行保留出流，守卫检测
    // has_include_guard 依赖它识别「#ifndef X + 同名 #define」守卫对；
    // 假组内的指令行随组吞掉，死代码里的守卫对不计）
    let mut off = false
    for s in stack {
      if !s.0 {
        off = true
        break
      }
    }
    if off {
      continue
    }
    out.push(line)
  }
  out
}

///|
/// 指令名提取（`#`-开头行 → 不含 `#` 的指令名）。**先归一**：`#` 与
/// 指令名间的空白剥除后扫描字母/下划线段（与 handle_directive 消费
/// leading_trim 后 rest 的首段扫描同形——PR #481 审阅 P2：初版直接从
/// `t[1]` 扫，`#  if 0` 形态漏检）。
fn directive_name_of(t : String) -> String {
  let s = leading_trim(t[1:].to_owned())
  let mut n = 0
  while n < s.length() {
    let c = s[n].to_int()
    if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' {
      n += 1
    } else {
      break
    }
  }
  s[0:n].to_owned()
}

///|
/// 提取头文件文本中的自定义 `#include "..."` 依赖（`<...>` 存根不算依赖边）。
/// #432 A2/A3：消费轻量预处理产物（注释剥离 + `#if 0` 条件态）——
/// 旧逐行文本扫描把注释内/`#if 0` 块内的 include 当真边（E1015 误报）。
fn custom_includes_of(text : String) -> Array[String] {
  let out : Array[String] = []
  for line_raw in preprocessed_lines(text) {
    let t = leading_trim(line_raw)
    if t.length() == 0 || t[0].to_int() != '#' {
      continue
    }
    let rest = leading_trim(t[1:].to_owned())
    if !rest_starts_with_include(rest) {
      continue
    }
    let inc_after = leading_trim(rest[7:].to_owned())
    if inc_after.length() > 0 && inc_after[0].to_int() == '"' {
      let mut i = 1
      while i < inc_after.length() {
        if inc_after[i].to_int() == '"' {
          out.push(inc_after[1:i].to_owned())
          break
        }
        i += 1
      }
    }
  }
  out
}

///|
fn rest_starts_with_include(rest : String) -> Bool {
  rest.length() >= 7 && rest[0:7] == "include"
}

///|
/// include 守卫形态检测（静态近似）：文件内首个 `#ifndef X` 指令之后
/// 出现同名 `#define X` 指令即认为有守卫——stb 等自 include 库的标准
/// 模式（二次展开为空）。近似口径：不校验 #endif 配对与守卫覆盖全文
///（教学语料域误判面可忽略）；嵌套条件块内的同名对按「存在即有守卫」
/// 从宽——漏检方向（把守卫环仍判真环）回到修复前行为，误检方向需
/// `#ifndef X` 与同名 `#define X` 恰好成对散布，语料域无此形态。
fn has_include_guard(text : String) -> Bool {
  let mut pending : String? = None
  // #432 A2/A3：与 custom_includes_of 共用轻量预处理——注释/`#if 0`
  // 块内的 #ifndef/#define 对不得误判守卫（同根因误检面）
  for line_raw in preprocessed_lines(text) {
    let t = leading_trim(line_raw)
    match pending {
      None =>
        if t.length() > 8 && t[0:8] == "#ifndef " {
          let name = macro_name_of(leading_trim(t[8:].to_owned()))
          if name.length() > 0 {
            pending = Some(name)
          }
        }
      Some(g) =>
        if t.length() > 8 && t[0:8] == "#define " {
          if macro_name_of(leading_trim(t[8:].to_owned())) == g {
            return true
          }
        }
    }
  }
  false
}

///|
/// 宏名提取：`[A-Za-z0-9_]+` 前缀段（到首个其余字符截止——
/// `#define GA_H2` 不误匹配守卫名 `GA_H`）。
fn macro_name_of(s : String) -> String {
  let mut i = 0
  while i < s.length() {
    let c = s[i].to_int()
    let is_name_char = c == 95 ||
      (c >= 48 && c <= 57) ||
      (c >= 65 && c <= 90) ||
      (c >= 97 && c <= 122)
    if !is_name_char {
      break
    }
    i += 1
  }
  s[0:i].to_owned()
}
