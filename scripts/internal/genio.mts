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
//
// 明确**不**收：-check 的成功/失败文案、退出码分流（fatal vs 汇总 bool）、
// -selftest 调度。那些是各生成器的真实设计差异，统一会变成参数迷宫——判据是
// 「配置面不超过被替换的代码」。
import fs from "node:fs";
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
 * `-check` 幂等：期望内容写盘 → `moon fmt` 归一 → 回读按 LF 归一比对 →
 * **无论成败都还原原产物**（文件参数 fmt 与整包 fmt 形态不同，不还原会让
 * -check 产生副作用并破坏幂等）。
 *
 * 非 check 模式留在「已写入」状态并直接返回（调用方自己打印成功消息）。
 */
export function emitWithMoonFmt(spec: MoonFmtSpec): void {
  const moonbit = spec.moonbit ?? path.join(spec.root, "moonbit");
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

  // 还原 = 回到调用前状态：**原本不存在的产物要删掉**，不是留着（既有实现
  // 只写回 cur!==null 的那些，于是 -check 在产物缺失时会把新产物留在盘上，
  // 破坏零副作用承诺——本条为骨架批修正）。
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
  if (!spec.check) return;

  const drifted: string[] = [];
  for (const it of items) {
    let now: Buffer;
    try {
      now = fs.readFileSync(it.abs);
    } catch (e) {
      restore();
      return spec.fail(`-check: 回读产物失败 ${it.rel}: ${(e as Error).message}`);
    }
    if (it.cur === null || !toLF(now).equals(toLF(it.cur))) drifted.push(it.rel);
  }
  restore();
  if (drifted.length > 0) {
    spec.fail(`-check: 产物漂移 ${drifted.join(", ")}——${spec.driftHint}`);
  }
}
