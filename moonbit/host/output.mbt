///| 输出通道：把"程序自己写出的字节"与"引擎附注"在源头分开。
///
/// **口径资产照搬**（Rust `vitro_runtime::output`，模块头的 E-P1-5 论证逐条继承）：
/// 此前所有输出都追加进同一个 `Vec<String>`，于是引擎的"程序运行完成，返回值：N"、
/// 内存泄漏报告、安全检测提示与学生的 `printf` 混在同一条字节流里；消费方
/// （Shadow Verification / E2E / 第三方）只能靠文本正则把附注"洗掉"，同一套清洗
/// 规则散落十余处且语义互不一致——程序自己打印 `程序运行完成，返回值：7` 时会被
/// 整段删除，导出假阳性 `output_gap`。改为在源头按 [`OutputKind`] 打标后：
/// - 需要与 Clang 比对的消费方读 stdout 通道，拿到的是**程序真实输出**；
/// - 需要展示的消费方按写入顺序拼接全量视图；
/// - 教学附注单独成通道，不再污染 stdout。
///
/// 之所以用"带 kind 的单序列"而不是"stdout/notes 两个独立缓冲区"：附注并非总在
/// 末尾（"堆内存耗尽"提示插在 malloc 失败处，程序后续还会继续输出），双缓冲会丢失
/// 真实交错顺序，UI 展示会错位。
///
/// **本批的结构变更（勘察 §5.5「输出通道改为字节累积」+ §9.2 约束 #4）**：
/// 片段的承载从 `String` 改成 **`Bytes`**。现版 `push_stdout(impl Into<String>)`
/// 使**非 UTF-8 字节永远无法保真**——`putchar(200)` 输出 2 字节 `C3 88` 而非
/// 1 字节 `C8`（`host/io.rs:346`；`printf("%c",200)` 同 `host/utils.rs:324-327`），
/// 而 MoonBit 的 `String` 内部是 UTF-16，问题只会更重。改 `Bytes` 后字节原样保真，
/// 且不可变载体天然可共享（与"快照零拷贝"同向）。
///
/// **一处随之而来的适配（诚实记录）**：Rust 的小段合并是 `String::push_str`
/// **原地增长**（摊还 O(1)），`Bytes` 不可变则每次拼接都要重分配 → 逐字符
/// `putchar` 在 4096 上限内会退化成 O(n²) 拷贝。故本实现把**未封口的尾块**
/// 放在可变累加缓冲 `pending` 里，达到合并条件即就地 `push`，封口时一次性
/// 物化为 `Bytes`（每字节恰一次拷贝）。可观测语义与 Rust 逐条等价
/// （合并阈值/上限/通道判定/note 不入合并），差异只在分配模式。

///|
/// 单个输出片段的来源。
pub(all) enum OutputKind {
  /// 程序自身写到 stdout 的字节（`printf` / `puts` / `putchar` / `fputs(stdout)` 等）。
  ///
  /// 这是 Shadow Verification 与 Clang golden 比对的**唯一**合法来源。
  Stdout
  /// 程序自身写到 stderr 的字节（`fputs(stderr)` / `perror` 等）。
  ///
  /// C 标准下 stderr 无缓冲且与 stdout 分流；与 Clang 比对 stdout 时不得混入。
  Stderr
  /// 引擎附注：教学诊断、运行完成提示、内存泄漏报告、堆上限提示等。
  ///
  /// **不属于程序输出**，任何 stdout 比对都必须排除。
  Note
} derive(Debug, Eq)

///|
/// 通道的稳定字符串标识（JSON 出口与文档口径）。
pub fn OutputKind::as_str(self : OutputKind) -> String {
  match self {
    OutputKind::Stdout => "stdout"
    OutputKind::Stderr => "stderr"
    OutputKind::Note => "note"
  }
}

///|
/// 从字符串解析通道标识；`None` 表示未知通道。
///
/// `"display"` 不是单一片段的 kind，而是"全部按序拼接"的投影，由调用方单独处理。
pub fn OutputKind::parse(s : String) -> OutputKind? {
  match s.trim().to_lower() {
    "stdout" => Some(OutputKind::Stdout)
    "stderr" => Some(OutputKind::Stderr)
    "note" | "notes" => Some(OutputKind::Note)
    _ => None
  }
}

