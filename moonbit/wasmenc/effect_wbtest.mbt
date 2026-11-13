///|
/// **效应推导对拍锚（REHOST 批 2a）**——`seq_net_effect`（WInstr 穷尽
/// match 的栈模拟）↔ 人工核对表（`witness_effect_rows`/`witness_a_rows`
/// 共 150 行——wabt wat 编译合法性背书的垫收快照）逐行对拍。双保险：
/// 人工表经 watcheck wat 对拍证「值正确」，推导器经本锚证「与表一致」
/// ——组装层（assemble.mbt）消费推导器（新增 opcode 自动连坐），人工表
/// 继续作 wat 证人对。J9 证红：改表任一行（如 PushConst 的 ""→"i"）即红
/// 〔2026-11-13 亲证〕。
test "effect_sim_matches_witness_table" {
  let ctx = witness_ctx()
  let all : Array[(@opcode.OpCode, Int32, String, Int32)] = []
  for row in witness_effect_rows() {
    all.push(row)
  }
  for row in witness_a_rows() {
    all.push(row)
  }
  for row in all {
    let (op, operand, pushes, drops) = row
    match template_net_effect(op, operand, ctx) {
      Ok((pad, residual)) => {
        // 类型串 → 字节串（i=I32 I=I64 f=F32 d=F64——witness 表型约定）
        let want : Array[Byte] = []
        for ch in pushes {
          match ch {
            'i' => want.push(WT_I32)
            'I' => want.push(WT_I64)
            'f' => want.push(WT_F32)
            _ => want.push(WT_F64)
          }
        }
        assert_eq(
          pad,
          want,
          msg="\{op.name()}(\{operand}) 前垫串：推导 \{hex_types(pad)} vs 人工 \"\{pushes}\"",
        )
        assert_eq(
          residual,
          drops,
          msg="\{op.name()}(\{operand}) 尾剩余：推导 \{residual} vs 人工 \{drops}",
        )
      }
      Err(e) =>
        fail(
          "\{op.name()}(\{operand}) 效应推导失败：\{effect_err_text(e)}",
        )
    }
  }
}

///|
/// 前垫类型串的调试渲染（断言消息用）。
fn hex_types(ts : Array[Byte]) -> String {
  let mut s = ""
  for t in ts {
    s = s +
      (if t == WT_I32 {
        "i"
      } else if t == WT_I64 {
        "I"
      } else if t == WT_F32 {
        "f"
      } else {
        "d"
      })
  }
  s
}

///|
/// **全可发射面推导成功锚**——新增 opcode（四态计数锚红）后模板进表，
/// 本锚保证「每个可发射 opcode 的模板都能被模拟器推导」（效应面与发射
/// 面同步——推导器不认识新模板的指令形态时在此红，而非装载期才炸）。
test "effect_sim_covers_all_emissive_ops" {
  let ctx = witness_ctx()
  let mut emissive = 0
  for code = 0; code <= 255; code = code + 1 {
    match @opcode.OpCode::from_u8(code) {
      Some(op) => {
        let spec = template_spec(op)
        if spec.state is Exact ||
          spec.state is Composed ||
          spec.state is Ambiguous {
          // operand 取 0（槽位类样值不影响结构效应——效应是结构性的）
          match template_net_effect(op, 0, ctx) {
            Ok(_) => emissive = emissive + 1
            Err(e) =>
              fail(
                "\{op.name()} 可发射但效应推导失败：\{effect_err_text(e)}",
              )
          }
        }
      }
      None => ()
    }
  }
  // 147 = 84 Exact + 50 Composed + 13 Ambiguous（anchors_wbtest 四态计数
  // 同源——改模板分类时两锚同红）
  assert_eq(emissive, 147, msg="可发射面效应推导全覆盖")
}

