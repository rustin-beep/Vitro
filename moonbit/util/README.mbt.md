# vitro/engine/util — L0 纯机械助手

零语义机械件的单点收口（G-1，2026-09-26）：纯函数、无业务判定、无状态、无副作用。任何层的包都可依赖它而不引入语义耦合——它是 L0（零依赖，与 `source` / `opcode` 同层）。

## 安装

```bash
moon add vitro/engine/util
```

## 三个件

### 1. UTF-8 字节长度（≠ 码元数）

```mbt check
///|
test {
  inspect(@util.utf8_len("你a好"), content="7")
  inspect("你a好".length(), content="3")
}
```

`String::length()` 数 UTF-16 码元，`utf8_len` 数 UTF-8 字节——与 Rust `String::len()` 同口径，也是列号契约（`source` 包）的字节偏移基准。

### 2. 字典序比较（内置 String 比较非字典序）

```mbt check
///|
test {
  inspect(@util.str_cmp("delta", "charlie"), content="1")
}
```

MoonBit 内置 `String::compare` / `<` / `>` 实测非字典序（疑似长度优先）。排序与对拍类逻辑一律走本函数。

### 3. 位截断与小端拼装

```mbt check
///|
test {
  inspect(@util.i64_to_i32_bits(4294967296L), content="0")
  let b : FixedArray[Byte] = FixedArray::make(4, b'\x00')
  b[0] = b'\x78'
  b[1] = b'\x56'
  b[2] = b'\x34'
  b[3] = b'\x12'
  inspect(@util.le_u32_at(b, 0), content="305419896")
}
```

`i64_to_i32_bits` = Rust `as i32`（低 32 位符号解释）；`le_u32_at` / `le_u64_at` = `FixedArray[Byte]` 的小端拼装读（越界不设防，调用方负责区间）。
