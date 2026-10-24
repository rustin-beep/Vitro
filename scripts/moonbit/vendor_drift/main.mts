#!/usr/bin/env node
// vendor_drift：vendored 上游依赖漂移探针（Go→.mts 重写，refs #273；原唯一依赖清除 B 路线批 2026-09-28）。
//
// 用法（仓库根）：
//   node scripts/moonbit/vendor_drift/main.mts                    # 比对上游 main vs 基线
//   node scripts/moonbit/vendor_drift/main.mts --update-baseline  # 拉上游 main 现状重建基线
//   node scripts/moonbit/vendor_drift/main.mts -baseline <file>   # J9：在基线副本上篡改证红
//
// 背景：vitro/engine 的 fs 实现 vendored 自 moonbitlang/x@0.5.5（文件级搬迁 +
// 符号前缀/pub 收窄/内联 utf8 三项机械改造）。上游是活仓库，且实测发生过
// 「内容已漂移而 version 未 bump」——只盯版本号的探针零报警，故主口径走
// **文件内容哈希**。
//
// 双层口径：
//   层 1（主口径）内容哈希：拉上游 main 被跟踪文件的 sha256 与基线比对；
//        不等 / 404（删移=结构变更）→ 漂移。
//   层 2（辅助）版本号：上游 moon.mod 的 version 与基线记录比对；仅报告不判红。
//
// 退出码契约（fail loud，禁静默 default）：
//   0 = 上游与基线一致
//   1 = 漂移——红 = 评估令，非自动同步令
//   2 = 无法判定（网络失败/超时/非 404 异常状态码/基线损坏）
//
// 环境变量 VENDOR_DRIFT_RAW_BASE 可覆盖 raw 域名（默认 raw.githubusercontent.com）。
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../../internal/capi.mts";

export const DEFAULT_RAW_BASE = "https://raw.githubusercontent.com";
export const TRACKED_MODULE = "moonbitlang/x";
export const TRACKED_REF = "main";
export const DEFAULT_BASELINE = "scripts/moonbit/vendor_baseline.json";

export interface FileEntry {
  path: string;
  sha256: string;
  vendored: string;
}

export interface Baseline {
  _generated_by: string;
  as_of: string;
  repo: string;
  ref: string;
  upstream_version: string;
  version_note: string;
  files: FileEntry[];
}

export type FetchStatus = "ok" | "notfound" | "other";

function fatal(msg: string): never {
  process.stderr.write(`vendor_drift: ${msg}\n`);
  process.exit(2);
}

function abs(p: string): string {
  return path.isAbsolute(p) ? p : path.join(projectRoot(), p);
}

/** 漂移（exit 1）与无法判定（exit 2）分开：drift 用专用错误类。 */
export class DriftError extends Error {
  // 不用参数属性（readonly public 形态）：node type stripping 只做擦除，
  // 参数属性需要 codegen —— 会以 triggerUncaughtException 崩在 constructor 行。
  readonly count: number;
  readonly details: string;
  constructor(count: number, details: string) {
    super(`漂移 ${count} 处:\n${details}`);
    this.count = count;
    this.details = details;
  }
}

export function sha256Hex(b: Buffer): string {
  return crypto.createHash("sha256").update(b).digest("hex");
}

/**
 * 拉上游 raw 文件。错误三分类：网络错误（throw → 无法判定）、404
 * （notfound → 漂移）、其余非 200（throw → 无法判定：5xx 抖动不当上游变更）。
 */
export async function fetchUpstream(
  rawBase: string,
  repo: string,
  ref: string,
  p: string,
): Promise<{ body: Buffer; status: FetchStatus }> {
  const url = `${rawBase.replace(/\/+$/, "")}/${repo}/${ref}/${p}`;
  let resp: Response;
  try {
    resp = await fetch(url, { signal: AbortSignal.timeout(30_000) });
  } catch (e) {
    throw new Error(`网络失败（${url}）: ${e instanceof Error ? e.message : String(e)}`);
  }
  if (resp.status === 404) return { body: Buffer.alloc(0), status: "notfound" };
  if (resp.status !== 200) throw new Error(`异常状态码 ${resp.status}（${url}）——非 404 的失败不判漂移`);
  try {
    return { body: Buffer.from(await resp.arrayBuffer()), status: "ok" };
  } catch (e) {
    throw new Error(`读响应体失败（${url}）: ${e instanceof Error ? e.message : String(e)}`);
  }
}

