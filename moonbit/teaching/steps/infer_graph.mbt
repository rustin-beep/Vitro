// teaching/steps·infer graph 族（S8 teaching 批四号，2026-10-01）：
// 七算法照搬 vitro_algorithm_steps/src/graph.rs:1-222——含全部审阅修复
// 语义：BFS 起点入队文案区分（U1#1 P1-6）/ prim 的 lowcost[k]=0 收紧
//（U1#1 P1-76——初始化行 lowcost[0]=0 不误判）/ dijkstra 的 visited[u]=1
// 收紧（U1#1 P0-1——初始化行 visited[v0]=1 不产「顶点 -1 已确定”）/
// 拓扑排序 output 挂真输出行（§6-5 v4 #112）。

///|
/// BFS 广度优先搜索。
fn infer_bfs(
  source_line : String,
  vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
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
  if line_lower.contains("visited") && line_lower.contains("=") {
    return Some(
      build_step(algorithm, "visit", "标记节点 \{u} 为已访问"),
    )
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
  if line_lower.contains("visited") && line_lower.contains("=") {
    return Some(
      build_step(algorithm, "visit", "标记节点 \{u} 为已访问"),
    )
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
