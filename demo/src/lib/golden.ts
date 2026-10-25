// Vitro · Clang golden 对照（2026-10-18 前端改造）——纯函数、无副作用。
//
// 设计说明 §12.2 的收口：未到末帧只写「未到末帧 · 自动对照」，末帧才给
// 「✓ 与 Clang golden 一致 / ✗ 不一致」；编辑器内容已改则**诚实失效**
// （不拿旧预期比新代码——旧 RunMeta 的 stale 边界原样保留）。
//
// 真值来源：cases.js 的 referenceOutput / referenceTrap（CI shadow 防线预置
// 真值），不是页面手写的第二份期望。
"use strict";

export type GoldenKind = "none" | "stale" | "pending" | "ok" | "bad";

export interface GoldenState {
  kind: GoldenKind;
  /** 徽章短语（输出块头 / 诊断摘要共用）。 */
  label: string;
  /** 展开对照时的两行真值预览（ok/bad 才有）。 */
  detail?: string;
  /** 期望值（数组「已就位」推断复用）。 */
  expected?: string | undefined;
}

export interface GoldenCase {
  id?: string | undefined;
  label?: string | undefined;
  source?: string | undefined;
  referenceOutput?: string | undefined;
  referenceTrap?: string | undefined;
  referenceKind?: string | undefined;
}

export interface GoldenInput {
  kase: GoldenCase | null;
  source: string;
  outputs: { stdout: string; stderr: string; note: string };
  stopped: string;
  idx: number;
  total: number;
  /** 程序仍等 stdin（scanf）——采集停在等待态，不是「末帧」。 */
  waiting?: boolean;
  /** 断点暂停——采集停在断点行，不是「末帧」。 */
  paused?: boolean;
}

export function goldenOf(i: GoldenInput): GoldenState {
  const k = i.kase;
  if (!k || (k.referenceOutput == null && k.referenceTrap == null)) {
    return { kind: "none", label: "无 golden 真值" };
  }
  if (k.source != null && i.source !== k.source) {
    return { kind: "stale", label: "已修改 · 不对照", expected: k.referenceOutput };
  }
  if (i.total <= 0) return { kind: "pending", label: "未采集 · 自动对照", expected: k.referenceOutput };
  // 等待 stdin / 断点暂停都不是末帧：此时 stdout 只是执行前缀，拿来比
  // golden 必假红（scanf 课实测 ✗）。两种停点各自诚实标注。
  if (i.waiting) return { kind: "pending", label: "等待输入 · 未到末帧", expected: k.referenceOutput };
  if (i.paused) return { kind: "pending", label: "断点暂停 · 未到末帧", expected: k.referenceOutput };
  if (i.idx < i.total - 1) return { kind: "pending", label: "未到末帧 · 自动对照", expected: k.referenceOutput };

  if (k.referenceOutput != null) {
    const ok = i.outputs.stdout === k.referenceOutput;
    return {
      kind: ok ? "ok" : "bad",
      label: ok ? "✓ 与 Clang golden 一致" : "✗ 与 golden 不一致",
      expected: k.referenceOutput,
      detail: `Clang golden: ${JSON.stringify(k.referenceOutput)}\nVitro stdout : ${JSON.stringify(i.outputs.stdout)}`,
    };
  }
  const ok = (i.stopped || "").includes(k.referenceTrap ?? "\u0000");
  return {
    kind: ok ? "ok" : "bad",
    label: ok ? `✓ 诊断类别一致（含 ${k.referenceTrap}）` : "✗ 未复现预期诊断",
    expected: k.referenceTrap,
    detail: ok ? `参考真值：${k.referenceTrap}（CI shadow 防线断言）` : `未命中参考真值：${k.referenceTrap}`,
  };
}

/** golden 输出里的整型序列（数组「已就位」推断：值 = 最终位置）。
 *  非整型/不可解析 → null（不对非排序课作任何假设）。 */
export function goldenNumbers(kase: GoldenCase | null): number[] | null {
  const text = kase?.referenceOutput;
  if (!text) return null;
  const toks = text.trim().split(/\s+/).filter(Boolean);
  if (toks.length < 2) return null;
  const nums = toks.map(Number);
  return nums.every((n) => Number.isFinite(n) && Number.isInteger(n)) ? nums : null;
}
