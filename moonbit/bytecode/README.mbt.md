# vitro/engine/bytecode — 字节码产物层与调用路由

C 教学引擎的产物层：**CompileOutput 产物 schema**（13 字段，与 Rust oracle 的 dump 逐字段同构）+ **Bytecode Libc 固定索引**（88 函数名单源，索引 = 1000 + 名单序）+ **R1 内存布局纯函数** + **调用形态单一路由表**（"一个名字走预编译 libc 还是 Host handler"从隐式覆盖变成可查询事实）。地址布局常量（`MEM_SIZE` / `HEAP_START` / 对齐）的单源也在这里，下游（memory / host）只消费不复制。

## 安装

```bash
moon add vitro/engine/bytecode
```

## 两个场景

### 1. 调用形态路由表：一个名字到底怎么被调用

```mbt check
///|
test {
  // strlen 预编译进 Bytecode Libc 固定索引段（基 1000 + 名单序）
  guard @bytecode.call_route("strlen")
    is Some(@bytecode.CallRoute::BytecodeLibc(idx)) else {
    fail("strlen 必须路由到 Bytecode Libc")
  }
  inspect(idx, content="1015")
  // strcpy/strcat 改判回 Host：Host 版带 E3070 栈缓冲区校验（显式例外集）
  guard @bytecode.call_route("strcpy") is Some(@bytecode.CallRoute::Host(_)) else {
    fail("strcpy 必须改判 Host")
  }
  // 遮蔽名单：20 个"有 Host handler 但按名调用到不了"的名字——可断言的事实，
  // 不再是无处可查的隐式覆盖
  inspect(@bytecode.SHADOWED_HOST_NAME_COUNT, content="20")
}
```

### 2. 固定索引段与布局常量（单源消费）

```mbt check
///|
test {
  // 名字 → 固定索引（Bytecode Libc 段 1000..1087；用户函数起点 1089）
  inspect(@bytecode.bytecode_libc_index("strcmp"), content="Some(1016)")
  inspect(@bytecode.BYTECODE_LIBC_FUNC_COUNT, content="88")
  inspect(@bytecode.BYTECODE_LIBC_BASE_INDEX, content="1000")
  // 地址布局常量：执行层（memory/host/vm）从这里消费，不复制数字
  inspect(@bytecode.MEM_SIZE, content="1048576")
}
```

## 契约要点

- **索引 = 名单序 + 1000**：`bytecode_libc_all_funcs` 的数组序即固定索引序，`bytecode_libc_index` 由派生 + 断言锚锁定；与 Rust 侧 `host_func_id.rs` / 产物 JSON 由对账闸（`libc_single_source`）机判一致。
- **空号与改判**：1088 为保留空洞；`strcpy`/`strcat` 是仅有的两条"索引存在但走 Host"的改判（`is_host_rerouted` 单点定义）。
- **产物 schema 与 emitter**：`CompileOutput` 的 dump（浮点文本化 / 转义 / 键序）与 Rust oracle 的 `dump-compile` 14 键逐字段同构——浮点经 `vitro/engine/ast` 的 JSON 文本化单源，禁再写一份。
