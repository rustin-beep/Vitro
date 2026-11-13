#!/usr/bin/env node
// wasmenc watcheck——wat 样例经 wabt 编译的指令字节 ↔ vitro（wasmenc）发射的
// 扁平字节**逐字节恒等对拍**（REHOST 批 1c 前置，2026-11-05）。
//
// 双方真源：
// - vitro 侧：`moon test -p wasmenc` 的 witness_dump_wbtest 打印行（DUMP1B 前缀）——
//   字节来自仓内单源发射器 emit_group_bytes（零孪生）；
// - node 侧：cases/*.wat 手写样例经 wabt parseWat→toBinary 编译——规范编码器。
// 对拍口径：提取 wat 模块第一个函数体的**指令区**（含尾 end），与
// 「block + 垫栈 + 模板字节 + drop×n + end」构造串逐字节比对——wabt 与
// wasmenc 对同一指令序列的编码选择（sleb/uleb 最短性、对齐立即数、f64 小端）
// 必须恒等，任何分歧即红（码位/编码形态的第三方证人——比 validate 内容级更强）。
//
// 用法：node scripts/wasmenc_watcheck/main.mts（cwd=仓库根；依赖 scripts/npm 的 wabt）

import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));

/// case 清单（wat 文件 → 组序列；每组 [op, operand] 对拍 witness dump 的
/// 同名条目——几条一组是常态形态，单条=特例）。覆盖：A 84 + B 50 + C 13
/// 的全部可发射条目（147 组，其中 PushConstD/Q 双形态与 TrapBounds 字面量
/// 形态各占第二组；A 84 含 CastD2UQ〔#471，opcode 156〕）。
const CASES: ReadonlyArray<{ wat: string; groups: ReadonlyArray<readonly [string, number]> }> = [
  { wat: "uadd.wat", groups: [["UAdd", 0]] },
  { wat: "loadlocal.wat", groups: [["LoadLocal", 8]] },
  { wat: "storemem.wat", groups: [["StoreMem", 0]] },
  { wat: "add_checked.wat", groups: [["Add", 0]] },
  { wat: "bitnot.wat", groups: [["BitNot", 0]] },
  { wat: "pushconstd.wat", groups: [["PushConstD", 0]] },
  { wat: "stackalloc.wat", groups: [["StackAlloc", 0]] },
  { wat: "a_core3.wat", groups: [["Nop", 0], ["PushConst", 8], ["Pop", 0], ["Not", 0]] },
  { wat: "a_i32_divmod.wat", groups: [["Div", 0], ["Mod", 0], ["TruncByte", 0]] },
  { wat: "a_i32_cmp.wat", groups: [["Eq", 0], ["Ne", 0], ["Lt", 0], ["Le", 0], ["Gt", 0], ["Ge", 0]] },
  { wat: "a_i32_ucmp.wat", groups: [["ULt", 0], ["ULe", 0], ["UGt", 0], ["UGe", 0]] },
  { wat: "a_i32_arith.wat", groups: [["UAdd", 0], ["USub", 0], ["UMul", 0], ["UDiv", 0], ["UMod", 0]] },
  { wat: "a_i32_bits.wat", groups: [["BitAnd", 0], ["BitOr", 0], ["BitXor", 0]] },
  { wat: "a_i64_bits.wat", groups: [["BitAndQ", 0], ["BitOrQ", 0], ["BitXorQ", 0]] },
  { wat: "a_f32_arith.wat", groups: [["PushConstF", 0x3fc00000], ["AddF", 0], ["SubF", 0], ["MulF", 0], ["DivF", 0], ["NegF", 0]] },
  { wat: "a_f32_conv.wat", groups: [["CastI2F", 0], ["CastF2I", 0], ["CastU2F", 0], ["CastUQ2F", 0]] },
  { wat: "a_f32_cmp.wat", groups: [["EqF", 0], ["NeF", 0], ["LtF", 0], ["LeF", 0], ["GtF", 0], ["GeF", 0]] },
  { wat: "a_f64_arith.wat", groups: [["AddD", 0], ["SubD", 0], ["MulD", 0], ["DivD", 0], ["NegD", 0]] },
  { wat: "a_f64_conv.wat", groups: [["CastI2D", 0], ["CastF2D", 0], ["CastD2I", 0], ["CastD2F", 0], ["CastU2D", 0], ["CastUQ2D", 0]] },
  { wat: "a_f64_cmp.wat", groups: [["EqD", 0], ["NeD", 0], ["LtD", 0], ["LeD", 0], ["GtD", 0], ["GeD", 0]] },
  { wat: "a_q_arith.wat", groups: [["AddQ", 0], ["SubQ", 0], ["MulQ", 0], ["DivQ", 0], ["ModQ", 0]] },
  { wat: "a_q_conv.wat", groups: [["CastI2Q", 0], ["CastQ2I", 0], ["CastQ2D", 0], ["CastD2Q", 0], ["CastD2UQ", 0], ["CastU2Q", 0]] },
  { wat: "a_q_cmp.wat", groups: [["EqQ", 0], ["NeQ", 0], ["LtQ", 0], ["LeQ", 0], ["GtQ", 0], ["GeQ", 0]] },
  { wat: "a_q_u.wat", groups: [["UDivQ", 0], ["UModQ", 0], ["ULtQ", 0], ["ULeQ", 0], ["UGtQ", 0], ["UGeQ", 0]] },
  { wat: "b_local.wat", groups: [["LoadLocal", 8], ["StoreLocal", 8], ["LoadLocalD", 8], ["StoreLocalD", 8], ["LoadLocalQ", 8], ["StoreLocalQ", 8]] },
  { wat: "b_global_int.wat", groups: [["LoadGlobal", 8], ["StoreGlobal", 8], ["StoreGlobalByte", 0], ["LoadGlobalByte", 0], ["LoadGlobalUByte", 0]] },
  { wat: "b_global_wide.wat", groups: [["LoadGlobalD", 0], ["StoreGlobalD", 0], ["LoadGlobalQ", 16], ["StoreGlobalQ", 16]] },
  { wat: "b_frame.wat", groups: [["GetFrameBase", 0], ["Dup", 0], ["Swap", 0]] },
  { wat: "b_mem_load.wat", groups: [["LoadMem", 0], ["LoadMemByte", 0], ["LoadMemUByte", 0], ["LoadMemD", 0], ["LoadMemQ", 0]] },
  { wat: "b_mem_store.wat", groups: [["StoreMem", 0], ["StoreMemByte", 0], ["StoreMemD", 0], ["StoreMemQ", 0]] },
  { wat: "b_split_alloc.wat", groups: [["SplitD", 0], ["SplitQ", 0], ["StackAlloc", 0]] },
  { wat: "b_memcpy.wat", groups: [["Memcpy", 0], ["Memset", 0]] },
  { wat: "b_overflow.wat", groups: [["Add", 0], ["Sub", 0], ["Mul", 0], ["Neg", 0], ["NegQ", 0], ["UNeg", 0], ["UNegQ", 0]] },
  { wat: "b_shift.wat", groups: [["Shl", 0], ["Shr", 0], ["LShr", 0], ["ShlQ", 0], ["ShrQ", 0], ["LShrQ", 0]] },
  { wat: "b_constpool.wat", groups: [["PushConstD", 0], ["PushConstD", 1], ["PushConstQ", 0], ["PushConstQ", 1], ["TruncUByte", 0]] },
  { wat: "b_obs.wat", groups: [["StepEvent", 0], ["TrapBounds", 0], ["TrapBounds", -3]] },
  { wat: "c_jump.wat", groups: [["Jump", 99], ["JumpIfZero", 42], ["JumpIfNotZero", 42]] },
  { wat: "c_call.wat", groups: [["Call", 5], ["CallPtr", 5], ["CallVar", 5], ["CallHost", 1007]] },
  { wat: "c_ret.wat", groups: [["Ret", 0], ["RetVoid", 0]] },
  { wat: "c_ambig_val.wat", groups: [["BitNot", 0], ["BitNotQ", 0], ["PushArgc", 0], ["PushArgv", 0]] },
];

