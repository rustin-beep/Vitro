#!/usr/bin/env node
// main.mts —— 测试数字自动同步 CLI（#273 存量 Go 重写批；原 main.go）。
// 可反复运行（不是一次性脚本）。
//
// 用法（**flag 必须写在子命令之前**——Go flag 在第一个位置参数处停止解析，
// `facts sync --yes` 里的 --yes 会被静默丢弃，脚本会显式报错拦截）：
//
//	node scripts/facts/main.mts                    # 采集(只读) → 对账 → 交互式逐条同步
//	node scripts/facts/main.mts check              # CI 门禁：有漂移 exit 1（不改文件）
//	node scripts/facts/main.mts report             # 只生成报告 reports/doc_fact_drift.md
//	node scripts/facts/main.mts facts              # 只打印事实台账 reports/facts.json
//
// 常用选项：
//
//	--run         额外执行 replay / serve_smoke（补全它们的真值）
//	--run-slow    再额外执行 cargo test（很慢）
//	--yes         自动应用无警告条目；带警告的（分解式/实测数字/同行多规则）仍跳过
//	--force       连带警告条目也自动应用（会改断分解式/伪造测量记录，慎用）
//	--verbose     报告含冻结（as-of）命中明细
//	--allow-stale check 容忍真值超龄（本地调试逃生门；CI 不得使用）
//	--max-age D   真值新鲜度预算，如 168h / 72h（默认 168h；超龄降级且 check 变红）
//
// 交互按键：y=改这一处  n=跳过  a=全部改  d=看完整行  q=退出
import * as fs from "node:fs";
import * as path from "node:path";
import * as readline from "node:readline";
import {
  allDrift, applyHit, auditDocs, labelOf, renderReport, rules, truthsInRange, unitOf,
} from "./audit.mts";
import type { AuditResult, Hit } from "./audit.mts";
import {
  cachedKeys, collectAll, demoteStale, goParseDuration, printFacts, writeFacts,
} from "./facts.mts";
import type { FactsDoc } from "./facts.mts";

function fatal(msg: string): never {
  process.stderr.write("错误: " + msg + "\n");
  process.exit(2);
}

// goQuote 复刻 fmt %q 的常见形态（可打印串双引号包裹；反斜杠/双引号转义）。
function goQuote(s: string): string {
  return '"' + s.replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
}

// truncate 按 Go 语义（rune 计长）。
function truncate(s: string, n: number): string {
  const runes = [...s];
  if (runes.length <= n) return s;
  return runes.slice(0, n).join("") + "…";
}

// ─── Go flag.NewFlagSet(ExitOnError) 语义复刻 ────────────────────────────────
//
// - `-x` / `--x` / `-x=v` / `-x v`；布尔 flag 不吃下一参数；
// - 布尔 flag 带 = 值 → fail loud（#289 P3-1 裁决：拒绝执行而非猜语义）；
// - 未定义 flag → fail loud（文案对齐 Go "flag provided but not defined"）；
// - 第一个非 flag 参数停止解析；`--` 终止且被吃；`-` 终止且进位置参数。
const BOOL_FLAGS = new Set(
  ["-run", "--run", "-run-slow", "--run-slow", "-verbose", "--verbose",
    "-yes", "--yes", "-force", "--force", "-allow-stale", "--allow-stale", "-strict", "--strict"],
);
const VALUE_FLAGS = new Set(["-max-age", "--max-age", "-cargo-log", "--cargo-log"]);

interface GoFlags {
  has(name: string): boolean;
  value(name: string): string | undefined;
  args: string[];
}

function parseGoFlags(argv: string[]): GoFlags {
  const bools = new Set<string>();
  const values = new Map<string, string>();
  const args: string[] = [];
  let i = 0;
  for (; i < argv.length; i++) {
    const a = argv[i]!;
    if (a === "--") {
      i++;
      break;
    }
    if (a === "-") break;
    if (!a.startsWith("-")) break;
    const eq = a.indexOf("=");
    const name = eq >= 0 ? a.slice(0, eq) : a;
    if (BOOL_FLAGS.has(name)) {
      if (eq >= 0) fatal(`布尔 flag ${name} 不接受值（收到 ${a}）——布尔 flag 一律无值形态`);
      bools.add(name);
    } else if (VALUE_FLAGS.has(name)) {
      if (eq >= 0) {
        values.set(name, a.slice(eq + 1));
      } else {
        const v = argv[i + 1];
        if (v === undefined) fatal(`${name} 缺值`);
        values.set(name, v);
        i++;
      }
    } else {
      fatal(`flag provided but not defined: ${name}\n（flag 必须写在子命令之前，如 \`node scripts/facts/main.mts --yes sync\`）`);
    }
  }
  args.push(...argv.slice(i));
  return {
    has: (n) => bools.has(n),
    value: (n) => values.get(n),
    args,
  };
}

