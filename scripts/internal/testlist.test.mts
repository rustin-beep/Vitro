// testlist.test.mts —— 「.test.mts 集合 ⊆ npm test 清单」机判（#292 审阅 P3 处方）。
//
// 为什么需要它：`scripts/package.json` 的 test 是**手写清单**，漏登记的文件既不进
// `npm test` 也不进 CI（本批实测 `diff_gate/targets/lexer.test.mts` 就是漏的）。
// 这类漏法静默——测试文件存在、lint 清单有它、跑起来却是零用例。
//
// 判据双向：① 磁盘上的每个 `*.test.mts` 都必须在 test 清单里（防漏登记）；
// ② 清单里每条都必须在磁盘上存在（防删文件后留死条目）。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { projectRoot } from "./capi.mts";

const SCRIPTS = path.join(projectRoot(), "scripts");
const SKIP_DIRS = new Set(["_build", ".mooncakes", "node_modules", "testdata"]);

/** 磁盘上全部 *.test.mts（scripts/ 相对路径，正斜杠）。 */
export function discoverTestFiles(root = SCRIPTS): string[] {
  const out: string[] = [];
  const walk = (dir: string): void => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      if (e.isDirectory()) {
        if (SKIP_DIRS.has(e.name)) continue;
        walk(path.join(dir, e.name));
        continue;
      }
      if (e.name.endsWith(".test.mts")) out.push(path.relative(root, path.join(dir, e.name)).split(path.sep).join("/"));
    }
  };
  walk(root);
  return out.sort();
}

/** package.json `scripts.test` 里登记的测试文件。 */
export function listedTestFiles(root = SCRIPTS): string[] {
  const pkg = JSON.parse(fs.readFileSync(path.join(root, "package.json"), "utf8")) as {
    scripts?: Record<string, string>;
  };
  const cmd = pkg.scripts?.["test"] ?? "";
  return cmd
    .split(/\s+/)
    .filter((t) => t.endsWith(".test.mts"))
    .sort();
}

test("test 清单与磁盘一致（双向，防漏登记/防死条目）", () => {
  const found = discoverTestFiles();
  const listed = listedTestFiles();
  const missing = found.filter((f) => !listed.includes(f));
  const stale = listed.filter((f) => !found.includes(f));
  assert.deepEqual(missing, [], `以下测试文件未登记进 npm test（不会在 CI 跑）：${missing.join(", ")}`);
  assert.deepEqual(stale, [], `test 清单里的条目在磁盘上不存在：${stale.join(", ")}`);
});

test("清单条目按包内相对路径书写（不带 scripts/ 前缀）", () => {
  for (const t of listedTestFiles()) {
    assert.ok(!t.startsWith("scripts/"), `清单条目应是包内相对路径：${t}`);
    assert.ok(!t.startsWith("./"), `清单条目不应带 ./ 前缀：${t}`);
  }
});
