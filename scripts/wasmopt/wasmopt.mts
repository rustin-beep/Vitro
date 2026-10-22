// wasmopt.mts —— binaryen JS API 优化执行器（scripts/wasmopt 驱动的 node 半边；#273 批 .mts 化）。
// 供给 = tools/cache/binaryen-<ver>/package（Go 驱动下载钉版本 + sha256 校验）。
// 特征位组合 = #120 实测可用集（GC|ReferenceTypes|Strings|BulkMemory|
// SignExt|MutableGlobals——Features.All 撞 exact heap type V8 拒收在案）。
// 等价性背书 = CI vm_diff wasm 臂全量 440 例 + vitro_cli_smoke 三臂对拍
// （本执行器不做行为对拍——防线职责分离）。
import { readFile, writeFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

interface BinaryenFeatures {
  GC: number;
  ReferenceTypes: number;
  Strings: number;
  BulkMemory: number;
  SignExt: number;
  MutableGlobals: number;
}

interface BinaryenModule {
  setOptimizeLevel(level: number): void;
  setShrinkLevel(level: number): void;
  optimize(): void;
  emitBinary(): Uint8Array;
}

interface BinaryenApi {
  Features: BinaryenFeatures;
  readBinary(data: Uint8Array, features: number): BinaryenModule;
}

export interface OptimizeResult {
  before: number;
  after: number;
}

export async function optimizeFile(inPath: string, outPath: string, binaryenDir: string): Promise<OptimizeResult> {
  const bmod = (await import(pathToFileURL(binaryenDir + "/index.js").href)) as BinaryenApi | { default?: BinaryenApi };
  const b = (bmod as { default?: BinaryenApi }).default ?? (bmod as BinaryenApi);
  const FEATURES =
    b.Features.GC |
    b.Features.ReferenceTypes |
    b.Features.Strings |
    b.Features.BulkMemory |
    b.Features.SignExt |
    b.Features.MutableGlobals;

  const original = await readFile(inPath);
  const mod = b.readBinary(original, FEATURES);
  try {
    mod.setOptimizeLevel(2);
    mod.setShrinkLevel(2);
  } catch {
    // 旧接口无 setter——默认等级即 -O2 同族（spike 实测形态）
  }
  mod.optimize();
  const out = Buffer.from(mod.emitBinary());
  await writeFile(outPath, out);
  return { before: original.length, after: out.length };
}

async function main(): Promise<void> {
  const [, , inPath, outPath, binaryenDir] = process.argv;
  if (!inPath || !outPath || !binaryenDir) {
    console.error("用法: node wasmopt.mts <in.wasm> <out.wasm> <binaryenDir>");
    process.exit(4);
  }
  const { before, after } = await optimizeFile(inPath, outPath, binaryenDir);
  console.log(`wasmopt.mts: ${inPath} -> ${outPath} (${before} -> ${after} B)`);
}

const invokedDirectly =
  process.argv[1] !== undefined &&
  pathToFileURL(process.argv[1]).href === import.meta.url;
if (invokedDirectly) {
  main().catch((e) => {
    console.error("[wasmopt.mts] 异常:", e);
    process.exit(2);
  });
}
