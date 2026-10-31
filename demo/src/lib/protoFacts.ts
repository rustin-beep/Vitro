// 协议面的阅读清单（#222 P1 内存/协议形态，2026-10-22）。
//
// 单源：ProtoView（主页方法分组）与 ProtoSide（右栏「本页消费 x / 25」）共用本表，
// 避免两处各写一份方法清单导致计数漂移。`used` = 本页是否消费该方法——与旧
// ProtoView 的 15 行清单逐项同义（未消费只在工具组显式标 —，不假装全用）。
//
// 口径注：METHOD_TOTAL = 协议方法面 26（#323 texts.get 起；既有 ProtoView 头口径）；
// METHOD_ROWS = 本页组清单行数（15）；两者分母不同，页面上分列不混算。
"use strict";

export interface MethodFact {
  name: string;
  desc: string;
  used: boolean;
}

export interface MethodGroup {
  id: string;
  title: string;
  items: MethodFact[];
}

export const METHOD_GROUPS: MethodGroup[] = [
  {
    id: "exec",
    title: "编译与执行",
    items: [
      { name: "compile", desc: "源码 → 编译；files 多编译单元 / filename；诊断含修复建议", used: true },
      { name: "run", desc: "执行；finished / trap / waiting_input；params 支持 argv 与 input", used: true },
      { name: "output.delta", desc: "stdout / stderr / note / display 四视图，游标制增量", used: true },
      { name: "input.feed", desc: "stdin 喂入续跑（交互程序）", used: true },
    ],
  },
  {
    id: "observe",
    title: "观测与教学",
    items: [
      { name: "memory.regions", desc: "内存白箱：三段式区域 + free_list + 隔离区", used: true },
      { name: "error_catalog", desc: "诊断目录（C 卡按 lang 过滤；含 common_causes 与修复建议）", used: true },
      { name: "semantic_labels", desc: "步进语义标注词表（条数见下方词表区——S8 step 流的呈现层词汇）", used: true },
      { name: "step.begin / next / seek / breakpoints.set", desc: "时间旅行采集：重建 / 批次推进 / 引擎级跳转 / 断点下发", used: true },
    ],
  },
  {
    id: "lifecycle",
    title: "配置与生命周期",
    items: [
      { name: "config.get / config.set", desc: "确定性 / 步数上限 / 调用深度 / 隔离区预算（4 可写字段）", used: true },
      { name: "session.create / reset / destroy", desc: "会话生命周期（create 清 runtime 域，config 需显式回设）", used: true },
      { name: "capabilities", desc: "schema 冻结 + v0.2 台账（languages / memory_model 已拉取，本页未展开）", used: true },
      { name: "contracts", desc: "行为契约 + v0.2 激活清单", used: true },
    ],
  },
  {
    id: "tools",
    title: "未消费 / 工具",
    items: [
      { name: "memory.dump", desc: "1MB 映像 base64 导出（CLI --dump-memory / vm_diff 映像联）", used: false },
      { name: "algorithms.catalog", desc: "算法族目录（#36 上线——课程数据引擎单源）", used: false },
      { name: "ping / shutdown", desc: "探活与关停", used: true },
    ],
  },
];

/** 协议方法面（错误帧自报口径；#323 texts.get 起 = 26，未入本页分组清单——本页不消费）。 */
export const METHOD_TOTAL = 26;

/** 本页组清单行数（四组之和；一行可能展开多个方法，如 step.* 一行 4 个）。 */
export const METHOD_ROWS = METHOD_GROUPS.reduce((s, g) => s + g.items.length, 0);

/** 单行展开成多少个方法名（'step.begin / next / seek' → 4）。 */
export function methodNames(m: MethodFact): string[] {
  return m.name.split("/").map((s) => s.trim()).filter(Boolean);
}

/** 单组方法数（展开后）：本页消费 / 组内方法总数。 */
export function groupMethodStats(g: MethodGroup): { used: number; total: number } {
  let used = 0;
  let total = 0;
  for (const m of g.items) {
    const c = methodNames(m).length;
    total += c;
    if (m.used) used += c;
  }
  return { used, total };
}

/** 本页清单展开后的方法总数（22）。 */
export const METHOD_LISTED = METHOD_GROUPS.reduce((s, g) => s + groupMethodStats(g).total, 0);

/** 本页实际消费的方法数（按方法展开，20）——大数字口径用它，不混行数。 */
export const METHOD_USED = METHOD_GROUPS.reduce((s, g) => s + groupMethodStats(g).used, 0);

/** 行级消费数（15 行里 13 行有 ✓；仅用于行口径展示/断言）。 */
export const METHOD_USED_ROWS = METHOD_GROUPS.reduce((s, g) => s + g.items.filter((i) => i.used).length, 0);

/** 单组行级消费计数（组内 used / 组内行数）——行口径。 */
export function groupUsed(g: MethodGroup): number {
  return g.items.filter((i) => i.used).length;
}