///|
/// 通道在固定三元组里的下标（`kind_bytes` 用）。
fn OutputKind::index(self : OutputKind) -> Int {
  match self {
    OutputKind::Stdout => 0
    OutputKind::Stderr => 1
    OutputKind::Note => 2
  }
}

///|
/// 一段带来源标记的输出。
pub(all) struct OutputChunk {
  kind : OutputKind
  bytes : Bytes
} derive(Debug, Eq)

///|
/// 输出日志默认总预算（16MB）。
///
/// 真实教学/防线用例的输出最大仅几十 KB，16MB 内**完全保真**（shadow 比对不受
/// 影响）；失控程序（如 10M 步上限内逐字符 `putchar`）超预算后丢最旧并附截断
/// 注记——有界且截断可见，替代无界累积形态。
pub const OUTPUT_LOG_BUDGET : Int = 16 * 1024 * 1024

///|
/// stdout/stderr 连续小段合并阈值：写入 ≤ 此长度的程序片段与末尾同通道块拼接
/// （`putchar` 逐字符分配合并）；大于此长度独立成段。
pub const MERGE_THRESHOLD : Int = 64

///|
/// 合并后单块长度上限（防止合并本身无界）。
pub const MERGE_LIMIT : Int = 4096

///|
/// 带预算的输出日志。
///
/// - **预算内保真**：顺序、通道、字节全部保持（shadow stdout 比对不受影响）；
/// - **超预算丢最旧**：尾部保真（学生看到的最新输出不丢），并附一条截断引擎
///   附注（截断可见，不静默）；
/// - **O(1) 长度**：总量与逐通道字节长度增量维护；
/// - **小段合并**：见模块头的适配说明。
///
/// **已知残余（继承 Rust 的诚实记录）**：引擎附注（note）不占预算、不参与丢弃
/// ——它是输出侧唯一无界通道，当前靠调用方的文本去重控制条数（`has_note`）。
pub struct OutputLog {
  /// 已封口的片段序列（写入序）。`Note` 永不参与合并。
  chunks : Array[OutputChunk]
  /// 累计字节总数（O(1) 展示视图长度；含未封口的 `pending`）。
  mut total_bytes : Int
  /// 逐通道字节数（O(1)）。
  kind_bytes : FixedArray[Int]
  /// 环形丢弃的累计字节数（诊断口径，`clear` 复位）。
  mut dropped_bytes : Int
  /// 首次触发丢弃后置位，避免重复附截断注记。
  mut truncation_noted : Bool
  /// 总字节预算（运行配置）。
  mut budget : Int
  /// **未封口的尾块**累加缓冲（仅 stdout/stderr；`Bytes` 不可变故先攒后物化）。
  pending : Array[Byte]
  /// 未封口尾块的通道（`pending` 非空时有效）。
  mut pending_kind : OutputKind
  /// `pending` 是否有内容。
  mut has_pending : Bool
}

///|
/// 空日志（默认 16MB 预算）。
pub fn OutputLog::new() -> OutputLog {
  OutputLog::{
    chunks: [],
    total_bytes: 0,
    kind_bytes: FixedArray::make(3, 0),
    dropped_bytes: 0,
    truncation_noted: false,
    budget: OUTPUT_LOG_BUDGET,
    pending: [],
    pending_kind: OutputKind::Stdout,
    has_pending: false,
  }
}

///|
/// 调整总预算（只影响后续写入的裁剪判定）。
pub fn OutputLog::set_budget(self : OutputLog, budget : Int) -> Unit {
  self.budget = budget
}

///|
/// 当前预算。
pub fn OutputLog::budget(self : OutputLog) -> Int {
  self.budget
}

///|
/// 现存全部字节总数（O(1)）。
pub fn OutputLog::total_bytes(self : OutputLog) -> Int {
  self.total_bytes
}

///|
/// 指定通道现存字节数（O(1)）。
pub fn OutputLog::len_of(self : OutputLog, kind : OutputKind) -> Int {
  self.kind_bytes[kind.index()]
}

