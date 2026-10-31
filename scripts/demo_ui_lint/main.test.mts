// demo_ui_lint.test.mts —— 五路判定族 + 裸值棘轮 + CLI 端到端（.mts 重写批）。
//
// 覆盖面（每条都是真跑，不是纸面断言）：
//   - 提取器：parseCSS / classListArgs / firstTopArg / normSel / ligClosed
//   - 检查 B（类名）：锚定失效、单类单元全局合法、复合单元必须整体落候选闭包、
//     未锚定降级全局检查、contains 读操作不查、toggle force 参不误采
//   - 检查 A（CSS 变量）：未定义红、带回退值跳过、setProperty/inline style 计入定义面
//   - 检查 C（id）：字面量缺失、动态前缀登记与否
//   - 检查 D（mono 连字）：无声明红、值 none 绿、值 normal 红（P3-⑦ 值判据）
//   - 僵尸条目四张表 + 抽取面下限 + 裸值棘轮六路 + Go JSON 序列化口径
//   - CLI：-selftest / 红 fixture / 载入失败 exit 2 / 布尔 =value 显式拒绝
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { projectRoot } from "../internal/capi.mts";
import { goJSONMarshalIndent } from "../internal/text.mts";
import {
  analyze,
  classListArgs,
  coverageIssues,
  firstTopArg,
  ligClosed,
  logoIssues,
  normSel,
  parseCSS,
} from "./main.mts";
import type { Issue, Rules, Sources, Stats } from "./main.mts";
import { aggregateRaw, checkRaw, relForBaseline, writeRawBaseline } from "./raw.mts";
import type { RawEntry } from "./raw.mts";

const MAIN = path.join(import.meta.dirname, "main.mts");
const FIXTURE = "scripts/demo_ui_lint/testdata/red";

function emptyRules(patch: Partial<Rules> = {}): Rules {
  return {
    min_class_sites: 0,
    dynamic_class_assigns: [],
    dynamic_id_prefixes: [],
    class_whitelist: [],
    var_whitelist: [],
    ...patch,
  };
}

function src(patch: Partial<Sources> = {}): Sources {
  return { html: "", js: "", css: "", newStackSrc: "", ...patch };
}

/** 只看某一 kind 的 issues 文案（排序无关——判定面是集合）。 */
function msgsOf(issues: Issue[], kind: string): string[] {
  return issues
    .filter((i) => i.kind === kind)
    .map((i) => i.msg)
    .sort();
}

// ── 提取器 ───────────────────────────────────────────────────

test("classListArgs：多类名展开 / 非字面量返空 / toggle 只取首参", () => {
  assert.deepEqual(classListArgs("add", '"a", "b"'), ["a", "b"]);
  assert.deepEqual(classListArgs("add", "cls"), []);
  // toggle(cls, force)：force 里的比较字面量不是类名（2026-10-10 审阅 P1-2）
  assert.deepEqual(classListArgs("toggle", '"on", seg.dataset.v === "off"'), ["on"]);
  assert.deepEqual(classListArgs("contains", '"on"'), ["on"]);
});

test("firstTopArg：括号/方括号内逗号不腰斩，字符串内逗号不腰斩", () => {
  assert.equal(firstTopArg('a("x,y"), b'), 'a("x,y")');
  assert.equal(firstTopArg('f(x), g'), "f(x)");
  assert.equal(firstTopArg("plain"), "plain");
});

test("normSel：首尾 trim + 内部空白折叠（手写空格差异不产生假红）", () => {
  assert.equal(normSel("  .a   .b\t"), ".a .b");
});

test("ligClosed：值判据——none/no-common-ligatures 绿，normal 与复合值红", () => {
  assert.equal(ligClosed("font-variant-ligatures: none"), true);
  assert.equal(ligClosed("font-variant-ligatures:no-common-ligatures;"), true);
  assert.equal(ligClosed("font-variant-ligatures: normal"), false);
  assert.equal(ligClosed("font-variant-ligatures: none /* x */"), false); // 复合值逼规范形态
  assert.equal(ligClosed("color: red"), false);
});

