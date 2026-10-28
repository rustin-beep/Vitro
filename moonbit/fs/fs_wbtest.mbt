// 白盒测试（vendored 批，2026-09-28）：上游 blackbox_test.mbt 三测试改写
// 转正（同包直呼全函数面——含收窄为 priv 的 read_file_to_bytes / is_file /
// remove_dir / remove_file）+ 内联 utf8 函数锚（含 0.5.5 截断行为分界锚）
// + 非 ASCII 路径行为锚（B-4：vendor 前在 x/fs@0.5.5 上实跑取证的同一行为）。
// 上游来源：moonbitlang/x@0.5.5 fs/blackbox_test.mbt（改动：@fs. 前缀去除、
// encoding 包 UTF16 依赖裁除（改字节保真断言）、临时目录名加 vitro 前缀、
// 新增三组锚）。

///|
test "write_and_read" {
  let dir = "tmp_vitro_fs_write_and_read"
  if path_exists(dir) {
    remove_file("\{dir}/test_1.txt") catch {
      _ => ()
    }
    remove_file("\{dir}/test_2.txt") catch {
      _ => ()
    }
    remove_dir(dir) catch {
      _ => ()
    }
  }
  create_dir(dir)
  let path_1 = "\{dir}/test_1.txt"
  let path_2 = "\{dir}/test_2.txt"
  let content_1 = "Hello, World"
  let content_2 = "Hello, MoonBit"
  // 上游用 encoding 包的 encode(UTF16, …) 产二进制后 to_unchecked_string 位
  // 重解释读回（String 内部 UTF-16 的平台耦合断言）；依赖闭合后改为直接
  // 字节保真断言——语义等价（write_bytes_to_file/read_file_to_bytes 的
  // 往返无损）且不绑 String 内部表示。
  write_bytes_to_file(path_1, to_utf8_bytes(content_1))
  inspect(
    read_file_to_bytes(path_1) == to_utf8_bytes(content_1),
    content="true",
  )
  write_string_to_file(path_2, content_2)
  let res_2 = read_file_to_string(path_2)
  inspect(res_2, content=content_2)
  remove_file(path_1)
  remove_file(path_2)
  remove_dir(dir)
}

///|
test "read_dir" {
  // Check the function type without implicitly converting an Array to a view.
  let read_dir_typed : (String) -> ArrayView[String] raise IOError = read_dir
  let dir = "tmp_vitro_fs_read_dir"
  if path_exists(dir) {
    remove_file("\{dir}/file_a.txt") catch {
      _ => ()
    }
    remove_file("\{dir}/file_b.txt") catch {
      _ => ()
    }
    remove_dir("\{dir}/.hidden_dir") catch {
      _ => ()
    }
    remove_dir("\{dir}/example_dir") catch {
      _ => ()
    }
    remove_dir(dir) catch {
      _ => ()
    }
  }
  create_dir(dir)
  debug_inspect(read_dir_typed(dir), content="<ArrayView: []>")
  create_dir("\{dir}/.hidden_dir")
  create_dir("\{dir}/example_dir")
  let file_a = "\{dir}/file_a.txt"
  let file_b = "\{dir}/file_b.txt"
  write_string_to_file(file_a, "a")
  write_string_to_file(file_b, "b")
  let files = read_dir_typed(dir).to_owned()
  files.sort()
  // 期望值照搬上游（含 String::sort 非字典序的既有语义——长度优先，
  // moonbit/AGENTS.md 陷阱 #29 同族；此处锚定的是 sort 行为而非 fs 行为）。
  debug_inspect(
    files,
    content=(
      #|["file_a.txt", "file_b.txt", ".hidden_dir", "example_dir"]
    ),
  )
  remove_file(file_a)
  remove_file(file_b)
  remove_dir("\{dir}/.hidden_dir")
  remove_dir("\{dir}/example_dir")
  remove_dir(dir)
}

///|
test "create_dir_and_remove_dir" {
  let dir = "tmp_vitro_fs_create_dir"
  if path_exists(dir) {
    remove_dir(dir) catch {
      _ => ()
    }
  }
  assert_false(path_exists(dir))
  create_dir(dir)
  assert_true(path_exists(dir))
  assert_true(is_dir(dir))
  assert_false(is_file(dir))
  remove_dir(dir)
  assert_false(path_exists(dir))
}

///|
test "non_ascii_path_roundtrip" {
  // B-4 行为锚（2026-09-28 vendor 前在 x/fs@0.5.5 上实跑取证，Windows
  // native）：中文目录 + 中文文件名 + 空格路径的读写往返、read_dir 返回
  // 非 ASCII 文件名、remove 后不可见——vendored 实现须同行为（宽字符
  // _wfopen/_wmkdir/FindFirstFileW 路径照搬的回归锚）。
  let dir = "tmp_vitro_fs_中文目录"
  let file = "\{dir}/文件_名 with space.txt"
  create_dir(dir)
  write_string_to_file(file, "内容：你好，世界！vitro")
  inspect(read_file_to_string(file), content="内容：你好，世界！vitro")
  assert_true(path_exists(file))
  assert_true(is_dir(dir))
  let names = read_dir(dir).to_owned()
  assert_eq(names.length(), 1, msg="read_dir 应恰好返回 1 个条目")
  inspect(names[0], content="文件_名 with space.txt")
  remove_file(file)
  remove_dir(dir)
  assert_false(path_exists(dir))
}

///|
test "utf8_roundtrip_ascii_cjk_emoji" {
  // 内联 utf8_compat.mbt 的编码/解码往返锚（照搬自 x@0.5.5 unicode）。
  let cases : Array[String] = [
    "pure ascii 123", "中文混合 mixed 你好", "emoji 😀🚀 astral", "",
  ]
  for c in cases {
    inspect(to_utf8_string(to_utf8_bytes(c)), content=c)
  }
}