///|
/// **组装产物结构锚（REHOST 批 2a）**——`assemble_witness_module` 的
/// 段序/装载约定镜像/垫收形态：
/// 1. 段 id 序列 == type(1) import(2) function(3) memory(5) global(6)
///    export(7) code(10)（wasm 规范段序——本组装器面内全段齐发）；
/// 2. import 段 = 唯一 `env.vitro_host_call`（H2 单一 ABI @ 函数索引 0）；
/// 3. 单组程序（PushConst 8）的 code 体 = `block + (组指令) + drop + end
///    + 尾 end`（前垫空/尾剩余 1 的最小组）；
/// 4. 组表覆盖完整性：边界越界/未覆盖 fail loud。
test "assemble_witness_module_structure" {
  let ctx = witness_ctx()
  // 单组程序：PushConst(8) → 效应 ("", 1)
  let (table, bytes) = match
    build_group_table([(PushConst, 8, @source.SourceLoc::new(1, 1))], ctx) {
    Ok(t) => t
    Err(e) => fail("单组建表失败：\{emit_err_text(e)}")
  }
  let mod_bytes = match assemble_witness_module(table, bytes) {
    Ok(m) => m
    Err(e) => fail("单组组装失败：\{assemble_err_text(e)}")
  }
  // 1. 段序扫描（uleb 长度跳段——段 id 序列断言）
  let seg_ids : Array[Int32] = []
  scan_section_ids(mod_bytes, seg_ids)
  assert_eq(seg_ids, [1, 2, 3, 5, 6, 7, 10], msg="段序 = 规范全段")
  // 2. import 段字节镜像：env.vitro_host_call + kind 0 + type_idx 1
  let import_seg = extract_section(mod_bytes, 2)
  // 段体 = vec(1) + "env" + "vitro_host_call" + kind(0) + type_idx(1)
  let env_name = "env".to_array()
  let host_name = "vitro_host_call".to_array()
  let expect : Array[Byte] = []
  expect.push(1) // vec 计数
  expect.push(env_name.length().to_byte())
  for ch in env_name {
    expect.push(Char::to_int(ch).to_byte())
  }
  expect.push(host_name.length().to_byte())
  for ch in host_name {
    expect.push(Char::to_int(ch).to_byte())
  }
  expect.push(0) // kind = func
  expect.push(1) // type_idx = 1 ((i32,i32)->i64)
  assert_eq(
    import_seg,
    expect,
    msg="import 段 = env.vitro_host_call func@type1",
  )
  // 3. code 体断言：locals(4 runs) + block(02 40) + PushConst 模板字节
  //    (i32.const 8 = 41 08) + drop(1a) + end(0b) + 函数尾 end(0b)
  let code_seg = extract_section(mod_bytes, 10)
  // code 段体 = vec(1) + body_size(uleb) + body
  let body : Array[Byte] = []
  body.push(4) // locals 4 runs
  body.push(3)
  body.push(WT_I32)
  body.push(1)
  body.push(WT_I64)
  body.push(1)
  body.push(WT_F64)
  body.push(1)
  body.push(WT_F32)
  body.push(0x02)
  body.push(WT_VOID) // block void
  body.push(0x41)
  body.push(0x08) // i32.const 8
  body.push(0x1a) // drop
  body.push(0x0b) // 组 end
  body.push(0x0b) // 函数尾 end
  let want_code : Array[Byte] = [1]
  let body_hex = uleb_bytes(body.length())
  for b in body_hex {
    want_code.push(b)
  }
  for b in body {
    want_code.push(b)
  }
  assert_eq(code_seg, want_code, msg="code 段 = locals + 垫收组 + 尾 end")
}

///|
/// **组装 fail loud 锚**——组表覆盖不完整/边界越界必须拒载（装载协议
/// 独立防线——verify 先行时恒绿，本锚证组装自身有牙）。
test "assemble_witness_module_fail_loud" {
  let ctx = witness_ctx()
  let (table, bytes) = match
    build_group_table(
      [
        (PushConst, 8, @source.SourceLoc::new(1, 1)),
        (Pop, 0, @source.SourceLoc::new(1, 1)),
      ],
      ctx,
    ) {
    Ok(t) => t
    Err(e) => fail("两组建表失败：\{emit_err_text(e)}")
  }
  // 边界越界：组 1 的 instr_len 拔高到流外（GroupEntry 字段不可变——重建）
  let g0 = table.groups[0]
  let g1 = table.groups[1]
  let bad : GroupTable = {
    groups: [
      g0,
      {
        gip: g1.gip,
        op: g1.op,
        operand: g1.operand,
        instr_offset: g1.instr_offset,
        instr_len: 99,
        loc_line: g1.loc_line,
        loc_column: g1.loc_column,
        loc_file_id: g1.loc_file_id,
      },
    ],
  }
  match assemble_witness_module(bad, bytes) {
    Ok(_) => fail("边界越界未拒载")
    Err(BadBoundary(_, _, _)) => ()
    Err(e) =>
      fail("边界越界给出了别的错误：\{assemble_err_text(e)}")
  }
  // 覆盖不完整：删首组（instr_offset 从 1 起——NotCovered）
  let holed : GroupTable = { groups: [], }
  for i = 1; i < table.groups.length(); i = i + 1 {
    holed.groups.push(table.groups[i])
  }
  match assemble_witness_module(holed, bytes) {
    Ok(_) => fail("组表缺口未拒载")
    Err(NotCovered(_, _)) => ()
    Err(e) =>
      fail("组表缺口给出了别的错误：\{assemble_err_text(e)}")
  }
  // 空组表 + 空字节 = 合法最小模块（空程序面——不拒载）
  match assemble_witness_module(GroupTable::new(), []) {
    Ok(_) => ()
    Err(e) => fail("空程序不该拒载：\{assemble_err_text(e)}")
  }
}

