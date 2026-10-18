// calltreeLayout —— 调用树布局纯函数（F4 组件迁移，审阅 C-P1-2 处方）：
// 旧栈 layout() 就地改写共享树模型（w/x/_x/_y 写进跨帧存活的 TreeNode），
// 不可缓存不可测；此处返回全新结构、输入零污染，可按引用记忆化/快照测试。
// 布局语义对齐旧栈（叶位归一、父=首尾子均值、NW/NH/VGAP/PAD 同值）。
"use strict";

import type { TreeNode } from "../../js/calltree.ts";

export const NW = 78;
// 2026-10-18 前端改造：节点高/层距按设计稿 214px 画布收紧（28/28），
// 让 7 节点本课树在默认画布内完整 fit（fit-first 的物理前提）。
export const NH = 28;
export const VGAP = 28;
export const PAD = 18;

export interface LayoutNode {
  id: string; // DFS 序（keyed each 的 key）
  node: TreeNode;
  label: string; // 函数名（>9 截断）
  arg: string; // 首参 name=value（>10 截断；enterVars 首个 is_local）
  x: number;
  y: number;
}

export interface LayoutEdge {
  id: string;
  path: string; // 贝塞尔 d
  from: TreeNode;
  to: TreeNode;
}

export interface CallTreeLayout {
  nodes: LayoutNode[];
  edges: LayoutEdge[];
  width: number;
  height: number;
}

export function layoutCallTree(root: TreeNode | null): CallTreeLayout | null {
  if (!root) return null;
  const nodes: LayoutNode[] = [];
  const edges: LayoutEdge[] = [];
  const xUnit = new Map<TreeNode, number>(); // 叶位归一（0..minX）
  const w = new Map<TreeNode, number>();
  const depthOf = new Map<TreeNode, number>();
  let minX = 0;
  let maxDepth = 0;

  const layout = (node: TreeNode, depth: number): void => {
    depthOf.set(node, depth);
    if (depth > maxDepth) maxDepth = depth;
    if (!node.children.length) {
      w.set(node, 1);
      xUnit.set(node, minX);
      minX += 1;
      return;
    }
    let first = 0;
    let last = 0;
    node.children.forEach((c, ci) => {
      layout(c, depth + 1);
      if (ci === 0) first = xUnit.get(c)!;
      last = xUnit.get(c)!;
    });
    const total = node.children.reduce((s, c) => s + (w.get(c) ?? 0), 0);
    w.set(node, total);
    xUnit.set(node, (first + last) / 2);
  };
  layout(root, 0);

  const unitW = NW + 18;
  const width = PAD * 2 + minX * unitW;
  const height = PAD * 2 + (maxDepth + 1) * (NH + VGAP);
  const cx = (n: TreeNode): number => PAD + (xUnit.get(n) ?? 0) * unitW + unitW / 2;
  const cy = (n: TreeNode): number => PAD + (depthOf.get(n) ?? 0) * (NH + VGAP);

  let seq = 0;
  const emit = (node: TreeNode): void => {
    const x = cx(node);
    const y = cy(node);
    const v = (node.enterVars || []).find((x2) => x2.is_local);
    let arg = v ? `${v.name}=${v.value}` : "";
    if (arg.length > 10) arg = arg.slice(0, 9) + "…";
    const label = node.name.length > 9 ? node.name.slice(0, 8) + "…" : node.name;
    const id = `n${seq++}`;
    nodes.push({ id, node, label, arg, x, y });
    node.children.forEach((c) => {
      const mx = (y + NH / 2 + cy(c) - NH / 2) / 2;
      const path = `M${x},${y + NH / 2} C${x},${mx} ${cx(c)},${mx} ${cx(c)},${cy(c) - NH / 2}`;
      edges.push({ id: `${id}->${c.name}@${xUnit.get(c)}`, path, from: node, to: c });
      emit(c);
    });
  };
  emit(root);
  return { nodes, edges, width, height };
}
