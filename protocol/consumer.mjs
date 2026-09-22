#!/usr/bin/env node
// `@vitro/protocol` 的**第一个消费者**（架构审阅 v2 A 组 #10 / §8.5）。
//
// 为什么它必须写出来：报告说「第一个消费者跑通之日，插件架构的所有开放问题
// 都有了实证答案；跑不通，任何预建框架都是空中楼阁」。本脚本就是那个最小实证：
// 用**生成的**协议面（`fields.mjs`，源自 `scripts/gen_protocol_ts`）去消费
// **真实的**引擎输出（`vitro_cli serve` 的 step payload）。
//
// 环境约束（实测）：本机有 node 但**无 npm / npx / tsc**，仓库零 TS 资产 ⇒
// **无法验证「字段名写错在 tsc 编译期即红」**这一 TS 的核心收益。故本消费者
// 取**降级形态**：以生成的字段/枚举元数据在**运行时**做字段级校验——这能证明
// 「生成物描述得了真实输出」（协议面正确性），但**证不了**编译期收益。后者明确
// 登记为待 tsc 环境就绪（见 TESTING 段与 CHANGELOG）。
//
// 职责两项：
//   1) **校验**：每个真实 payload 的字段集与生成物是否一致（未知字段 / 缺字段 /
//      枚举越界）；嵌套结构与枚举按 FIELDS / ENUMS 递归比对。
//   2) **渲染**：把 payload 渲染成一行步骤摘要（最小内容层消费——不经 DOM，
//      故可在纯 node 下跑）。
//
// 用法（仓库根）：
//   node protocol/consumer.mjs [vitro_cli 路径]
//   缺省 exe = native/target/release/vitro_cli.exe
//   --selftest  注入非法 payload，断言校验必报错（J9 形式）

import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { FIELDS, ENUMS, SCHEMA_VERSION } from './fields.mjs';

// ---------------------------------------------------------------- 校验

/** 递归校验一个 payload 对象；错误累积到 errors（每个对象**恰好**检查一次）。 */
export function validatePayload(payload, errors, pathPrefix = '', typeName = 'StepPayload', seen = new WeakSet()) {
  if (typeof payload !== 'object' || payload === null) {
    errors.push(`${pathPrefix || '<root>'}：期望对象，实得 ${payload === null ? 'null' : typeof payload}`);
    return;
  }
  if (seen.has(payload)) return; // 防环
  seen.add(payload);

  const spec = FIELDS[typeName];
  if (!spec) {
    errors.push(`${pathPrefix}：生成物里没有类型 ${typeName} 的字段集（生成器与消费者不同步？）`);
    return;
  }
  const keys = Object.keys(payload);

  // ① 缺字段（协议保证字段只增不改语义 ⇒ 旧消费方可能看到缺省字段；
  //    对当前引擎输出则应为全字段——缺即视为不一致）
  for (const f of spec) {
    if (!keys.includes(f)) {
      errors.push(`${pathPrefix || typeName}：缺字段 \`${f}\`（生成物要求，真实输出没有）`);
    }
  }
  // ② 未知字段：消费方按纪律**应忽略**，但出现即说明生成物落后于引擎
  for (const k of keys) {
    if (!spec.includes(k)) {
      errors.push(`${pathPrefix || typeName}：未知字段 \`${k}\`（真实输出有，生成物没有——协议面落后）`);
    }
  }

  // ③ 嵌套结构 + 枚举值
  for (const childType of ['local_vars', 'call_stack', 'accessed_vars', 'array_snapshots', 'pointer_snapshots', 'vis_events']) {
    if (!Array.isArray(payload[childType])) continue;
    const elemType = {
      local_vars: 'ApiVariableSnapshot',
      call_stack: 'ApiFrameInfo',
      accessed_vars: 'AccessedVar',
      array_snapshots: 'ArraySnapshot',
      pointer_snapshots: 'PointerSnapshot',
      vis_events: 'VisEvent',
    }[childType];
    payload[childType].forEach((el, i) => {
      validatePayload(el, errors, `${pathPrefix}.${childType}[${i}]`, elemType, seen);
    });
  }
  if (payload.algorithm_step !== null && payload.algorithm_step !== undefined) {
    validatePayload(payload.algorithm_step, errors, `${pathPrefix}.algorithm_step`, 'AlgorithmStepSnapshot', seen);
  }
  if (payload.root_cause_hint !== null && payload.root_cause_hint !== undefined) {
    validatePayload(payload.root_cause_hint, errors, `${pathPrefix}.root_cause_hint`, 'RootCauseHint', seen);
  }
  // 枚举字面量校验（§3 的枚举是契约的一部分）
  if (Array.isArray(payload.pointer_snapshots)) {
    payload.pointer_snapshots.forEach((ps, i) => {
      if (ps.status !== undefined && !ENUMS.PointerStatus.includes(ps.status)) {
        errors.push(`${pathPrefix}.pointer_snapshots[${i}].status：枚举越界 "${ps.status}"（合法：${ENUMS.PointerStatus.join(' / ')}）`);
      }
    });
  }
  if (Array.isArray(payload.accessed_vars)) {
    payload.accessed_vars.forEach((av, i) => {
      if (av.access_type !== undefined && !['Read', 'Write'].includes(av.access_type)) {
        errors.push(`${pathPrefix}.accessed_vars[${i}].access_type：枚举越界 "${av.access_type}"（合法：Read / Write）`);
      }
    });
  }
}

