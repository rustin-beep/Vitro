#!/usr/bin/env node
// gen_svg.mts —— 文档插图生成器（#273 存量 Go 重写批；原 scripts/gen_svg/main.go，
// 探针转正 Go 重写 2026-09-20 → 十五张图，2026-10-25 页脚命令翻新批）。
//
// 入库插图的跑批快照数字**只在此处为模板**：生成时从 reports/facts.json 读真值
// 注入，并以 <tspan data-fact="key">n</tspan> 显式锚定；scripts/facts check 逐锚
// 机判漂移。漂移工作流：
//
//   跑防线（或 go run ./scripts/facts facts）→ facts check 红（SVG 数字过时）
//   → node scripts/gen_svg/main.mts → facts check 绿
//
// 建成状态类内容（包图实/虚线、在架版本徽标）同样 facts 派生——CI 重生成闸红
// 不了「生成器源码过时」，故状态词一律不写死，改由 facts 采集器供给机械真值。
//
// 禁止手改入库 SVG 的 data-fact 锚定数字——下次生成即回退（facts 的
// interactiveSync 也刻意跳过 .svg 命中）。设计常量（2000 帧 / 50 检查点 /
// 256KB 隔离预算等）不是跑批快照、无锚，改动属代码常量变更，走评审。
//
// 用法（flag 在前）：
//   node scripts/gen_svg/main.mts [-check] [arch|cache|kg|shadow|packages|uarch|
//                                  ustate|memory|protocol|wasm|gates|skills|
//                                  panorama|teach|all]
//
// -check：与落盘 SVG 逐字节比对，漂移列清单后 exit 1，无写副作用（CI hygiene
// 闸用；J9 证红：手改任一落盘 SVG 后 -check 必红）。
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { spawnSync } from "node:child_process";
import {
  MARKER_DEF,
  arrow,
  arrowPoly,
  box,
  drifts,
  fatal,
  line,
  loadFacts,
  mustFactS,
  setCheckMode,
  svgOpen,
  textF,
  textL,
  writeSVG,
  type FactsDoc,
} from "./svg.mts";
import { genPanorama } from "./panorama.mts";
import { genTeach } from "./teach.mts";

// ─── 图 A：架构总览（源：README 单轨口径节 + 架构设计.md §2）─────────────────

export function genArch(root: string): void {
  const P: string[] = svgOpen(
    1200,
    724,
    "vitro 架构总览图",
    "vitro — MoonBit 现役单轨 · 引擎 + Go 防线 + Clang 真值",
    "内容对账 README.md 单轨口径节 与 架构设计.md §2；进度与版本以 README / 总计划 §10 为权威（无快照数字，无 data-fact 锚）",
  );
  P.push(
    MARKER_DEF,
    textF(600, 56, "tt", "vitro — MoonBit 现役单轨 · 引擎 + Go 防线 + Clang 真值", ""),
  );
  // 主轨：MoonBit 现役引擎
  P.push(
    box(40, 96, 1120, 300, "core", 14),
    textF(600, 128, "t", "MoonBit 现役引擎 · vitro/engine（mooncakes 源码级发布）", ""),
  );
  const pipe: { x: number; name: string; desc: string }[] = [
    { x: 64, name: "lexer", desc: "独立 pass · LineMap" },
    { x: 280, name: "parser", desc: "depth 守卫" },
    { x: 496, name: "typeck", desc: "定型 + lowering" },
    { x: 712, name: "codegen", desc: "槽位 v1" },
    { x: 928, name: "bytecode", desc: "产物 schema 单源" },
  ];
  pipe.forEach((c, i) => {
    const cx = c.x + 95;
    P.push(
      box(c.x, 148, 190, 60, "card", 10),
      textF(cx, 174, "tn", c.name, ""),
      textF(cx, 196, "tc", c.desc, ""),
    );
    if (i < pipe.length - 1) P.push(arrow(c.x + 190, 178, c.x + 216, 178, "edge"));
  });
  const base: { x: number; name: string; desc: string }[] = [
    { x: 64, name: "memory", desc: "MemoryMap + check_access 单入口" },
    { x: 428, name: "host", desc: "路由表 + Bytes 输出通道" },
    { x: 792, name: "vm", desc: "穷尽 executor + VMSnapshot" },
  ];
  for (const c of base) {
    const cx = c.x + 172;
    P.push(
      box(c.x, 224, 344, 62, "zone", 10),
      textF(cx, 250, "tn", c.name, ""),
      textF(cx, 274, "tc", c.desc, ""),
    );
  }
  P.push(
    box(64, 302, 1072, 32, "card", 10),
    textF(600, 324, "tm", "S8 已落：time_travel 时间旅行 · teaching/steps 教学判据 · diagnostics 教学诊断 · protocol/session/gateway 会话协议", ""),
  );
  P.push(
    box(64, 348, 1072, 32, "card", 10),
    textF(600, 370, "tm", "出口：wasm-gc 单出口多宿主（浏览器 Worker · Node · .NET）+ native stdio 壳 cmd/serve · cmd/vitro", ""),
  );
  // 中带：Go 司法与防线层
  P.push(
    line(600, 396, 600, 420, "line"),
    box(40, 420, 1120, 150, "zone", 14),
    textF(600, 450, "t", "Go 司法与防线层（归一化器 · 对拍驱动 · 生成器）", ""),
  );
  const diffs: { x: number; name: string; desc: string }[] = [
    { x: 64, name: "lexer_diff", desc: "token TSV" },
    { x: 280, name: "parser_diff", desc: "AST+诊断归一" },
    { x: 496, name: "typeck_diff", desc: "E1–E4" },
    { x: 712, name: "codegen_diff", desc: "字节码逐指令" },
    { x: 928, name: "vm_diff", desc: "执行轨迹" },
  ];
  diffs.forEach((c, i) => {
    const cx = c.x + 95;
    P.push(
      box(c.x, 470, 190, 56, "card", 10),
      textF(cx, 494, "tn", c.name, ""),
      textF(cx, 516, "tc", c.desc, ""),
    );
    if (i < diffs.length - 1) P.push(arrow(c.x + 190, 498, c.x + 216, 498, "edge"));
  });
  P.push(
    textF(600, 552, "tc", "对拍真值 = 冻结 golden（工序③固化锚）· 层 2 直拍 clang_direct（Clang 唯一真值）· facts check · 生成器 -check 闸", ""),
  );
  // 底部：Rust oracle 退役档案条
  P.push(
    line(600, 570, 600, 594, "line"),
    box(40, 594, 1120, 66, "warn", 14),
    textF(600, 620, "t", "Rust 冻结对照 oracle — 已退役（2026-10-05 工序④删区，native/ 物理删除）", ""),
    textF(600, 644, "tc", "档案：tag rust-oracle-freeze · 分支 frozen-oracle-snapshot · git 历史（探测档案提交 917251e）", ""),
    textF(600, 694, "tc", "对账 README 单轨口径节 + 架构设计.md §2 · 漂移重生成：node scripts/gen_svg/main.mts arch", ""),
  );
  writeSVG(root, "docs/current/01-定位与路线/vitro-architecture.svg", P);
}

// ─── 图 B：统一模式·三态缓存（源：统一模式设计.md §2.1 表格 + §5.2）──────────

export function genCache(root: string): void {
  const P: string[] = svgOpen(
    1200,
    716,
    "vitro 统一模式三态缓存",
    "统一模式 · 三态缓存（Triple-Cache）",
    "对账 统一模式设计.md §2.1 表格三行 + §5.2 CheckpointManager 落地更新；数字为设计常量（非快照，无 data-fact 锚）",
  );
  P.push(
    textF(600, 56, "tt", "统一模式 · 三态缓存（Triple-Cache）", ""),
    textF(600, 92, "tm", "90% 操作只访问 Frame Cache（零延迟）· 10% 操作恢复 Active VM（从 Checkpoint 懒加载）· 只有一个“当前 VM”", ""),
  );
  // 每列行布局独立：Checkpoint 列的 <(i32, VMSnapshot)> 行曾与"全量+增量混合"
  // 同段溢出框边（视觉验收 2026-09-20 fail），拆为两行。
  interface Row {
    dy: number;
    cls: string;
    s: string;
  }
  const cols: { x: number; rows: Row[] }[] = [
    {
      x: 30,
      rows: [
        { dy: 42, cls: "t", s: "Frame Cache" },
        { dy: 70, cls: "ts", s: "time_travel FrameWindow" },
        { dy: 94, cls: "tc", s: "滑动窗口（2000 帧）" },
        { dy: 120, cls: "ts", s: "Array[StepPayload]" },
        { dy: 150, cls: "tm", s: "动画渲染 / 变量面板 / 进度条拖动" },
        { dy: 182, cls: "tm", s: "大小：2~5MB（1000 步）" },
      ],
    },
    {
      x: 430,
      rows: [
        { dy: 42, cls: "t", s: "Checkpoint" },
        { dy: 72, cls: "tc", s: "time_travel.CheckpointManager" },
        { dy: 102, cls: "ts", s: "Array[(Int, VMSnapshot)]" },
        { dy: 128, cls: "tm", s: "全量 + 增量混合" },
        { dy: 156, cls: "tm", s: "VM 状态恢复·继续执行" },
        { dy: 184, cls: "tm", s: "大小：全量 50MB → 增量 5~10MB" },
      ],
    },
    {
      x: 830,
      rows: [
        { dy: 42, cls: "t", s: "Active VM" },
        { dy: 76, cls: "tc", s: "MoonBit 引擎（vitro/engine/vm）" },
        { dy: 112, cls: "ts", s: "VitroVM 实例" },
        { dy: 148, cls: "tm", s: "当前可执行的 VM 状态" },
        { dy: 182, cls: "tm", s: "大小：1MB" },
      ],
    },
  ];
  for (const c of cols) {
    const cx = c.x + 170;
    P.push(box(c.x, 130, 340, 210, "card", 14));
    for (const r of c.rows) P.push(textF(cx, 130 + r.dy, r.cls, r.s, ""));
  }
  P.push(
    line(200, 340, 200, 430, "line"),
    line(600, 340, 600, 430, "line"),
    line(1000, 340, 1000, 430, "line"),
    line(200, 430, 1000, 430, "line"),
    line(600, 430, 600, 470, "line"),
    box(120, 470, 960, 146, "warn", 12),
    textF(600, 508, "t", "CheckpointManager 落地机制（§5.2，MoonBit 侧随 S8 落地）", ""),
    textF(600, 540, "tc", "每 full_every 个检查点存完整 1MB 全量，其余仅存被修改的 4KB 脏页", ""),
    textF(600, 566, "tc", "上限 max_checkpoints = 50 · smart_mode 语义关键点强制保存", ""),
    textF(600, 592, "tc", "隔离区 quarantine 必须随快照往返，否则时间旅行回退后 UAF 检测出现假阴性", ""),
    textF(600, 640, "tc", "Frame Cache 权威副本在引擎内；消费方经 serve payload.get / gateway step 族取用，不得假设窗口外历史仍可查询", ""),
  );
  writeSVG(root, "docs/current/05-教学体验/unified-triple-cache.svg", P);
}

