// Vitro demo · 调用树（app.js 拆分批 2026-10-04，refs #28：单体 1370 行 →
// 模块化 ESM——零构建纪律不变，<script type="module"> 静态直开兼容；内容自
// app.js 逐字迁移，仅增 import/export。TS 重写批：签名类型化。）
"use strict";

import { $, esc } from "./util.ts";
import type { LocalVar, CallFrame, SemanticLabel } from "./types.ts";

/** 调用树节点（trie：路径增量挂靠——循环迭代同节点、返回后再调新兄弟）。 */
export interface TreeNode {
  name: string;
  parent: TreeNode | null;
  children: TreeNode[];
  depth: number;
  firstStep?: number;
  lastStep?: number;
  hitCount?: number;
  enterVars?: LocalVar[];
  enterLabel?: string;
  /** 布局/渲染派生（renderCallTree 写入） */
  w?: number;
  x?: number;
  _x?: number;
  _y?: number;
}

export interface CallTree {
  root: TreeNode;
  frameNode: (TreeNode | null)[];
}

// 调用树重建：call_stack 是「根到当前帧」的路径序列——按帧序走进/退事件
// 把路径增量挂成 trie（循环迭代不换栈帧 = 同节点；返回后再调 = 新兄弟节点）。
// frameNode[i] = 第 i 帧所在节点（播放高亮用）。
// buildCallTree 的入参消费面（2026-10-04 审阅 P3-④/tests 类型面）：只读本四
// 字段（local_vars/semantic_label 体内 || 兜底故可选）——StepPayload 结构
// 兼容可直传，测试 mock 只需造最小帧
export interface CallTreeFrame {
  step_index: number;
  call_stack: Array<Pick<CallFrame, "func_name">>;
  local_vars?: LocalVar[];
  semantic_label?: SemanticLabel;
}

export function buildCallTree(frames: CallTreeFrame[]): CallTree {
  const root: TreeNode = { name: "prog", parent: null, children: [], depth: 0 };
  let cur = root;
  let curPath: string[] = [];
  const frameNode: (TreeNode | null)[] = new Array(frames.length);
  frames.forEach((f, i) => {
    const path = (f.call_stack || []).map((c) => c.func_name);
    if (!path.length) { frameNode[i] = root; return; }
    let lcp = 0;
    while (lcp < path.length && lcp < curPath.length && path[lcp] === curPath[lcp]) lcp++;
    while (curPath.length > lcp) { curPath.pop(); cur = cur.parent as TreeNode; }
    while (curPath.length < path.length) {
      const node: TreeNode = { name: path[curPath.length], parent: cur, children: [], depth: curPath.length + 1, firstStep: f.step_index, enterVars: f.local_vars || [], enterLabel: f.semantic_label || "执行" };
      cur.children.push(node);
      cur = node;
      curPath.push(node.name);
    }
    cur.lastStep = f.step_index;
    cur.hitCount = (cur.hitCount || 0) + 1;
    frameNode[i] = cur;
  });
  return { root, frameNode };
}

/** 视图状态（缩放/平移/跟随；采集重置，用户交互后暂停跟随，双击恢复） */
export interface TreeViewState {
  k: number;
  tx: number;
  ty: number;
  follow: boolean;
  contentW?: number;
  contentH?: number;
}

export const treeView: TreeViewState = { k: 1, tx: 0, ty: 0, follow: true };