// ---------------------------------------------------------------- 渲染（最小内容层）

export function renderStep(p) {
  const vars = (p.local_vars || []).map((v) => `${v.name}=${v.value}`).join(', ');
  const arrs = (p.array_snapshots || [])
    .map((a) => `${a.name}: [${a.elements.join(', ')}]${a.truncated ? ' (截断)' : ''}`)
    .join('  ');
  const ptrs = (p.pointer_snapshots || [])
    .map((s) => `${s.name}→${s.target_name || '0x' + s.target_addr.toString(16)}(${s.status})`)
    .join('  ');
  const parts = [`#${String(p.step_index).padStart(3)} line ${String(p.code_line).padStart(3)} ${p.func_name || '-'}`];
  if (p.semantic_label) parts.push(`  ⟨${p.semantic_label}⟩`);
  if (vars) parts.push(`  vars: ${vars}`);
  if (arrs) parts.push(`  ${arrs}`);
  if (ptrs) parts.push(`  ptr: ${ptrs}`);
  if (p.root_cause_hint) parts.push(`  ⚠ 根因: ${p.root_cause_hint.category} — ${p.root_cause_hint.one_liner}`);
  return parts.join('\n   ');
}

// ---------------------------------------------------------------- serve 驱动

const PROBE_SRC = `int main() {
  int arr[5] = {5, 3, 4, 1, 2};
  int *p = arr;
  for (int i = 0; i < 5; i++)
    for (int j = 0; j < 4 - i; j++)
      if (arr[j] > arr[j + 1]) { int t = arr[j]; arr[j] = arr[j + 1]; arr[j + 1] = t; }
  return *p;
}
`;

// 注意（实测）：`payload.get(start,end)` **不推进执行**——它只返回已收集窗口内的
// 快照（只 step.begin 后调用会得到 0 个 payload）。故消费者必须靠 `step.next`
// 逐步行进；请求是一次性写入 NDJSON（无法按响应动态追加），故预设上限步数，
// finished 之后的请求返回空 payloads，无害。
const MAX_STEPS = 400;

function fetchPayloads(exe) {
  const reqs = [
    JSON.stringify({ id: 1, method: 'compile', params: { source: PROBE_SRC } }),
    JSON.stringify({ id: 2, method: 'step.begin' }),
  ];
  for (let i = 0; i < MAX_STEPS; i++) {
    reqs.push(JSON.stringify({ id: 1000 + i, method: 'step.next' }));
  }
  reqs.push(JSON.stringify({ id: 9999, method: 'shutdown' }));

  const r = spawnSync(exe, ['serve'], { input: reqs.join('\n') + '\n', encoding: 'utf-8', maxBuffer: 256 * 1024 * 1024 });
  if (r.error) throw new Error(`serve 启动失败：${r.error.message}`);
  const lines = (r.stdout || '').split('\n').filter((l) => l.trim());
  const out = [];
  let finished = false;
  for (const l of lines) {
    let d;
    try {
      d = JSON.parse(l);
    } catch {
      continue;
    }
    if (d.id === 1 && d.ok !== true) throw new Error(`compile 失败：${JSON.stringify(d.result)}`);
    const res = d.result;
    if (!res || !Array.isArray(res.payloads)) continue;
    out.push(...res.payloads);
    if (res.finished === true) finished = true;
  }
  if (!finished && out.length >= MAX_STEPS) {
    throw new Error(`步数达上限 ${MAX_STEPS} 仍未 finished——请提高 MAX_STEPS（程序可能很长）`);
  }
  return out;
}

