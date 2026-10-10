// teaching/assets·43 算法教学文案【真源】（issue #60 批一，2026-10-10）。
//
// 管线（双出口架构）：jsonmbt build → 同目录 suggestions.json（教师面，
// 改后 import --fill 回本源——类型头逐字节保留）；引擎消费走 map.mbt 的
// suggestion_map（43 臂穷尽 match = 编译期名单闸）。
//
// 形态注（moon fmt × jsonmbt 交互，2026-10-10）：本文件是包成员会被
// moon fmt 规范——多行 payload 会被 fmt 加圆括号（`B((#| …))` 形态）；
// jsonmbt #25 修复后剥冗余圆括号，#| 多行长文案与 fmt 稳定共存。
// `#|` 行净内容的首空格为 moon 原生语义（入值），map.mbt derive 侧剥。

///|
pub enum AlgoSuggestion {
  BubbleSort(String)
  SelectionSort(String)
  InsertionSort(String)
  QuickSort(String)
  MergeSort(String)
  BinarySearch(String)
  HeapSort(String)
  Bfs(String)
  Dfs(String)
  Dp(String)
  ShellSort(String)
  CountingSort(String)
  LinkedListDelete(String)
  BstInsert(String)
  BstSearch(String)
  BstDelete(String)
  BstValidate(String)
  StringReverse(String)
  Gcd(String)
  IsPrime(String)
  Hanoi(String)
  SeqList(String)
  LinkedListAppend(String)
  CircularQueue(String)
  LinkedStack(String)
  LinkedQueue(String)
  LevelOrder(String)
  HashTable(String)
  Josephus(String)
  CircularLinkedList(String)
  StaticLinkedList(String)
  StringMatchBf(String)
  StringMatchKmp(String)
  ThreadedBinaryTree(String)
  HuffmanTree(String)
  UnionFind(String)
  AvlTree(String)
  PrimMst(String)
  KruskalMst(String)
  Dijkstra(String)
  Floyd(String)
  TopologicalSort(String)
  RadixSort(String)
}

