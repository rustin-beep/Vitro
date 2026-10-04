// Vitro demo · wire DTO 类型（TS 惯用法重写批 2026-10-04，refs #28）。
// 源 = gateway wire 帧（canonicalize 口径），与 engine 侧 emitter 字段序无关。
//
// 声明口径（2026-10-04 审阅 P2-3 修正）：StepPayload 顶层 14 字段 = 协议
// v0.1 白名单全集（demo_smoke 键集全等断言机判）；但「字段已声明」≠「页面
// 已消费」——vis_events / algorithm_step / root_cause_hint / pointer_
// snapshots / accessed_vars / heatmap_line / heatmap_count / array_snapshots
// 八字段当前无前端消费者，为 demo 前端接线批（#28 可视化侧栏）的预留声明；
// 接线落地时此处逐字段补消费点注释。协议权威面在 @vitro/protocol/index.d.ts。

// ── step 流（时间旅行回放消费）────────────────────────────────

/** semantic_label 受控词表渲染文本（engine 侧 14 类；此处只需 string 语义） */
export type SemanticLabel = string;

export interface VisEvent {
  ty: number;
  line: number;
  extra0: number;
  extra1: number;
  extra2: number;
  context: string;
}

export interface CallFrame {
  func_name: string;
  return_line: number;
}

export interface LocalVar {
  name: string;
  addr: number;
  is_local: boolean;
  ty_name: string;
  value: string;
}

export interface AlgorithmStep {
  algorithm_name: string;
  display_name: string;
  phase: string;
  description: string;
}

/** 数组快照（数组柱状图消费：renderArrayViz 读 name/elements） */
export interface ArraySnapshot {
  name: string;
  element_ty: string;
  elements: string[];
}

export interface StepPayload {
  step_index: number;
  code_line: number;
  func_name: string;
  semantic_label: SemanticLabel;
  algorithm_step: AlgorithmStep | null;
  local_vars: LocalVar[];
  call_stack: CallFrame[];
  vis_events: VisEvent[];
  heatmap_line: number;
  heatmap_count: number;
  accessed_vars: unknown[];
  array_snapshots: ArraySnapshot[];
  pointer_snapshots: unknown[];
  root_cause_hint: {
    category: string;
    one_liner: string;
    related_lines: number[];
    suggested_fix_kind: string;
    suggested_fix_line: number | null;
    suggested_fix_desc: string | null;
  } | null;
}

/** step.next 帧批（U1#1 一帧发布缓冲 + finished 冲刷形态） */
export interface StepNextResult {
  payloads: StepPayload[];
  finished: boolean;
  trapped: boolean;
  waiting_input?: boolean;
  /** 断点暂停（breakpoints.set 后推进到断点行的批次——2026-10-04 消费接线） */
  paused?: boolean;
  trap_message: string | null;
  max_collected_step?: number;
}

// ── compile / run（运行链消费）──────────────────────────────

export interface Diagnostic {
  code: string;
  error_code: string;
  severity: string;
  line: number;
  column: number;
  end_line?: number;
  end_column?: number;
  message: string;
  fix_suggestion: string;
  filename: string;
}

export interface CompileResult {
  ok: boolean;
  diagnostics: Diagnostic[];
  preprocessor_trace: string[];
}

export interface RunResult {
  ok: boolean;
  status: "finished" | "trap" | "waiting_input" | "not_compiled";
  return_value: number;
  trap: string;
  waiting_input: boolean;
  steps_executed: number;
}

// ── output.delta（四通道游标制增量）─────────────────────────

export interface OutputDelta {
  delta: string;
  cursor: number;
  total: number;
  stream: string;
}

// ── memory.regions（内存地图消费）───────────────────────────

export interface HeapRegion {
  addr: number;
  size: number;
  is_heap: boolean;
  is_freed: boolean;
  alloc_line: number;
  alloc_by: string;
  ty: string;
  name: string;
  /** 段着色类（band 渲染消费：blk 类名组成） */
  kind: string;
}

export interface MemoryRegions {
  region_counts: { global: number; heap: number; stack: number };
  alloc_counter: number;
  free_list: unknown[];
  quarantine: { bytes: number; budget: number; blocks: number };
  regions: HeapRegion[];
  heap_base: number;
  heap_offset: number;
}

// ── config（会话配置消费）───────────────────────────────────

export interface EngineConfig {
  max_steps: number;
  call_depth_limit: number;
  deterministic: boolean;
  input_mode_batch: boolean;
  quarantine_budget: number;
}

// ── gateway 帧信封 ──────────────────────────────────────────

/** 协议所有方法帧均为「顶层 id/ok + result」包裹（2026-09-30 审阅复核修正） */
export interface Frame<T = unknown> {
  id: number | null;
  ok: boolean;
  result?: T;
  error?: { kind: string; message: string };
}
