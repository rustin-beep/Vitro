// teaching/steps·infer structures 族（S8 teaching 批六号收官，2026-10-02）：
// 十一算法照搬 vitro_algorithm_steps/src/structures.rs:1-301——seq_list 的
// 表长更新挂真值行（U1#1 P1-89：旧判据命中后移循环，真值在 L->length--，
// 用原大小写 source_line 判 length--/length++）；全族行级判据零变量读口
//（仅 josephus/union_find 取 m/remain/x）。

///|
/// 链表删除。
fn infer_linked_list_delete(
  source_line : String,
  _vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
) -> @protocol.AlgorithmStepSnapshot? {
  let line_lower = source_line.to_lower()
  if line_lower.contains("head") &&
    line_lower.contains("next") &&
    line_lower.contains("free") {
    return Some(
      build_step(algorithm, "delete_head", "删除头节点并释放内存"),
    )
  }
  if starts_with(line_lower, "while ") &&
    line_lower.contains("data") &&
    line_lower.contains("key") {
    return Some(
      build_step(algorithm, "search", "遍历链表查找目标节点"),
    )
  }
  if line_lower.contains("prev") &&
    line_lower.contains("next") &&
    line_lower.contains("=") {
    return Some(
      build_step(
        algorithm, "unlink", "调整前驱指针，跳过待删除节点",
      ),
    )
  }
  if line_lower.contains("free") && line_lower.contains("temp") {
    return Some(
      build_step(algorithm, "free", "释放被删除节点的堆内存"),
    )
  }
  if starts_with(line_lower, "return") {
    return Some(build_step(algorithm, "finish", "链表删除完成"))
  }
  None
}

///|
/// 顺序表。
fn infer_seq_list(
  source_line : String,
  _vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
) -> @protocol.AlgorithmStepSnapshot? {
  let line_lower = source_line.to_lower()
  if line_lower.contains("length") &&
    line_lower.contains("maxsize") &&
    line_lower.contains("||") {
    return Some(
      build_step(algorithm, "check", "检查插入/删除位置的合法性"),
    )
  }
  if line_lower.contains("data[i]") &&
    line_lower.contains("data[i - 1]") &&
    line_lower.contains("=") {
    return Some(
      build_step(algorithm, "shift", "移动元素，腾出或填补位置"),
    )
  }
  if line_lower.contains("data[pos]") &&
    line_lower.contains("=") &&
    !line_lower.contains("||") {
    return Some(build_step(algorithm, "place", "在目标位置放入元素"))
  }
  // U1#1 P1-89（用户审阅）：旧判据命中后移循环，真值在 L->length--。
  if source_line.contains("length--") || source_line.contains("length++") {
    return Some(build_step(algorithm, "update_len", "更新表长度"))
  }
  if starts_with(line_lower, "return") {
    return Some(build_step(algorithm, "finish", "顺序表操作完成"))
  }
  None
}

///|
/// 链表尾插。
fn infer_linked_list_append(
  source_line : String,
  _vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
) -> @protocol.AlgorithmStepSnapshot? {
  let line_lower = source_line.to_lower()
  if line_lower.contains("next") &&
    line_lower.contains("null") &&
    line_lower.contains("while") {
    return Some(
      build_step(algorithm, "find_tail", "遍历链表寻找尾节点"),
    )
  }
  if line_lower.contains("next") &&
    line_lower.contains("=") &&
    !line_lower.contains("null") {
    return Some(
      build_step(algorithm, "link", "将新节点链接到链表尾部"),
    )
  }
  None
}

///|
/// 循环队列。
fn infer_circular_queue(
  source_line : String,
  _vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
) -> @protocol.AlgorithmStepSnapshot? {
  let line_lower = source_line.to_lower()
  if line_lower.contains("rear") &&
    line_lower.contains("front") &&
    line_lower.contains("%") {
    return Some(
      build_step(algorithm, "check", "利用取模判断队列空或满"),
    )
  }
  if line_lower.contains("data") &&
    line_lower.contains("rear") &&
    line_lower.contains("=") {
    return Some(build_step(algorithm, "enqueue", "元素入队"))
  }
  if line_lower.contains("data") &&
    line_lower.contains("front") &&
    !line_lower.contains("==") {
    return Some(build_step(algorithm, "dequeue", "元素出队"))
  }
  if line_lower.contains("rear") && line_lower.contains("%") {
    return Some(build_step(algorithm, "wrap", "指针循环绕回数组开头"))
  }
  None
}

///|
/// 链栈。
fn infer_linked_stack(
  source_line : String,
  _vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
) -> @protocol.AlgorithmStepSnapshot? {
  let line_lower = source_line.to_lower()
  if line_lower.contains("next") &&
    line_lower.contains("top") &&
    line_lower.contains("=") &&
    line_lower.contains("malloc") {
    return Some(build_step(algorithm, "push", "新节点入栈"))
  }
  if line_lower.contains("free") && line_lower.contains("temp") {
    return Some(build_step(algorithm, "pop", "释放栈顶节点"))
  }
  None
}

