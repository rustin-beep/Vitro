// prove_bucket J9 五形态（PR #509 审阅 P3-3：闸的判据先证会红再采信——
// 与审阅人手工五路对照：全 no-prover→0 / 混合→1 / 纯 goal 红→1 /
// failures 空→1 / 文件缺→1）
import { test } from "node:test";
import assert from "node:assert/strict";
import { isInfraOnly, main } from "./main.mts";

test("isInfraOnly：failures 全 no-prover → true（infra 红，钩子不阻断）", () => {
  const report = {
    failures: [
      { result: "Failure\n(no prover available)" },
      { result: "Failure\n(no prover available)" },
    ],
  };
  assert.equal(isInfraOnly(report), true);
});

test("isInfraOnly：混合形态（no-prover + 真 goal 红）→ false（有真红必须拦）", () => {
  const report = {
    failures: [
      { result: "Failure\n(no prover available)" },
      { result: "Failure\n(postcondition 未证)" },
    ],
  };
  assert.equal(isInfraOnly(report), false);
});

test("isInfraOnly：纯 goal 红 → false", () => {
  const report = { failures: [{ result: "Failure\n(postcondition 未证)" }] };
  assert.equal(isInfraOnly(report), false);
});

test("isInfraOnly：failures 空 → false（全绿态不进 infra 通道——fail loud）", () => {
  assert.equal(isInfraOnly({ failures: [] }), false);
  assert.equal(isInfraOnly({}), false);
});

test("main：文件缺/坏 JSON → 1（fail loud 不静默放行）", () => {
  assert.equal(main([]), 1, "缺参数");
  assert.equal(main(["./no-such-proof.json"]), 1, "文件不存在");
});
