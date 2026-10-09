// Vitro demo · 链接分享（2026-10-09 批）：编辑器内容 → URL # 片段 → 朋友点开即还原。
//
// 形态与理由（用户拍板 + 实测口径，细节见 demo/README「链接分享」节）：
// - **零后端**：代码只活在链接的 # 片段里（# 不参与 HTTP 请求）⇒ 不破
//   README 既有的「零后端 / 页面本体不发第三方请求」声明。
// - **压缩用浏览器原生** CompressionStream/DecompressionStream("deflate-raw")
//   ——本页浏览器底线（Chrome/Edge 130+、Firefox 134+）远超过该 API 可用点
//   （103/113+），零新依赖、零 polyfill；实测源码 deflate 后 base64url 只有
//   源码的 0.4~0.9 倍（<300 字符的小片段才会更长，见 README 表格）。
// - **载荷只装源码**：版本 tag + base64url(deflate-raw(utf8(source)))，不含
//   步号/断点/课程 id 等运行上下文——2026-10-09 用户拍板「那是无关信息」，
//   少装一个字段就是少几十个字符。
// - **不花载荷买校验和**：DEFLATE 流被截断必然解压失败（实测 17 份用例 ×
//   4 个截断比 + 尾部少 1 字节 = 85 例全抛错），故截断由解压失败兜住，
//   无需额外校验字节。**未做形式化证明，是实测口径**（README 记同样边界）。
// - **不自动运行**：链接内容是不可信输入，只填编辑器，点了「运行」才编译。
"use strict";

import { $, setStatus } from "./util.ts";
import { renderEditorDecor } from "./editor.ts";

/** 载荷版本 tag（片段最前面）。不认识的版本明确拒绝——禁静默退回默认示例。 */
export const SHARE_VERSION = "z1";
const VERSION_SEP = ".";

/** 链接长度告警阈值（字符）。依据：实测源码 deflate+base64url 后只有源码的
 *  0.4~0.9 倍，教学片段（≤ 几千字节）稳定落在 2000 字符内；越过 8000 说明
 *  分享的是大文件，聊天工具/二维码多半会截断——此时**仍然出链接**，但状态
 *  提示明确说「换个方式发」，不静默给出一条会烂掉的链接。 */
export const SHARE_URL_WARN = 8000;

/** 链接过长的提示语（空串 = 无告警）。纯函数，便于 node --test 锚定。 */
export function urlLenWarning(urlLen: number): string {
  return urlLen > SHARE_URL_WARN ? `——已超 ${SHARE_URL_WARN} 字符，聊天工具多半会截断，建议改发 .c 文件` : "";
}

// ── 纯函数面（node --test 锚定；不触 DOM）────────────────────

/** Uint8Array → base64url（无 padding）。btoa 只吃 latin1，故逐字节折字符串。 */
export function bytesToB64url(bytes: Uint8Array): string {
  let bin = "";
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** base64url → Uint8Array；空载荷 / 非法字符 / 长度 %4==1 一律抛（fail loud）。 */
export function b64urlToBytes(s: string): Uint8Array<ArrayBuffer> {
  if (s.length === 0) throw new Error("载荷为空");
  if (!/^[A-Za-z0-9_-]+$/.test(s)) throw new Error("载荷含 base64url 之外的字符");
  const rem = s.length % 4;
  if (rem === 1) throw new Error("载荷长度非法（%4==1 不可能是 base64 输出）");
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat(rem === 0 ? 0 : 4 - rem);
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

/** 拼分享链接：剥掉已有 # 片段再挂新片段（连点分享不叠加、不产生双 #）。 */
export function shareUrlFrom(href: string, fragment: string): string {
  return href.split("#")[0] + "#" + fragment;
}

/** # 片段解析三态（不含前导 #）。 */
export type FragmentParse =
  | { kind: "none" } // 无片段 = 正常首访
  | { kind: "bad"; reason: string } // 有片段但不认识/不完整 = 链接被截断或损坏
  | { kind: "payload"; payload: string };

/** 解析 # 片段。**判据刻意分三层**：无片段 = 首访（静默继续）；有片段但
 *  版本前缀不对 = 截断/损坏（明确报错——半截链接最危险，朋友会拿到一段
 *  看似正常的默认页面而不知道代码丢了）；前缀对但载荷非法 = 同样报错。 */
export function parseFragment(fragment: string): FragmentParse {
  if (!fragment) return { kind: "none" };
  const i = fragment.indexOf(VERSION_SEP);
  if (i <= 0) return { kind: "bad", reason: "片段缺少版本前缀" };
  const ver = fragment.slice(0, i);
  if (ver !== SHARE_VERSION) {
    return { kind: "bad", reason: `不认识的片段版本「${ver}」（本页只认 ${SHARE_VERSION}）` };
  }
  const payload = fragment.slice(i + 1);
  if (!payload) return { kind: "bad", reason: "版本前缀后没有载荷" };
  return { kind: "payload", payload };
}

/** 源码 → 片段（"z1.<base64url>"）。 */
export async function packSource(source: string): Promise<string> {
  return SHARE_VERSION + VERSION_SEP + bytesToB64url(await deflateRaw(source));
}

/** 片段载荷 → 源码（解压失败/编码非法照抛——截断即在此被兜住）。 */
export async function unpackSource(payload: string): Promise<string> {
  return inflateRaw(b64urlToBytes(payload));
}

/** ReadableStream<Uint8Array> → 单块字节（reader 循环而非 Response 包装：
 *  语义最直接，且与 node --test 下同一实现）。 */
async function collect(stream: ReadableStream<Uint8Array>): Promise<Uint8Array<ArrayBuffer>> {
  const reader = stream.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    if (value && value.length) {
      chunks.push(value);
      total += value.length;
    }
  }
  const out = new Uint8Array(total);
  let off = 0;
  for (const c of chunks) {
    out.set(c, off);
    off += c.length;
  }
  return out;
}

/** 把一块字节灌进 TransformStream 并取回输出。**读侧与写侧必须并行 await**：
 *  写侧先出错时若只 await 写侧，读侧的 rejection 会变成未处理拒绝（node --test
 *  直接判整条测试红——2026-10-09 截断锚首跑实测踩到）。 */
async function runStream(
  stream: { readable: ReadableStream<Uint8Array>; writable: WritableStream<BufferSource> },
  bytes: BufferSource,
): Promise<Uint8Array<ArrayBuffer>> {
  const done = collect(stream.readable);
  const w = stream.writable.getWriter();
  const written = (async () => {
    await w.write(bytes);
    await w.close();
  })();
  const [out] = await Promise.all([done, written]);
  return out;
}

/** utf8 文本 → deflate-raw 字节（浏览器与 node ≥18 同 API）。 */
export async function deflateRaw(text: string): Promise<Uint8Array<ArrayBuffer>> {
  return runStream(new CompressionStream("deflate-raw"), new TextEncoder().encode(text));
}

/** deflate-raw 字节 → utf8 文本；流被截断/损坏必然抛（截断检测的承担方）。 */
export async function inflateRaw(bytes: Uint8Array<ArrayBuffer>): Promise<string> {
  const out = await runStream(new DecompressionStream("deflate-raw"), bytes);
  return new TextDecoder("utf-8", { fatal: true }).decode(out);
}

// ── 页面挂接面 ─────────────────────────────────────────────

/** 是否具备所需浏览器能力（本页底线浏览器必然有；缺失时 fail loud 不静默）。 */
export function shareSupported(): boolean {
  return typeof CompressionStream === "function" && typeof DecompressionStream === "function";
}

async function copyText(text: string): Promise<boolean> {
  try {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      await navigator.clipboard.writeText(text);
      return true;
    }
  } catch {
    /* 权限被拒 / 非安全上下文 → 落回手动复制（链接条常驻可见） */
  }
  return false;
}