function summarize(res: AuditResult, doc: FactsDoc, strict = false): void {
  console.log(`\n扫描 ${res.scanN} 份文档：漂移 ${res.driftN} 处 / 冻结 ${res.frozenN} 处 / 人工维护 ${res.manualN} 处（其中疑似未连坐 ${res.suspectN} 处）/ 待采集 ${res.pendingN} 处 / 坏引用 ${res.broken.length} 处`);
  for (const a of res.audits) {
    if (a.drift.length > 0) {
      const first = a.drift[0]!;
      console.log(`  [漂移] ${a.rule.label}: 真值 ${a.truth}，${a.drift.length} 处不一致（如 ${first.file}:${first.lineNo} = ${hitValueOf(first)}）`);
    }
  }
  for (const c of res.consts) {
    if (c.drift.length > 0) {
      const first = c.drift[0]!;
      console.log(`  [漂移·常量] ${c.rule.label}: 真值 ${c.truth}，${c.drift.length} 处不一致（如 ${first.file}:${first.lineNo} = ${first.found.join("、")}）——人工修，不自动替换`);
    }
  }
  for (const a of res.audits) {
    if (a.manual.length > 0) {
      const first = a.manual[0]!;
      console.log(`  [人工维护] ${a.rule.label}: ${a.manual.length} 处（分解式/实测行，子项与总数机判不区分）如 ${first.file}:${first.lineNo}`);
    }
  }
  // Manual 兜底：整行无数字对上真值（见 FactAudit.suspect）。默认只提醒；
  // --strict 时判红。首条连同文件行号列出，便于直接定位。
  for (const a of res.audits) {
    if (a.suspect.length > 0) {
      const first = a.suspect[0]!;
      console.log(`  ❗[疑似未连坐] ${a.rule.label}: ${a.suspect.length} 处整行无数字等于真值 ${a.truth}（manual 兜底；--strict 判红）如 ${first.file}:${first.lineNo} = ${hitValueOf(first)}`);
    }
  }
  // Suspect 豁免留痕（suspect_exemptions.json，2026-10-01 接线批）——
  // 豁免面常显，防"白名单悄悄扩大"。
  if (res.suspectExemptedN > 0) {
    console.log(`  [Suspect 已豁免] ${res.suspectExemptedN} 处经 suspect_exemptions.json 过闸（--strict 不判红；详情见报告）`);
  }
  for (const s of res.staleSuspectExempts) {
    console.log(`  ❗[僵尸豁免] suspect_exemptions.json 条目本轮零命中：${s}（删除或修正该条目）`);
  }
  for (const r of res.broken) {
    console.log(`  [坏引用] ${r.file}:${r.lineNo} → ${r.path}（文件不存在）`);
  }
  for (const a of res.audits) {
    if (a.truth === null && a.pending.length > 0) {
      console.log(`  [待采集] ${a.rule.label}: ${a.pending.length} 处引用无真值 —— 用 --run 补（见 facts.json 的 how_to_get）${strict ? "〔--strict：待采集即红——漂移判定不得静默跳过，#298〕" : ""}`);
    }
  }
  const ck = cachedKeys(doc);
  if (ck.length > 0) {
    console.log(`  [沿用上次采集] ${ck.join("、")}（加 --run 可刷新）`);
  }
  console.log("报告: reports/doc_fact_drift.md");
}

function hitValueOf(h: Hit): number {
  return h.spans[0]!.value;
}

