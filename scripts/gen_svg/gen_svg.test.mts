// gen_svg.test.mts —— SVG 拼装 helper / skills 折行与发现 / packages 层徽标 /
// 真实仓库 -check（15 张图逐字节）。
//
// 真实仓库用例需要 reports/facts.json（gitignored，本地先跑
// `go run ./scripts/facts facts` 采集）——缺失时该用例 fail loud，不静默跳过：
// 环境缺口静默通过就是假绿。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { allBuilt, dispW, discoverSkills, wrapDesc } from "./main.mts";
import { box, esc, svgOpen, textF, textL, textSegs, writeSVG, setCheckMode, drifts } from "./svg.mts";
import { projectRoot } from "../internal/capi.mts";

test("esc：& < > 三面转义（& 先转，则不产生二次匹配）", () => {
  assert.equal(esc("a&b"), "a&amp;b");
  assert.equal(esc("<x>"), "&lt;x&gt;");
  assert.equal(esc("a & <b>"), "a &amp; &lt;b&gt;");
  assert.equal(esc("&amp;"), "&amp;amp;");
  assert.equal(esc("无特殊"), "无特殊");
});

test("box / textL / textF：属性序与 text-anchor 形态", () => {
  assert.equal(box(1, 2, 3, 4, "card", 5), '<rect class="card" x="1" y="2" width="3" height="4" rx="5"/>');
  assert.equal(textL(1, 2, "tn", "a<b"), '<text class="tn" x="1" y="2" text-anchor="start">a&lt;b</text>');
  assert.equal(textF(1, 2, "t", "x", ""), '<text class="t" x="1" y="2" text-anchor="middle">x</text>');
  assert.equal(
    textF(1, 2, "t", "x", "moonbit_test_passed"),
    '<text class="t" x="1" y="2" text-anchor="middle"><tspan data-fact="moonbit_test_passed">x</tspan></text>',
  );
});

test("textSegs：文本段 esc、数字段进 data-fact 锚", () => {
  const out = textSegs(1, 2, "tc", [
    { text: "共 ", num: "", val: 0 },
    { text: "", num: "k", val: 7 },
  ]);
  assert.equal(out, '<text class="tc" x="1" y="2" text-anchor="middle">共 <tspan data-fact="k">7</tspan></text>');
});

test("svgOpen：viewBox / title / @generated 注 / CSS / bg", () => {
  const parts = svgOpen(100, 200, '标"签', "标题", "说明");
  assert.match(parts[0] ?? "", /viewBox="0 0 100 200"/);
  // esc 只转 & < >（Go 版同口径）——引号不转义，aria-label 里裸引号是既有形态
  assert.match(parts[0] ?? "", /aria-label="标"签"/);
  assert.match(parts[1] ?? "", /<title>标题<\/title>/);
  assert.match(parts[2] ?? "", /由 scripts\/gen_svg 生成（勿手改）：说明/);
  assert.match(parts[3] ?? "", /prefers-color-scheme: dark/);
  assert.match(parts[4] ?? "", /<rect class="bg" width="100" height="200"\/>/);
});

test("writeSVG：check 模式无落盘副作用，漂移收进清单", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-svg-"));
  const rel = "x.svg";
  try {
    // 先正写入盘
    setCheckMode(false);
    writeSVG(dir, rel, ["<a/>"]);
    const landed = fs.readFileSync(path.join(dir, rel), "utf8");
    assert.equal(landed, "<a/>\n</svg>\n");

    // check 模式：一致 → 不新增漂移
    const before = drifts().length;
    setCheckMode(true);
    writeSVG(dir, rel, ["<a/>"]);
    assert.equal(drifts().length, before);

    // check 模式：不一致 → 记一条；落盘不变
    writeSVG(dir, rel, ["<b/>"]);
    assert.equal(drifts().length, before + 1);
    assert.equal(fs.readFileSync(path.join(dir, rel), "utf8"), "<a/>\n</svg>\n");

    // check 模式：文件缺失 → 记「落盘缺失」
    writeSVG(dir, "missing.svg", ["<b/>"]);
    assert.match(drifts()[drifts().length - 1] ?? "", /落盘缺失/);
  } finally {
    setCheckMode(false);
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("allBuilt：空清单视为未建（防漏填 builtAs 假绿）", () => {
  const built = new Set(["a", "b"]);
  assert.equal(allBuilt("", built), false);
  assert.equal(allBuilt("a", built), true);
  assert.equal(allBuilt("a b", built), true);
  assert.equal(allBuilt("a c", built), false);
});

test("dispW：CJK 全角算 2，ASCII 算 1", () => {
  assert.equal(dispW("abc"), 3);
  assert.equal(dispW("中文"), 4);
  assert.equal(dispW("a中"), 3);
});

test("wrapDesc：贪心折行 + 超行以 … 收尾 + 残词不腰斩", () => {
  // 单行放得下 → 原样一行
  assert.deepEqual(wrapDesc("短描述", 10, 2), ["短描述"]);
  // 两行放得下 → 两行且不加省略号（切点回退到词边界）
  assert.deepEqual(wrapDesc("abcdefghij klmnopqrst", 12, 2), ["abcdefghij", "klmnopqrst"]);
  // 放不下 → 末行 … 收尾，且不出现半截英文词（"generat…" 类缺陷的回归锚）
  const cut = wrapDesc("generator contract", 8, 1);
  assert.equal(cut.length, 1);
  assert.ok((cut[0] ?? "").endsWith("…"), cut[0]);
  assert.doesNotMatch(cut[0] ?? "", /generat…|contrac…/);
});

test("discoverSkills：真实仓库按 git 入库面发现，name 与目录名一致", () => {
  const skills = discoverSkills(projectRoot());
  assert.ok(skills.length > 0);
  for (const s of skills) {
    assert.ok(s.name !== "");
    assert.ok(s.desc !== "", `${s.name} 缺 description`);
  }
  // 排序确定性（图内卡片顺序依赖它）
  const names = skills.map((s) => s.name);
  assert.deepEqual(names, [...names].sort());
});

test("真实仓库：-check 通过（15 张图与落盘逐字节一致）", () => {
  const facts = path.join(projectRoot(), "reports", "facts.json");
  assert.ok(
    fs.existsSync(facts),
    "缺 reports/facts.json（gitignored）——先跑 go run ./scripts/facts facts 采集（不做 skip 兜底）",
  );
  const r = spawnSync(process.execPath, [path.join(import.meta.dirname, "main.mts"), "-check"], {
    cwd: projectRoot(),
    encoding: "utf8",
  });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /check ok：落盘 SVG 与生成器输出一致/);
});

test("真实仓库：单目标 -check（panorama / teach 独立可达）", () => {
  for (const target of ["panorama", "teach", "skills"]) {
    const r = spawnSync(
      process.execPath,
      [path.join(import.meta.dirname, "main.mts"), "-check", target],
      { cwd: projectRoot(), encoding: "utf8" },
    );
    assert.equal(r.status, 0, `${target}: ${r.stderr}`);
    assert.match(r.stdout, /check ok/);
  }
});
