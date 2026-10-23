#!/usr/bin/env node
// course_catalog —— 课程内容管线契约闸（Go→.mts 重写，refs #273；原 #120，2026-10-15）。
//
// 判定型脚本纪律：stdlib 优先、规则内联（本闸无 rules.json）、fail loud、无静默 default。
//
// 用法（cwd = 仓库根）：
//   node scripts/course_catalog/main.mts            # 全量校验
//   node scripts/course_catalog/main.mts -v         # 逐条打印通过项
//   node scripts/course_catalog/main.mts -selftest  # J9 注入证红（闸自身体检）
//
// 判据（schema 校验单源在 gen_course——回退预案，不入 CI；#273 批二已迁 .mts）：
//  1. 叙述→课目对账：course/**/*.md 的 (kind,id) 必须命中 demo 课目集
//     （cases.js 用例 id ∪ algorithms.js 族/扩展 id ∪ variants tpl）——
//     「叙述指向不存在的课」即红（反方向不查：课目可以暂无叙述，渐进覆盖）。
//  2. lesson.c 防线对拍：course/**/lesson.c 存在即对拍——vitro 编译运行
//     vs clang 编译运行，stdout/stderr 逐字节比对（stdin 取自 frontmatter）。
//     独立于 corpus/ 语料线（lesson.c 是课程示例防线，非引擎对拍语料）。
//  3. J9 自检：-selftest 注入假课（id=strng-typo）断言判据必红。
//
// 两处**有意改进**（Go 版此路径在 Windows 从未被执行过——仓库当前 0 个
// lesson.c，故其 `exec.Command("scripts/bin/vitro")` 直接跑 .sh 的形态未被
// 实测覆盖）：
//   - vitro 走 `bash scripts/bin/vitro`（与 teaching_gen_check 同形态，Windows
//     Git Bash / Linux 双通），不走裸路径 exec；
//   - 帧 delta 与 clang 输出一律按**字节**（Buffer）重建与比较，不用 string
//     拼接——Latin-1 折叠口径下 string 会把 >0x7F 的字节交给 UTF-8 解码器。
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../internal/capi.mts";

export interface SrcNote {
  id: string;
  kind: string;
  dir: string;
  stdin: string;
  hasC: boolean;
}

export interface JudgeFail {
  judge: string;
  msg: string;
}

const RE_CASE_ID = /^\s*id: "([a-z_0-9]+)"/gm;
const RE_ALGO_ID = /\{\s*id: "([A-Za-z_0-9]+)", name:/g;
const RE_VAR_TPL = /tpl: "([A-Za-z_0-9]+)"/g;
const RE_LESSON_M = /^---\r?\n((?:.*\r?\n)*?)---\r?\n/m;
const RE_FM_ID = /^id:\s*"?([A-Za-z_0-9-]+)"?\s*$/m;
const RE_FM_KIND = /^kind:\s*"?([a-z]+)"?\s*$/m;
const RE_FM_STDIN = /^stdin:\s*"?([^"\n]*)"?/m;

function die(msg: string): never {
  process.stderr.write(`[course_catalog] ${msg}\n`);
  process.exit(1);
}

/** 相对仓库根解析（不 chdir，避免 import 时污染进程 cwd）。 */
function abs(p: string): string {
  return path.isAbsolute(p) ? p : path.join(projectRoot(), p);
}

/** 从若干正则抽键集（并集）。 */
export function readKeys(p: string, res: RegExp[]): Set<string> {
  let src: string;
  try {
    src = fs.readFileSync(abs(p), "utf8");
  } catch (e) {
    die(`读 ${p}: ${e instanceof Error ? e.message : String(e)}`);
  }
  const out = new Set<string>();
  for (const re of res) for (const m of src.matchAll(re)) out.add(m[1] ?? "");
  return out;
}

