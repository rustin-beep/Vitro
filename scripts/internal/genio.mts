// genio.mts —— 生成器共享的出口 / 参数 / 幂等校验单源（#273 骨架批）。
//
// 只收「确实同构」的三件，不硬统一语义有差异的部分：
//
//   ① makeFail   —— 转 18 份各自实现的 die/fatal/fail 为工厂（前缀与退出码是
//                   历史既有行为，逐生成器不同，故必须显式传参而非取默认）
//   ② parseFlags —— 转 5 份手写 argv 解析（其中 gen_protocol_fields 与
//                   gen_host_route 两份是逐字复制），支持 `-k v` 与 `-k=v`
//   ③ emitWithMoonFmt —— 转 3 份「写盘 → moon fmt → 回读 → LF 归一比较 →
//                   无条件还原」同构段（单产物 = 长度 1 的数组）
//   ④ goJSONString —— 转 2 份逐字重复的 Go encoding/json 字符串形态复刻
//                   （gen_icons / gen_course；2026-11-01 审阅 v2 S08 次级下沉）
//
// 明确**不**收：-check 的成功/失败文案、退出码分流（fatal vs 汇总 bool）、
// -selftest 调度。那些是各生成器的真实设计差异，统一会变成参数迷宫——判据是
// 「配置面不超过被替换的代码」。
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

/** 生成器错误出口：打印带前缀的消息后以指定码退出。 */
export interface GenFail {
  (msg: string): never;
}

/**
 * 造错误出口。前缀与退出码由调用方给——既有行为分两族：
 * `"<name>: " + 1/2`（gen_stubs / gen_libc_data / gen_demo_algorithms）与
 * `"FATAL: " + 2`（gen_icons / capi.fatal 族）。收敛时**不改语义**。
 */
export function makeFail(prefix: string, code = 2): GenFail {
  return (msg: string): never => {
    process.stderr.write(prefix + msg + "\n");
    process.exit(code);
  };
}

/**
 * Go encoding/json 字符串形态（HTML 三字符 `<>&` 与 U+2028/U+2029 转义）——
 * 产物与旧 Go 生成器保持同一编码口径（icons.json / lessons.ts 逐字节锁）。
 */
export function goJSONString(s: string): string {
  return JSON.stringify(s).replace(/[<>&\u2028\u2029]/g, (c) => {
    switch (c) {
      case "<":
        return "\\u003c";
      case ">":
        return "\\u003e";
      case "&":
        return "\\u0026";
      case "\u2028":
        return "\\u2028";
      default:
        return "\\u2029";
    }
  });
}

export interface FlagSpec {
  /** 无值 flag（含短横线），如 ["-check", "--check"] */
  bool: string[];
  /** 带值 flag（含短横线），如 ["-src", "-out"] */
  value: string[];
}

export interface ParsedFlags {
  /** 任一名命中即为真（`p.has("-check", "--check")`） */
  has(...names: string[]): boolean;
  /** 取带值 flag 的原始字符串（未 resolve，调用方自行 path.resolve） */
  value(name: string): string | undefined;
  /** 未识别的参数（含位置参数）——调用方按各生成器既有语义决定 fail 与否 */
  rest: string[];
}

/**
 * 解析 `-k` / `-k=v` / `-k v`。
 *
 * 语义对齐既有实现：未知参数收进 rest（不在此处 fail，因为「未知即错」与
 * 「未知视为位置参数」在既有生成器里并存）；布尔 flag 带 `=` 值则 fail loud
 * （既有实现会静默忽略 `-check=x` 的值——这是静默 default，不迁）。
 */
export function parseFlags(argv: string[], spec: FlagSpec, fail: GenFail): ParsedFlags {
  const bools = new Set<string>();
  const values = new Map<string, string>();
  const rest: string[] = [];
  for (let i = 0; i < argv.length; i++) {
    const raw = argv[i] ?? "";
    const eq = raw.indexOf("=");
    const flag = eq >= 0 ? raw.slice(0, eq) : raw;
    if (spec.bool.includes(flag)) {
      if (eq >= 0) fail(`布尔 flag ${flag} 不接受值（收到 ${raw}）`);
      bools.add(flag);
      continue;
    }
    if (spec.value.includes(flag)) {
      const v = eq >= 0 ? raw.slice(eq + 1) : argv[++i];
      if (v === undefined) fail(`${flag} 缺值`);
      values.set(flag, v);
      continue;
    }
    rest.push(raw);
  }
  return {
    has: (...names: string[]): boolean => names.some((n) => bools.has(n)),
    value: (name: string): string | undefined => values.get(name),
    rest,
  };
}

