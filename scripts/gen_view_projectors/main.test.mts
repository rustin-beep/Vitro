#!/usr/bin/env node
// gen_view_projectors 白盒锚（#273 四件套）：真源完备性 / 双产物同源 / 判定面证红。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { spawnSync } from "node:child_process";
import { projectRoot } from "../internal/capi.mts";
import {
  parseDoc,
  load,
  renderMoonBit,
  renderTs,
  verify,
  SRC_PATH,
  MBT_PATH,
  TS_PATH,
} from "./main.mts";

const root = projectRoot();
const DIGEST = crypto.createHash("sha256").update(fs.readFileSync(path.join(root, SRC_PATH))).digest("hex");

function idsOf(text: string): string[] {
  return [...text.matchAll(/^    id: "([a-z0-9_]+)",$/gm)].map((m) => m[1] as string);
}

const minimal = (): Record<string, unknown> =>
  JSON.parse(
    JSON.stringify({
      version: 1,
      default: "cells",
      projectors: [
        { id: "cells", seriesMin: 1, seriesMax: 1, minDims: 0, opts: [], note: "索引格" },
      ],
    }),
  ) as Record<string, unknown>;

test("真源：全族枚举 + 默认投影器 + id 字节序", () => {
  const doc = load(path.join(root, SRC_PATH));
  assert.equal(doc.version, 1);
  assert.equal(doc.default, "cells");
  // 全族枚举（禁抽样）：新增投影器不改此锚即红。
  assert.deepEqual(
    doc.projectors.map((p) => p.id),
    ["bars", "cells", "grid2d", "line", "polar", "spectrum"],
  );
  const polar = doc.projectors.find((p) => p.id === "polar");
  assert.deepEqual(
    [polar?.seriesMin, polar?.seriesMax, polar?.minDims, polar?.opts],
    [2, 2, 0, ["group", "gain"]],
  );
  const grid = doc.projectors.find((p) => p.id === "grid2d");
  assert.equal(grid?.minDims, 2, "grid2d 须有 dims");
  assert.equal(doc.projectors.find((p) => p.id === "line")?.seriesMax, -1, "line 条数不限");
});

test("parseDoc：完备性负例 fail loud（未知字段 / 版本 / 重复 / 越界 / 默认不在表）", () => {
  assert.throws(() => parseDoc(null), /顶层须为对象/);
  const bad = (mut: (d: Record<string, unknown>) => void, re: RegExp): void => {
    const d = minimal();
    mut(d);
    assert.throws(() => parseDoc(d), re);
  };
  bad((d) => { d.extra = 1; }, /未知顶层字段/);
  bad((d) => { d.version = 2; }, /版本须为 1/);
  bad((d) => { d.default = "nope"; }, /不在词表内/);
  bad((d) => { d.projectors = []; }, /非空数组/);
  bad((d) => {
    const p = (d.projectors as Record<string, unknown>[])[0]!;
    p.extra = 1;
  }, /未知字段/);
  bad((d) => {
    d.projectors = [(d.projectors as unknown[])[0], (d.projectors as unknown[])[0]];
  }, /id 重复/);
  bad((d) => {
    const p = (d.projectors as Record<string, unknown>[])[0]!;
    p.seriesMin = 0;
  }, /seriesMin 须 ≥1/);
  bad((d) => {
    const p = (d.projectors as Record<string, unknown>[])[0]!;
    p.seriesMax = -2;
  }, /seriesMax/);
  bad((d) => {
    const p = (d.projectors as Record<string, unknown>[])[0]!;
    p.opts = ["Bad-Key"];
  }, /opts 键须为合法键名/);
  bad((d) => {
    const p = (d.projectors as Record<string, unknown>[])[0]!;
    p.note = "  ";
  }, /note 须非空/);
  assert.equal(parseDoc(minimal()).projectors.length, 1, "合法最小真源仍绿");
});

test("双产物：确定性 + 同源同 id 集 + digest 一致", () => {
  const doc = load(path.join(root, SRC_PATH));
  const mbt = renderMoonBit(doc, DIGEST);
  const ts = renderTs(doc, DIGEST);
  assert.equal(renderMoonBit(doc, DIGEST), mbt, "MoonBit 产物确定");
  assert.equal(renderTs(doc, DIGEST), ts, "TS 产物确定");
  assert.deepEqual(idsOf(mbt), idsOf(ts), "两产物投影器 id 全族相等");
  assert.equal(idsOf(mbt).length, 6);
  assert.ok(mbt.includes(`digest sha256:${DIGEST}`));
  assert.ok(ts.includes(`PROJECTOR_DIGEST = "sha256:${DIGEST}"`));
  assert.ok(mbt.includes("Int32"), "MoonBit 产物须是 fmt 稳定形态（Int 会被 fmt 改写）");
  assert.ok(ts.includes("export type ProjectorId"), "TS 产物发射 id union");
});

test("verify：同集绿 / 篡改红 / CRLF 归一（判定面与自证面同一）", () => {
  const doc = load(path.join(root, SRC_PATH));
  const want = renderMoonBit(doc, DIGEST);
  assert.equal(verify(MBT_PATH, want, want), null);
  assert.equal(verify(MBT_PATH, want, want.replace(/\n/g, "\r\n")), null, "CRLF 不假红");
  const tampered = want.replace('    series_min: 1,', '    series_min: 9,');
  assert.notEqual(tampered, want);
  assert.ok(verify(MBT_PATH, want, tampered) !== null);
});

test("-check 从 scripts/ 目录 spawn 仍绿（判定面不依赖调用者 cwd）", () => {
  // 批 D 实测：产物按相对路径读时，npm test 从 scripts/ 跑会把 -check 判成
  // ENOENT 假红。三个生成器已在 check() 统一按 projectRoot() 解析。
  const main = path.join(root, "scripts/gen_view_projectors/main.mts");
  const r = spawnSync(process.execPath, [main, "-check"], {
    cwd: path.join(root, "scripts"),
    encoding: "utf8",
  });
  assert.equal(r.status, 0, `${r.stdout ?? ""}${r.stderr ?? ""}`);
});

test("入库产物与真源逐字节对账（-check 的等价进程内断言）", () => {
  const doc = load(path.join(root, SRC_PATH));
  assert.equal(fs.readFileSync(path.join(root, MBT_PATH), "utf8"), renderMoonBit(doc, DIGEST));
  assert.equal(fs.readFileSync(path.join(root, TS_PATH), "utf8"), renderTs(doc, DIGEST));
});
