// 蓝本注记：文内 Rust 源引用（`*.rs` 路径/行号/符号）均为档案态蓝本——tag rust-oracle-freeze（2026-10-05 删区），现为本仓自主基线。

// teaching/steps·infer graph 族（S8 teaching 批四号，2026-10-01）：
// 七算法照搬 vitro_algorithm_steps/src/graph.rs:1-222——含全部审阅修复
// 语义：BFS 起点入队文案区分（U1#1 P1-6）/ prim 的 lowcost[k]=0 收紧
//（U1#1 P1-76——初始化行 lowcost[0]=0 不误判）/ dijkstra 的 visited[u]=1
// 收紧（U1#1 P0-1——初始化行 visited[v0]=1 不产「顶点 -1 已确定」）/
// 拓扑排序 output 挂真输出行（§6-5 v4 #112）。
// #436 翻面（M34b A3）：BFS/DFS 的 visit 判据补修——U1#1 P0-1 dijkstra
// 同款收紧漏修面（宽判据 contains("visited")&&contains("=") 把重置行
// visited[i]=0 与判断行 == 双双误标 visit；节点值取 u/front/start 与
// 行下标变量脱钩——真标记行 visited[v]=1 显示的不是 v）。

///|
/// `arr[expr] = 1` 裸赋值形态提取（#436 翻面 M34b A3）：返回下标表达式
/// expr；非该形态返回 None——判断行（== 由 bare_assign_eq 排除）/ 重置行
///（= 0 的 RHS 排除）/ 复合赋值排除。真标记语义只在「下标写 1」。
/// PR #463 审阅 P3-4：marker 查找走小写化行（`Visited[...]` 形态同判）；
/// 下标表达式原样保留（变量名大小写敏感——eval_index_expr 按原名查）。
/// 子串查找复用 infer_dp 的 find_sub（3 参版）。
fn array_write_one_of(line : String, arr : String) -> String? {
  let marker = "\{arr}["
  let lower_line = line.to_lower()
  let p = match find_sub(lower_line, marker, 0) {
    Some(v) => v
    None => return None
  }
  let n = line.length()
  let b0 = p + marker.length()
  let mut b1 = b0
  while b1 < n && line[b1].to_int() != 93 {
    b1 = b1 + 1
  }
  if b1 >= n {
    return None
  }
  let expr = line[b0:b1].trim().to_owned()
  if expr.is_empty() {
    return None
  }
  // 裸赋值 = 须在下标之后；RHS（trim 去 ;/}）须恰为 "1"
  let eq = bare_assign_eq(line)
  if eq < 0 || eq < b1 {
    return None
  }
  let rhs = line[eq + 1:n].trim().to_owned()
  let rhs_clean = if rhs.length() > 0 {
    let last = rhs[rhs.length() - 1].to_int()
    if last == 59 || last == 125 {
      rhs[0:rhs.length() - 1].trim().to_owned()
    } else {
      rhs
    }
  } else {
    rhs
  }
  if rhs_clean != "1" {
    return None
  }
  Some(expr)
}

