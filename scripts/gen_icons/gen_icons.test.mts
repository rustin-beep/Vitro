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

test("真实仓库：-check 通过（与 CI 同门径）", () => {
  const r = spawnSync(process.execPath, [path.join(import.meta.dirname, "main.mts"), "-check"], {
    cwd: projectRoot(),
    encoding: "utf8",
  });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /OK：几何层与真源一致/);
});