test("parseCSS：@media 头剥离 / 注释剥除 / 复合单元与变量定义", () => {
  const css = `/* .ghost {} */ @media (max-width: 10px) { .a .b { color: var(--x); } }
:root { --y: 1px; } #id.c { }`;
  const { units, vars } = parseCSS(css);
  const classSets = units.map((u) => [...u.classes].sort().join("+"));
  assert.ok(classSets.includes("a+b"), "复合选择器成单元");
  assert.deepEqual(vars, new Set(["--y"]));
  assert.ok(units.some((u) => u.id === "id" && u.classes.has("c")), "#id.c 同段 id+类");
  assert.ok(!classSets.includes("ghost"), "注释里的选择器不参与");
});

// ── 检查 B：类名对账 ───────────────────────────────────────

test("检查 B：锚定失效的类名报红（对元素永不生效）", () => {
  const { issues } = analyze(
    src({ html: `<div id="box" class="tab"></div>`, js: `$("box").classList.add("ghost")`, css: `.tab {}` }),
    emptyRules(),
  );
  const m = msgsOf(issues, "class");
  assert.equal(m.length, 1);
  assert.match(m[0] ?? "", /add 类名 "ghost" 对元素 #box 永不生效/);
});

test("检查 B：单类单元（全局工具类）对任何元素合法", () => {
  const { issues } = analyze(
    src({ html: `<div id="box"></div>`, js: `$("box").classList.add("muted")`, css: `.muted { color: gray; }` }),
    emptyRules(),
  );
  assert.deepEqual(msgsOf(issues, "class"), []);
});

test("检查 B：复合单元须整体落在元素候选类闭包内（stdin-row 实锤形态）", () => {
  const bad = analyze(
    src({
      html: `<div id="row" class="row"></div>`,
      js: `$("row").classList.add("active")`,
      css: `.tab.active { color: red; }`,
    }),
    emptyRules(),
  );
  assert.equal(msgsOf(bad.issues, "class").length, 1, "row 没有 tab 类，.tab.active 对它不生效");

  const good = analyze(
    src({
      html: `<div id="row" class="row tab"></div>`,
      js: `$("row").classList.add("active")`,
      css: `.tab.active { color: red; }`,
    }),
    emptyRules(),
  );
  assert.deepEqual(msgsOf(good.issues, "class"), []);
});

test("检查 B：未锚定变量走降级全局检查（全库无定义才红）", () => {
  const r = analyze(
    src({
      html: `<div id="box"></div>`,
      js: `qs.classList.add("ghost2"); qs.classList.add("muted");`,
      css: `.muted {}`,
    }),
    emptyRules(),
  );
  const m = msgsOf(r.issues, "class");
  assert.equal(m.length, 1);
  assert.match(m[0] ?? "", /类名 "ghost2" 全库无定义（未锚定元素，降级全局检查）/);
});

test("检查 B：contains 读操作不查；toggle force 参字面量不入账", () => {
  const r = analyze(
    src({
      html: `<div id="box"></div>`,
      js: `$("box").classList.contains("nope"); $("box").classList.toggle("nope2", v === "off");`,
      css: ``,
    }),
    emptyRules(),
  );
  const m = msgsOf(r.issues, "class");
  assert.equal(m.length, 1, "只报 toggle 首参 nope2，contains 与 force 参不报");
  assert.match(m[0] ?? "", /"nope2"/);
  assert.ok(!m.some((s) => s.includes(`"off"`)), "force 参字面量不许当类名");
});

// ── 检查 A：CSS 变量 ───────────────────────────────────────

test("检查 A：未定义变量红 / 带回退值跳过 / setProperty 与内联 style 计入定义面", () => {
  const undef = analyze(src({ css: `.a { color: var(--nope); }` }), emptyRules());
  assert.equal(msgsOf(undef.issues, "var").length, 1);

  const fb = analyze(src({ css: `.a { color: var(--nope, red); }` }), emptyRules());
  assert.deepEqual(msgsOf(fb.issues, "var"), [], "带回退值不破坏渲染");

  const viaJS = analyze(src({ js: `el.style.setProperty("--nope", "1px")`, css: `.a { color: var(--nope); }` }), emptyRules());
  assert.deepEqual(msgsOf(viaJS.issues, "var"), []);

  const viaInline = analyze(src({ js: `el.innerHTML = '<b style="--nope:1px"></b>'`, css: `.a { color: var(--nope); }` }), emptyRules());
  assert.deepEqual(msgsOf(viaInline.issues, "var"), []);
});

test("检查 A：var_whitelist 定义面豁免，但僵尸判定不看白名单", () => {
  const r = analyze(
    src({ css: `.a { color: var(--keep); }` }),
    emptyRules({ var_whitelist: ["--keep", "--unused"] }),
  );
  assert.deepEqual(msgsOf(r.issues, "var"), [], "白名单豁免未定义");
  const z = msgsOf(r.issues, "zombie");
  assert.equal(z.length, 1, "--unused 无定义无引用 = 僵尸；--keep 有引用不僵尸");
  assert.match(z[0] ?? "", /var_whitelist 登记的 "--unused"/);
});

// ── 检查 C：id 对账 ──────────────────────────────────────

test("检查 C：字面量 id 缺失红 / 动态前缀未登记红 / 已登记绿", () => {
  const bad = analyze(src({ js: `$("missing"); $("tab-" + n);` }), emptyRules());
  const m = msgsOf(bad.issues, "id");
  assert.equal(m.length, 2);
  assert.match(m.join("\n"), /在 index.html 无此 id/);
  assert.match(m.join("\n"), /动态 id 前缀 "tab-"\+ 未在 rules.json 登记/);

  const good = analyze(
    src({ html: `<div id="tab-result"></div>`, js: `$("tab-result"); $("tab-" + n);` }),
    emptyRules({ dynamic_id_prefixes: [{ prefix: "tab-", ids: ["tab-result"] }] }),
  );
  assert.deepEqual(good.issues.filter((i) => i.kind === "id"), []);
});

test("检查 C：泛型实参 $<T>(\"id\") 形态必须被抽取（2026-10-04 审阅 P2-1 回归锚）", () => {
  const r = analyze(src({ js: `const t = $<HTMLTextAreaElement>("ghost-generic")` }), emptyRules());
  assert.match(msgsOf(r.issues, "id").join("\n"), /ghost-generic/);
});

// ── 检查 D：mono 连字 ────────────────────────────────────

test("检查 D：消费 --mono 无关闭声明红 / 值 none 绿 / 值 normal 红", () => {
  const r = analyze(
    src({
      css: `.face { font: 12px var(--mono); }
.ok { font: 12px var(--mono); font-variant-ligatures: none; }
.normal { font: 12px var(--mono); font-variant-ligatures: normal; }
.vr { font: 12px var(--vr-mono); }`,
    }),
    emptyRules(),
  );
  const m = msgsOf(r.issues, "mono");
  assert.equal(m.length, 3, "face 无声明 + normal 值非关闭 + vr 无声明");
  assert.ok(m.some((s) => s.includes(".face 消费 var(--mono)") && s.includes("连字复活")));
  assert.ok(m.some((s) => s.includes(".normal 的 font-variant-ligatures 值非关闭态")));
  assert.ok(m.some((s) => s.includes(".vr 消费")));
});

test("检查 D：豁免集从带声明规则块收集——枚举块选择器连坐即绿", () => {
  const r = analyze(
    src({ css: `.face { font: 12px var(--mono); }\n.face { font-variant-ligatures: none; }` }),
    emptyRules(),
  );
  assert.deepEqual(msgsOf(r.issues, "mono"), [], "选择器 ∈ 豁免集即不红（旧栈枚举块形态）");
});

test("检查 D：Svelte <style> 块并入 css 面、模板段并入 html 面", () => {
  const r = analyze(
    src({
      newStackSrc: `<div class="mono-face">x</div>\n<style>\n.mono-face { font: 12px var(--mono); }\n</style>`,
    }),
    emptyRules(),
  );
  assert.equal(msgsOf(r.issues, "mono").length, 1, "<style> 块内的 mono 面必须入账");
  assert.equal(msgsOf(r.issues, "var").length, 1, "--mono 未定义（var 面同样并入）");
});

// ── 僵尸条目 ─────────────────────────────────────────────

test("僵尸：四张表各自无引用即红，有引用即绿", () => {
  const r = analyze(
    src({ html: `<div id="tab-live"></div>`, js: `$("box2").classList.add("live-class")`, css: `.live-class {}` }),
    emptyRules({
      dynamic_class_assigns: [{ where: "w", classes: ["live-class", "dead-class"] }],
      class_whitelist: ["dead-wl"],
      dynamic_id_prefixes: [{ prefix: "tab-", ids: ["tab-live", "tab-dead"] }],
      var_whitelist: ["--dead-var"],
    }),
  );
  const z = msgsOf(r.issues, "zombie");
  assert.equal(z.length, 4, "dead-class / dead-wl / tab-dead / --dead-var 各一条");
  assert.ok(z.some((s) => s.includes("dynamic_class_assigns(w) 登记的类 \"dead-class\"")));
  assert.ok(z.some((s) => s.includes("class_whitelist 登记的 \"dead-wl\"")));
  assert.ok(z.some((s) => s.includes("dynamic_id_prefixes(tab-) 登记的 id \"tab-dead\"")));
  assert.ok(z.some((s) => s.includes("var_whitelist 登记的 \"--dead-var\"")));
});

// ── 抽取面下限 ───────────────────────────────────────────

test("抽取面下限：class 位点低于 min_class_sites / var 位点低于 60 各自报 coverage", () => {
  const stats: Stats = { sitesClass: 1, sitesUnresolved: 0, sitesID: 0, sitesVar: 2, sitesMono: 0 };
  const one = coverageIssues(stats, emptyRules({ min_class_sites: 2 }));
  assert.equal(one.length, 1);
  assert.match(one[0]?.msg ?? "", /class=1（下限 2）/);
  assert.match(one[0]?.msg ?? "", /var=2（下限 60）/);

  const ok = coverageIssues({ ...stats, sitesClass: 3, sitesVar: 60, sitesMono: 40 }, emptyRules({ min_class_sites: 3 }));
  assert.deepEqual(ok, []);
});

test("logo 双份：缺失 / 分叉 / 一致三态（pages.yml 用根份、本地预览用 demo 份）", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "dul-logo-"));
  const names = ["vitro-icon.svg", "vitro-icon-light.svg", "vitro-icon-dark.svg"];
  fs.mkdirSync(path.join(root, "assets", "logo"), { recursive: true });
  fs.mkdirSync(path.join(root, "demo", "assets", "logo"), { recursive: true });
  for (const n of names) fs.writeFileSync(path.join(root, "assets", "logo", n), "<svg>same</svg>");
  const missing = logoIssues(path.join(root, "demo"));
  assert.equal(missing.length, 3, "demo 份全缺 → 三条缺失");
  assert.match(missing[0]?.msg ?? "", /logo 双份缺失：vitro-icon\.svg（根份在=true \/ demo 份在=false）/);

  for (const n of names) fs.writeFileSync(path.join(root, "demo", "assets", "logo", n), "<svg>same</svg>");
  assert.deepEqual(logoIssues(path.join(root, "demo")), [], "两份一致即绿");

  fs.writeFileSync(path.join(root, "demo", "assets", "logo", names[0] ?? ""), "<svg>drift</svg>");
  const drift = logoIssues(path.join(root, "demo"));
  assert.equal(drift.length, 1);
  assert.match(drift[0]?.msg ?? "", /logo 双份分叉：vitro-icon\.svg/);
});

