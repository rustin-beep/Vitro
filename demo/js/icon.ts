// Vitro demo · 语义图标渲染单源（#27 方案 C 消费端，2026-10-07）。
// 本地表优先（拍板）：渲染一律用内置 ICONS（scripts/gen_icons -demo 产），
// icons.get 帧只做 digest 对拍——不一致 = 版本漂移信号，console.warn 不回退。
// trap 文案 [id] 徽章同理走本地表；ICONS[id] 缺项（引擎新 id 本地未更新）
// 降级为文本 id 徽章，不空白不报错。
"use strict";

import { ICONS } from "./icons.ts";

/** 单枚图标（内联 SVG；size = 像素边长，描边按 1.8×S/24 契约换算）。 */
export function iconSvg(id: string, size = 22): string {
  const body = ICONS[id];
  if (!body) return `<span class="icon-missing">[${id}]</span>`;
  const sw = ((1.8 * size) / 24).toFixed(2);
  return `<svg class="icon-svg" width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="${sw}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${body}</svg>`;
}

/**
 * trap 文案徽章装饰：已 esc 文本中的 `[语义 id]` 换内联 SVG。
 * 白名单由 ICONS 键集判定——C 代码示例里的 `[0]`、`[i]` 等原样保留。
 */
export function decorateBadges(escaped: string): string {
  return escaped.replace(/\[([a-z][a-z0-9-]*)\]/g, (m, id: string) =>
    ICONS[id] ? iconSvg(id, 20) : m,
  );
}
