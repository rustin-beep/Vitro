// 协议面的阅读清单（#222 P1 内存/协议形态，2026-10-22）。
//
// 单源：ProtoView（主页方法分组）与 ProtoSide（右栏「本页消费 x / 25」）共用本表，
// 避免两处各写一份方法清单导致计数漂移。`used` = 本页是否消费该方法——与旧
// ProtoView 的 15 行清单逐项同义（未消费只在工具组显式标 —，不假装全用）。
//
// 口径注：METHOD_TOTAL = 协议 v0.2 冻结方法面 25（既有 ProtoView 头口径）；
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
      { name: "semantic_labels", desc: "步进语义标注词表（14 类——S8 step 流的呈现层词汇）", used: true },
      { name: "step.begin / next / seek / breakpoints.set", desc: "时间旅行采集：重建 / 批次推进 / 引擎级跳转 / 断点下发", used: true },
    ],
  },
  {
    id: "lifecycle",
    title: "配置与生命周期",
    items: [
      { name: "config.get / config.set", desc: "确定性 / 步数上限 / 调用深度 / 隔离区预算（4 可写字段）", used: true },
      { name: "session.create / reset / destroy", desc: "会话生命周期（create 清 runtime 域，config 需显式回设）", used: true },
      { name: "capabilities", desc: "schema 冻结 + v0.2 台账 + languages + memory_model", used: true },
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

/** 协议 v0.2 冻结方法面（既有 ProtoView 头口径）。 */
export const METHOD_TOTAL = 25;

/** 本页组清单行数（四组之和）。 */
export const METHOD_ROWS = METHOD_GROUPS.reduce((s, g) => s + g.items.length, 0);

/** 本页实际消费的方法数（used=true 的行数）。 */
export const METHOD_USED = METHOD_GROUPS.reduce((s, g) => s + g.items.filter((i) => i.used).length, 0);

/** 单组消费计数（组内 used / 组内行数）。 */
export function groupUsed(g: MethodGroup): number {
  return g.items.filter((i) => i.used).length;
}
