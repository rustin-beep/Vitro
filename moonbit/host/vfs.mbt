///| VFS-lite 虚拟文件系统（Rust `vfs.rs:1-771` 照搬）。
///
/// 设计三要点（oracle 原样）：文件**元数据**（fd/游标/模式/EOF）在引擎侧；
/// 文件**数据**存 VM 堆（区域名 `vfs:<name>`，前端内存 Canvas 可直接可视）；
/// 文本模式 CRLF 伸缩（读压 `\r\n`→`\n`、写展开，逻辑/物理偏移互转）。
///
/// **坑 13 修复（既定接纳方案 §4.2-11，登记分叉）**：oracle `fopen(path,"a")`
/// 对不存在文件的建文件分支嵌在 `Write` 块内部恒不可达（追加写静默丢弃）——
/// 本实现按 `VfsMode` 穷尽分支、每模式独立建文件路径；oracle 侧修复列两侧
/// 同修候选。
///
/// **数据读写的故障语义照搬 oracle**：oracle 用 `read_memory_to`/
/// `write_memory` 的 bool 返回静默失败（返回 0/-1 哨兵）；此处受检读写
/// `Err` 同样落哨兵——但**受检化的分叉照登**（oracle `read_memory_to`
/// 不查 UAF——文件区域被 free 后读，oracle 静默、此处失败哨兵）。
///
/// **快照形状（vm 片义务登记）**：fd 表/文件表克隆即得快照态（文件数据在
/// 堆内，随 `MemoryImage` 走）——`VMSnapshot` 落形时接 §4.2-7「VFS 纳入
/// 快照」。oracle 的 `snapshot_files`/`restore_files` 是死代码（全仓零调用）
/// 不搬。

///|
/// 打开模式（穷尽三态——坑 13 的结构性预防）。
enum VfsMode {
  Read
  Write
  Append
} derive(Debug, Eq)

///|
/// 文件元数据（数据在 VM 堆 `heap_addr` 处）。
struct VfsFileMeta {
  mut heap_addr : UInt
  mut size : Int
  mut capacity : Int
} derive(Debug)

///|
/// 文件描述符。
struct VfsDesc {
  mut file_name : String
  mode : VfsMode
  mut cursor : Int
  mut eof : Bool
  mut error : Bool
  is_text_mode : Bool
} derive(Debug)

///|
pub struct VirtualFileSystem {
  files : Map[String, VfsFileMeta]
  descriptors : Map[UInt, VfsDesc]
  mut next_fd : UInt
}

///|
pub fn VirtualFileSystem::new() -> VirtualFileSystem {
  VirtualFileSystem::{ files: Map([]), descriptors: Map([]), next_fd: 0U, }
}

///|
/// 文本模式：逻辑位置 → 物理字节偏移（`\r\n` 计一）。
fn logical_to_physical(data : Array[Byte], logical_pos : Int) -> Int {
  let mut logical = 0
  let mut physical = 0
  let n = data.length()
  while physical < n && logical < logical_pos {
    if data[physical] == b'\r' &&
      physical + 1 < n &&
      data[physical + 1] == b'\n' {
      logical = logical + 1
      physical = physical + 2
    } else {
      logical = logical + 1
      physical = physical + 1
    }
  }
  physical
}

///|
/// 文本模式：物理偏移 → 逻辑位置。
fn physical_to_logical(data : Array[Byte], physical_pos : Int) -> Int {
  let mut logical = 0
  let mut physical = 0
  let n = data.length()
  let limit = if physical_pos < n { physical_pos } else { n }
  while physical < limit {
    if data[physical] == b'\r' &&
      physical + 1 < n &&
      data[physical + 1] == b'\n' {
      logical = logical + 1
      physical = physical + 2
    } else {
      logical = logical + 1
      physical = physical + 1
    }
  }
  logical
}

///|
/// 文本模式读一个逻辑字节：`\r\n` 压成 `\n`（跨二字节）。
fn read_text_byte(data : Array[Byte], physical_pos : Int) -> (Byte, Int) {
  let n = data.length()
  if physical_pos >= n {
    return (b'\x00', physical_pos)
  }
  if data[physical_pos] == b'\r' &&
    physical_pos + 1 < n &&
    data[physical_pos + 1] == b'\n' {
    (b'\n', physical_pos + 2)
  } else {
    (data[physical_pos], physical_pos + 1)
  }
}

