// 像素闸底层（demo/tests/visual/png.mjs）的纯函数锚（#222 P0 第三批）。
//
// 为什么要有：visual_regress 的判定全压在「解码 → 差分 → 掩膜」上，这三步错
// 会表现为「永远 PASS」（比永远红更危险）。这里用合成像素做 round-trip 与
// 边界锚，不依赖浏览器——CI 的 demo pure 步一起跑。
import { test } from "node:test";
import assert from "node:assert/strict";

import { decodePNG, encodePNG, diffRGBA, diffImage, maskRect } from "./png.mjs";

/** 合成 RGBA 图：按坐标填充可预测的颜色。 */
function makeImage(w: number, h: number, fn: (x: number, y: number) => [number, number, number, number]) {
  const data = Buffer.alloc(w * h * 4);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const [r, g, b, a] = fn(x, y);
      const i = (y * w + x) * 4;
      data[i] = r;
      data[i + 1] = g;
      data[i + 2] = b;
      data[i + 3] = a;
    }
  }
  return { width: w, height: h, data };
}

test("png：encode → decode 逐字节 round-trip（RGBA 8bit）", () => {
  const img = makeImage(7, 5, (x, y) => [(x * 31) & 0xff, (y * 47) & 0xff, (x * y * 13) & 0xff, 255]);
  const back = decodePNG(encodePNG(img));
  assert.equal(back.width, 7);
  assert.equal(back.height, 5);
  assert.deepEqual([...back.data], [...img.data]);
});

test("png：diffRGBA 同图 0 差、单像素变更定位到 bbox", () => {
  const a = makeImage(4, 3, () => [10, 20, 30, 255]);
  const zero = diffRGBA(a, a);
  assert.equal(zero.changed, 0);
  assert.equal(zero.ratio, 0);
  assert.equal(zero.bbox, null);

  const b = makeImage(4, 3, () => [10, 20, 30, 255]);
  const off = (2 * 4 + 1) * 4; // (x=1, y=2)
  b.data[off] = 11;
  const d = diffRGBA(a, b);
  assert.equal(d.changed, 1);
  assert.ok(Math.abs(d.ratio - 1 / 12) < 1e-12);
  assert.deepEqual(d.bbox, { x: 1, y: 2, w: 1, h: 1 });
});

test("png：diffRGBA 尺寸不一致 fail loud（不静默出 0 差）", () => {
  const a = makeImage(2, 2, () => [0, 0, 0, 255]);
  const b = makeImage(2, 3, () => [0, 0, 0, 255]);
  assert.throws(() => diffRGBA(a, b), /尺寸不一致/);
});

test("png：maskRect 只涂指定矩形（含越界钳制）", () => {
  const img = makeImage(4, 4, () => [255, 255, 255, 255]);
  maskRect(img, { x: -1, y: 1, w: 3, h: 2 }, 0x40);
  // (0,1) 与 (1,2) 在矩形内 → 0x40；(0,0) 不在 → 保持 255
  const at = (x: number, y: number) => img.data[(y * 4 + x) * 4];
  assert.equal(at(0, 1), 0x40);
  assert.equal(at(1, 2), 0x40);
  assert.equal(at(0, 0), 255);
  assert.equal(at(3, 3), 255); // 越界部分不写
});

test("png：差异图把变化像素涂成品红，其余转灰（视觉可读）", () => {
  const a = makeImage(3, 1, () => [0, 0, 0, 255]);
  const b = makeImage(3, 1, () => [0, 0, 0, 255]);
  b.data[1 * 4] = 255; // x=1 的 R 变
  const diff = diffImage(a, b);
  assert.equal(diff.width, 3);
  const px = (x: number) => [...diff.data.subarray(x * 4, x * 4 + 3)];
  assert.deepEqual(px(1), [255, 0, 128]); // 品红 = 变化
  assert.notDeepEqual(px(0), [255, 0, 128]); // 未变 = 灰
});
