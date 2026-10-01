// teaching/steps·detect graph 族（S8 teaching 批四号）：七算法判据照搬
// detector/graph.rs:6-76——U1#1 P0-2 收紧后的**全命名主导**形态（BFS/DFS
// 旧结构分支已删——收紧注释语义照搬；features 仅贡献 compare_lines 投影，
// 判据零结构特征消费 ⇒ moon.pkg 头注「graph 族消费 back_edge」悬案以
// 「收紧版判据零 CFG 消费」销案，CFG 决策继续悬置到 analysis 域）。

///|
/// graph 族判据（七算法——全命名主导；U1#1 P0-2 收紧注释照搬）。
pub fn detect_graph(
  name_lower : String,
  features : FuncFeatures,
  func_name : String,
  line : Int,
) -> Array[@protocol.AlgorithmMatch] {
  let matches : Array[@protocol.AlgorithmMatch] = []
  // BFS 广度优先搜索
  // U1#1 P0-2（用户复审实锤）：旧结构分支 `contains("search") &&
  // has_single_loop && cfg_has_back_edge` 把 linearSearch / hashTable /
  // stringBasicOps 等一切「带回边的单循环查找」全判成 BFS——结构特征
  // 缺队列/visited 判据，误判面比命名子串更大。收紧为命名主导；
  // 漏检（未叫 bfs 名的 BFS 实现）由模板命名规范兜底。
  if name_lower.contains("bfs") || name_lower.contains("breadth") {
    matches.push(
      build_match(
        "bfs",
        "BFS 广度优先搜索",
        func_name,
        line,
        features.compare_lines,
      ),
    )
  }
  // DFS 深度优先搜索
  // U1#1 P0-2：同 BFS——`is_recursive && contains("search")` 结构分支
  // 会把递归的 binarySearch / interpolationSearch 等误判 DFS。命名主导。
  if name_lower.contains("dfs") || name_lower.contains("depth") {
    matches.push(
      build_match(
        "dfs",
        "DFS 深度优先搜索",
        func_name,
        line,
        features.compare_lines,
      ),
    )
  }
  // Prim 最小生成树
  if name_lower.contains("prim") {
    matches.push(
      build_match(
        "prim_mst",
        "Prim 最小生成树",
        func_name,
        line,
        features.compare_lines,
      ),
    )
  }
  // Kruskal 最小生成树
  if name_lower.contains("kruskal") {
    matches.push(
      build_match(
        "kruskal_mst",
        "Kruskal 最小生成树",
        func_name,
        line,
        features.compare_lines,
      ),
    )
  }
  // Dijkstra 最短路径
  if name_lower.contains("dijkstra") {
    matches.push(
      build_match(
        "dijkstra",
        "Dijkstra 最短路径",
        func_name,
        line,
        features.compare_lines,
      ),
    )
  }
  // Floyd 最短路径
  if name_lower.contains("floyd") {
    matches.push(
      build_match(
        "floyd",
        "Floyd 最短路径",
        func_name,
        line,
        features.compare_lines,
      ),
    )
  }
  // 拓扑排序
  if name_lower.contains("topolog") {
    matches.push(
      build_match(
        "topological_sort",
        "拓扑排序",
        func_name,
        line,
        features.compare_lines,
      ),
    )
  }
  matches
}