///|
/// BFS 广度优先搜索。
fn infer_bfs(
  source_line : String,
  vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
  env : InferEnv,
) -> @protocol.AlgorithmStepSnapshot? {
  let line_lower = source_line.to_lower()
  let u = match vars.get_int_any(["u", "front", "start"]) {
    Some(v) => v
    None => -1
  }
  let front = match vars.get_int("front") {
    Some(v) => v
    None => -1
  }
  let rear = match vars.get_int("rear") {
    Some(v) => v
    None => -1
  }
  if starts_with(line_lower, "while ") {
    return Some(
      build_step(
        algorithm,
        "loop",
        "队列非空，继续广度优先搜索 [front=\{front}, rear=\{rear}]",
      ),
    )
  }
  if line_lower.contains("queue[front++]") ||
    (line_lower.contains("front") && line_lower.contains("++")) {
    return Some(build_step(algorithm, "dequeue", "出队节点 u=\{u}"))
  }
  if line_lower.contains("queue[rear++]") ||
    (line_lower.contains("rear") && line_lower.contains("++")) {
    // U1#1 P1-6（用户审阅）：首帧常为起点入队（queue[rear++] = start），
    // 文案区分起点与邻居。
    if line_lower.contains("start") ||
      line_lower.contains("source") ||
      line_lower.contains("root") {
      return Some(build_step(algorithm, "enqueue", "起点入队"))
    }
    return Some(build_step(algorithm, "enqueue", "邻居节点入队"))
  }
  // #436 翻面（M34b A3）：visit 只认 `visited[X] = 1` 裸赋值真标记形态
  //（判断行 == / 重置行 = 0 皆非访问语义）；节点值取行内下标变量 X 的
  // 帧值（求值不可得则不产——不拼负哨兵）。
  match array_write_one_of(source_line, "visited") {
    Some(idx_expr) =>
      match eval_index_expr(idx_expr, env.prev_vars, vars) {
        Some(node) =>
          return Some(
            build_step(algorithm, "visit", "标记节点 \{node} 为已访问"),
          )
        None => ()
      }
    None => ()
  }
  if starts_with(line_lower, "return") {
    return Some(build_step(algorithm, "finish", "BFS 遍历完成"))
  }
  None
}

///|
/// DFS 深度优先搜索。
fn infer_dfs(
  source_line : String,
  vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
  func_name : String,
  env : InferEnv,
) -> @protocol.AlgorithmStepSnapshot? {
  let line_lower = source_line.to_lower()
  let u = match vars.get_int_any(["u", "v", "start"]) {
    Some(v) => v
    None => -1
  }
  // 递归调用判定用**原大小写** source_line（Rust 同款——C 函数名大小写
  // 敏感，lower 化会把 Printf 之类误当递归调用）
  if source_line.contains("\{func_name}(") {
    return Some(
      build_step(
        algorithm,
        "recursive",
        "递归深入：从节点 \{u} 继续深度优先搜索",
      ),
    )
  }
  // #436 翻面（M34b A3，DFS 侧同款）：`visited[X] = 1` 裸赋值真标记形态
  // + 节点值取行内下标变量 X。
  match array_write_one_of(source_line, "visited") {
    Some(idx_expr) =>
      match eval_index_expr(idx_expr, env.prev_vars, vars) {
        Some(node) =>
          return Some(
            build_step(algorithm, "visit", "标记节点 \{node} 为已访问"),
          )
        None => ()
      }
    None => ()
  }
  if starts_with(line_lower, "for ") || starts_with(line_lower, "while ") {
    return Some(build_step(algorithm, "scan", "扫描节点 \{u} 的邻居"))
  }
  if starts_with(line_lower, "return") {
    return Some(build_step(algorithm, "finish", "DFS 遍历完成"))
  }
  None
}

///|
/// Prim 最小生成树。
fn infer_prim_mst(
  source_line : String,
  vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
) -> @protocol.AlgorithmStepSnapshot? {
  let line_lower = source_line.to_lower()
  let k = match vars.get_int_any(["k"]) {
    Some(v) => v
    None => -1
  }
  if line_lower.contains("lowcost") &&
    line_lower.contains("min") &&
    line_lower.contains("inf") {
    return Some(
      build_step(algorithm, "select_min", "选择最小边，顶点 k=\{k}"),
    )
  }
  // U1#1 P1-76（用户审阅）：旧条件命中初始化行 `lowcost[0] = 0;`（k 未
  // 初始化 → "顶点 -1 加入生成树"）。收紧为 `lowcost[k] = 0` 形态——
  // 与 dijkstra 的 visited[u] 同款修法。
  if (line_lower.contains("lowcost[k]") || line_lower.contains("lowcost [k]")) &&
    line_lower.contains("0") &&
    line_lower.contains("=") &&
    !line_lower.contains("!=") {
    return Some(
      build_step(algorithm, "add_vertex", "顶点 \{k} 加入生成树"),
    )
  }
  if line_lower.contains("g[k]") &&
    line_lower.contains("lowcost") &&
    line_lower.contains("<") {
    return Some(
      build_step(algorithm, "update", "更新邻接顶点的最小边权"),
    )
  }
  None
}

