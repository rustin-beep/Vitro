#!/usr/bin/env node
// teaching_gen_check —— 教学资产生成闸（Go→.mts 重写，refs #273；原 #125 批 A）。
//
// 驱动 moonbit/teaching/tools/content_parser.c（**vitro 编译运行——C 解析器
// 自举**，三 schema 经 `--` argv 选模式），产物经 moon fmt 后与入库
// `moonbit/teaching/{assets,content_data}/*_gen.mbt` 逐字节比对（生成器契约：
// 产物形态以 fmt 为准；builtin_notes 实测 fmt 改写数组换行 58B，故 fmt 必须在环内）。
//
// 用法（仓库根）：
//   node scripts/teaching_gen_check/main.mts                 # -check 语义（CI 闸）
//   node scripts/teaching_gen_check/main.mts -write          # 再生（真源变更后）
//   node scripts/teaching_gen_check/main.mts -backend native # 换臂（缺省 js；
//                                                            # 四臂对拍由批 A 验收
//                                                            # driver 离线覆盖）
//
// 语义要点（实测记档 2026-10-15，本重写逐条保留）：
//   - 程序返回值在 **note 帧**（"程序运行完成，返回值：N"），CLI 自身恒
//     rc=0——必须解析 note 帧，否则失败静默假绿（#129 裸跑 stdout 污染另案）。
//   - --json stdout 帧的 delta 是 **Latin-1 折叠字节**（1 字符=1 字节），
//     重建 = 逐码点折回字节；>0xFF 码点按 UTF-8 编码（demo run.ts 同款）。
//   - fmt 走包内临时件：写 assets/_gencheck_tmp.mbt → moon fmt → 比对 →
//     删除（check 不留副作用；-write 直接落正式路径后再 fmt）。
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../internal/capi.mts";

export interface Spec {
  /** parser argv[1] */
  mode: string;
  /** 真源（content/ 下） */
  src: string;
  /** 产物目录（moonbit/ 相对；#130 批③a：trap 留 assets，另两表拆 content_data） */
  dir: string;
  product: string;
  /** 基线条数（解析器自校，此处仅报告） */
  expected: number;
}

export const SPECS: Spec[] = [
  { mode: "trap", src: "trap_messages.md", dir: "teaching/assets", product: "trap_messages_gen.mbt", expected: 45 },
  { mode: "suggestions", src: "suggestions.md", dir: "teaching/content_data", product: "suggestions_gen.mbt", expected: 43 },
  { mode: "builtin_notes", src: "builtin_notes.md", dir: "teaching/content_data", product: "builtin_notes_gen.mbt", expected: 12 },
];

const RE_NOTE_RC = /程序运行完成，返回值：(\d+)/;

export interface Negative {
  name: string;
  mode: string;
  src: string;
  wantFail: string;
}

/**
 * 负例组（P2-3，2026-10-15 审阅批）：此前闸只喂三个 happy-path 真源——突变
 * 「废除节标题重复检查」两闸全绿（审阅实锤负路径零覆盖）。每项 = 恶意真源 +
 * 期望 FAIL 关键词；断言解析器 fail loud：程序 rc != 0 且 stderr 重建文本命中
 * 关键词。文案锚同时锁错误信息本身（改文案不改断言 = 红）。
 */
export const NEGATIVES: Negative[] = [
  { name: "节标题重复", mode: "builtin_notes", src: "<!-- t -->\n\n## abs\n\ncount_note: a\n\n## abs\n\ncount_note: b\n", wantFail: "节标题重复" },
  { name: "param_notes 索引溢出（B18 面：2^31 段错误 → fail loud）", mode: "builtin_notes", src: "<!-- t -->\n\n## abs\n\nparam_notes[2147483648]: x\n", wantFail: "槽位超上限" },
  { name: "param_notes 空索引（静默落槽 0 → fail loud）", mode: "builtin_notes", src: "<!-- t -->\n\n## abs\n\nparam_notes[]: x\n", wantFail: "槽位为空" },
  { name: "param_notes 非数字", mode: "builtin_notes", src: "<!-- t -->\n\n## abs\n\nparam_notes[ab]: x\n", wantFail: "槽位非数字" },
  { name: "param_notes 槽位重复", mode: "builtin_notes", src: "<!-- t -->\n\n## good\n\ncount_note: a\nparam_notes[0]: x\nparam_notes[0]: y\n", wantFail: "槽位重复" },
  { name: "builtin 节不应有正文", mode: "builtin_notes", src: "<!-- t -->\n\n## abs\n\nunknown_field: x\n", wantFail: "不应有正文" },
  { name: "suggestions 臂名数字起（P3②）", mode: "suggestions", src: "<!-- t -->\n\n## 2fast_sort\n\nbody\n", wantFail: "不能以数字起" },
];

