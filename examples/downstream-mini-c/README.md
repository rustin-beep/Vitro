# vitro/engine 下游接线示例（downstream-mini-c）

> **这是一个独立的 MoonBit module**，不是本仓 workspace 成员：它像任何下游用户一样
> `import "vitro/engine@0.9.1"`（mooncakes 已发布包），**零仓内相对路径**。
> 仓内源码改了它不会跟着变——它锁的是发布面。B3 批（2026-11-02，审阅 v2 R3 处方）建。

## 为什么有它

R3 报告（下游用户模拟，从未见过仓库源码、只凭 `moon add` 后的包内容拼管线）的结论：
**底层五步管线签名齐全可推断，越高层越不可发现**——`gateway.invoke` 这个 NDJSON
单口是下游最想要的入口，而 0.9.1 包内 gateway 没有 `pkg.generated.mbti`，只能 grep 源码；
`session` 包导出了一堆类型却没有产生它们的方法（它是 gateway 的内部件）；包 README 没有
一个「喂 C 字符串 → 出结果」的端到端例子。本示例把 R3 半小时拼出来的两条路**固化成可
`moon run` 的代码**，每个「光看签名猜不到」的参数都在调用处写了语义。

## 两种接线形态

| 形态 | 入口 | 适合 | 代价 |
|---|---|---|---|
| **A 五步库直连**（`cmd/pipeline`） | `lexer.tokenize → parser.parse → TypeChecker.check → codegen.compile → VitroVM` | 任意阶段截停（只 typeck 不跑）、直接持有 VM 观测结构、教学卡片一行 `ec.catalog()` 拿结构体 | 要懂五步管线；无会话语义 |
| **B gateway NDJSON**（`cmd/protocol`） | `@gateway.invoke(String) -> String` | 帧流（`step.next` 批式）/ 断点 / `input.feed` 续跑 / 输出分页游标 / config 预设——与仓内浏览器 demo 同源通道 | 全 JSON 文本面，自己拼/解帧；协议面以随包 `docs/spec/CLI_PROTOCOL_V1.md` 为准 |

## 运行

```bash
cd examples/downstream-mini-c
moon check                                   # 首跑会从 mooncakes 拉 vitro/engine@0.9.1

# 形态 A（三目标输出逐字一致——B3 批实测 wasm/js/native 三连 cmp）
moon run cmd/pipeline                        # 默认 wasm（moonrun）
moon run --target js cmd/pipeline            # node
MOON_CC=clang-cl moon run --target native cmd/pipeline   # Windows（见下「目标面」）

# 形态 B（gateway 的 supported_targets 不含默认 wasm——须显式目标）
moon run --target js cmd/protocol
```

预期输出（形态 A 三案例）：案例 1 `hello from vitro! 42` / 案例 2 typeck 诊断 +
E3004 教学卡片 / 案例 3 scanf 读预给定 stdin 得 `got 21, doubled=42`。形态 B 全链
`session.create → compile → run(123 步) → step.begin → step.next ×123 批 → output.delta
"sum=10\n" → session.destroy`。

## 目标面与工具链注意（R3 实踩）

- **`moon new` 模板默认 `preferred_target = "wasm"`，与 0.9.1 发布包的 gateway
  （`+wasm-gc +native +js`）不交**。import gateway 的子包不声明 `supported_targets`
  就 `moon check` 会报「Selected backend 'wasm' is incompatible ... requires
  '<自己>' whose active dependency graph supports [js, native, wasm-gc]」——措辞像自环
  依赖，实为目标面不交。解法见 `cmd/protocol/moon.pkg`（收窄 + run 时显式 `--target`）。
  B3 批已给仓内 gateway 补 `+wasm`，随下一版本发布后此坑消失。
- **Windows 下游项目 native 目标用 `MOON_CC=clang-cl`，不是 `clang`**：独立项目走
  MSVC 直连目标，裸 `clang` 非 cl 兼容驱动会被 moon **静默忽略**回落 MSVC 探测（警告
  「MOON_CC is ignored for Windows MSVC direct object native target」）。仓内 workspace
  的 `moon build` 面认 clang 是另一回事（根 AGENTS 纪律 11 / #117 边界）。
- **`moonc --version` 不识别，用 `moonc -v`**（工具链形态，非包问题）。

## 「光看签名猜不到」的参数（示例代码里都注了）

| 签名 | 含义 |
|---|---|
| `VitroVM::setup_from_output(o, argc, argv, vis_lines)` | `vis_lines` = 教学可视化事件投影 `(line, ty, ctx)` 三元组，来自 compile 响应的 `algorithm_matches.vis_events`；库直连不做算法标注时传 `[]` |
| `InputState::from_stdin_text(text, batch)` | `batch=true` 流耗尽即 EOF（scanf 返回 -1）——headless 正解；`false` 流耗尽回退 Waiting 等 `input.feed`（gateway 会话语义，库直连无 feed 通道勿用） |
| `lexer.tokenize(src, cpp_mode~)` | 缺省 false = C 域；C++ 子集语法要显式 true |
| `TypeChecker::check(program)` → 四元组 | `(lowered, errors, warnings, hints)`——**后续 codegen 必须喂返回的 lowered 树**（函数式重建，值进值出），hints 是非错非警的教学提示 |
| `vm.output.join(OutputKind::Stdout)` → `Bytes` | 输出面是字节保真（`putchar(200)` 落 1 字节 0xC8），文本化用引擎自带 `@util.utf8_text_partial`（非法序列折 U+FFFD、截断尾部宽容）——不必自写 bytes→String |；**下一版起可直接 `vm.output.join_text(OutputKind::Stdout)`**（#449 一等出口，本示例 pin 0.9.1 暂用两段式） |
| `@util.json_escape(s)` | 拼 NDJSON 请求时源码进 JSON 字符串域的转义单源（RFC 8259 全量控制字符）——不必手写 |

## 去哪找签名

`moon add` 后一切在 `.mooncakes/vitro/engine/`：

- `<pkg>/pkg.generated.mbti`——各包接口面（0.9.1 包 22 个；gateway 的在下一版本进包）
- `docs/spec/CLI_PROTOCOL_V1.md` / `STEP_PAYLOAD_SCHEMA_V0_1.md` / `DUMP_ARTIFACTS_V1.md`——协议面权威
- `README.md`——包清单与契约要点（L0–L8 每包一句职责）
- 全部 `.mbt` 源码随包分发——mbti 不含 doc comment（moon info 生成面限制），参数语义去源码的 `///` 注释找

## 这个示例不做什么

- 不进 CI、不挂 `moonbit/moon.work`——它是发布面消费者，仓内改源码不应连坐它；
  升版本时改 `moon.mod` 的 `vitro/engine@<ver>` 一处即可
- 不替代仓内 `demo/`（浏览器形态）与 `desktop/`（proton 测试壳）——那两个消费仓内构建产物
- 课程叙述（`course/*/lesson.md`）、语言包产物、算法侧栏数据不随包——下游要自建（R3 ⑤ 资产清单）
