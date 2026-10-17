// Vitro demo · 调用树（纯函数面——2026-10-17 F4 收尾：view 状态与 DOM 渲染随旧栈退役，新栈渲染在 src/lib/CallTree.svelte）
// 原模块：调用树（app.js 拆分批 2026-10-04，refs #28：单体 1370 行 →
// 模块化 ESM——零构建纪律不变，<script type="module"> 静态直开兼容；内容自
// app.js 逐字迁移，仅增 import/export。TS 重写批：签名类型化。）
"use strict";

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
