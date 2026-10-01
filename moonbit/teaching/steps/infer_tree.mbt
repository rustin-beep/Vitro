// teaching/steps·infer tree 族（S8 teaching 批三号，2026-10-01）：八算法
// 照搬 vitro_algorithm_steps/src/tree.rs:1-259——含全部审阅修复语义：
// bst_validate 三 phase 锚定模板行（二审 P0-B 方案②）+ 顶层调用帧入口
// 语义（v5 ✗2）+ bst_delete 判据置顶（findMin 行不被替换判据误吃）。

///|
/// BST 插入。
fn infer_bst_insert(
  source_line : String,
  vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
  func_name : String,
) -> @protocol.AlgorithmStepSnapshot? {
  ignore(vars)
  let line_lower = source_line.to_lower()
  if source_line.contains("\{func_name}(") {
    return Some(build_step(algorithm, "recursive", "递归查找插入位置"))
  }
  if line_lower.contains("null") && line_lower.contains("return") {
    return Some(
      build_step(algorithm, "create", "找到空位，创建新节点"),
    )
  }
  if line_lower.contains("val") &&
    line_lower.contains("root->val") &&
    line_lower.contains("<") {
    return Some(
      build_step(
        algorithm, "compare", "比较插入值与当前节点值，决定向左或向右",
      ),
    )
  }
  if starts_with(line_lower, "return") {
    return Some(build_step(algorithm, "finish", "BST 插入完成"))
  }
  None
}

///|
/// BST 合法性校验（二审 P0-B 方案②——挂载点锚定模板三行：
/// `if (root == NULL) return 1;` → empty_valid；
/// `if (root->val <= min || >= max) return 0;` → range_check；
/// 递归行 → recursive〔判据置顶——该行同时含 min/max 会被区间判据误吃〕）。
fn infer_bst_validate(
  source_line : String,
  vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
  func_name : String,
  env : InferEnv,
) -> @protocol.AlgorithmStepSnapshot? {
  ignore(vars)
  let line_lower = source_line.to_lower()
  // 递归校验行置顶
  if source_line.contains("\{func_name}(") {
    // v5 ✗2：顶层调用帧（at_callee_entry + caller_is_main）给入口语义
    if env.at_callee_entry && env.caller_is_main {
      return Some(
        build_step(
          algorithm, "recursive", "启动校验：从根节点开始，检查整棵树是否满足 BST 性质",
        ),
      )
    }
    return Some(
      build_step(
        algorithm, "recursive", "递归校验子树：左子树区间收窄为 (min, val)，右子树为 (val, max)",
      ),
    )
  }
  // 空树合法判定
  if line_lower.contains("null") && line_lower.contains("return") {
    return Some(
      build_step(
        algorithm, "empty_valid", "空子树不违反 BST 性质，判定合法",
      ),
    )
  }
  // 区间校验
  let mentions_bound = line_lower.contains("min") || line_lower.contains("max")
  if mentions_bound && (line_lower.contains("<=") || line_lower.contains(">=")) {
    return Some(
      build_step(
        algorithm, "range_check", "校验当前节点值：必须严格落在开区间 (min, max) 内，越界即非法",
      ),
    )
  }
  None
}

///|
/// BST 删除（人审档 A 裸命名补齐侧——判据置顶优先序照搬）。
fn infer_bst_delete(
  source_line : String,
  vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
  func_name : String,
) -> @protocol.AlgorithmStepSnapshot? {
  ignore(vars)
  let line_lower = source_line.to_lower()
  // 找中序后继（置顶：findMin(root->right) 赋值行含 temp，会被替换判据误吃）
  let successor_call = line_lower.contains("findmin") ||
    line_lower.contains("find_min") ||
    line_lower.contains("successor")
  if successor_call && line_lower.contains("(") {
    return Some(
      build_step(
        algorithm, "find_successor", "双孩子情况：找右子树最小节点作为中序后继",
      ),
    )
  }
  // 递归删除
  if source_line.contains("\{func_name}(") {
    return Some(
      build_step(
        algorithm, "recursive", "递归在子树中定位并删除目标节点",
      ),
    )
  }
  // 释放被删节点
  if line_lower.contains("free(") {
    return Some(build_step(algorithm, "free", "摘除并释放被删节点"))
  }
  // 后继值替换（root->val = temp->val;）
  if line_lower.contains("val") &&
    line_lower.contains("temp") &&
    line_lower.contains("=") &&
    not(line_lower.contains("==")) {
    return Some(
      build_step(
        algorithm, "replace", "用中序后继的值替换被删节点的值",
      ),
    )
  }
  // 空/未找到
  if line_lower.contains("null") && line_lower.contains("return") {
    return Some(
      build_step(algorithm, "not_found", "搜索到空节点，目标不存在"),
    )
  }
  // 单孩子/叶子判定
  if (line_lower.contains("left") || line_lower.contains("right")) &&
    line_lower.contains("null") {
    return Some(
      build_step(
        algorithm, "single_child", "判断孩子情况：叶子或单孩子节点可直接摘除",
      ),
    )
  }
  // 比较
  if line_lower.contains("key") &&
    line_lower.contains("val") &&
    (line_lower.contains("<") || line_lower.contains(">")) {
    return Some(
      build_step(
        algorithm, "compare", "比较目标关键字与当前节点值，决定递归方向",
      ),
    )
  }
  None
}

