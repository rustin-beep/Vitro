// StepStreamBatch 解码器（S7 批一号段二，2026-09-27）。
// 照搬 native/src/unified/stream/decode.rs：维护 current_vars（SymIdx ->
// 快照）+ var_order（base 序 + 新增追加）+ 各快照当前态，逐 delta 应用后
// 重建完整 StepPayload 列表。get_sym 越界返回空串（Rust unwrap_or_default
// 同义——容错读，不 fail loud：流数据由本方编码器产出，越界属上游 bug，
// 解码侧按 Rust 现状照搬不私改）。

///|
/// 将 StepStreamBatch 解码为完整的 StepPayload 列表。
pub fn decode_batch(batch : StepStreamBatch) -> Array[StepPayload] {
  if batch.base_payloads.is_empty() {
    return []
  }
  let result : Array[StepPayload] = []
  let base = batch.base_payloads[0]
  result.push(decode_step_payload_ref(base, batch.symbol_table))
  let current_vars : Map[SymIdx, ApiVariableSnapshot] = Map([])
  for v in base.local_vars {
    current_vars.set(v.name_idx, {
      name: get_sym(batch.symbol_table, v.name_idx),
      addr: v.addr,
      is_local: v.is_local,
      ty_name: get_sym(batch.symbol_table, v.ty_name_idx),
      value: v.value,
    })
  }
  // 维护变量出现顺序（base 顺序 + 后续新增追加到末尾）
  let var_order : Array[SymIdx] = base.local_vars.map(v => v.name_idx)
  // 维护其他快照的当前状态，用于应用差分
  let current_call_stack : Array[ApiFrameInfo] = base.call_stack.map(f => {
    func_name: get_sym(batch.symbol_table, f.func_name_idx),
    return_line: f.return_line,
  })
  // Rust base.vis_events.clone() 等价——map 重建防共享（P1 审阅修复：
  // 此前共享引用被后续 delta.clear() 就地污染，decode_batch 破坏输入）
  let mut current_vis_events : Array[VisEvent] = base.vis_events.map(e => {
    ty: e.ty,
    line: e.line,
    extra0: e.extra0,
    extra1: e.extra1,
    extra2: e.extra2,
    context: e.context,
  })
  let current_accessed_vars : Array[AccessedVar] = base.accessed_vars.map(a => {
    name: get_sym(batch.symbol_table, a.name_idx),
    access_type: get_sym(batch.symbol_table, a.access_type_idx),
  })
  let current_arrays : Array[ArraySnapshot] = base.array_snapshots.map(a => {
    name: get_sym(batch.symbol_table, a.name_idx),
    element_ty: get_sym(batch.symbol_table, a.element_ty_idx),
    elements: a.elements,
    truncated: a.truncated,
  })
  let current_pointers : Array[PointerSnapshot] = base.pointer_snapshots.map(p => {
    name: get_sym(batch.symbol_table, p.name_idx),
    addr: p.addr,
    ty_name: get_sym(batch.symbol_table, p.ty_name_idx),
    target_addr: p.target_addr,
    target_name: get_sym(batch.symbol_table, p.target_name_idx),
    status: p.status,
  })
  for delta in batch.deltas {
    // 应用 var_deltas
    for d in delta.var_deltas {
      match current_vars.get(d.name_idx) {
        Some(v) => v.value = d.value
        None => ()
      }
    }
    // 添加新变量
    for v in delta.new_vars {
      current_vars.set(v.name_idx, {
        name: get_sym(batch.symbol_table, v.name_idx),
        addr: v.addr,
        is_local: v.is_local,
        ty_name: get_sym(batch.symbol_table, v.ty_name_idx),
        value: v.value,
      })
    }
    // 移除消失的变量
    for idx in delta.removed_var_name_indices {
      current_vars.remove(idx)
    }
    // 更新 var_order：移除已消失的，追加新出现的
    let kept_order : Array[SymIdx] = []
    for idx in var_order {
      let mut drop = false
      for r in delta.removed_var_name_indices {
        if idx == r {
          drop = true
          break
        }
      }
      if !drop {
        kept_order.push(idx)
      }
    }
    for v in delta.new_vars {
      let mut seen = false
      for idx in kept_order {
        if idx == v.name_idx {
          seen = true
          break
        }
      }
      if !seen {
        kept_order.push(v.name_idx)
      }
    }
    var_order.clear()
    for idx in kept_order {
      var_order.push(idx)
    }
    // 按 var_order 构建 local_vars（Rust .cloned() —— 快照互不污染：
    // 后续 delta 的 value mutate 不得回写先前 result）
    let local_vars : Array[ApiVariableSnapshot] = []
    for idx in var_order {
      match current_vars.get(idx) {
        Some(v) =>
          local_vars.push({
            name: v.name,
            addr: v.addr,
            is_local: v.is_local,
            ty_name: v.ty_name,
            value: v.value,
          })
        None => ()
      }
    }
    // 应用 call_stack 差分
    match delta.call_stack {
      Some(frames) => {
        current_call_stack.clear()
        for f in frames {
          current_call_stack.push({
            func_name: get_sym(batch.symbol_table, f.func_name_idx),
            return_line: f.return_line,
          })
        }
      }
      None => ()
    }
    // 应用 vis_events 差分（Rust = events.clone() 整体替换——不得就地
    // clear 共享数组，否则污染 decode_step_payload_ref 路径的 base 帧）
    match delta.vis_events {
      Some(events) =>
        current_vis_events = events.map(e => {
          ty: e.ty,
          line: e.line,
          extra0: e.extra0,
          extra1: e.extra1,
          extra2: e.extra2,
          context: e.context,
        })
      None => ()
    }
    // 应用 accessed_vars 差分
    match delta.accessed_vars {
      Some(vars) => {
        current_accessed_vars.clear()
        for a in vars {
          current_accessed_vars.push({
            name: get_sym(batch.symbol_table, a.name_idx),
            access_type: get_sym(batch.symbol_table, a.access_type_idx),
          })
        }
      }
      None => ()
    }
    // 应用 array_snapshots 差分（先删 removed，再按名替换或追加）
    match delta.array_snapshots {
      Some(arrays) => {
        for idx in delta.removed_array_name_indices {
          let name = get_sym(batch.symbol_table, idx)
          retain_arrays_by_name(current_arrays, name)
        }
        for a in arrays {
          let decoded : ArraySnapshot = {
            name: get_sym(batch.symbol_table, a.name_idx),
            element_ty: get_sym(batch.symbol_table, a.element_ty_idx),
            elements: a.elements,
            truncated: a.truncated,
          }
          replace_or_push_array(current_arrays, decoded)
        }
      }
      None => ()
    }
    // 应用 pointer_snapshots 差分
    match delta.pointer_snapshots {
      Some(pointers) => {
        for idx in delta.removed_pointer_name_indices {
          let name = get_sym(batch.symbol_table, idx)
          retain_pointers_by_name(current_pointers, name)
        }
        for p in pointers {
          let decoded : PointerSnapshot = {
            name: get_sym(batch.symbol_table, p.name_idx),
            addr: p.addr,
            ty_name: get_sym(batch.symbol_table, p.ty_name_idx),
            target_addr: p.target_addr,
            target_name: get_sym(batch.symbol_table, p.target_name_idx),
            status: p.status,
          }
          replace_or_push_pointer(current_pointers, decoded)
        }
      }
      None => ()
    }
    result.push({
      step_index: delta.step_index,
      code_line: delta.code_line,
      func_name: get_sym(batch.symbol_table, delta.func_name_idx),
      semantic_label: get_sym(batch.symbol_table, delta.semantic_label_idx),
      algorithm_step: decode_algo_step(delta.algorithm_step, batch.symbol_table),
      local_vars,
      call_stack: current_call_stack.map(f => {
        func_name: f.func_name,
        return_line: f.return_line,
      }),
      vis_events: current_vis_events.map(e => {
        ty: e.ty,
        line: e.line,
        extra0: e.extra0,
        extra1: e.extra1,
        extra2: e.extra2,
        context: e.context,
      }),
      heatmap_line: delta.heatmap_line,
      heatmap_count: delta.heatmap_count,
      accessed_vars: current_accessed_vars.map(a => {
        name: a.name,
        access_type: a.access_type,
      }),
      array_snapshots: current_arrays.map(a => {
        name: a.name,
        element_ty: a.element_ty,
        elements: a.elements.map(e => e),
        truncated: a.truncated,
      }),
      pointer_snapshots: current_pointers.map(p => {
        name: p.name,
        addr: p.addr,
        ty_name: p.ty_name,
        target_addr: p.target_addr,
        target_name: p.target_name,
        status: p.status,
      }),
      root_cause_hint: delta.root_cause_hint,
    })
  }
  result
}

