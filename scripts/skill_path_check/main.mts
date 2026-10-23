#!/usr/bin/env node
// skill_path_check — .agents/skills/** 手册中「仓库内路径引用」的存在性闸
// （Go→.mts 重写，refs #273；原 2026-10-07 审阅处置批）。
//
// 背景：skill 手册改写引用面时曾按脑测填迁移目标（corpus/cases/ 中间层、
// -o 参数、"无门禁"断言），产出形状合理但不存在的指令——缺陷形态 03 E11/E13
// 同族面。本闸机判其中可机判的一面：手册内出现的仓库内路径引用（围栏代码块
// 整行 + 正文行内反引号 span）必须真实存在。
//
// 覆盖面（诚实声明，勿夸大）：
//   - 只校验「首段 = 仓库根一级目录/文件」的引用；相对包路径（cmd/run、
//     gateway/wasm）、skill 内相对链接（references/...）、纯裸文件名不在面内。
//   - 变量/占位符段（$d、<suite>、{...}）之前的最长静态前缀必须存在；
//     `file:line` 的 `:line` 截断。
//   - rules.json 外置：whitelist_prefixes（gitignore 域 / 构建产物 / 退役
//     历史域）、dead_paths、skip_files（只追加不改写的历史日志）、min_hits
//     （引用总数下限——低于即红，抽取面塌缩守卫）。
//
// fail loud：skills 目录缺失 / 0 个 md / 规则文件缺失 / 路径缺失 / 命中数
// 低于下限 ⇒ exit 1。
//
// 用法：node scripts/skill_path_check/main.mts [-root <仓库根>] [-selftest]
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../internal/capi.mts";

export interface Rules {
  whitelist_prefixes: string[];
  dead_paths: string[];
  skip_files: string[];
  min_hits: number;
}

export interface Hit {
  file: string;
  line: number;
  path: string;
}

