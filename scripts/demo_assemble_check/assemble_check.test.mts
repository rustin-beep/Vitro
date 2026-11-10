// demo_assemble_check 单元面（#273 四件套：node:test）——四条判据的正反面。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { checkAssembly } from "./main.mts";

function fixture(html: string, files: Record<string, string>): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-assemble-"));
  fs.writeFileSync(path.join(dir, "index.html"), html);
  for (const [rel, content] of Object.entries(files)) {
    const p = path.join(dir, rel);
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(p, content);
  }
  return dir;
}

const HTML = [
  '<script type="module" src="cases.js"></script>',
  '<img src="logo.png">',
  '<link rel="icon" href="favicon.ico">',
  '<script src="https://cdn.example/x.js"></script>',
].join("\n");

function sourceFixture(extra: Record<string, string> = {}): string {
  return fixture(HTML, { "cases.js": "", "logo.png": "", "favicon.ico": "", "src/main.ts": "", ...extra });
}

test("源目录面：本地 ref 全在（外链不计）", () => {
  assert.deepEqual(checkAssembly(sourceFixture(), { noTs: false }), { refs: 3, noticesPkgs: 0 });
});

test("缺资源 fail loud（逐项点名）", () => {
  const dir = sourceFixture();
  fs.rmSync(path.join(dir, "logo.png"));
  assert.throws(() => checkAssembly(dir, { noTs: false }), /组装缺资源: logo\.png/);
});

test("抽取面退化 = 红（<script src> 零命中）", () => {
  const dir = fixture('<img src="logo.png">', { "logo.png": "", "src/main.ts": "" });
  assert.throws(() => checkAssembly(dir, { noTs: false }), /抽取面 0 < 1/);
});

test("源目录面缺入口 src/main.ts = 红", () => {
  const dir = fixture(HTML, { "cases.js": "", "logo.png": "", "favicon.ico": "" });
  assert.throws(() => checkAssembly(dir, { noTs: false }), /缺入口源 src\/main\.ts/);
});

// 判据 ④ fixture：一个合法包段（`── <name>@<version>`）即过内容非退化断言
const NOTICES = "── @x/y@1.2.3 ──────\nlicense: MIT\n\nMIT License text\n";

test("发布面 --no-ts：干净产物通过且不要求 src/main.ts", () => {
  const dir = fixture(HTML, {
    "cases.js": "",
    "logo.png": "",
    "favicon.ico": "",
    "THIRD-PARTY-NOTICES.txt": NOTICES,
  });
  assert.deepEqual(checkAssembly(dir, { noTs: true }), { refs: 3, noticesPkgs: 1 });
});

test("发布面 --no-ts：漏出 .ts 源 = 红", () => {
  const dir = fixture(HTML, { "cases.js": "", "logo.png": "", "favicon.ico": "", "src/x.ts": "" });
  assert.throws(() => checkAssembly(dir, { noTs: true }), /发布面含 TS 源.*src[/\\]x\.ts/);
});

test("发布面 --no-ts：缺 THIRD-PARTY-NOTICES.txt = 红（判据 ④）", () => {
  const dir = fixture(HTML, { "cases.js": "", "logo.png": "", "favicon.ico": "" });
  assert.throws(() => checkAssembly(dir, { noTs: true }), /发布面缺 THIRD-PARTY-NOTICES\.txt/);
});

test("发布面 --no-ts：notices 0 包段（内容退化）= 红（判据 ④）", () => {
  const dir = fixture(HTML, {
    "cases.js": "",
    "logo.png": "",
    "favicon.ico": "",
    "THIRD-PARTY-NOTICES.txt": "Vitro demo — third-party software notices\n(empty)\n",
  });
  assert.throws(() => checkAssembly(dir, { noTs: true }), /内容退化：0 个包段/);
});

test("源目录面不要求 notices（判据 ④ 仅挂发布面）", () => {
  assert.equal(checkAssembly(sourceFixture(), { noTs: false }).noticesPkgs, 0);
});