///|
fn decode_step_payload_ref(
  base : StepPayloadRef,
  sym : Array[String],
) -> StepPayload {
  {
    step_index: base.step_index,
    code_line: base.code_line,
    func_name: get_sym(sym, base.func_name_idx),
    semantic_label: get_sym(sym, base.semantic_label_idx),
    algorithm_step: decode_algo_step(base.algorithm_step, sym),
    local_vars: base.local_vars.map(v => {
      name: get_sym(sym, v.name_idx),
      addr: v.addr,
      is_local: v.is_local,
      ty_name: get_sym(sym, v.ty_name_idx),
      value: v.value,
    }),
    call_stack: base.call_stack.map(f => {
      func_name: get_sym(sym, f.func_name_idx),
      return_line: f.return_line,
    }),
    vis_events: base.vis_events.map(e => {
      ty: e.ty,
      line: e.line,
      extra0: e.extra0,
      extra1: e.extra1,
      extra2: e.extra2,
      context: e.context,
    }),
    heatmap_line: base.heatmap_line,
    heatmap_count: base.heatmap_count,
    accessed_vars: base.accessed_vars.map(a => {
      name: get_sym(sym, a.name_idx),
      access_type: get_sym(sym, a.access_type_idx),
    }),
    array_snapshots: base.array_snapshots.map(a => {
      name: get_sym(sym, a.name_idx),
      element_ty: get_sym(sym, a.element_ty_idx),
      elements: a.elements,
      truncated: a.truncated,
    }),
    pointer_snapshots: base.pointer_snapshots.map(p => {
      name: get_sym(sym, p.name_idx),
      addr: p.addr,
      ty_name: get_sym(sym, p.ty_name_idx),
      target_addr: p.target_addr,
      target_name: get_sym(sym, p.target_name_idx),
      status: p.status,
    }),
    root_cause_hint: base.root_cause_hint,
  }
}

