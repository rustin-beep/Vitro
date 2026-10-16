// teaching/steps·算法目录静态导出（#36，2026-10-16）：43 族目录是引擎
// 知识——判据在 detect_*.mbt（build_match 第二参即中文名）。本表是判据
// 调用点的结构化投影：与 build_match 提取物的零漂移由 Go 闸
// `teaching_annotation_diff --catalog-check` 锁（源码正则提取 ↔ 引擎
// 导出 JSON 对拍）；键集与 suggestion_map 的一致性在 catalog_wbtest。
//
// 字段：group = 分组**建议**（七组自 gen_demo_algorithms 呈现层表上移
// ——组概念属 UI，引擎只出建议值，消费方自由重组）；vis_events = 判据
// 第 5 参是否恒空（`[]` ⇒ vis_events 恒空——dp/string 三族/math 三族共
// 7 族；其余族传 features.compare_lines，vis_events = compare 投影）。
// 排列序 = detect_in_func 分派序（sorting → search → graph → tree →
// structures → string → math，dp 尾挂——B13 契约同构）。

///|
struct AlgoCatalogEntry {
  family : String
  display_name : String
  group : String
  vis_events : Bool
}

///|
/// 七组分组建议（id ↔ 呈现层标签）。
let algo_groups : Array[(String, String)] = [
  ("sorting", "排序"),
  ("search", "查找"),
  ("graph", "图"),
  ("tree", "树"),
  ("structures", "结构"),
  ("string", "字符串"),
  ("mathdp", "数学与动态规划"),
]

