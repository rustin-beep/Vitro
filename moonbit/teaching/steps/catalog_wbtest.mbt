// catalog 键集对账（#36）：algo_catalog ↔ known_suggestion_keys 43 键
// 互含 + groups 覆盖 + family 无重复。#130 批③a 起对账对象从烘焙表改
// 引擎侧值域名单（catalog ≡ known〔本锚〕+ known ≡ 烘焙表〔content_data
// wbtest〕分层证明——wbtest 不可 import content_data，直查烘焙表会
// 在 lean 引擎测试态恒空）。与 build_match 调用点的对账（源码正则
// 提取 ↔ 引擎导出）在 Go 闸 teaching_annotation_diff --catalog-check
//（wbtest 拿不到源码文本，分层锁）。

///|
test "catalog_keys_match_suggestion_map" {
  let mut ok = true
  for e in algo_catalog {
    if !@assets.known_suggestion_keys.contains(e.family) {
      ok = false
      println("catalog 族无文案：\{e.family}")
    }
  }
  // 反向：43 名单每键都在 catalog
  let fams : Set[String] = Set([])
  for e in algo_catalog {
    fams.add(e.family)
  }
  for k in @assets.known_suggestion_keys {
    if !fams.contains(k) {
      ok = false
      println("文案键不在 catalog：\{k}")
    }
  }
  inspect(ok, content="true")
  inspect(algo_catalog.length(), content="43")
}

///|
test "catalog_groups_cover_all_entries" {
  let gids : Set[String] = Set([])
  for g in algo_groups {
    gids.add(g.0)
  }
  let mut ok = true
  for e in algo_catalog {
    if !gids.contains(e.group) {
      ok = false
      println("catalog 组 id 未登记：\{e.group}")
    }
  }
  inspect(ok, content="true")
  inspect(algo_groups.length(), content="7")
}

///|
test "catalog_families_unique" {
  let seen : Set[String] = Set([])
  let mut ok = true
  for e in algo_catalog {
    if seen.contains(e.family) {
      ok = false
      println("family 重复：\{e.family}")
    }
    seen.add(e.family)
  }
  inspect(ok, content="true")
}

///|
test "catalog_json_emits_all_43" {
  // emitter 冒烟：total=43 + 首末条在 + 合法转义通道（控制字节零）
  let j = export_algorithms_catalog_json()
  inspect(j.contains("\"total\":43"), content="true")
  inspect(j.contains("\"family\":\"bubble_sort\""), content="true")
  inspect(j.contains("\"family\":\"dp\""), content="true")
  inspect(j.contains("\"display_name\":\"冒泡排序\""), content="true")
}