/** 真源收集：course/<章>/<课>/lesson.md frontmatter（缺 lesson.md = 草稿目录，跳过）。 */
export function collectNotes(): SrcNote[] {
  let chaps: string[];
  try {
    chaps = fs.readdirSync(abs("course")).sort();
  } catch (e) {
    die(`读 course/（本闸 cwd 须为仓库根）: ${e instanceof Error ? e.message : String(e)}`);
  }
  const out: SrcNote[] = [];
  for (const chap of chaps) {
    if (chap.startsWith(".")) continue;
    const chapDir = path.join("course", chap);
    let st: fs.Stats;
    try {
      st = fs.statSync(abs(chapDir));
    } catch {
      continue;
    }
    if (!st.isDirectory()) continue;
    for (const l of fs.readdirSync(abs(chapDir)).sort()) {
      const dir = path.join(chapDir, l);
      let md: string;
      try {
        md = fs.readFileSync(abs(path.join(dir, "lesson.md")), "utf8");
      } catch {
        continue; // 草稿目录
      }
      const fm = RE_LESSON_M.exec(md);
      if (fm === null) die(`${dir}: 缺 frontmatter`);
      const body = fm[1] ?? "";
      const id = RE_FM_ID.exec(body);
      const kd = RE_FM_KIND.exec(body);
      if (id === null || kd === null) die(`${dir}: frontmatter 缺 id 或 kind`);
      const si = RE_FM_STDIN.exec(body);
      out.push({
        id: id[1] ?? "",
        kind: kd[1] ?? "",
        dir,
        stdin: si === null ? "" : (si[1] ?? ""),
        hasC: fs.existsSync(abs(path.join(dir, "lesson.c"))),
      });
    }
  }
  out.sort((a, b) => Buffer.compare(Buffer.from(a.dir), Buffer.from(b.dir)));
  return out;
}

/** 判据 1：叙述→课目对账。 */
export function reconcile(notes: SrcNote[], verbose: boolean): JudgeFail[] {
  const casesKeys = readKeys("demo/cases.js", [RE_CASE_ID]);
  const algoKeys = readKeys("demo/algorithms.js", [RE_ALGO_ID, RE_VAR_TPL]);
  const fails: JudgeFail[] = [];
  for (const n of notes) {
    let ok: boolean;
    if (n.kind === "case") ok = casesKeys.has(n.id);
    else if (n.kind === "algo" || n.kind === "xlab" || n.kind === "variant") ok = algoKeys.has(n.id);
    else {
      fails.push({ judge: "对账", msg: `${n.dir}: 未知 kind "${n.kind}"` });
      continue;
    }
    if (!ok) {
      fails.push({
        judge: "对账",
        msg: `${n.dir}: 叙述 (kind=${n.kind}, id=${n.id}) 不命中任何课目（cases.js/algorithms.js 无此键）`,
      });
      continue;
    }
    if (verbose) process.stdout.write(`[course_catalog] ✓ 对账 ${n.dir} (${n.kind},${n.id})\n`);
  }
  return fails;
}

/**
 * 把 wire 侧 Latin-1 折回的 delta 还原为字节（语义对齐 demo run.ts 同名函数：
 * >0xFF 截低字节必乱码的坑已在 demo 侧实锤，此处按码点逐个还原）。
 */
export function latin1ToBytes(s: string): Buffer {
  const chunks: Buffer[] = [];
  for (const ch of s) {
    const cp = ch.codePointAt(0) ?? 0;
    if (cp <= 0xff) chunks.push(Buffer.from([cp]));
    else chunks.push(Buffer.from(ch, "utf8"));
  }
  return Buffer.concat(chunks);
}

/** CRLF → LF（字节面替换；clang 在 Windows 文本模式写 \r\n）。 */
export function normLF(b: Buffer): Buffer {
  const out: number[] = [];
  for (let i = 0; i < b.length; i++) {
    const c = b[i]!;
    if (c === 0x0d && b[i + 1] === 0x0a) continue;
    out.push(c);
  }
  return Buffer.from(out);
}

/** 从 --json 帧流拼 stdout/stderr 字节。 */
export function collectFrames(raw: string): { stdout: Buffer; stderr: Buffer } {
  const so: Buffer[] = [];
  const se: Buffer[] = [];
  for (const line of raw.split("\n")) {
    if (!line.includes('"delta"')) continue;
    let frame: { type?: string; frame?: { result?: { delta?: string } } };
    try {
      frame = JSON.parse(line) as typeof frame;
    } catch {
      continue;
    }
    const delta = frame.frame?.result?.delta ?? "";
    if (frame.type === "stdout") so.push(latin1ToBytes(delta));
    else if (frame.type === "stderr") se.push(latin1ToBytes(delta));
  }
  return { stdout: Buffer.concat(so), stderr: Buffer.concat(se) };
}

/** 跑 vitro run --json，返回两通道字节（stdin 走仓库根 `_stdin.txt`，与 Go 版同口径）。 */
export function collectVitroOutput(cPath: string, stdin: string): { stdout: Buffer; stderr: Buffer } {
  const root = projectRoot();
  const args = ["scripts/bin/vitro", "run", "--json", cPath];
  let inPath: string | null = null;
  if (stdin !== "") {
    inPath = path.join(root, "_stdin.txt");
    fs.writeFileSync(inPath, stdin);
    args.push("-i", "_stdin.txt");
  }
  try {
    const r = spawnSync("bash", args, { cwd: root });
    if (r.error !== undefined || r.status !== 0) {
      throw new Error(
        `vitro run: ${r.error?.message ?? `exit ${r.status}`}\n${(r.stdout ?? Buffer.alloc(0)).toString("utf8")}`,
      );
    }
    return collectFrames((r.stdout ?? Buffer.alloc(0)).toString("utf8"));
  } finally {
    if (inPath !== null) fs.rmSync(inPath, { force: true });
  }
}