///|
/// 环形丢弃的累计字节数。
pub fn OutputLog::dropped_bytes(self : OutputLog) -> Int {
  self.dropped_bytes
}

///|
/// 是否一个片段都没有（含未封口）。
pub fn OutputLog::is_empty(self : OutputLog) -> Bool {
  self.chunks.is_empty() && !self.has_pending
}

///|
/// 片段数（**纯读**：未封口尾块按一个片段计，口径与 Rust 的 `chunks.len()` 一致）。
pub fn OutputLog::len(self : OutputLog) -> Int {
  self.chunks.length() + (if self.has_pending { 1 } else { 0 })
}

///|
/// 程序输出（stdout+stderr）现存字节数——预算只约束程序输出，引擎附注不占
/// 预算、不参与环形丢弃（截断提示被程序输出挤掉就失去意义）。
fn OutputLog::program_bytes(self : OutputLog) -> Int {
  self.total_bytes - self.kind_bytes[OutputKind::Note.index()]
}

///|
/// 把 `[off, off + len)` 切片复制为新的 `Bytes`（经 `FixedArray` 中转——读侧
/// 没有 FixedArray 版原语，`BytesView::to_owned` 是 `Bytes` 侧的现成路径）。
fn bytes_slice(src : Bytes, off : Int, len : Int) -> Bytes {
  src.get_view(start=off, end=off + len).unwrap().to_owned()
}

///|
/// 把未封口尾块物化为 `Bytes`（**不改状态**）。
fn OutputLog::pending_bytes(self : OutputLog) -> Bytes {
  let n = self.pending.length()
  let arr : FixedArray[Byte] = FixedArray::make(n, b'\x00')
  for i = 0; i < n; i = i + 1 {
    arr[i] = self.pending[i]
  }
  Bytes::from_array(arr)
}

///|
/// **只读视图**：已封口片段 + （若有）未封口尾块的临时片段。
///
/// **为什么读取必须走视图而不是"顺手封口"**：Rust 的 `chunks` 是稳定结构，
/// 读 `len()` / `chunks_of` 不影响后续合并——写一个小段再读一次，Rust 里
/// 仍合并进末尾块。若读取顺手封口，则"读一次再写小段"会另起一块（S6 host
/// 批实测：两次 64B 写之间插一次 `len()`，块数从 1 变 2，与 Rust 分叉）。
/// 故**封口只发生在写路径**：换通道、新段超阈值、`push_note`、超预算裁剪。
fn OutputLog::view(self : OutputLog) -> Array[OutputChunk] {
  if !self.has_pending {
    return self.chunks
  }
  let out : Array[OutputChunk] = Array(capacity=self.chunks.length() + 1)
  for c in self.chunks {
    out.push(c)
  }
  out.push(OutputChunk::{
    kind: self.pending_kind,
    bytes: self.pending_bytes(),
  })
  out
}

///|
/// 物化未封口的尾块为 `Bytes` 片段并压入 `chunks`（记数已发生，此处不再加）。
fn OutputLog::flush_pending(self : OutputLog) -> Unit {
  if !self.has_pending {
    return
  }
  self.chunks.push(OutputChunk::{
    kind: self.pending_kind,
    bytes: self.pending_bytes(),
  })
  self.pending.clear()
  self.has_pending = false
}

///|
/// 追加一段输出（stdout/stderr 的小段与末尾同通道块合并）。
///
/// 合并判定与 Rust `OutputLog::push` 逐条等价：`kind != Note` 且新段
/// `≤ MERGE_THRESHOLD` 且末尾同通道且合并不超 `MERGE_LIMIT`。
pub fn OutputLog::push(
  self : OutputLog,
  kind : OutputKind,
  bytes : Bytes,
) -> Unit {
  let n = bytes.length()
  if kind != OutputKind::Note && n <= MERGE_THRESHOLD {
    if self.has_pending &&
      self.pending_kind == kind &&
      self.pending.length() + n <= MERGE_LIMIT {
      for i = 0; i < n; i = i + 1 {
        self.pending.push(bytes[i])
      }
      self.total_bytes = self.total_bytes + n
      self.kind_bytes[kind.index()] = self.kind_bytes[kind.index()] + n
      self.enforce_budget()
      return
    }
    // 封口旧尾块，改由新段开启新尾块
    self.flush_pending()
    self.pending_kind = kind
    self.has_pending = true
    for i = 0; i < n; i = i + 1 {
      self.pending.push(bytes[i])
    }
    self.total_bytes = self.total_bytes + n
    self.kind_bytes[kind.index()] = self.kind_bytes[kind.index()] + n
    self.enforce_budget()
    return
  }
  self.flush_pending()
  self.chunks.push(OutputChunk::{ kind, bytes, })
  self.total_bytes = self.total_bytes + n
  self.kind_bytes[kind.index()] = self.kind_bytes[kind.index()] + n
  self.enforce_budget()
}

