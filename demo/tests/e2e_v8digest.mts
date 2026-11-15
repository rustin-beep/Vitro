// E2E V8 digest 锚（批②-5，2026-11-14）：浏览器 V8 宿主盲区收口——
// gates-wasm 的 wasm 臂跑在 node 的 V8 上（.node-version 单点），demo E2E
// 的浏览器 V8（runner 镜像 Chrome 随版本漂移）此前只有 UI 锚、零引擎行为
// 对拍（js-string builtins 等版本敏感面在两个 V8 域之间无判别）。
//
// 形态：**同一 gateway wasm 产物 × 同三语料 × 同 invoke 序列**，node V8
// 侧（本进程）与 Chrome V8 侧（CDP 页内）各算帧 digest（sha256），逐字节
// 相等才绿。装配逻辑两端手写同构（10 行——枚举 "_" 常量 + options 编译，
// 与 scripts/wasm_load.mts 单源声明同款；不从 wasm_load import 是刻意的：
// 两端逻辑必须逐行对称，digest 的判别力才唯一归于 V8 版本差异）。
//
// 判别门量（防假绿）：三语料 digest 互异——compile 面全崩时三行错误帧
// digest 相同，互异断言先红。
//
// 用法：E2E 体系内（静态服 + headless Chrome 起好后）：
//   node tests/e2e_v8digest.mts http://127.0.0.1:8931/
// 前置：demo/wasm.wasm 就位（构建期资产 cp，E2E 主步同款）。
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { connectCdp } from "./cdp.mts";

const BASE = process.argv[2] ?? "http://127.0.0.1:8931/";

// 三语料判别面：算术 / 循环累加 / 字符串直出
const SOURCES = [
  'int main(){int a=3;int b=4;printf("%d",a*b+1);return 0;}',
  'int main(){int s=0;for(int i=1;i<=5;i++)s+=i;printf("%d",s);return 0;}',
  'int main(){printf("vitro-v8");return 0;}',
];

/** invoke 序列（compile→run→output.delta stdout）——两端同构的唯一真源（字符串模板注入页内）。 */
const RUNNER_JS = `
  async function digestInPage(sources) {
    const buf = await (await fetch(${JSON.stringify(BASE + "wasm.wasm")})).arrayBuffer();
    // 装配（与 node 侧对称）：枚举 "_" 常量 + options 编译（js-string builtins）
    const bare = new WebAssembly.Module(buf);
    const consts = {};
    for (const imp of WebAssembly.Module.imports(bare)) {
      if (imp.module === "_") consts[imp.name] = imp.name;
    }
    const mod = new WebAssembly.Module(buf, { builtins: ["js-string"], importedStringConstants: "_" });
    const inst = await WebAssembly.instantiate(mod, { _: consts });
    const g = inst.exports;
    const lines = [];
    for (const src of sources) {
      g.reset();
      lines.push(g.invoke(JSON.stringify({ id: 1, method: "compile", params: { source: src } })));
      lines.push(g.invoke(JSON.stringify({ id: 2, method: "run", params: {} })));
      lines.push(g.invoke(JSON.stringify({ id: 3, method: "output.delta", params: { cursor: 0, stream: "stdout" } })));
    }
    const text = lines.join("\\n");
    const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
    return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
  }
`;

function sha256(s: string): string {
  return createHash("sha256").update(s, "utf8").digest("hex");
}

async function main(): Promise<number> {
  // ── node V8 侧基准（装配与页内 RUNNER_JS 逐行对称）──
  const buf = readFileSync(new URL("../wasm.wasm", import.meta.url));
  const bare = new WebAssembly.Module(buf);
  const consts: Record<string, string> = {};
  for (const imp of WebAssembly.Module.imports(bare)) {
    if (imp.module === "_") consts[imp.name] = imp.name;
  }
  // TS lib 的 Module 构造签名不含 V8 扩展选项——收窄一次（scripts/wasm_load.mts 同款）
  const ModuleWithOptions = WebAssembly.Module as unknown as new (
    buf: BufferSource,
    options: { builtins: string[]; importedStringConstants: string },
  ) => WebAssembly.Module;
  const mod = new ModuleWithOptions(buf, { builtins: ["js-string"], importedStringConstants: "_" });
  const inst = await WebAssembly.instantiate(mod, { _: consts } as unknown as WebAssembly.Imports);
  const g = inst.exports as unknown as {
    reset(): void;
    invoke(line: string): string;
  };
  const lines: string[] = [];
  for (const src of SOURCES) {
    g.reset();
    lines.push(g.invoke(JSON.stringify({ id: 1, method: "compile", params: { source: src } })));
    lines.push(g.invoke(JSON.stringify({ id: 2, method: "run", params: {} })));
    lines.push(g.invoke(JSON.stringify({ id: 3, method: "output.delta", params: { cursor: 0, stream: "stdout" } })));
  }
  const nodeDigestAll = sha256(lines.join("\n"));
  // 互异门量：逐语料 digest（compile 帧单独）——全崩形态下三者相同即红
  const perSource = SOURCES.map((src) => sha256(g.invoke(JSON.stringify({ id: 1, method: "compile", params: { source: src } }))));
  if (perSource[0] === perSource[1] || perSource[1] === perSource[2]) {
    console.error(`e2e_v8digest: 判别门量红——三语料 compile digest 互同（compile 面全崩假形态）：${perSource.join(",")}`);
    return 1;
  }

  // ── Chrome V8 侧（CDP 页内——E2E 主步已起 Chrome 9222 + 静态服）──
  const cdp = await connectCdp();
  // evaluate 内建 awaitPromise：RUNNER_JS 是 async 函数声明，IIFE 直呼返回 digest
  const pageDigest = await cdp.evaluate<string>(
    `(async () => { ${RUNNER_JS} return await digestInPage(${JSON.stringify(SOURCES)}); })()`,
  );
  cdp.close();
  console.log(`node  V8 digest: ${nodeDigestAll}`);
  console.log(`chrome V8 digest: ${pageDigest}`);
  if (nodeDigestAll !== pageDigest) {
    console.error("e2e_v8digest: 红——同产物同序列的 wasm-gc 帧流在 node V8 与 Chrome V8 分叉（版本异构面，先查 runner Chrome 的 V8 版本与 .node-version 差）");
    return 1;
  }
  console.log(`e2e_v8digest: 绿——浏览器 V8 ≡ node V8（三语料 9 帧序列 digest 一致）`);
  return 0;
}

process.exit(await main());
