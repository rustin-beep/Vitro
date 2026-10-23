// #224 审阅 P1-3 端到端锚（2026-10-23）：真实教科书 heapsort 源码
//（函数名不含 heap、堆子索引 a[2*i+1] 直写、driver n/2-1 建堆起点）
// 经 serve compile 通道断言 heap_sort 结构命中——审阅插桩实证旧实现
// 「收紧即关闭」（check_compare_expr 独立递归看不到比较表达式里的
// 堆子索引 + 三合取证据跨函数，matches 恒空）。修复 = 比较通道 Index
// 臂/声明 init 补堆算术判定 + 结构分支 OR 链。证红形态：禁用两处
// 补判后本锚红（matches 空）。

///|
/// 直写形态（a[2*i+1] 作下标）：siftDown 比较行 + driver 建堆起点。
test "issue224_heap_realcode_direct_index_detected" {
  let s = @session.Session::new()
  let jsrc = "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"" +
    "#include <stdio.h>\\n" +
    "void siftDown(int a[], int n, int i) {\\n" +
    "    int largest = i;\\n" +
    "    if (2 * i + 1 < n && a[2 * i + 1] > a[largest]) largest = 2 * i + 1;\\n" +
    "    if (2 * i + 2 < n && a[2 * i + 2] > a[largest]) largest = 2 * i + 2;\\n" +
    "    if (largest != i) {\\n" +
    "        int t = a[i]; a[i] = a[largest]; a[largest] = t;\\n" +
    "        siftDown(a, n, largest);\\n" +
    "    }\\n" +
    "}\\n" +
    "void sortArray(int a[], int n) {\\n" +
    "    for (int i = n / 2 - 1; i >= 0; i--) siftDown(a, n, i);\\n" +
    "    for (int i = n - 1; i > 0; i--) {\\n" +
    "        int t = a[0]; a[0] = a[i]; a[i] = t;\\n" +
    "        siftDown(a, n, 0);\\n" +
    "    }\\n" +
    "}\\n" +
    "int main() {\\n" +
    "    int a[5] = {5, 3, 8, 1, 2};\\n" +
    "    sortArray(a, 5);\\n" +
    "    printf(\\\"%d %d %d %d %d\\\", a[0], a[1], a[2], a[3], a[4]);\\n" +
    "    return 0;\\n" +
    "}\\n" +
    "\"}}"
  let (cresp, _) = serve_handle(s, jsrc)
  assert_true(cresp.contains("\"ok\":true"), msg="编译须成功")
  // siftDown：比较行堆子索引（比较通道 Index 臂）+ swap → OR 链结构命中
  let mut sift_hit = false
  for m in s.compile.algorithm_matches {
    if m.func_name == "siftDown" &&
      m.name == "heap_sort" &&
      m.evidence == "structure" {
      sift_hit = true
    }
  }
  assert_true(
    sift_hit,
    msg="siftDown（无名+直写堆子索引+swap）应结构命中 heap_sort——审阅 P1-3 端到端锚",
  )
}

///|
/// 间接形态（int l = 2*i+1 声明 + a[l] 下标）：堆算术在声明 init——
/// 声明臂判定覆盖（CLRS 风）。
test "issue224_heap_realcode_indirect_index_detected" {
  let s = @session.Session::new()
  let jsrc = "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"" +
    "#include <stdio.h>\\n" +
    "void sift(int a[], int n, int i) {\\n" +
    "    int largest = i;\\n" +
    "    int l = 2 * i + 1;\\n" +
    "    int r = 2 * i + 2;\\n" +
    "    if (l < n && a[l] > a[largest]) largest = l;\\n" +
    "    if (r < n && a[r] > a[largest]) largest = r;\\n" +
    "    if (largest != i) {\\n" +
    "        int t = a[i]; a[i] = a[largest]; a[largest] = t;\\n" +
    "        sift(a, n, largest);\\n" +
    "    }\\n" +
    "}\\n" +
    "int main() {\\n" +
    "    int a[4] = {4, 1, 3, 2};\\n" +
    "    for (int i = 4 / 2 - 1; i >= 0; i--) sift(a, 4, i);\\n" +
    "    printf(\\\"%d %d %d %d\\\", a[0], a[1], a[2], a[3]);\\n" +
    "    return 0;\\n" +
    "}\\n" +
    "\"}}"
  let (cresp, _) = serve_handle(s, jsrc)
  assert_true(cresp.contains("\"ok\":true"), msg="编译须成功")
  let mut hit = false
  for m in s.compile.algorithm_matches {
    if m.name == "heap_sort" && m.evidence == "structure" {
      hit = true
    }
  }
  assert_true(
    hit,
    msg="间接形态（声明 init 堆算术）应结构命中 heap_sort",
  )
}
