// Vitro · 课目一句话说明（#222 P2 目录页文案补全，2026-10-23）。
//
// 形态：键 = "<chap>/<id>"，值 = 一句话说明——说清「这门课让你看到什么执行现象」
// （哪一步动作、哪个结构变了、输出落在哪儿），不是课程大纲，也不是知识点列表。
//
// 口径（诚实边界）：
//   · 只写源码里能读到的执行现象——不写复杂度/性能结论（无实测依据不写），
//     不写「最重要 / 必学 / 经典」这类评价性措辞。
//   · case 课（第〇章基础课）已有真实 blurb（在 cases.js 里），本表不收；
//     本表只覆盖算法章 / 变体 / 扩展练习共 96 门。
//   · 键缺失时 courseIndex 回落到原占位文案（不白屏、不改既有行为）。
//
// ⚠️ 键碰撞一处（数据面既成事实，非本表引入）：structures 章的族课 id 是
//   `josephus`，其变体 tpl 也叫 `josephus`——两者在目录页是**两行**（行键
//   `kind/famId/id` 不同，见 E2E F7 锚），但 <chap>/<id> 键完全相同。故
//   96 门非 case 课 = 95 个键，josephus 两行共用一条说明（写的是两者共同
//   的「数满 m 淘汰一个」现象）。若日后要求两行文案分开，键需再加一段
//   <famId> 前缀——本表按「键 = <chap>/<id>」契约先保持不歧义。
//
// 数据面不动：cases.js / algorithms.js 由生成器发射，本文件是纯前端文案层，
// 与课程数据解耦（改了文案不必重跑生成器）。
"use strict";