function die(msg: string): never {
  process.stderr.write("[teaching_gen_check] FAIL: " + msg + "\n");
  process.exit(1);
}

/** 跑 vitro（--json），返回原始 stdout 文本；启动失败即 fail loud。 */
function runVitroRaw(root: string, backend: string, inputPath: string, mode: string): string {
  const args = [path.join(root, "scripts/bin/vitro")];
  if (backend !== "js") args.push("--backend", backend);
  args.push("run", "--json", "moonbit/teaching/tools/content_parser.c", "-i", inputPath, "--", mode);
  const r = spawnSync("bash", args, { cwd: root });
  if (r.error !== undefined || r.status === null) {
    die(`vitro 启动失败（${backend} 臂）: ${r.error?.message ?? "未知错误"}`);
  }
  // CLI 自身 rc 恒 0；语义失败在 note 帧。非 0 说明 launcher 层挂了。
  if (r.status !== 0) {
    die(`vitro 启动失败（${backend} 臂）: exit ${r.status}\n${(r.stderr ?? Buffer.alloc(0)).toString("utf8")}`);
  }
  return (r.stdout ?? Buffer.alloc(0)).toString("utf8");
}

/** 从 note 帧取程序返回值；缺帧 = 0（与 Go 版同口径）。 */
export function programRC(stdout: string): number {
  const m = RE_NOTE_RC.exec(stdout);
  return m === null ? 0 : Number(m[1]);
}

/**
 * 帧重建：`--json` 的 delta 是 Latin-1 折叠字节，逐码点折回（<=0xFF → 单字节；
 * >0xFF → UTF-8 编码）。`frameType` 选 stdout / stderr 通道。
 */
export function rebuildChannel(stdout: string, frameType: "stdout" | "stderr"): Buffer {
  const chunks: Buffer[] = [];
  for (const line of stdout.split("\n")) {
    if (!line.includes('"delta"')) continue;
    let frame: { type?: string; frame?: { result?: { delta?: string } } };
    try {
      frame = JSON.parse(line) as typeof frame;
    } catch {
      continue;
    }
    if (frame.type !== frameType) continue;
    const delta = frame.frame?.result?.delta ?? "";
    for (const ch of delta) {
      const cp = ch.codePointAt(0) ?? 0;
      if (cp <= 0xff) chunks.push(Buffer.from([cp]));
      else chunks.push(Buffer.from(ch, "utf8"));
    }
  }
  return Buffer.concat(chunks);
}

/** runParser：跑 vitro → 帧重建出程序 stdout 字节（含 note 帧 rc 校验）。 */
export function runParser(root: string, s: Spec, backend: string): Buffer {
  const stdout = runVitroRaw(root, backend, `moonbit/teaching/content/${s.src}`, s.mode);
  const rc = programRC(stdout);
  if (rc !== 0) die(`解析器程序返回值 ${rc}（${s.mode}）\nstderr: ${rebuildChannel(stdout, "stderr").toString("utf8")}`);
  return rebuildChannel(stdout, "stdout");
}

/** runMoonFmt：包内 fmt（cwd=moonbit/，workspace 命令）。 */
export function runMoonFmt(root: string, rel: string): void {
  const r = spawnSync("moon", ["fmt", rel], { cwd: path.join(root, "moonbit") });
  if (r.error !== undefined || r.status !== 0) {
    die(`moon fmt 失败（moon 须在 PATH）: ${r.error?.message ?? `exit ${r.status}`}\n${((r.stdout ?? Buffer.alloc(0)) + "" + (r.stderr ?? Buffer.alloc(0))).toString()}`);
  }
}

/** runNegative：写临时真源 → 跑解析器（--json）→ 重建 stderr → 断言 rc≠0 + 关键词。 */
export function runNegative(root: string, n: Negative, backend: string, tmpDir: string): void {
  const p = path.join(tmpDir, `neg_${n.mode}_${Math.random().toString(16).slice(2)}.md`);
  fs.writeFileSync(p, n.src);
  try {
    const stdout = runVitroRaw(root, backend, p, n.mode);
    const rc = programRC(stdout);
    const errText = rebuildChannel(stdout, "stderr").toString("utf8");
    if (rc === 0) die(`负例 ${n.name} 未 fail loud（程序 rc=0——fail 路径回归）`);
    if (!errText.includes(n.wantFail)) {
      die(`负例 ${n.name} 的 stderr 未含期望文案 "${n.wantFail}"（实得: ${errText}）`);
    }
    process.stdout.write(`[teaching_gen_check] ✓ 负例「${n.name}」fail loud（文案锚: ${n.wantFail}）\n`);
  } finally {
    fs.rmSync(p, { force: true });
  }
}