///|
/// 受检读一段字节。
fn read_span(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  addr : UInt,
  len : Int,
) -> Result[Array[Byte], @memory.MemFault] {
  let out : Array[Byte] = []
  let mut i = 0
  while i < len {
    match mem.load_i8(map, addr + i.reinterpret_as_uint()) {
      Ok(v) => out.push(v.to_byte())
      Err(e) => return Err(e)
    }
    i = i + 1
  }
  Ok(out)
}

///|
/// VFS 内部分配（oracle `malloc_raw`：不碰值栈；区域 `heap_N`/`alloc_by="vfs"`）。
fn vfs_malloc_raw(map : @memory.MemoryMap, aligned : Int) -> UInt? {
  let addr = match
    map.allocate_raw(aligned.reinterpret_as_uint(), @bytecode.MEM_SIZE) {
    Some(a) => a
    None => return None
  }
  map.register_alloc(addr, aligned, 0, "vfs", true)
  Some(addr)
}

///|
/// VFS 内部释放（oracle `free_region`——**不写 freed_logs 的缺口登记**：
/// 此处走 memory 包 `release` 单出口，FILE*/文件区域进 UAF 窗口是受检化
/// 增强，oracle 侧列两侧同修候选）。
fn vfs_free_raw(map : @memory.MemoryMap, addr : UInt) -> Unit {
  ignore(map.release(addr, 0, 0))
}

///|
/// 区域改名（`vfs:<name>` / `FILE:<path>` 元数据）。
fn rename_region(map : @memory.MemoryMap, addr : UInt, name : String) -> Unit {
  match map.region(addr) {
    Some(r) => {
      r.name = name
      map.set_region(addr, r)
    }
    None => ()
  }
}

///|
/// 为文件扩容（oracle `realloc_vfs_file`：新块拷贝 + 旧块释放；**新区域名
/// 落 `heap_N`、size 更新为文件实长**——oracle 同名行为照搬）。
fn vfs_realloc_file(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  meta : VfsFileMeta,
  new_cap : Int,
) -> Bool {
  if new_cap <= meta.capacity {
    return true
  }
  let new_addr = match vfs_malloc_raw(map, new_cap) {
    Some(a) => a
    None => return false
  }
  match mem.copy(map, new_addr, meta.heap_addr, meta.size) {
    Ok(_) => ()
    Err(_) => {
      vfs_free_raw(map, new_addr)
      return false
    }
  }
  vfs_free_raw(map, meta.heap_addr)
  meta.heap_addr = new_addr
  meta.capacity = new_cap
  match map.region(new_addr) {
    Some(r) =>
      if !r.is_freed {
        r.size = meta.size
        map.set_region(new_addr, r)
      }
    None => ()
  }
  true
}

///|
/// 注入预设文件（oracle `inject_preset_file`——`setup_vm` 后调用，教学
/// 演示用；重名 false）。
pub fn VirtualFileSystem::inject_preset_file(
  self : VirtualFileSystem,
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  name : String,
  data : Bytes,
) -> Bool {
  if self.files.contains(name) {
    return false
  }
  let size = data.length()
  let aligned = @bytecode.align4(size.reinterpret_as_uint()).reinterpret_as_int()
  let addr = match vfs_malloc_raw(map, aligned) {
    Some(a) => a
    None => return false
  }
  match mem.write_bytes(map, addr, data) {
    Ok(_) => ()
    Err(_) => {
      vfs_free_raw(map, addr)
      return false
    }
  }
  rename_region(map, addr, "vfs:\{name}")
  self.files.set(name, VfsFileMeta::{
    heap_addr: addr,
    size,
    capacity: aligned,
  })
  true
}

