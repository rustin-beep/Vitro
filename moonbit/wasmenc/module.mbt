///|
/// wasm 模块段结构编码（L0 机械件）——探针 `ModuleBuilder` 的 MoonBit
/// 直译（type/memory/global/export/code/data 最小段集；table/elem 按
/// 设计单 §2.1 子集边界不用，start/datacount 同）。
///
/// **import 段预留（PR #495 审阅 P3 勘正——与 templates.mbt 统一）**：
/// 本文件的段原语面不含 import 段（1a 往返不消费），但 CallHost 模板
/// 发射 `call 0`（templates.mbt）依赖装载约定 **函数索引 0 =
/// `env.vitro_host_call(route_id, argv_ptr) -> i64`**（H2 单一 ABI）——
/// 该索引只在模块铺了 import 段（env.vitro_host_call 为唯一 import、
/// 排在 function 段之前）时才成立。批 1c 组装完整模块时**必须**按此
/// 约定铺设 import 段（wasm 索引空间：import 函数先于本模块函数编号），
/// 否则 `call 0` 落到首个本地函数——装载约定两文件以此注为准。
///
/// 段序按 wasm 二进制规范固定：magic+version → type(1) → **import(2)
/// 〔批 1c 起——env.vitro_host_call @ 函数索引 0〕** → function(3) →
/// memory(5) → global(6) → export(7) → code(10) → data(11)。段 id+uleb
/// 长度前缀；vec 元素 uleb 计数前缀。
///
/// **批 1a 职责边界**：本文件只做段结构的字节组装与解析往返（模块级闭环
/// 测试消费）；完整 dispatch-loop 模块组装（入口 main(start_ip)、$steps/
/// $pc/$fb global 约定、data 段铺设、import 段铺设）是批 1b/1c 的发射器
/// 职责——段原语先在位。

///|
/// 函数体（locals 声明 + 指令序列 + 结尾 end）。
#derive(Debug, Eq)
pub(all) struct FuncBody {
  /// (个数, 类型字节) 单元素组展开形（探针 finish() 的简写形态）
  locals : Array[(Int32, Byte)]
  body : Array[WInstr]
}

///|
pub extend FuncBody with Eq::{not_equal, equal}

///|
pub extend FuncBody with Debug::{to_repr}

///|
/// 模块构建器（探针 ModuleBuilder 直译；不去重 type——最小实现口径）。
#derive(Debug)
pub(all) struct ModuleBuilder {
  /// (params, results) 类型表
  types : Array[(Array[Byte], Array[Byte])]
  /// (type_idx) 函数表
  funcs : Array[Int32]
  /// (min, max?) 内存表（max=None → 无上界声明；设计单基线 {16,16}）
  memories : Array[(Int32, Int32?)]
  /// (类型字节, mutable, init 常量)——init 仅支持 i32/f64 常量初始化
  globals : Array[(Byte, Bool, WInstr)]
  /// (名字, kind, idx)——kind: 0=func 1=table 2=memory 3=global（探针坑位 2）
  exports : Array[(String, Int32, Int32)]
  /// 函数体（与 funcs 一一对应）
  codes : Array[FuncBody]
  /// (offset, bytes) active data（memory 0）
  datas : Array[(Int32, Array[Byte])]
}

///|
pub extend ModuleBuilder with Debug::{to_repr}

///|
pub fn ModuleBuilder::new() -> ModuleBuilder {
  {
    types: [],
    funcs: [],
    memories: [],
    globals: [],
    exports: [],
    codes: [],
    datas: [],
  }
}

///|
/// 追加函数类型（返回 type 索引）。
pub fn ModuleBuilder::add_type(
  self : ModuleBuilder,
  params : Array[Byte],
  results : Array[Byte],
) -> Int32 {
  self.types.push((params, results))
  self.types.length() - 1
}