export function loadBaseline(p: string): Baseline {
  let raw: string;
  try {
    raw = fs.readFileSync(abs(p), "utf8");
  } catch (e) {
    throw new Error(
      `基线缺失/不可读 ${p}（首建参照 README 手工落基线后 --update-baseline）: ${e instanceof Error ? e.message : String(e)}`,
    );
  }
  let bl: Baseline;
  try {
    bl = JSON.parse(raw) as Baseline;
  } catch (e) {
    throw new Error(`基线 JSON 损坏 ${p}: ${e instanceof Error ? e.message : String(e)}`);
  }
  if (bl.repo !== TRACKED_MODULE) {
    throw new Error(`基线 repo=${JSON.stringify(bl.repo)} 与探针跟踪对象 ${JSON.stringify(TRACKED_MODULE)} 不符（基线张冠李戴，拒绝判定）`);
  }
  if (bl.ref !== TRACKED_REF) {
    throw new Error(`基线 ref=${JSON.stringify(bl.ref)} 与探针跟踪引用 ${JSON.stringify(TRACKED_REF)} 不符（口径变更须同步改探针常量）`);
  }
  if (!Array.isArray(bl.files) || bl.files.length === 0) throw new Error(`基线 files 为空: ${p}`);
  for (const f of bl.files) {
    if (!f.path || !f.sha256) throw new Error(`基线条目缺 path/sha256: ${JSON.stringify(f)}`);
  }
  return bl;
}

const RE_VERSION = /^version\s*=\s*"([^"]+)"/m;

/** 解析上游 moon.mod 的 version 字段（层 2 辅助口径）。 */
export function parseVersion(mod: string): string {
  const m = RE_VERSION.exec(mod);
  return m === null ? "" : (m[1] ?? "");
}

/** 层 1 内容哈希（判红）+ 层 2 版本号（仅报告）。 */
export async function check(rawBase: string, baselinePath: string): Promise<void> {
  const bl = loadBaseline(baselinePath);
  if (bl.files.length === 0) throw new Error(`基线 files 为空（空集不得绿）: ${baselinePath}`);
  const drifts: string[] = [];
  for (const f of bl.files) {
    const { body, status } = await fetchUpstream(rawBase, bl.repo, bl.ref, f.path);
    if (status === "notfound") {
      drifts.push(`  ${f.path}: 404（上游删移=结构变更）`);
      continue;
    }
    const actual = sha256Hex(body);
    if (actual !== f.sha256) {
      drifts.push(`  ${f.path}: 哈希不等\n    基线: ${f.sha256}\n    实测: ${actual}`);
    } else {
      process.stdout.write(`[绿] ${f.path}（sha256 一致）\n`);
    }
  }
  // 层 2：版本号仅报告（内容变而 version 不 bump 是已实证的漏报形态）
  try {
    const { body, status } = await fetchUpstream(rawBase, bl.repo, bl.ref, "moon.mod");
    if (status === "ok") {
      const v = parseVersion(body.toString("utf8"));
      if (v !== "" && v !== bl.upstream_version) {
        process.stdout.write(`[报告·不判红] 上游版本号 ${bl.upstream_version} → ${v}（内容哈希是主口径，见基线 version_note）\n`);
      }
    }
  } catch {
    // 层 2 失败不影响判定（Go 版同：`if err == nil && st == statusOK`）
  }
  if (drifts.length > 0) throw new DriftError(drifts.length, drifts.join("\n"));
}