export function renderCallTree(root: TreeNode | null, curNode: TreeNode | null): void {
  if (!root) return;
  const NW = 78, NH = 36, VGAP = 42, PAD = 26;
  let maxDepth = 0;
  let minX = 0;
  function layout(node: TreeNode, depth: number): void {
    maxDepth = Math.max(maxDepth, depth);
    node.depth = depth;
    if (!node.children.length) {
      node.w = 1;
      node.x = minX;
      minX += 1;
      return;
    }
    let first: TreeNode | null = null, last: TreeNode | null = null;
    for (const c of node.children) {
      layout(c, depth + 1);
      if (!first) first = c;
      last = c;
    }
    node.w = node.children.reduce((s, c) => s + (c.w as number), 0);
    node.x = ((first as TreeNode).x as number + (last as TreeNode).x as number) / 2;
  }
  layout(root, 0);
  const unitW = NW + 18;
  const width = PAD * 2 + minX * unitW;
  const height = PAD * 2 + (maxDepth + 1) * (NH + VGAP);
  const cx = (node: TreeNode): number => PAD + (node.x as number) * unitW + unitW / 2;
  const cy = (node: TreeNode): number => PAD + node.depth * (NH + VGAP);
  const edgePath = (x1: number, y1: number, x2: number, y2: number): string => {
    const my = (y1 + y2) / 2;
    return `M${x1},${y1} C${x1},${my} ${x2},${my} ${x2},${y2}`;
  };
  const edges: string[] = [], nodes: string[] = [], dots: string[] = [];
  // 【TS 重写批注】原 shortArg 死函数已删（emit 内联 find 从未调它——
  //  noUnusedLocals 抓出；教学截断逻辑仍活在 emit 的 arg 段）
  (function emit(node: TreeNode, walkedPath: boolean): void {
    const x = cx(node), y = cy(node);
    node._x = x; node._y = y; // 供跟随居中定位
    node.children.forEach((c, ci) => {
      const walkedEdge = walkedPath && c.lastStep !== undefined;
      edges.push(`<path class="edge${walkedEdge ? " walked" : ""}" d="${edgePath(x, y + NH / 2, cx(c), cy(c) - NH / 2)}"/>`);
      if (walkedEdge) dots.push(`<circle class="dot" cx="${cx(c)}" cy="${cy(c) - NH / 2}" r="3"/>`);
      emit(c, walkedPath && walkedEdge);
    });
    const isCur = node === curNode;
    const isVisited = !isCur && node.lastStep !== undefined;
    const cls = isCur ? " cur" : isVisited ? " visited" : "";
    const v = (node.enterVars || []).find((x) => x.is_local);
    let arg = v ? `${v.name}=${v.value}` : "";
    if (arg.length > 10) arg = arg.slice(0, 9) + "…";
    const label = node.name.length > 9 ? node.name.slice(0, 8) + "…" : node.name;
    // 树面只保留 函数名 + 首参（信息卡常驻右上角、随帧刷新——树面零噪音）
    nodes.push(
      `<g class="nd${cls}">` +
      `<rect x="${x - NW / 2}" y="${y - NH / 2}" width="${NW}" height="${NH}" rx="9"/>` +
      `<text class="tname" x="${x}" y="${y - 1}">${esc(label)}</text>` +
      (arg ? `<text class="targ" x="${x}" y="${y + 12}">${esc(arg)}</text>` : "") +
      `</g>`
    );
  })(root, true);
  const host = $("step-tree");
  // 常驻信息卡（#node-card）不被覆盖——每帧只重建 svg
  const oldSvg = document.querySelector("#tree-svg"); // 每帧重建的动态元素
  if (oldSvg) oldSvg.remove();
  const ph = host.querySelector(":scope > span.muted"); // 静态占位文字（插入式渲染后残留会露在画布角落）
  if (ph) ph.remove();
  host.insertAdjacentHTML(
    "afterbegin",
    `<svg id="tree-svg" width="100%" height="340">` +
    `<g id="tree-viewport" transform="translate(0,0) scale(1)">` +
    edges.join("") + dots.join("") + nodes.join("") +
    `</g></svg>`
  );
  treeView.contentW = width;
  treeView.contentH = height;
  // 视图状态（k/tx/ty/follow）跨帧保留——每帧重建 DOM 但不重置用户的缩放平移；
  // 仅 k===0（新采集）时初始化：小树完整渲染居中，大树走「镜头跟随」模式
  if (!treeView.k) initTreeView(width, height, curNode);
  else {
    applyTreeView();
    if (treeView.follow && curNode) centerOnNode(curNode);
  }
  bindTreeView(width, height);
}

// 视图初始化：小树（fit ≥ 0.75）完整渲染居中不跟随；大树固定可读缩放，
// 当前事件节点为窗口重心（到哪帧镜头跟到哪，帧间 CSS 过渡平滑移动）
function initTreeView(width: number, height: number, curNode: TreeNode | null): void {
  const host = $("step-tree");
  const cw = host.clientWidth || 600;
  const fitK = Math.min(1, (cw - 8) / width);
  if (fitK >= 0.75) {
    treeView.k = fitK;
    treeView.tx = (cw - width * fitK) / 2;
    treeView.ty = 6;
    treeView.follow = false; // 全貌可见，无需跟随
  } else {
    treeView.k = 0.75;
    treeView.follow = true;
  }
  applyTreeView();
  if (treeView.follow && curNode) centerOnNode(curNode);
  bindTreeView(width, height);
}

function applyTreeView(): void {
  const g = document.querySelector("#tree-viewport"); // 动态生成元素，querySelector 检索
  if (g) g.setAttribute("transform", `translate(${treeView.tx},${treeView.ty}) scale(${treeView.k})`);
}