///|
/// 段 id 扫描（uleb 长度跳段——结构锚用；非法长度返回即断言自然红）。
fn scan_section_ids(bytes : Array[Byte], out : Array[Int32]) -> Unit {
  let mut pos = 8 // magic+version
  while pos < bytes.length() {
    let id = bytes[pos].to_int()
    out.push(id)
    let (size, hdr) = uleb_at(bytes, pos + 1)
    pos = pos + 1 + hdr + size
  }
}

///|
/// 取段体字节（无该段返回空——结构锚断言自然红）。
fn extract_section(bytes : Array[Byte], want_id : Int32) -> Array[Byte] {
  let mut pos = 8
  while pos < bytes.length() {
    let id = bytes[pos].to_int()
    let (size, hdr) = uleb_at(bytes, pos + 1)
    if id == want_id {
      let out : Array[Byte] = []
      for k = 0; k < size; k = k + 1 {
        out.push(bytes[pos + 1 + hdr + k])
      }
      return out
    }
    pos = pos + 1 + hdr + size
  }
  []
}

///|
/// uleb 读回（值, 头长）——结构锚用。
fn uleb_at(bytes : Array[Byte], pos : Int32) -> (Int32, Int32) {
  let mut value : Int32 = 0
  let mut shift : Int32 = 0
  let mut i = pos
  let mut n : Int32 = 0
  while i < bytes.length() {
    let b = bytes[i].to_uint() & 0xFFU
    n = n + 1
    value = value | ((b & 0x7FU).reinterpret_as_int() << shift)
    i = i + 1
    if (b & 0x80U) == 0U {
      break
    }
    shift = shift + 7
  }
  (value, n)
}

///|
/// uleb 编码（结构锚期望字节用——与 leb128.mbt 同算法的测试侧复刻，
/// 断言消费非生产消费）。
fn uleb_bytes(n : Int32) -> Array[Byte] {
  let out : Array[Byte] = []
  let mut v = n.reinterpret_as_uint()
  let mut go = true
  while go {
    let b = v & 0x7FU
    v = v >> 7
    if v != 0U {
      out.push((b | 0x80U).reinterpret_as_int().to_byte())
    } else {
      out.push(b.reinterpret_as_int().to_byte())
      go = false
    }
  }
  out
}

///|
/// 错误文本化（断言消息用——EffectError/AssembleError/EmitError 无 Show，
/// 分臂渲染；AssembleError::Decode 内嵌 DecodeError 只带偏移）。
fn effect_err_text(e : EffectError) -> String {
  match e {
    TypeMismatch(at, want, got) =>
      "TypeMismatch @\{at} want=0x\{want.to_int()} got=0x\{got.to_int()}"
    BadBrDepth(at, d, n) => "BadBrDepth @\{at} d=\{d} frames=\{n}"
    BadSlot(at, i) => "BadSlot @\{at} idx=\{i}"
    BadCallIdx(at, n) => "BadCallIdx @\{at} idx=\{n}"
  }
}

///|
fn assemble_err_text(e : AssembleError) -> String {
  match e {
    Decode(off, _) => "Decode @\{off}"
    BadBoundary(gip, off, len) => "BadBoundary gip=\{gip} off=\{off} len=\{len}"
    NotCovered(want, got) => "NotCovered expect=\{want} got=\{got}"
    Effect(inner) => "Effect(\{effect_err_text(inner)})"
  }
}

///|
fn emit_err_text(e : EmitError) -> String {
  match e {
    NotImplemented(s) => "NotImplemented: \{s}"
    BadOperand(s) => "BadOperand: \{s}"
  }
}