/** 键 = "<chap>/<id>"；值为该课的一句话执行现象说明。 */
export const COURSE_BLURB: Record<string, string> = {
  // ── 排序（9） ───────────────────────────────────────────────────────
  "sorting/bubble_sort": "相邻两两比较、逆序就交换，每轮把最大值挤到末尾，终态有序。",
  "sorting/insertion_sort": "取出待插元素一路右移腾出空位，落位后已排好一段有序前缀。",
  "sorting/merge_sort": "递归劈成两半再逐个合并回写，临时数组 L/R 的搬运看得见。",
  "sorting/quick_sort": "以末元素为基准做划分，左右两段再各自递归——划分位置一目了然。",
  "sorting/selection_sort": "每轮只找一次最小值下标，只交换一次——有序前缀一格一格长。",
  "sorting/heap_sort": "先堆成大顶堆，再把堆顶换到末尾并缩小堆——逐轮看堆顶被取走。",
  "sorting/counting_sort": "先数每个值出现几次，再按计数把值依次写回数组。",
  "sorting/shell_sort": "按步长 gap 分组插入，gap 一路减半——远处元素先就位。",
  "sorting/radix_sort": "按个位、十位逐趟稳定计数分布，每趟写回一个临时数组。",

  // ── 查找（2 + 1 变体） ──────────────────────────────────────────────
  "search/binary_search": "左右区间不断折半，每次比较只走一侧，命中下标直接返回。",
  "search/is_prime": "试除到平方根就收手，逐个判定 2 到 30 并数出素数个数。",
  "search/isPrime": "同一个试除函数，换成判定单个数：17 的结论在分支两侧落地。",

  // ── 图（7） ─────────────────────────────────────────────────────────
  "graph/bfs": "队列先进先出，顶点一层层被取出，访问顺序逐个打印。",
  "graph/dfs": "递归一路深入到底再回头，每到一个顶点就打印一次。",
  "graph/dijkstra": "每轮挑最近顶点定距并松弛邻边，终值是一张从起点出发的距离表。",
  "graph/floyd": "三重循环逐个中转点松弛，矩阵里的 INF 被真实路径一点点替换。",
  "graph/kruskal_mst": "边按权重挑出来，再看并查集是否已成环——每条选中的边当场打印。",
  "graph/prim_mst": "从当前树出发，每次接上代价最小的未选顶点。",
  "graph/topological_sort": "入度为 0 的顶点先入队，逐个出队并给后继减入度——顺序即结果。",

  // ── 树（8 + 3 变体） ────────────────────────────────────────────────
  "tree/bst_insert": "七个键逐个插入，按大小找落点，树形当场长出来。",
  "tree/bst_search": "沿左右子树逐层比对，命中或走空两种结局各走一条分支。",
  "tree/bst_delete": "删结点时拿右子树最小值顶上，旧结点 free 掉再把链路接回去。",
  "tree/bst_validate": "给每个子树带上上下界，越界就判为不合法。",
  "tree/avl_tree": "插入失衡时当场旋转，节点高度被重新算平——树形自己稳住了。",
  "tree/huffman_tree": "每次合并最小的两个权值，直到只剩一个根——根的权值是全部之和。",
  "tree/level_order": "按层把节点装进队列逐个吐出，输出是自上而下的层序。",
  "tree/threaded_binary_tree": "中序走一遍，把空指针改成前驱后继线索，标签位当场翻转。",
  "tree/bstInsert": "只做插入不做删除，中序输出看到的是插入后的键序列。",
  "tree/bstSearch": "建完树再查一个键，命中时直接打印找到的结点值。",
  "tree/threadedBinaryTree": "带头结点的中序线索化，走线索时不回头找子树也能按序打印。",

  // ── 结构（11 + 7 变体） ─────────────────────────────────────────────
  "structures/linked_list_append": "尾插三次后从表头顺次解引用，直接读出三个结点值。",
  "structures/linked_list_delete": "从中间摘掉一个结点，链表重新接上，输出指向它的后继。",
  "structures/static_linked_list": "结点住在固定数组里，cur 字段当下标用——不碰指针也能串成链。",
  "structures/circular_linked_list": "尾结点的 next 绕回表头，遍历一圈后又是同一个起点。",
  "structures/linked_stack": "压栈三个再弹一次，栈顶指针换到下一个结点。",
  "structures/linked_queue": "队头出队尾入队，两次出队取到的正是最早入队的两个。",
  "structures/circular_queue": "固定容量数组配首尾指针，队列走到数组末尾会绕回开头。",
  "structures/hash_table": "按下标散列存放三个键，再查其中一个——看它落在哪一格。",
  "structures/seq_list": "连续数组里插入再删除一格，后面元素整体前移。",
  "structures/union_find": "合并若干组后查两点是否同族，父指针一改一压缩就连起来了。",
  "structures/josephus": "绕着圈数满 m 个淘汰一个，幸存者编号当场算出来。",
  "structures/staticLinkedList": "同样用数组当链，但把下标存进 cur 字段，遍历靠手工跳转。",
  "structures/circularLinkedList": "头插式的循环链表版本，打印时绕一圈回到起点。",
  "structures/linkedStack": "压栈后整栈打印一次，弹出一个再打印一次——栈高肉眼可见。",
  "structures/linkedQueue": "同一件事换一套接口名：三个入队，再依次出队打印三个数。",
  "structures/circularQueue": "补上初始化与判空判满接口，循环队列的容量边界露出来。",
  "structures/unionFind": "并查集写成函数式接口，合并三组后直接打印 3 的根是谁。",

  // ── 字符串（3 + 2 变体） ────────────────────────────────────────────
  "string/string_match_bf": "从每个起点逐字符硬比，失配就退一位重来——命中位置直接报出。",
  "string/string_match_kmp": "先把模式串的 next 值表打出来，失配时跳到表里给的下一处。",
  "string/string_reverse": "首尾字符对调、指针向中间收拢，原地就把字符串翻了过来。",
  "string/stringMatchKMP": "先算 next 表，再靠它跳过重复比较，直接给出匹配位置。",
  "string/stringReverse": "不用库函数：手写长度统计，再两两交换字符完成反转。",

  // ── 数学与动态规划（3 + 5 变体） ─────────────────────────────────────
  "mathdp/gcd": "大数除小数取余，余数继续往下除——递归的终点就是答案。",
  "mathdp/hanoi": "每移动一次盘子都打印一行来源与去向，三层递归逐步展开。",
  "mathdp/dp": "dp 数组一格一格填，每格只从更小的金额转移，最后一格是答案。",
  "mathdp/dpFib": "手写斐波那契表：前两项定死，之后每格等于前两格之和。",
  "mathdp/dpKnapsack": "二维表按物品逐行填，每格在装与不装之间挑一个更大的值。",
  "mathdp/dpLCS": "两个串逐格比对：字符相同就接上一格，不同就取两格里的较大值。",
  "mathdp/dpLIS": "以每个数结尾的最长递增长度逐个算出，答案是这些值的最大者。",
  "mathdp/matrixChain": "dp 表记录每段连乘的最优代价，最后一格给出整条链的答案。",

  // ── 扩展练习（35） ──────────────────────────────────────────────────
  "xlab/activitySelection": "按结束时间挑不冲突的活动，每选中一个就打印它的序号。",
  "xlab/array": "五个元素逐个累加进一个变量，最后打印总和。",
  "xlab/bTree": "结点装多个键，插入触发分裂与提升——键序遍历后能读出全部。",
  "xlab/bellmanFord": "边表逐轮松弛，dist 被一点点改短，最后打印每个顶点的距离。",
  "xlab/bucketSort": "按区间把元素分进各个桶，再从桶里倒回原数组。",
  "xlab/criticalPath": "先算每个事件的最早与最晚时刻，等值的那条链就是关键路径。",
  "xlab/deque": "两端都能进出：先压尾再压头，接着从头、从尾、从头各弹一次。",
  "xlab/doublyLinkedList": "结点同时握住前驱和后继，尾插之后从头顺着打印一遍。",
  "xlab/externalSort": "缓冲区只留四个元素，选最小值送出、再补一个进来。",
  "xlab/factorial": "递归调用自己直到 n 退到 1，回程时把结果一层层乘回来。",
  "xlab/fib": "递归展开成一串对数相加的调用，逐层回算最后得到一个数。",
  "xlab/fibonacciSearch": "用斐波那契数切分数组，查找区间的收缩步长由表给出。",
  "xlab/infixEvaluation": "运算符栈与数值栈同步进退，优先级高的先算，末尾弹出结果。",
  "xlab/inorder": "先走左子树再取根最后右子树，输出是左小右大的键序。",
  "xlab/interpolationSearch": "按值在区间里的比例估算落点，而不是固定取中间。",
  "xlab/linear": "从头逐个比对，命中就返回下标，没命中走到末尾为止。",
  "xlab/linked": "手工把三个结点串起来，next 指针逐个指到下一个。",
  "xlab/linkedDelete": "删掉中间那个结点后，前驱的 next 直接跨过它接到后继。",
  "xlab/linkedInsert": "每次都插到最前面——后插进去的 3 反而排在 1 前面。",
  "xlab/linkedListTail": "从头到尾依次接在末尾，串好后整条链打印出来。",
  "xlab/linkedTraverse": "从头结点一路顺着 next 走到底，每个值依次打印。",
  "xlab/mergeSortedLists": "两个已排好序的链表逐个比大小，重接出一条合并后的链。",
  "xlab/parenthesesMatch": "左括号压栈、右括号出栈对配，栈里空了才算配平。",
  "xlab/pointer": "把两个变量的地址传进函数，函数里一交换，外面就变了。",
  "xlab/polynomialAdd": "同次项的系数相加，不同次项直接接在后面依次打印。",
  "xlab/postorder": "先走完左右子树再取根，输出顺序与前中序都不同。",
  "xlab/queueArray": "固定数组加队头队尾两个下标，出队顺序就是入队顺序。",
  "xlab/redBlackTree": "插入后若红红冲突就旋转改色，红黑两条性质在修补里被守住。",
  "xlab/sieveOfEratosthenes": "先把倍数标记成合数，剩下的就是三十以内的素数。",
  "xlab/spfa": "只有距离被改短的顶点才重新入队，队列里进出的次序看得见。",
  "xlab/stackArray": "用数组末端当栈顶，压三个再连弹三次，顺序完全倒过来。",
  "xlab/stringBasicOps": "赋值、比较、截取、拼接四个动作各走一遍，缓冲区里能读到结果。",
  "xlab/treeNode": "建一个带左右孩子的结点，root 指针握住整棵树的起点。",
  "xlab/treePreorder": "先取根再走左子树最后右子树，输出顺序是根左右。",
  "xlab/treeToForest": "一棵二叉树换成孩子兄弟链表，遍历照样按同一次序输出。",
};