///|
/// 追加程序 stdout 片段。
pub fn OutputLog::push_stdout(self : OutputLog, bytes : Bytes) -> Unit {
  self.push(OutputKind::Stdout, bytes)
}

///|
/// 追加程序 stderr 片段。
pub fn OutputLog::push_stderr(self : OutputLog, bytes : Bytes) -> Unit {
  self.push(OutputKind::Stderr, bytes)
}

///|
/// 追加引擎附注：保证每段以 `\n` 收尾（段落语义，不参与小段合并）。
pub fn OutputLog::push_note(self : OutputLog, bytes : Bytes) -> Unit {
  let n = bytes.length()
  if n == 0 {
    return
  }
  let text = if bytes[n - 1] == b'\n' { bytes } else { bytes + b"\n" }
  self.flush_pending()
  self.chunks.push(OutputChunk::{ kind: OutputKind::Note, bytes: text, })
  self.total_bytes = self.total_bytes + text.length()
  let i = OutputKind::Note.index()
  self.kind_bytes[i] = self.kind_bytes[i] + text.length()
  self.enforce_budget()
}

///|
/// 追加引擎附注（文本便捷入口；UTF-8 编码后走 `push_note`）。
pub fn OutputLog::push_note_str(self : OutputLog, text : String) -> Unit {
  self.push_note(@utf8.encode(text))
}

///|
/// 是否已存在完全相同的附注（调用方的 O(n) 去重口径，Rust
/// `note_chunks().contains(&msg)` 同）。
pub fn OutputLog::has_note(self : OutputLog, bytes : Bytes) -> Bool {
  for c in self.chunks {
    if c.kind == OutputKind::Note && c.bytes == bytes {
      return true
    }
  }
  false
}

///|
/// 超预算时从最旧端丢弃**程序输出**（尾部保真）；单条超预算的块截其头部保留
/// 尾部。引擎附注不参与丢弃且**位置不动**——按索引跳过 note 找到最旧的可丢弃
/// 程序块（垂下再排到队尾会破坏 display 的真实交错顺序；截断提示也不能被程序
/// 输出逐字节吃掉）。首次触发丢弃时附一条截断注记。
///
/// 与 Rust 的唯一语义差异：**不做 UTF-8 边界对齐**。Rust 因载体是 `String`，
/// 部分截除必须把切点向后推到 `is_char_boundary`，否则 `drain` 直接 panic；
/// 本实现的载体是 `Bytes`，字节就是字节——这正是"字节保真"的收益所在。
fn OutputLog::enforce_budget(self : OutputLog) -> Unit {
  // **只在真超预算时才把未封口尾块物化**：裁剪判定要看全部程序字节
  // （含 pending）。若无条件封口，则每次 push 后的 pending 都被立
  // 即变成独立块——"与末尾同通道块合并"就此失效（S6 host 批实测：
  // 100 次 1 字节写若合并失效会落成 100 块）。
  if self.program_bytes() > self.budget {
    self.flush_pending()
  }
  while self.program_bytes() > self.budget {
    let mut idx = -1
    for i = 0; i < self.chunks.length(); i = i + 1 {
      if self.chunks[i].kind != OutputKind::Note {
        idx = i
        break
      }
    }
    if idx < 0 {
      break
    }
    let target = self.chunks[idx]
    let n = target.bytes.length()
    let over = self.program_bytes() - self.budget
    if n > over {
      // 从头部移除 over 字节，保留尾部
      self.chunks[idx] = OutputChunk::{
        kind: target.kind,
        bytes: bytes_slice(target.bytes, over, n - over),
      }
      self.on_bytes_removed(target.kind, over)
      break
    } else {
      ignore(self.chunks.remove(idx))
      self.on_bytes_removed(target.kind, n)
    }
  }
  if self.dropped_bytes > 0 && !self.truncation_noted {
    self.truncation_noted = true
    let note = "[引擎] 程序输出超出 \{self.budget} 字节预算，更早的输出已截断丢弃，仅保留最新部分。\n"
    self.chunks.push(OutputChunk::{
      kind: OutputKind::Note,
      bytes: @utf8.encode(note),
    })
    self.total_bytes = self.total_bytes + note.length()
    let i = OutputKind::Note.index()
    self.kind_bytes[i] = self.kind_bytes[i] + note.length()
  }
}

