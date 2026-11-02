// host_shared_guard.test.mts —— 函数解析三态 / 消费方对账纯函数 + 真实仓库判定 + J9 内存红路
import { test } from "node:test";
import assert from "node:assert/strict";
import path from "node:path";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import { loadRules, negLenVerdict, parseHostFns, sharedVerdict } from "./main.mts";
import { projectRoot } from "../../internal/capi.mts";

const MAIN = path.join(import.meta.dirname, "main.mts");

const SAMPLE = `pub fn host_strncpy(
  map : @memory.MemoryMap,
  n : Int32,
) -> HostMemReply {
  if n < 0 {
    return trap_only("负 n", "")
  }
  value_only(1)
}

pub fn host_memcpy(
  n : Int32,
) -> HostMemReply {
  host_memmove(n)
}

pub fn host_memmove(
  n : Int32,
) -> HostMemReply {
  if n < 0 {
    return trap_only("负 n", "")
  }
  value_only(1)
}

pub fn host_memset(
  size : UInt64,
) -> HostMemReply {
  let size_u = if size > 0xFFFFFFFFUL { 0xFFFFFFFFUL } else { size }
  if ptr < 16 && write_len > 0U {
    return trap_only("NULL 区", "")
  }
  value_only(1)
}

pub fn host_strlen(
  s : UInt32,
) -> HostMemReply {
  value_only(1)
}
`;

test("parseHostFns：长度参数识别 / trap 三态 / 转发识别 / memset 软夹不算 trap", () => {
  const fns = parseHostFns(SAMPLE);
  const by = (n: string) => fns.find((f) => f.name === n);
  assert.equal(by("host_strncpy")?.hasTrap, true);
  assert.equal(by("host_memcpy")?.forwardsTo, "host_memmove");
  assert.equal(by("host_memset")?.hasTrap, false, "NULL 区 trap_only + clamp 0xFFFF 是软夹不是负域 trap（F6）");
  assert.equal(by("host_strlen")?.hasLenParam, false, "无长度参数的函数不进面 A");
});

test("negLenVerdict：三态全过 / 缺守卫未登记红 / 僵尸豁免红 / 空集红", () => {
  const fns = parseHostFns(SAMPLE);
  // memset 无守卫不在豁免 → 红
  assert.equal(negLenVerdict(fns, {}).ok, false);
  // 登记 memset → strncpy(trap)+memcpy(转发)+memset(豁免) 全过
  const ok = negLenVerdict(fns, { host_memset: { reason: "F6" } });
  assert.equal(ok.ok, true);
  // 僵尸豁免：给已有守卫的 strncpy 加豁免 → 红
  const zombie = negLenVerdict(fns, { host_memset: { reason: "F6" }, host_strncpy: { reason: "z" } });
  assert.equal(zombie.ok, false);
  assert.ok(zombie.issues.some((s) => s.includes("僵尸豁免") && s.includes("host_strncpy")));
  // 空集
  assert.equal(negLenVerdict([], {}).ok, false);
});

test("sharedVerdict：幽灵消费方红 / def 缺失红 / 空表红", () => {
  const rd = loadRules();
  const rd2 = JSON.parse(JSON.stringify(rd)) as typeof rd;
  rd2.shared_functions["json_escape"]!.consumers.push("ghost/zz.mbt");
  assert.equal(sharedVerdict(rd2).ok, false);
  const rd3 = JSON.parse(JSON.stringify(rd)) as typeof rd;
  rd3.shared_functions["json_escape"]!.def = "ghost/nowhere.mbt";
  assert.equal(sharedVerdict(rd3).ok, false);
  const rd4 = JSON.parse(JSON.stringify(rd)) as typeof rd;
  rd4.shared_functions = {};
  assert.equal(sharedVerdict(rd4).ok, false);
});

test("真实仓库：面 A 三态全覆盖（strncpy/memmove trap + memcpy 转发 + 5 u64 豁免）+ 面 B 账实相符", () => {
  const rd = loadRules();
  const text = fs.readFileSync(path.join(projectRoot(), rd.neg_len_source.file), "utf8");
  const fns = parseHostFns(text);
  const lenFns = fns.filter((f) => f.hasLenParam);
  assert.ok(lenFns.length >= 8, `带长度参数函数 ${lenFns.length}`);
  const a = negLenVerdict(fns, rd.neg_len_exemptions);
  assert.equal(a.ok, true, a.issues.join("; "));
  const b = sharedVerdict(rd);
  assert.equal(b.ok, true, b.issues.join("; "));
});

test("J9 红：真实仓库注入——memmove 去 trap 后必须红（守卫倒退防线）", () => {
  const rd = loadRules();
  const text = fs.readFileSync(path.join(projectRoot(), rd.neg_len_source.file), "utf8");
  const fns = parseHostFns(text).map((f) => ({ ...f }));
  const mm = fns.find((f) => f.name === "host_memmove");
  if (mm === undefined) assert.fail("host_memmove 不在解析集");
  mm.hasTrap = false; // 模拟删守卫
  const r = negLenVerdict(fns, rd.neg_len_exemptions);
  assert.equal(r.ok, false, "memmove 守卫倒退必须红");
});

test("子进程：-check rc=0 / --selftest rc=0 / --discover rc=0 / 未知参数 rc=2", () => {
  const run = (args: string[]): number => {
    const r = spawnSync(process.execPath, [MAIN, ...args], { cwd: projectRoot() });
    return r.status ?? -1;
  };
  assert.equal(run(["-check"]), 0);
  assert.equal(run(["--selftest"]), 0);
  assert.equal(run(["--discover"]), 0);
  assert.equal(run(["--wat"]), 2);
});