// ── 裸值棘轮 ─────────────────────────────────────────────

test("裸值棘轮：同集绿，新增/用量增加/减少/消失各自红", () => {
  const base: RawEntry[] = [
    { file: "demo/src/a.css", kind: "color", literal: "#fff", count: 1 },
    { file: "demo/src/a.css", kind: "font-px", literal: "12px", count: 2 },
  ];
  assert.deepEqual(checkRaw(base, base), []);

  const added = checkRaw([...base, { file: "demo/src/b.svelte", kind: "color", literal: "#123456", count: 1 }], base);
  assert.equal(added.length, 1);
  assert.match(added[0]?.msg ?? "", /新增裸值 #123456（color，demo\/src\/b\.svelte）/);

  const grew = checkRaw(
    [
      { file: "demo/src/a.css", kind: "color", literal: "#fff", count: 1 },
      { file: "demo/src/a.css", kind: "font-px", literal: "12px", count: 3 },
    ],
    base,
  );
  assert.match(grew.map((i) => i.msg).join("\n"), /裸值用量增加 demo\/src\/a\.css（12px，2 → 3 次）/);

  const shrank = checkRaw([{ file: "demo/src/a.css", kind: "color", literal: "#fff", count: 1 }], base);
  assert.match(shrank.map((i) => i.msg).join("\n"), /僵尸基线 demo\/src\/a\.css（font-px，12px）已消失/);

  const decreased = checkRaw(
    [
      { file: "demo/src/a.css", kind: "color", literal: "#fff", count: 1 },
      { file: "demo/src/a.css", kind: "font-px", literal: "12px", count: 1 },
    ],
    base,
  );
  assert.match(decreased.map((i) => i.msg).join("\n"), /裸值用量减少 demo\/src\/a\.css（12px，2 → 1 次）/);
});

test("裸值棘轮：rgba 分量变化算不同字面量（只记函数名的旧形态会假绿）", () => {
  const base: RawEntry[] = [{ file: "a.css", kind: "color", literal: "rgba(0, 0, 0, .5)", count: 1 }];
  const moved = checkRaw([{ file: "a.css", kind: "color", literal: "rgba(0, 0, 0, .6)", count: 1 }], base);
  assert.equal(moved.length, 2, "新增 + 僵尸各一条");
});

test("aggregateRaw：同键合并计数，输出按 file/kind/literal 字节序", () => {
  const out = aggregateRaw([
    { file: "b.css", kind: "color", literal: "#bbb", count: 1 },
    { file: "a.css", kind: "font-px", literal: "12px", count: 1 },
    { file: "a.css", kind: "font-px", literal: "12px", count: 2 },
    { file: "a.css", kind: "color", literal: "#aaa", count: 1 },
  ]);
  assert.deepEqual(
    out.map((e) => `${e.file}|${e.kind}|${e.literal}|${e.count}`),
    ["a.css|color|#aaa|1", "a.css|font-px|12px|3", "b.css|color|#bbb|1"],
  );
});

test("relForBaseline：相对 demoDir 原样落相对路径，绝对 demoDir 归一为仓库相对", () => {
  assert.equal(relForBaseline("demo", path.join("demo", "src", "a.css")), "demo/src/a.css");
  const absDemo = path.resolve("demo");
  assert.equal(relForBaseline(absDemo, path.join(absDemo, "src", "a.css")), "demo/src/a.css");
});

test("writeRawBaseline：键序 = Go struct 声明序 + SetEscapeHTML 转义 + 尾换行", () => {
  // #392 审阅 P3-2（2026-10-31）：TEMP 环境变量 Linux 不存在（#360 同族）
  // → os.tmpdir() 跨平台；realpathSync（Windows 8.3 短路径展开）保留
  const dir = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), "dul-raw-"));
  const p = path.join(dir, "baseline.json");
  writeRawBaseline(p, [{ file: "demo/src/a.css", kind: "color", literal: "#fff", count: 1 }]);
  const text = fs.readFileSync(p, "utf8");
  assert.ok(text.endsWith("}\n"), "尾换行");
  const keys = [...text.matchAll(/^  "([^"]+)":/gm)].map((m) => m[1]);
  assert.deepEqual(keys, ["_comment", "note", "surface", "entries"]);
  assert.ok(text.includes("\\u003cstyle\\u003e"), "SetEscapeHTML 口径：< > 转义");
  assert.equal(goJSONMarshalIndent({ a: 1, b: 2 }), JSON.stringify({ a: 1, b: 2 }, null, 2), "无特殊字符时与 stringify 同形");
});

