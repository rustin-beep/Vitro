// gen_api_help.test.mts —— dispatch 段提取 / 形状归位 / 双向对账 J9 / 渲染口径 /
// 真实仓库 -check。
import { test } from "node:test";
import assert from "node:assert/strict";
import path from "node:path";
import { spawnSync } from "node:child_process";
import {
  checkShapeSkips,
  extractDispatch,
  extractShapes,
  mbtEscape,
  reconcile,
  render,
  type MethodHelp,
  type ParamErr,
  type Rules,
} from "./main.mts";
import { projectRoot } from "../internal/capi.mts";

function rules(methods: MethodHelp[], count: number, allow: Rules["shape_skip_allow"] = []): Rules {
  return {
    schema: 1,
    expected_method_count: count,
    methods,
    shape_skip_allow: allow,
  };
}

test("真实仓库：dispatch 段非空且方法名为小写点分形态", () => {
  const d = extractDispatch();
  assert.deepEqual(d.errs, []);
  assert.ok(d.methods.length > 0);
  for (const m of d.methods) assert.match(m, /^[a-z_.]+$/);
});

test("真实仓库：serve_param_err 形状面可提取", () => {
  const s = extractShapes();
  assert.deepEqual(s.errs, []);
  assert.ok(s.shapes.size > 0);
});

test("J9：方法计数漂移即红", () => {
  const methods = ["a.b", "c.d"];
  const errs = reconcile(methods, rules([{ method: "a.b", brief: "", example: "" }, { method: "c.d", brief: "", example: "" }], 3), new Map());
  assert.equal(errs.length, 1);
  assert.match(errs[0] ?? "", /方法计数漂移/);
});

test("J9：dispatch 缺简介即红；僵尸简介亦红（双向）", () => {
  const errs = reconcile(
    ["a.b"],
    rules([{ method: "zombie", brief: "b", example: "e" }], 1),
    new Map(),
  );
  assert.ok(errs.some((e) => /缺 rules 简介/.test(e)), errs.join(" / "));
  assert.ok(errs.some((e) => /不在 dispatch/.test(e)), errs.join(" / "));
});

test("J9：形状提取方法不在 dispatch 即红（真相源脱节）", () => {
  const errs = reconcile(
    ["a.b"],
    rules([{ method: "a.b", brief: "", example: "" }], 1),
    new Map([["ghost.method", "x:Int"]]),
  );
  assert.ok(errs.some((e) => /形状提取方法/.test(e)), errs.join(" / "));
});

test("J9：非规范形态未豁免即红；僵尸豁免亦红（双向）", () => {
  const bad: ParamErr[] = [{ message: "配置键非法", expected: "keys:白名单" }];
  const red1 = checkShapeSkips(rules([], 0), bad);
  assert.equal(red1.length, 1);
  assert.match(red1[0] ?? "", /非规范形态未豁免/);

  const red2 = checkShapeSkips(
    rules([], 0, [{ prefix: "zzz", reason: "r" }]),
    [],
  );
  assert.equal(red2.length, 1);
  assert.match(red2[0] ?? "", /僵尸豁免/);

  // 绿路径：前缀命中且被使用 → 双向皆空
  const green = checkShapeSkips(rules([], 0, [{ prefix: "配置键", reason: "顶层" }]), bad);
  assert.deepEqual(green, []);
});

test("render：方法清单按字节序 + %-20s rune 补齐；缺形状走「无必填」分支", () => {
  const out = render(
    ["b.method", "a.method"],
    rules(
      [
        { method: "a.method", brief: "甲", example: "{}" },
        { method: "b.method", brief: "乙", example: "{}" },
      ],
      2,
    ),
    new Map([["a.method", "x:Int"]]),
  );
  assert.match(out, /api 方法清单（2）/);
  // 声明序打散、按字节序输出：a.method 在 b.method 之前
  assert.ok(out.indexOf('"a.method" =>') < out.indexOf('"b.method" =>'));
  // 有形状 → params 原样；无形状 → 缺省文案
  assert.match(out, /params: x:Int/);
  assert.match(out, /params: 无必填（缺省 \{\}）/);
  // %-20s：'a.method' 8 rune → 补 12 空格
  assert.match(out, /  a\.method {13}甲/);
});

test("mbtEscape：反斜杠先于引号、真实换行落 \\n", () => {
  assert.equal(mbtEscape('a"b'), 'a\\"b');
  assert.equal(mbtEscape("a\\b"), "a\\\\b");
  assert.equal(mbtEscape("a\nb"), "a\\nb");
  // 顺序锚：反斜杠先转义 → 引号转义引入的 \ 不被二次转义
  assert.equal(mbtEscape('a\\"b'), 'a\\\\\\"b');
});

test("真实仓库：-check 通过（与 CI 同门径）", () => {
  const r = spawnSync(process.execPath, [path.join(import.meta.dirname, "main.mts"), "-check"], {
    cwd: projectRoot(),
    encoding: "utf8",
  });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /check OK/);
});

test("真实仓库：-selftest 四路证红全过", () => {
  const r = spawnSync(
    process.execPath,
    [path.join(import.meta.dirname, "main.mts"), "-selftest"],
    { cwd: projectRoot(), encoding: "utf8" },
  );
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /selftest 全过/);
  assert.doesNotMatch(r.stdout, /FAIL/);
});