/** CRLF 归一（latin1 往返，避免 UTF-8 解码损耗——与既有实现同口径）。 */
function toLF(b: Buffer): Buffer {
  return Buffer.from(b.toString("latin1").replace(/\r\n/g, "\n"), "latin1");
}

export interface MoonFmtProduct {
  /** moonbit/ 相对路径（moon fmt 的实参形态） */
  rel: string;
  content: string;
}

export interface MoonFmtSpec {
  root: string;
  products: MoonFmtProduct[];
  check: boolean;
  fail: GenFail;
  /** -check 漂移时的再生命令提示（各生成器文案不同，由调用方给） */
  driftHint: string;
  /** moonbit workspace 目录，默认 <root>/moonbit */
  moonbit?: string;
}

/**
 * 期望内容经 moon fmt 归一后的字节（产物本体零触碰）：写系统临时目录的
 * standalone `.mbtx`（moon fmt 支持无包语境格式化——与包内 .mbt 的 fmt 输出逐
 * 字节等价，2026-11-02 对仓内 8 个 *_gen.mbt 逐一 md5 实测全等），fmt 后读回即删。
 * fmt 失败（如 moon 缺失）只抛不留痕。
 */
export function fmtViaTmpMbtx(moonbit: string, content: string, fail: GenFail): Buffer {
  const tmp = path.join(os.tmpdir(), `genio_fmt_${process.pid}_${Date.now()}_${Math.random().toString(36).slice(2)}.mbtx`);
  try {
    fs.writeFileSync(tmp, content);
    const fmt = spawnSync("moon", ["fmt", tmp], { cwd: moonbit, encoding: "utf8" });
    if (fmt.status !== 0) {
      return fail(`moon fmt 失败（moon 须在 PATH）: exit ${fmt.status}\n${(fmt.stdout ?? "") + (fmt.stderr ?? "")}`);
    }
    return fs.readFileSync(tmp);
  } finally {
    fs.rmSync(tmp, { force: true });
  }
}

/**
 * `-check`：**产物本体零触碰**——期望内容经 fmtViaTmpMbtx 归一后与盘上产物 LF
 * 归一比对；缺失即漂移。（2026-11-02 PR #416 审阅 P2-2 升格：原「写产物 → moon
 * fmt → 回读 → 还原」形态每跑一次 -check 必刷产物 mtime（D20 同族——扰动
 * gen_demo_algorithms 的 ensureFresh 复核链），且 fmt 失败窗口把产物覆盖为未
 * fmt 模板——gen_icons S08-1/2 先治、本次下沉单源让全部消费者同治。）
 *
 * 非 check 模式：写盘 → `moon fmt <rel>` → 失败则还原调用前状态（原本不存在的
 * 产物删掉——骨架批修正）；成功留在「已写入」状态并直接返回（调用方自己打印成功消息）。
 */
export function emitWithMoonFmt(spec: MoonFmtSpec): void {
  const moonbit = spec.moonbit ?? path.join(spec.root, "moonbit");

  if (spec.check) {
    const drifted: string[] = [];
    for (const p of spec.products) {
      const abs = path.join(moonbit, p.rel);
      let cur: Buffer | null;
      try {
        cur = fs.readFileSync(abs);
      } catch {
        cur = null;
      }
      const want = fmtViaTmpMbtx(moonbit, p.content, spec.fail);
      if (cur === null || !toLF(want).equals(toLF(cur))) drifted.push(p.rel);
    }
    if (drifted.length > 0) {
      spec.fail(`-check: 产物漂移 ${drifted.join(", ")}——${spec.driftHint}`);
    }
    return;
  }

  const items = spec.products.map((p) => {
    const abs = path.join(moonbit, p.rel);
    let cur: Buffer | null;
    try {
      cur = fs.readFileSync(abs);
    } catch {
      cur = null;
    }
    try {
      fs.mkdirSync(path.dirname(abs), { recursive: true });
      fs.writeFileSync(abs, p.content);
    } catch (e) {
      if (cur !== null) fs.writeFileSync(abs, cur);
      return spec.fail(`写产物失败 ${p.rel}: ${(e as Error).message}`);
    }
    return { abs, rel: p.rel, cur };
  });

  const restore = (): void => {
    for (const it of items) {
      if (it.cur !== null) fs.writeFileSync(it.abs, it.cur);
      else fs.rmSync(it.abs, { force: true });
    }
  };

  const fmt = spawnSync("moon", ["fmt", ...items.map((i) => i.rel)], {
    cwd: moonbit,
    encoding: "utf8",
  });
  if (fmt.status !== 0) {
    restore();
    spec.fail(
      `moon fmt 失败（moon 须在 PATH）: exit ${fmt.status}\n${(fmt.stdout ?? "") + (fmt.stderr ?? "")}`,
    );
  }
}