///|
fn decode_algo_step(
  a : AlgorithmStepSnapshotRef?,
  sym : Array[String],
) -> AlgorithmStepSnapshot? {
  match a {
    Some(step) =>
      Some({
        algorithm_name: get_sym(sym, step.algorithm_name_idx),
        display_name: get_sym(sym, step.display_name_idx),
        phase: get_sym(sym, step.phase_idx),
        description: get_sym(sym, step.description_idx),
      })
    None => None
  }
}

///|
/// 越界容错读：返回空串（照搬 get_sym 的 unwrap_or_default）。
fn get_sym(sym : Array[String], idx : SymIdx) -> String {
  if idx >= 0 && idx < sym.length() {
    sym[idx]
  } else {
    ""
  }
}

///|
fn retain_arrays_by_name(arrays : Array[ArraySnapshot], name : String) -> Unit {
  let kept : Array[ArraySnapshot] = []
  for a in arrays {
    if a.name != name {
      kept.push(a)
    }
  }
  arrays.clear()
  for a in kept {
    arrays.push(a)
  }
}

///|
fn retain_pointers_by_name(
  pointers : Array[PointerSnapshot],
  name : String,
) -> Unit {
  let kept : Array[PointerSnapshot] = []
  for p in pointers {
    if p.name != name {
      kept.push(p)
    }
  }
  pointers.clear()
  for p in kept {
    pointers.push(p)
  }
}

///|
fn replace_or_push_array(
  arrays : Array[ArraySnapshot],
  decoded : ArraySnapshot,
) -> Unit {
  let len_arrays = arrays.length()
  for i in 0..<len_arrays {
    if arrays[i].name == decoded.name {
      arrays[i] = decoded
      return
    }
  }
  arrays.push(decoded)
}

///|
fn replace_or_push_pointer(
  pointers : Array[PointerSnapshot],
  decoded : PointerSnapshot,
) -> Unit {
  let len_pointers = pointers.length()
  for i in 0..<len_pointers {
    if pointers[i].name == decoded.name {
      pointers[i] = decoded
      return
    }
  }
  pointers.push(decoded)
}
