// 虚拟模块 "virtual:demo-globals" 类型（vite.config.ts 的 demoGlobals 插件
// 构建期合成 cases.js + algorithms.js 的 ESM 视图）。字段形态对齐 wire 面
// 现役消费（course.ts buildChapters / cases.js DemoCase）；结构性演进随
// wire 面扩，不锁全量。
declare module "virtual:demo-globals" {
  export interface DemoCase {
    id: string;
    label: string;
    blurb?: string;
    source: string;
    stdin?: string;
    configHint?: Record<string, unknown>;
    [k: string]: unknown;
  }
  export interface AlgoVariant {
    id: string;
    tpl: string;
    source: string;
    [k: string]: unknown;
  }
  export interface AlgoItem {
    id: string;
    name: string;
    template: string;
    source: string;
    variants?: AlgoVariant[];
    [k: string]: unknown;
  }
  export interface AlgoGroup {
    id: string;
    label: string;
    items?: AlgoItem[];
    xitems?: AlgoItem[];
    [k: string]: unknown;
  }
  export const DEMO_CASES: DemoCase[];
  export const DEMO_ALGORITHMS: { groups: AlgoGroup[] };
}
