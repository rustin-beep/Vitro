// teaching/steps·判据 tree 族（S8 teaching 批三号，2026-10-01）：
// detector/tree.rs:6-120 照搬——bst 家族「名字+语义双条件」（二审 P0-B
// 方案②：valid 优先于 insert；裸命名靠 TreeNode 参数语境补齐——
// is_treenode_ctx 整名匹配排除 HashEntry/RBNode/BTreeNode 同形）；
// level_order/avl/huffman/threaded 命名判据。

///|
pub fn detect_tree(
  name_lower : String,
  features : FuncFeatures,
  func_name : String,
  line : Int,
) -> Array[@session.AlgorithmMatch] {
  let matches : Array[@session.AlgorithmMatch] = []
  // —— bst 家族（else-if 链：校验 > 插入 > 查找 > 删除）——
  let has_bst = has_word(func_name, "bst")
  let in_tree_ctx = has_bst || features.is_treenode_ctx
  let valid_word = has_word(func_name, "valid") ||
    has_word(func_name, "validate")
  let insert_word = has_word(func_name, "insert") || has_word(func_name, "add")
  let search_word = has_word(func_name, "search") || has_word(func_name, "find")
  let delete_word = has_word(func_name, "delete") ||
    has_word(func_name, "remove")
  if valid_word && in_tree_ctx {
    matches.push(
      build_match(
        "bst_validate",
        "BST 合法性校验",
        func_name,
        line,
        features.compare_lines,
      ),
    )
  } else if insert_word && in_tree_ctx {
    matches.push(
      build_match(
        "bst_insert",
        "BST 插入",
        func_name,
        line,
        features.compare_lines,
      ),
    )
  } else if search_word && in_tree_ctx && features.is_recursive {
    // 查找要求递归：bstDelete 的迭代 findMin(TreeNode*) 不算
    matches.push(
      build_match(
        "bst_search",
        "BST 查找",
        func_name,
        line,
        features.compare_lines,
      ),
    )
  } else if delete_word && in_tree_ctx {
    matches.push(
      build_match(
        "bst_delete",
        "BST 删除",
        func_name,
        line,
        features.compare_lines,
      ),
    )
  }
  // 层序遍历
  if name_lower.contains("levelorder") || name_lower.contains("level_order") {
    matches.push(
      build_match(
        "level_order",
        "层序遍历",
        func_name,
        line,
        features.compare_lines,
      ),
    )
  }
  // AVL 树
  if name_lower.contains("avl") {
    matches.push(
      build_match(
        "avl_tree",
        "AVL 树",
        func_name,
        line,
        features.compare_lines,
      ),
    )
  }
  // 哈夫曼树
  if name_lower.contains("huffman") {
    matches.push(
      build_match(
        "huffman_tree",
        "哈夫曼树",
        func_name,
        line,
        features.compare_lines,
      ),
    )
  }
  // 线索二叉树
  if name_lower.contains("thread") && name_lower.contains("tree") {
    matches.push(
      build_match(
        "threaded_binary_tree",
        "线索二叉树",
        func_name,
        line,
        features.compare_lines,
      ),
    )
  }
  matches
}
