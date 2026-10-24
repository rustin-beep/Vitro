#!/usr/bin/env node
// demo_ui_lint —— demo/ 静态三件套的字符串契约对账闸（Go→.mts 重写，refs #273）。
//
// 原 Go 版：main.go 924 行 + raw.go 273 行（本批 raw 侧落 raw.mts）。
//
// 动机（2026-10-02 demo UI 批实测三 bug 的归因）：三个实锤 bug 全部是
// **JS↔CSS 的字符串契约**或 CSS 本体问题——TS 类型系统一个都拦不住，对症
// 防线是文本对账闸：
//
//	A. CSS 变量：var(--x) 引用 ⊆ 定义（css 定义 ∪ JS/HTML setProperty）∪ 白名单
//	   ——实锤先例：--fg-muted 引用不存在的变量，静默回退 inherit。
//	B. 类名：classList 写操作字面量对「元素候选类闭包 ∪ CSS 复合单元 ∪ JS
//	   生成面 ∪ 白名单」对账。CSS 单元 = 复合选择器里同属一个元素的段
//	   （.tab.active 的 {tab,active}）——单元必须整体落在元素候选类集内才
//	   为该元素提供定义，专抓「操作了永不生效的类」形态（实锤先例：
//	   $("stdin-row").classList.add("active") 只有 .tab.active 定义，
//	   #stdin-row 永远没有 tab 类，行永不显示）。
//	C. getElementById 字面量 id ⊆ html id 集 ∪ 动态前缀白名单（防静默 null）。
//	D. mono 连字对账（2026-10-16 #122 闸门批）：凡 var(--mono) / var(--vr-mono)
//	   字体面消费规则，须**规则体内自带 font-variant-ligatures 关闭**（新栈
//	   组件同行声明形态）**或选择器 ∈ style.css 末尾枚举块**（旧栈形态）。
//	   `font:` 简写重置连字 + 同特异性层叠后者赢两条实测约束使「新面忘了关」
//	   静默发生——CallTree.svelte SVG 树节点 text 的实锤即此形态：教学文本
//	   `<=` 渲染成 `≤`（#121① 教学硬伤同族）。
//
// 扫描面（2026-10-16 扩）：旧栈三件套（index.html + app.ts + js/*.ts + *.css）
// ∪ 新栈 F4 面（src/**/*.svelte 模板段并入 html 面、<style> 块并入 css 面、
// src/**/*.ts 并入 js 面——排除 src/data/ 生成物）。
//
// 规则外置 rules.json：动态 className 拼接簇、动态 id 前缀、显式白名单；
// **僵尸条目（登记的类/id 已无任何引用或定义）无条件红**。
//
// 判定型脚本纪律：stdlib 优先、fail loud（exit 1 列出全部未命中）、
// -selftest 内存注入证红（class/var/id/zombie/mono 各≥1，不落盘）。
// 抽取面下限（D8 族防线）：真跑时各路有效检查位点数低于下限即红。
//
// 迁移口径（#292 批，逐字对拍为前提）：
//   - stdout/stderr/退出码与 Go 版逐字一致（parity 闸三模式对拍：默认 / -selftest /
//     红 fixture）；stdout 里 `go run ./scripts/demo_ui_lint -update-raw` 处方
//     **按 Go 原文保留**——改文案即破对拍，终局批（Go 版退役）统一改写；
//   - Go 版两处死代码未移植：`compoundUnit.raw` 字段（只写不读）、
//     `reCSSVarUseNoFB` 正则（声明即死）；
//   - Go `flag` 口径：字符串 flag 支持 `-x v` / `-x=v`（`--x` 同形）；布尔 flag
//     只认裸形态，带 `=value` **显式 exit 2**（Go 会解析 `=false` 继续跑；本仓
//     #289 审阅 P3-1 已定「拒绝执行而非猜语义」）；首个非 flag 参数后停止解析；
//   - 排序口径：结果按 kind 排序，kind 相同者保持插入序（Go `sort.SliceStable`
//     口径；Go 侧同批由 `sort.Slice` 改为 SliceStable——原实现 n>12 时 tie 序
//     落进 pdqsort 划分路径，红路径无法逐字对拍）；
//   - **错误路径文案**（文件不可读 / 坏 JSON / 未知参数）按 .mts 习惯重写，不逐字
//     复刻：Go 侧掺 platform 相关的 `open …: The system cannot find the file
//     specified.` 与 flag 包 usage 段，逐字复刻没有判定价值（parity 对拍的是
//     §判定面：默认 / -selftest / 红 fixture 三模式）。
//
// 用法：node scripts/demo_ui_lint/main.mts [-demo demo] [-rules scripts/demo_ui_lint/rules.json]
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { byteCompare, byteSort, goFields, goTrimSpace } from "../internal/text.mts";
import { walkDirSorted } from "../internal/capi.mts";
import { checkRaw, collectRawLiterals, countRawKind, loadRawBaseline, selftestRaw, writeRawBaseline } from "./raw.mts";
import type { RawEntry } from "./raw.mts";

// ── 规则外置（Go 零值口径：缺键 = 0 / 空表，非静默 default）──────

export interface DynClassRule {
  /** 登记说明（哪处动态拼接） */
  where: string;
  /** 该拼接可能产生的全部类名 */
  classes: string[];
}

export interface DynIDRule {
  /** $("tab-" + ...) 的字面量前缀 */
  prefix: string;
  /** 可能拼出的全部 id */
  ids: string[];
}

export interface Rules {
  /** classList 字面量位点下限（防抽取面被变量化掏空；0=缺省 3） */
  min_class_sites: number;
  dynamic_class_assigns: DynClassRule[];
  dynamic_id_prefixes: DynIDRule[];
  class_whitelist: string[];
  var_whitelist: string[];
}

export interface Issue {
  kind: string;
  msg: string;
}

export interface Stats {
  sitesClass: number;
  sitesUnresolved: number;
  sitesID: number;
  sitesVar: number;
  sitesMono: number;
}