function todayLocal(): string {
  const d = new Date();
  const p = (n: number): string => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

/** 拉上游全部被跟踪文件 + moon.mod 版本号，重建基线（人工评估跟进后使用）。 */
export async function updateBaseline(rawBase: string, baselinePath: string): Promise<void> {
  const bl = loadBaseline(baselinePath);
  const today = todayLocal();
  for (const f of bl.files) {
    const { body, status } = await fetchUpstream(rawBase, bl.repo, bl.ref, f.path);
    if (status !== "ok") throw new Error(`拉取 ${f.path} 状态非 200（基线不更新）`);
    f.sha256 = sha256Hex(body);
    process.stdout.write(`[更新] ${f.path} → ${f.sha256}\n`);
  }
  try {
    const { body, status } = await fetchUpstream(rawBase, bl.repo, bl.ref, "moon.mod");
    if (status === "ok") {
      const v = parseVersion(body.toString("utf8"));
      if (v !== "") {
        if (v !== bl.upstream_version) process.stdout.write(`[更新] 上游版本号 ${bl.upstream_version} → ${v}\n`);
        bl.upstream_version = v;
      }
    }
  } catch {
    // 与 Go 同：层 2 失败不阻断基线写回
  }
  bl.as_of = today;
  bl._generated_by = "node scripts/moonbit/vendor_drift/main.mts --update-baseline";
  // 键序 = Go struct 声明序（MarshalIndent 口径）
  const ordered = {
    _generated_by: bl._generated_by,
    as_of: bl.as_of,
    repo: bl.repo,
    ref: bl.ref,
    upstream_version: bl.upstream_version,
    version_note: bl.version_note,
    files: bl.files.map((f) => ({ path: f.path, sha256: f.sha256, vendored: f.vendored })),
  };
  try {
    fs.writeFileSync(abs(baselinePath), JSON.stringify(ordered, null, 2) + "\n", "utf8");
  } catch (e) {
    throw new Error(`基线写回失败 ${baselinePath}: ${e instanceof Error ? e.message : String(e)}`);
  }
  process.stdout.write(`vendor_drift: 基线已更新 → ${baselinePath}（as_of ${today}）\n`);
}

export async function main(argv: string[]): Promise<number> {
  let update = false;
  let baselinePath = DEFAULT_BASELINE;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i] ?? "";
    const eq = a.indexOf("=");
    const flag = eq >= 0 ? a.slice(0, eq) : a;
    if (flag === "-update-baseline" || flag === "--update-baseline") {
      if (eq >= 0) {
        process.stderr.write(`vendor_drift: 布尔 flag ${flag} 不接受值\n`);
        return 2;
      }
      update = true;
    } else if (flag === "-baseline" || flag === "--baseline") {
      const v = eq >= 0 ? a.slice(eq + 1) : argv[++i];
      if (v === undefined) {
        process.stderr.write("vendor_drift: -baseline 缺值\n");
        return 2;
      }
      baselinePath = v;
    } else {
      process.stderr.write(`vendor_drift: 未知参数 ${JSON.stringify(a)}\n`);
      return 2;
    }
  }
  const rawBase = process.env["VENDOR_DRIFT_RAW_BASE"] || DEFAULT_RAW_BASE;
  try {
    if (update) {
      await updateBaseline(rawBase, baselinePath);
      return 0;
    }
    await check(rawBase, baselinePath);
    process.stdout.write("vendor_drift: PASS（上游 moonbitlang/x main 与基线一致）\n");
    return 0;
  } catch (e) {
    if (e instanceof DriftError) {
      process.stderr.write(`vendor_drift: FAIL——上游漂移（${e.count} 处）：\n${e.details}\n`);
      process.stderr.write(
        "处置：读 diff 评估（无关/有利/有害）→ 跟进则手工同步 vendored 文件 + 全量防线 + --update-baseline；见 唯一依赖清除路线.md §3B-4\n",
      );
      return 1;
    }
    fatal(`无法判定: ${e instanceof Error ? e.message : String(e)}`);
  }
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  void main(process.argv.slice(2)).then((rc) => process.exit(rc));
}
