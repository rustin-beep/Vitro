///|
/// bytecode 白盒测试（S5）——libc 固定索引锚 / R1 布局纯函数（r1 第 7 道
/// `test_compute_heap_base_layout_rules` 等价断言全量照搬）/ dump emitter
/// 形态锚。私有常量（BYTECODE_LIBC_* / GLOBAL_*）可直接访问。

test "libc_index: full table contiguous, unique, head/tail anchors" {
  // 数组序 = 索引序（BASE_INDEX + 下标）——与 Rust 88 条显式臂的对应关系锚
  for i, n in bytecode_libc_all_funcs {
    let idx = bytecode_libc_index(n).unwrap()
    assert_eq(idx, BYTECODE_LIBC_BASE_INDEX + i)
  }
  assert_eq(bytecode_libc_all_funcs.length(), BYTECODE_LIBC_FUNC_COUNT)
  // 名字唯一（重复名会使"数组序=索引序"派生失真）
  let seen : Map[String, Bool] = {}
  for n in bytecode_libc_all_funcs {
    guard !(seen.contains(n)) else { fail("重复函数名: \{n}") }
    seen.set(n, true)
  }
  // 首尾定点锚（照搬 Rust bytecode_libc_index.rs 显式臂）
  assert_eq(bytecode_libc_index("isdigit").unwrap(), 1000)
  assert_eq(bytecode_libc_index("atoi").unwrap(), 1012)
  assert_eq(bytecode_libc_index("strcpy").unwrap(), 1017)
  assert_eq(bytecode_libc_index("vitro_sort_int_swap__int").unwrap(), 1087)
  // 不在表 → None（穷尽查表无兜底）
  assert_true(bytecode_libc_index("main") is None)
  assert_true(bytecode_libc_index("printf") is None)
  assert_true(bytecode_libc_index("") is None)
  assert_true(is_bytecode_libc("strlen"))
  assert_true(!(is_bytecode_libc("fprintf")))
  // 常量照搬锚
  assert_eq(BYTECODE_LIBC_CODE_LEN, 3485)
  assert_eq(BYTECODE_LIBC_BASE_INDEX, 1000)
  assert_eq(BYTECODE_LIBC_GLOBALS_RESERVED, 1024U)
}

test "R1 layout constants and align4 (r1 #7)" {
  // 上限常量：与旧字符串判据 MEM_SIZE/16 一致，不收紧存量行为
  assert_eq(GLOBAL_REGION_LIMIT, MEM_SIZE / 16)
  assert_eq(GLOBAL_REGION_LIMIT, 0x10000)
  assert_eq(GLOBAL_START, 0x1000)
  assert_eq(HEAP_START, 0x5000)
  assert_eq(STACK_START, 0x100000)
  assert_eq(align4(0U), 0)
  assert_eq(align4(1U), 4)
  assert_eq(align4(4U), 4)
  assert_eq(align4(5U), 8)
  assert_eq(align4(65533U), 65536)
}

test "compute_heap_base rules (r1 #7)" {
  // 无全局数据 / 无 argv → 静态 HEAP_START（行为不变锚）
  assert_eq(compute_heap_base(0, 0, []), HEAP_START)
  // 大全局（32KB）→ 堆起点 = align4(global_data_end)
  let end = GLOBAL_START + 33024
  assert_eq(compute_heap_base(end, 0, []), align4(end))
  // 未对齐的全局末端 → 4 字节对齐
  assert_eq(
    compute_heap_base(GLOBAL_START + 33025, 0, []),
    align4(GLOBAL_START + 33025),
  )
  // 有 argv → 堆起点必须越过 argv 顶界（GLOBAL_REGION_LIMIT）
  assert_eq(
    compute_heap_base(GLOBAL_START + 2048, 2, ["a", "bb"]),
    GLOBAL_REGION_LIMIT,
  )
}

test "argv_region_footprint (r1 #7 + F2 byte-unit anchor)" {
  // argc*4 指针槽 + Σ(len+1)，4 字节对齐（2*4 + 2 + 3 = 13 → 16）
  assert_eq(argv_region_footprint(2, ["a", "bb"]), 16)
  assert_eq(argv_region_footprint(0, ["a"]), 0)
  assert_eq(argv_region_footprint(3, ["x"]), align4(14U))
  // F2：字符串长度按 UTF-8 字节数计（MoonBit String::length 是 UTF-16 码元，
  // 误用会静默少算——"中文" 2 码元 / 6 字节）
  assert_eq(argv_region_footprint(1, ["中文"]), align4(11U))
}