///|
/// 链队列。
fn infer_linked_queue(
  source_line : String,
  _vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
) -> @protocol.AlgorithmStepSnapshot? {
  let line_lower = source_line.to_lower()
  if line_lower.contains("rear") &&
    line_lower.contains("next") &&
    line_lower.contains("=") {
    return Some(
      build_step(algorithm, "enqueue", "新节点入队并更新尾指针"),
    )
  }
  if line_lower.contains("front") &&
    line_lower.contains("next") &&
    !line_lower.contains("rear") {
    return Some(build_step(algorithm, "dequeue", "队头出队"))
  }
  if line_lower.contains("free") {
    return Some(build_step(algorithm, "free", "释放被删除节点"))
  }
  None
}

///|
/// 哈希表。
fn infer_hash_table(
  source_line : String,
  _vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
) -> @protocol.AlgorithmStepSnapshot? {
  let line_lower = source_line.to_lower()
  if line_lower.contains("key") && line_lower.contains("%") {
    return Some(build_step(algorithm, "hash", "计算哈希值"))
  }
  if line_lower.contains("occupied") && line_lower.contains("while") {
    return Some(
      build_step(algorithm, "probe", "线性探测寻找空位或目标"),
    )
  }
  if line_lower.contains("key") &&
    line_lower.contains("==") &&
    line_lower.contains("return") {
    return Some(build_step(algorithm, "hit", "找到目标关键字"))
  }
  None
}

///|
/// 约瑟夫环。
fn infer_josephus(
  source_line : String,
  vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
) -> @protocol.AlgorithmStepSnapshot? {
  let line_lower = source_line.to_lower()
  let m = match vars.get_int_any(["m"]) {
    Some(v) => v
    None => -1
  }
  let remain = match vars.get_int_any(["remain"]) {
    Some(v) => v
    None => -1
  }
  if line_lower.contains("alive") &&
    line_lower.contains("1") &&
    line_lower.contains("=") {
    return Some(
      build_step(algorithm, "init", "初始化所有人为存活状态"),
    )
  }
  if line_lower.contains("alive") &&
    line_lower.contains("0") &&
    line_lower.contains("=") {
    return Some(
      build_step(
        algorithm,
        "eliminate",
        "报到 \{m} 的人被淘汰，剩余 \{remain} 人",
      ),
    )
  }
  if line_lower.contains("%") && line_lower.contains("+ 1") {
    return Some(
      build_step(algorithm, "rotate", "下标循环绕回，模拟圆圈"),
    )
  }
  if starts_with(line_lower, "return") {
    return Some(build_step(algorithm, "finish", "约瑟夫环淘汰完成"))
  }
  None
}

///|
/// 循环链表。
fn infer_circular_linked_list(
  source_line : String,
  _vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
) -> @protocol.AlgorithmStepSnapshot? {
  let line_lower = source_line.to_lower()
  if line_lower.contains("next") &&
    line_lower.contains("head") &&
    line_lower.contains("=") {
    return Some(
      build_step(algorithm, "link", "尾节点回指头节点，形成循环"),
    )
  }
  if line_lower.contains("do") {
    return Some(
      build_step(algorithm, "traverse", "do-while 遍历循环链表"),
    )
  }
  if starts_with(line_lower, "return") {
    return Some(build_step(algorithm, "finish", "循环链表操作完成"))
  }
  None
}

///|
/// 静态链表。
fn infer_static_linked_list(
  source_line : String,
  _vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
) -> @protocol.AlgorithmStepSnapshot? {
  let line_lower = source_line.to_lower()
  if line_lower.contains("cur") && line_lower.contains("i + 1") {
    return Some(build_step(algorithm, "init", "初始化备用链表"))
  }
  if line_lower.contains("space[0].cur") && line_lower.contains("space[i].cur") {
    return Some(build_step(algorithm, "malloc", "从备用链表分配节点"))
  }
  if line_lower.contains("space[k].cur") && line_lower.contains("space[0].cur") {
    return Some(build_step(algorithm, "free", "回收节点到备用链表"))
  }
  None
}

///|
/// 并查集。
fn infer_union_find(
  source_line : String,
  vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
) -> @protocol.AlgorithmStepSnapshot? {
  let line_lower = source_line.to_lower()
  let x = match vars.get_int_any(["x"]) {
    Some(v) => v
    None => -1
  }
  if line_lower.contains("parent[x]") && line_lower.contains("< 0") {
    return Some(build_step(algorithm, "find", "查找 \{x} 的根节点"))
  }
  if line_lower.contains("parent[x]") &&
    line_lower.contains("find") &&
    line_lower.contains("=") {
    return Some(
      build_step(algorithm, "compress", "路径压缩，直接指向根"),
    )
  }
  if line_lower.contains("union") && line_lower.contains("root") {
    return Some(build_step(algorithm, "union", "合并两个集合"))
  }
  None
}
