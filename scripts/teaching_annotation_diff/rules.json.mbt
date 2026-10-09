// 手写真源（jsonmbt import 产初版后人工建模接管，4913eece；本文件即真相源，直接编辑后
// `jsonmbt build --pretty` 再生 .json 供闸门消费——AGENTS.md 第 13 条流程）。

// Exemption 类型手工定（J4001 空数组占位——照消费方
// scripts/teaching_annotation_diff/main.go 的 Exemption struct 六字段；
// #14 --fill 前的 Never 替换）

///|
pub struct Exemption {
  template : String
  kind : String
  algorithm : String
  phase : String
  desc : String
  reason : String
}

///|
pub struct Rules {
  as_of : String
  migrated_algorithms : Array[String]
  step_budget : Int
  exemptions : Array[Exemption]
}

///|
pub let rules : Rules = Rules::{
  as_of: "2026-10-02",
  migrated_algorithms: [
    "avl_tree", "bfs", "binary_search", "bst_delete", "bst_insert", "bst_search",
    "bst_validate", "bubble_sort", "circular_linked_list", "circular_queue", "counting_sort",
    "dfs", "dijkstra", "dp", "floyd", "gcd", "hanoi", "hash_table", "heap_sort",
    "huffman_tree", "insertion_sort", "is_prime", "josephus", "kruskal_mst", "level_order",
    "linked_list_append", "linked_list_delete", "linked_queue", "linked_stack", "merge_sort",
    "prim_mst", "quick_sort", "radix_sort", "selection_sort", "seq_list", "shell_sort",
    "static_linked_list", "string_match_bf", "string_match_kmp", "string_reverse",
    "threaded_binary_tree", "topological_sort", "union_find",
  ],
  step_budget: 4000,
  exemptions: [],
}