const FENCE_RE = /^\s*```/;
const INLINE_RE = /`([^`\n]+)`/g;
const STRIKE_RE = /~~[^~]*~~/g;
/** Go FieldsFunc 的 tokenCut 字符集（含全角标点）。 */
const TOKEN_SPLIT = /[ \t|;()"'&,*?（），：、；。「」『』·—…]+/;

/** 进程级上下文（与 Go 版 repoRoot / topCache 同位；selftest 会重置）。 */
let repoRoot = "";
let topCache = new Set<string>();

function fail(msg: string): never {
  process.stderr.write("skill_path_check: " + msg + "\n");
  process.exit(1);
}

/** 路径是否落在豁免前缀内。 */
export function whitelisted(p: string, r: Rules): boolean {
  return r.whitelist_prefixes.some((wl) => p.startsWith(wl));
}

/**
 * 判定单个 token：返回 { pfx, skipped }。
 * 首段必须是仓库根一级条目；其后逐段走静态段，遇 $<>{}: 截断。
 */
export function checkToken(tok: string, top: Set<string>, r: Rules): { pfx: string; skipped: boolean } {
  let t = tok.replace(/^[.,;:]+/, "").replace(/[.,;:]+$/, "");
  if (t.startsWith("./")) t = t.slice(2);
  if (t === "" || t.startsWith("~/") || t.startsWith("/")) return { pfx: "", skipped: true };
  if (whitelisted(t, r)) return { pfx: "", skipped: true };
  const segs = t.split("/");
  const first = segs[0] ?? "";
  if (!top.has(first)) return { pfx: "", skipped: true }; // 裸名或非仓库根前缀
  if (first.startsWith(".")) return { pfx: "", skipped: true }; // 隐藏域
  let pfx = first;
  if (whitelisted(pfx + "/", r)) return { pfx: "", skipped: true };
  for (const seg of segs.slice(1)) {
    if (seg === "") continue;
    if (/[$<>{}:]/.test(seg)) break; // 变量 / 占位符 / glob / file:line
    pfx += "/" + seg;
    if (whitelisted(pfx + "/", r)) return { pfx: "", skipped: true };
  }
  for (const dead of r.dead_paths) {
    if (pfx === dead) return { pfx: "", skipped: true }; // 退役/反例语境合法引用
  }
  return { pfx, skipped: false };
}

/**
 * 扫单个 md：围栏代码块整行 + 正文行内反引号 span。
 * 返回：缺失清单、仓库路径引用总数（含存在的——min_hits 下限守卫的计数面）、跳过数。
 */
export function scanFile(p: string, r: Rules): { hits: Hit[]; repoHits: number; skips: number } {
  const text = fs.readFileSync(p, "utf8");
  const lines = text.split("\n");
  const hits: Hit[] = [];
  let skips = 0;
  let repoHits = 0;
  let inFence = false;
  const rel = path.relative(repoRoot, p).split(path.sep).join("/");
  lines.forEach((raw, i) => {
    if (FENCE_RE.test(raw)) {
      inFence = !inFence;
      return;
    }
    const pieces: string[] = [];
    if (inFence) pieces.push(raw);
    else {
      const clean = raw.replace(STRIKE_RE, ""); // 删除线 = 退役历史，整体剥除
      for (const m of clean.matchAll(INLINE_RE)) pieces.push(m[1] ?? "");
    }
    for (const piece of pieces) {
      for (const tok of piece.split(TOKEN_SPLIT)) {
        if (tok === "") continue;
        const { pfx, skipped } = checkToken(tok, topCache, r);
        if (skipped) {
          skips++;
          continue;
        }
        repoHits++; // 走到 stat 的都是「仓库路径引用」，无论存在与否都计数
        const target = path.join(repoRoot, pfx.split("/").join(path.sep));
        let exists = false;
        try {
          fs.statSync(target);
          exists = true;
        } catch {
          exists = false;
        }
        if (exists) continue;
        // 审阅 P1-a②（2026-10-14）：skill 内相对引用按仓库根解析 miss 时，回退
        // 按**引用文件所在目录**再试——仓库根恰有同名一级目录时按根解析是假红。
        try {
          fs.statSync(path.join(path.dirname(p), pfx.split("/").join(path.sep)));
          continue;
        } catch {
          // 相对也 miss → 记缺失
        }
        hits.push({ file: rel, line: i + 1, path: pfx });
      }
    }
  });
  return { hits, repoHits, skips };
}

export function loadRules(root: string): Rules {
  const p = path.join(root, "scripts", "skill_path_check", "rules.json");
  let raw: string;
  try {
    raw = fs.readFileSync(p, "utf8");
  } catch (e) {
    fail(`读 rules.json 失败（fail loud，规则不内置）: ${e instanceof Error ? e.message : String(e)}`);
  }
  let r: Rules;
  try {
    r = JSON.parse(raw) as Rules;
  } catch (e) {
    fail(`rules.json 解析失败: ${e instanceof Error ? e.message : String(e)}`);
  }
  return {
    whitelist_prefixes: r.whitelist_prefixes ?? [],
    dead_paths: r.dead_paths ?? [],
    skip_files: r.skip_files ?? [],
    min_hits: r.min_hits ?? 0,
  };
}

function collectMd(root: string): string[] {
  const skills = path.join(root, ".agents", "skills");
  let st: fs.Stats;
  try {
    st = fs.statSync(skills);
  } catch {
    fail(`skills 目录不存在: ${skills}`);
  }
  if (!st.isDirectory()) fail(`skills 目录不存在: ${skills}`);
  const out: string[] = [];
  const walk = (dir: string): void => {
    for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, ent.name);
      if (ent.isDirectory()) walk(p);
      else if (ent.name.endsWith(".md")) out.push(p);
    }
  };
  walk(skills);
  if (out.length === 0) fail("skills 目录下 0 个 md 文件——扫描面塌缩，fail loud");
  return out;
}

export function run(root: string): number {
  const r = loadRules(root);
  repoRoot = root;
  topCache = new Set(fs.readdirSync(root));
  const skipSet = new Set(r.skip_files.map((s) => ".agents/skills/" + s.split(path.sep).join("/")));
  const total: Hit[] = [];
  let nFiles = 0;
  let repoHits = 0;
  for (const f of collectMd(root)) {
    const rel = path.relative(root, f).split(path.sep).join("/");
    if (skipSet.has(rel)) continue;
    nFiles++;
    const res = scanFile(f, r);
    total.push(...res.hits);
    repoHits += res.repoHits;
  }
  process.stdout.write(
    `skill_path_check: files=${nFiles} repo_path_refs=${repoHits} (min_hits=${r.min_hits}) missing=${total.length}\n`,
  );
  for (const h of total) process.stdout.write(`  MISSING ${h.file}:${h.line}  ${h.path}\n`);
  if (total.length > 0) fail(`发现 ${total.length} 处不存在的路径引用`);
  if (repoHits < r.min_hits) {
    fail(`仓库路径引用总数 ${repoHits} 低于下限 ${r.min_hits}——抽取面塌缩（D8 形态），先人工核扫描面是否失效`);
  }
  process.stdout.write("ok all referenced repo paths exist\n");
  return 0;
}

/** 9 路判定 + min_hits 守卫（临时树，不碰仓库）。 */
export function selftest(): number {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "spc_selftest"));
  try {
    repoRoot = root;
    topCache = new Set(["scripts", "corpus", "tmp", "native", "AGENTS.md"]);
    for (const d of ["scripts/bin", "corpus/baseline", "tmp/x"]) fs.mkdirSync(path.join(root, d), { recursive: true });
    for (const f of ["scripts/bin/vitro", "corpus/baseline/a.c", "tmp/x/any", "AGENTS.md"]) {
      fs.writeFileSync(path.join(root, f), "x");
    }
    const r: Rules = { whitelist_prefixes: ["tmp/", "moonbit/_build/", "native/"], dead_paths: [], skip_files: [], min_hits: 2 };
    const cases: Array<{ name: string; tok: string; missing: boolean; skipped: boolean }> = [
      { name: "存在路径绿", tok: "scripts/bin/vitro", missing: false, skipped: false },
      { name: "不存在路径红", tok: "scripts/nope/zzz", missing: true, skipped: false },
      { name: "变量段截断取静态前缀", tok: "corpus/$d", missing: false, skipped: false },
      { name: "占位符段截断", tok: "corpus/<suite>/x.c", missing: false, skipped: false },
      { name: "白名单豁免", tok: "tmp/anything/here", missing: false, skipped: true },
      { name: "退役历史域豁免", tok: "native/tests/cases/$d", missing: false, skipped: true },
      { name: "file:line 截断到静态目录", tok: "corpus/baseline/a.c:3", missing: false, skipped: false },
      { name: "非仓库根前缀不判", tok: "cmd/run/run.exe", missing: false, skipped: true },
      { name: "裸文件名不判", tok: "p.c", missing: false, skipped: true },
    ];
    for (const c of cases) {
      const { pfx, skipped } = checkToken(c.tok, topCache, r);
      let missing = "";
      if (pfx !== "") {
        try {
          fs.statSync(path.join(repoRoot, pfx.split("/").join(path.sep)));
        } catch {
          missing = pfx;
        }
      }
      if (missing !== "" && !c.missing) fail(`selftest ${c.name}: "${c.tok}" 意外报缺失 ${missing}`);
      if (missing === "" && c.missing) fail(`selftest ${c.name}: "${c.tok}" 期望红却未红（闸无牙）`);
      if (skipped !== c.skipped) fail(`selftest ${c.name}: "${c.tok}" skip=${skipped} 期望 ${c.skipped}`);
    }
    if (1 < r.min_hits) process.stdout.write("selftest ok: 9 路判定 + min_hits 守卫在案\n");
    process.stdout.write("ok selftest\n");
    return 0;
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
}

export function main(argv: string[]): number {
  let rootArg = ".";
  let self = false;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i] ?? "";
    const eq = a.indexOf("=");
    const flag = eq >= 0 ? a.slice(0, eq) : a;
    if (flag === "-root" || flag === "--root") {
      const v = eq >= 0 ? a.slice(eq + 1) : argv[++i];
      if (v === undefined) {
        process.stderr.write("skill_path_check: -root 缺值\n");
        return 2;
      }
      rootArg = v;
    } else if (flag === "-selftest" || flag === "--selftest") self = true;
    else {
      process.stderr.write(`skill_path_check: 未知参数 ${JSON.stringify(a)}\n`);
      return 2;
    }
  }
  if (self) return selftest();
  // 默认根 = 仓库根（projectRoot 找不到即 exit 2）；显式 -root 原样解析
  const root = rootArg === "." ? projectRoot() : path.resolve(rootArg);
  return run(root);
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  process.exit(main(process.argv.slice(2)));
}