// ─── 图 C：认知推理·概念图谱（源：认知推理系统设计.md §3.1 三域树）────────────

export function genKG(root: string): void {
  const P: string[] = svgOpen(
    1200,
    780,
    "vitro 认知推理概念图谱",
    "P2 知识图谱 · C 语言概念三域（已实现）",
    "对账 认知推理系统设计.md §3.1 节点分类树；P2 状态=已实现（24 节点 + 30+ 边）",
  );
  P.push(
    textF(600, 54, "tt", "P2 知识图谱 · C 语言概念三域", ""),
    textF(600, 88, "tm", "已实现：概念激活 activate_from_error / activate_from_ast · 先修路径 find_prerequisite_path · vitro/engine/diagnostics", ""),
  );
  const domains: { name: string; x: number; nodes: string[] }[] = [
    {
      name: "编译概念域",
      x: 60,
      nodes: [
        "变量声明 VarDecl",
        "类型系统 TypeSystem",
        "· 隐式转换 / 指针类型",
        "运算符 Operators",
        "· 算术 / 逻辑 / 位运算",
        "作用域 Scope",
      ],
    },
    {
      name: "内存概念域",
      x: 460,
      nodes: [
        "栈内存 StackMemory",
        "堆内存 HeapMemory",
        "指针 Pointer",
        "· 取址 / 解引用 / 指针算术",
        "数组 Array（· 数组退化）",
        "结构体布局 StructLayout",
      ],
    },
    {
      name: "控制流概念域",
      x: 860,
      nodes: [
        "条件分支 IfSwitch",
        "循环 Loop",
        "· for / while / 边界条件",
        "函数调用 FunctionCall",
        "· 参数传递 / 返回值",
        "递归 Recursion",
      ],
    },
  ];
  for (const d of domains) {
    const cx = d.x + 150;
    P.push(
      box(d.x, 150, 300, 64, "core", 14),
      textF(cx, 191, "t", d.name, ""),
      line(cx, 214, cx, 246, "line"),
      box(d.x, 246, 300, 364, "card", 12),
    );
    d.nodes.forEach((n, i) => {
      P.push(textF(cx, 286 + i * 52, n.startsWith("·") ? "tm" : "t", n, ""));
    });
  }
  P.push(
    box(160, 660, 880, 100, "warn", 12),
    textF(600, 696, "t", "学生遇错 / 浏览代码 → 动态激活相关概念子图，展示知识间关联", ""),
    textF(600, 722, "tc", "现有基础：error_catalog 中文解释 · 7 种 AST 模式识别", ""),
    textF(600, 748, "tc", "（模板 knowledge_nodes 标注已随 #40 作废——如需概念标注走 diagnostics 域）", ""),
  );
  writeSVG(root, "docs/current/05-教学体验/cognitive-knowledge-graph.svg", P);
}

// ─── 图 D：影子验证·门禁流水线（源：影子验证框架.md §一/§三/§2.3）────────────
// 本图的跑批快照数字全部 data-fact 锚定 facts 台账。

export function genShadow(root: string): void {
  // 工序④删区（2026-10-05）：原锚 shadow（被测物 = Rust DLL）随区退役，重绘为
  // 删区后语义——Clang 直拍门禁完整流水线（corpus 双臂 → 逐字节比对 → 判定
  // 三分流）。数字口径化零 facts 依赖（同 genGates 先例）：hygiene 的 facts 步
  // 为 `--strict check`（无 --run），run 型键在 CI 检出态为 unavailable，
  // mustFact 会把 -check 闸 fatal（2026-10-05 推送后 CI 红实锤）。
  const P: string[] = svgOpen(
    1200,
    860,
    "vitro Clang 直拍门禁流水线",
    "Clang 直拍框架 · 真值对照与 CI 硬门禁",
    "对账 docs/current/04-标准库与防线/Clang直拍门禁.md §1–§5（文件名随防线更名 clang-direct-gate-flow.svg）；结构图无数字锚（测试数见 README 机判行）",
  );
  // 顶：标题 + 定位副题
  P.push(
    MARKER_DEF,
    textF(600, 54, "tt", "Clang 直拍 · 真值对照与 CI 硬门禁", ""),
    textF(600, 94, "tm", "层 2 直拍活真值——「golden 固化锚 + 引擎」的共同偏差只有本防线兜得住（与 vm_diff 五闸互补）", ""),
  );
  // 左列主流水线：语料 → 双臂 → 比对 → 三分流
  P.push(
    box(40, 128, 720, 66, "zone", 12),
    textF(400, 156, "t", "语料 corpus/ 六目录全量", ""),
    textF(400, 182, "tc", "baseline · knr · leetcode · gap · codegen_skeleton · template_generated", ""),
  );
  P.push(arrow(215, 194, 215, 238, "line"), arrow(585, 194, 585, 238, "line"));
  P.push(
    box(40, 238, 350, 136, "card", 12),
    textF(215, 270, "ts", "Clang 本尊（真值源）", ""),
    textF(215, 298, "tc", "clang 编译 + 运行 → golden", ""),
    textF(215, 322, "tc", "stdout + 返回码 · golden 唯一来源", ""),
    textF(215, 346, "tc", "缓存：源码 + stdin + 版本 + 参数", ""),
    box(410, 238, 350, 136, "card", 12),
    textF(585, 270, "ts", "MoonBit cmd/run（被测物）", ""),
    textF(585, 298, "tc", "stdout + 返回码", ""),
    textF(585, 322, "tc", "Latin-1 归一后折回单字节比对", ""),
    textF(585, 346, "tc", "exe 新鲜度门禁（MOON_CC=clang）", ""),
  );
  P.push(
    arrowPoly("215,374 215,398 400,398 400,424", "line"),
    arrowPoly("585,374 585,398 400,398 400,424", "line"),
  );
  P.push(
    box(140, 424, 520, 70, "card", 12),
    textF(400, 452, "t", "逐字节比对（纯 stdout 通道）", ""),
    textF(400, 480, "tc", "引擎附注 / stderr 独立通道不进比对 · stdin 同份字节注入", ""),
  );
  P.push(
    arrowPoly("400,494 400,516 153,516 153,540", "line"),
    arrow(400, 494, 400, 540, "line"),
    arrowPoly("400,494 400,516 647,516 647,540", "line"),
  );
  P.push(
    box(40, 540, 226, 110, "card", 12),
    textF(153, 574, "ts", "SAME", ""),
    textF(153, 602, "tc", "通过", ""),
    textF(153, 626, "tc", "含双侧编译失败等价", ""),
    box(287, 540, 226, 110, "card", 12),
    textF(400, 574, "ts", "DIFF-known", ""),
    textF(400, 602, "tc", "白名单放行", ""),
    textF(400, 626, "tc", "case + digest 锁定", ""),
    box(534, 540, 226, 110, "warn", 12),
    textF(647, 574, "ts", "DIFF 非预期", ""),
    textF(647, 602, "tc", "exit 1 · CI 即红", ""),
    textF(647, 626, "tc", "无 Clang → exit 2", ""),
  );
  // 右列三卡：白名单纪律 / 语义要点 / vm_diff 分工
  P.push(
    box(780, 128, 390, 192, "zone", 14),
    textF(975, 160, "t", "白名单纪律（活文档）", ""),
    textL(804, 192, "tc", "每条 = 用例名 + 差异 digest 锁定"),
    textL(804, 218, "tc", "输出漂移 → digest 失配 → 降级红"),
    textL(804, 244, "tc", "修复转绿 → 即红逼移除（只减不增）"),
    textL(804, 270, "tc", "新增条目须先以 DIFF 形态露红"),
    textL(804, 296, "tc", "CI 前置 --check-known 逐条复现"),
  );
  P.push(
    box(780, 340, 390, 170, "zone", 14),
    textF(975, 372, "t", "三个语义要点（比对面）", ""),
    textL(804, 404, "tc", "① 纯 stdout 通道：附注 / stderr 不进"),
    textL(804, 430, "tc", "② stdin 注入：两侧同份字节"),
    textL(804, 456, "tc", "③ Latin-1 归一：0xC8 → 0xC3 0x88 折回"),
    textL(804, 482, "tc", "（U+0080–00FF 封闭域，无损可逆）"),
  );
  P.push(
    box(780, 530, 390, 170, "zone", 14),
    textF(975, 562, "t", "与 vm_diff 五闸分工", ""),
    textL(804, 594, "tc", "本防线：直面 Clang 活真值，"),
    textL(804, 620, "tc", "抓引擎与真值的一切偏差"),
    textL(804, 646, "tc", "vm_diff：对拍冻结 golden 抓回归"),
    textL(804, 672, "tc", "互补：固化锚共同偏差逃不过 Clang"),
  );
  // 底：删区清算 + CI 形态横条 + 脚注
  P.push(
    box(40, 726, 1120, 84, "warn", 12),
    textF(600, 758, "tm", "工序④删区批（2026-10-05）：shadow〔被测物 Rust DLL〕随区退役；语料域 698 例由本防线独挑", ""),
    textF(600, 788, "tm", "shadow 685 ⊆ clang_direct 698 差量 0 · 白名单逐条平移 · 瞬态异常（超时 / 启动失败 / 0xC0000005）重试不落缓存", ""),
  );
  P.push(textF(600, 838, "tc", "对账 Clang直拍门禁.md §1–§5 · 漂移重生成： node scripts/gen_svg/main.mts shadow", ""));
  writeSVG(root, "docs/current/04-标准库与防线/clang-direct-gate-flow.svg", P);
}