///|
/// BST 查找。
fn infer_bst_search(
  source_line : String,
  vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
  func_name : String,
) -> @protocol.AlgorithmStepSnapshot? {
  ignore(vars)
  let line_lower = source_line.to_lower()
  if source_line.contains("\{func_name}(") {
    return Some(build_step(algorithm, "recursive", "递归进入子树查找"))
  }
  if line_lower.contains("val") &&
    line_lower.contains("key") &&
    line_lower.contains("==") {
    return Some(build_step(algorithm, "hit", "找到目标节点"))
  }
  if line_lower.contains("null") && line_lower.contains("return") {
    return Some(build_step(algorithm, "miss", "到达空节点，查找失败"))
  }
  if line_lower.contains("key") &&
    line_lower.contains("val") &&
    line_lower.contains("<") {
    return Some(
      build_step(algorithm, "compare", "比较关键字与当前节点值"),
    )
  }
  None
}

///|
/// 层序遍历。
fn infer_level_order(
  source_line : String,
  vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
) -> @protocol.AlgorithmStepSnapshot? {
  ignore(vars)
  let line_lower = source_line.to_lower()
  if line_lower.contains("queue") &&
    line_lower.contains("[") &&
    line_lower.contains("root") {
    return Some(build_step(algorithm, "enqueue", "根节点入队"))
  }
  if line_lower.contains("node") &&
    line_lower.contains("queue") &&
    line_lower.contains("front") {
    return Some(build_step(algorithm, "dequeue", "取出队头节点访问"))
  }
  if line_lower.contains("left") &&
    line_lower.contains("queue") &&
    line_lower.contains("[") {
    return Some(build_step(algorithm, "enqueue_left", "左子节点入队"))
  }
  if line_lower.contains("right") &&
    line_lower.contains("queue") &&
    line_lower.contains("[") {
    return Some(build_step(algorithm, "enqueue_right", "右子节点入队"))
  }
  None
}

///|
/// 线索二叉树。
fn infer_threaded_binary_tree(
  source_line : String,
  vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
) -> @protocol.AlgorithmStepSnapshot? {
  ignore(vars)
  let line_lower = source_line.to_lower()
  if line_lower.contains("ltag") && line_lower.contains("thread") {
    return Some(
      build_step(algorithm, "thread_left", "建立左线索指向前驱"),
    )
  }
  if line_lower.contains("rtag") && line_lower.contains("thread") {
    return Some(
      build_step(algorithm, "thread_right", "建立右线索指向后继"),
    )
  }
  if line_lower.contains("ltag") && line_lower.contains("link") {
    return Some(
      build_step(algorithm, "find_leftmost", "沿左孩子找到最左节点"),
    )
  }
  if line_lower.contains("rtag") &&
    line_lower.contains("thread") &&
    line_lower.contains("while") {
    return Some(
      build_step(algorithm, "follow_thread", "沿后继线索访问节点"),
    )
  }
  None
}

///|
/// 哈夫曼树。
fn infer_huffman_tree(
  source_line : String,
  vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
) -> @protocol.AlgorithmStepSnapshot? {
  ignore(vars)
  let line_lower = source_line.to_lower()
  if line_lower.contains("parent") &&
    line_lower.contains("-1") &&
    line_lower.contains("weight") {
    return Some(
      build_step(
        algorithm, "select", "在森林中选择两个最小权值节点",
      ),
    )
  }
  if line_lower.contains("parent") &&
    line_lower.contains("=") &&
    not(line_lower.contains("-1")) {
    return Some(build_step(algorithm, "merge", "合并两个节点为新树"))
  }
  None
}

///|
/// AVL 树。
fn infer_avl_tree(
  source_line : String,
  vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
) -> @protocol.AlgorithmStepSnapshot? {
  ignore(vars)
  let line_lower = source_line.to_lower()
  if line_lower.contains("r_rotate") || line_lower.contains("l_rotate") {
    return Some(build_step(algorithm, "rotate", "旋转调整平衡"))
  }
  if line_lower.contains("leftbalance") || line_lower.contains("rightbalance") {
    return Some(
      build_step(
        algorithm, "balance", "平衡因子失衡，进行平衡调整",
      ),
    )
  }
  if line_lower.contains("bf") &&
    line_lower.contains("=") &&
    not(line_lower.contains("null")) {
    return Some(build_step(algorithm, "update_bf", "更新平衡因子"))
  }
  None
}
