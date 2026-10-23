// precompile.test.mts —— digest 确定性 + 冻结闸正反面 + 真实产物校验。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { artifactPath, computeSourceDigest, sourceFiles, verify } from "./main.mts";
import { projectRoot } from "../internal/capi.mts";

function fixture(): string {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-precompile-"));
  fs.mkdirSync(path.join(root, "scripts/moonbit/libc_src/src"), { recursive: true });
  fs.mkdirSync(path.join(root, "scripts/moonbit/libc_src/vitro"), { recursive: true });
  fs.mkdirSync(path.join(root, "scripts/moonbit/libc_data"), { recursive: true });
  fs.writeFileSync(path.join(root, "scripts/moonbit/libc_src/src/a.c"), "int a;\r\n");
  fs.writeFileSync(path.join(root, "scripts/moonbit/libc_src/src/b.h"), "// h\n");
  fs.writeFileSync(path.join(root, "scripts/moonbit/libc_src/vitro/c.cpp"), "int c;\n");
  fs.writeFileSync(artifactPath(root), JSON.stringify({ source_digest: computeSourceDigest(root) }));
  return root;
}

test("sourceFiles：.c/.cpp 恒在，.h 按开关；排序确定性", () => {
  const root = fixture();
  const noH = sourceFiles(root, false).map((p) => path.basename(p));
  assert.deepEqual(noH, ["a.c", "c.cpp"]);
  assert.deepEqual(sourceFiles(root, true).map((p) => path.basename(p)), ["a.c", "b.h", "c.cpp"]);
});

test("digest：CRLF 归一后与 LF 同值；幂等；改一字节即变", () => {
  const root = fixture();
  const d1 = computeSourceDigest(root);
  assert.equal(computeSourceDigest(root), d1);
  fs.writeFileSync(path.join(root, "scripts/moonbit/libc_src/src/a.c"), "int a;\n");
  assert.equal(computeSourceDigest(root), d1, "CRLF→LF 归一后应同值");
  fs.writeFileSync(path.join(root, "scripts/moonbit/libc_src/src/a.c"), "int b;\n");
  assert.notEqual(computeSourceDigest(root), d1);
});

test("verify：一致 PASS；篡改源/缺 digest/缺产物三态红", () => {
  const root = fixture();
  assert.equal(verify(root).ok, true);
  fs.writeFileSync(path.join(root, "scripts/moonbit/libc_src/src/a.c"), "int changed;\n");
  const r1 = verify(root);
  assert.equal(r1.ok, false);
  assert.match(r1.message, /ERROR: libc 源已变更/);
  fs.writeFileSync(artifactPath(root), "{}");
  assert.match(verify(root).message, /no source_digest/);
  fs.rmSync(artifactPath(root));
  assert.match(verify(root).message, /missing artifact/);
});

test("真实仓库：--check 通过（与 CI 同门径）", () => {
  const r = spawnSync(process.execPath, [path.join(import.meta.dirname, "main.mts"), "--check"], {
    cwd: projectRoot(),
    encoding: "utf8",
  });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /Precompiled artifact integrity OK/);
});