///|
/// 记账：从某通道移除 `n` 字节。
fn OutputLog::on_bytes_removed(
  self : OutputLog,
  kind : OutputKind,
  n : Int,
) -> Unit {
  self.total_bytes = self.total_bytes - n
  let i = kind.index()
  self.kind_bytes[i] = self.kind_bytes[i] - n
  self.dropped_bytes = self.dropped_bytes + n
}

///|
/// **片段视图（带通道标记，写入序）**：已封口片段 + 未封口尾块（若有）。
///
/// 出口给"需要按原始交错顺序连同通道一起看"的消费方（引擎附注并非总在末尾，
/// 双缓冲会丢真实交错顺序——模块头已论证）；`join_all` 只给拼接结果，看不出
/// 哪段是附注。返回的是**独立数组**（`OutputChunk` 本身不可变，可安全共享）。
pub fn OutputLog::chunk_list(self : OutputLog) -> Array[OutputChunk] {
  let out : Array[OutputChunk] = Array(capacity=self.len())
  for c in self.view() {
    out.push(c)
  }
  out
}

///|
/// 按通道筛选片段（保写入顺序）。返回值为 `Bytes`（不可变，可安全共享）。
pub fn OutputLog::chunks_of(
  self : OutputLog,
  kind : OutputKind,
) -> Array[Bytes] {
  let out : Array[Bytes] = []
  for c in self.view() {
    if c.kind == kind {
      out.push(c.bytes)
    }
  }
  out
}

///|
/// 拼接指定通道的全部字节。
pub fn OutputLog::join(self : OutputLog, kind : OutputKind) -> Bytes {
  assemble(self.view(), Some(kind))
}

///|
/// 展示视图：所有通道按写入顺序拼接。
pub fn OutputLog::join_all(self : OutputLog) -> Bytes {
  assemble(self.view(), None)
}

///|
/// 连续缓冲拼装（先算总长，再一次 `blit`——避免逐段 `Bytes::add` 的 O(n²)）。
fn assemble(chunks : Array[OutputChunk], kind : OutputKind?) -> Bytes {
  let mut total = 0
  for c in chunks {
    if kind_ok(c.kind, kind) {
      total = total + c.bytes.length()
    }
  }
  let arr : FixedArray[Byte] = FixedArray::make(total, b'\x00')
  let mut off = 0
  for c in chunks {
    if kind_ok(c.kind, kind) {
      let n = c.bytes.length()
      arr.blit_from_bytes(off, c.bytes, 0, n)
      off = off + n
    }
  }
  Bytes::from_array(arr)
}

///|
/// 通道筛选判定（`None` = 全通过）。
fn kind_ok(actual : OutputKind, want : OutputKind?) -> Bool {
  match want {
    Some(k) => actual == k
    None => true
  }
}

///|
/// 清空（预算与配置保留）。
pub fn OutputLog::clear(self : OutputLog) -> Unit {
  self.chunks.clear()
  self.pending.clear()
  self.has_pending = false
  self.total_bytes = 0
  for i = 0; i < 3; i = i + 1 {
    self.kind_bytes[i] = 0
  }
  self.dropped_bytes = 0
  self.truncation_noted = false
}
