#!/usr/bin/env node
// 图鉴生成器 —— 展示层排版（非判定型；判定型闸是 Go 的 scripts/icon_catalog）。
//
// 读 moonbit/icons/*.svg + moonbit/icons/index.tsv，按 category 分组排卡片，产出
// assets/icons-preview.svg：每卡 = 图标 + 英文 id + 中文短标签，深色底（图鉴是唯一
// 自带底色的文件——图标资产一律透明，由消费方叠底着色）。
//
// 用法：
//     node scripts/gen_icon_preview/main.mts
//     node scripts/gen_icon_preview/main.mts -check    # 只校验现有图鉴是否最新（不落盘）
//
// 幂等：卡片顺序按 category 固定序 + 组内 id 字典序，行尾固定 LF ⇒ 双次运行字节一致；
// -check 完全不落盘（不碰 mtime）。展示层与资产面解耦：改图标后重跑本脚本即可。
//
// 退出码：0 成功（含 -check 一致）/ 1 不一致或写出失败 / 2 环境错（fail loud）。
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const ROOT = path.resolve(import.meta.dirname, "../..");
const ASSETS = path.join(ROOT, "moonbit", "icons");
const TSV = path.join(ASSETS, "index.tsv");
const OUT = path.join(ROOT, "assets", "icons-preview.svg");

const FONT = "-apple-system,'Segoe UI','Microsoft YaHei UI',sans-serif";
const CW = 96;
const CH = 96;
const COLS = 6;
const GAP = 4.8;
const X0 = 40;
const ORDER = ["词法", "语法", "语义", "C++", "运行时"];

// 图鉴专用中文短标签：tsv 的 desc 是完整语义（最长 9 字，96px 卡装不下），
// 这里给一个 4~6 字的短标签。新增 id 时必须补，否则回落成 id 本身（可接受的退化）。
const SHORT = new Map<string, string>([
  ["string", "字符串"], ["comment", "块注释"], ["operator", "操作符"], ["macro", "宏定义"],
  ["unsupported", "暂不支持"], ["complex", "声明复杂"], ["array-size", "数组大小"],
  ["expr-expected", "缺表达式"], ["switch-clause", "分支项"], ["semicolon", "分号"],
  ["bracket", "括号"], ["duplicate", "重复定义"], ["type-mismatch", "类型不符"],
  ["array-init", "数组初始化"], ["index", "索引"], ["jump-outside", "跳转越界"],
  ["return", "返回值"], ["cond-invalid", "条件非法"], ["undeclared", "未声明"],
  ["op-type", "运算类型"], ["deref", "解引用"], ["array-decay", "数组退化"],
  ["incdec", "自增自减"], ["alloc-args", "分配参数"], ["call-args", "实参"],
  ["call-target", "调用目标"], ["printf", "printf"], ["scanf", "scanf"],
  ["struct-member", "成员访问"], ["assign-readonly", "右值赋值"], ["case-const", "case 常量"],
  ["off-by-one", "差一错误"], ["implicit-cast", "隐式转换"], ["pointer-compat", "指针兼容"],
  ["promote", "类型提升"], ["uaf", "内存已释放"], ["double-free", "重复释放"],
  ["leak", "内存泄漏"], ["dangling", "悬垂引用"], ["slice", "对象切片"],
  ["ownership", "所有权"], ["move", "移动后使用"], ["buffer-overflow", "缓冲区溢出"],
  ["cause", "原因"], ["deny", "非法访问"], ["divide-zero", "除零"], ["fix", "解决方法"],
  ["inspect", "查看"], ["location", "位置"], ["note", "示例"], ["step-limit", "步数超限"],
  ["timeline", "时间轴"],
  // 2026-10-10 C 语义全集批（24 枚新增，按 C 语言概念而非诊断码定粒度）
  ["unknown-char", "未知字符"], ["string-multiline", "字符串跨行"],
  ["preproc-cond", "条件编译"], ["include-missing", "头文件缺失"],
  ["include-cycle", "循环包含"], ["token-paste", "记号粘贴"],
  ["depth-limit", "展开超限"], ["shadow", "遮蔽"], ["side-effect", "宏参副作用"],
  ["static-assert", "静态断言"], ["number-literal", "数字字面量"],
  ["char-literal", "字符字面量"], ["type-expected", "缺类型名"],
  ["paren-close", "缺右圆括号"], ["bracket-close", "缺右方括号"],
  ["static-linkage", "静态链接"], ["label-undefined", "标签未定义"],
  ["cond-assign", "条件里赋值"], ["const-qual", "const 限定"],
  ["printf-format", "输出格式串"], ["scanf-format", "输入格式串"],
  ["func-undefined", "未定义函数"], ["null-deref", "空指针"],
  ["uninit-read", "未初始化"],
]);

const DESC_RE = /<\/desc>\n([\s\S]*?)\n<\/svg>/;

export interface IconRow {
  id: string;
  category: string;
}

// fmtG 对齐 Python 的 "%g"（默认 6 位有效数字、去尾零）——图鉴坐标口径。
export function fmtG(n: number): string {
  if (n === 0) return "0";
  const s = n.toPrecision(6);
  const e = s.search(/[eE]/);
  if (e < 0) {
    const t = s.includes(".") ? s.replace(/0+$/, "").replace(/\.$/, "") : s;
    return t;
  }
  const mant = s.slice(0, e);
  const exp = Number(s.slice(e + 1));
  const m = mant.includes(".") ? mant.replace(/0+$/, "").replace(/\.$/, "") : mant;
  const sign = exp >= 0 ? "+" : "-";
  return `${m}e${sign}${String(Math.abs(exp)).padStart(2, "0")}`;
}