///|
/// `fopen(path, mode)` → fd（0 = 失败）。模式串 `r/rb/w/wb/a/ab`；文本
/// 模式带 CRLF 伸缩。
///
/// **坑 13 修复**：Append 对不存在文件**建文件**（oracle 该分支死代码，
/// 追加写静默丢弃——登记分叉）；Write 建文件/清空既有；Read 不存在即失败。
pub fn VirtualFileSystem::fopen(
  self : VirtualFileSystem,
  map : @memory.MemoryMap,
  path : String,
  mode : String,
) -> UInt {
  let mode_pair = if mode == "r" {
    Some((VfsMode::Read, true))
  } else if mode == "rb" {
    Some((VfsMode::Read, false))
  } else if mode == "w" {
    Some((VfsMode::Write, true))
  } else if mode == "wb" {
    Some((VfsMode::Write, false))
  } else if mode == "a" {
    Some((VfsMode::Append, true))
  } else if mode == "ab" {
    Some((VfsMode::Append, false))
  } else {
    None
  }
  let vfs_mode = match mode_pair {
    Some(p) => p.0
    None => return 0U
  }
  let is_text = mode_pair.unwrap().1
  match vfs_mode {
    VfsMode::Read =>
      if !self.files.contains(path) {
        return 0U // 读模式文件不存在
      }
    VfsMode::Write =>
      match self.files.get(path) {
        Some(meta) => meta.size = 0 // 覆盖：清空既有
        None => {
          // 建新文件（256 初始容量）
          let addr = match vfs_malloc_raw(map, 256) {
            Some(a) => a
            None => return 0U
          }
          rename_region(map, addr, "vfs:\{path}")
          self.files.set(path, VfsFileMeta::{
            heap_addr: addr,
            size: 0,
            capacity: 256,
          })
        }
      }
    VfsMode::Append =>
      if !self.files.contains(path) {
        // 坑 13 修复：Append 建文件（oracle 死分支——分叉登记）
        let addr = match vfs_malloc_raw(map, 256) {
          Some(a) => a
          None => return 0U
        }
        rename_region(map, addr, "vfs:\{path}")
        self.files.set(path, VfsFileMeta::{
          heap_addr: addr,
          size: 0,
          capacity: 256,
        })
      }
  }
  let fd = self.next_fd + 1U
  self.next_fd = fd
  let cursor = match vfs_mode {
    VfsMode::Append =>
      match self.files.get(path) {
        Some(m) => m.size
        None => 0
      }
    _ => 0
  }
  self.descriptors.set(fd, VfsDesc::{
    file_name: path,
    mode: vfs_mode,
    cursor,
    eof: false,
    error: false,
    is_text_mode: is_text,
  })
  fd
}

///|
/// `fread(buf, size, nmemb, stream)` → 元素数（oracle `vfs.rs:218-286`）。
/// 尺寸链防护照搬（乘法溢出/超 MEM_SIZE → 0）。
pub fn VirtualFileSystem::fread(
  self : VirtualFileSystem,
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  fd : UInt,
  buf : UInt,
  size : Int,
  nmemb : Int,
) -> Int {
  if size <= 0 || nmemb <= 0 {
    return 0
  }
  let to_read = size.to_uint64() * nmemb.to_uint64()
  if to_read > @bytecode.MEM_SIZE.to_uint64() {
    return 0
  }
  let desc = match self.descriptors.get(fd) {
    Some(d) => d
    None => return 0
  }
  let meta = match self.files.get(desc.file_name) {
    Some(m) => m
    None => return 0
  }
  let mut actual = 0
  if desc.is_text_mode {
    // 文本模式：整读文件，逐逻辑字节压缩 \r\n
    let data = match read_span(mem, map, meta.heap_addr, meta.size) {
      Ok(d) => d
      Err(_) => return 0
    }
    let tmp : Array[Byte] = []
    let mut physical = desc.cursor
    while actual < to_read.to_int() && physical < meta.size {
      if data[physical] == b'\r' &&
        physical + 1 < meta.size &&
        data[physical + 1] == b'\n' {
        tmp.push(b'\n')
        physical = physical + 2
      } else {
        tmp.push(data[physical])
        physical = physical + 1
      }
      actual = actual + 1
    }
    desc.cursor = physical
    if actual > 0 {
      match mem.write_bytes(map, buf, Bytes::from_array(tmp)) {
        Ok(_) => ()
        Err(_) => return 0
      }
    }
  } else {
    let remaining = meta.size - desc.cursor
    actual = if to_read.to_int() < remaining {
      to_read.to_int()
    } else {
      remaining
    }
    if actual <= 0 {
      desc.eof = true
      return 0
    }
    let src = meta.heap_addr + desc.cursor.reinterpret_as_uint()
    // 段级拷贝（file → buf 走内存对内存）
    match mem.copy(map, buf, src, actual) {
      Ok(_) => ()
      Err(_) => return 0
    }
    desc.cursor = desc.cursor + actual
  }
  if actual == 0 {
    desc.eof = true
    return 0
  }
  if desc.cursor >= meta.size {
    desc.eof = true
  }
  actual / size
}

