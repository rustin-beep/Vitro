///| #95 VFS 预置与列举域（单源收口）：
///   - 预置清单单源：此前 serve_run / serve_step 两处手写同款注入
///     （C5 分叉形态——改一侧漏一侧即两通道预置不一致）；清单与注入序
///     在此唯一定义，run/step.begin 两通道共用。
///   - `vfs.list` 方法帧：列举口——预置可见性 + 程序自建文件进列
///     （此前「只能靠一个个名字试」，issue #95 核心诉求）。

///|
/// VFS 预置文件清单（#95 单源——(名, 内容)，数组序即注入序即 vfs.list
/// 列举序；改动须连坐：C语言子集规范 VFS 段 + serve_vfs_wbtest 锚）。
/// 语义照搬 Rust execute_run：随每次 run/step.begin **无条件注入**
/// （reset_vfs 后重灌——教学演示通道）；重名注入静默跳过（程序在 vfs
/// 重建后、注入前建同名文件的窗口外不存在——注入先于用户代码执行）。
fn preset_vfs_files() -> Array[(String, Bytes)] {
  [("test.txt", b"hello\nworld\n"), ("numbers.txt", b"1 2 3 4 5\n")]
}

///|
/// 预置注入（serve_execute_run / 统一模式重建两通道共用——#95 收口）。
fn inject_preset_vfs_files(s : @session.Session) -> Unit {
  for pair in preset_vfs_files() {
    ignore(
      s.vm.vfs.inject_preset_file(s.vm.mem_map, s.vm.memory, pair.0, pair.1),
    )
  }
}

///|
/// `vfs.list` 方法帧（#95）：`{files:[{name,size}...]}`——**插入序**
/// （预置在前、程序自建在后）。时机语义：预置随 run/step.begin 注入
/// （run 前清单为空）；每 run 重建（reset_vfs——自建文件不跨 run）。
fn serve_vfs_list_frame(s : @session.Session, id : Json) -> (String, Bool) {
  let files : Array[Json] = []
  for pair in s.vm.vfs.list_files() {
    let e : Map[String, Json] = Map([])
    e.set("name", Json::string(pair.0))
    e.set("size", Json(pair.1))
    files.push(Json::object(e))
  }
  let m : Map[String, Json] = Map([])
  m.set("files", Json::array(files))
  (serve_ok(id, Json::object(m)).stringify(), false)
}