export function buildSvg(rows: IconRow[], bodyOf: Map<string, string>): string {
  const groups = ORDER.map((c) => [c, rows.filter((r) => r.category === c).map((r) => r.id)] as [string, string[]])
    .filter(([, ids]) => ids.length > 0);
  const h =
    66 + groups.reduce((acc, [, ids]) => acc + 18 + Math.ceil(ids.length / COLS) * (CH + 12) + 10, 0) + 56;

  const p: string[] = [
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 680 ${h}" width="680" height="${h}" role="img">`,
    "<title>Vitro 语义图标图鉴</title>",
    "<desc>按 category 分组的语义图标，每卡为图标、英文 id 与中文语义</desc>",
    `<rect x="0" y="0" width="680" height="${h}" fill="#17171b"/>`,
    `<text x="40" y="30" font-family="${FONT}" font-size="15" font-weight="500" fill="#f2f2f2">Vitro 语义图标图鉴 · ${rows.length} 个</text>`,
    `<text x="40" y="48" font-family="${FONT}" font-size="11" fill="#8a8a90">viewBox 24 · stroke 1.8 · currentColor · 语义 id 与图形严格双射</text>`,
  ];
  let y = 66;
  for (const [gname, ids] of groups) {
    p.push(`<text x="40" y="${y}" font-family="${FONT}" font-size="12" font-weight="500" fill="#c9c9cf">${gname} · ${ids.length}</text>`);
    p.push(`<line x1="40" y1="${y + 6}" x2="640" y2="${y + 6}" stroke="#3a3a40" stroke-width="1"/>`);
    y += 18;
    ids.forEach((key, i) => {
      const col = i % COLS;
      const row = Math.floor(i / COLS);
      const x = X0 + col * (CW + GAP);
      const cy = y + row * (CH + 12);
      p.push(`<rect x="${fmtG(x)}" y="${cy}" width="${CW}" height="${CH}" rx="10" fill="#2b2b2e"/>`);
      p.push(
        `<g transform="translate(${fmtG(x + CW / 2 - 20.4)},${cy + 10}) scale(1.7)" fill="none" stroke="#e8e8e8" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${bodyOf.get(key) ?? ""}</g>`
      );
      p.push(`<text x="${fmtG(x + CW / 2)}" y="${cy + 74}" text-anchor="middle" font-family="${FONT}" font-size="11" fill="#f2f2f2">${key}</text>`);
      p.push(
        `<text x="${fmtG(x + CW / 2)}" y="${cy + 89}" text-anchor="middle" font-family="${FONT}" font-size="11" fill="#9a9aa0">${SHORT.get(key) ?? key}</text>`
      );
    });
    y += Math.ceil(ids.length / COLS) * (CH + 12) + 10;
  }
  p.push(
    `<text x="40" y="${y + 16}" font-family="${FONT}" font-size="11" fill="#7a7a80">真源 moonbit/icons/&lt;id&gt;.svg · 清单 index.tsv · 几何层 moonbit/icons/icons.json（gen_icons 产，随 mooncakes 包发布）· 图鉴为展示层，不进契约闸</text>`
  );
  p.push(
    `<text x="40" y="${y + 34}" font-family="${FONT}" font-size="11" fill="#6b6b72">设计准则：代码字面量 / 经典 CS 隐喻优先，禁生活化抽象比喻（灯泡≠原因 · 水滴≠内存 · 角尺≠语汇）</text>`
  );
  p.push("</svg>");
  return p.join("\n") + "\n";
}

function fail(code: number, msg: string): never {
  console.error(msg);
  process.exit(code);
}

function main(check: boolean): void {
  if (!fs.existsSync(ASSETS) || !fs.statSync(ASSETS).isDirectory()) {
    fail(2, `FATAL: 读不到资产目录 ${ASSETS}`);
  }
  const lines = fs
    .readFileSync(TSV, "utf8")
    .split(/\r?\n/)
    .filter((ln) => ln.trim() !== "");
  const rows: IconRow[] = [];
  for (const ln of lines.slice(1)) {
    const cols = ln.split("\t");
    if (cols.length !== 5) fail(2, `FATAL: index.tsv 列数=${cols.length}（应 5）：${ln}`);
    rows.push({ id: cols[0] ?? "", category: cols[1] ?? "" });
  }

  const bodyOf = new Map<string, string>();
  for (const r of rows) {
    const p = path.join(ASSETS, r.id + ".svg");
    if (!fs.existsSync(p)) fail(2, `FATAL: index.tsv 有 id 但缺资产：${p}`);
    const m = DESC_RE.exec(fs.readFileSync(p, "utf8"));
    bodyOf.set(r.id, m?.[1]?.replaceAll("\n", "") ?? "");
  }

  const out = buildSvg(rows, bodyOf);

  if (check) {
    if (!fs.existsSync(OUT)) fail(1, `FAIL: 图鉴缺失 ${OUT}（跑 node scripts/gen_icon_preview/main.mts）`);
    const cur = fs.readFileSync(OUT, "utf8");
    if (cur !== out) {
      fail(1, `FAIL: 图鉴与真源不一致（${cur.length} B vs ${out.length} B），重跑生成器`);
    }
    console.log(`OK：图鉴与真源一致（${rows.length} 个图标）`);
    return;
  }

  try {
    fs.writeFileSync(OUT, out);
  } catch (e) {
    fail(1, `FAIL: 写出失败 ${OUT}: ${String(e)}`);
  }
  const groups = ORDER.filter((c) => rows.some((r) => r.category === c)).length;
  console.log(`生成 ${OUT}：${rows.length} 个图标，${out.length} B，${groups} 组`);
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) main(process.argv.slice(2).includes("-check"));
