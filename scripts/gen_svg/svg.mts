// svg.mts —— 插图生成器共享层：SVG 拼装 helper + 品牌 CSS + 落盘/校验（#273
// 存量 Go 重写批；原 scripts/gen_svg/main.go 的同 package helper 段）。
//
// 品牌纪律（照搬 assets/logo/vitro-logo.svg）：只用玻璃蓝 #155E86 /
// #4FB3E8(dark) + 基准灰 #94A3AD / #5A6B75(dark) + 墨 #0D1B24 / #E9F1F7(dark)
// + 白高光；无渐变堆叠、无投影、圆头端点；纯 CSS @media 深浅自适应，无脚本。
import fs from "node:fs";
import path from "node:path";

export interface FactsEntry {
  value: number | null;
  svalue: string;
  as_of: string;
  status: string;
  source: string;
  how_to_get: string;
}
export interface FactsDoc {
  generated_at: string;
  facts: Record<string, FactsEntry>;
}

export function fatal(msg: string): never {
  process.stderr.write("错误: " + msg + "\n");
  process.exit(2);
}

// ─── facts 台账（只读；与 scripts/facts 同一份 reports/facts.json）──────────

export function loadFacts(root: string): FactsDoc {
  const p = path.join(root, "reports", "facts.json");
  let b: string;
  try {
    b = fs.readFileSync(p, "utf8");
  } catch (e) {
    return fatal(`读不到 reports/facts.json（先跑 go run ./scripts/facts facts 采集）: ${(e as Error).message}`);
  }
  try {
    return JSON.parse(b) as FactsDoc;
  } catch (e) {
    return fatal(`reports/facts.json 解析失败: ${(e as Error).message}`);
  }
}

const OK_STATUS = new Set(["ok", "stale", "cached"]);

/** 取数值真值，fail loud：不猜默认值（缺 key / 待采集 / 超龄一律红）。 */
export function mustFact(d: FactsDoc, key: string): number {
  const f = d.facts[key];
  if (f === undefined || f.value === null || !OK_STATUS.has(f.status)) {
    fatal(`facts 键 ${goQuote(key)} 不可用（status=${f?.status ?? "缺失"}）——how_to_get: ${f?.how_to_get ?? ""}`);
  }
  return f.value;
}

/** 取字符串真值（如建包清单 / 引擎版本），fail loud 同 mustFact。 */
export function mustFactS(d: FactsDoc, key: string): string {
  const f = d.facts[key];
  if (f === undefined || f.svalue === "" || !OK_STATUS.has(f.status)) {
    fatal(`facts 键 ${goQuote(key)} 不可用（status=${f?.status ?? "缺失"}）——how_to_get: ${f?.how_to_get ?? ""}`);
  }
  return f.svalue;
}

/** Go `%q`（错误消息里的键名形态）。 */
function goQuote(s: string): string {
  return `"${s.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
}

// ─── SVG 拼装 helper ─────────────────────────────────────────────────────────

/** Go strings.NewReplacer 单次扫描语义：& < > 各自替换，产物不再二次匹配。 */
export function esc(s: string): string {
  return s.replace(/[&<>]/g, (c) => (c === "&" ? "&amp;" : c === "<" ? "&lt;" : "&gt;"));
}

export function box(x: number, y: number, w: number, h: number, cls: string, rx: number): string {
  return `<rect class="${cls}" x="${x}" y="${y}" width="${w}" height="${h}" rx="${rx}"/>`;
}

/**
 * dataFact 非空时把整段文本包进 <tspan data-fact=…>——数字与锚一一对应
 *（facts 的 SVG 通道按锚后最近 tspan 文本取数，一行多锚零歧义）。
 */
export function textF(x: number, y: number, cls: string, s: string, dataFact: string): string {
  let content = esc(s);
  if (dataFact !== "") content = `<tspan data-fact="${dataFact}">${content}</tspan>`;
  return `<text class="${cls}" x="${x}" y="${y}" text-anchor="middle">${content}</text>`;
}

/** 一行内多段（文本片段 | 锚+数字）交替拼接。 */
export interface Seg {
  text: string; // 纯文本段（内部 esc）
  num: string; // 非空 = 数字段，值为 data-fact 键
  val: number; // 数字段的值
}

export function textSegs(x: number, y: number, cls: string, segs: Seg[]): string {
  let b = `<text class="${cls}" x="${x}" y="${y}" text-anchor="middle">`;
  for (const s of segs) {
    if (s.num !== "") b += `<tspan data-fact="${s.num}">${s.val}</tspan>`;
    else b += esc(s.text);
  }
  return b + "</text>";
}

export function line(x1: number, y1: number, x2: number, y2: number, cls: string): string {
  return `<line class="${cls}" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}"/>`;
}

/** 带三角箭头的直线（marker orient=auto 按线方向旋转）。 */
export function arrow(x1: number, y1: number, x2: number, y2: number, cls: string): string {
  return `<line class="${cls}" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" marker-end="url(#ah)"/>`;
}