function showShareRow(url: string, sourceLen: number): void {
  $<HTMLInputElement>("share-url").value = url;
  $("share-len").textContent = `${sourceLen} 字符源码 → 链接 ${url.length} 字符`;
  $("share-row").classList.remove("hidden");
}

/** 复制当前链接条内容（复制按钮入口——不重新编码）。 */
async function copyCurrent(): Promise<void> {
  const out = $<HTMLInputElement>("share-url");
  if (!out.value) return;
  out.focus();
  out.select();
  const ok = await copyText(out.value);
  setStatus(ok ? "ok" : "busy", ok
    ? `链接已复制（${out.value.length} 字符）`
    : `剪贴板不可用——链接已选中，按 Ctrl+C 复制`);
}

/** 分享：编辑器当前内容 → 压缩 → 链接（写剪贴板 + 常驻链接条）。 */
export async function doShare(): Promise<void> {
  const src = $<HTMLTextAreaElement>("editor").value;
  if (!src.trim()) {
    setStatus("err", "编辑器是空的——没有可分享的代码");
    return;
  }
  if (!shareSupported()) {
    setStatus("err", "本浏览器不支持 CompressionStream —— 无法生成分享链接");
    return;
  }
  let url: string;
  try {
    url = shareUrlFrom(location.href, await packSource(src));
  } catch (e) {
    setStatus("err", "生成分享链接失败：" + (e instanceof Error ? e.message : String(e)));
    return;
  }
  showShareRow(url, src.length);
  const warn = urlLenWarning(url.length);
  const ok = await copyText(url);
  if (!ok) {
    const out = $<HTMLInputElement>("share-url");
    out.focus();
    out.select();
  }
  const head = ok ? "分享链接已复制" : "链接已生成，剪贴板不可用——按 Ctrl+C 复制链接条内容";
  const kind = ok ? (warn ? "err" : "ok") : "busy";
  setStatus(kind, `${head}（${url.length} 字符）${warn}`);
}

/** 消费 # 片段（boot 调用）：命中则填编辑器并返回 true。
 *  **不自动运行**——链接内容是不可信输入，只落到编辑器，点了「运行」才编译。 */
export async function applySharedSource(): Promise<boolean> {
  const parsed = parseFragment(location.hash.replace(/^#/, ""));
  if (parsed.kind === "none") return false;
  if (parsed.kind === "bad") {
    setStatus("err", `分享链接不完整（${parsed.reason}）——请让朋友重新复制一次完整链接`);
    return false;
  }
  let src: string;
  try {
    src = await unpackSource(parsed.payload);
  } catch {
    setStatus("err", "分享链接不完整（载荷解压失败）——请让朋友重新复制一次完整链接");
    return false;
  }
  $<HTMLTextAreaElement>("editor").value = src;
  renderEditorDecor();
  $("case-blurb").textContent = "已从分享链接载入代码（链接只带源码，不带任何运行上下文）";
  setStatus("ok", `已载入分享代码（${src.length} 字符）`);
  return true;
}

/** 挂接（app boot 调用一次）。 */
export function initShare(): void {
  $("share-btn").onclick = () => void doShare();
  $("share-copy").onclick = () => void copyCurrent();
}
