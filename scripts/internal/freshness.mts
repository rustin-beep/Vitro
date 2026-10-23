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

export function ensureFresh(prefix: string, artifact: string, buildArgs: string[]): void {
  try {
    fs.statSync(artifact);
  } catch {
    die(`${prefix}: ${artifact} 不存在——先跑 cd moonbit && moon ${buildArgs.join(" ")}`);
  }
  const stale = findStaleSource(artifact);
  if (stale !== "") {
    process.stderr.write(`${prefix}: ${artifact} 旧于源 ${stale}——跑构建复核（moon 内容 hash 增量）...\n`);
    if (!rebuild(buildArgs)) {
      die(`${prefix}: 构建失败——修好构建前不给判定（陈旧产物假红/假绿由此封死）`);
    }
    try {
      fs.statSync(artifact);
    } catch {
      die(`${prefix}: 构建成功但 ${artifact} 仍缺失（moon 缓存与磁盘不一致）——删对应 _build 目标目录后重建`);
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
