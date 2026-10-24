// parity_gate.test.mts —— 归一化与差异定位（比对逻辑自身）
import { test } from "node:test";
import assert from "node:assert/strict";
import { normalize } from "./main.mts";

test("normalize：剥离 go run 的 exit status 噪音行 + 分隔符归一 + 去尾空行", () => {
  assert.equal(normalize("a\r\nexit status 2\nb\n\n"), "a\nb");
  // 反斜杠用码点构造：字面量经 shell heredoc 写入会被折叠成正斜杠，断言会失真
  const BS = String.fromCharCode(92);
  assert.equal(normalize(`C:${BS}x${BS}y.ts`), "C:/x/y.ts");
  assert.equal(normalize("keep  exit status 1\n"), "keep  exit status 1");
});

test("normalize：空输入与纯噪音行", () => {
  assert.equal(normalize(""), "");
  assert.equal(normalize("exit status 1\n"), "");
});
