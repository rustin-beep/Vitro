// M5 概念图激活（knowledge_graph.rs 照搬，2026-10-02）：错误码/AST 特征
// 激活 + 1-hop 邻居收集 + 前置路径 DFS。**遍历序契约**：边遍历 = 源声明
// 序（concepts_gen 保序生成）——Rust Vec 声明序遍历的等价物，DFS 前置
// 路径的输出序列依赖此序（勘察 spike ②「序列逐项等价」判据）。

///|
/// 节点索引（25 条小表——线性构建，Map 保查询 O(1)）。
fn node_map() -> Map[String, ConceptNode] {
  let m : Map[String, ConceptNode] = Map([])
  for n in concept_nodes() {
    m.set(n.id, n)
  }
  m
}

///|
/// 按错误码激活概念（Rust activate_from_error 照搬：映射表 → 逐概念
/// 带 1-hop 邻居；映射表无此码返回空）。
pub fn activate_from_error(error_code : Int) -> Array[ActivatedConcept] {
  let result : Array[ActivatedConcept] = []
  let nmap = node_map()
  match error_concept_map().get(error_code) {
    Some(concept_ids) =>
      for cid in concept_ids {
        match nmap.get(cid) {
          Some(node) =>
            result.push(ActivatedConcept::{
              node,
              activated_by: "Error",
              neighbors: collect_neighbors(cid, nmap),
            })
          None => ()
        }
      }
    None => ()
  }
  result
}

///|
/// 按 AST 特征关键词激活概念（Rust activate_from_ast 照搬——特征词 →
/// 概念对的硬映射 + 跨特征去重保首现序）。
pub fn activate_from_ast(features : Array[String]) -> Array[ActivatedConcept] {
  let result : Array[ActivatedConcept] = []
  let nmap = node_map()
  let activated : Set[String] = Set([])
  for feature in features {
    let matched : Array[String] = match feature {
      "malloc" | "free" | "calloc" | "realloc" => ["HeapMemory", "Pointer"]
      "array_index" | "arr[" | "a[" => ["Array", "BoundaryCondition"]
      "pointer_deref" | "*p" => ["Pointer", "Dereference"]
      "for_loop" => ["ForLoop", "BoundaryCondition"]
      "while_loop" => ["WhileLoop", "BoundaryCondition"]
      "if_statement" => ["IfSwitch", "LogicOp"]
      "function_call" => ["FunctionCall", "ParameterPassing"]
      "recursive_call" => ["Recursion", "BoundaryCondition"]
      "struct_member" | "." | "->" => ["StructLayout"]
      "scanf" => ["AddressOf"]
      "printf" => ["ArithOp"]
      _ => []
    }
    if matched.is_empty() {
      continue
    }
    for cid in matched {
      if !activated.contains(cid) {
        activated.add(cid)
        match nmap.get(cid) {
          Some(node) =>
            result.push(ActivatedConcept::{
              node,
              activated_by: "AST",
              neighbors: collect_neighbors(cid, nmap),
            })
          None => ()
        }
      }
    }
  }
  result
}

///|
/// 前置学习路径（Rust find_prerequisite_path 照搬）：沿 Prerequisite/
/// LeadsTo 边递归下钻（visited 防环）后序 push——输出序 = 深度序先父后子。
pub fn find_prerequisite_path(target_id : String) -> Array[ConceptNode] {
  let nmap = node_map()
  let visited : Set[String] = Set([])
  let path : Array[ConceptNode] = []
  prereq_dfs(target_id, nmap, visited, path)
  path
}

///|
fn prereq_dfs(
  id : String,
  nmap : Map[String, ConceptNode],
  visited : Set[String],
  path : Array[ConceptNode],
) -> Unit {
  if visited.contains(id) {
    return
  }
  visited.add(id)
  for edge in concept_edges() {
    if edge.to_id == id &&
      (edge.relation == "Prerequisite" || edge.relation == "LeadsTo") {
      prereq_dfs(edge.from_id, nmap, visited, path)
    }
  }
  match nmap.get(id) {
    Some(node) => path.push(node)
    None => ()
  }
}

///|
/// 1-hop 邻居收集（Rust collect_neighbors 照搬——边声明序遍历；
/// 反向边（edge.to == 本节点）的 is_prerequisite = relation==Prerequisite）。
fn collect_neighbors(
  node_id : String,
  nmap : Map[String, ConceptNode],
) -> Array[NeighborConcept] {
  let neighbors : Array[NeighborConcept] = []
  for edge in concept_edges() {
    let other : String = if edge.from_id == node_id {
      edge.to_id
    } else if edge.to_id == node_id {
      edge.from_id
    } else {
      continue
    }
    let is_prereq = edge.to_id == node_id && edge.relation == "Prerequisite"
    match nmap.get(other) {
      Some(n) =>
        neighbors.push(NeighborConcept::{
          node: n,
          relation: edge.relation,
          strength: edge.strength,
          is_prerequisite: is_prereq,
        })
      None => ()
    }
  }
  neighbors
}
