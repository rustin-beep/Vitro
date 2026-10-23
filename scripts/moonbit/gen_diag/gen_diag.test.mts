// gen_diag.test.mts —— MoonBit 转义 / 80 列装行 / 两产物渲染形态 / 真实仓库 -check。
import { test } from "node:test";
import assert from "node:assert/strict";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { escapeMbt, renderCatalog, renderErrorCode, wrapInts } from "./main.mts";
import { projectRoot } from "../../internal/capi.mts";

test("escapeMbt：反斜杠 / 引号 / 换行 / 制表 / CR", () => {
  assert.equal(escapeMbt("a\\b"), "a\\\\b");
  assert.equal(escapeMbt('a"b'), 'a\\"b');
  assert.equal(escapeMbt("a\nb"), "a\\nb");
  assert.equal(escapeMbt("a\tb"), "a\\tb");
  assert.equal(escapeMbt("a\rb"), "a\\rb");
  assert.equal(escapeMbt("中文 ok"), "中文 ok");
});

test("wrapInts：4 空格前缀 + 84 列贪心（元字节口径，全 ASCII）", () => {
  assert.equal(wrapInts([1, 2, 3]), "    1, 2, 3,");
  assert.equal(wrapInts([]), "");
  // 装满到超 84 才折行：每元素 "NNNN," 5 字节 + 空格
  const many = Array.from({ length: 40 }, (_, i) => 1000 + i);
  const out = wrapInts(many);
  const lines = out.split("\n");
  assert.ok(lines.length > 1, "40 个四位数必须折行");
  for (const l of lines) assert.ok(l.length <= 84, `行超 84：${l.length}`);
  // 还原性：拆开再拼回去应得原序列
  const back = lines.join(" ").replace(/,/g, "").trim().split(/\s+/).map(Number);
  assert.deepEqual(back, many);
});

test("renderErrorCode：七段骨架 + severity/lang/prefix 映射 + 长名折行", () => {
  const arms = [
    { name: "E1001_UnknownChar", code: 1001 },
    { name: "W3053_FormatMismatch", code: 3053 },
    { name: "H3057_SomeHint", code: 3057 },
    { name: "E4001_CppOnly", code: 4001 },
    { name: "E1002_AVeryLongVariantNameThatExceedsEightyColumnsWhenRendered", code: 1002 },
  ];
  const w = [3053];
  const h = [3057];
  const entries = [{ code: 1001, icon: "i", title: "t", explanation: "e", common_causes: [] }];
  const out = renderErrorCode(arms, w, h, entries, "abcd1234");

  // 标题段与源指纹
  assert.match(out, /sha256\/abcd1234/);
  assert.match(out, /pub\(all\) enum ErrorCode \{/);
  // 编号升序（arms 乱序输入也按 code 排）：1001 在 3053 前
  assert.ok(out.indexOf("  E1001_UnknownChar\n") < out.indexOf("  W3053_FormatMismatch\n"));
  // severity：W→Warning / H→Hint / 其余 Error
  assert.match(out, /W3053_FormatMismatch => Warning/);
  assert.match(out, /H3057_SomeHint => Hint/);
  assert.match(out, /E1001_UnknownChar => Error/);
  // lang：4xxx→Cpp
  assert.match(out, /E4001_CppOnly => Cpp/);
  assert.match(out, /E1001_UnknownChar => C\n/);
  // display_code：W/H/E 前缀 + 码值
  assert.match(out, /W3053_FormatMismatch => "W3053"/);
  assert.match(out, /E1001_UnknownChar => "E1001"/);
  // 长名走折行形态（>80 列把值挪下一行）
  assert.match(
    out,
    /    E1002_AVeryLongVariantNameThatExceedsEightyColumnsWhenRendered =>\n      "E1002_AVeryLongVariantNameThatExceedsEightyColumnsWhenRendered"/,
  );
  // 卡片码清单：有卡片的进 catalog_codes，其余进 codes_without_catalog
  assert.match(out, /pub fn catalog_codes\(\) -> Array\[Int\] \{\n  \[\n    1001,/);
  assert.match(out, /pub fn codes_without_catalog\(\) -> Array\[Int\] \{\n  \[\n    1002, 3053, 3057, 4001,/);
});

test("renderCatalog：causes 爆开按 UTF-8 字节判（中文 3 字节，非 UTF-16 长度）", () => {
  // 30 个汉字：causesLine 字符数 39（≤84）但字节数 99（>84）→ 必须爆开。
  // 若实现误用 .length，就不会爆开——本条即该口径的回归锚。
  const cjk = "中".repeat(30);
  const out = renderCatalog(
    [{ code: 1001, icon: "🔍", title: "标题", explanation: "解释", common_causes: [cjk] }],
    "aaaa1111",
    "bbbb2222",
  );
  assert.match(out, /    \[\n      "中{30}",\n    \],/);
  assert.match(out, /sha256\/aaaa1111/);
  assert.match(out, /sha256\/bbbb2222/);

  // 短 causes：不爆开，单行形态
  const short = renderCatalog(
    [{ code: 1001, icon: "i", title: "t", explanation: "e", common_causes: ["短因"] }],
    "aaaa1111",
    "bbbb2222",
  );
  assert.match(short, /    \["短因"\],\n/);
});

test("renderCatalog：码升序输出（输入乱序）", () => {
  const out = renderCatalog(
    [
      { code: 3002, icon: "i", title: "b", explanation: "e", common_causes: [] },
      { code: 1001, icon: "i", title: "a", explanation: "e", common_causes: [] },
    ],
    "a",
    "b",
  );
  assert.ok(out.indexOf("  1001: @diag.CatalogEntry::of(") < out.indexOf("  3002: @diag.CatalogEntry::of("));
});

test("真实仓库：-check 通过（与 CI 同门径，2 文件未漂移）", () => {
  const r = spawnSync(process.execPath, [path.join(import.meta.dirname, "main.mts"), "-check"], {
    cwd: projectRoot(),
    encoding: "utf8",
  });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /check OK（产物与 JSON 真源一致，2 文件未漂移）/);
});
