// 蓝本注记：文内 Rust 源引用（`*.rs` 路径/行号/符号）均为档案态蓝本——tag rust-oracle-freeze（2026-10-05 删区），现为本仓自主基线。

///| L7 执行层·VM 域·executor：**栈 / 局部 / 全局族**（Rust
/// `executor/stack.rs` + `executor/memory.rs` 的 execute_global 段照搬）。
///
/// 局部变量在线性内存（`locals_base + operand` 编址）；变量名取
/// 装载期派生索引（`locals_by_func`〔按当前帧函数名〕/ `global_syms`——
/// 批一号的坑 12 结构性消除，Rust 侧是 `local_sym_map`/`global_sym_map`
/// 常驻索引），缺名回退 `local_{n}`/`global_{n}` 同款。

///|
/// 栈顶操作族（PushConst / PushArgc / PushArgv / Pop / Dup / Swap）。
fn VitroVM::execute_stack(
  self : VitroVM,
  op : @opcode.OpCode,
  operand : Int32,
  line : Int32,
  column : Int32,
) -> Unit {
  match op {
    PushConst => self.push_i32(operand)
    PushArgc => self.push_i32(self.argc)
    PushArgv => self.push(self.argv_addr.to_uint64())
    Pop => {
      let _ = self.pop()
    }
    Dup =>
      if self.stack.length() > 0 {
        self.push(self.stack[self.stack.length() - 1])
      } else {
        self.trap("Dup: 栈空", line, column)
      }
    Swap => {
      let len = self.stack.length()
      if len >= 2 {
        let tmp = self.stack[len - 1]
        self.stack[len - 1] = self.stack[len - 2]
        self.stack[len - 2] = tmp
      } else {
        self.trap("Swap: 栈不足", line, column)
      }
    }
    _ => ()
  }
}

///|
/// 当前帧局部变量名（派生索引；缺名回退——Rust `local_{n}` 同款）。
fn VitroVM::local_var_name(self : VitroVM, offset : Int32) -> String {
  if self.call_stack.length() > 0 {
    let frame = self.call_stack[self.call_stack.length() - 1]
    match self.locals_by_func.get(frame.func_name) {
      Some(m) =>
        match m.get(offset) {
          Some(n) => return n
          None => ()
        }
      None => ()
    }
  }
  "local_" + offset.to_string()
}

///|
/// 全局变量名（派生索引；缺名回退 `global_{n}`）。
fn VitroVM::global_var_name(self : VitroVM, offset : Int32) -> String {
  match self.global_syms.get(offset) {
    Some(n) => n
    None => "global_" + offset.to_string()
  }
}

///|
/// 局部变量访问观测登记（P0 观测落闸单点，#176，2026-11-02）：观测态推
/// `last_accessed_vars`（含 `local_var_name` 双 Map 查找——#176 §5 实测
/// js 45 / native 30 ns 每次）；run 全速态整段短路（零消费方）。十臂
/// 调用点只换此一行，Read/Write 语义与推入时序逐字保留。
fn VitroVM::note_local_access(
  self : VitroVM,
  operand : Int32,
  kind : @memory.AccessKind,
) -> Unit {
  if self.observe {
    self.last_accessed_vars.push(VariableAccess::{
      name: self.local_var_name(operand),
      access_type: kind,
    })
  }
}

///|
/// 全局变量访问观测登记（同 `note_local_access`——global_syms 单 Map 查找）。
fn VitroVM::note_global_access(
  self : VitroVM,
  operand : Int32,
  kind : @memory.AccessKind,
) -> Unit {
  if self.observe {
    self.last_accessed_vars.push(VariableAccess::{
      name: self.global_var_name(operand),
      access_type: kind,
    })
  }
}