test "sorted_keys ascending (emitter determinism)" {
  let m : Map[String, Int] = {}
  m.set("delta", 4)
  m.set("alpha", 1)
  m.set("charlie", 3)
  m.set("bravo", 2)
  assert_eq(sorted_keys(m), ["alpha", "bravo", "charlie", "delta"])
}

test "compile_output_dump_json empty shape (14 keys)" {
  let empty_out : CompileOutput = {
    code: [],
    globals_init_32: [],
    globals_init_64: [],
    func_table: Map([]),
    func_index: Map([]),
    string_data: [],
    source_map: [],
    symbols: [],
    struct_defs: Map([]),
    union_defs: Map([]),
    f64_constants: [],
    i64_constants: [],
    global_data_end: 0,
  }
  let json = compile_output_dump_json(empty_out)
  assert_eq(
    json,
    "{\"version\":1,\"code\":[],\"globals_init_32\":[],\"globals_init_64\":[],\"func_table\":{},\"func_index\":{},\"string_data\":[],\"source_map\":[],\"symbols\":[],\"struct_defs\":{},\"union_defs\":{},\"f64_constants\":[],\"i64_constants\":[],\"global_data_end\":0}",
  )
}

test "compile_output_dump_json rich shape (Type/f64/escape single-source)" {
  let out : CompileOutput = {
    code: [
      @opcode.Instruction::new(
        @opcode.OpCode::StoreLocal,
        12,
        @source.SourceLoc::with_file(2, 14, 0),
      ),
    ],
    globals_init_32: [(16U, 65)],
    globals_init_64: [(24U, (4294967296L).reinterpret_as_uint64())],
    func_table: {
      "main": {
        ip: 3,
        arg_count: 0,
        param_count: 0,
        local_count: 4,
        param_sizes: [],
        return_type: @ast.Type::Int(false, false),
        is_variadic: false,
        local_buffers: [],
      },
    },
    func_index: { "main": 1089 },
    string_data: [(4104U, "a\"b")],
    source_map: [(1U, @source.SourceLoc::with_file(2, 14, 0))],
    symbols: [
      {
        name: "p",
        addr: 16U,
        is_local: true,
        ty: @ast.Type::Pointer(@ast.Type::Int(false, false), false),
        scope_depth: 1,
        func_name: "main",
        decl_line: 2,
      },
    ],
    struct_defs: {
      "S": [{ ty: @ast.Type::Int(false, false), name: "x" }],
    },
    union_defs: Map([]),
    f64_constants: [1.0, -0.0],
    i64_constants: [9223372036854775807L],
    global_data_end: 5124U,
  }
  let json = compile_output_dump_json(out)
  let expect = "{\"version\":1,\"code\":[{\"op\":\"StoreLocal\",\"operand\":12,\"loc\":{\"line\":2,\"column\":14,\"file_id\":0}}],\"globals_init_32\":[[16,65]],\"globals_init_64\":[[24,4294967296]],\"func_table\":{\"main\":{\"ip\":3,\"arg_count\":0,\"param_count\":0,\"local_count\":4,\"param_sizes\":[],\"return_type\":{\"Int\":{\"is_unsigned\":false,\"is_const\":false}},\"is_variadic\":false,\"local_buffers\":[]}},\"func_index\":{\"main\":1089},\"string_data\":[[4104,\"a\\\"b\"]],\"source_map\":[[1,{\"line\":2,\"column\":14,\"file_id\":0}]],\"symbols\":[{\"name\":\"p\",\"addr\":16,\"is_local\":true,\"ty\":{\"Pointer\":{\"pointee\":{\"Int\":{\"is_unsigned\":false,\"is_const\":false}},\"is_const\":false}},\"scope_depth\":1,\"func_name\":\"main\",\"decl_line\":2}],\"struct_defs\":{\"S\":[{\"ty\":{\"Int\":{\"is_unsigned\":false,\"is_const\":false}},\"name\":\"x\"}]},\"union_defs\":{},\"f64_constants\":[1.0,-0.0],\"i64_constants\":[9223372036854775807],\"global_data_end\":5124}"
  assert_eq(json, expect)
}
