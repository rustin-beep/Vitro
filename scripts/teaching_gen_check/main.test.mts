// teaching_gen_check.test.mts —— 帧重建口径（Latin-1 折叠）+ note 帧 rc 解析。
//
// 端到端（跑 vitro + moon fmt）不在本测试内：scripts-ts job 无 moon 工具链，
// 端到端由本地双跑对拍（Go ↔ .mts 输出逐字一致）与 CI gen slice 的生成闸承担。
import { test } from "node:test";
import fs from "node:fs";
import assert from "node:assert/strict";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { projectRoot } from "../internal/capi.mts";
import { checkTrapKeyCodeAlignment, programRC, rebuildChannel } from "./main.mts";

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

test("P3-1：-write 带 = 值显式拒绝（rc=2，不静默进入 write 模式）", () => {
  const r = spawnSync(process.execPath, [path.join(import.meta.dirname, "main.mts"), "-write=false"], {
    cwd: projectRoot(),
    encoding: "utf8",
  });
  assert.equal(r.status, 2);
  assert.match(r.stderr, /布尔 flag -write 不接受值/);
});

test("#261 审阅 P3-1：键名↔码位不变式——带前缀键正文首行无同码即违例", () => {
  // 绿态：带码键 + 文案首行含同码
  const good = ["## E3086_bounds_array", "", "placeholders: a", "", "[deny] 数组越界 (E3086)：正文", ""].join("\n");
  assert.deepEqual(checkTrapKeyCodeAlignment(good), []);
  // 负例①（审阅实锤形态）：带前缀键 + 文案无码（旧 div_zero_inspect 自违）
  const bad1 = ["## E3088_div_zero_inspect", "", "[inspect] 段落文案无码", ""].join("\n");
  assert.deepEqual(checkTrapKeyCodeAlignment(bad1), [
    "键 E3088_div_zero_inspect 带前缀 E3088，但正文首行无 (E3088)——改键名（段落键去前缀）或文案补码",
  ]);
  // 负例②：码位错配（键 E3083、文案印 E3060）
  const bad2 = ["## E3083_null_deref", "", "访问 (E3060) 区域", ""].join("\n");
  assert.equal(checkTrapKeyCodeAlignment(bad2).length, 1);
  // 段落键（无 E 前缀）不校验
  const sectionKey = ["## div_zero_inspect", "", "[inspect] 无码段落", ""].join("\n");
  assert.deepEqual(checkTrapKeyCodeAlignment(sectionKey), []);
  // 真源绿态
  const src = fs.readFileSync(
    path.join(projectRoot(), "moonbit", "teaching", "content", "trap_messages.md"),
    "utf8",
  );
  assert.deepEqual(checkTrapKeyCodeAlignment(src), []);
});