///|
/// `fwrite(buf, size, nmemb, stream)` → 元素数（oracle `vfs.rs:289-354`）。
/// 文本模式 `\n` 展开 `\r\n`；超容扩容（`max(2×容, 需求)` 对齐 4）。
pub fn VirtualFileSystem::fwrite(
  self : VirtualFileSystem,
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  fd : UInt,
  buf : UInt,
  size : Int,
  nmemb : Int,
) -> Int {
  if size <= 0 || nmemb <= 0 {
    return 0
  }
  let to_write = size.to_uint64() * nmemb.to_uint64()
  if to_write > @bytecode.MEM_SIZE.to_uint64() {
    return 0
  }
  let desc = match self.descriptors.get(fd) {
    Some(d) => d
    None => return 0
  }
  if desc.mode == VfsMode::Read {
    return 0
  }
  let meta = match self.files.get(desc.file_name) {
    Some(m) => m
    None => return 0
  }
  // 读用户数据
  let user_data = match read_span(mem, map, buf, to_write.to_int()) {
    Ok(d) => d
    Err(_) => return 0
  }
  // 文本模式 \n → \r\n
  let data_to_write : Array[Byte] = []
  if desc.is_text_mode {
    for b in user_data {
      if b == b'\n' {
        data_to_write.push(b'\r')
        data_to_write.push(b'\n')
      } else {
        data_to_write.push(b)
      }
    }
  } else {
    for b in user_data {
      data_to_write.push(b)
    }
  }
  let write_len = data_to_write.length()
  let new_size = desc.cursor + write_len
  if new_size > meta.capacity {
    let grow = if meta.capacity * 2 > new_size {
      meta.capacity * 2
    } else {
      new_size
    }
    let new_cap = @bytecode.align4(grow.reinterpret_as_uint()).reinterpret_as_int()
    if !vfs_realloc_file(map, mem, meta, new_cap) {
      return 0
    }
  }
  let dst = meta.heap_addr + desc.cursor.reinterpret_as_uint()
  match mem.write_bytes(map, dst, Bytes::from_array(data_to_write)) {
    Ok(_) => ()
    Err(_) => return 0
  }
  desc.cursor = desc.cursor + write_len
  if desc.cursor > meta.size {
    meta.size = desc.cursor
  }
  nmemb
}

///|
/// `fclose(stream)` → 0/-1（描述符移除）。
pub fn VirtualFileSystem::fclose(self : VirtualFileSystem, fd : UInt) -> Int {
  match self.descriptors.get(fd) {
    Some(_) => {
      ignore(self.descriptors.remove(fd))
      0
    }
    None => -1
  }
}

///|
/// `feof(stream)` → 1/0。
pub fn VirtualFileSystem::feof(self : VirtualFileSystem, fd : UInt) -> Int {
  match self.descriptors.get(fd) {
    Some(d) => if d.eof { 1 } else { 0 }
    None => 0
  }
}

///|
/// `fgets(buf, n, stream)` → buf 地址或 0。**无论文本/二进制模式都走
/// `read_text_byte`**（`\r\n` 压缩）——oracle 现状照搬（二进制 fgets 不压
/// 缩才是 C 语义，既有偏差登记）。
pub fn VirtualFileSystem::fgets(
  self : VirtualFileSystem,
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  fd : UInt,
  buf : UInt,
  n : Int,
) -> UInt {
  if n == 0 {
    return 0U
  }
  let desc = match self.descriptors.get(fd) {
    Some(d) => d
    None => return 0U
  }
  let meta = match self.files.get(desc.file_name) {
    Some(m) => m
    None => return 0U
  }
  let data = match read_span(mem, map, meta.heap_addr, meta.size) {
    Ok(d) => d
    Err(_) => return 0U
  }
  let mut read_count = 0
  let tmp : Array[Byte] = []
  while read_count < n - 1 && desc.cursor < meta.size {
    let pair = read_text_byte(data, desc.cursor)
    tmp.push(pair.0)
    desc.cursor = pair.1
    read_count = read_count + 1
    if pair.0 == b'\n' {
      break
    }
  }
  if read_count == 0 {
    desc.eof = true
    return 0U
  }
  tmp.push(b'\x00')
  match mem.write_bytes(map, buf, Bytes::from_array(tmp)) {
    Ok(_) => ()
    Err(_) => return 0U
  }
  if desc.cursor >= meta.size {
    desc.eof = true
  }
  buf
}

