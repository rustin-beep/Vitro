// teaching_gen_check.test.mts —— 帧重建口径（Latin-1 折叠）+ note 帧 rc 解析。
//
// 端到端（跑 vitro + moon fmt）不在本测试内：scripts-ts job 无 moon 工具链，
// 端到端由本地双跑对拍（Go ↔ .mts 输出逐字一致）与 CI gen slice 的生成闸承担。
import { test } from "node:test";
import assert from "node:assert/strict";
import { programRC, rebuildChannel } from "./main.mts";

/** 造一帧 --json 输出行（与 CLI_PROTOCOL_V1 的 stdout/stderr 帧同形）。 */
function frame(type: string, delta: string): string {
  return JSON.stringify({ type, frame: { result: { delta } } });
}

test("programRC：note 帧取返回值；缺帧回落 0（与 Go 版同口径）", () => {
  assert.equal(programRC("程序运行完成，返回值：3\n"), 3);
  assert.equal(programRC("程序运行完成，返回值：0\n"), 0);
  assert.equal(programRC("no note frame here\n"), 0);
});

test("rebuildChannel：Latin-1 折叠字节逐码点折回", () => {
  // 0xE4 = 'ä' 的 Latin-1 折叠形态（1 字符 = 1 字节），折回后必须是单字节 0xE4
  const raw = [frame("stdout", "ä"), frame("stdout", "\u00c8\u00ff")].join("\n");
  const out = rebuildChannel(raw, "stdout");
  assert.deepEqual([...out], [0xe4, 0xc8, 0xff]);
});

test("rebuildChannel：>0xFF 码点按 UTF-8 编码（中文不被折成字节）", () => {
  const raw = frame("stdout", "中a");
  const out = rebuildChannel(raw, "stdout");
  assert.deepEqual([...out], [...Buffer.from("中a", "utf8")]);
});

test("rebuildChannel：按帧类型分流，忽略非 JSON 行与无 delta 行", () => {
  const raw = [
    "not json at all",
    frame("stderr", "\u00e4"),
    frame("stdout", "\u00e5"),
    JSON.stringify({ type: "stdout", frame: { result: {} } }),
  ].join("\n");
  assert.deepEqual([...rebuildChannel(raw, "stdout")], [0xe5]);
  assert.deepEqual([...rebuildChannel(raw, "stderr")], [0xe4]);
});

test("rebuildChannel：delta 为空 / 全无匹配 → 空 Buffer", () => {
  assert.equal(rebuildChannel("", "stdout").length, 0);
  assert.equal(rebuildChannel(frame("stdout", ""), "stdout").length, 0);
});
