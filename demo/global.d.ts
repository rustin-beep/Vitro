// Vitro demo · 全局脚本声明（TS 惯用法重写批 2026-10-04，refs #28）。
// cases.js 是普通 <script>（非 module）先行加载挂 window——ESM 侧裸引用
// DEMO_CASES 走全局链，本文件是它的 ambient 声明（81 条 TS2304 的一类解）。
// 注意：本文件必须保持无顶层 import/export（否则沦为模块、ambient 失效）。

/** 预置用例（cases.js 数据文件的消费契约） */
interface DemoCase {
  id: string;
  label: string;
  blurb: string;
  source: string;
  stdin?: string;
  /** configHint.max_steps：长程序（infinite 类）放宽步数上限的用例提示 */
  configHint?: { max_steps?: number };
}

declare const DEMO_CASES: DemoCase[];