///|
/// `fputs(s, stream)` → 0/-1（写 C 字符串入文件；文本模式 `\n` 展开）。
pub fn VirtualFileSystem::fputs(
  self : VirtualFileSystem,
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  fd : UInt,
  s_addr : UInt,
) -> Int {
  let desc = match self.descriptors.get(fd) {
    Some(d) => d
    None => return -1
  }
  if desc.mode == VfsMode::Read {
    return -1
  }
  let meta = match self.files.get(desc.file_name) {
    Some(m) => m
    None => return -1
  }
  let tmp = match read_cstring(mem, map, s_addr) {
    Ok(b) => b
    Err(_) => return -1
  }
  let data_to_write : Array[Byte] = []
  let tn = tmp.length()
  let mut i = 0
  while i < tn {
    let b = tmp[i]
    if desc.is_text_mode && b == b'\n' {
      data_to_write.push(b'\r')
      data_to_write.push(b'\n')
    } else {
      data_to_write.push(b)
    }
    i = i + 1
  }
  vfs_append_bytes(map, mem, meta, desc, data_to_write)
}

///|
/// 追加写入公共段（fputs/fputc/fwrite 的尾部三步：扩容 → 写 → 前移游标）。
fn vfs_append_bytes(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  meta : VfsFileMeta,
  desc : VfsDesc,
  data : Array[Byte],
) -> Int {
  let write_len = data.length()
  let new_size = desc.cursor + write_len
  if new_size > meta.capacity {
    let grow = if meta.capacity * 2 > new_size {
      meta.capacity * 2
    } else {
      new_size
    }
    let new_cap = @bytecode.align4(grow.reinterpret_as_uint()).reinterpret_as_int()
    if !vfs_realloc_file(map, mem, meta, new_cap) {
      return -1
    }
  }
  let dst = meta.heap_addr + desc.cursor.reinterpret_as_uint()
  match mem.write_bytes(map, dst, Bytes::from_array(data)) {
    Ok(_) => ()
    Err(_) => return -1
  }
  desc.cursor = desc.cursor + write_len
  if desc.cursor > meta.size {
    meta.size = desc.cursor
  }
  0
}

///|
/// `fgetc(stream)` → 字节值或 -1。
pub fn VirtualFileSystem::fgetc(
  self : VirtualFileSystem,
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  fd : UInt,
) -> Int {
  let desc = match self.descriptors.get(fd) {
    Some(d) => d
    None => return -1
  }
  let meta = match self.files.get(desc.file_name) {
    Some(m) => m
    None => return -1
  }
  if desc.cursor >= meta.size {
    desc.eof = true
    return -1
  }
  let data = match read_span(mem, map, meta.heap_addr, meta.size) {
    Ok(d) => d
    Err(_) => return -1
  }
  let pair = read_text_byte(data, desc.cursor)
  desc.cursor = pair.1
  if desc.cursor >= meta.size {
    desc.eof = true
  }
  pair.0.to_int()
}

///|
/// `fputc(c, stream)` → 写入值或 -1（文本模式 `\n` → `\r\n`）。
pub fn VirtualFileSystem::fputc(
  self : VirtualFileSystem,
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  fd : UInt,
  c : Int,
) -> Int {
  let desc = match self.descriptors.get(fd) {
    Some(d) => d
    None => return -1
  }
  if desc.mode == VfsMode::Read {
    return -1
  }
  let meta = match self.files.get(desc.file_name) {
    Some(m) => m
    None => return -1
  }
  let data : Array[Byte] = if desc.is_text_mode && (c & 0xFF) == 10 {
    [b'\r', b'\n']
  } else {
    [(c & 0xFF).to_byte()]
  }
  let r = vfs_append_bytes(map, mem, meta, desc, data)
  if r != 0 {
    return -1
  }
  c
}

