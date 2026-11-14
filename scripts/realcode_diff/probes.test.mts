// probes 纯逻辑单测（#303 审阅 P3-3）：诊断行计数 / 警告过滤 / gcc 探测序。
import { test } from "node:test";
import assert from "node:assert/strict";
import { GCC_FALLBACK, clangDiagnosticCounts, gccErrorCount, resolveGcc } from "./probes.mts";

test("clangDiagnosticCounts：错误/警告计数、CRT/deprecated 豁免、首错 trim", () => {
  const out = [
    "  a.c:1:1: error: boom",
    "a.c:2:1: warning: normal",
    "a.c:3:1: warning: _CRT_SECURE_NO_WARNINGS",
    "a.c:4:1: warning: deprecated foo",
    "a.c:5:1: error: second",
  ].join("\n");
  assert.deepEqual(clangDiagnosticCounts(out), {
    errs: 2,
    warns: 1,
    first: "a.c:1:1: error: boom",
  });
  assert.deepEqual(clangDiagnosticCounts(""), { errs: 0, warns: 0, first: "" });
});

test("clangDiagnosticCounts：CRLF 行尾不污染首错", () => {
  const out = "a.c:1:1: error: boom\r\nb.c:2:1: warning: w\r\n";
  assert.deepEqual(clangDiagnosticCounts(out), {
    errs: 1,
    warns: 1,
    first: "a.c:1:1: error: boom",
  });
});

test("gccErrorCount：只数 error 行，warning 不计", () => {
  assert.equal(gccErrorCount("a:1: error: x\nb:2: warning: y\na:3: error: z\n"), 2);
  assert.equal(gccErrorCount(""), 0);
});

test("resolveGcc：--gcc 显式优先；显式缺失不回退；PATH 优先于 fallback", () => {
  const exists = (p: string): boolean => p === "explicit.exe" || p === GCC_FALLBACK;
  assert.deepEqual(resolveGcc("explicit.exe", "path.exe", GCC_FALLBACK, exists), {
    gcc: "explicit.exe",
    source: "explicit",
  });
  assert.deepEqual(resolveGcc("missing.exe", "path.exe", GCC_FALLBACK, exists), {
    gcc: "",
    source: "none",
    missingExplicit: "missing.exe",
  });
  assert.deepEqual(resolveGcc("", "path.exe", GCC_FALLBACK, exists), {
    gcc: "path.exe",
    source: "path",
  });
  assert.deepEqual(resolveGcc("", null, GCC_FALLBACK, exists), {
    gcc: GCC_FALLBACK,
    source: "fallback",
  });
  assert.deepEqual(resolveGcc("", null, GCC_FALLBACK, () => false), { gcc: "", source: "none" });
});

// PR #513 审阅 P2-1 真跑锚：serveBatchKeys 首参是**活的子进程 cwd**（Go 版为弃用
// 死参，.mts 迁移激活语义后 main.mts:705 曾沿传 repoAbs 致剥壳批全灭——修复零锚
// 是复发温床）。锚定语义：cwd 无 moon module 时必须 fail loud reject，禁止任何
// 「静默换目录成功」的退化形态回潮。
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { serveBatchKeys } from "./probes.mts";

test("serveBatchKeys：cwd 无 module（空目录）→ reject（首参=cwd 语义锚）", async () => {
  const emptyDir = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-servecwd-"));
  const tmpC = path.join(emptyDir, "a.c");
  fs.writeFileSync(tmpC, "int main(void){return 0;}\n");
  await assert.rejects(
    serveBatchKeys(emptyDir, ["k"], [tmpC]),
    (e: unknown) => {
      const msg = e instanceof Error ? e.message : String(e);
      if (!msg.includes("serve 响应不足")) {
        console.error("reject 形态漂移（判据须随实况校准）:", msg);
      }
      return true; // 只要 fail-loud reject 即锚成立；文案形态打印供人工核对
    },
  );
});
