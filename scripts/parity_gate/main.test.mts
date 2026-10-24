// parity_gate.test.mts —— 归一化与差异定位（比对逻辑自身）
import { test } from "node:test";
import assert from "node:assert/strict";
import { formatUnclassified, normalize } from "./main.mts";

test("normalize：剥离 go run 的 exit status 噪音行 + 去尾空行（**不**做分隔符归一）", () => {
  assert.equal(normalize("a\r\nexit status 2\nb\n\n"), "a\nb");
  // #292 审阅 P3-1：全文 `\\`→`/` 是结构性假绿——会掩盖真实差异（CSS 转义 vs 路径）
  const BS = String.fromCharCode(92);
  assert.equal(normalize(`C:${BS}x${BS}y.ts`), `C:${BS}x${BS}y.ts`, "路径分隔符原样保留");
  assert.notEqual(normalize(`${BS}2014`), normalize("/2014"), "转义序列与路径不得被判等价");
  assert.equal(normalize("keep  exit status 1\n"), "keep  exit status 1");
});

test("normalize：空输入与纯噪音行", () => {
  assert.equal(normalize(""), "");
  assert.equal(normalize("exit status 1\n"), "");
});

test("formatUnclassified：输出含目录名，绝不出现 [object Object]（P2-2 回归锚）", () => {
  const out = formatUnclassified(["scripts/foo/foo", "scripts/bar（基名不同：…）"]);
  assert.match(out, /^ {2}- scripts\/foo\/foo$/m);
  assert.match(out, /scripts\/bar/);
  assert.ok(!out.includes("[object Object]"), "对象插值回归即红");
  assert.equal(formatUnclassified([]), "");
});
