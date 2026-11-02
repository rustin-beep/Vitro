// gen_icons.test.mts —— 图元抽取/坐标最短往返/几何层序列化/TSV 契约 + 真实 -check。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import crypto from "node:crypto";
import { spawnSync } from "node:child_process";
import { digestOf, extractPaths, marshalGeo, n, readTsv, renderDemoTs } from "./main.mts";
import { projectRoot } from "../internal/capi.mts";

test("n：1e-6 收敛 + 最短往返 + -0 归一", () => {
  assert.equal(n(20.099999999999998), "20.1");
  assert.equal(n(-0), "0");
  assert.equal(n(0), "0");
  assert.equal(n(2.5), "2.5");
  assert.equal(n(-10), "-10");
});

test("extractPaths：path 原样 / circle 双弧 / rect 四段闭合", () => {
  assert.deepEqual(extractPaths('<svg><path d="M0 0h24"/></svg>'), ["M0 0h24"]);
  assert.deepEqual(extractPaths('<circle cx="12" cy="12" r="5"/>'), ["M7 12a5 5 0 1 0 10 0a5 5 0 1 0 -10 0z"]);
  assert.deepEqual(extractPaths('<rect x="4" y="4" width="16" height="16"/>'), ["M4 4h16v16h-16 0z"]);
  assert.throws(() => extractPaths('<rect x="1" y="1" width="2" height="2" rx="1"/>'), /rect 带 rx/);
  assert.throws(() => extractPaths('<circle cx="1" cy="1"/>'), /缺属性 r/);
});

test("readTsv：5 列映射 category/scope；CRLF/短列 fail loud", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-icons-"));
  const p = path.join(dir, "index.tsv");
  fs.writeFileSync(p, "id\tcategory\tscope\temoji\tdesc\na\t词法\tcatalog\tx\t说明\n");
  assert.deepEqual(readTsv(p), new Map([["a", ["词法", "catalog"]]]));
  fs.writeFileSync(p, "id\tcategory\tscope\temoji\tdesc\r\na\tb\tc\td\te\r\n");
  assert.throws(() => readTsv(p), /CRLF/);
  fs.writeFileSync(p, "id\tcategory\tscope\temoji\tdesc\na\tb\n");
  assert.throws(() => readTsv(p), /列数不足/);
});

test("digestOf：id+NUL+svg+NUL 顺序摘要", () => {
  const byID = new Map([
    ["a", Buffer.from("<svg/>")],
    ["b", Buffer.from("<svg2/>")],
  ]);
  const expect = crypto.createHash("sha256").update("a\0<svg/>\0b\0<svg2/>\0", "latin1").digest("hex");
  assert.equal(digestOf(["a", "b"], byID), "sha256:" + expect);
});

test("marshalGeo：Go MarshalIndent 形态（键序/空字段/双尾换行）", () => {
  const geo = {
    schema: "icons/v1",
    digest: "sha256:x",
    viewBox: "0 0 24 24",
    stroke_width: 1.8,
    stroke_linecap: "round",
    stroke_linejoin: "round",
    fill: "none",
    scale_formula: "strokeWidth = 1.8 * S / 24",
    icons: new Map([["a", { title: "A", category: "", scope: "catalog", paths: ["M0 0"] }]]),
  };
  const out = marshalGeo(geo);
  assert.match(out, /"stroke_width": 1\.8,/);
  assert.match(out, /"category": "",/);
  assert.match(out, /"paths": \[\n        "M0 0"\n      \]/);
  assert.ok(out.endsWith("}\n\n"));
});

test("renderDemoTs：digest + body 片段表", () => {
  const out = renderDemoTs(["a"], new Map([["a", { title: "", category: "", scope: "", paths: ['M0 0"x'] }]]), "sha256:y");
  assert.match(out, /export const ICONS_DIGEST = "sha256:y";/);
  assert.match(out, /  "a": '<path d="M0 0"x"\/>',/);
});

test("S08-5（2026-11-01 审阅 v2）：renderDemoTs 单引号/反斜杠转义（demo ts 臂注入面封堵）", () => {
  // 修复前：d 含单引号时产出行 `'<path d="M0'+alert(1)+'"/>'` 被 JS 解析为
  // 字符串拼接（new Function 求值即执行）——当前资产靠字符集习惯挡住而非契约。
  const out = renderDemoTs(
    ["a"],
    new Map([["a", { title: "", category: "", scope: "", paths: ["M0 0'x\\y"] }]]),
    "sha256:y",
  );
  // 期望行：`  "a": '<path d="M0 0\'x\\y"/>',` —— 单引号与反斜杠均被转义
  assert.ok(out.includes(`  "a": '<path d="M0 0\\'x\\\\y"/>',`), `转义形态不符：${out}`);
});

test("真实仓库：-check 通过（与 CI 同门径）", () => {
  const r = spawnSync(process.execPath, [path.join(import.meta.dirname, "main.mts"), "-check"], {
    cwd: projectRoot(),
    encoding: "utf8",
  });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /OK：几何层与真源一致/);
});

test("S08-2（2026-11-01 审阅 v2）：-check 对 icons_gen.mbt 零写副作用（mtime+hash 不变）", () => {
  // 原实现「写产物 → moon fmt → 回读 → 还原」每跑一次 -check 必刷 mtime，扰动
  // gen_demo_algorithms 的 ensureFresh 构建复核链；fmt 失败窗口更把产物覆盖为
  // 未 fmt 模板（S08-1，剥离 moon 探针实锤 hash 变）。现形态 = 期望内容写系统
  // 临时目录 .mbtx 比对，仓库产物全程只读。本锚锁零写契约。
  const p = path.join(projectRoot(), "moonbit/icons/icons_gen.mbt");
  const h1 = crypto.createHash("md5").update(fs.readFileSync(p)).digest("hex");
  const m1 = fs.statSync(p).mtimeMs;
  const r = spawnSync(process.execPath, [path.join(import.meta.dirname, "main.mts"), "-check"], {
    cwd: projectRoot(),
    encoding: "utf8",
  });
  assert.equal(r.status, 0, r.stderr);
  const h2 = crypto.createHash("md5").update(fs.readFileSync(p)).digest("hex");
  assert.equal(h2, h1, "icons_gen.mbt 内容不得被 -check 改写");
  assert.equal(fs.statSync(p).mtimeMs, m1, "icons_gen.mbt 的 mtime 不得被 -check 刷新");
});