/** 正交折线箭头（末段出箭头）。pts 形如 "x1,y1 x2,y2 x3,y3"。 */
export function arrowPoly(pts: string, cls: string): string {
  return `<polyline class="${cls}" points="${pts}" marker-end="url(#ah)"/>`;
}

/** 左对齐文本（表格式排版用）。 */
export function textL(x: number, y: number, cls: string, s: string): string {
  return `<text class="${cls}" x="${x}" y="${y}" text-anchor="start">${esc(s)}</text>`;
}

/** 箭头头部（每图一次）。颜色走 class，随深浅模式联动。 */
export const MARKER_DEF = `  <defs>
    <marker id="ah" viewBox="0 0 10 10" refX="8.5" refY="5" markerWidth="6.5" markerHeight="6.5" orient="auto-start-reverse">
      <path d="M0,0 L10,5 L0,10 z" class="ahf"/>
    </marker>
  </defs>`;

export const CSS = `  <style>
    .bg     { fill: #FFFFFF; }
    .core   { fill: #155E86; fill-opacity: .07; stroke: #155E86; stroke-width: 3; }
    .card   { fill: #155E86; fill-opacity: .05; stroke: #155E86; stroke-width: 2.5; }
    .cons   { fill: none; stroke: #94A3AD; stroke-width: 2; }
    .warn   { fill: #155E86; fill-opacity: .04; stroke: #94A3AD; stroke-width: 2; stroke-dasharray: 7 5; }
    .plan   { fill: none; stroke: #94A3AD; stroke-width: 1.8; stroke-dasharray: 5 4; }
    .line   { stroke: #94A3AD; stroke-width: 3; fill: none; }
    .edge   { stroke: #94A3AD; stroke-width: 2.5; fill: none; }
    .ahf    { fill: #94A3AD; stroke: none; }
    .tn     { font-family: "Consolas","Cascadia Mono",monospace; font-size: 17px; fill: #155E86; stroke: none; }
    .zone   { fill: #155E86; fill-opacity: .028; stroke: #155E86; stroke-width: 1.6; }
    .tt     { font-family: "Segoe UI","Microsoft YaHei",sans-serif; font-size: 34px; font-weight: 600; fill: #0D1B24; stroke: none; }
    .t      { font-family: "Segoe UI","Microsoft YaHei",sans-serif; font-size: 23px; fill: #0D1B24; stroke: none; }
    .ts     { font-family: "Consolas","Cascadia Mono",monospace; font-size: 21px; fill: #155E86; stroke: none; }
    .tm     { font-family: "Segoe UI","Microsoft YaHei",sans-serif; font-size: 20px; fill: #5A6B75; stroke: none; }
    .tc     { font-family: "Segoe UI","Microsoft YaHei",sans-serif; font-size: 18px; fill: #5A6B75; stroke: none; }
    @media (prefers-color-scheme: dark) {
      .bg   { fill: #0D1B24; }
      .core { stroke: #4FB3E8; fill: #4FB3E8; fill-opacity: .1; }
      .card { stroke: #4FB3E8; fill: #4FB3E8; fill-opacity: .07; }
      .zone { stroke: #4FB3E8; fill: #4FB3E8; fill-opacity: .05; }
      .cons, .warn, .plan { stroke: #5A6B75; }
      .line, .edge { stroke: #5A6B75; }
      .ahf  { fill: #5A6B75; }
      .tt, .t { fill: #E9F1F7; }
      .ts, .tn { fill: #4FB3E8; }
      .tm, .tc { fill: #94A3AD; }
    }
  </style>`;

export function svgOpen(w: number, h: number, label: string, title: string, note: string): string[] {
  return [
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w} ${h}" role="img" aria-label="${esc(label)}">`,
    "  <title>" + esc(title) + "</title>",
    "  <!-- 由 scripts/gen_svg 生成（勿手改）：" + note + " -->",
    CSS,
    `  <rect class="bg" width="${w}" height="${h}"/>`,
  ];
}

// ─── 落盘 / 校验 ─────────────────────────────────────────────────────────────

/** check 模式：writeSVG 不落盘，改为与现有文件逐字节比对，漂移收进 checkDrifts。 */
let checkMode = false;
const checkDrifts: string[] = [];

export function setCheckMode(on: boolean): void {
  checkMode = on;
}

export function drifts(): readonly string[] {
  return checkDrifts;
}

export function writeSVG(root: string, rel: string, parts: string[]): void {
  const body = parts.join("\n") + "\n</svg>\n";
  const p = path.join(root, rel);
  if (checkMode) {
    let existing: string;
    try {
      existing = fs.readFileSync(p, "utf8");
    } catch {
      checkDrifts.push(rel + "（落盘缺失）");
      return;
    }
    if (existing !== body) checkDrifts.push(rel);
    return;
  }
  try {
    fs.mkdirSync(path.dirname(p), { recursive: true });
  } catch (e) {
    fatal((e as Error).message);
  }
  try {
    fs.writeFileSync(p, body, { mode: 0o644 });
  } catch (e) {
    fatal("写 " + rel + " 失败: " + (e as Error).message);
  }
  process.stdout.write(`written: ${rel} (${Buffer.byteLength(body, "utf8")} bytes)\n`);
}