///|
/// 43 族目录（族名/中文名/分组建议/vis 能力位）。
let algo_catalog : Array[AlgoCatalogEntry] = [
  {
    family: "bubble_sort",
    display_name: "冒泡排序",
    group: "sorting",
    vis_events: true,
  },
  {
    family: "selection_sort",
    display_name: "选择排序",
    group: "sorting",
    vis_events: true,
  },
  {
    family: "insertion_sort",
    display_name: "插入排序",
    group: "sorting",
    vis_events: true,
  },
  {
    family: "quick_sort",
    display_name: "快速排序",
    group: "sorting",
    vis_events: true,
  },
  {
    family: "merge_sort",
    display_name: "归并排序",
    group: "sorting",
    vis_events: true,
  },
  {
    family: "heap_sort",
    display_name: "堆排序",
    group: "sorting",
    vis_events: true,
  },
  {
    family: "shell_sort",
    display_name: "希尔排序",
    group: "sorting",
    vis_events: true,
  },
  {
    family: "counting_sort",
    display_name: "计数排序",
    group: "sorting",
    vis_events: true,
  },
  {
    family: "radix_sort",
    display_name: "基数排序",
    group: "sorting",
    vis_events: true,
  },
  {
    family: "binary_search",
    display_name: "二分查找",
    group: "search",
    vis_events: true,
  },
  {
    family: "bfs",
    display_name: "BFS 广度优先搜索",
    group: "graph",
    vis_events: true,
  },
  {
    family: "dfs",
    display_name: "DFS 深度优先搜索",
    group: "graph",
    vis_events: true,
  },
  {
    family: "prim_mst",
    display_name: "Prim 最小生成树",
    group: "graph",
    vis_events: true,
  },
  {
    family: "kruskal_mst",
    display_name: "Kruskal 最小生成树",
    group: "graph",
    vis_events: true,
  },
  {
    family: "dijkstra",
    display_name: "Dijkstra 最短路径",
    group: "graph",
    vis_events: true,
  },
  {
    family: "floyd",
    display_name: "Floyd 最短路径",
    group: "graph",
    vis_events: true,
  },
  {
    family: "topological_sort",
    display_name: "拓扑排序",
    group: "graph",
    vis_events: true,
  },
  {
    family: "bst_validate",
    display_name: "BST 合法性校验",
    group: "tree",
    vis_events: true,
  },
  {
    family: "bst_insert",
    display_name: "BST 插入",
    group: "tree",
    vis_events: true,
  },
  {
    family: "bst_search",
    display_name: "BST 查找",
    group: "tree",
    vis_events: true,
  },
  {
    family: "bst_delete",
    display_name: "BST 删除",
    group: "tree",
    vis_events: true,
  },
  {
    family: "level_order",
    display_name: "层序遍历",
    group: "tree",
    vis_events: true,
  },
  {
    family: "avl_tree",
    display_name: "AVL 树",
    group: "tree",
    vis_events: true,
  },
  {
    family: "huffman_tree",
    display_name: "哈夫曼树",
    group: "tree",
    vis_events: true,
  },
  {
    family: "threaded_binary_tree",
    display_name: "线索二叉树",
    group: "tree",
    vis_events: true,
  },
  {
    family: "linked_list_delete",
    display_name: "链表删除",
    group: "structures",
    vis_events: true,
  },
  {
    family: "seq_list",
    display_name: "顺序表",
    group: "structures",
    vis_events: true,
  },
  {
    family: "linked_list_append",
    display_name: "链表尾插",
    group: "structures",
    vis_events: true,
  },
  {
    family: "circular_queue",
    display_name: "循环队列",
    group: "structures",
    vis_events: true,
  },
  {
    family: "linked_stack",
    display_name: "链栈",
    group: "structures",
    vis_events: true,
  },
  {
    family: "linked_queue",
    display_name: "链队列",
    group: "structures",
    vis_events: true,
  },
  {
    family: "hash_table",
    display_name: "哈希表",
    group: "structures",
    vis_events: true,
  },
  {
    family: "josephus",
    display_name: "约瑟夫环",
    group: "structures",
    vis_events: true,
  },
  {
    family: "circular_linked_list",
    display_name: "循环链表",
    group: "structures",
    vis_events: true,
  },
  {
    family: "static_linked_list",
    display_name: "静态链表",
    group: "structures",
    vis_events: true,
  },
  {
    family: "union_find",
    display_name: "并查集",
    group: "structures",
    vis_events: true,
  },
  {
    family: "string_reverse",
    display_name: "字符串反转",
    group: "string",
    vis_events: false,
  },
  {
    family: "string_match_bf",
    display_name: "朴素模式匹配",
    group: "string",
    vis_events: false,
  },
  {
    family: "string_match_kmp",
    display_name: "KMP 模式匹配",
    group: "string",
    vis_events: false,
  },
  {
    family: "gcd",
    display_name: "最大公约数",
    group: "mathdp",
    vis_events: false,
  },
  {
    // is_prime 分组分歧登记：判据属 math 族（detect_math.mbt 分派序），
    // 呈现归 search——跟 gen_demo_algorithms 现役分组（分组建议的意义 =
    // demo 切换 catalog 消费后侧栏呈现零变化）
    family: "is_prime",
    display_name: "素数判断",
    group: "search",
    vis_events: false,
  },
  {
    family: "hanoi",
    display_name: "汉诺塔",
    group: "mathdp",
    vis_events: false,
  },
  {
    family: "dp",
    display_name: "动态规划",
    group: "mathdp",
    vis_events: false,
  },
]

///|
/// algorithms.catalog JSON 出口（#36）——显式 emitter 纪律（B 级锚，
/// error_catalog 同款）：字段序 schema/total/groups/algorithms，字符串
/// 转义经 @util.json_escape 单点（中文名无控制字节，恒等——接线纪律
/// 优先于必要性）。
pub fn export_algorithms_catalog_json() -> String {
  let buf = StringBuilder()
  buf.write_string("{\"schema\":\"algorithms.catalog/1\"")
  buf.write_string(",\"total\":\{algo_catalog.length()}")
  buf.write_string(",\"groups\":[")
  for i, g in algo_groups {
    if i > 0 {
      buf.write_string(",")
    }
    buf.write_string("{\"id\":\{json_str(g.0)},\"label\":\{json_str(g.1)}}")
  }
  buf.write_string("]")
  buf.write_string(",\"algorithms\":[")
  for i, e in algo_catalog {
    if i > 0 {
      buf.write_string(",")
    }
    buf.write_string(
      "{\"family\":\{json_str(e.family)},\"display_name\":\{json_str(e.display_name)},\"group\":\{json_str(e.group)},\"vis_events\":\{e.vis_events}}",
    )
  }
  buf.write_string("]}")
  buf.to_string()
}

///|
fn json_str(s : String) -> String {
  "\"" + @util.json_escape(s) + "\""
}