///|
/// 追加函数（type_idx + 体；返回函数索引）。
pub fn ModuleBuilder::add_func(
  self : ModuleBuilder,
  type_idx : Int32,
  body : FuncBody,
) -> Int32 {
  self.funcs.push(type_idx)
  self.codes.push(body)
  self.funcs.length() - 1
}

///|
/// 追加内存声明（min/max 页数）。
pub fn ModuleBuilder::add_memory(
  self : ModuleBuilder,
  min : Int32,
  max : Int32?,
) -> Int32 {
  self.memories.push((min, max))
  self.memories.length() - 1
}

///|
/// 追加可变 global（init 为常量指令）。
pub fn ModuleBuilder::add_global(
  self : ModuleBuilder,
  valtype : Byte,
  mutable : Bool,
  init : WInstr,
) -> Int32 {
  self.globals.push((valtype, mutable, init))
  self.globals.length() - 1
}

///|
/// 追加导出（kind: 0=func 2=memory 3=global）。
pub fn ModuleBuilder::add_export(
  self : ModuleBuilder,
  name : String,
  kind : Int32,
  idx : Int32,
) -> Unit {
  self.exports.push((name, kind, idx))
}

///|
/// 追加 active data 段（memory 0 偏移铺设）。
pub fn ModuleBuilder::add_data(
  self : ModuleBuilder,
  offset : Int32,
  bytes : Array[Byte],
) -> Int32 {
  self.datas.push((offset, bytes))
  self.datas.length() - 1
}

///|
fn section_into(id : Int32, payload : Array[Byte], out : Array[Byte]) -> Unit {
  out.push(id.to_byte())
  for b in uleb_encode(payload.length().to_uint64()) {
    out.push(b)
  }
  for b in payload {
    out.push(b)
  }
}

///|
fn name_le_bytes(s : String) -> Array[Byte] {
  // ASCII 名字（本包导出面名字域：main/steps/memory 等）；非 ASCII 走
  // UTF-8 字节数——仓内 @util.utf8_bytes 已有单源，但引入 String→Bytes
  // 依赖面（util 已 import，直接用）
  let bs = @util.utf8_bytes(s)
  let out : Array[Byte] = []
  for b in uleb_encode(bs.length().to_uint64()) {
    out.push(b)
  }
  // Bytes → Array[Byte] 逐字节拷贝（批 1a 名字域恒短）
  for i = 0; i < bs.length(); i = i + 1 {
    out.push(bs[i])
  }
  out
}

