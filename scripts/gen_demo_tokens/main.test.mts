// gen_demo_tokens.test.mts —— 渲染确定性 / 完备性断言 / J9 判定面（子进程红路径）。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { diffHint, load, render, sortedSizes, verify } from "./main.mts";
import { projectRoot } from "../internal/capi.mts";

const MAIN = path.join(import.meta.dirname, "main.mts");

/** 最小合法真源（DTCG 子集 + 本生成器契约字段）。 */
function baseDoc(): Record<string, unknown> {
  return {
    $schema: "https://design-tokens.github.io/community-group/format/",
    $description: "fixture",
    generatedBy: "scripts/gen_demo_tokens",
    products: ["demo/src/tokens.css", "demo/src/extra.css"],
    base: { tokens: { "--vr-fs": { $value: "14px", $type: "dimension" } } },
    themeOrder: ["ice", "rose"],
    themes: {
      ice: { colorScheme: "light", tokens: { "--vr-bg": { $value: "#fff", $type: "color" } } },
      rose: { colorScheme: "dark", tokens: { "--vr-bg": { $value: "#111", $type: "color" } } },
    },
    sizes: {
      "14": { tokens: { "--vr-fs": { $value: "14px", $type: "dimension" } } },
      "13": { tokens: { "--vr-fs": { $value: "13px", $type: "dimension" } } },
    },
  };
}

function tmpJson(doc: unknown): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-tokens-"));
  const p = path.join(dir, "tokens.json");
  fs.writeFileSync(p, JSON.stringify(doc, null, 2));
  return p;
}

function run(args: string[]): { status: number | null; out: string } {
  const r = spawnSync(process.execPath, [MAIN, ...args], { cwd: projectRoot(), encoding: "utf8" });
  return { status: r.status, out: (r.stdout ?? "") + (r.stderr ?? "") };
}

test("render：base → themeOrder → sizes 数值序；块内按名字字节序", () => {
  const doc = load(tmpJson(baseDoc()));
  const css = render(doc);
  const iP = css.indexOf(":root {");
  const iIce = css.indexOf('[data-theme="ice"]');
  const iRose = css.indexOf('[data-theme="rose"]');
  const i13 = css.indexOf('[data-size="13"]');
  const i14 = css.indexOf('[data-size="14"]');
  assert.ok(iP >= 0 && iIce > iP && iRose > iIce, "序必须是 base → themeOrder 逐个");
  assert.ok(i13 > iRose && i14 > i13, "sizes 在 themes 之后，且按数值序（13 前于 14）");
  assert.match(css, /:root\[data-theme="rose"\] \{\n  color-scheme: dark;\n  --vr-bg: #111;\n\}/);
});

test("sortedSizes：数值序（'9' < '14'，字典序会反）", () => {
  const g = { tokens: { "--vr-a": { $value: "1", $type: "number" } } };
  assert.deepEqual(sortedSizes({ "14": g, "9": g, "100": g }), ["9", "14", "100"]);
});

test("真实真源：load + render ≡ 入库产物（逐字节）", () => {
  const root = projectRoot();
  const doc = load(path.join(root, "demo/tokens.json"));
  const css = fs.readFileSync(path.join(root, "demo/src/tokens.css"), "utf8");
  assert.equal(render(doc), css.replace(/\r\n/g, "\n"));
});

test("verify / diffHint：CRLF 假绿消除；篡改定位到行号", () => {
  const want = "a\nb\nc\n";
  assert.equal(verify("x", want, want.replace(/\n/g, "\r\n")), null);
  const err = verify("x", want, "a\nB\nc\n");
  assert.ok(err !== null);
  assert.match(err.message, /第 2 行起不一致/);
  assert.match(diffHint("a\nb", "a\nb\nc"), /行数不一致：期望 2 行，实际 3 行/);
});

test("J9：完备性断言逐条红（未知字段 / $schema / generatedBy / 前缀 / 空值 / colorScheme / 档位键）", () => {
  const cases: Array<[string, (d: Record<string, unknown>) => void, RegExp]> = [
    ["未知字段", (d) => { d["extra"] = 1; }, /未知字段 "extra"/],
    ["$schema", (d) => { d["$schema"] = "x"; }, /\$schema 必须是/],
    ["generatedBy", (d) => { d["generatedBy"] = "other"; }, /generatedBy 必须是/],
    ["products 首项", (d) => { d["products"] = ["x.css"]; }, /products 首项必须是 demo\/src\/tokens\.css/],
    ["token 前缀", (d) => { (d["base"] as any).tokens["fs"] = { $value: "1", $type: "number" }; }, /不是 --vr- 前缀/],
    ["空 $value", (d) => { (d["base"] as any).tokens["--vr-fs"].$value = "  "; }, /没有 \$value/],
    ["空 $type", (d) => { (d["base"] as any).tokens["--vr-fs"].$type = ""; }, /没有 \$type/],
    ["colorScheme", (d) => { (d["themes"] as any).ice.colorScheme = "dim"; }, /colorScheme 必须是 light\/dark/],
    ["档位键", (d) => { (d["sizes"] as any)["abc"] = { tokens: { "--vr-a": { $value: "1", $type: "number" } } }; }, /档位键必须是整数/],
    ["themeOrder 重复", (d) => { d["themeOrder"] = ["ice", "ice", "rose"]; }, /themeOrder 重复：ice/],
    ["themeOrder 漏列", (d) => { d["themeOrder"] = ["ice"]; }, /themeOrder 只列了 1 个/],
    ["themeOrder 指向缺失主题", (d) => { d["themeOrder"] = ["ice", "nope"]; }, /列了 "nope" 但 themes 里没有/],
  ];
  for (const [name, mutate, re] of cases) {
    const d = baseDoc();
    mutate(d);
    const r = run(["-src", tmpJson(d), "-check"]);
    assert.equal(r.status, 1, `${name}: ${r.out}`);
    assert.match(r.out, re, name);
  }
});

test("确定性：同输入两次生成字节一致；-check 对生成结果绿", () => {
  const src = tmpJson(baseDoc());
  const out = path.join(path.dirname(src), "out.css");
  const a = run(["-src", src, "-out", out]);
  assert.equal(a.status, 0, a.out);
  const first = fs.readFileSync(out);
  const b = run(["-src", src, "-out", out]);
  assert.equal(b.status, 0, b.out);
  assert.deepEqual(fs.readFileSync(out), first);

  const chk = run(["-src", src, "-out", out, "-check"]);
  assert.equal(chk.status, 0, chk.out);
  // 篡改产物 → -check 必红，且 -check 无副作用（内容保持不变）
  fs.writeFileSync(out, Buffer.concat([first, Buffer.from("/* tampered */\n")]));
  const bad = run(["-src", src, "-out", out, "-check"]);
  assert.equal(bad.status, 1);
  assert.match(bad.out, /产物漂移/);
  assert.ok(fs.readFileSync(out).toString().includes("tampered"), "-check 不得写盘");
});

test("真实仓库：-check 绿 + -selftest 绿；未知参数 exit 2", () => {
  const ok = run(["-check"]);
  assert.equal(ok.status, 0, ok.out);
  const self = run(["-selftest"]);
  assert.equal(self.status, 0, self.out);
  assert.match(self.out, /篡改 --vr-fs → verify 判红且定位可见/);
  const bad = run(["--nope"]);
  assert.equal(bad.status, 2);
});