///|
/// 局部变量族（LoadLocal / StoreLocal / D / Q 四型 + GetFrameBase）。
/// 地址越界文案带 opcode 名（Rust `stack.rs:50-57` 手写预检同款——
/// 受检访存的兜底渲染在先，正常路径不会触达）。
fn VitroVM::execute_local(
  self : VitroVM,
  op : @opcode.OpCode,
  operand : Int32,
  line : Int32,
  column : Int32,
) -> Unit {
  match op {
    LoadLocal => {
      self.note_local_access(operand, Read)
      if self.call_stack.length() > 0 {
        let frame = self.call_stack[self.call_stack.length() - 1]
        let addr = frame.locals_base + operand.reinterpret_as_uint()
        if addr + 4U > @bytecode.MEM_SIZE || addr < @bytecode.NULL_TRAP_SIZE {
          self.trap("LoadLocal: 地址越界", line, column)
        } else {
          let val = self.vm_load_u32(addr, line, column)
          self.push_i32(val.reinterpret_as_int())
        }
      } else {
        self.trap("LoadLocal: 无调用帧", line, column)
      }
    }
    StoreLocal => {
      self.note_local_access(operand, Write)
      if self.call_stack.length() > 0 {
        let frame = self.call_stack[self.call_stack.length() - 1]
        let addr = frame.locals_base + operand.reinterpret_as_uint()
        if addr + 4U > @bytecode.MEM_SIZE || addr < @bytecode.NULL_TRAP_SIZE {
          self.trap("StoreLocal: 地址越界", line, column)
        } else {
          let val = self.pop().to_uint()
          self.vm_store_u32(addr, val, line, column)
        }
      } else {
        self.trap("StoreLocal: 无调用帧", line, column)
      }
    }
    LoadLocalD | LoadLocalQ => {
      // 病 91 观测缺失修（#71，2026-10-16）：D/Q 八字节族与 4 字节族同推
      // last_accessed_vars——此前 8 臂零观测，double/long long 变量的访问
      // 记录在 observe/时间旅行面静默缺失（oracle 同源缺失，Rust 已退役
      // 无对侧——单侧修）
      self.note_local_access(operand, Read)
      if self.call_stack.length() > 0 {
        let frame = self.call_stack[self.call_stack.length() - 1]
        let addr = frame.locals_base + operand.reinterpret_as_uint()
        if addr + 8U > @bytecode.MEM_SIZE || addr < @bytecode.NULL_TRAP_SIZE {
          let nm = if op is LoadLocalD { "LoadLocalD" } else { "LoadLocalQ" }
          self.trap("\{nm}: 地址越界", line, column)
        } else {
          let val = self.vm_load_u64(addr, line, column)
          self.push(val)
        }
      } else {
        let nm = if op is LoadLocalD { "LoadLocalD" } else { "LoadLocalQ" }
        self.trap("\{nm}: 无调用帧", line, column)
      }
    }
    StoreLocalD | StoreLocalQ => {
      // 病 91 观测缺失修（同上）——写侧同推
      self.note_local_access(operand, Write)
      if self.call_stack.length() > 0 {
        let frame = self.call_stack[self.call_stack.length() - 1]
        let addr = frame.locals_base + operand.reinterpret_as_uint()
        if addr + 8U > @bytecode.MEM_SIZE || addr < @bytecode.NULL_TRAP_SIZE {
          let nm = if op is StoreLocalD { "StoreLocalD" } else { "StoreLocalQ" }
          self.trap("\{nm}: 地址越界", line, column)
        } else {
          let val = self.pop()
          self.vm_store_u64(addr, val, line, column)
        }
      } else {
        let nm = if op is StoreLocalD { "StoreLocalD" } else { "StoreLocalQ" }
        self.trap("\{nm}: 无调用帧", line, column)
      }
    }
    GetFrameBase =>
      if self.call_stack.length() > 0 {
        let frame = self.call_stack[self.call_stack.length() - 1]
        self.push(frame.locals_base.to_uint64())
      } else {
        self.trap("GetFrameBase: 无调用帧", line, column)
      }
    _ => ()
  }
}

///|
/// 全局变量族（LoadGlobal / StoreGlobal / D / Q 四型；`GLOBAL_START +
/// operand` 编址）。
fn VitroVM::execute_global(
  self : VitroVM,
  op : @opcode.OpCode,
  operand : Int32,
  line : Int32,
  column : Int32,
) -> Unit {
  let addr = @bytecode.GLOBAL_START + operand.reinterpret_as_uint()
  match op {
    LoadGlobal => {
      self.note_global_access(operand, Read)
      if addr + 4U > @bytecode.MEM_SIZE || addr < @bytecode.NULL_TRAP_SIZE {
        self.trap("LoadGlobal: 地址越界", line, column)
      } else {
        let val = self.vm_load_u32(addr, line, column)
        self.push_i32(val.reinterpret_as_int())
      }
    }
    StoreGlobal => {
      self.note_global_access(operand, Write)
      if addr + 4U > @bytecode.MEM_SIZE || addr < @bytecode.NULL_TRAP_SIZE {
        self.trap("StoreGlobal: 地址越界", line, column)
      } else {
        let val = self.pop().to_uint()
        self.vm_store_u32(addr, val, line, column)
      }
    }
    LoadGlobalD | LoadGlobalQ => {
      // 病 91 观测缺失修（#71，2026-10-16）：全局 D/Q 同推观测
      self.note_global_access(operand, Read)
      let nm = if op is LoadGlobalD { "LoadGlobalD" } else { "LoadGlobalQ" }
      if addr + 8U > @bytecode.MEM_SIZE || addr < @bytecode.NULL_TRAP_SIZE {
        self.trap("\{nm}: 地址越界", line, column)
      } else {
        let val = self.vm_load_u64(addr, line, column)
        self.push(val)
      }
    }
    StoreGlobalD | StoreGlobalQ => {
      // 病 91 观测缺失修（同上）——写侧同推
      self.note_global_access(operand, Write)
      let nm = if op is StoreGlobalD { "StoreGlobalD" } else { "StoreGlobalQ" }
      if addr + 8U > @bytecode.MEM_SIZE || addr < @bytecode.NULL_TRAP_SIZE {
        self.trap("\{nm}: 地址越界", line, column)
      } else {
        let val = self.pop()
        self.vm_store_u64(addr, val, line, column)
      }
    }
    LoadGlobalByte | LoadGlobalUByte => {
      // #177：char 全局 1 字节读——i8 符号扩展 / u8 零扩展
      //（语义对齐 LoadMemByte/LoadMemUByte）
      self.note_global_access(operand, Read)
      let nm = if op is LoadGlobalByte {
        "LoadGlobalByte"
      } else {
        "LoadGlobalUByte"
      }
      if addr + 1U > @bytecode.MEM_SIZE || addr < @bytecode.NULL_TRAP_SIZE {
        self.trap("\{nm}: 地址越界", line, column)
      } else {
        let val = self.vm_load_i8(addr, line, column)
        self.push_i32(if op is LoadGlobalByte { val } else { val & 0xFF })
      }
    }
    StoreGlobalByte => {
      // #177：char 全局 1 字节写——只落低 8 位，不越权抹右侧邻居
      self.note_global_access(operand, Write)
      if addr + 1U > @bytecode.MEM_SIZE || addr < @bytecode.NULL_TRAP_SIZE {
        self.trap("StoreGlobalByte: 地址越界", line, column)
      } else {
        let val = self.pop_i32()
        self.vm_store_i8(addr, val, line, column)
      }
    }
    _ => ()
  }
}
