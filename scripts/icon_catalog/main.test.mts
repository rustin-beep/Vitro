// icon_catalog.test.mts —— 十项契约判定（合成 fixture 逐项证红）+ 真实仓库端到端。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { assertRules, digestOf, readTsv, run } from "./main.mts";
import type { Rules } from "./main.mts";
import { projectRoot } from "../internal/capi.mts";

const MAIN = path.join(import.meta.dirname, "main.mts");

const SVG_OK =
  '<svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" ' +
  'stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">' +
  "<title>甲</title><desc>a</desc><path d=\"M4 4h16\"></path></svg>\n";

function baseRules(): Rules {
  return {
    assets_dir: "moonbit/icons",
    index_tsv: "moonbit/icons/index.tsv",
    geometry_json: "moonbit/icons/icons.json",
    catalog_json: "moonbit/icons/catalog.json",
    svg_attrs: {
      viewBox: "0 0 24 24",
      width: "24",
      height: "24",
      fill: "none",
      stroke: "currentColor",
      "stroke-width": "1.8",
      "stroke-linecap": "round",
      "stroke-linejoin": "round",
    },
    allowed_elements: ["path", "circle", "rect"],
    rect_forbidden_attrs: ["rx", "ry"],
    forbid_color_literal: true,
    forbid_named_color: true,
    forbid_zero_length_subpath: true,
    forbid_aria_hidden: true,
    require_title: true,
    require_desc: true,
    tsv_columns: ["id", "category", "scope", "emoji", "desc"],
    categories: ["ui"],
    scopes: ["core"],
    emoji_required_scopes: ["core"],
    emoji_must_be_unique: true,
    named_colors: ["red", "black"],
  };
}

interface Fixture {
  root: string;
  rulesPath: string;
  edit(rel: string, fn: (s: string) => string): void;
}

/** 最小绿 fixture：1 个合法 svg + 1 行 tsv + 现算 digest + 1 条 catalog。 */
function makeFixture(): Fixture {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-iconcat-"));
  fs.mkdirSync(path.join(root, "moonbit/icons"), { recursive: true });
  fs.writeFileSync(path.join(root, "moonbit/icons/a.svg"), SVG_OK);
  fs.writeFileSync(path.join(root, "moonbit/icons/index.tsv"), "id\tcategory\tscope\temoji\tdesc\na\tui\tcore\tX\t甲\n");
  fs.writeFileSync(path.join(root, "moonbit/icons/catalog.json"), JSON.stringify({ entries: [{ code: 3061, icon: "a" }] }));
  const digest = digestOf(["a"], new Map([["a", fs.readFileSync(path.join(root, "moonbit/icons/a.svg"))]]));
  fs.writeFileSync(path.join(root, "moonbit/icons/icons.json"), JSON.stringify({ digest }));
  const rulesPath = path.join(root, "rules.json");
  fs.writeFileSync(rulesPath, JSON.stringify(baseRules(), null, 2));
  return {
    root,
    rulesPath,
    edit(rel, fn) {
      const p = path.join(root, rel);
      fs.writeFileSync(p, fn(fs.readFileSync(p, "utf8")));
    },
  };
}

function errsOf(f: Fixture): string {
  return run(f.root, f.rulesPath).errs.join("\n");
}

test("绿 fixture：零红，pass 面五项齐", () => {
  const f = makeFixture();
  const r = run(f.root, f.rulesPath);
  assert.deepEqual(r.errs, []);
  assert.equal(r.iconCount, 1);
  assert.equal(r.passes.length, 5); // 资产契约 / 清单值域 / 双向 / 几何层 / 协议值域
  assert.match(r.passes.join("\n"), /几何层 digest 同步：sha256:/);
});

test("readTsv：CRLF / 表头不符 / 列数错 / 空数据行 四处 fail loud", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-iconcat-tsv-"));
  const p = path.join(dir, "x.tsv");
  const cols = ["id", "desc"];
  fs.writeFileSync(p, "id\tdesc\r\na\tb\r\n");
  assert.throws(() => readTsv(dir, p, cols), /含 CRLF/);
  fs.writeFileSync(p, "id\tname\na\tb\n");
  assert.throws(() => readTsv(dir, p, cols), /表头不符/);
  fs.writeFileSync(p, "id\tdesc\na\n");
  assert.throws(() => readTsv(dir, p, cols), /列数=1（应 2）/);
  fs.writeFileSync(p, "id\tdesc\n\n");
  assert.throws(() => readTsv(dir, p, cols), /无数据行/);
  fs.writeFileSync(p, "id\tdesc\na\tb\n\n");
  assert.equal(readTsv(dir, p, cols).length, 1);
});