///|
/// `fseek(stream, offset, whence)` → 0/-1。负目标（含 CUR/END 计算出的）
/// 统一 -1 不动游标（U2#13 语义）；文本模式 SET/CUR 走逻辑↔物理换算，
/// END 基于物理末尾（Windows CRT 行为）。
pub fn VirtualFileSystem::fseek(
  self : VirtualFileSystem,
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  fd : UInt,
  offset : Int,
  whence : Int,
) -> Int {
  let desc = match self.descriptors.get(fd) {
    Some(d) => d
    None => return -1
  }
  let meta = match self.files.get(desc.file_name) {
    Some(m) => m
    None => return -1
  }
  let new_cursor : Int = if desc.is_text_mode {
    let data = match read_span(mem, map, meta.heap_addr, meta.size) {
      Ok(d) => d
      Err(_) => return -1
    }
    match whence {
      0 => {
        if offset < 0 {
          return -1
        }
        logical_to_physical(data, offset)
      }
      1 => {
        let logical = physical_to_logical(data, desc.cursor)
        let target = logical.to_int64() + offset.to_int64()
        if target < 0L {
          return -1
        }
        logical_to_physical(data, target.to_int())
      }
      2 => {
        let target = meta.size.to_int64() + offset.to_int64()
        if target < 0L {
          return -1
        }
        target.to_int()
      }
      _ => return -1
    }
  } else {
    let target = match whence {
      0 => offset.to_int64()
      1 => desc.cursor.to_int64() + offset.to_int64()
      2 => meta.size.to_int64() + offset.to_int64()
      _ => return -1
    }
    if target < 0L {
      return -1
    }
    target.to_int()
  }
  desc.cursor = new_cursor
  desc.eof = false
  0
}

///|
/// `ftell(stream)` → 物理游标（Windows CRT 口径）或 -1。
pub fn VirtualFileSystem::ftell(self : VirtualFileSystem, fd : UInt) -> Int {
  match self.descriptors.get(fd) {
    Some(d) => d.cursor
    None => -1
  }
}

///|
/// `rewind(stream)`——游标归零 + 清 EOF/错误位。
pub fn VirtualFileSystem::rewind(self : VirtualFileSystem, fd : UInt) -> Unit {
  match self.descriptors.get(fd) {
    Some(d) => {
      d.cursor = 0
      d.eof = false
      d.error = false
    }
    None => ()
  }
}

///|
/// `fflush`——内存文件无底层缓冲，恒 0。
pub fn VirtualFileSystem::fflush(self : VirtualFileSystem, fd : UInt) -> Int {
  let _ = (self, fd) // 内存文件无底层缓冲：无状态可查（oracle 同为空操作）
  0
}

///|
/// `clearerr(stream)`。
pub fn VirtualFileSystem::clearerr(self : VirtualFileSystem, fd : UInt) -> Unit {
  match self.descriptors.get(fd) {
    Some(d) => {
      d.eof = false
      d.error = false
    }
    None => ()
  }
}

///|
/// `remove(path)` → 0/-1——释放文件区域 + 关闭指向它的全部描述符。
pub fn VirtualFileSystem::remove(
  self : VirtualFileSystem,
  map : @memory.MemoryMap,
  path : String,
) -> Int {
  let removed : VfsFileMeta? = match self.files.get(path) {
    Some(m) => {
      self.files.remove(path)
      Some(m)
    }
    None => None
  }
  match removed {
    Some(meta) => {
      vfs_free_raw(map, meta.heap_addr)
      let to_close : Array[UInt] = []
      for fd, desc in self.descriptors {
        if desc.file_name == path {
          to_close.push(fd)
        }
      }
      for fd in to_close {
        ignore(self.descriptors.remove(fd))
      }
      0
    }
    None => -1
  }
}

///|
/// `rename(old, new)` → 0/-1——文件表换键 + 描述符指向跟随。
pub fn VirtualFileSystem::rename(
  self : VirtualFileSystem,
  old_path : String,
  new_path : String,
) -> Int {
  let moved : VfsFileMeta? = match self.files.get(old_path) {
    Some(m) => {
      self.files.remove(old_path)
      Some(m)
    }
    None => None
  }
  match moved {
    Some(meta) => {
      self.files.set(new_path, meta)
      for _, desc in self.descriptors {
        if desc.file_name == old_path {
          desc.file_name = new_path
        }
      }
      0
    }
    None => -1
  }
}

///|
/// fd → 文件名（调试/观测）。
pub fn VirtualFileSystem::get_file_name(
  self : VirtualFileSystem,
  fd : UInt,
) -> String? {
  match self.descriptors.get(fd) {
    Some(d) => Some(d.file_name)
    None => None
  }
}