/// 垫栈指令字节（与 witness_dump_wbtest 的垫栈约定一致）
const PUSHERS: Readonly<Record<string, ReadonlyArray<number>>> = {
  i: [0x41, 0x00],
  I: [0x42, 0x00],
  f: [0x43, 0x00, 0x00, 0x00, 0x00],
  d: [0x44, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
};

const hex = (bytes: ReadonlyArray<number>): string =>
  bytes.map((b) => b.toString(16).padStart(2, "0")).join(" ");

/// 跑 moon test 抓 witness dump 行（vitro 侧扁平字节真源）
export function collectDump(repoRoot: string): Map<string, { operand: number; pushes: string; drops: number; bytes: number[] }> {
  const out = execFileSync("moon", ["test", "-p", "wasmenc"], {
    cwd: path.join(repoRoot, "moonbit"),
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
    maxBuffer: 64 * 1024 * 1024,
  });
  const dump = new Map<string, { operand: number; pushes: string; drops: number; bytes: number[] }>();
  for (const line of out.split("\n")) {
    if (!line.startsWith("DUMP1B ")) continue;
    const m = line.match(/^DUMP1B (\S+) (-?\d+) (\S*) (\d+) ([0-9a-f]*)$/);
    if (m === null) throw new Error(`witness dump 行解析失败: ${line.slice(0, 80)}`);
    const op = m[1] as string;
    const operand = m[2] as string;
    const pushes = m[3] as string;
    const drops = m[4] as string;
    const hexStr = m[5] as string;
    const bytes: number[] = [];
    for (let i = 0; i < hexStr.length; i += 2) bytes.push(parseInt(hexStr.slice(i, i + 2), 16));
    dump.set(`${op}:${operand}`, { operand: Number(operand), pushes, drops: Number(drops), bytes });
  }
  return dump;
}

/// uleb 读值（返回 [值, 消费字节数]）
function readUleb(bytes: ReadonlyArray<number>, pos: number): [number, number] {
  let value = 0;
  let shift = 0;
  let i = pos;
  for (;;) {
    if (i >= bytes.length) throw new Error("uleb 越界");
    const b = bytes[i] as number;
    value |= (b & 0x7f) << shift;
    i += 1;
    if ((b & 0x80) === 0) return [value >>> 0, i - pos];
    shift += 7;
  }
}

/// 提取 wat 模块第一个函数体的指令区（含尾 end；跳过 locals 声明）
export function extractFirstBodyInstrs(moduleBytes: ReadonlyArray<number>): number[] {
  if (moduleBytes.length < 8) throw new Error("模块过短");
  let pos = 8;
  while (pos < moduleBytes.length) {
    const id = moduleBytes[pos] as number;
    const [size, hdrLen] = readUleb(moduleBytes, pos + 1);
    if (id === 10) {
      const bodyStart = pos + 1 + hdrLen;
      const [funcCount, c1] = readUleb(moduleBytes, bodyStart);
      if (funcCount < 1) throw new Error("code 段空");
      const [bodySize, b1] = readUleb(moduleBytes, bodyStart + c1);
      const bodyEnd = bodyStart + c1 + b1 + bodySize;
      let p = bodyStart + c1 + b1;
      const [localRuns, l1] = readUleb(moduleBytes, p);
      p += l1;
      for (let r = 0; r < localRuns; r += 1) {
        const [, n1] = readUleb(moduleBytes, p);
        p += n1 + 1; // n 个 uleb + 1 字节值类型
      }
      return moduleBytes.slice(p, bodyEnd);
    }
    pos += 1 + hdrLen + size;
  }
  throw new Error("无 code 段");
}

/// 构造单组期望段：block + 垫栈 + 模板字节 + drop×n + end
function buildGroupExpected(entry: { pushes: string; drops: number; bytes: ReadonlyArray<number> }): number[] {
  const out: number[] = [0x02, 0x40];
  for (const ch of entry.pushes) out.push(...(PUSHERS[ch] as number[]));
  out.push(...entry.bytes);
  for (let k = 0; k < entry.drops; k += 1) out.push(0x1a);
  out.push(0x0b);
  return out;
}

/// 构造期望指令区：各组段顺序拼接 + 函数级尾 end（wat 编译产物固有）
export function buildExpected(groups: ReadonlyArray<{ pushes: string; drops: number; bytes: ReadonlyArray<number> }>): number[] {
  const out: number[] = [];
  for (const g of groups) out.push(...buildGroupExpected(g));
  out.push(0x0b);
  return out;
}

/// 差异窗口 hex（组内偏移前后各 8 字节——长组（StackAlloc 58B 族）失败
/// 报告可读性：全段 dump 噪音大，窗口够定位）
function windowHex(bytes: ReadonlyArray<number>, at: number): string {
  const lo = Math.max(0, at - 8);
  const hi = Math.min(bytes.length, at + 9);
  const prefix = lo > 0 ? "…" : "";
  const suffix = hi < bytes.length ? "…" : "";
  return prefix + hex(bytes.slice(lo, hi)) + suffix;
}

/// 单 case 对拍（**逐组切片**——红返回首个差异描述，精确到组与组内偏移）。
/// 每组是独立断言单元：`groupNames`（可选）携带组名（`op(operand)` 形态），
/// 缺省以序号代名；组间独立定位 = 单文件多组的「逐个小单元」形态。
export function compareCase(
  watText: string,
  groups: ReadonlyArray<{ pushes: string; drops: number; bytes: ReadonlyArray<number> }>,
  wabtCompile: (wat: string) => number[],
  groupNames?: ReadonlyArray<string>,
): string | null {
  const got = extractFirstBodyInstrs(wabtCompile(watText));
  const nameOf = (gi: number): string =>
    groupNames !== undefined && groupNames[gi] !== undefined ? (groupNames[gi] as string) : `#${gi + 1}`;
  let off = 0;
  for (let gi = 0; gi < groups.length; gi += 1) {
    const seg = buildGroupExpected(groups[gi] as { pushes: string; drops: number; bytes: ReadonlyArray<number> });
    const label = `组 ${nameOf(gi)}（第 ${gi + 1}/${groups.length} 组）`;
    if (off + seg.length > got.length) {
      return `${label}：期望 ${seg.length} 字节但产物只剩 ${got.length - off} 字节（截断）——wabt=${hex(got.slice(off))} vs vitro=${hex(seg)}`;
    }
    for (let i = 0; i < seg.length; i += 1) {
      const b = got[off + i] as number;
      const w = seg[i] as number;
      if (b !== w) {
        return `${label}：组内偏移 ${i}——wabt=${windowHex(got.slice(off), i)} vs vitro=${windowHex(seg, i)}`;
      }
    }
    off += seg.length;
  }
  // 函数级尾 end（wat 编译产物固有——见 buildExpected）
  if (off >= got.length || (got[off] as number) !== 0x0b) {
    return `尾部：函数级 end 失配——产物剩 ${got.length - off} 字节 ${windowHex(got, off)}`;
  }
  if (off + 1 !== got.length) {
    return `尾部：end 后多 ${got.length - off - 1} 字节——${windowHex(got, off + 1)}`;
  }
  return null;
}

async function loadWabt(): Promise<(wat: string) => number[]> {
  const wabtInit = (await import("wabt")).default;
  const wabt = await wabtInit();
  return (wat: string) => {
    const mod = wabt.parseWat("case.wat", wat, {});
    const bin = mod.toBinary({});
    return Array.from(bin.buffer as Uint8Array);
  };
}

export async function main(): Promise<number> {
  const repoRoot = path.resolve(scriptDir, "..", "..");
  const dump = collectDump(repoRoot);
  if (dump.size !== 150) throw new Error(`witness dump 应 150 行（A 84 + B/C 63 + 双形态 3），实得 ${dump.size}`);
  const compile = await loadWabt();
  let pass = 0;
  let fail = 0;
  const covered = new Set<string>();
  for (const c of CASES) {
    const groups = [];
    const groupNames = [];
    for (const [op, operand] of c.groups) {
      const entry = dump.get(`${op}:${operand}`);
      if (entry === undefined) throw new Error(`dump 缺 ${op}(${operand})`);
      groups.push(entry);
      groupNames.push(`${op}(${operand})`);
      covered.add(`${op}:${operand}`);
    }
    const watText = readFileSync(path.join(scriptDir, "cases", c.wat), "utf8");
    const diff = compareCase(watText, groups, compile, groupNames);
    if (diff === null) {
      pass += 1;
      console.log(`PASS ${c.wat} ↔ ${groupNames.join(" + ")}`);
    } else {
      fail += 1;
      console.log(`FAIL ${c.wat}：${diff}`);
    }
  }
  // 覆盖对账（J9 面）：witness dump 全量条目（150 = 147 可发射 + 双形态）
  // 必须逐条被某 wat 小单元覆盖——新增可发射 opcode 不配 wat 用例即红、
  // 删条目不撤用例即红（反向由 dump 缺条目 throw 锁）。cases↔dump 双向
  // 对账 = 「每条码表条目都有 .wat 小单元测试」的机检形态。
  const missing = [...dump.keys()].filter((k) => !covered.has(k));
  if (missing.length > 0) {
    console.error(`覆盖对账红：${missing.length} 条 dump 条目无 wat 用例（每条可发射条目须有 .wat 小单元——新增即配、删除即撤）：`);
    for (const k of missing) console.error(`  - ${k}`);
    return 1;
  }
  const groupCount = CASES.reduce((n, c) => n + c.groups.length, 0);
  console.log(`wasmenc watcheck: ${pass} PASS / ${fail} FAIL（${CASES.length} 文件 / ${groupCount} 组次 / 覆盖对账 ${covered.size}/${dump.size} 全量）`);
  return fail === 0 ? 0 : 1;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  process.exit(await main());
}