test("digestOf：拼接序（id\\0svg\\0）+ sha256 前缀；顺序敏感", () => {
  const m = new Map([
    ["a", Buffer.from("A")],
    ["b", Buffer.from("B")],
  ]);
  const d1 = digestOf(["a", "b"], m);
  assert.match(d1, /^sha256:[0-9a-f]{64}$/);
  assert.notEqual(digestOf(["b", "a"], m), d1, "顺序必须影响 digest");
  assert.equal(digestOf(["a", "b"], m), d1, "同输入必须稳定");
});

test("J9 红：属性契约 / 具体色值 / 具名色 / 白名单外图元 / rect rx / 零长度子路径 / aria-hidden", () => {
  const cases: Array<[string, (f: Fixture) => void, RegExp]> = [
    ["属性缺失", (f) => f.edit("moonbit/icons/a.svg", (s) => s.replace('width="24"', 'width="32"')), /属性 width="32"，契约要求 "24"/],
    ["具体色值 hex", (f) => f.edit("moonbit/icons/a.svg", (s) => s.replace('stroke="currentColor"', 'stroke="#fff"')), /出现具体色值/],
    ["具体色值 rgb()", (f) => f.edit("moonbit/icons/a.svg", (s) => s.replace("</svg>", '<rect fill="rgb(1,2,3)"/></svg>')), /出现具体色值/],
    ["具名色", (f) => f.edit("moonbit/icons/a.svg", (s) => s.replace('fill="none"', 'fill="red"')), /出现具名色 fill="red"/],
    ["白名单外图元", (f) => f.edit("moonbit/icons/a.svg", (s) => s.replace("</svg>", "<script/></svg>")), /图元白名单外的 <script>/],
    ["rect 带 rx", (f) => f.edit("moonbit/icons/a.svg", (s) => s.replace("</svg>", '<rect x="1" y="1" rx="2"/></svg>')), /<rect> 带 rx/],
    ["零长度子路径", (f) => f.edit("moonbit/icons/a.svg", (s) => s.replace('d="M4 4h16"', 'd="M4 4h.01"')), /零长度子路径/],
    ["aria-hidden", (f) => f.edit("moonbit/icons/a.svg", (s) => s.replace("<svg ", '<svg aria-hidden="true" ')), /不得写死 aria-hidden/],
    ["缺 title", (f) => f.edit("moonbit/icons/a.svg", (s) => s.replace("<title>甲</title>", "")), /缺 <title>/],
    ["缺 desc", (f) => f.edit("moonbit/icons/a.svg", (s) => s.replace("<desc>a</desc>", "")), /缺 <desc>/],
    ["desc≠id", (f) => f.edit("moonbit/icons/a.svg", (s) => s.replace("<desc>a</desc>", "<desc>b</desc>")), /<desc>="b" 必须等于 id/],
    ["id 命名", (f) => {
      fs.renameSync(path.join(f.root, "moonbit/icons/a.svg"), path.join(f.root, "moonbit/icons/Bad_Id.svg"));
      f.edit("moonbit/icons/index.tsv", (s) => s.replace("a\t", "Bad_Id\t"));
      f.edit("moonbit/icons/Bad_Id.svg", (s) => s.replace("<desc>a</desc>", "<desc>Bad_Id</desc>"));
    }, /id 命名不合法/],
  ];
  for (const [name, mutate, re] of cases) {
    const f = makeFixture();
    mutate(f);
    assert.match(errsOf(f), re, name);
  }
});