// ── CLI 端到端（真进程，比 stdout/stderr/退出码）─────────

function cli(args: string[]): { out: string; err: string; rc: number } {
  const r = spawnSync(process.execPath, [MAIN, ...args], { cwd: projectRoot(), encoding: "utf8" });
  return { out: r.stdout ?? "", err: r.stderr ?? "", rc: r.status ?? -1 };
}

test("CLI：-selftest 五类证红自检 exit 0，文案逐字锁定", () => {
  const r = cli(["-selftest"]);
  assert.equal(r.rc, 0);
  assert.equal(
    r.out,
    "demo_ui_lint: -selftest 五类证红 OK + 泛型锚 OK + 裸值棘轮六路 OK（class=2 var=6 id=2 zombie=2 mono=3）\n",
  );
});

test("CLI：红 fixture exit 1，逐条列 stderr 且同 kind 保持插入序（13 条 >12 排序阈值）", () => {
  const r = cli([
    "-demo",
    FIXTURE,
    "-rules",
    `${FIXTURE}/rules.json`,
    "-raw-baseline",
    `${FIXTURE}/raw_baseline.json`,
  ]);
  assert.equal(r.rc, 1);
  const lines = r.err.trimEnd().split("\n");
  assert.equal(lines.at(-1), "demo_ui_lint: 13 条未命中——字符串契约对账红");
  assert.equal(lines.length, 14);
  // kind 升序；同 kind 保持插入序（Go 版 SliceStable —— 13 条越过插入排序阈值，
  // 若回退成 sort.Slice 此断言即红）
  const kinds = lines.slice(0, -1).map((l) => /^\[demo_ui_lint\]\[(\w+)\]/.exec(l)?.[1] ?? "");
  assert.deepEqual(kinds, [
    "class",
    "class",
    "coverage",
    "id",
    "logo",
    "logo",
    "logo",
    "mono",
    "mono",
    "var",
    "var",
    "zombie",
    "zombie",
  ]);
  // 插入序：链式写法（$("id").classList.*）先于变量写法（el.classList.*）入账
  assert.match(lines[0] ?? "", /add 类名 "tab" 对元素 #nope-id 永不生效/);
  assert.match(lines[1] ?? "", /add 类名 "ghost-class" 对元素 #box 永不生效/);
  assert.equal(r.out.split("\n")[0], "demo_ui_lint: classList 可解析位点 2（观测值——跌破历史值时人工复核抽取面）");
});

test("CLI：规则文件缺失 exit 2（fail loud，不静默放过）", () => {
  const r = cli(["-demo", "demo", "-rules", "scripts/demo_ui_lint/nope.json"]);
  assert.equal(r.rc, 2);
  assert.match(r.err, /demo_ui_lint: 规则文件不可读: /);
});

test("CLI：布尔 flag 带 =value 显式拒绝（不猜语义），未知参数 exit 2", () => {
  const eq = cli(["-selftest=false"]);
  assert.equal(eq.rc, 2);
  assert.match(eq.err, /布尔 flag -selftest 不接受 =value 形态/);
  const bogus = cli(["--definitely-bogus"]);
  assert.equal(bogus.rc, 2);
  assert.match(bogus.err, /未知参数 -definitely-bogus/);
});

test("CLI：规则文件类型错 exit 2（Go json.Unmarshal 同口径，不静默 String() 化）", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "dul-rules-"));
  const p = path.join(dir, "rules.json");
  fs.writeFileSync(p, JSON.stringify({ min_class_sites: "3" }), "utf8");
  const r = cli(["-demo", "demo", "-rules", p]);
  assert.equal(r.rc, 2);
  assert.match(r.err, /规则文件坏 JSON: min_class_sites 须是整数/);
});

test("CLI：真实仓库默认模式绿（本闸对 demo/ 现场对账）", () => {
  const r = cli([]);
  assert.equal(r.rc, 0, r.err);
  assert.match(r.out, /类名\/CSS 变量\/id\/mono 连字对账全部通过/);
});
