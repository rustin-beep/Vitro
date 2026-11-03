// lintlist.test.mts —— 「.mts 集合 ⊆ oxlint 清单」机判（PR #452 审阅 P3-6；testlist.test.mts 的对偶件）。
//
// 为什么需要它：`scripts/package.json` 的 lint 是**手写清单**（oxlint 对 .mts 目录扫描有缺口，
// 故显式列文件——#273 批一的形态）。test 清单早有 testlist.test.mts 双向闸，lint 同名形态
// 却零完备性机判——漏登记的文件不进 `npm run lint` 也不进 CI 的 oxlint 面，静默零规则检查
//（本批 coverage_snapshot/consumer_smoke 四个新文件就是手工加进去的，手就是不可靠的）。
//
// 判据双向：① 磁盘上的每个 `.mts` 都必须在 lint 清单里（防漏登记——含 .test.mts）；
// ② 清单里每条都必须在磁盘上存在（防删文件后留死条目）。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { projectRoot } from "./capi.mts";

const SCRIPTS = path.join(projectRoot(), "scripts");
const SKIP_DIRS = new Set(["_build", ".mooncakes", "node_modules", "testdata", ".stryker-tmp"]);

/** 磁盘上全部 .mts（scripts/ 相对路径，正斜杠；含 .test.mts——lint 清单本就全含）。 */
export function discoverMtsFiles(root = SCRIPTS): string[] {
  const out: string[] = [];
  const walk = (dir: string): void => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      if (e.isDirectory()) {
        if (SKIP_DIRS.has(e.name)) continue;
        walk(path.join(dir, e.name));
        continue;
      }
      if (e.name.endsWith(".mts")) out.push(path.relative(root, path.join(dir, e.name)).split(path.sep).join("/"));
    }
  };
  walk(root);
  return out.sort();
}

/** package.json `scripts.lint` 里登记的 .mts 文件（取 oxlint 参数段）。 */
export function listedLintFiles(root = SCRIPTS): string[] {
  const pkg = JSON.parse(fs.readFileSync(path.join(root, "package.json"), "utf8")) as {
    scripts?: Record<string, string>;
  };
  const cmd = pkg.scripts?.["lint"] ?? "";
  return cmd
    .split(/\s+/)
    .filter((t) => t.endsWith(".mts"))
    .sort();
}

test("lint 清单与磁盘 .mts 全集一致（双向，防漏登记/防死条目）", () => {
  const found = discoverMtsFiles();
  const listed = listedLintFiles();
  assert.ok(found.length > 100, `扫描面异常（${found.length} 个 .mts——SKIP_DIRS 误伤？）`);
  const missing = found.filter((f) => !listed.includes(f));
  const stale = listed.filter((f) => !found.includes(f));
  assert.deepEqual(missing, [], `以下 .mts 未登记进 npm run lint（oxlint 零检查面）：${missing.join(", ")}`);
  assert.deepEqual(stale, [], `lint 清单里的条目在磁盘上不存在：${stale.join(", ")}`);
});

test("清单条目按包内相对路径书写（不带 scripts/ 前缀）", () => {
  for (const t of listedLintFiles()) {
    assert.ok(!t.startsWith("scripts/"), `清单条目应是包内相对路径：${t}`);
    assert.ok(!t.startsWith("./"), `清单条目不应带 ./ 前缀：${t}`);
  }
});

test("J9：从清单删一条 → 双向闸必红（fixture 化证红，不动真实 package.json）", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-lintlist-"));
  try {
    fs.mkdirSync(path.join(dir, "sub"), { recursive: true });
    fs.writeFileSync(path.join(dir, "a.mts"), "export const a = 1;\n");
    fs.writeFileSync(path.join(dir, "sub", "b.mts"), "export const b = 2;\n");
    fs.writeFileSync(path.join(dir, "package.json"), JSON.stringify({ scripts: { lint: "oxlint a.mts sub/b.mts" } }));
    // 双向绿
    assert.deepEqual(discoverMtsFiles(dir), ["a.mts", "sub/b.mts"]);
    assert.deepEqual(listedLintFiles(dir), ["a.mts", "sub/b.mts"]);
    // 漏登记：清单去掉 sub/b.mts → missing 非空
    fs.writeFileSync(path.join(dir, "package.json"), JSON.stringify({ scripts: { lint: "oxlint a.mts" } }));
    const missing = discoverMtsFiles(dir).filter((f) => !listedLintFiles(dir).includes(f));
    assert.deepEqual(missing, ["sub/b.mts"]);
    // 死条目：清单加不存在的 c.mts → stale 非空
    fs.writeFileSync(path.join(dir, "package.json"), JSON.stringify({ scripts: { lint: "oxlint a.mts sub/b.mts c.mts" } }));
    const stale = listedLintFiles(dir).filter((f) => !discoverMtsFiles(dir).includes(f));
    assert.deepEqual(stale, ["c.mts"]);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
