// freshness.mts —— MoonBit 产物新鲜度门禁单源（#273 存量 Go 重写批）。
//
// 语义（与 Go 版一致）：产物缺失 fail loud exit 1；任一 moonbit 源
// （.mbt/.mod/.pkg，排除 *_test.mbt / *_wbtest.mbt，跳过 _build/.mooncakes）
// 新于产物 → 跑规范化构建复核（MOON_CC=clang），失败 exit 1；复核后产物仍缺
// → exit 1。mtime 只作触发、内容 hash 由 moon 增量判定把关（防 touch/换行归一
// 假阳性）。
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { projectRoot } from "./capi.mts";

function die(msg: string): never {
  process.stderr.write(msg + "\n");
  process.exit(1);
}

export const ENSURE_FRESH_FAIL_MARKS = [
  "不存在——先跑",
  "构建失败——修好构建前不给判定",
  "仍缺失",
  "后置优化失败——修好构建链前不给判定",
] as const;

// 构建后置钩子端口（PR #518 追加批：vm_diff wasm 臂硬门禁前置）——产物链含
// 构建后覆盖步骤（wasmopt 后置优化等）的消费方必须传 postBuild：自动重建
// 只跑 moon build 会以裸产物覆盖优化产物（gateway/wasm 链实锤），后置链
// 与构建同批执行才保链完整。moonbitRoot/rebuildRunner 为测试注入端口
// （hermetic——同 findStaleSource 的 moonbitRoot 先例），生产调用省略。
export interface EnsureFreshOpts {
  postBuild?: (artifact: string) => boolean;
  moonbitRoot?: string;
  rebuildRunner?: (buildArgs: string[]) => boolean;
}

// #483/PR #487 审阅 P3-3·P3-4：「环境前置未就绪」die 的判别标记单源——
// die 文案以常量引用拼装，下游检测器（facts artifactMissingNote——数组遍历
// 匹配，第四条自动认得）与测试只引此处（防手写字面量脱钩 fail-open）。
export function ensureFresh(
  prefix: string,
  artifact: string,
  buildArgs: string[],
  opts?: EnsureFreshOpts,
): void {
  try {
    fs.statSync(artifact);
  } catch {
    const postNote =
      opts?.postBuild !== undefined ? " && node scripts/wasmopt/main.mts <产物>（后置链）" : "";
    die(
      `${prefix}: ${artifact} ${ENSURE_FRESH_FAIL_MARKS[0]} cd moonbit && moon ${buildArgs.join(" ")}${postNote}`,
    );
  }
  const stale = findStaleSource(artifact, opts?.moonbitRoot);
  if (stale !== "") {
    process.stderr.write(`${prefix}: ${artifact} 旧于源 ${stale}——跑构建复核（moon 内容 hash 增量）...\n`);
    const runner = opts?.rebuildRunner ?? rebuild;
    if (!runner(buildArgs)) {
      die(`${prefix}: ${ENSURE_FRESH_FAIL_MARKS[1]}（陈旧产物假红/假绿由此封死）`);
    }
    if (opts?.postBuild !== undefined && !opts.postBuild(artifact)) {
      die(`${prefix}: ${ENSURE_FRESH_FAIL_MARKS[3]}（构建成功但后置链失败——裸产物已覆盖优化产物，重跑链或手跑 node scripts/wasmopt/main.mts ${artifact}）`);
    }
    try {
      fs.statSync(artifact);
    } catch {
      die(`${prefix}: 构建成功但 ${artifact} ${ENSURE_FRESH_FAIL_MARKS[2]}（moon 缓存与磁盘不一致）——删对应 _build 目标目录后重建`);
    }
  }
}

function rebuild(buildArgs: string[]): boolean {
  const r = spawnSync("moon", buildArgs, {
    cwd: path.join(projectRoot(), "moonbit"),
    env: { ...process.env, MOON_CC: "clang" },
    encoding: "utf8",
  });
  if (r.status !== 0) {
    if (r.stdout) process.stderr.write(r.stdout);
    if (r.stderr) process.stderr.write(r.stderr);
    return false;
  }
  return true;
}

// findStaleSource 返回任一比产物新的 moonbit 源（字典序首个）；全新鲜返回空串。
// moonbitRoot 参数仅供测试注入；默认仓库 moonbit/。
export function findStaleSource(artifact: string, moonbitRoot?: string): string {
  let artMtime: number;
  try {
    artMtime = fs.statSync(artifact).mtimeMs;
  } catch {
    return artifact;
  }
  const root = moonbitRoot ?? path.join(projectRoot(), "moonbit");
  let stale = "";
  const walk = (dir: string): void => {
    let entries: fs.Dirent[];
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    entries.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
    for (const e of entries) {
      const p = path.join(dir, e.name);
      if (e.isDirectory()) {
        if (e.name === "_build" || e.name === ".mooncakes") continue;
        walk(p);
        continue;
      }
      if (e.name.endsWith("_test.mbt") || e.name.endsWith("_wbtest.mbt")) continue;
      if (!(e.name.endsWith(".mbt") || e.name.endsWith(".mod") || e.name.endsWith(".pkg"))) continue;
      try {
        if (fs.statSync(p).mtimeMs > artMtime && stale === "") stale = p;
      } catch {
        // 读不到 mtime 的文件不参与判定（与 WalkDir 出错跳过一致）
      }
    }
  };
  walk(root);
  return stale;
}