test("J9 红：index.tsv 值域 / emoji 唯一 / desc 与 title 不一致 / 孤儿与缺件", () => {
  const category = makeFixture();
  category.edit("moonbit/icons/index.tsv", (s) => s.replace("\tui\t", "\tweird\t"));
  assert.match(errsOf(category), /category="weird" 越界/);

  const scope = makeFixture();
  scope.edit("moonbit/icons/index.tsv", (s) => s.replace("\tcore\t", "\telsewhere\t"));
  assert.match(errsOf(scope), /scope="elsewhere" 越界/);

  const emoji = makeFixture();
  emoji.edit("moonbit/icons/index.tsv", (s) => s.replace("\tX\t", "\t \t"));
  assert.match(errsOf(emoji), /scope=core 必须有 emoji 兼容别名/);

  const dup = makeFixture();
  // 追加第二行同 emoji（同时补 svg 避免孤儿噪声）
  dup.edit("moonbit/icons/index.tsv", (s) => s + "b\tui\tcore\tX\t乙\n");
  fs.writeFileSync(path.join(dup.root, "moonbit/icons/b.svg"), SVG_OK.replace(/<desc>a<\/desc>/, "<desc>b</desc>").replace("甲", "乙"));
  assert.match(errsOf(dup), /emoji "X" 重复（a 与 b）/);

  const mismatch = makeFixture();
  mismatch.edit("moonbit/icons/index.tsv", (s) => s.replace("\t甲", "\t乙"));
  assert.match(errsOf(mismatch), /desc="乙" 与 svg <title>="甲" 不一致/);

  const orphan = makeFixture();
  fs.writeFileSync(path.join(orphan.root, "moonbit/icons/b.svg"), SVG_OK.replace(/<desc>a<\/desc>/, "<desc>b</desc>"));
  assert.match(errsOf(orphan), /孤儿资产 b\.svg：index\.tsv 无此 id/);

  const missing = makeFixture();
  missing.edit("moonbit/icons/index.tsv", (s) => s + "zz\tui\tcore\tY\t丙\n");
  assert.match(errsOf(missing), /缺资产 zz\.svg：index\.tsv 有此 id/);
});

test("J9 红：几何层 digest 过期 / catalog icon 越界", () => {
  const stale = makeFixture();
  stale.edit("moonbit/icons/icons.json", () => JSON.stringify({ digest: "sha256:" + "0".repeat(64) }));
  assert.match(errsOf(stale), /几何层 digest 过期：文件=sha256:0{64}/);

  const cat = makeFixture();
  cat.edit("moonbit/icons/catalog.json", () => JSON.stringify({ entries: [{ code: 3061, icon: "nope" }] }));
  assert.match(errsOf(cat), /E3061 的 icon="nope" 不在资产表/);
});

test("真实仓库：默认绿（OK 行逐字）+ -v 五项 pass", () => {
  const root = projectRoot();
  const r = run(root);
  assert.deepEqual(r.errs, []);
  assert.equal(r.iconCount, 76);

  const def = spawnSync(process.execPath, [MAIN], { cwd: root, encoding: "utf8" });
  assert.equal(def.status, 0, def.stderr);
  assert.equal(def.stdout, "OK：76 个图标，契约全绿\n");

  const v = spawnSync(process.execPath, [MAIN, "-v"], { cwd: root, encoding: "utf8" });
  assert.equal(v.status, 0, v.stderr);
  // 不能用 trim()——会吃掉首行的两个前导空格，导致少计一行
  assert.equal(v.stdout.split("\n").filter((l) => l.startsWith("  ok  ")).length, 5);

  const bad = spawnSync(process.execPath, [MAIN, "--nope"], { cwd: root, encoding: "utf8" });
  assert.equal(bad.status, 2);
});

test("P2-1：icons.json 缺 digest / 空串必须红（不得静默放行）", () => {
  for (const bad of ["{}", '{"digest":""}']) {
    const f = makeFixture();
    fs.writeFileSync(path.join(f.root, "moonbit/icons/icons.json"), bad);
    assert.match(errsOf(f), /缺 digest 字段（空值不得放行/, bad);
  }
});

test("P2-2：规则字段类型畸形必须 fail loud（布尔变 0 / 数组变串 / 对象变数组）", () => {
  const cases: Array<[string, (r: Record<string, unknown>) => void, RegExp]> = [
    ["svg_attrs 变数组", (r) => { r["svg_attrs"] = []; }, /svg_attrs 必须是平面对象/],
    ["布尔变 0", (r) => { r["forbid_color_literal"] = 0; }, /forbid_color_literal 必须是布尔/],
    ["数组变字符串", (r) => { r["categories"] = "词法"; }, /categories 必须是字符串数组/],
    ["named_colors 变字符串", (r) => { r["named_colors"] = "red"; }, /named_colors 必须是字符串数组/],
    ["assets_dir 缺失", (r) => { delete r["assets_dir"]; }, /assets_dir 必须是非空字符串/],
  ];
  for (const [name, mutate, re] of cases) {
    const r = baseRules() as unknown as Record<string, unknown>;
    mutate(r);
    assert.throws(() => assertRules(r), re, name);
  }
  // 合法规则必须通过（防止校验本身过严）
  assert.equal(assertRules(baseRules()).assets_dir, "moonbit/icons");
});