///|
/// 组装完整模块字节（段序：type(1)/function(3)/memory(5)/global(6)/
/// export(7)/code(10)/data(11)——空段不发）。
pub fn ModuleBuilder::build(self : ModuleBuilder) -> Array[Byte] {
  let out : Array[Byte] = [
    (0x00).to_byte(),
    (0x61).to_byte(),
    (0x73).to_byte(),
    (0x6D).to_byte(),
    (0x01).to_byte(),
    (0x00).to_byte(),
    (0x00).to_byte(),
    (0x00).to_byte(),
  ]
  if self.types.length() > 0 {
    let payload : Array[Byte] = []
    for b in uleb_encode(self.types.length().to_uint64()) {
      payload.push(b)
    }
    for entry in self.types {
      payload.push((0x60).to_byte())
      for b in uleb_encode(entry.0.length().to_uint64()) {
        payload.push(b)
      }
      for t in entry.0 {
        payload.push(t)
      }
      for b in uleb_encode(entry.1.length().to_uint64()) {
        payload.push(b)
      }
      for t in entry.1 {
        payload.push(t)
      }
    }
    section_into(1, payload, out)
  }
  if self.funcs.length() > 0 {
    let payload : Array[Byte] = []
    for b in uleb_encode(self.funcs.length().to_uint64()) {
      payload.push(b)
    }
    for ti in self.funcs {
      for b in uleb_encode(ti.to_uint64()) {
        payload.push(b)
      }
    }
    section_into(3, payload, out)
  }
  if self.memories.length() > 0 {
    let payload : Array[Byte] = []
    for b in uleb_encode(self.memories.length().to_uint64()) {
      payload.push(b)
    }
    for m in self.memories {
      match m.1 {
        Some(max) => {
          payload.push((0x01).to_byte())
          for b in uleb_encode(m.0.to_uint64()) {
            payload.push(b)
          }
          for b in uleb_encode(max.to_uint64()) {
            payload.push(b)
          }
        }
        None => {
          payload.push((0x00).to_byte())
          for b in uleb_encode(m.0.to_uint64()) {
            payload.push(b)
          }
        }
      }
    }
    section_into(5, payload, out)
  }
  if self.globals.length() > 0 {
    let payload : Array[Byte] = []
    for b in uleb_encode(self.globals.length().to_uint64()) {
      payload.push(b)
    }
    for g in self.globals {
      payload.push(g.0)
      payload.push((if g.1 { 0x01 } else { 0x00 }).to_byte())
      winstr_encode_into(g.2, payload)
      payload.push((0x0B).to_byte()) // init 表达式结尾 end
    }
    section_into(6, payload, out)
  }
  if self.exports.length() > 0 {
    let payload : Array[Byte] = []
    for b in uleb_encode(self.exports.length().to_uint64()) {
      payload.push(b)
    }
    for e in self.exports {
      for b in name_le_bytes(e.0) {
        payload.push(b)
      }
      payload.push(e.1.to_byte())
      for b in uleb_encode(e.2.to_uint64()) {
        payload.push(b)
      }
    }
    section_into(7, payload, out)
  }
  if self.codes.length() > 0 {
    let payload : Array[Byte] = []
    for b in uleb_encode(self.codes.length().to_uint64()) {
      payload.push(b)
    }
    for body in self.codes {
      let entry : Array[Byte] = []
      for b in uleb_encode(body.locals.length().to_uint64()) {
        entry.push(b)
      }
      for l in body.locals {
        for b in uleb_encode(l.0.to_uint64()) {
          entry.push(b)
        }
        entry.push(l.1)
      }
      for instr in body.body {
        winstr_encode_into(instr, entry)
      }
      entry.push((0x0B).to_byte()) // 函数体结尾 end
      for b in uleb_encode(entry.length().to_uint64()) {
        payload.push(b)
      }
      for b in entry {
        payload.push(b)
      }
    }
    section_into(10, payload, out)
  }
  if self.datas.length() > 0 {
    let payload : Array[Byte] = []
    for b in uleb_encode(self.datas.length().to_uint64()) {
      payload.push(b)
    }
    for d in self.datas {
      payload.push((0x00).to_byte()) // active, memory 0
      winstr_encode_into(WI32Const(d.0), payload)
      payload.push((0x0B).to_byte()) // offset 表达式 end
      for b in uleb_encode(d.1.length().to_uint64()) {
        payload.push(b)
      }
      for by in d.1 {
        payload.push(by)
      }
    }
    section_into(11, payload, out)
  }
  out
}

///|
/// 模块级解析错误（段结构对账用——批 1a 只解析到 code 段体提取，
/// 供「模块封装 → 段解析 → 折叠往返」闭环）。
#derive(Debug)
pub(all) enum ModuleParseError {
  BadMagic
  BadVersion
  /// 段长越过模块尾（探针坑位 3——段 size 虚报 extends past end）
  SectionOverrun(Int32)
  /// 段内计数与段长不符 / 结构损坏
  Malformed(Int32)
  /// code 段外的非预期段 id（本解析器面：1/3/5/6/7/10/11）
  UnexpectedSection(Int32)
}

///|
pub extend ModuleParseError with Debug::{to_repr}

