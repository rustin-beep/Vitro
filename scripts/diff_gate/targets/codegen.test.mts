// codegen.test.mts —— dump 段原始字节提取（u64 保真）、判定记录 flatten、
// corpora digest 序列化、真实仓库对拍。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { parseMoonDoc, rawField, loadCg, serializeCg } from "./codegen.mts";
import { projectRoot } from "../../internal/capi.mts";
import type { Fail } from "../../internal/diffgate.mts";

const boom: Fail = (msg: string): never => {
  throw new Error(msg);
};

test("rawField / scanValue：u64 位模式保真（JSON.parse 会丢的那个值）", () => {
  // 4609434218613702656 > 2^53 —— JSON.parse 往返后末位漂移（Go 端实测量）
  const big = "4609434218613702656";
  const text = `{"ok":true,"stage":"","slot_strategy":1,"verify":{"ok":true},"dump":{"globals_init_64":[1,${big}],"code":[]}}`;
  const raw = rawField(text, "dump");
  assert.ok(raw !== undefined);
  assert.ok(raw.includes(big), `提取结果必须保留原始数字 token，实际: ${raw}`);

  // JSON.parse 对照：同一文本经 parse 后大整数末位已漂移
  const parsed = JSON.parse(text) as { dump: { globals_init_64: number[] } };
  assert.notEqual(String(parsed.dump.globals_init_64[1]), big, "本机 JSON.parse 应当失真（否则本锚失效）");

  // 键出现在字符串内容里时不得误判为对象键
  assert.equal(rawField('{"note":"含 \\"dump\\": 字样"}', "dump"), undefined);
  // 嵌套对象配平 + 字符串内括号不干扰
  const nested = rawField('{"a":{"b":"}{"},"dump":{"x":"}"}}', "dump");
  assert.equal(nested, '{"x":"}"}');
  // 数字值
  assert.equal(rawField('{"slot_strategy":1,"dump":0}', "dump"), "0");
});

test("parseMoonDoc：ok/stage/slot/verifyOK 四字段 + dump 原始子串", () => {
  const big = "18446744073709551615";
  const raw = Buffer.from(
    `{"ok":true,"stage":"","slot_strategy":1,"verify":{"ok":true,"violations":[]},"dump":{"globals_init_64":[1,${big}]}}`,
  );
  const d = parseMoonDoc(raw);
  assert.equal(d.ok, true);
  assert.equal(d.slot, 1);
  assert.equal(d.verifyOK, true);
  assert.ok(d.dump.includes(big));

  const failDoc = parseMoonDoc(Buffer.from('{"ok":false,"stage":"parse","parse_errors":[]}'));
  assert.equal(failDoc.ok, false);
  assert.equal(failDoc.stage, "parse");
  assert.equal(failDoc.slot, -1, "字段缺失 = -1");
  assert.equal(failDoc.verifyOK, null, "失败例无 verify 面");

  const noVerify = parseMoonDoc(Buffer.from('{"ok":true,"stage":"","dump":{}}'));
  assert.equal(noVerify.verifyOK, null, "ok 例缺 verify = 协议缺位（调用方判红）");
});

test("digest 序列化：顶层 struct 序（version→note→corpora）+ 判定记录两种形态", () => {
  const raw = serializeCg({
    version: 1,
    note: "n",
    corpora: {
      beta: { sources: { "b.c": "bbbbbbbb" }, cases: { "b.c": { fail: true, fail_stage: "lex" } } },
      alpha: { sources: { "a.c": "aaaaaaaa" }, cases: { "a.c": { result_sha: "1111" } } },
    },
  });
  assert.match(raw, /^\{\n {2}"version": 1,\n {2}"note": "n",\n {2}"corpora": \{/);
  assert.ok(raw.indexOf('"alpha"') < raw.indexOf('"beta"'), "corpora 是 map → 键字节序");
  // 节内 struct 字段序：sources 在 cases 前；case 条目 result_sha 单字段
  assert.ok(raw.indexOf('"sources"') < raw.indexOf('"cases"'));
  assert.match(raw, /"a\.c": \{\n {10}"result_sha": "1111"\n {8}\}/);
  assert.match(raw, /"fail": true,\n {10}"fail_stage": "lex"/);
  assert.ok(raw.endsWith("}\n"));
});

test("真实仓库：serializeCg 与入库 golden_digest.json 逐字节一致", () => {
  const rel = "scripts/codegen_diff/golden_digest.json";
  const doc = loadCg(projectRoot(), boom);
  const original = fs.readFileSync(path.join(projectRoot(), rel), "utf8");
  assert.equal(serializeCg(doc), original);
});

test("真实仓库：codegen 在 gap 上 PASS 且 slot_strategy 对账通过", () => {
  const r = spawnSync(
    process.execPath,
    [path.join(projectRoot(), "scripts/diff_gate/main.mts"), "codegen", "corpus/gap"],
    { cwd: projectRoot(), encoding: "utf8", timeout: 600_000 },
  );
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /slot_strategy=1×\d+（期望 1/);
  assert.match(r.stdout, /codegen_diff\[golden\]: PASS——20 个 case hash 与冻结基线一致（语料 gap）/);
});

test("真实仓库：codegen 在 baseline 上 PASS 且 fork 例单列", () => {
  const r = spawnSync(
    process.execPath,
    [path.join(projectRoot(), "scripts/diff_gate/main.mts"), "codegen", "corpus/baseline"],
    { cwd: projectRoot(), encoding: "utf8", timeout: 600_000 },
  );
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /FORK\(known-golden-skip\) function_pointer_return_ptr\.c/);
  assert.match(r.stdout, /PASS——487 个 case hash 与冻结基线一致（语料 baseline，1 例 known-fork 跳过）/);
});