// needsHumanReview 判定一条漂移是否必须人工确认后才能改写。
// 警告来源（audit.mts 生成）：
//   - 数字绑定了实测结果（耗时/加速比…）——直接替换会伪造测量记录；
//   - 数字分解式（a + b + c）——只换总数会让算式不成立；
//   - 同一行被多条规则命中——逐条替换会交叉污染。
function needsHumanReview(h: Hit): boolean {
  return h.warn !== "" || h.cooccur.length > 0;
}

// interactiveSync 逐条弹出，输入字母确认后改写文件。
// autoYes：无警告条目自动应用；forceYes：连同警告条目也自动应用。
async function interactiveSync(root: string, res: AuditResult, autoYes: boolean, forceYes: boolean): Promise<void> {
  // SVG 命中不进文本替换清单：SVG 由 scripts/gen_svg 生成，修复动作是
  // 重跑生成器（手改数字下次再生成即回退，见 audit.mts SVG 通道注释）。
  const hits: Hit[] = [];
  let svgDrift = 0;
  for (const h of allDrift(res)) {
    if (h.file.endsWith(".svg")) {
      svgDrift++;
      continue;
    }
    hits.push(h);
  }
  const rl = readline.createInterface({ input: process.stdin });
  let stdinClosed = false;
  const readLine = (): Promise<string | null> =>
    new Promise((resolve) => {
      if (stdinClosed) {
        resolve(null);
        return;
      }
      rl.once("line", (l) => resolve(l));
      rl.once("close", () => {
        stdinClosed = true;
        resolve(null);
      });
    });
  // 启动即自动（--yes/--force）；交互中按 a 只把"无警告条目"转为自动，
  // 带警告的仍逐条询问（保留人工否决权）。
  const autoMode = autoYes || forceYes;
  const overrideWarn = forceYes;
  let applyAll = autoMode;
  let applied = 0;
  let skipped = 0;
  let failed = 0;

  console.log(`\n逐条确认（共 ${hits.length} 处）。按键: [y] 改  [n] 跳过  [a] 全部改  [d] 详情  [q] 退出`);
  if (forceYes) {
    console.log("（--force：连同警告条目全部自动应用）");
  } else if (autoYes) {
    console.log("（--yes：无警告条目自动应用，带警告的仍会逐条询问）");
  }

  let quit = false;
  for (let i = 0; i < hits.length; i++) {
    if (quit) break;
    const h = hits[i]!;
    // Drift 条目必然产生于 truth!=null 的规则（见 audit.mts 判定流），缺键不可能。
    const truth = res.truthOf[h.key]!;
    console.log(`\n[${i + 1}/${hits.length}] ${labelOf(res, h.key)}`);
    console.log(`  ${h.file}:${h.lineNo}`);
    console.log(`  ${hitValueOf(h)} → ${truth} ${unitOf(res, h.key)}`);
    console.log(`  > ${truncate(h.text, 150)}`);
    if (h.warn !== "") {
      console.log(`  ⚠ ${h.warn}`);
    }
    if (h.cooccur.length > 0) {
      console.log(`  ⚠ 同一行还含: ${h.cooccur.join(" / ")} —— 改完请人工核对整行`);
    }

    // 自动应用仅覆盖无警告条目；--force 覆盖一切。
    if (applyAll && (overrideWarn || !needsHumanReview(h))) {
      try {
        applyHit(root, h, truth);
        applied++;
        console.log("  ✓ 已改");
      } catch (e) {
        console.log(`  ✗ 失败: ${(e as Error).message}`);
        failed++;
      }
      continue;
    }
    if (applyAll && autoMode && needsHumanReview(h)) {
      // --yes 遇到警告条目：不静默跳过，明示留给人审
      skipped++;
      console.log("  – 带警告，--yes 不自动改（--force 强制 / 交互运行逐条确认）");
      continue;
    }

    let handled = false;
    while (!handled) {
      process.stdout.write("  [y] 改  [n] 跳过  [a] 全部改  [d] 详情  [q] 退出 > ");
      const line = await readLine();
      if (line === null) {
        // stdin 关闭（非交互）：保守退出，不动文件
        console.log("\n（标准输入已结束，停止同步）");
        quit = true;
        break;
      }
      const ans = line.trim().toLowerCase();
      switch (ans) {
        case "y":
          try {
            applyHit(root, h, truth);
            applied++;
            console.log("  ✓ 已改");
          } catch (e) {
            console.log(`  ✗ 失败: ${(e as Error).message}`);
            failed++;
          }
          handled = true;
          break;
        case "n":
        case "":
          skipped++;
          console.log("  – 跳过");
          handled = true;
          break;
        case "a":
          applyAll = true;
          try {
            applyHit(root, h, truth);
            applied++;
            console.log("  ✓ 已改（后续无警告条目自动应用，带警告的仍会询问）");
          } catch (e) {
            console.log(`  ✗ 失败: ${(e as Error).message}`);
            failed++;
          }
          handled = true;
          break;
        case "d":
          console.log(`\n  完整行:\n  ${h.text}`);
          break; // 不置 handled：重问
        case "q":
          quit = true;
          console.log("  – 退出");
          handled = true;
          break;
        default:
          break; // 重问
      }
    }
  }
  rl.close();

  console.log(`\n同步结束：已改 ${applied} / 跳过 ${skipped} / 失败 ${failed}`);
  if (svgDrift > 0) {
    console.log(`另有 SVG data-fact 漂移 ${svgDrift} 处未入列——重跑 node scripts/gen_svg/main.mts 再 check`);
  }
  if (applied > 0) {
    console.log("建议复查: git diff --stat  （数字改动应只落在被确认的行）");
  }
}

