// Vitro demo · 全局脚本声明（TS 惯用法重写批 2026-10-04，refs #28）。
// cases.js 是普通 <script>（非 module）先行加载挂 window——ESM 侧裸引用
// DEMO_CASES 走全局链，本文件是它的 ambient 声明（81 条 TS2304 的一类解）。
// 注意：本文件必须保持无顶层 import/export（否则沦为模块、ambient 失效）。

/** 预置用例（cases.js 数据文件的消费契约） */
interface DemoCaseFile {
  filename: string;
  source: string;
}

interface DemoCase {
  id: string;
  label: string;
  blurb: string;
  source: string;
  stdin?: string;
  /** 命令行参数（run params.argv 的用例声明形态） */
  argv?: string[];
  /** 多编译单元（compile params.files；首文件 = 编辑器内容） */
  files?: DemoCaseFile[];
  /** configHint.max_steps：长程序（infinite 类）放宽步数上限的用例提示 */
  configHint?: { max_steps?: number };
  /** 参考对照（Clang golden 预置真值——诚实边界：编辑器改动后不比对） */
  referenceKind?: "stdout" | "trap";
  referenceOutput?: string;
  referenceTrap?: string;
}

declare const DEMO_CASES: DemoCase[];

// 算法侧栏数据（algorithms.js = scripts/gen_demo_algorithms 机判产物；
// 形态见 AlgoItem——template "extra" = 演示覆盖源，其余为 templates/ 模板名）
interface DemoAlgoVariant {
  tpl: string;
  source: string;
}
interface DemoAlgoItem {
  id: string;
  name: string;
  template: string;
  source: string;
  variants?: DemoAlgoVariant[];
}
interface DemoAlgoXItem {
  id: string;
  name: string;
  source: string;
}
interface DemoAlgoGroup {
  id: string;
  label: string;
  items?: DemoAlgoItem[];
  xitems?: DemoAlgoXItem[];
}
declare const DEMO_ALGORITHMS: { groups: DemoAlgoGroup[] };
