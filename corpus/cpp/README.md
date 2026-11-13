# corpus/cpp 状态标注（deferred）

> **C1 卫生批标注（2026-11-13）**：本桶 83 例 `.cpp` 为 C++ E2E 探索期（S9 期）入库资产。

- **状态**：**deferred——非承诺面**。C++ 专属路径已随 S9 裁定剔除（typeck convert 的 Reference/RValueRef/is_upcast 分支剔除登记、codegen C only 裁剪；前端核心语言 = C 单语言定稿见 [#491](https://github.com/rustin-beep/Vitro/issues/491)）。parser 层保留 C++ 分支（class/template 可解析进 AST——ast 包确含 C++ 节点族），本桶是**parser 面潜在资产**而非 e2e 面。
- **消费现状**：全仓零消费——CI 与防线脚本零引用（clang_direct 的 cpp 桶属自动跳过的非直拍面）；facts 计数键 `cpp_e2e_cases` 已退役（键名「e2e」虚指对拍面，2026-11-13 C1 卫生批）。
- **去留**：随 1.0 退役评估统一裁定（Go 防线层与三外援终局评估同批）；在此之前原地保留、不新增、不删除。