///|
/// Kruskal 最小生成树。
fn infer_kruskal_mst(
  source_line : String,
  _vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
) -> @protocol.AlgorithmStepSnapshot? {
  let line_lower = source_line.to_lower()
  if line_lower.contains("edges") &&
    line_lower.contains("w") &&
    line_lower.contains("<") {
    return Some(build_step(algorithm, "sort", "按边权排序"))
  }
  if line_lower.contains("find") &&
    line_lower.contains("parent") &&
    line_lower.contains("!=") {
    return Some(build_step(algorithm, "check_cycle", "并查集判环"))
  }
  if line_lower.contains("union") && line_lower.contains("parent") {
    return Some(
      build_step(algorithm, "add_edge", "加入生成树并合并集合"),
    )
  }
  None
}

///|
/// Dijkstra 最短路径。
fn infer_dijkstra(
  source_line : String,
  vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
) -> @protocol.AlgorithmStepSnapshot? {
  let line_lower = source_line.to_lower()
  let u = match vars.get_int_any(["u"]) {
    Some(v) => v
    None => -1
  }
  if line_lower.contains("dist") &&
    line_lower.contains("min") &&
    line_lower.contains("inf") {
    return Some(
      build_step(
        algorithm,
        "select",
        "选择距离最小的未确定顶点 u=\{u}",
      ),
    )
  }
  // U1#1 P0-1 复审补充：旧条件 `contains("visited") && contains('=') &&
  // contains('1')` 把初始化行 `visited[v0] = 1;` 误判「确认顶点」（u 取到
  // 未初始化哨兵 -1，实测"顶点 -1 的最短距离已确定"）。收紧为
  // `visited[u] = 1` 形态（u 作下标才是确认）。
  if line_lower.contains("visited[u]") && line_lower.contains("=") {
    return Some(
      build_step(algorithm, "confirm", "顶点 \{u} 的最短距离已确定"),
    )
  }
  if line_lower.contains("dist[u]") &&
    line_lower.contains("g[u]") &&
    line_lower.contains("+") {
    return Some(
      build_step(algorithm, "relax", "松弛操作，更新邻接顶点距离"),
    )
  }
  None
}

///|
/// Floyd 最短路径。
fn infer_floyd(
  source_line : String,
  vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
) -> @protocol.AlgorithmStepSnapshot? {
  let line_lower = source_line.to_lower()
  let k = match vars.get_int_any(["k"]) {
    Some(v) => v
    None => -1
  }
  if starts_with(line_lower, "for ") && line_lower.contains("k") {
    return Some(
      build_step(algorithm, "outer_loop", "枚举中间顶点 k=\{k}"),
    )
  }
  if line_lower.contains("g[i][k]") &&
    line_lower.contains("g[k][j]") &&
    line_lower.contains("<") {
    return Some(
      build_step(algorithm, "relax", "检查经 k 中转是否更短"),
    )
  }
  None
}

///|
/// 拓扑排序。
fn infer_topological_sort(
  source_line : String,
  vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
) -> @protocol.AlgorithmStepSnapshot? {
  let line_lower = source_line.to_lower()
  let u = match vars.get_int_any(["u"]) {
    Some(v) => v
    None => -1
  }
  if line_lower.contains("indegree") &&
    line_lower.contains("0") &&
    line_lower.contains("queue") {
    return Some(build_step(algorithm, "enqueue", "入度为 0 的顶点入队"))
  }
  // §6-5（v4 #112）：output 挂**真输出行**（printf）——原判据命中 L17 出队行
  //（`int u = queue[front++];`），文案"输出顶点 0"与所挂语句不符（真输出在
  // L18 printf）。出队行独立为 dequeue（词汇只增）。
  if line_lower.contains("printf") {
    return Some(build_step(algorithm, "output", "输出顶点 \{u}"))
  }
  if line_lower.contains("queue[front++]") {
    return Some(build_step(algorithm, "dequeue", "取出队头顶点"))
  }
  if line_lower.contains("indegree") && line_lower.contains("--") {
    return Some(
      build_step(algorithm, "decrease", "删边，邻接点入度减 1"),
    )
  }
  None
}