///|
pub let suggestions : Array[AlgoSuggestion] = [
  BubbleSort(
    (
      #| 冒泡排序：通过相邻元素两两比较并交换，将最大元素逐步「冒泡」到数组末尾。时间复杂度 O(n²)。
    ),
  ),
  SelectionSort(
    (
      #| 选择排序：每次从未排序部分选择最小元素，放到已排序部分末尾。时间复杂度 O(n²)。
    ),
  ),
  InsertionSort(
    (
      #| 插入排序：将元素逐个插入到已排序部分的正确位置。时间复杂度 O(n²)，对近乎有序的数组效率很高。
    ),
  ),
  QuickSort(
    (
      #| 快速排序：通过分治法，选取枢轴将数组分区，再递归排序子数组。平均时间复杂度 O(n log n)。
    ),
  ),
  MergeSort(
    (
      #| 归并排序：将数组递归分成两半，排序后合并。时间复杂度稳定为 O(n log n)。
    ),
  ),
  BinarySearch(
    (
      #| 二分查找：在有序数组中每次将搜索范围减半。时间复杂度 O(log n)。
    ),
  ),
  HeapSort(
    (
      #| 堆排序：利用堆数据结构进行排序。先建堆再反复取出堆顶元素。时间复杂度 O(n log n)。
    ),
  ),
  Bfs(
    (
      #| BFS 广度优先搜索：从起点出发，逐层扩展访问邻居。适合求最短路径。
    ),
  ),
  Dfs(
    (
      #| DFS 深度优先搜索：从起点出发，沿着一条路径走到尽头再回溯。适合连通性判断。
    ),
  ),
  Dp(
    (
      #| 动态规划：将复杂问题分解为子问题，保存子问题答案避免重复计算。
    ),
  ),
  ShellSort(
    (
      #| 希尔排序：通过增量分组进行插入排序，逐步缩小增量至 1。时间复杂度介于 O(n log n) 和 O(n²) 之间。
    ),
  ),
  CountingSort(
    (
      #| 计数排序：用统计数组记录元素出现次数，适合数据范围小的场景。时间复杂度 O(n+k)。
    ),
  ),
  LinkedListDelete(
    (
      #| 链表删除：遍历链表找到目标节点，调整指针并释放内存。
    ),
  ),
  BstInsert(
    (
      #| BST 插入：利用二叉搜索树性质，递归找到正确位置插入新节点。
    ),
  ),
  BstSearch(
    (
      #| BST 查找：利用二叉搜索树性质，每次比较可排除一半子树，平均时间复杂度 O(log n)。
    ),
  ),
  BstDelete(
    (
      #| BST 删除：定位目标节点后按叶子/单孩子/双孩子三种情况重构子树，双孩子时用中序后继替换。
    ),
  ),
  BstValidate(
    (
      #| BST 合法性校验：为每个节点维护 (min, max) 开区间，递归校验节点值不越界，区间随下钻逐层收窄。
    ),
  ),
  StringReverse(
    (
      #| 字符串反转：利用双指针从两端向中间交换字符。
    ),
  ),
  Gcd(
    (
      #| 辗转相除法：gcd(a,b) = gcd(b, a mod b)，直到余数为 0。
    ),
  ),
  IsPrime(
    (
      #| 素数判断：试除法，只需检查 2 到 sqrt(n) 是否能整除。
    ),
  ),
  Hanoi(
    (
      #| 汉诺塔：经典递归问题，将 n 个盘子分解为移动 n-1 个盘子 + 移动最底下盘子 + 再移动 n-1 个盘子。
    ),
  ),
  SeqList(
    (
      #| 顺序表：用连续数组存储数据，支持按位置插入、删除和查找。
    ),
  ),
  LinkedListAppend(
    (
      #| 链表尾插法：将新节点追加到链表末尾，保持插入顺序。
    ),
  ),
  CircularQueue(
    (
      #| 循环队列：用数组实现队列，front/rear 指针循环移动，牺牲一个单元区分空和满。
    ),
  ),
  LinkedStack(
    (
      #| 链栈：用单链表实现栈，top 指针指向栈顶，没有固定容量限制。
    ),
  ),
  LinkedQueue(
    (
      #| 链队列：用链表实现队列，front 指向队头，rear 指向队尾。
    ),
  ),
  LevelOrder(
    (
      #| 层序遍历：利用队列按从上到下、从左到右的顺序访问二叉树节点。
    ),
  ),
  HashTable(
    (
      #| 哈希表：通过哈希函数直接定位存储位置，理想情况下查找时间复杂度 O(1)。
    ),
  ),
  Josephus(
    (
      #| 约瑟夫环：经典的循环报数淘汰问题，可用数组模拟圆圈解决。
    ),
  ),
  CircularLinkedList(
    (
      #| 循环链表：尾节点 next 回指头节点，遍历时需用 do-while 判断终止。
    ),
  ),
  StaticLinkedList(
    (
      #| 静态链表：用数组游标模拟指针，下标 0 作为备用链表头。
    ),
  ),
  StringMatchBf(
    (
      #| 朴素模式匹配：双指针逐位比较，失配后主串回溯、模式串归零。时间复杂度 O(m·n)。
    ),
  ),
  StringMatchKmp(
    (
      #| KMP 模式匹配：利用 next 数组避免主串回溯，时间复杂度 O(m+n)。
    ),
  ),
  ThreadedBinaryTree(
    (
      #| 线索二叉树：利用空指针域存储中序前驱和后继，实现无栈遍历。
    ),
  ),
  HuffmanTree(
    (
      #| 哈夫曼树：每次选两个最小权值节点合并，构造带权路径长度最小的二叉树。
    ),
  ),
  UnionFind(
    (
      #| 并查集：用数组表示森林，支持路径压缩和按秩合并，近乎 O(1) 的查询与合并。
    ),
  ),
  AvlTree(
    (
      #| AVL 树：自平衡二叉搜索树，通过旋转保持左右子树高度差不超过 1。
    ),
  ),
  PrimMst(
    (
      #| Prim 最小生成树：从顶点出发，每次选连接两集合的最小边，贪心扩展生成树。
    ),
  ),
  KruskalMst(
    (
      #| Kruskal 最小生成树：按边权排序后用并查集判环，贪心选取不形成环的边。
    ),
  ),
  Dijkstra(
    (
      #| Dijkstra 最短路径：单源最短路径，每次选距离最近的未确定顶点进行松弛。
    ),
  ),
  Floyd(
    (
      #| Floyd 最短路径：三重循环枚举中间点，动态规划求所有顶点对最短路径。
    ),
  ),
  TopologicalSort(
    (
      #| 拓扑排序：Kahn 算法，利用入度和队列，输出有向无环图的一个线性序列。
    ),
  ),
  RadixSort(
    (
      #| 基数排序：按位进行稳定计数排序，从低位到高位依次分配收集。时间复杂度 O(d·(n+k))。
    ),
  ),
]
