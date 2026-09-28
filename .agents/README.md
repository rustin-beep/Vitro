# .agents/skills — Vitro 项目专属 Agent Skills

给 AI agent（及 clone 本仓库的贡献者）用的**操作手册**，覆盖那些"踩过实锤、每次都要重学"的项目流程。
格式为通用 Agent Skills 规范（目录 + `SKILL.md` + YAML frontmatter），**不绑定任何特定工具**。

## 与 AGENTS.md 的分工

- `AGENTS.md`（根 + 两分区）：每批都读入的**静态纪律与路由**，必须保持克制；
- `.agents/skills/`：**按需触发**的详细操作手册——agent 在命中触发场景时才加载，不占常驻上下文；
- 时点性事实（测试数、版本状态）一律以 `docs/current/`、`reports/facts.json`、总计划为权威，skill 只写流程与陷阱。

## 清单

| Skill | 触发场景 |
|---|---|
| `vitro-toolchain-upgrade` | `toolchain_probe` 红 / moon 工具链升级后 link-core 全挂 |
| `vitro-generator-contract` | 新写或改 `scripts/gen_*` 生成器、接 `-check` 闸、产物漂移排查 |
| `vitro-baseline-corpus-workflow` | 新增/修改 `native/tests/cases/` 语料、补 golden、加用例后防线红 |
| `vitro-facts-reconciliation` | `scripts/facts` 红/绿判读、写文档数字、J9 埋雷 |
| `vitro-release-playbook` | mooncakes 发版、publish 前彩排、下载计数排查 |
| `vitro-workspace-review` | 审阅未提交改动/最近提交批/人写脚本与方案主张（五阶段规程+演化机制） |

## 安装

```bash
go run .agents/install_skills.go --list        # 查看 + frontmatter 校验
go run .agents/install_skills.go --all         # 装到检测到的工具（用户级）
go run .agents/install_skills.go --tool claude # 装到 ~/.claude/skills
go run .agents/install_skills.go --dest <dir>  # 任意目录（其他工具）
```

**ZCode 用户无需安装**：ZCode 直接扫描工作区 `.agents/skills/`。
Claude Code 等其他工具按上面的命令装到各自目录；安装物是普通目录复制，删除即卸载。

## 维护义务

改动 skill 覆盖的流程（防线、生成器契约、facts 判据、发版步骤）时**连坐更新**对应 `SKILL.md`；
每个 skill 尾部有 `as_of` 日期，过期即疑。新增 skill 后跑一次 `go run .agents/install_skills.go --list` 确认校验绿。