// ─── 图 E：MoonBit 包切分分层（源：MoonBit迁移总计划.md §4）───────────────────

interface PkgCell {
  name: string;
  desc: string;
  builtAs: string; // 空格分隔的 moonbit/ 相对包路径（对账 facts）
  extra: boolean; // 规划外围件（jit / CS 批）：恒虚线、不参与层计数
}
interface Layer {
  tag: string;
  name: string;
  rows: PkgCell[][];
  note: string;
}

/** builtAs 列的全部包都已建成（facts moonbit_built_packages）。空清单视为未建。 */
export function allBuilt(builtAs: string, built: Set<string>): boolean {
  if (builtAs === "") return false;
  for (const p of builtAs.split(/\s+/).filter((x) => x !== "")) {
    if (!built.has(p)) return false;
  }
  return true;
}

function sumWs(ws: number[]): number {
  return ws.reduce((a, b) => a + b, 0);
}

export function genPackages(root: string, fd: FactsDoc): void {
  // 2026-09-24 观感批：拆为编译侧（L0–L6）与执行与智能侧（L7–L9+仓库外）两张。
  // 2026-09-28 防漂移批：实/虚线与徽标全部改为 facts 派生（见下方 badgeOf）。
  const built = new Set<string>();
  for (const p of mustFactS(fd, "moonbit_built_packages").split(/\s+/).filter((x) => x !== "")) {
    built.add(p.replace(/^moonbit\//, ""));
  }
  const ver = mustFactS(fd, "moonbit_engine_version");

  const compile: Layer[] = [
    {
      tag: "L0",
      name: "零依赖",
      rows: [
        [
          { name: "vitro/engine/source", desc: "SourceLoc + 坐标契约（字节偏移 +1 · 双坐标）", builtAs: "source", extra: false },
          { name: "vitro/engine/opcode", desc: "135 opcodes 稳定编号（44–46 C# 异常三件 + 47–49 空号）", builtAs: "opcode", extra: false },
        ],
      ],
      note: "",
    },
    {
      tag: "L1",
      name: "诊断契约",
      rows: [
        [{ name: "vitro/engine/diag", desc: "ErrorCode 137 臂 + Severity + SourceLang + catalog JSON + 覆盖率断言", builtAs: "diag", extra: false }],
      ],
      note: "",
    },
    {
      tag: "L2",
      name: "抽象语法",
      rows: [
        [{ name: "vitro/engine/ast", desc: "Type 17 / Expr 26 / Stmt 16 + depth + 判等渲染单源", builtAs: "ast", extra: false }],
      ],
      note: "",
    },
    {
      tag: "L3",
      name: "名字单源",
      rows: [
        [{ name: "vitro/engine/names", desc: "InstKey→InstId→mangled Name 唯一产出口（parser / typeck 共依赖）", builtAs: "names", extra: false }],
      ],
      note: "",
    },
    {
      tag: "L4",
      name: "前端",
      rows: [
        [
          { name: "vitro/engine/lexer", desc: "独立预处理 pass + LineMap + 宿主 IO", builtAs: "lexer", extra: false },
          { name: "vitro/engine/parser", desc: "token→AST · 瀑布 + 声明符螺旋 · depth 守卫", builtAs: "parser", extra: false },
        ],
        [{ name: "csharp/lexer + csharp/parser", desc: "〔CS 批·S6 后〕C# 前端；插值字符串 hole 级 span", builtAs: "csharp/lexer csharp/parser", extra: true }],
      ],
      note: "",
    },
    {
      tag: "L5",
      name: "语义",
      rows: [
        [
          { name: "vitro/engine/typeck", desc: "定型 + lowering（4 Pass）", builtAs: "typeck", extra: false },
          { name: "vitro/engine/containers", desc: "JSON 数据驱动 · S9 裁定", builtAs: "containers", extra: false },
          { name: "vitro/engine/libc", desc: "单表签名 57 + 放行 175", builtAs: "libc", extra: false },
        ],
        [{ name: "csharp/typeck", desc: "〔CS 批〕引用语义 / 类系统 / 异常类型链 / ARC 插桩点判定（共享切线=表达式/语句层）", builtAs: "csharp/typeck", extra: true }],
      ],
      note: "",
    },
    {
      tag: "L6",
      name: "发射",
      rows: [
        [
          { name: "vitro/engine/codegen", desc: "compile/compile_library 双入口 · 槽位 v1", builtAs: "codegen", extra: false },
          { name: "vitro/engine/bytecode", desc: "产物 schema + libc 固定索引 + 路由表单源", builtAs: "bytecode", extra: false },
        ],
        [{ name: "csharp/codegen", desc: "〔CS 批〕ARC 插桩 / 异常映射 trap→Throw / 顶层语句入口合成", builtAs: "csharp/codegen", extra: true }],
      ],
      note: "",
    },
  ];
  const runtime: Layer[] = [
    {
      tag: "L7",
      name: "执行",
      rows: [
        [
          { name: "vitro/engine/memory", desc: "MemoryMap + checked_access 单入口", builtAs: "memory", extra: false },
          { name: "vitro/engine/host", desc: "路由表消费侧 · Bytes 输出通道 · 100+ handlers", builtAs: "host", extra: false },
        ],
        [
          { name: "vitro/engine/vm", desc: "executor 穷尽 match + snapshot 派生", builtAs: "vm", extra: false },
          { name: "vitro/engine/jit", desc: "〔S9 裁定批〕必须可整体移除", builtAs: "jit", extra: true },
        ],
      ],
      note: "",
    },
    {
      tag: "L8",
      name: "会话/协议",
      rows: [
        [
          { name: "vitro/engine/session", desc: "SessionConfig 值对象", builtAs: "session", extra: false },
          { name: "vitro/engine/protocol", desc: "schema + stream 差分", builtAs: "protocol", extra: false },
          { name: "vitro/engine/gateway", desc: "wasm-gc 导出 + NDJSON", builtAs: "gateway", extra: false },
        ],
      ],
      note: "",
    },
    {
      tag: "L9",
      name: "教学智能",
      rows: [
        [
          { name: "time_travel", desc: "seek / 检查点重放", builtAs: "time_travel", extra: false },
          { name: "teaching/steps", desc: "算法步骤语义", builtAs: "teaching/steps", extra: false },
          { name: "analysis", desc: "cfg / algorithms", builtAs: "analysis", extra: false },
          { name: "diagnostics", desc: "根因 / 误区", builtAs: "diagnostics", extra: false },
        ],
      ],
      note: "── 经 VmObserver / SourceProvider / AlgorithmContext 三接口依赖反转，不依赖 session",
    },
  ];

  // 层徽标：builtAs 全集机械计数（extra 不计入）。全建 = 在架版本；
  // 部分 = 在建 n/m；零 = 未开工——文字全部派生，无手工状态词可漂移。
  const badgeOf = (lr: Layer): string => {
    let total = 0;
    let have = 0;
    for (const row of lr.rows) {
      for (const pc of row) {
        if (pc.extra || pc.builtAs === "") continue;
        for (const p of pc.builtAs.split(/\s+/).filter((x) => x !== "")) {
          total++;
          if (built.has(p)) have++;
        }
      }
    }
    if (total > 0 && have === total) return ver + " 在架";
    if (have > 0) return `在建 ${have}/${total}`;
    return "未开工";
  };

  const drawLayers = (
    title: string,
    sub: string,
    layers: Layer[],
    canvasH: number,
    out: string,
    withOutside: boolean,
  ): void => {
    const P: string[] = svgOpen(
      1200,
      canvasH,
      "vitro MoonBit 包切分分层图",
      title,
      "对账 MoonBit迁移总计划.md §4 包切分总图逐层文字；实/虚线与在架版本机器对账 facts（moonbit_built_packages / moonbit_engine_version），批次权威=总计划 §10",
    );
    P.push(
      MARKER_DEF,
      textF(600, 56, "tt", title, ""),
      textF(600, 94, "tm", sub, ""),
    );
    let y = 118;
    for (const lr of layers) {
      let h = 12 + lr.rows.length * 72 + 12;
      if (lr.rows.length > 1) h += 10;
      if (lr.note !== "") h += 26;
      P.push(
        box(20, y, 1160, h, "card", 12),
        textL(40, y + 34, "t", lr.tag),
        textL(40, y + 62, "tc", lr.name),
      );
      const b = badgeOf(lr);
      if (b !== "") P.push(textL(1065, y + 34, "tc", b));
      lr.rows.forEach((row, j) => {
        const fy = y + 12 + j * 82;
        let ws: number[];
        switch (row.length) {
          case 1:
            ws = [880];
            break;
          case 2:
            ws = [433, 433];
            break;
          case 3:
            ws = [280, 280, 280];
            break;
          default:
            ws = [210, 210, 210, 210];
        }
        // Go 整数除法（向零截断）——此处全为正数，Math.trunc 等价；直接用
        // 浮点会让 x 变成 398.333… 并漏进 SVG 坐标（2026-10-23 对拍实锤）。
        const gap = ws.length > 1 ? Math.trunc((880 - sumWs(ws)) / (ws.length - 1)) : 0;
        let x = 175;
        row.forEach((pc, k) => {
          const w = ws[k] ?? 0;
          const pcls = pc.extra || !allBuilt(pc.builtAs, built) ? "plan" : "card";
          const nameCls = row.length > 2 ? "tn" : "ts";
          P.push(
            box(x, fy, w, 60, pcls, 10),
            textL(x + 16, fy + 26, nameCls, pc.name),
            textL(x + 16, fy + 50, "tc", pc.desc),
          );
          x += w + gap;
        });
      });
      if (lr.note !== "") P.push(textL(175, y + h - 16, "tc", lr.note));
      y += h + 18;
    }
    if (withOutside) {
      // 执行与智能侧附仓库外横条
      P.push(
        box(20, y, 1160, 60, "warn", 12),
        textL(40, y + 36, "t", "仓库外"),
        textL(175, y + 36, "tm", "Go 驱动层（保留·司法/驱动语言）· Node engine-host（新增薄层·golden 生成宿主）· spike 目录"),
      );
      y += 78;
    }
    // 脚注不含 as_of 日期：采集时刻烙进落盘产物后，任何环境重生成必漂
    //（2026-09-28 e35e4eb CI 实证——-check 的比对对象必须只含跨环境稳定内容）。
    P.push(
      textF(600, y + 24, "tc", "硬约束：依赖严格单向无环 · .mbti 只暴露 protocol / lexer.tokenize / typeck.check 三面 · 版本锚 protocol_version 编译期常量", ""),
      textF(600, y + 52, "tc", "虚线框 = 包目录未建（机器对账 facts: moonbit_built_packages）", ""),
      textF(600, y + 80, "tc", "权威：总计划 §10 · 漂移重生成：node scripts/gen_svg/main.mts packages", ""),
    );
    writeSVG(root, out, P);
  };

  const sub = "module vitro/engine · 依赖严格单向无环 · .mbti 取代 ABI 版本化成为对外义务载体";
  drawLayers("MoonBit 迁移 · 包切分分层（L0–L6 编译侧）", sub, compile, 1258, "docs/current/01-定位与路线/moonbit-package-layers-compile.svg", false);
  drawLayers("MoonBit 迁移 · 包切分分层（L7–L9 执行与智能侧）", sub, runtime, 748, "docs/current/01-定位与路线/moonbit-package-layers-runtime.svg", true);
}

// ─── 图 F：统一模式架构总览（源：统一模式设计.md §3 ASCII 架构图）────────────

export function genUnifiedArch(root: string): void {
  const P: string[] = svgOpen(
    1200,
    902,
    "vitro 统一模式架构总览",
    "统一模式 · 架构总览",
    "对账 统一模式设计.md §3 架构总览图（消费方前端 → 出口 → session → time_travel → VitroVM；实现锚已随删区/S8 切换 MoonBit 侧）",
  );
  P.push(
    MARKER_DEF,
    textF(600, 56, "tt", "统一模式 · 架构总览", ""),
    textF(600, 94, "tm", "消费方前端（社区实现）经出口触及 session 会话层与 time_travel 采集引擎；seek 越窗 = 最近 Checkpoint 恢复 + 正向重放", ""),
  );
  // 消费方前端
  P.push(
    box(40, 112, 1120, 240, "core", 14),
    textL(64, 146, "t", "消费方前端（社区实现；本仓库不含前端）"),
  );
  const comps: { x: number; name: string; desc: string }[] = [
    { x: 64, name: "CodeEditor + Heatmap", desc: "代码编辑 + 执行热力条带" },
    { x: 424, name: "ExecControlPanel", desc: "Play / Pause / Step / Slider" },
    { x: 784, name: "AlgoCanvas / VisPanel", desc: "算法可视化 · 变量 · 内存面板" },
  ];
  for (const c of comps) {
    const cx = c.x + 168;
    P.push(
      box(c.x, 162, 336, 76, "card", 12),
      textF(cx, 192, "t", c.name, ""),
      textF(cx, 220, "tc", c.desc, ""),
    );
  }
  P.push(
    box(64, 254, 1056, 94, "card", 12),
    textF(592, 282, "t", "消费方执行控制器（阶段机 + 本地视图缓存）", ""),
    textF(592, 310, "tc", "FrameCache（窗口内 payload 的本地副本，可选）· StateMachine: Idle / Collecting / Paused / Playback / Seeking", ""),
    textF(592, 334, "tc", "CurrentStep: int", ""),
  );
  // 出口带（加高：文字与后端框缘脱开）
  P.push(
    arrow(600, 352, 600, 414, "line"),
    textL(620, 378, "tm", "出口：serve JSON-lines / wasm gateway / vitro api 单帧"),
    textL(620, 404, "tc", "出口只做薄包装，语义一律取自 session 会话层"),
  );
  // MoonBit 后端
  P.push(
    box(40, 421, 1120, 405, "core", 14),
    textL(64, 455, "t", "MoonBit 后端（vitro/engine）"),
  );
  P.push(
    box(200, 462, 800, 50, "card", 10),
    textF(600, 492, "t", "session —— 语言中立会话语义层（各出口共用同一套入口语义）", ""),
  );
  P.push(
    arrow(600, 512, 600, 536, "line"),
    box(100, 536, 1000, 200, "card", 12),
    textF(600, 568, "ts", "time_travel 采集引擎（vitro/engine/time_travel）", ""),
  );
  const ue: { x: number; name: string; desc: string }[] = [
    { x: 130, name: "collect", desc: "StepPayload 逐帧采集" },
    { x: 450, name: "CheckpointMgr", desc: "save · nearest 恢复" },
    { x: 770, name: "VM (Active)", desc: "memory 1MB · VMSnapshot" },
  ];
  for (const u of ue) {
    const cx = u.x + 150;
    P.push(
      box(u.x, 584, 300, 80, "zone", 10),
      textF(cx, 614, "t", u.name, ""),
      textF(cx, 636, "tc", u.desc, ""),
    );
  }
  // 三小卡汇流到 VitroVM
  P.push(
    line(280, 664, 280, 706, "line"),
    line(600, 664, 600, 706, "line"),
    line(920, 664, 920, 706, "line"),
    line(280, 706, 920, 706, "line"),
    arrow(600, 706, 600, 746, "line"),
    box(100, 746, 1000, 76, "card", 12),
    textF(600, 774, "t", "VitroVM：step() · snapshot() / restore() · 内存读（check_access 单入口）", ""),
    textF(600, 800, "tc", "快照/恢复实现 vitro/engine/time_travel + vm · 隔离区 quarantine 必须随快照往返", ""),
  );
  P.push(
    textF(600, 854, "tc", "一致性契约：seek 到第 N 步后 local_vars / call_stack / array_snapshots / pointer_snapshots / heatmap_count 以第 N 步快照为准（spec §4.3）", ""),
    textF(600, 880, "tc", "对账 统一模式设计.md §3 · 漂移重生成：node scripts/gen_svg/main.mts uarch", ""),
  );
  writeSVG(root, "docs/current/05-教学体验/unified-architecture.svg", P);
}

// ─── 图 G：统一模式六状态机（源：统一模式设计.md §4 状态图 + §4.1/§4.2）──────

export function genStateMachine(root: string): void {
  const P: string[] = svgOpen(
    1200,
    920,
    "vitro 统一模式六状态机",
    "统一模式 · 六状态有限状态机",
    "对账 统一模式设计.md §4 状态图与 §4.2 关键状态转换（边文字逐条取原文）",
  );
  P.push(
    MARKER_DEF,
    textF(600, 56, "tt", "统一模式 · 六状态有限状态机", ""),
    textF(600, 94, "tm", "所有用户操作都触发状态转换（§4）· 边标注 = 用户操作原文", ""),
  );
  const states: { x: number; y: number; name: string; hint: string }[] = [
    { x: 70, y: 150, name: "Idle", hint: "编辑器可编辑" },
    { x: 500, y: 150, name: "Collecting", hint: "自动前进·动画跟随" },
    { x: 930, y: 150, name: "Playback", hint: "执行结束·可自由拖动" },
    { x: 500, y: 430, name: "Paused", hint: "进度暂停·动画定格" },
    { x: 930, y: 430, name: "Seeking", hint: "拖动中·动画跟随" },
    { x: 500, y: 690, name: "StepMode", hint: "单步·类似传统调试器" },
  ];
  for (const s of states) {
    const cx = s.x + 100;
    P.push(
      box(s.x, s.y, 200, 78, "card", 12),
      textF(cx, s.y + 34, "t", s.name, ""),
      textF(cx, s.y + 64, "tc", s.hint, ""),
    );
  }
  P.push(
    arrow(270, 189, 500, 189, "edge"),
    textF(385, 174, "tc", "编译运行", ""),
    arrow(700, 172, 930, 172, "edge"),
    textF(815, 158, "tc", "执行结束", ""),
    arrow(930, 206, 700, 206, "edge"),
    textF(815, 232, "tc", "继续执行", ""),
    arrow(570, 228, 570, 430, "edge"),
    textF(516, 330, "tc", "暂停", ""),
    arrowPoly("500,728 440,728 440,210 500,210", "edge"),
    textF(360, 560, "tc", "自动播放", ""),
    arrow(600, 508, 600, 690, "edge"),
    textF(654, 600, "tc", "继续", ""),
    arrow(1030, 228, 1030, 430, "edge"),
    textF(1100, 330, "tc", "拖动进度条", ""),
    arrow(985, 430, 985, 228, "edge"),
    textF(922, 330, "tc", "恢复完成", ""),
    arrow(930, 469, 700, 469, "edge"),
    textF(815, 456, "tc", "用户暂停/拖动", ""),
    arrowPoly("500,748 150,748 150,228", "cons"),
    textF(310, 700, "tc", "任何状态：修改代码", ""),
    textF(310, 726, "tc", "→ 提示重新编译、重置缓存", ""),
    textF(205, 258, "tc", "点击“重跑”", ""),
    box(60, 800, 1080, 84, "card", 12),
    textF(600, 832, "t", "seek 一致性契约（spec/STEP_PAYLOAD_SCHEMA_V0_1.md §4.3）", ""),
    textF(600, 862, "tc", "seek 到第 N 步：local_vars / call_stack / array_snapshots / pointer_snapshots / heatmap_count 以第 N 步快照为准（消费方整体重绘）", ""),
  );
  writeSVG(root, "docs/current/05-教学体验/unified-state-machine.svg", P);
}

// ─── 图 H：1MB 线性内存布局与有界隔离（源：内存安全规范 §3.4 + 堆有界隔离决议）─

export function genMemory(root: string): void {
  const P: string[] = svgOpen(
    1200,
    900,
    "vitro 线性内存布局与有界隔离",
    "VitroVM · 1MB 线性内存布局 + 堆有界隔离（Bounded Quarantine）",
    "对账 内存安全规范.md §3.4 + 堆有界隔离决议.md §1–§5；地址段为设计常量（非快照，无 data-fact 锚）",
  );
  P.push(
    MARKER_DEF,
    textF(600, 56, "tt", "VitroVM · 1MB 线性内存布局 + 堆有界隔离", ""),
    textF(600, 94, "tm", "VM 的堆不是宿主 allocator，而是 1MB 线性内存中的一段；释放不立即归还，先进有界隔离区（FIFO 驱逐复用）", ""),
  );
  interface SegRow {
    dy: number;
    cl: string;
    s: string;
  }
  const segs: { y0: number; y1: number; cls: string; rows: SegRow[] }[] = [
    { y0: 122, y1: 242, cls: "zone", rows: [{ dy: 36, cl: "t", s: "栈 Stack（顶 = 1MB）" }, { dy: 66, cl: "tc", s: "自高地址向下 ↓" }, { dy: 92, cl: "tc", s: "局部变量 / 调用帧" }] },
    { y0: 242, y1: 322, cls: "zone", rows: [{ dy: 34, cl: "t", s: "argv" }, { dy: 64, cl: "tc", s: "自 0x10000（64KB）向下分配" }] },
    { y0: 322, y1: 402, cls: "bg", rows: [{ dy: 50, cl: "tc", s: "（未用地址空间）" }] },
    { y0: 402, y1: 522, cls: "warn", rows: [{ dy: 34, cl: "t", s: "隔离区 quarantine" }, { dy: 64, cl: "tc", s: "FIFO · 预算 = 堆上限 1/4 = 256KB" }, { dy: 90, cl: "tc", s: "超预算驱逐最老已释放块" }] },
    { y0: 522, y1: 582, cls: "zone", rows: [{ dy: 40, cl: "tc", s: "bump 已分配 ↑（顶指针 O(1)）" }] },
    { y0: 582, y1: 642, cls: "zone", rows: [{ dy: 40, cl: "tc", s: "first-fit 复用（驱逐后归还）" }] },
    { y0: 642, y1: 722, cls: "zone", rows: [{ dy: 32, cl: "t", s: "全局区（0x1000 起）" }, { dy: 60, cl: "tc", s: "全局变量·extern·vtable·字符串字面量·静态局部" }] },
    { y0: 722, y1: 776, cls: "bg", rows: [{ dy: 32, cl: "tc", s: "0x0–0x1000 保留" }] },
  ];
  for (const sg of segs) {
    if (sg.cls !== "bg") P.push(box(150, sg.y0, 410, sg.y1 - sg.y0, sg.cls, 0));
    for (const r of sg.rows) P.push(textF(355, sg.y0 + r.dy, r.cl, r.s, ""));
  }
  const ticks: { y: number; a: string }[] = [
    { y: 122, a: "0x100000" },
    { y: 322, a: "0x10000" },
    { y: 642, a: "0x5000" },
    { y: 722, a: "0x1000" },
    { y: 776, a: "0x0" },
  ];
  for (const tk of ticks) {
    P.push(line(116, tk.y, 150, tk.y, "cons"), textL(20, tk.y + 7, "ts", tk.a));
  }
  P.push(
    box(610, 122, 560, 192, "card", 12),
    textF(890, 154, "t", "bump 分配 + 有界隔离（决议 2026-09-11）", ""),
    textL(630, 188, "tc", "malloc：顶指针 O(1) 推进；隔离超预算 → 先 FIFO 驱逐"),
    textL(630, 214, "tc", "free：标记 + 进 FIFO 隔离区，不立即归还"),
    textL(630, 240, "tc", "realloc：恒为新块拷贝（与 glibc 常见路径一致）"),
    textL(630, 266, "tc", "heap_base = max(0x5000, align4(global_data_end))（R1）"),
    textL(630, 292, "tc", "预算会话可调：vitro_set_quarantine_budget（默认 256KB）"),
  );
  P.push(
    box(610, 334, 560, 208, "card", 12),
    textF(890, 366, "t", "教学四场景（churn / leak 正确分离）", ""),
    textL(630, 400, "tc", "churn：隔离稳态 ≤ 预算，驱逐复用 → 无限可跑（不误伤）"),
    textL(630, 426, "tc", "leak：不进隔离区，bump 推进 → 撞 1MB 墙 → 教学 trap"),
    textL(630, 452, "tc", "UAF：检测窗口 = 最近 256KB free 历史，覆盖率极高"),
    textL(630, 478, "tc", "Double-Free：隔离窗口内地址不复用 → 必检出"),
    textL(630, 504, "tc", "时间旅行：隔离窗口内内存单调（CoW 与确定性受益）"),
  );
  P.push(
    box(610, 562, 560, 140, "card", 12),
    textF(890, 594, "t", "三道墙（决议 §6，全部已实施）", ""),
    textL(630, 628, "tc", "① 1MB 堆墙：malloc 耗尽 → 返 NULL + 教学 trap"),
    textL(630, 654, "tc", "② 步数保险丝 max_steps（会话配置，reset 保留）"),
    textL(630, 680, "tc", "③ region 表封顶（记账侧有界）"),
  );
  P.push(
    box(610, 722, 560, 92, "zone", 12),
    textL(630, 750, "tc", "MoonBit vitro/engine/memory 已建包（S6）"),
    textL(630, 774, "tc", "MemoryMap + check_access 单入口 + FreedLogs 二分"),
    textL(630, 798, "tc", "地址布局常量定义点仍在 L6 bytecode"),
  );
  P.push(
    textF(600, 848, "tc", "诚实记录：隔离窗口外 UAF 可能漏检——free 与误用之间 churn 超过 256KB 后，*p 落在已复用块（同 ASAN quarantine 行为）", ""),
    textF(600, 874, "tc", "布局示意不按比例 · 对账 内存安全规范 §3.4 + 堆有界隔离决议 · 漂移重生成：node scripts/gen_svg/main.mts memory", ""),
  );
  writeSVG(root, "docs/current/01-定位与路线/memory-layout-quarantine.svg", P);
}

// ─── 图 I：StepPayload v0.1 帧结构（源：docs/spec/STEP_PAYLOAD_SCHEMA_V0_1.md §0–§5）──

export function genProtocol(root: string): void {
  const P: string[] = svgOpen(
    1200,
    940,
    "vitro StepPayload v0.1 帧结构",
    "StepPayload Schema v0.1 · 单步快照帧（已冻结）",
    "对账 docs/spec/STEP_PAYLOAD_SCHEMA_V0_1.md §0–§5；字段清单为 schema 冻结内容（非快照，无 data-fact 锚）",
  );
  P.push(
    textF(600, 56, "tt", "StepPayload Schema v0.1 · 单步快照帧", ""),
    textF(600, 94, "tm", "已冻结（2026-09-12 · S1–S5 签字回放 61/61）· 语言中立，任何语言按此解析步数据，无需了解引擎内部表示", ""),
    textF(600, 138, "tc", "（同一语义）出口：serve JSON-lines（step / payload.get）· gateway wasm 帧 · vitro api 万能单帧", ""),
    box(40, 174, 720, 638, "core", 14),
    textL(64, 204, "ts", "StepPayload（单步快照 · 14 顶层字段）"),
    textL(64, 234, "tc", "── 步定位 ──"),
    textL(64, 258, "ts", "step_index"),
    textL(280, 258, "tc", "int32 · 步号 0 起；一步 = 一条字节码指令"),
    textL(64, 282, "ts", "code_line"),
    textL(280, 282, "tc", "int32 · 源码行 1 起（0 = 无源码行）"),
    textL(64, 306, "ts", "func_name"),
    textL(280, 306, "tc", "string · 教学可读名（main / bubble_sort）"),
    textL(64, 330, "ts", "semantic_label"),
    textL(280, 330, "tc", "string · 行 + 值推断的教学语义标签"),
    textL(64, 362, "tc", "── 教学快照 ──"),
    textL(64, 386, "ts", "local_vars"),
    textL(280, 386, "tc", "ApiVariableSnapshot[] · 当前作用域变量"),
    textL(64, 410, "ts", "call_stack"),
    textL(280, 410, "tc", "ApiFrameInfo[] · 自底向上，末元素 = 当前帧"),
    textL(64, 434, "ts", "array_snapshots"),
    textL(280, 434, "tc", "ArraySnapshot[] · 元素上限 256，超出 truncated"),
    textL(64, 458, "ts", "pointer_snapshots"),
    textL(280, 458, "tc", "PointerSnapshot[] · 四状态见右侧"),
    textL(64, 490, "tc", "── 行为与事件 ──"),
    textL(64, 514, "ts", "vis_events"),
    textL(280, 514, "tc", "VisEvent[] · 取走式：同一步不重复投递"),
    textL(64, 538, "ts", "heatmap_*"),
    textL(280, 538, "tc", "heatmap_line + heatmap_count · 该行累计执行次数"),
    textL(64, 562, "ts", "accessed_vars"),
    textL(280, 562, "tc", "AccessedVar[] · 本步读写的变量"),
    textL(64, 594, "tc", "── 可空（JSON null）──"),
    textL(64, 618, "ts", "algorithm_step"),
    textL(280, 618, "tc", "AlgorithmStepSnapshot? · 未命中算法模板 = null"),
    textL(64, 642, "ts", "root_cause_hint"),
    textL(280, 642, "tc", "RootCauseHint? · 无运行时陷阱 = null"),
    textL(64, 690, "tc", "多文件会话：code_line / heatmap_line 为合并源码全局行号（§8 #9）"),
    textL(64, 716, "tc", "地址：1MB 线性内存内 u32（0x1000 全局区起 · 0x5000 堆起 · 栈自高向下）"),
    textL(64, 742, "tc", "可空 = null；消费方须同时容忍字段缺省（新字段可不出现在旧数据）"),
    textL(64, 768, "tc", "枚举取值为字符串字面量，大小写敏感（\"Valid\" / \"Read\"）"),
  );
  P.push(
    box(800, 174, 370, 156, "card", 12),
    textF(985, 204, "t", "pointer 四状态（§3.1）", ""),
    textL(820, 234, "tc", "Valid 有效"),
    textL(820, 260, "tc", "Freed 已释放（判定依赖隔离区）"),
    textL(820, 286, "tc", "Null 空指针"),
    textL(820, 312, "tc", "Dangling 悬垂"),
  );
  P.push(
    box(800, 350, 370, 170, "card", 12),
    textF(985, 382, "t", "frameCache 窗口语义（§4）", ""),
    textL(820, 412, "tc", "payload.get(start, end)：窗口内 O(1)"),
    textL(820, 438, "tc", "越窗 seek：Checkpoint 恢复 + 正向重放"),
    textL(820, 464, "tc", "seek 第 N 步 → 五视图以第 N 步快照为准"),
    textL(820, 490, "tc", "（消费方整体重绘，无需自行回退状态）"),
  );
  P.push(
    box(800, 540, 370, 170, "card", 12),
    textF(985, 572, "t", "差分编码与版本纪律（§5 / §9）", ""),
    textL(820, 602, "tc", "StepStreamBatch / Delta 字段级差分"),
    textL(820, 628, "tc", "解码不变量：delta 后与全量逐字段相等"),
    textL(820, 654, "tc", "字段只增不改语义；新增字段可空 / 有默认"),
    textL(820, 680, "tc", "废弃走双写过渡期；版本 abi + engine"),
  );
  P.push(
    box(800, 730, 370, 104, "zone", 12),
    textF(985, 760, "t", "消费方", ""),
    textL(820, 788, "tc", "serve · gateway wasm · vitro api"),
    textL(820, 812, "tc", "任何第三方语言按本 schema 自行解析"),
  );
  P.push(
    textF(600, 852, "tc", "实现锚 MoonBit 侧：vitro/engine/protocol（schema · stream · types · vocabulary）· session（会话状态机）· gateway（出口帧）", ""),
    textF(600, 878, "tc", "对账 docs/spec/STEP_PAYLOAD_SCHEMA_V0_1.md §0–§5 · 漂移重生成：node scripts/gen_svg/main.mts protocol", ""),
  );
  writeSVG(root, "docs/spec/step-payload-frame.svg", P);
}

// ─── 图 J：wasm 多实例并发隔离（源：wasm多实例并发模型与U2拍板.md §1–§2）──────

export function genWasm(root: string): void {
  const P: string[] = svgOpen(
    1200,
    880,
    "vitro wasm 多实例并发隔离",
    "wasm 多实例并发模型 · 1 实例 = 1 线程 = 1 会话",
    "对账 wasm多实例并发模型与U2拍板.md §1 裁定结论 + §2 依据；三宿主形态表逐列对账",
  );
  P.push(
    textF(600, 56, "tt", "wasm 多实例并发隔离", ""),
    textF(600, 94, "tm", "裁定（2026-09-19）：每线程一个完全独立的引擎实例——隔离是 wasm 实例模型的构造性质，不依赖引擎侧线程安全改造", ""),
    box(40, 116, 390, 240, "warn", 14),
    textF(235, 150, "t", "反例：capi 单实例形态", ""),
    textF(235, 178, "tc", "（形态本身的构造缺陷，非可修 bug）", ""),
    textF(235, 210, "tc", "单进程单实例全局状态", ""),
    textF(235, 238, "tc", "DLL 并发调用 → 堆损坏（引擎非线程安全）", ""),
    textF(235, 266, "tc", "Vitro 侧调用必须互斥", ""),
    textF(235, 302, "tc", "wasm 多实例是其正解：同进程 N 实例", ""),
    textF(235, 330, "tc", "替代「N 进程 DLL 池」或「单实例互斥」", ""),
    box(470, 116, 700, 248, "core", 14),
    textL(494, 150, "t", "正解：同进程 N 个完全独立的引擎实例"),
  );
  for (let i = 0; i < 3; i++) {
    const x = 494 + i * 222;
    const cx = x + 100;
    P.push(
      box(x, 168, 200, 188, "card", 12),
      textF(cx, 198, "ts", `Instance ${i + 1}`, ""),
      textF(cx, 228, "tc", "1MB 线性内存 ✓", ""),
      textF(cx, 256, "tc", "全局状态 ✓", ""),
      textF(cx, 284, "tc", "VFS + rand MT19937 ✓", ""),
      textF(cx, 312, "tc", "GC 堆（wasm-gc）", ""),
      textF(cx, 338, "tc", "绑定 1 线程 · 1 会话", ""),
    );
  }
  P.push(
    box(40, 384, 1130, 68, "core", 12),
    textF(605, 414, "t", "铁律：1 实例 = 1 线程 = 1 会话——同一实例不得跨线程并发调用", ""),
    textF(605, 440, "tc", "实例内部保持单线程不是缺陷：判分确定性与 seek 回放可重放的来源", ""),
  );
  const hosts: { x: number; name: string; rows: string[] }[] = [
    {
      x: 40,
      name: "浏览器（IBrowserHost · 终局）",
      rows: ["N × Web Worker", "Module 结构化克隆进各 worker", "各自 instantiate", "（编译一次 · 实例化 N 次）", "铁律硬度：结构性（worker 各持）"],
    },
    {
      x: 425,
      name: "Node",
      rows: ["worker_threads", "structuredClone 支持", "WebAssembly.Module 转移", "铁律硬度：结构性"],
    },
    {
      x: 810,
      name: ".NET 内嵌（Wasmtime）",
      rows: ["每线程独立 Store + Instance", "Module 编译一次（Send+Sync）", "每线程 Store::new + instantiate", "铁律硬度：类型系统强制", "Store 非 Sync：跨线程共享编译失败"],
    },
  ];
  for (const h of hosts) {
    const cx = h.x + 180;
    P.push(box(h.x, 480, 360, 214, "card", 12), textF(cx, 514, "t", h.name, ""));
    h.rows.forEach((r, j) => {
      P.push(textF(cx, 548 + j * 28, j === 0 ? "ts" : "tc", r, ""));
    });
  }
  P.push(
    textL(60, 740, "tc", "边界（诚实记录）：宿主 import 面不在构造性隔离内——输出/输入通道由宿主提供，输出挂宿主全局（console / 单管道）会交错；"),
    textL(60, 766, "tc", "宿主须按实例绑定输出回调；serve 的 session id 概念平移，宿主只做帧路由。"),
    textL(60, 798, "tc", "容量参考：serve RSS 预算 64MB、实测峰值 ~24MB/会话——N 的上限由内存决定，不是并发正确性。"),
    textL(60, 830, "tc", "实证缺口：同进程 N 实例并发互不干扰尚无实测记录（拍板生效前补锚）· wasm32 现产冒烟 3.75MB 即具备全部并发性质。"),
    textF(600, 862, "tc", "对账 wasm多实例并发模型与U2拍板.md §1–§2 · 漂移重生成：node scripts/gen_svg/main.mts wasm", ""),
  );
  writeSVG(root, "docs/current/06-出口与协议/wasm-multi-instance-isolation.svg", P);
}

// ─── 图 K：MoonBit 自建验证防线全景（源：脚本总清单与必跑防线.md §1/§2 + ci.yml）─

export function genGates(root: string): void {
  // 本图零 facts 依赖：moonbit_test_passed 的采集依赖 moon test（CI --run 形态下
  // 疑似秒挂 → unavailable → mustFact 会把 -check 闸 fatal）。数字由 README 的
  // moonbit_test_passed 机判行 + scripts/moonbit/testcount 三向对账承载。
  const P: string[] = svgOpen(
    1200,
    900,
    "vitro MoonBit 自建验证防线全景",
    "MoonBit 自建验证防线 · 对拍链与闸卫",
    "对账 docs/current/02-构建与上手/脚本总清单与必跑防线.md §1/§2 与 .github/workflows/ci.yml hygiene job；结构图无数字锚（测试数见 README 机判行）",
  );
  // 顶条：引擎白盒测试
  P.push(
    MARKER_DEF,
    textF(600, 56, "tt", "MoonBit 自建验证防线 · 对拍链与闸卫", ""),
  );
  P.push(box(40, 108, 1120, 62, "core", 12));
  P.push(textF(600, 146, "t", "moon test 引擎白盒 + 契约测试全绿（防线底座 · 数字见 README 机判行）", ""));
  // 左列：对拍链（差分五闸 + Clang 直拍）
  P.push(
    box(40, 190, 640, 300, "zone", 14),
    textF(360, 224, "t", "逐层对拍（MoonBit ↔ 冻结 golden，工序③固化锚）", ""),
  );
  const layers: { name: string; desc: string }[] = [
    { name: "lexer_diff", desc: "token TSV 双层逐字节一致" },
    { name: "parser_diff", desc: "AST + 诊断序列归一逐字节" },
    { name: "typeck_diff", desc: "E1–E4 四出口归一" },
    { name: "codegen_diff", desc: "字节码 code 段逐指令" },
    { name: "vm_diff", desc: "执行轨迹差分（cmd/run 对齐）" },
  ];
  layers.forEach((l, i) => {
    const y = 240 + i * 48;
    P.push(
      box(64, y, 592, 42, "card", 10),
      textL(84, y + 28, "tn", l.name),
      textL(230, y + 28, "tc", l.desc),
    );
  });
  P.push(
    line(360, 490, 360, 516, "line"),
    box(64, 516, 286, 84, "card", 10),
    textF(207, 548, "ts", "clang_direct", ""),
    textF(207, 574, "tc", "层 2 · Clang 编译运行直拍", ""),
    textF(207, 596, "tc", "吸收 shadow（2026-10-05）", ""),
    box(370, 516, 286, 84, "card", 10),
    textF(513, 548, "ts", "冻结 golden 锚", ""),
    textF(513, 574, "tc", "工序③固化 · 五闸对拍锚", ""),
    textF(513, 596, "tc", "oracle 退役后自持", ""),
  );
  // 右列：闸卫家族
  P.push(
    box(700, 190, 460, 410, "zone", 14),
    textF(930, 224, "t", "闸卫家族（-check 硬闸 · CI hygiene）", ""),
  );
  const guards: { name: string; desc: string }[] = [
    { name: "moonbit_surface", desc: "对外面对账" },
    { name: "pkg_deps", desc: "依赖单向无环" },
    { name: "mbti_sync", desc: ".mbti 接口面" },
    { name: "gen_diag 族 ×4", desc: "生成物新鲜度" },
    { name: "gen_protocol_fields", desc: "S7 字段单源" },
    { name: "gen_svg", desc: "插图重生成一致" },
    { name: "facts check", desc: "文档数字对账" },
    { name: "host_contract_map", desc: "host 契约对账" },
    { name: "toolchain_probe", desc: "工具链漂移探针" },
  ];
  guards.forEach((g, i) => {
    const y = 240 + i * 38;
    P.push(
      box(724, y, 412, 32, "card", 8),
      textL(742, y + 23, "tn", g.name),
      textL(962, y + 23, "tc", g.desc),
    );
  });
  // 底部：真值源与删区敞口清算
  P.push(
    box(40, 620, 1120, 76, "warn", 12),
    textF(600, 650, "t", "真值源", ""),
    textF(600, 678, "tc", "Clang = golden 唯一来源 · 对拍锚 = 冻结 golden（工序③固化）· Rust oracle 已退役（档案 tag rust-oracle-freeze）", ""),
  );
  P.push(
    box(40, 712, 1120, 96, "warn", 12),
    textF(600, 744, "t", "删区敞口清算（2026-10-05 删区批）", ""),
    textF(600, 772, "tc", "oracle 测试体量随删区消失——语料域差量经 clang_direct 吸收（shadow 685 ⊆ 698 差量 0）+ MoonBit 自建测试 + fuzz 不变量自检承接；", ""),
    textF(600, 796, "tc", "遗留敞口与逐项清算以总计划 §10 为权威", ""),
  );
  P.push(
    textF(600, 848, "tc", "对账 脚本总清单与必跑防线.md §1/§2 · 漂移重生成：node scripts/gen_svg/main.mts gates", ""),
  );
  writeSVG(root, "docs/current/02-构建与上手/moonbit-verification-gates.svg", P);
}

// ─── 图 L：Agent Skills 全景（源：.agents/skills/ 盘上目录 + frontmatter 扫描）─

const FM_LINE = /^([A-Za-z][\w-]*):\s*(.+?)\s*$/gm;

interface SkillInfo {
  name: string;
  desc: string;
}

/**
 * 扫描面 = git 入库文件（第十一轮审阅 P3-3，2026-10-09）：盘上目录扫描会把
 * gitignore 遮蔽的本地副本（jsonmbt-authoring——权威源在 jsonmbt 仓）也计入
 * ⇒ 本地 -check 假红（8 skill vs 入库 7）。按 git ls-files 取面 = 本地与 CI
 * 天然一致；无 git 环境（理论面）退盘上扫描并打警告。
 */
export function discoverSkills(root: string): SkillInfo[] {
  const dir = path.join(root, ".agents", "skills");
  const names: string[] = [];
  const r = spawnSync("git", ["-C", root, "ls-files", "--", ".agents/skills"], { encoding: "utf8" });
  if (r.status === 0) {
    const seen = new Set<string>();
    for (const line of (r.stdout ?? "").trim().split("\n")) {
      if (line === "") continue;
      const rel = line.replace(/\\/g, "/").replace(/^\.agents\/skills\//, "");
      const head = rel.split("/")[0] ?? "";
      if (head !== "" && !seen.has(head)) {
        seen.add(head);
        names.push(head);
      }
    }
  } else {
    process.stderr.write("gen_svg: 警告——git ls-files 不可用，退盘上目录扫描（本地副本可能计入）\n");
    let entries: fs.Dirent[];
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch (e) {
      return fatal(`读不到 .agents/skills/（skills 图输入源）: ${(e as Error).message}`);
    }
    for (const e of entries) if (e.isDirectory()) names.push(e.name);
  }
  names.sort();

  const out: SkillInfo[] = [];
  for (const e of names) {
    const p = path.join(dir, e, "SKILL.md");
    let text: string;
    try {
      text = fs.readFileSync(p, "utf8");
    } catch {
      continue; // git 面含已删未提交等瞬态——缺 SKILL.md 跳过
    }
    // CRLF 兼容（2026-09-29 J9 证红抓出）：Windows 工作区里 SKILL.md 是 CRLF，
    // "---\r\n" 不匹配 "---\n" 前缀会误报缺 frontmatter——归一后再解析。
    text = text.replace(/\r\n/g, "\n");
    if (!text.startsWith("---\n")) fatal("skills/" + e + ": SKILL.md 缺 YAML frontmatter");
    const end = text.slice(4).indexOf("\n---");
    if (end < 0) fatal("skills/" + e + ": frontmatter 未闭合");
    const meta = new Map<string, string>();
    FM_LINE.lastIndex = 0;
    const fmText = text.slice(4, end + 4);
    for (const m of fmText.matchAll(FM_LINE)) meta.set(m[1] ?? "", m[2] ?? "");
    const nm = meta.get("name") ?? "";
    const desc = meta.get("description") ?? "";
    if (nm === "" || desc === "") fatal("skills/" + e + ": frontmatter 缺 name 或 description");
    if (nm !== e) fatal(`skills/${e}: frontmatter name="${nm}" 与目录名不一致`);
    out.push({ name: e, desc });
  }
  if (out.length === 0) fatal(".agents/skills/ 下没有可绘制的 skill");
  out.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  return out;
}

/** 显示宽度估算（CJK 全角 = 2，其余 = 1）。 */
export function dispW(s: string): number {
  let w = 0;
  for (const ch of s) w += (ch.codePointAt(0) ?? 0) >= 0x2e80 ? 2 : 1;
  return w;
}

/**
 * 按显示宽度贪心折行，最多 maxLines 行；放不下时末行以 "…" 收尾。
 * 硬切点若落在英文单词中间（切点两侧都是词字符），回退到最近词边界——
 * 2026-09-29 视觉审实证 "generator"→"generat…"、"golden" 被拆行的缺陷。
 */
export function wrapDesc(s: string, maxUnits: number, maxLines: number): string[] {
  const isWord = (ch: string | undefined): boolean =>
    ch !== undefined && /^[A-Za-z0-9_-]$/.test(ch);
  const rs = Array.from(s);
  const lines: string[] = [];
  let i = 0;
  for (let ln = 0; ln < maxLines; ln++) {
    let w = 0;
    let j = i;
    let last = i;
    while (j < rs.length) {
      const rw = (rs[j]?.codePointAt(0) ?? 0) >= 0x2e80 ? 2 : 1;
      if (w + rw > maxUnits) break;
      w += rw;
      j++;
      last = j;
    }
    if (last === i) last = i + 1;
    if (last < rs.length && last > i && isWord(rs[last - 1]) && isWord(rs[last])) {
      let k = last;
      while (k > i + 1 && isWord(rs[k - 1])) k--;
      last = k;
    }
    lines.push(rs.slice(i, last).join("").replace(/ +$/, ""));
    i = last;
    if (i >= rs.length) return lines;
  }
  let tail = Array.from(lines[lines.length - 1] ?? "");
  // cutPos = 原串中 tail 末字符的下一个位置（宽度回退同步左移）——残词判据必须
  // 看它而非贪心停点：贪心常停在词后的分隔符上（探针实证 rs[cutPos]=' ' 使
  // isWord 假、残词漏判 "generat…"）。
  let cutPos = i + tail.length;
  while (dispW(tail.join("").replace(/ +$/, "")) > maxUnits - 2 && tail.length > 1) {
    tail = tail.slice(0, -1);
    cutPos--;
  }
  // 末行残词处理：tail 末词在原串中被腰斩（紧随原字符仍是词字符）时去掉整个残词再补 "…"。
  if (tail.length > 0 && cutPos < rs.length && isWord(tail[tail.length - 1]) && isWord(rs[cutPos])) {
    while (tail.length > 1 && isWord(tail[tail.length - 1])) tail = tail.slice(0, -1);
  }
  lines[lines.length - 1] = tail.join("").replace(/ +$/, "") + "…";
  return lines;
}

export function genSkills(root: string): void {
  const skills = discoverSkills(root);
  const W = 1200;
  const cardW = 550;
  const cardH = 170;
  const gapX = 20;
  const gapY = 22;
  const headH = 128;
  const warnH = 110;
  const units = 54;
  const rows = Math.ceil(skills.length / 2);
  const warnY = headH + rows * (cardH + gapY);
  const n1 = warnY + warnH + 32;
  const n2 = warnY + warnH + 60;
  const H = n2 + 30;
  const P: string[] = svgOpen(
    W,
    H,
    "vitro Agent Skills 全景",
    `Vitro Agent Skills · ${skills.length} 个项目专属操作手册`,
    "内容从 .agents/skills/ 盘上目录与 SKILL.md frontmatter 扫描生成——skill 增删改名 / 描述变更必致本图失步，gen_svg -check（CI）即红；权威清单 .agents/README.md",
  );
  P.push(
    textF(600, 56, "tt", `Vitro Agent Skills · ${skills.length} 个项目专属操作手册`, ""),
    textF(600, 94, "tm", "通用 Agent Skills 格式 · 不绑定特定工具 · ZCode 直接扫描工作区 · 其他工具 node .agents/install_skills.mts --all 安装", ""),
  );
  skills.forEach((s, i) => {
    const x = 40 + (i % 2) * (cardW + gapX);
    const y = headH + Math.floor(i / 2) * (cardH + gapY);
    P.push(box(x, y, cardW, cardH, "card", 12), textL(x + 24, y + 42, "tn", s.name));
    wrapDesc(s.desc, units, 2).forEach((ln, k) => {
      P.push(textL(x + 24, y + 78 + k * 30, "tc", ln));
    });
  });
  P.push(
    box(40, warnY, 1120, warnH, "warn", 12),
    textF(600, warnY + 36, "t", "透明度与防漂移（CI 双闸）", ""),
    textF(600, warnY + 68, "tc", "skill 内容全部可读：.agents/skills/<name>/SKILL.md（+ references/）· 任何 skill 变更必经 git diff 人审", ""),
    textF(600, warnY + 94, "tc", "frontmatter 校验 node .agents/install_skills.mts --list（CI）· 本图失步即 gen_svg -check 红（CI）", ""),
    textF(600, n1, "tc", "权威清单与维护义务：.agents/README.md · 漂移重生成：node scripts/gen_svg/main.mts skills", ""),
  );
  writeSVG(root, "docs/current/02-构建与上手/agent-skills-overview.svg", P);
}

// ─── 入口 ────────────────────────────────────────────────────────────────────

const TARGETS = [
  "arch",
  "cache",
  "kg",
  "shadow",
  "packages",
  "uarch",
  "ustate",
  "memory",
  "protocol",
  "wasm",
  "gates",
  "skills",
  "panorama",
  "teach",
] as const;

type Target = (typeof TARGETS)[number];

function runTarget(which: Target, root: string, fd: FactsDoc): void {
  switch (which) {
    case "arch":
      return genArch(root);
    case "cache":
      return genCache(root);
    case "kg":
      return genKG(root);
    case "shadow":
      return genShadow(root);
    case "packages":
      return genPackages(root, fd);
    case "uarch":
      return genUnifiedArch(root);
    case "ustate":
      return genStateMachine(root);
    case "memory":
      return genMemory(root);
    case "protocol":
      return genProtocol(root);
    case "wasm":
      return genWasm(root);
    case "gates":
      return genGates(root);
    case "skills":
      return genSkills(root);
    case "panorama":
      return genPanorama(root);
    case "teach":
      return genTeach(root);
  }
}

export function main(): void {
  // flag 在前（对账 Go 版 `gen_svg [-check] <target>`）：-check 任意位置识别，
  // 其余以 - 开头的参数 fail loud（Go flag 的「静默丢弃」不迁）。
  let check = false;
  const positional: string[] = [];
  for (const a of process.argv.slice(2)) {
    if (a === "-check" || a === "--check") check = true;
    else if (a.startsWith("-")) fatal(`未知参数 ${a}`);
    else positional.push(a);
  }
  setCheckMode(check);

  const which = positional[0] ?? "all";
  if (positional.length > 1) fatal(`多余参数 ${positional.slice(1).join(" ")}（一次只画一个目标）`);

  const root = process.cwd();
  if (!fs.existsSync(path.join(root, "go.mod"))) {
    fatal("请在项目根目录运行（找不到 go.mod）");
  }
  const fd = loadFacts(root);

  if (which === "all") {
    for (const t of TARGETS) runTarget(t, root, fd);
  } else if ((TARGETS as readonly string[]).includes(which)) {
    runTarget(which as Target, root, fd);
  } else {
    fatal(`未知目标: ${which}（可用: ${TARGETS.join(" / ")} / all）`);
  }

  if (check) {
    const ds = drifts();
    if (ds.length > 0) {
      process.stderr.write(
        `SVG 漂移 ${ds.length} 张（生成器输出与落盘不一致——禁手改，跑 node scripts/gen_svg/main.mts 重生成）：\n`,
      );
      for (const d of ds) process.stderr.write("  " + d + "\n");
      process.exit(1);
    }
    process.stdout.write("check ok：落盘 SVG 与生成器输出一致\n");
  }
}

// 入口守卫：被 node:test import 时只取纯函数，不落盘
if (
  process.argv[1] !== undefined &&
  pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url
) {
  main();
}