///|
/// 解析出的函数体（code 段第 0 个条目——批 1a 闭环用单函数模块）。
pub fn parse_first_code_body(
  bytes : Array[Byte],
) -> Result[Array[WInstr], ModuleParseError] {
  if bytes.length() < 8 {
    return Err(BadMagic)
  }
  if bytes[0] != 0x00 ||
    bytes[1] != 0x61 ||
    bytes[2] != 0x73 ||
    bytes[3] != 0x6D {
    return Err(BadMagic)
  }
  if bytes[4] != 0x01 ||
    bytes[5] != 0x00 ||
    bytes[6] != 0x00 ||
    bytes[7] != 0x00 {
    return Err(BadVersion)
  }
  let mut pos = 8
  let mut code_body : Array[WInstr]? = None
  while pos < bytes.length() {
    let sec_id = bytes[pos].to_int()
    let sec_pos = pos
    pos = pos + 1
    let (sec_len, n) = match uleb_decode(bytes, pos) {
      Ok((v, n)) => (v.to_int(), n)
      Err(_) => return Err(Malformed(sec_pos))
    }
    pos = pos + n
    let sec_end = pos + sec_len
    if sec_end > bytes.length() {
      return Err(SectionOverrun(sec_pos))
    }
    match sec_id {
      10 => {
        // code 段：vec 计数 + (size, body)*——取第 0 个 body
        let (count, cn) = match uleb_decode(bytes, pos) {
          Ok((v, n)) => (v.to_int(), n)
          Err(_) => return Err(Malformed(sec_pos))
        }
        if count < 1 {
          return Err(Malformed(sec_pos))
        }
        pos = pos + cn
        let (body_size, bn) = match uleb_decode(bytes, pos) {
          Ok((v, n)) => (v.to_int(), n)
          Err(_) => return Err(Malformed(sec_pos))
        }
        pos = pos + bn
        let body_end = pos + body_size
        if body_end > sec_end {
          return Err(Malformed(sec_pos))
        }
        // locals 声明组
        let (n_groups, gn) = match uleb_decode(bytes, pos) {
          Ok((v, n)) => (v.to_int(), n)
          Err(_) => return Err(Malformed(sec_pos))
        }
        pos = pos + gn
        for _k = 0; _k < n_groups; _k = _k + 1 {
          let (_, cnt_n) = match uleb_decode(bytes, pos) {
            Ok((v, n)) => (v.to_int(), n)
            Err(_) => return Err(Malformed(sec_pos))
          }
          pos = pos + cnt_n + 1 // (count uleb, 一个类型字节)
        }
        // 指令序列到 body 尾（含结尾 end）
        let instrs : Array[WInstr] = []
        while pos < body_end {
          match winstr_decode(bytes, pos) {
            Ok((instr, consumed)) => {
              instrs.push(instr)
              pos = pos + consumed
            }
            Err(_) => return Err(Malformed(sec_pos))
          }
        }
        // body 边界 fail loud（PR #493 审阅 P2）：末条指令消费数越过
        // body 界（sleb 续位跨界读段内字节，解码"成功"但越权）或末条
        // 非 end（合法 wasm 函数体必以 end 收尾——空指令流同罪）一律
        // Malformed 拒载，不让装载器把「非自家产物」误信为自家产物
        if pos != body_end {
          return Err(Malformed(sec_pos))
        }
        if instrs.length() == 0 {
          return Err(Malformed(sec_pos))
        }
        match instrs[instrs.length() - 1] {
          WEnd => ()
          _ => return Err(Malformed(sec_pos))
        }
        code_body = Some(instrs)
      }
      1 | 3 | 5 | 6 | 7 | 11 => pos = sec_end // 跳过（批 1a 不解析内容）
      _ => return Err(UnexpectedSection(sec_pos))
    }
    pos = sec_end
    match code_body {
      Some(_) => break // 只取首个 code 段即返
      None => ()
    }
  }
  match code_body {
    Some(instrs) => Ok(instrs)
    None => Err(Malformed(bytes.length()))
  }
}