export interface Sources {
  html: string;
  js: string;
  css: string;
  /** 新栈 F4 面（svelte + ts 原文合并） */
  newStackSrc: string;
}

export interface CompoundUnit {
  id: string;
  classes: Set<string>;
}

// ── 提取器 ───────────────────────────────────────────────────

const RE_CSS_COMMENT = /\/\*[\s\S]*?\*\//g;
const RE_CSS_RULE = /([^{}]+)\{/g;
const RE_CSS_FULL_RULE = /([^{}]+)\{([^{}]*)\}/g;
const RE_CSS_COMPOUND = /[#.][A-Za-z_][\w-]*/g;
const RE_CSS_VAR_DEF = /(--[\w-]+)\s*:/g;
const RE_CSS_VAR_USE = /var\((--[\w-]+)/g;
const RE_MEDIA_HEAD = /@media[^{]*\{/g;

const RE_HTML_TAG = /<([a-z]+)[^>]*>/g;
const RE_ATTR_ID = /\bid="([\w-]+)"/;
const RE_ATTR_CLASS = /\bclass="([^"]*)"/;

/** Svelte 组件 <style> 块拆分：style 块并入 css 面、模板段并入 html 面。
 *  非贪婪到第一个 </style>——组件单 style 块形态（walk 顺序合并多块亦安全）。 */
const RE_SVELTE_STYLE_BLOCK = /<style[^>]*>[\s\S]*?<\/style>/g;

/** 泛型实参分支 \$<[^>()]*>\(（2026-10-04 审阅 P2-1）：TS 源面 $<T>("id")
 *  形态裸 \( 侧正则全漏——注入泛型 ghost id 闸绿实锤（位点 26→21 静默塌缩）；
 *  禁 () 因函数定义签名会被误入捕获域，[^>()]* 使其不命中引号捕获组。 */
const RE_JS_CLASSLIST_CHAIN =
  /(?:\$<[^>()]*>\(|\$\(|getElementById\(|querySelector\()["']#?([\w-]+)["']\)\.classList\.(add|remove|toggle|contains)\(([^)]*)\)/g;
const RE_JS_VAR_BIND = /(?:const|let|var)\s+(\w+)\s*=\s*(?:\$<[^>()]*>\(|\$\(|getElementById\(|querySelector\()["']#?([\w-]+)["']\)/g;
const RE_JS_CLASSLIST_VAR = /(\w+)\.classList\.(add|remove|toggle|contains)\(([^)]*)\)/g;
const RE_JS_GET_BY_ID = /(?:\$<[^>()]*>\(|\$\(|getElementById\()["']([\w-]+)["']\)/g;
const RE_JS_GET_BY_ID_DYN = /(?:\$<[^>()]*>\(|\$\(|getElementById\()["']([\w-]+)["']\s*\+/g;
const RE_JS_GEN_CLASS = /class=\\?"([^"\\$]+)\\?"/g;
const RE_QUOTED_ARGS = /"([^"]+)"/g;
const RE_JS_INLINE_STYLE_VAR = /style=\\?"[^"\\$]*?(--[\w-]+)/g;
const RE_SET_PROPERTY = /setProperty\(\s*"([\w-]+)"/g;
/** 带回退值的引用：var(--x, fallback) */
const RE_VAR_WITH_FALLBACK = /var\(([\w-]+)\s*,/g;
/** font-variant-ligatures 的**值**判据（2026-10-17 审阅 P3-⑦）：关闭态 = 值恰为
 *  none / no-common-ligatures（trim 后整值比对；复合值红，逼规范形态）。原检查
 *  只认声明在场：`normal`（=连字开启的缺省值）同样豁免 ⇒ 假绿。 */
const RE_LIG_VALUE = /font-variant-ligatures:\s*([^;}]+)/;

// ── 小工具 ───────────────────────────────────────────────────

/** Go `%q`（普通文本/ASCII）的等价形态。 */
const quote = (s: string): string => JSON.stringify(s);

/** 选择器比对形态归一：去首尾空白 + 内部空白折叠（同一规则块内手写空格差异不产生假红）。 */
export function normSel(s: string): string {
  return goFields(goTrimSpace(s)).join(" ");
}

/** 计数型提取（Go `FindAllStringSubmatch(x, -1)` 只要条数的位点面）。 */
function countMatches(re: RegExp, s: string): number {
  return [...s.matchAll(re)].length;
}

/** classList 实参提取：只认带引号的字面量串。add("a","b") 多类名照常展开；
 *  非字面量实参返回空（由调用方降级处理）。toggle(class, force) 的 force 是
 *  布尔表达式非类名——2026-10-10 审阅 P1-2 实锤：force 里的比较字面量
 *  （v !== "off"）被整串抽取误当类名报红，故 toggle 只解析首个顶层实参。 */
export function classListArgs(kind: string, s: string): string[] {
  const text = kind === "toggle" ? firstTopArg(s) : s;
  const out: string[] = [];
  for (const m of text.matchAll(RE_QUOTED_ARGS)) out.push(m[1] ?? "");
  return out;
}

/** 截取实参串的首个顶层实参：跳过字符串字面量与括号/方括号内的逗号。 */
export function firstTopArg(s: string): string {
  let depth = 0;
  let inStr = false;
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (inStr) {
      if (c === '"') inStr = false;
      continue;
    }
    switch (c) {
      case '"':
        inStr = true;
        break;
      case "(":
      case "[":
        depth++;
        break;
      case ")":
      case "]":
        depth--;
        break;
      case ",":
        if (depth === 0) return s.slice(0, i);
        break;
      default:
        break;
    }
  }
  return s;
}

/** font-variant-ligatures 是否**值为**关闭态（值判据，非声明在场判据）。 */
export function ligClosed(body: string): boolean {
  const m = RE_LIG_VALUE.exec(body);
  if (m === null) return false;
  const v = goTrimSpace(m[1] ?? "");
  return v === "none" || v === "no-common-ligatures";
}

// ── CSS 解析 ─────────────────────────────────────────────────

/** 返回：复合单元全集、变量定义集。@media 头剥离后规则提取不受嵌套影响。 */
export function parseCSS(text: string): { units: CompoundUnit[]; vars: Set<string> } {
  const bare = text.replace(RE_CSS_COMMENT, "").replace(RE_MEDIA_HEAD, "");
  const units: CompoundUnit[] = [];
  for (const m of bare.matchAll(RE_CSS_RULE)) {
    const sel = goTrimSpace(m[1] ?? "");
    if (sel === "" || sel.startsWith("@")) continue;
    for (const one of sel.split(",")) {
      const u: CompoundUnit = { id: "", classes: new Set<string>() };
      for (const tok of one.matchAll(RE_CSS_COMPOUND)) {
        const t = tok[0];
        if (t.startsWith("#")) u.id = t.slice(1);
        else u.classes.add(t.slice(1));
      }
      if (u.classes.size > 0 || u.id !== "") units.push(u);
    }
  }
  const vars = new Set<string>();
  for (const m of bare.matchAll(RE_CSS_VAR_DEF)) vars.add(m[1] ?? "");
  return { units, vars };
}

// ── 判定核心（纯函数：不读盘、不打屏） ───────────────────────

export interface Bindings {
  /** const el = $("id") 的唯一锚定 */
  varBind: Map<string, string>;
  /** 同名变量绑到多个 id（不可靠锚定，走降级全局检查） */
  varAmbiguous: Set<string>;
}

export function analyze(src: Sources, rl: Rules): { issues: Issue[]; stats: Stats; bindings: Bindings } {
  const issues: Issue[] = [];
  const js = src.js;
  let html = src.html;
  let css = src.css;

  // 新栈面并入：<style> 块 → css 面；模板段 → html 面
  for (const m of src.newStackSrc.matchAll(RE_SVELTE_STYLE_BLOCK)) css += "\n" + (m[0] ?? "");
  html += "\n" + src.newStackSrc.replace(RE_SVELTE_STYLE_BLOCK, "\n");

  // ── 定义面收集 ──
  const htmlIDs = new Set<string>();
  const htmlClassByID = new Map<string, Set<string>>(); // id → 静态类
  const htmlClassAll = new Set<string>();
  for (const tag of html.matchAll(RE_HTML_TAG)) {
    const t = tag[0];
    const idm = RE_ATTR_ID.exec(t);
    const clm = RE_ATTR_CLASS.exec(t);
    const cls = new Set<string>();
    if (clm !== null) {
      for (const c of goFields(clm[1] ?? "")) {
        cls.add(c);
        htmlClassAll.add(c);
      }
    }
    if (idm !== null) {
      htmlIDs.add(idm[1] ?? "");
      htmlClassByID.set(idm[1] ?? "", cls);
    }
  }

  const parsed = parseCSS(css);
  const cssUnits = parsed.units;
  const cssVarDefs = parsed.vars;

  // html 元素的静态类集也构成复合单元（<button class="tab active"> 的 {tab,active}
  // 与 css .tab.active 等价）——html 豁免不走全局集，走同一套单元判定，否则
  // active 类在 html 出现一次就全元素放行（stdin-row 实锤漏报形态）。
  for (const tag of html.matchAll(RE_HTML_TAG)) {
    const t = tag[0];
    const clm = RE_ATTR_CLASS.exec(t);
    if (clm === null) continue;
    const idm = RE_ATTR_ID.exec(t);
    const u: CompoundUnit = { id: idm === null ? "" : (idm[1] ?? ""), classes: new Set<string>() };
    for (const c of goFields(clm[1] ?? "")) u.classes.add(c);
    cssUnits.push(u);
  }

  // JS 生成面：innerHTML/模板里的 class="..." + className 字面量 + classList 字面量
  const jsGenClasses = new Set<string>();
  for (const m of js.matchAll(RE_JS_GEN_CLASS)) {
    for (const c of goFields(m[1] ?? "")) jsGenClasses.add(c);
  }

  // 变量绑定：const el = $("id")。同名变量绑定到多个不同 id 时视为歧义
  // （JS 无块级作用域分析，forEach 参数遮蔽等形态不可靠）——不锚定，走降级全局检查。
  const varBind = new Map<string, string>();
  const varAmbiguous = new Set<string>();
  {
    const binds = new Map<string, Set<string>>();
    for (const m of js.matchAll(RE_JS_VAR_BIND)) {
      const name = m[1] ?? "";
      const id = m[2] ?? "";
      const cur = binds.get(name);
      if (cur === undefined) binds.set(name, new Set([id]));
      else cur.add(id);
    }
    for (const [name, ids] of binds) {
      if (ids.size === 1) varBind.set(name, [...ids][0] ?? "");
      else varAmbiguous.add(name);
    }
  }

  // 元素候选类闭包：静态类 ∪ 该元素全部 classList add/remove/toggle 字面量
  // ∪ 动态簇（className 整体赋值不并入候选——覆盖语义，生成面已由 RE_JS_GEN_CLASS 收集）
  const candidate = (id: string): Set<string> => {
    const set = new Set<string>();
    for (const c of htmlClassByID.get(id) ?? []) set.add(c);
    for (const m of js.matchAll(RE_JS_CLASSLIST_CHAIN)) {
      if ((m[1] ?? "") === id && m[2] !== "contains") {
        for (const c of classListArgs(m[2] ?? "", m[3] ?? "")) set.add(c);
      }
    }
    for (const m of js.matchAll(RE_JS_CLASSLIST_VAR)) {
      if (varBind.get(m[1] ?? "") === id && m[2] !== "contains") {
        for (const c of classListArgs(m[2] ?? "", m[3] ?? "")) set.add(c);
      }
    }
    // 动态簇并入**每个**元素的候选闭包（登记即全局放行）——已知降级：
    // 动态拼接无法静态定位元素，登记面承担「这些类合法」的证明义务
    for (const r of rl.dynamic_class_assigns) for (const c of r.classes) set.add(c);
    return set;
  };

  // ── 检查 B：classList 写操作类名对账 ──
  let sitesClass = 0;
  let sitesUnresolved = 0;
  const checkClassWrite = (anchorID: string, kind: string, args: string, at: string): void => {
    if (kind === "contains") return; // 读操作保守不查（恒 false 也算 bug，但避免误报面扩大）
    const cs = classListArgs(kind, args);
    if (cs.length === 0) {
      sitesUnresolved++;
      return;
    }
    sitesClass++;
    for (const c of cs) {
      if (!validClass(c, anchorID, candidate, cssUnits, jsGenClasses, rl)) {
        issues.push({
          kind: "class",
          msg: `${at}: ${kind} 类名 ${quote(c)} 对元素 #${anchorID} 永不生效（无匹配 CSS 单元/生成面/白名单）`,
        });
      }
    }
  };

  for (const m of js.matchAll(RE_JS_CLASSLIST_CHAIN)) {
    checkClassWrite(m[1] ?? "", m[2] ?? "", m[3] ?? "", "app.js classList");
  }
  for (const m of js.matchAll(RE_JS_CLASSLIST_VAR)) {
    const name = m[1] ?? "";
    const kind = m[2] ?? "";
    const args = m[3] ?? "";
    const bound = varBind.get(name);
    if (bound !== undefined && !varAmbiguous.has(name)) checkClassWrite(bound, kind, args, "app.js classList");
    // 未锚定/歧义绑定的调用（querySelector 结果、forEach 参数遮蔽等）降级：
    // 类名须全局有定义
    if (bound === undefined || varAmbiguous.has(name)) {
      if (kind !== "contains") {
        for (const c of classListArgs(kind, args)) {
          if (!classKnownAnywhere(c, cssUnits, jsGenClasses, htmlClassAll, rl)) {
            issues.push({ kind: "class", msg: `app.js classList: 类名 ${quote(c)} 全库无定义（未锚定元素，降级全局检查）` });
          }
        }
      }
    }
  }

  // ── 检查 A：CSS 变量对账（varRefs 同时收集自然引用面——var_whitelist 僵尸判定用）──
  // 定义面 = css --x: 定义 ∪ JS/HTML setProperty ∪ JS innerHTML 内联 style="--x:…" ∪ 白名单。
  // 带回退值的 var(--x, fb) 引用按 CSS 语义跳过（未定义时回退兜底，不是契约破坏）。
  const varDefs = new Set<string>(cssVarDefs);
  for (const m of js.matchAll(RE_SET_PROPERTY)) varDefs.add(m[1] ?? "");
  for (const m of html.matchAll(RE_SET_PROPERTY)) varDefs.add(m[1] ?? "");
  for (const m of js.matchAll(RE_JS_INLINE_STYLE_VAR)) varDefs.add(m[1] ?? "");
  const varNatural = new Set<string>(varDefs); // 定义面快照（白名单并入前——僵尸判定用）
  for (const w of rl.var_whitelist) varDefs.add(w);

  const varRefs = new Set<string>();
  const varWithFallback = new Set<string>();
  for (const m of css.matchAll(RE_VAR_WITH_FALLBACK)) varWithFallback.add(m[1] ?? "");
  let sitesVar = 0;
  const checkVars = (text: string, file: string): void => {
    for (const m of text.matchAll(RE_CSS_VAR_USE)) {
      const v = m[1] ?? "";
      varRefs.add(v);
      if (varWithFallback.has(v)) continue; // 带回退值，未定义也不破坏渲染
      if (!varDefs.has(v)) issues.push({ kind: "var", msg: `${file}: var(${v}) 引用未定义变量` });
    }
  };
  sitesVar += countMatches(RE_CSS_VAR_USE, css);
  sitesVar += countMatches(RE_CSS_VAR_USE, js);
  sitesVar += countMatches(RE_CSS_VAR_USE, html);
  checkVars(css, "style.css");
  checkVars(js, "app.js");
  checkVars(html, "index.html");

  // ── 检查 C：getElementById 字面量 id 对账 ──
  const dynIDs = new Set<string>();
  for (const r of rl.dynamic_id_prefixes) for (const id of r.ids) dynIDs.add(id);
  let sitesID = 0;
  for (const m of js.matchAll(RE_JS_GET_BY_ID)) {
    const id = m[1] ?? "";
    sitesID++;
    if (!htmlIDs.has(id) && !dynIDs.has(id)) {
      issues.push({ kind: "id", msg: `app.js: $(${quote(id)}) 在 index.html 无此 id` });
    }
  }
  for (const m of js.matchAll(RE_JS_GET_BY_ID_DYN)) {
    const prefix = m[1] ?? "";
    const covered = rl.dynamic_id_prefixes.some((r) => r.prefix === prefix);
    if (!covered) {
      issues.push({ kind: "id", msg: `app.js: 动态 id 前缀 ${quote(prefix)}+ 未在 rules.json 登记` });
    }
  }

  // ── 检查 D：mono 连字对账（#121① 债机判）──
  // 凡 var(--mono)/var(--vr-mono) 字体面消费规则：规则体内自带 font-variant-ligatures
  // 或选择器 ∈ 连字豁免集。⚠️ 规则提取前必须剥 CSS 注释——块前注释混进选择器串
  // 使豁免比对恒假红（首跑 6 红中 4 红即此抽取缺陷）。
  const cssBare = css.replace(RE_CSS_COMMENT, "");
  const monoExempt = new Set<string>();
  for (const m of cssBare.matchAll(RE_CSS_FULL_RULE)) {
    if (ligClosed(m[2] ?? "")) {
      for (const one of (m[1] ?? "").split(",")) {
        const sel = normSel(one);
        if (sel !== "") monoExempt.add(sel);
      }
    }
  }
  let sitesMono = 0;
  for (const m of cssBare.matchAll(RE_CSS_FULL_RULE)) {
    const sels = m[1] ?? "";
    const body = m[2] ?? "";
    if (!body.includes("var(--mono)") && !body.includes("var(--vr-mono)")) continue;
    if (body.includes("font-variant-ligatures")) {
      sitesMono++;
      if (!ligClosed(body)) {
        // 2026-10-17 审阅 P3-⑦：原检查只认声明在场——normal（=连字开启的缺省值）
        // 同样豁免 ⇒ 假绿；值判据收严后分叉报错。
        for (const one of sels.split(",")) {
          const sel = normSel(one);
          if (sel !== "") {
            issues.push({
              kind: "mono",
              msg: `mono 连字对账: ${sel} 的 font-variant-ligatures 值非关闭态（须 none / no-common-ligatures——normal 与缺省=连字开启，#121①）`,
            });
          }
        }
      }
      continue;
    }
    for (const one of sels.split(",")) {
      const sel = normSel(one);
      if (sel === "" || sel.startsWith("@")) continue;
      sitesMono++;
      if (!monoExempt.has(sel)) {
        issues.push({
          kind: "mono",
          msg: `mono 连字对账: ${sel} 消费 var(--mono)/var(--vr-mono) 但规则体无 font-variant-ligatures 关闭、也未连坐 style.css 末尾枚举块——连字复活（#121① 教学硬伤同族；新面在组件内同行声明，旧面连坐枚举块）`,
        });
      }
    }
  }

  // ── 僵尸条目：白名单/动态簇登记的类与 id 必须仍有真实引用或定义 ──
  const allClassNames = new Set<string>(htmlClassAll);
  for (const u of cssUnits) for (const c of u.classes) allClassNames.add(c);
  for (const c of jsGenClasses) allClassNames.add(c);
  for (const m of js.matchAll(RE_JS_CLASSLIST_CHAIN)) {
    for (const c of classListArgs(m[2] ?? "", m[3] ?? "")) allClassNames.add(c);
  }
  for (const r of rl.dynamic_class_assigns) {
    for (const c of r.classes) {
      if (!allClassNames.has(c)) {
        issues.push({
          kind: "zombie",
          msg: `rules.json: dynamic_class_assigns(${r.where}) 登记的类 ${quote(c)} 全库无引用无定义（僵尸条目）`,
        });
      }
    }
  }
  for (const w of rl.class_whitelist) {
    if (!allClassNames.has(w)) {
      issues.push({ kind: "zombie", msg: `rules.json: class_whitelist 登记的 ${quote(w)} 全库无引用无定义（僵尸条目）` });
    }
  }
  for (const r of rl.dynamic_id_prefixes) {
    for (const id of r.ids) {
      if (!htmlIDs.has(id)) {
        issues.push({
          kind: "zombie",
          msg: `rules.json: dynamic_id_prefixes(${r.prefix}) 登记的 id ${quote(id)} 在 index.html 不存在（僵尸条目）`,
        });
      }
    }
  }
  // var_whitelist 僵尸（2026-10-02 审阅 P3-1 补齐——契约早写"僵尸无条件红"，
  // 此前实现对不上）：登记的变量须在自然定义面或引用面仍出现
  for (const w of rl.var_whitelist) {
    if (!varNatural.has(w) && !varRefs.has(w)) {
      issues.push({ kind: "zombie", msg: `rules.json: var_whitelist 登记的 ${quote(w)} 全库无定义无引用（僵尸条目）` });
    }
  }

  return {
    issues,
    stats: { sitesClass, sitesUnresolved, sitesID, sitesVar, sitesMono },
    bindings: { varBind, varAmbiguous },
  };
}

function validClass(
  c: string,
  anchorID: string,
  candidate: (id: string) => Set<string>,
  units: readonly CompoundUnit[],
  gen: Set<string>,
  rl: Rules,
): boolean {
  if (gen.has(c)) return true; // JS 模板自产自销
  if (rl.class_whitelist.includes(c)) return true;
  const cand = candidate(anchorID);
  for (const u of units) {
    if (!u.classes.has(c)) continue;
    // 单类单元（.muted 这类全局工具类）对任何元素合法；
    // 多类复合单元必须整体落在元素候选闭包内（.tab.active 对无 tab 类的元素不生效）
    if (u.classes.size === 1 && u.id === "") return true;
    if (unitValidFor(u, cand, anchorID)) return true;
  }
  return false;
}

/** 单元对锚点元素有效：单元 #id 匹配（或无 id）且全部类 ⊆ 元素候选类闭包 */
function unitValidFor(u: CompoundUnit, cand: Set<string>, id: string): boolean {
  if (u.id !== "" && u.id !== id) return false;
  for (const c of u.classes) if (!cand.has(c)) return false;
  return true;
}

function classKnownAnywhere(
  c: string,
  units: readonly CompoundUnit[],
  gen: Set<string>,
  htmlAll: Set<string>,
  rl: Rules,
): boolean {
  if (gen.has(c) || htmlAll.has(c)) return true;
  if (rl.class_whitelist.includes(c)) return true;
  return units.some((u) => u.classes.has(c));
}

/** 锚定变量的 classList 写操作位点数（下限检查用——与主对账同口径，
 *  歧义绑定不计入：那类位点本就走降级全局检查）。 */
function countVarSites(js: string, varBind: Map<string, string>, varAmbiguous: Set<string>): number {
  let n = 0;
  for (const m of js.matchAll(RE_JS_CLASSLIST_VAR)) {
    const name = m[1] ?? "";
    if (varBind.has(name) && !varAmbiguous.has(name) && m[2] !== "contains") n++;
  }
  return n;
}

/**
 * 抽取面下限（2026-10-02 审阅 P2-2）：各路有效位点塌缩即红——同一 bug 字面量红、
 * 变量绿的静默失能形态由下限兜住。class 下限可经 rules.json min_class_sites 配置
 * （0/缺省 = 3——显式缺省非静默 default）；id/var 下限维持硬编码（无配置诉求，
 * 不加孤儿旋钮）。F4 收尾（2026-10-17）后 class/id 字面量面归零，下限随重构归 0；
 * var 面仍由 60 兜住（令牌引用未变）；mono 面 2026-10-18 扩面（--vr-mono）后由 40 兜住。
 */
export function coverageIssues(stats: Stats, rl: Rules): Issue[] {
  const minClassSites = rl.min_class_sites;
  const minIDSites = 0;
  const minVarSites = 60;
  const minMonoSites = 40;
  if (
    stats.sitesClass < minClassSites ||
    stats.sitesID < minIDSites ||
    stats.sitesVar < minVarSites ||
    stats.sitesMono < minMonoSites
  ) {
    return [
      {
        kind: "coverage",
        msg:
          `抽取面塌缩：有效位点 class=${stats.sitesClass}（下限 ${minClassSites}）/ id=${stats.sitesID}（下限 ${minIDSites}）` +
          `/ var=${stats.sitesVar}（下限 ${minVarSites}）/ mono=${stats.sitesMono}（下限 ${minMonoSites}）——抽取器失能或 demo 大重构（重构则更新常量）`,
      },
    ];
  }
  return [];
}

/**
 * logo 双份一致性（审阅 2026-10-03 P3-5）：demo/assets/logo 是根 assets/logo 的拷贝，
 * pages.yml 用根份、本地预览用 demo 份——分叉即线上门面与本地不一致且零告警。
 */
export function logoIssues(demoDir: string): Issue[] {
  const out: Issue[] = [];
  const rootLogo = path.join(path.dirname(path.resolve(demoDir)), "assets", "logo");
  const demoLogo = path.join(demoDir, "assets", "logo");
  for (const name of ["vitro-icon.svg", "vitro-icon-light.svg", "vitro-icon-dark.svg"]) {
    const read = (p: string): Buffer | null => {
      try {
        return fs.readFileSync(p);
      } catch {
        return null;
      }
    };
    const rb = read(path.join(rootLogo, name));
    const db = read(path.join(demoLogo, name));
    if (rb === null || db === null) {
      out.push({ kind: "logo", msg: `logo 双份缺失：${name}（根份在=${rb !== null} / demo 份在=${db !== null}）` });
      continue;
    }
    if (!rb.equals(db)) {
      out.push({
        kind: "logo",
        msg: `logo 双份分叉：${name} 根份与 demo/assets 份内容不一致——同步后复跑（义务见 demo/assets/logo/README.md）`,
      });
    }
  }
  return out;
}

// ── -selftest 注入源（各路埋雷）────────────────────────────

function selftestRules(): Rules {
  return {
    min_class_sites: 0,
    dynamic_class_assigns: [{ where: "st", classes: ["ghost-class"] }],
    dynamic_id_prefixes: [{ prefix: "tab-", ids: ["tab-result"] }],
    class_whitelist: [],
    var_whitelist: ["--ghost-var"],
  };
}

const SELFTEST_HTML = `<div id="box" class="tab"></div><div id="tab-result"></div>`;
const SELFTEST_CSS = `:root { --real: 1px; } .tab.on { color: red; }`;
const SELFTEST_JS = `$("box").classList.add("phantom-class");
$("box").classList.toggle("phantom-toggle", seg.dataset.v === "off");
document.getElementById("no-such-id").onclick = null;
const g = $<HTMLTextAreaElement>("no-such-id-generic");
const v = "var(--no-such-var)";`;

/** mono 路（检查 D）注入雷——.mono-face 消费 var(--mono) 无连字关闭亦无枚举连坐必红；
 *  .mono-ok 同行声明为绿对照。.mono-normal 声明在场但值 = normal（连字开启缺省）
 *  ——值判据收严后必红（原只认声明在场的形态下它是假绿）。 */
const SELFTEST_SVELTE = `<div class="mono-face">x</div>
<style>
.mono-face { font: 12px var(--mono); }
.mono-ok { font: 12px var(--mono); font-variant-ligatures: none; }
.mono-normal { font: 12px var(--mono); font-variant-ligatures: normal; }
.mono-vr-face { font: 12px var(--vr-mono); }
.mono-vr-ok { font: 12px var(--vr-mono); font-variant-ligatures: none; }
</style>`;

// ── CLI ──────────────────────────────────────────────────────

interface Opts {
  demoDir: string;
  rulesPath: string;
  selftest: boolean;
  rawBaseline: string;
  updateRaw: boolean;
}

const USAGE =
  "用法：node scripts/demo_ui_lint/main.mts [-demo demo] [-rules scripts/demo_ui_lint/rules.json] " +
  "[-selftest] [-raw-baseline scripts/demo_ui_lint/raw_literals_baseline.json] [-update-raw]";

class ExitErr extends Error {
  // 注意：node type stripping 不做代码生成 ⇒ **禁参数属性**（`constructor(readonly x)`）
  readonly code: number;
  constructor(code: number) {
    super("exit");
    this.name = "ExitErr";
    this.code = code;
  }
}

function die(code: number, msg: string): never {
  process.stderr.write(msg);
  throw new ExitErr(code);
}

class UsageError extends Error {}

function parseArgs(argv: readonly string[]): Opts {
  const o: Opts = {
    demoDir: "demo",
    rulesPath: "scripts/demo_ui_lint/rules.json",
    selftest: false,
    rawBaseline: "scripts/demo_ui_lint/raw_literals_baseline.json",
    updateRaw: false,
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i] ?? "";
    // Go flag 口径：首个非 flag 参数（或单个 "-"）后停止解析，其余当位置参数忽略
    if (!a.startsWith("-") || a === "-") break;
    const body = a.replace(/^--?/, "");
    const eq = body.indexOf("=");
    const name = eq >= 0 ? body.slice(0, eq) : body;
    const inline = eq >= 0 ? body.slice(eq + 1) : undefined;
    if (name === "demo" || name === "rules" || name === "raw-baseline") {
      let v = inline;
      if (v === undefined) {
        const next = argv[i + 1];
        if (next === undefined) throw new UsageError(`${name} 缺参数值`);
        v = next;
        i++;
      }
      if (name === "demo") o.demoDir = v;
      else if (name === "rules") o.rulesPath = v;
      else o.rawBaseline = v;
      continue;
    }
    if (name === "selftest" || name === "update-raw") {
      // 本仓 #289 审阅 P3-1 口径：拒绝执行而非猜语义（Go flag 会解析 =false 继续跑）
      if (inline !== undefined) throw new UsageError(`布尔 flag -${name} 不接受 =value 形态`);
      if (name === "selftest") o.selftest = true;
      else o.updateRaw = true;
      continue;
    }
    throw new UsageError(`未知参数 -${name}`);
  }
  return o;
}

/**
 * rules.json → Rules。**类型错误一律抛**（Go `json.Unmarshal` 对
 * `min_class_sites: "x"` 这类形态报错 → 调用方 exit 2）；缺键走 Go 零值口径。
 * 不静默 String() 化——那会把 `classes: [1]` 变成合法类名 "1"。
 */
function parseRules(raw: unknown): Rules {
  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) throw new Error("顶层须是对象");
  const o = raw as Record<string, unknown>;
  const strArr = (v: unknown, field: string): string[] => {
    if (v === undefined) return [];
    if (!Array.isArray(v)) throw new Error(`${field} 须是字符串数组`);
    return v.map((x) => {
      if (typeof x !== "string") throw new Error(`${field} 元素须是字符串`);
      return x;
    });
  };
  const dynClass = (v: unknown): DynClassRule[] => {
    if (v === undefined) return [];
    if (!Array.isArray(v)) throw new Error("dynamic_class_assigns 须是数组");
    return v.map((x) => {
      if (x === null || typeof x !== "object") throw new Error("dynamic_class_assigns 元素须是对象");
      const r = x as Record<string, unknown>;
      return { where: typeof r["where"] === "string" ? r["where"] : "", classes: strArr(r["classes"], "dynamic_class_assigns.classes") };
    });
  };
  const dynID = (v: unknown): DynIDRule[] => {
    if (v === undefined) return [];
    if (!Array.isArray(v)) throw new Error("dynamic_id_prefixes 须是数组");
    return v.map((x) => {
      if (x === null || typeof x !== "object") throw new Error("dynamic_id_prefixes 元素须是对象");
      const r = x as Record<string, unknown>;
      return { prefix: typeof r["prefix"] === "string" ? r["prefix"] : "", ids: strArr(r["ids"], "dynamic_id_prefixes.ids") };
    });
  };
  const minClass = o["min_class_sites"];
  if (minClass !== undefined && (typeof minClass !== "number" || !Number.isInteger(minClass))) {
    throw new Error("min_class_sites 须是整数");
  }
  return {
    min_class_sites: minClass ?? 0,
    dynamic_class_assigns: dynClass(o["dynamic_class_assigns"]),
    dynamic_id_prefixes: dynID(o["dynamic_id_prefixes"]),
    class_whitelist: strArr(o["class_whitelist"], "class_whitelist"),
    var_whitelist: strArr(o["var_whitelist"], "var_whitelist"),
  };
}

/** 目录列举 + 后缀过滤（Go filepath.Glob 的字节序口径；. 开头的文件也匹配）。 */
function globSuffix(dir: string, suffix: string): string[] {
  let names: string[];
  try {
    names = fs.readdirSync(dir);
  } catch {
    return [];
  }
  return byteSort(names.filter((n) => n.endsWith(suffix)).map((n) => path.join(dir, n)));
}

function readSrc(demoDir: string, name: string): string {
  try {
    return fs.readFileSync(path.join(demoDir, name), "utf8");
  } catch (e) {
    die(2, `demo_ui_lint: ${name} 不可读: ${(e as Error).message}\n`);
  }
}

function collectSources(o: Opts): Sources {
  const html = o.selftest ? SELFTEST_HTML : readSrc(o.demoDir, "index.html");

  // JS 扫描面 = 入口 + js/*.ts 排序合并（F4 收尾后旧栈入口 app.ts 退役）
  let js = SELFTEST_JS;
  if (!o.selftest) {
    const mods = globSuffix(path.join(o.demoDir, "js"), ".ts");
    if (mods.length === 0) die(2, "demo_ui_lint: demo/js/ 无模块文件（拆分后形态预期）\n");
    let b = "";
    for (const f of mods) {
      try {
        b += "\n" + fs.readFileSync(f, "utf8");
      } catch (e) {
        die(2, `demo_ui_lint: ${f} 不可读: ${(e as Error).message}\n`);
      }
    }
    js = b;
  }

  // css = demo 目录下全部 .css + src/*.css 合并解析（定义面跨文件）
  let css = SELFTEST_CSS;
  if (!o.selftest) {
    const files = globSuffix(o.demoDir, ".css");
    const srcCSS = globSuffix(path.join(o.demoDir, "src"), ".css");
    if (files.length === 0 && srcCSS.length === 0) {
      die(2, `demo_ui_lint: ${o.demoDir} 下（含 src/）无 .css 可扫\n`);
    }
    let b = "";
    for (const f of [...files, ...srcCSS]) {
      try {
        b += "\n" + fs.readFileSync(f, "utf8");
      } catch (e) {
        die(2, `demo_ui_lint: ${f} 不可读: ${(e as Error).message}\n`);
      }
    }
    css = b;
  }

  // 新栈面：src/**/*.svelte + src/**/*.ts（src/data/ 排除——生成物，本地/CI 抽取面漂移）
  let newStackSrc = SELFTEST_SVELTE;
  if (!o.selftest) {
    let b = "";
    try {
      walkDirSorted(path.join(o.demoDir, "src"), (full, name, isDir) => {
        if (isDir) {
          if (name === "data") return "skip";
          return;
        }
        if (name.endsWith(".svelte") || name.endsWith(".ts")) b += "\n" + fs.readFileSync(full, "utf8");
      });
    } catch (e) {
      die(2, `demo_ui_lint: demo/src/ 不可扫: ${(e as Error).message}\n`);
    }
    newStackSrc = b;
  }
  return { html, js, css, newStackSrc };
}

/** 结果排序：Go `sort.Slice(by kind)`——kind 相同保持插入序（稳定排序复刻）。 */
function sortIssues(issues: Issue[]): void {
  issues.sort((a, b) => byteCompare(a.kind, b.kind));
}

export function runArgv(argv: readonly string[]): number {
  let o: Opts;
  try {
    o = parseArgs(argv);
  } catch (e) {
    if (e instanceof UsageError) {
      process.stderr.write(`demo_ui_lint: ${e.message}\n${USAGE}\n`);
      return 2;
    }
    throw e;
  }
  try {
    if (o.selftest) {
      const rawErr = selftestRaw();
      if (rawErr !== null) die(1, `demo_ui_lint: -selftest 裸值棘轮证红失败: ${rawErr}\n`);
    }

    let rl: Rules;
    if (o.selftest) {
      rl = selftestRules();
    } else {
      let text: string;
      try {
        text = fs.readFileSync(o.rulesPath, "utf8");
      } catch (e) {
        die(2, `demo_ui_lint: 规则文件不可读: ${(e as Error).message}\n`);
      }
      try {
        rl = parseRules(JSON.parse(text));
      } catch (e) {
        die(2, `demo_ui_lint: 规则文件坏 JSON: ${(e as Error).message}\n`);
      }
    }

    const src = collectSources(o);
    const { issues, stats, bindings } = analyze(src, rl);

    if (o.selftest) {
      const kinds = new Map<string, number>();
      for (const i of issues) kinds.set(i.kind, (kinds.get(i.kind) ?? 0) + 1);
      const k = (n: string): number => kinds.get(n) ?? 0;
      // zombie 下限 2 = 僵尸两张表（dynamic_class_assigns/var_whitelist）雷各一
      if (k("class") < 1 || k("var") < 1 || k("id") < 1 || k("zombie") < 2 || k("mono") < 1) {
        die(
          1,
          `demo_ui_lint: -selftest 未达到五类证红（class=${k("class")} var=${k("var")} id=${k("id")} zombie=${k("zombie")} mono=${k("mono")}）——闸失效\n`,
        );
      }
      // 泛型回归锚：$<T>("ghost") 形态必须被抓——正则退化丢泛型分支时本断言红
      if (!issues.some((i) => i.msg.includes("no-such-id-generic"))) {
        die(1, `demo_ui_lint: -selftest 泛型形态 $<T>("id") 未被抓——泛型抽取分支失明复发（审阅 P2-1 回归锚）\n`);
      }
      // toggle 双参锚：force 布尔参里的比较字面量被当类名抽取 = 事故指纹；
      // 首参特判退化（toggle 首参也漏抽）同样红，两面一次锁死。
      if (issues.some((i) => i.msg.includes(`类名 "off"`))) {
        die(1, `demo_ui_lint: -selftest toggle force 参字面量 "off" 被当类名——classListArgs 过采集复发（D8）\n`);
      }
      if (!issues.some((i) => i.msg.includes(`"phantom-toggle"`))) {
        die(1, `demo_ui_lint: -selftest toggle 首参未定义类未被抽到——首参特判退化\n`);
      }
      process.stdout.write(
        `demo_ui_lint: -selftest 五类证红 OK + 泛型锚 OK + 裸值棘轮六路 OK（class=${k("class")} var=${k("var")} id=${k("id")} zombie=${k("zombie")} mono=${k("mono")}）\n`,
      );
      return 0;
    }

    issues.push(...logoIssues(o.demoDir));

    // classList 抽取面记录（审阅 2026-10-03 P3-7 销项定性：文本闸防不住定向
    // 变量化掏空——变量实参在文本层不可解析，完整解需 AST 级实参追踪，
    // 超出本文本闸能力边界——记录在案，不做半吊子假闸。）
    const chainSites = countMatches(RE_JS_CLASSLIST_CHAIN, src.js);
    process.stdout.write(
      `demo_ui_lint: classList 可解析位点 ${chainSites + countVarSites(src.js, bindings.varBind, bindings.varAmbiguous)}（观测值——跌破历史值时人工复核抽取面）\n`,
    );

    // 抽取面下限（各路有效位点塌缩即红）
    issues.push(...coverageIssues(stats, rl));

    // ── 裸值棘轮（#222 P0 第三批）：存量冻结、只减不增 ──
    let rawEntries: RawEntry[];
    try {
      rawEntries = collectRawLiterals(o.demoDir);
    } catch (e) {
      die(2, `demo_ui_lint: 裸值扫描失败: ${(e as Error).message}\n`);
    }
    if (o.updateRaw) {
      try {
        writeRawBaseline(o.rawBaseline, rawEntries);
      } catch (e) {
        die(2, `demo_ui_lint: 写裸值基线失败: ${(e as Error).message}\n`);
      }
      process.stdout.write(
        `demo_ui_lint: 裸值基线已重写 ${o.rawBaseline}（${rawEntries.length} 条 / 颜色 ${countRawKind(rawEntries, "color")} + 字号 ${countRawKind(rawEntries, "font-px")}）\n`,
      );
      return 0;
    }
    let baseRaw: RawEntry[];
    try {
      baseRaw = loadRawBaseline(o.rawBaseline);
    } catch (e) {
      die(2, `demo_ui_lint: 裸值基线不可读 ${o.rawBaseline}: ${(e as Error).message}（先跑 -update-raw）\n`);
    }
    issues.push(...checkRaw(rawEntries, baseRaw));

    if (issues.length > 0) {
      sortIssues(issues);
      for (const i of issues) process.stderr.write(`[demo_ui_lint][${i.kind}] ${i.msg}\n`);
      process.stderr.write(`demo_ui_lint: ${issues.length} 条未命中——字符串契约对账红\n`);
      return 1;
    }
    process.stdout.write(
      `demo_ui_lint: 类名/CSS 变量/id/mono 连字对账全部通过（位点 class=${stats.sitesClass}〔不可解析 ${stats.sitesUnresolved}〕/ id=${stats.sitesID} / var=${stats.sitesVar} / mono=${stats.sitesMono}）\n`,
    );
    return 0;
  } catch (e) {
    if (e instanceof ExitErr) return e.code;
    throw e;
  }
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  process.exit(runArgv(process.argv.slice(2)));
}