// 当前帧节点居中（跟随模式）：水平垂直都到画布重心，帧间由 CSS 过渡平滑
function centerOnNode(node: TreeNode | null): void {
  const host = $("step-tree");
  if (!host || !node || node._x === undefined) return;
  const cw = host.clientWidth || 600;
  const ch = host.clientHeight || 360;
  const dx = cw / 2 - (treeView.tx + node._x * treeView.k);
  if (Math.abs(dx) > 2) treeView.tx += dx;
  const dy = ch / 2 - (treeView.ty + node._y * treeView.k);
  if (Math.abs(dy) > 2) treeView.ty += dy;
  applyTreeView();
}

interface PinchState {
  dist: number;
  midX: number;
  midY: number;
  k: number;
  tx: number;
  ty: number;
}

interface DragState {
  x: number;
  y: number;
  tx: number;
  ty: number;
}

// 树画布交互：滚轮缩放（鼠标锚点）、拖拽平移（暂停跟随）、双击恢复适应+跟随
function bindTreeView(contentW: number, contentH: number): void {
  const svg = document.querySelector("#tree-svg") as SVGElement | null; // 动态生成元素
  // dataset.bound 防的是同一 svg 重复绑定；svg 每帧随 DOM 重建，新元素必须重绑
  if (!svg || svg.dataset.bound) return;
  svg.dataset.bound = "1";
  svg.style.touchAction = "none";
  svg.addEventListener("wheel", (e: WheelEvent) => {
    e.preventDefault();
    const rect = svg.getBoundingClientRect();
    const mx = e.clientX - rect.left, my = e.clientY - rect.top;
    const k2 = Math.max(0.12, Math.min(2.5, treeView.k * (1 - e.deltaY * 0.0012)));
    // 鼠标位置为锚：缩放前后该内容点保持在屏幕同处
    treeView.tx = mx - ((mx - treeView.tx) / treeView.k) * k2;
    treeView.ty = my - ((my - treeView.ty) / treeView.k) * k2;
    treeView.k = k2;
    treeView.follow = false;
    applyTreeView();
  }, { passive: false });
  // 双指 pinch 缩放（触屏）：touch-action:none 禁掉了浏览器原生 pinch，
  // 移动端缩放完全依赖此手势——双指距离比=缩放比，双指中点为锚
  const pointers = new Map<number, { x: number; y: number }>();
  let pinch: PinchState | null = null;
  let drag: DragState | null = null;
  svg.addEventListener("pointerdown", (e: PointerEvent) => {
    pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
    if (pointers.size === 2) {
      drag = null; // 进入 pinch：取消单指拖拽
      const [p1, p2] = Array.from(pointers.values());
      pinch = {
        dist: Math.hypot(p1.x - p2.x, p1.y - p2.y) || 1,
        midX: (p1.x + p2.x) / 2,
        midY: (p1.y + p2.y) / 2,
        k: treeView.k, tx: treeView.tx, ty: treeView.ty,
      };
      return;
    }
    drag = { x: e.clientX, y: e.clientY, tx: treeView.tx, ty: treeView.ty };
    const g = document.querySelector("#tree-viewport");
    if (g) g.classList.add("dragging"); // 拖拽无过渡
    svg.setPointerCapture(e.pointerId);
  });
  svg.addEventListener("pointermove", (e: PointerEvent) => {
    if (pointers.has(e.pointerId)) pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
    if (pinch && pointers.size >= 2) {
      const [p1, p2] = Array.from(pointers.values());
      const dist = Math.hypot(p1.x - p2.x, p1.y - p2.y) || 1;
      const k2 = Math.max(0.12, Math.min(2.5, (pinch.k * dist) / pinch.dist));
      const svgRect = svg.getBoundingClientRect();
      const ax = pinch.midX - svgRect.left, ay = pinch.midY - svgRect.top;
      treeView.tx = ax - ((ax - pinch.tx) / pinch.k) * k2;
      treeView.ty = ay - ((ay - pinch.ty) / pinch.k) * k2;
      treeView.k = k2;
      treeView.follow = false;
      applyTreeView();
      return;
    }
    if (!drag) return;
    treeView.tx = drag.tx + (e.clientX - drag.x);
    treeView.ty = drag.ty + (e.clientY - drag.y);
    treeView.follow = false;
    applyTreeView();
  });
  const endPointer = (e: PointerEvent): void => {
    pointers.delete(e.pointerId);
    if (pointers.size < 2) pinch = null;
    drag = null;
    const g = document.querySelector("#tree-viewport");
    if (g) g.classList.remove("dragging");
  };
  svg.addEventListener("pointerup", endPointer);
  svg.addEventListener("pointercancel", endPointer);
  svg.addEventListener("dblclick", () => {
    treeView.k = 0; // 触发重新初始化（小树完整渲染 / 大树镜头跟随）
    initTreeView(contentW, contentH, null);
  });
}
