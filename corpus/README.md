# corpus — 语料来源与许可说明

`corpus/` 是引擎对拍防线的 C/C++ 语料集（1,100+ 文件）。**除 `chibicc_port/` 移植自 chibicc（MIT）外，全部语料为本仓库自写或 LLM 生成，不含任何上游文本/代码拷贝**；上游编号（K&R 习题号、LeetCode 题号）仅作文件命名索引、便于追溯对应题目，题面与流传解答文本均未入库。

LLM 生成语料一律经 clang 对拍防线验收（clang golden + 三臂 js/native/wasm 对拍，见 `docs/current/07-质量与裁定/`）；AI 生成内容披露以本节为准。

| 目录 | 规模 | 来源 | 命名规约 |
|:---|:---|:---|:---|
| `baseline/` | 560 `.c` + 15 `.h` + 13 `.in` | 自写基线语料（`.in` 为 scanf/stdio 输入面对拍语料） | 主题式 snake_case；多数文件带 `@category` 头注 |
| `chibicc_port/` | 36 | **移植自 [chibicc](https://github.com/rui314/chibicc) 测试集（MIT, © 2019 Rui Ueyama）**——唯一上游来源目录，许可义务由**逐文件头注**承接（`source:` 字段注明上游文件与 © 行） | 沿用上游测试名 |
| `codegen_skeleton/` | 13 | 自写（代码生成骨架用例：无穷字面量、标识符、字符数组等边界面） | 主题式 snake_case |
| `cpp/` | 83 | 自写 C++ 特性/经典算法小例 | `cpp_<主题>.cpp` |
| `gap/` | 23 | 自写差异面探针（complex.h、fopen 等引擎↔clang 行为边界） | 主题式 snake_case，`@category` 头注 |
| `knr/` | 81 | **LLM 生成解答**（未参考上游文本与流传解答集）；`kr_<章>_<题>` 指向《K&R》第 2 版习题号，仅作索引 | `kr_<章>_<题>.c` |
| `leetcode/` | 138 | **LLM 生成解法**（未参考题面文本与题解）；`lc_<题号>` 指向 LeetCode 题号，仅作索引 | `lc_<题号>.c` |
| `llm_multifile/` | 36 项目（112 `.c/.h`） | LLM 生成多文件项目语料 | `MF-<主题>/` 目录，内含 `main.c` 等多文件 |
| `llm_scale/` | 6 | LLM 生成千行级压力语料（来源与入库批次见各文件头注） | `llm_scale_<主题>.c` |
| `mutator_probe/` | 1 | 自写变异探针种子 | `seed_all.c` |
| `template_generated/` | 82 | Rust 对照区时代 E2E **自写模板**的发射产物（模板源自写；随档记录 `E2E_FAILURES.md` 所引 `native/tests/` 路径已随 2026-10-05 删区退役） | `<主题>_default.c`，`@category: baseline` 头注 |

## 许可

- 本目录语料随仓库以 [MIT](../LICENSE) 发布（与仓库根 LICENSE 一致）。
- `chibicc_port/` 的上游 MIT 许可义务（保留版权与许可声明）由各文件头注的 `source:` 字段承接。

> 口径：表内规模为 2026-11-10 实测的 `.c/.h` 主口径；`baseline` 另有 13 个 `.in` 对拍输入文件。