async function main(): Promise<void> {
  const gf = parseGoFlags(process.argv.slice(2));
  const doRun = gf.has("-run") || gf.has("--run");
  const doRunSlow = gf.has("-run-slow") || gf.has("--run-slow");
  const verbose = gf.has("-verbose") || gf.has("--verbose");
  const autoYes = gf.has("-yes") || gf.has("--yes");
  const forceYes = gf.has("-force") || gf.has("--force");
  const allowStale = gf.has("-allow-stale") || gf.has("--allow-stale");
  const strict = gf.has("-strict") || gf.has("--strict");
  const maxAgeRaw = gf.value("-max-age") ?? gf.value("--max-age");
  let maxAgeMs = 168 * 36e5;
  if (maxAgeRaw !== undefined) {
    const d = goParseDuration(maxAgeRaw);
    if (d === null) fatal(`无效的 --max-age 值 ${goQuote(maxAgeRaw)}（Go duration 形态：168h / 72h30m）`);
    maxAgeMs = d;
  }
  const cargoLog = gf.value("-cargo-log") ?? gf.value("--cargo-log") ?? "";

  // Go flag 在第一个位置参数处停止解析：`facts sync --yes` 的 --yes 会被
  // 位置参数静默丢弃、自动降级为交互模式（曾实测：--yes 完全空转、已改 0）。
  // 残留 flag 形态的参数必须 fail loud，不许静默吞掉。
  for (const a of gf.args) {
    if (a.startsWith("-") && a !== "-") {
      fatal(`参数 ${goQuote(a)} 未被解析（flag 必须写在子命令之前，如 \`node scripts/facts/main.mts --yes sync\`）`);
    }
  }

  let cmd = "sync";
  if (gf.args.length > 0) cmd = gf.args[0]!;

  const root = process.cwd();
  // 口径演进（2026-10-25 迁移批，登记在案）：Go 版判 go.mod；TS 版判
  // moonbit/moon.mod——MoonBit workspace 是现役唯一实现区，Go 工具链退役后
  // go.mod 将随批删除，根判据必须换到永远在的真值锚。
  if (!fs.existsSync(path.join(root, "moonbit", "moon.mod"))) {
    fatal("请在项目根目录运行（找不到 moonbit/moon.mod）");
  }

  const factsPath = path.join(root, "reports", "facts.json");
  const reportPath = path.join(root, "reports", "doc_fact_drift.md");

  // ── 采集（仅读产物；--run 才实际执行防线）──
  // 沿用上次采集值，避免每次运行都要重跑 replay / serve_smoke。
  let prev: FactsDoc | null = null;
  try {
    prev = JSON.parse(fs.readFileSync(factsPath, "utf8")) as FactsDoc;
  } catch {
    prev = null;
  }
  const doc = collectAll(root, doRun, doRunSlow, cargoLog, prev);
  // 先写盘**原始采集值**，再做超龄降级（降级只作用于内存中本轮判定的 doc）。
  // 若把 value:null 写回 facts.json，replay/serve_smoke 这类靠 prev-fallback
  // 沿用的真值会不可逆丢失——超龄一次就必须 --run 重采（曾实测踩坑）。
  writeFacts(doc, factsPath);

  if (cmd === "facts") {
    console.log("事实台账已写入: reports/facts.json");
    printFacts(doc);
    return;
  }

  // 真值新鲜度门禁：as_of 超过预算的真值降级为待采集（不参与漂移判定），
  // 防止用陈旧真值判新文档、乃至把错数字 sync 进文档。
  const staleN = demoteStale(doc, maxAgeMs);

  // ── 对账 ──
  // 真值越界自检先于文档扫描（模块审阅 09 P2-2 治本）：带宽过时会让
  // 对账整体静默——先红一次，逼人改区间，而不是拿盲区当绿灯。
  const rc = truthsInRange(rules(), doc);
  if (rc.out) {
    fatal(`规则 ${rc.key} 真值 ${rc.truth} 越出带宽 [${rc.lo},${rc.hi}]——候选过滤后整行静默；请放宽区间（scripts/facts/audit.mts rules()）`);
  }
  const res = auditDocs(root, doc);
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  fs.writeFileSync(reportPath, renderReport(root, doc, res, verbose), { mode: 0o644 });

  summarize(res, doc, strict);
  if (staleN > 0) {
    if (allowStale) {
      console.log(`  [真值超龄] ${staleN} 项 as_of 超过预算，已降级为待采集（--allow-stale：本轮容忍；加 --run 刷新）`);
    } else {
      console.log(`  [真值超龄] ${staleN} 项 as_of 超过预算，已降级为待采集——check 将 exit 1（加 --run 刷新）`);
    }
  }

  switch (cmd) {
    case "check":
      // 超龄即红（曾实测假绿：--max-age 1ns → 真值全超龄 → 漂移 0 → exit 0，
      // 文档漂移一个没修 CI 照样绿——降级保护了 sync 却给 check 开了后门）。
      // --allow-stale 是本地调试逃生门，CI 不得使用。坏引用同理：文档指向
      // 不存在的脚本 = 文档已失效，必须红。
      //
      // --strict：再叠一层 Manual 兜底（分解式行整行无数字等于真值）。误报
      // 面经 suspect_exemptions.json 显式过闸后 CI 启用（2026-10-01 接线）。
      // 僵尸豁免条目无条件红（数据错误非口径问题，不随 --strict 开关）。
      //
      // #298（2026-10-27）：待采集（键真值缺位）有文档消费点时 strict 判红
      // ——旧形态只提示不判红：CI fresh 环境（无 reports/facts.json）27 处
      // 待采集静默跳过漂移判定 → 漂移 0 → 假绿（run 40409823786 实锤，
      // 「MoonBit 测试数」21 处引用的漂移防护整体失效）。红 = 逼采集面
      // （--run）与消费面同步；非 strict 保持提示（本地快查逃生门，
      // 与 --allow-stale 对称）。
      {
        const suspectRed = strict && res.suspectN > 0;
        const pendingRed = strict && res.pendingN > 0;
        if (res.driftN > 0 || res.broken.length > 0 || (staleN > 0 && !allowStale) || suspectRed || pendingRed || res.staleSuspectExempts.length > 0) {
          process.exit(1);
        }
      }
      break;
    case "report":
      return;
    case "sync": {
      // DriftN 已并入常量漂移数（见 auditDocs），交互同步只管数字部分。
      let constDriftN = 0;
      for (const c of res.consts) constDriftN += c.drift.length;
      if (res.driftN - constDriftN > 0) {
        await interactiveSync(root, res, autoYes, forceYes);
      } else {
        console.log("所有 CURRENT 数字与真值一致，无需同步。");
      }
      // 常量漂移不进自动替换（会把"更名时返回 2.0.0"这类事件句篡改成
      // 假历史），只指路：改写句子形态是语义决策，人来做。
      for (const c of res.consts) {
        if (c.drift.length === 0) continue;
        console.log(`⚠ 常量漂移 ${c.drift.length} 处（${c.rule.label}，真值 ${c.truth}）需人工修——见 reports/doc_fact_drift.md`);
      }
      break;
    }
    default:
      fatal("未知子命令: " + cmd + "（可用: sync / check / report / facts）");
  }
}

await main();
