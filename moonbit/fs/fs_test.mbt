// 黑盒测试（vendored 批，2026-09-28）：对外面消费面点名——pub 收窄后的
// 7 函数 + IOError 各至少一个 `@fs.` 形态调用（moonbit_surface 闸的
// 消费边锚）。priv 四函数（read_file_to_bytes/is_file/remove_dir/
// remove_file）由 fs_wbtest.mbt 覆盖，此处不重复。
// 注：remove_file/remove_dir 已收窄 priv，黑盒无自清能力——测试目录
// tmp_vitro_fs_bb_roundtrip 留盘，由仓库 .gitignore 兜底（上游黑盒测试
// 用 pub remove 自清的形态随 pub 收窄不再可用）；写前 create_dir 的
// 已存在 raise 由 catch 吞掉（幂等重跑）。

///|
test "public_surface_write_read_roundtrip" {
  let dir = "tmp_vitro_fs_bb_roundtrip"
  @fs.create_dir(dir) catch {
    _ => ()
  }
  // read_file_to_string / write_string_to_file（9+5 调用点的两个主力）
  @fs.write_string_to_file("\{dir}/a.txt", "blackbox 内容 42")
  inspect(@fs.read_file_to_string("\{dir}/a.txt"), content="blackbox 内容 42")
  // write_bytes_to_file（--dump-memory 二进制出口同款）；写 ASCII 字节后
  // 经字符串通道读回（read_file_to_bytes 已收窄 priv，黑盒不点名）
  @fs.write_bytes_to_file("\{dir}/b.bin", b"vitro-bin-42")
  inspect(@fs.read_file_to_string("\{dir}/b.bin"), content="vitro-bin-42")
  // path_exists / is_dir
  assert_true(@fs.path_exists("\{dir}/a.txt"))
  assert_true(@fs.is_dir(dir))
  // read_dir：签名点名（含 ArrayView 返回型与 raise IOError 形态）
  let read_dir_typed : (String) -> ArrayView[String] raise @fs.IOError = @fs.read_dir
  let names = read_dir_typed(dir).to_owned()
  assert_eq(names.length(), 2, msg="黑盒 read_dir 应见 2 个文件")
}

///|
test "ioerror_is_raised_for_missing_file" {
  // IOError 是 pub 面的一员（raise 签名跟随类型）：不存在的文件读必须
  // raise 而非静默（fail loud 口径在 fs 层的体现）。
  let raised = try {
    let _ = @fs.read_file_to_string("tmp_vitro_fs_不存在的文件.txt")
    false
  } catch {
    _ => true
  }
  assert_true(raised, msg="读不存在的文件必须 raise IOError")
}