// ---------------------------------------------------------------- 主流程

function main() {
  const argv = process.argv.slice(2);
  const selftest = argv.includes('--selftest');
  const exe = argv.find((a) => !a.startsWith('--')) || 'native/target/release/vitro_cli.exe';

  if (selftest) {
    // J9：构造三类非法 payload，断言校验**必然**报错（否则判据是摆设）
    const probes = [
      ['未知字段', { ...emptyPayload(), __fabricated_field: 1 }],
      ['缺字段', (() => { const p = emptyPayload(); delete p.step_index; return p; })()],
      ['枚举越界', { ...emptyPayload(), pointer_snapshots: [{ name: 'p', addr: 1, ty_name: 'int*', target_addr: 2, target_name: 'x', status: 'Bogus' }] }],
    ];
    let failed = 0;
    for (const [name, bad] of probes) {
      const errs = [];
      validatePayload(bad, errs);
      if (errs.length === 0) {
        console.log(`consumer: selftest FAIL——注入「${name}」后校验仍无错，该判据失效`);
        failed++;
      } else {
        console.log(`consumer: selftest ok——注入「${name}」被捕获（${errs.length} 处）`);
      }
    }
    // 正向：真实 payload 必须零错（否则消费者对真实输出都通不过）
    if (existsSync(exe)) {
      try {
        const real = fetchPayloads(exe);
        const errs = [];
        real.forEach((p) => validatePayload(p, errs));
        if (errs.length === 0) console.log(`consumer: selftest ok——真实 payload ${real.length} 步零错（正向也活）`);
        else {
          console.log(`consumer: selftest FAIL——真实 payload 校验有 ${errs.length} 处错`);
          failed++;
        }
      } catch (e) {
        console.log(`consumer: selftest ABORT——取真实 payload 失败：${e.message}`);
      }
    } else {
      console.log(`consumer: selftest 跳过正向（找不到 ${exe}；先 cd native && cargo build --release）`);
    }
    process.exit(failed > 0 ? 1 : 0);
  }

  if (!existsSync(exe)) {
    console.error(`consumer: 找不到引擎 ${exe}\n请先：cd native && cargo build --release --bin vitro_cli`);
    process.exit(2);
  }

  console.log(`consumer: @vitro/protocol SCHEMA_VERSION=${SCHEMA_VERSION}（生成物字段集：${Object.keys(FIELDS).length} 类型）`);
  let payloads;
  try {
    payloads = fetchPayloads(exe);
  } catch (e) {
    console.error(`consumer: ${e.message}`);
    process.exit(2);
  }
  if (payloads.length === 0) {
    console.error('consumer: serve 未返回任何 payload——拒绝判绿（空集不得绿）');
    process.exit(2);
  }

  const errors = [];
  payloads.forEach((p) => validatePayload(p, errors));

  console.log(`consumer: 消费 ${payloads.length} 步真实 step payload`);
  if (errors.length > 0) {
    console.log(`  !! 字段级校验失败 ${errors.length} 处：`);
    for (const e of errors.slice(0, 20)) console.log(`     ${e}`);
    if (errors.length > 20) console.log(`     …（其余 ${errors.length - 20} 处省略）`);
    console.log('consumer: FAIL——生成物与真实输出不一致');
    process.exit(1);
  }
  console.log('  ok 字段级校验零错（生成物完整描述了真实输出）');

  // 最小内容层渲染：只打印最后一步（栈最深、信息最全）与首个有数组快照的步
  const withArr = payloads.find((p) => (p.array_snapshots || []).length > 0);
  const last = payloads[payloads.length - 1];
  console.log('  ── 最小渲染（内容层消费样例）──');
  if (withArr) console.log('   ' + renderStep(withArr));
  if (last && last !== withArr) console.log('   ' + renderStep(last));
  console.log('consumer: PASS');
}

function emptyPayload() {
  // 与 StepPayload 字段集对齐的全字段空 payload（selftest 基线）
  const p = {};
  for (const f of FIELDS.StepPayload) p[f] = null;
  p.step_index = 0;
  p.code_line = 0;
  p.func_name = '';
  p.semantic_label = '';
  p.heatmap_line = 0;
  p.heatmap_count = 0;
  p.local_vars = [];
  p.call_stack = [];
  p.vis_events = [];
  p.accessed_vars = [];
  p.array_snapshots = [];
  p.pointer_snapshots = [];
  return p;
}

main();