///|
test "utf8_decode_replaces_malformed_with_ufffd" {
  // #363（2026-10-28）语义翻锚：0.5.5 的「非法/不完整序列静默截断」→
  // U+FFFD 替换（上游 main 同向）。翻案动因：to_utf8_string 是三后端
  // read_file_to_string 唯一解码口，0.5.5 语义下 4 字节越界序列
  // （FF FE 64 65）经 unsafe_to_char 产出代理段/越界码点——native 运行时
  // panic（SIGABRT）、wasm-gc 裸 unreachable、js 静默容忍，三臂分叉
  // （issue 实测三形态）。替换策略 = 每个非法极大子部分一个 U+FFFD，
  // 永不产出非法码点（unsafe_to_char 恒安全）。
  // "你" = E4 BD A0：截去尾字节 A0 → 尾部不完整 → 一个 U+FFFD。
  let truncated_ni = Bytes::from_array([
    (0x61).to_byte(),
    (0xE4).to_byte(),
    (0xBD).to_byte(),
  ])
  inspect(to_utf8_string(truncated_ni), content="a�")
  // 孤立延续字节 → 各自一个 U+FFFD（61 80 → "a�"）。
  let lone_cont = Bytes::from_array([(0x61).to_byte(), (0x80).to_byte()])
  inspect(to_utf8_string(lone_cont), content="a�")
  // 四字节序列（emoji U+1F600 = F0 9F 98 80）截去尾字节 → 尾部不完整 →
  // 一个 U+FFFD（旧锚期望 "a"）。
  let truncated_emoji = Bytes::from_array([
    (0x61).to_byte(),
    (0xF0).to_byte(),
    (0x9F).to_byte(),
    (0x98).to_byte(),
  ])
  inspect(to_utf8_string(truncated_emoji), content="a�")
  // #363 现场形态一：FF FE 80（全非法 lead/孤立延续）→ 三个 U+FFFD。
  // （native 修前 SIGABRT、wasm 修前裸 unreachable、js 修前 3 字节
  // 截断止空串——三臂三种结局。）
  let issue_a = Bytes::from_array([
    (0xFF).to_byte(),
    (0xFE).to_byte(),
    (0x80).to_byte(),
  ])
  inspect(to_utf8_string(issue_a), content="���")
  // #363 现场形态二：FF FE 64 65（4 字节越界序列 FF FE 64 65 组不出
  // 合法码点）→ 两 U+FFFD + "de"（js 修前静默容忍 rc=0 的病灶面）。
  let issue_b = Bytes::from_array([
    (0xFF).to_byte(),
    (0xFE).to_byte(),
    (0x64).to_byte(),
    (0x65).to_byte(),
  ])
  inspect(to_utf8_string(issue_b), content="��de")
  // 代理段编码（ED A0 80 = D800）：延续字节合法但码点非法 → 整序列一个
  // U+FFFD（native 修前 unsafe_to_char(0xD800) panic 的直击面）。
  let surrogate = Bytes::from_array([
    (0xED).to_byte(),
    (0xA0).to_byte(),
    (0x80).to_byte(),
  ])
  inspect(to_utf8_string(surrogate), content="�")
  // 过长编码（C0 AF = "/" 的 2 字节过长形）：码点 < 0x80 → 非法 → U+FFFD。
  let overlong = Bytes::from_array([(0xC0).to_byte(), (0xAF).to_byte()])
  inspect(to_utf8_string(overlong), content="�")
  // 合法序列紧邻非法序列：好字节不受伤（前缀 "你" + 代理段 + 尾 "x"）。
  let mixed = Bytes::from_array([
    (0xE4).to_byte(),
    (0xBD).to_byte(),
    (0xA0).to_byte(),
    (0xED).to_byte(),
    (0xA0).to_byte(),
    (0x80).to_byte(),
    (0x78).to_byte(),
  ])
  inspect(to_utf8_string(mixed), content="你�x")
}

///|
test "utf16_pair_inverse" {
  // 照搬 x@0.5.5 unicode/basic_test.mbt 的逆关系锚（供 to_utf8_bytes 的
  // 代理对路径复证）。
  debug_inspect(utf16_pair_to_char(0xD83D, 0xDE00), content="Some('😀')")
  debug_inspect(utf16_pair_to_char(0x0041, 0xDE00), content="None")
  debug_inspect(char_to_utf16_pair('A'), content="None")
  debug_inspect(char_to_utf16_pair('😀'), content="Some((55357, 56832))")
}

///|
/// 病 44 锚（2026-10-13）：写方向 fopen 失败须 raise IOError 而非 NULL
/// 直传 fwrite 崩进程（0xC0000409）——上游 x@0.5.5 的
/// write_bytes_to_file_internal 本有 guard is_null，vitro 搬迁批
/// （d29a3470）单行丢失（上游 3 次 guard vs 搬迁版 2 次实测）；本锚
/// 补回前为红（崩进程不可断言——以修复后 IOError 形态锚定），修复后
/// 不可写路径（不存在目录下写）走 raise。
test "write_to_unwritable_path_raises" {
  // 目录不存在 ⇒ fopen 返回 NULL ⇒ 修复前 NULL 直传 fwrite 崩进程，
  // 修复后 raise IOError
  let bad = "tmp_vitro_no_such_dir/x.txt"
  let mut raised = false
  write_bytes_to_file(bad, b"hi") catch {
    _ => raised = true
  }
  inspect(raised, content="true")
  let mut raised2 = false
  write_string_to_file(bad, "hi") catch {
    _ => raised2 = true
  }
  inspect(raised2, content="true")
}
