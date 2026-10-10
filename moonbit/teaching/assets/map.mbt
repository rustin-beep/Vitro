///|
/// 43 算法文案查表 Map（包初始化求值一次——build_match 的 get(name) 形态）。
/// match 全臂穷尽 = 名单对账的**编译期形态**（新增 AlgoSuggestion 变体
/// 不更新此 match 即红）；`#|` 前导空格（moon 原生语义，排版习惯）在此剥。
pub let suggestion_map : Map[String, String] = build_suggestion_map()

///|
fn build_suggestion_map() -> Map[String, String] {
  let m : Map[String, String] = Map([])
  for entry in suggestions {
    match entry {
      BubbleSort(t) => m.set("bubble_sort", trim_hash_pipe_space(t))
      SelectionSort(t) => m.set("selection_sort", trim_hash_pipe_space(t))
      InsertionSort(t) => m.set("insertion_sort", trim_hash_pipe_space(t))
      QuickSort(t) => m.set("quick_sort", trim_hash_pipe_space(t))
      MergeSort(t) => m.set("merge_sort", trim_hash_pipe_space(t))
      BinarySearch(t) => m.set("binary_search", trim_hash_pipe_space(t))
      HeapSort(t) => m.set("heap_sort", trim_hash_pipe_space(t))
      Bfs(t) => m.set("bfs", trim_hash_pipe_space(t))
      Dfs(t) => m.set("dfs", trim_hash_pipe_space(t))
      Dp(t) => m.set("dp", trim_hash_pipe_space(t))
      ShellSort(t) => m.set("shell_sort", trim_hash_pipe_space(t))
      CountingSort(t) => m.set("counting_sort", trim_hash_pipe_space(t))
      LinkedListDelete(t) =>
        m.set("linked_list_delete", trim_hash_pipe_space(t))
      BstInsert(t) => m.set("bst_insert", trim_hash_pipe_space(t))
      BstSearch(t) => m.set("bst_search", trim_hash_pipe_space(t))
      BstDelete(t) => m.set("bst_delete", trim_hash_pipe_space(t))
      BstValidate(t) => m.set("bst_validate", trim_hash_pipe_space(t))
      StringReverse(t) => m.set("string_reverse", trim_hash_pipe_space(t))
      Gcd(t) => m.set("gcd", trim_hash_pipe_space(t))
      IsPrime(t) => m.set("is_prime", trim_hash_pipe_space(t))
      Hanoi(t) => m.set("hanoi", trim_hash_pipe_space(t))
      SeqList(t) => m.set("seq_list", trim_hash_pipe_space(t))
      LinkedListAppend(t) =>
        m.set("linked_list_append", trim_hash_pipe_space(t))
      CircularQueue(t) => m.set("circular_queue", trim_hash_pipe_space(t))
      LinkedStack(t) => m.set("linked_stack", trim_hash_pipe_space(t))
      LinkedQueue(t) => m.set("linked_queue", trim_hash_pipe_space(t))
      LevelOrder(t) => m.set("level_order", trim_hash_pipe_space(t))
      HashTable(t) => m.set("hash_table", trim_hash_pipe_space(t))
      Josephus(t) => m.set("josephus", trim_hash_pipe_space(t))
      CircularLinkedList(t) =>
        m.set("circular_linked_list", trim_hash_pipe_space(t))
      StaticLinkedList(t) =>
        m.set("static_linked_list", trim_hash_pipe_space(t))
      StringMatchBf(t) => m.set("string_match_bf", trim_hash_pipe_space(t))
      StringMatchKmp(t) => m.set("string_match_kmp", trim_hash_pipe_space(t))
      ThreadedBinaryTree(t) =>
        m.set("threaded_binary_tree", trim_hash_pipe_space(t))
      HuffmanTree(t) => m.set("huffman_tree", trim_hash_pipe_space(t))
      UnionFind(t) => m.set("union_find", trim_hash_pipe_space(t))
      AvlTree(t) => m.set("avl_tree", trim_hash_pipe_space(t))
      PrimMst(t) => m.set("prim_mst", trim_hash_pipe_space(t))
      KruskalMst(t) => m.set("kruskal_mst", trim_hash_pipe_space(t))
      Dijkstra(t) => m.set("dijkstra", trim_hash_pipe_space(t))
      Floyd(t) => m.set("floyd", trim_hash_pipe_space(t))
      TopologicalSort(t) => m.set("topological_sort", trim_hash_pipe_space(t))
      RadixSort(t) => m.set("radix_sort", trim_hash_pipe_space(t))
    }
  }
  m
}

///|
/// `#|` 行净内容的前导空格剥除（moon 原生语义：`#| 文本` 的空格入值——
/// 排版习惯不入数据；jsonmbt #24 已反馈 doctor hint 建议）。
fn trim_hash_pipe_space(s : String) -> String {
  if s.length() > 0 && s[0] == 32 {
    s[1:].to_owned()
  } else {
    s
  }
}
