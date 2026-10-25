// 本幕逐行注记（#222 P1 第五片，2026-10-21）：从帧流差分出「哪一行改了什么」。
//
// 口径（与拍板稿一致的一行一注记）：
//   - 只看**本幕**帧区间（scene.from..to）里、**当前帧及之前**已执行的帧；
//   - 每行取**最近一次执行**的差分（随单步/播放更新，不把整幕多次迭代叠在一行）；
//   - 局部量变化 → `t ← 5`；数组元素变化 → `a[1] ← 3`；
//   - 首帧没有前态可比 → 不猜（幕首的初始值由「局部变量」表承担，不塞进代码行）；
//   - 跨函数帧不做差分（不同栈帧的同名变量不是同一个量）；
//   - **归行校验**：局部量注记只在「该行源码确实写这个变量」时保留——语句级帧
//     会把 for 的 `j++` 并进循环体末行（实测 j 在 `a[j+1] = t` 帧已递增），不过滤
//     就会把 `j ← 1` 贴到不写 j 的行上；
//   - 单帧内同行最多 maxPerLine 条（多变量同时改时按顺序截断）。
//
// 纯函数：不碰 Svelte/CM6，锚在 tests/pure.test.mts。

/** 帧流的最小结构面（StepPayload 结构兼容——只取注记需要的字段）。 */
export interface StepLike {
  code_line: number;
  func_name?: string;
  local_vars?: Array<{ name: string; value: string; ty_name?: string; is_local?: boolean }>;
  array_snapshots?: Array<{ name: string; elements: string[] }>;
}

export interface LineAnnotation {
  line: number;
  /** 同行多条以 ` · ` 连接（例：`a[1] ← 3 · j ← 1`）。 */
  text: string;
  /** 该行注记来自哪一帧（最近一次执行）。 */
  frame: number;
}

/** 值过长时截断（注记是提示，不是数据表——完整值看局部变量面）。 */
function short(v: string): string {
  return v.length > 14 ? v.slice(0, 13) + "…" : v;
}

function escapeRe(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/** 该行源码是否**写入** name（`x =` / `x++` / `++x` / `x +=` …；数组元素写入
 *  `a[i] = v` 不算写 `a` 本身，数组面由快照负责）。 */
export function writesName(lineText: string, name: string): boolean {
  const n = escapeRe(name);
  const target = new RegExp(`(^|[^\\w.])${n}\\s*(?:[+\\-*/%&|^]?=|\\+\\+|--)(?!=)`);
  const prefix = new RegExp(`(?:\\+\\+|--)\\s*${n}(?![\\w\\[.])`);
  return target.test(lineText) || prefix.test(lineText);
}

function diffNotes(prev: StepLike, cur: StepLike, lineText: string): string[] {
  const out: string[] = [];
  const before = new Map((prev.local_vars ?? []).map((v) => [v.name, v.value]));
  for (const v of cur.local_vars ?? []) {
    // 数组整体值（int[5] 这类）不进 local 面——元素级变化由 array_snapshots 承担
    if (v.ty_name && v.ty_name.includes("[")) continue;
    const old = before.get(v.name);
    if (old === undefined || old !== v.value) {
      // 源码行存在但该行不写这个变量 → 属于语句边界归并（如并入末行的 j++），不贴注记
      if (lineText && !writesName(lineText, v.name)) continue;
      out.push(`${v.name} ← ${short(v.value)}`);
    }
  }
  const arrBefore = new Map((prev.array_snapshots ?? []).map((s) => [s.name, s.elements]));
  for (const s of cur.array_snapshots ?? []) {
    const old = arrBefore.get(s.name);
    if (!old || old.length !== s.elements.length) continue;
    for (let i = 0; i < s.elements.length; i += 1) {
      if (old[i] !== s.elements[i]) out.push(`${s.name}[${i}] ← ${short(s.elements[i] as string)}`);
    }
  }
  return out;
}

/** 本幕注记（截至 at 帧）：按源码行升序返回；无变化/无前态/跨函数 → 不产出。
 *  sourceLines 为 1-based 源码行（传入才做归行校验；不传 = 不校验，供纯测试/无源码面）。 */
export function sceneAnnotations(
  frames: StepLike[],
  from: number,
  to: number,
  at: number = to,
  sourceLines: string[] = [],
  maxPerLine = 2,
): LineAnnotation[] {
  const lo = Math.max(0, from);
  const hi = Math.min(to, at, frames.length - 1);
  if (hi < lo) return [];
  const byLine = new Map<number, { notes: string[]; frame: number }>();
  let prev: StepLike | null = lo > 0 ? (frames[lo - 1] ?? null) : null;
  for (let i = lo; i <= hi; i += 1) {
    const f = frames[i];
    if (!f) continue;
    if (f.code_line <= 0) continue; // 收尾帧无当前行：保留 prev，不拿空数据当「全都变了」
    if (prev && prev.code_line > 0 && prev.func_name === f.func_name) {
      const notes = diffNotes(prev, f, sourceLines[f.code_line - 1] ?? "");
      if (notes.length) byLine.set(f.code_line, { notes: notes.slice(0, maxPerLine), frame: i });
    }
    prev = f;
  }
  return [...byLine.entries()]
    .filter(([, e]) => e.notes.length > 0)
    .map(([line, e]) => ({ line, text: e.notes.join(" · "), frame: e.frame }))
    .sort((a, b) => a.line - b.line);
}
