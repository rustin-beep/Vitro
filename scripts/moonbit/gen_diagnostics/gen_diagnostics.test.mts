// gen_diagnostics.test.mts —— 转义 / 四产物渲染形态（anchor 归一、strength 浮点
// 口径、嵌套 step）/ 真实仓库 -check。
import { test } from "node:test";
import assert from "node:assert/strict";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { escapeMbt, renderConcepts, renderFixPayloads, renderPaths, renderPatterns } from "./main.mts";
import { projectRoot } from "../../internal/capi.mts";

const FIX = {
  code: 1001,
  suggestion: "补分号",
  fix_kind: 2,
  anchor: "LineEnd",
  text: "x = 1;",
};
const NODE = {
  id: "VarDecl",
  domain: "compile",
  title: "变量声明",
  description: "d",
  difficulty: 2,
  related_card_ids: ["C1", "C2"],
};
const EDGE = { from: "A", to: "B", relation: "prereq", strength: 0.85 };
const MAP = { code: 1001, concepts: ["VarDecl"] };

test("escapeMbt：反斜杠 / 引号 / 换行 / 制表 / CR", () => {
  assert.equal(escapeMbt("a\\b"), "a\\\\b");
  assert.equal(escapeMbt('a"b'), 'a\\"b');
  assert.equal(escapeMbt("a\nb"), "a\\nb");
  assert.equal(escapeMbt("a\tb"), "a\\tb");
  assert.equal(escapeMbt("a\rb"), "a\\rb");
  assert.equal(escapeMbt("中文 ok"), "中文 ok");
});

test("renderFixPayloads：anchor 只认 LineEnd（其余归一 Manual）+ 动态码 %v 形态", () => {
  const out = renderFixPayloads(
    [FIX, { ...FIX, code: 1002, anchor: "Manual" }, { ...FIX, code: 1003, anchor: "什么鬼" }],
    new Set([3035, 1004]),
    "abcd1234",
  );
  assert.match(out, /sha256\/abcd1234/);
  // 4 空格缩进的 match 臂 + 悬挂 Some(...) 形态
  assert.match(out, /    1001 =>\n      Some\(\n        FixPayload::\{/);
  assert.match(out, /anchor: LineEnd,/);
  assert.match(out, /1002 =>[\s\S]*anchor: Manual,/);
  // 乱值也归一 Manual（禁静默 default 的反面：未知值不崩、按 Manual 落）
  assert.match(out, /1003 =>[\s\S]*anchor: Manual,/);
  // Go %v 对 []int：空格分隔带方括号，且升序（1004 在 3035 前）
  assert.match(out, /动态码 \[1004 3035\] 不入表/);
  assert.match(out, /    _ => None\n  \}\n\}\n$/);
});

test("renderConcepts：strength 走 Go %v 浮点口径（1e6 出 1e+06，非 1000000）", () => {
  const out = renderConcepts(
    [NODE],
    [EDGE, { ...EDGE, strength: 1e6 }, { ...EDGE, strength: 1 }],
    [MAP],
    "hhhh0000",
  );
  assert.match(out, /strength: 0\.85,/);
  // 分歧点锚：JS String(1e6) = "1000000"，Go 'g' 给 "1e+06"
  assert.match(out, /strength: 1e\+06,/);
  assert.match(out, /strength: 1,/);
  assert.match(out, /related_card_ids: \["C1", "C2"\],/);
  assert.match(out, /  m\.set\(1001, \["VarDecl"\]\)\n/);
});

test("renderPatterns / renderPaths：嵌套结构与会空表形态", () => {
  const pat = renderPatterns(
    [
      {
        id: "M01",
        name: "边界混淆",
        description: "d",
        error_codes: [3051, 3069],
        min_occurrences: 3,
        time_window: 10,
      },
    ],
    "p0",
  );
  assert.match(pat, /error_codes: \[3051, 3069\],/);
  assert.match(pat, /min_occurrences: 3,\n      time_window: 10,/);

  const pth = renderPaths(
    [
      {
        id: "M01",
        estimated_time_minutes: 20,
        steps: [
          { step_type: "read", title: "读", detail: "d", target_id: "N1", highlight_lines: [3, 7] },
        ],
      },
    ],
    "q0",
  );
  assert.match(pth, /target_misconception_id: "M01",/);
  assert.match(pth, /target_misconception_name: "",/);
  assert.match(pth, /highlight_lines: \[3, 7\],/);
  // 空 steps：只留空数组与闭合
  const empty = renderPaths([{ id: "M02", estimated_time_minutes: 5, steps: [] }], "q0");
  assert.match(empty, /      steps: \[\n      \],\n/);
});

test("真实仓库：-check 通过（4 件未漂移，与 CI 同门径）", () => {
  const r = spawnSync(process.execPath, [path.join(import.meta.dirname, "main.mts"), "-check"], {
    cwd: projectRoot(),
    encoding: "utf8",
  });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /check OK（\.mbt 4 件未漂移）/);
});