/** check 模式：包内临时件 → fmt → 与入库产物比对（LF 归一）→ 删临时件。 */
export function checkOne(root: string, s: Spec, raw: Buffer, tmpAbs: string, tmpRel: string): boolean {
  fs.writeFileSync(tmpAbs, raw);
  runMoonFmt(root, tmpRel);
  const after = fs.readFileSync(tmpAbs);
  fs.rmSync(tmpAbs, { force: true });
  const committedPath = path.join(root, "moonbit", s.dir, s.product);
  let committed: Buffer;
  try {
    committed = fs.readFileSync(committedPath);
  } catch {
    die(`读入库产物失败 ${s.product}（先 -write 再生）`);
  }
  const norm = (b: Buffer): Buffer => Buffer.from(b.toString("latin1").replace(/\r\n/g, "\n"), "latin1");
  if (!norm(after).equals(norm(committed))) {
    process.stderr.write(
      `[teaching_gen_check] ✗ ${s.product} 漂移（raw ${raw.length} B / fmt 后 ${after.length} B / 入库 ${committed.length} B）\n`,
    );
    return false;
  }
  process.stdout.write(`[teaching_gen_check] ✓ ${s.product} 与解析器输出一致（fmt 后 ${after.length} B）\n`);
  return true;
}

/** write 模式：落正式路径 → fmt。 */
export function writeOne(root: string, s: Spec, raw: Buffer): void {
  const real = path.join(root, "moonbit", s.dir, s.product);
  fs.writeFileSync(real, raw);
  runMoonFmt(root, `${s.dir}/${s.product}`);
  process.stdout.write(`[teaching_gen_check] 再生 ${s.product}（fmt 后 ${raw.length} B）\n`);
}

export function main(argv: string[]): number {
  let backend = "js";
  let writeMode = false;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i] ?? "";
    const eq = a.indexOf("=");
    const flag = eq >= 0 ? a.slice(0, eq) : a;
    if (flag === "-backend" || flag === "--backend") {
      const v = eq >= 0 ? a.slice(eq + 1) : argv[++i];
      if (v === undefined) {
        process.stderr.write("[teaching_gen_check] -backend 缺值\n");
        return 2;
      }
      backend = v;
    } else if (flag === "-write" || flag === "--write") {
      // #289 审阅 P3-1：布尔 flag 带 = 值显式拒绝（Go flag 解析 false，本版早前丢值当 true）
      if (eq >= 0) {
        process.stderr.write(`[teaching_gen_check] 布尔 flag ${flag} 不接受值（收到 ${a}）\n`);
        return 2;
      }
      writeMode = true;
    } else {
      // 用法错 = exit 2（Go flag 包同口径），与判定红的 1 分流
      process.stderr.write(`[teaching_gen_check] 未知参数 ${JSON.stringify(a)}\n`);
      return 2;
    }
  }
  if (!["js", "native", "wasm"].includes(backend)) {
    process.stderr.write(`[teaching_gen_check] 未知 backend ${JSON.stringify(backend)}（js | native | wasm）\n`);
    return 2;
  }
  const root = projectRoot();
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "vitro_gencheck_"));

  let drifted: string[] = [];
  try {
    for (const s of SPECS) {
      const raw = runParser(root, s, backend);
      if (writeMode) {
        writeOne(root, s, raw);
        continue;
      }
      const tmpAbs = path.join(root, "moonbit", "teaching", "assets", "_gencheck_tmp.mbt");
      const ok = checkOne(root, s, raw, tmpAbs, "teaching/assets/_gencheck_tmp.mbt");
      if (!ok) drifted = [...drifted, s.product];
    }
    if (drifted.length > 0) {
      die(`产物漂移 ${drifted.join(", ")}——真源已改未再生（node scripts/teaching_gen_check/main.mts -write）`);
    }
    if (!writeMode) {
      for (const n of NEGATIVES) runNegative(root, n, backend, tmpDir);
      process.stdout.write(
        "[teaching_gen_check] 全部通过：三 schema 产物 ≡ 解析器输出（fmt 后）+ 负例 fail-loud ×7\n",
      );
    }
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
  return 0;
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  process.exit(main(process.argv.slice(2)));
}