/** Go `%q` 的近似形态（红路径诊断用；绿路径不打印）。 */
function quote(b: Buffer): string {
  return JSON.stringify(b.toString("utf8"));
}

/** 判据 2：lesson.c 防线对拍（vitro vs clang）。 */
export function verifyC(notes: SrcNote[], verbose: boolean): JudgeFail[] {
  const fails: JudgeFail[] = [];
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "course_verify_"));
  try {
    for (const n of notes) {
      if (!n.hasC) continue;
      const cPath = path.join(n.dir, "lesson.c");
      let v: { stdout: Buffer; stderr: Buffer };
      try {
        v = collectVitroOutput(cPath, n.stdin);
      } catch (e) {
        fails.push({ judge: "对拍", msg: `${cPath}: vitro 臂失败: ${e instanceof Error ? e.message : String(e)}` });
        continue;
      }
      const exe = path.join(tmp, "prog.exe");
      const cc = spawnSync("clang", [abs(cPath), "-o", exe], { cwd: tmp });
      if (cc.error !== undefined || cc.status !== 0) {
        fails.push({
          judge: "对拍",
          msg: `${cPath}: clang 编译失败: ${cc.error?.message ?? `exit ${cc.status}`}\n${(cc.stderr ?? Buffer.alloc(0)).toString("utf8")}`,
        });
        continue;
      }
      // 运行：有 stdin 时管道喂入；无 stdin 时继承空输入。
      const rr = spawnSync(exe, [], n.stdin !== "" ? { cwd: tmp, input: n.stdin } : { cwd: tmp });
      const cOut = Buffer.from(rr.stdout ?? Buffer.alloc(0));
      const cErr = Buffer.from(rr.stderr ?? Buffer.alloc(0));
      if (!normLF(v.stdout).equals(normLF(cOut)) || !normLF(v.stderr).equals(normLF(cErr))) {
        fails.push({
          judge: "对拍",
          msg: `${cPath}: 双臂输出不一致\n  vitro stdout=${quote(v.stdout)} stderr=${quote(v.stderr)}\n  clang stdout=${quote(cOut)} stderr=${quote(cErr)}`,
        });
        continue;
      }
      if (verbose) process.stdout.write(`[course_catalog] ✓ 对拍 ${cPath}（vitro ≡ clang，${v.stdout.length} B stdout）\n`);
    }
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
  return fails;
}

/** J9 自检：注入假课，断言对账判据必红。 */
export function selftest(): void {
  const fake: SrcNote[] = [{ id: "strng-typo", kind: "algo", dir: "<J9注入>", stdin: "", hasC: false }];
  const fails = reconcile(fake, false);
  for (const f of fails) {
    if (f.judge === "对账" && f.msg.includes("strng-typo")) {
      process.stdout.write("[course_catalog] J9 自检 OK：假课注入被对账判据捕获\n");
      return;
    }
  }
  die("J9 自检失败：假课注入未被捕获——判据已失效（对账函数或键集抽取漂移）");
}

export function main(argv: string[]): number {
  let verbose = false;
  let self = false;
  for (const a of argv) {
    if (a === "-v" || a === "--v") verbose = true;
    else if (a === "-selftest" || a === "--selftest") self = true;
    else {
      // 用法错 = exit 2（Go flag 包同口径），与判定红的 1 分流
      process.stderr.write(`[course_catalog] 未知参数 ${JSON.stringify(a)}\n`);
      return 2;
    }
  }
  projectRoot();
  if (self) {
    selftest();
    return 0;
  }
  const notes = collectNotes();
  const fails = [...reconcile(notes, verbose), ...verifyC(notes, verbose)];
  if (fails.length > 0) {
    for (const f of fails) process.stderr.write(`[course_catalog] ✗ [${f.judge}] ${f.msg}\n`);
    die(`${fails.length} 项判据未过`);
  }
  process.stdout.write(
    `[course_catalog] 全部通过：${notes.length} 课叙述对账 + ${notes.filter((x) => x.hasC).length} 个 lesson.c 对拍\n`,
  );
  return 0;
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  process.exit(main(process.argv.slice(2)));
}
