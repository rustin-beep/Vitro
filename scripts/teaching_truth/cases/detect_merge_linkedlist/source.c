#include <stdio.h>
#include <stdlib.h>

/* M33b A4 红例：链表归并辅助函数（自递归 + 调用名含 merge）命中
   merge_sort 结构分支（is_recursive && has_merge_pattern && !has_partition_pattern
   ——结构分支无 sort 语境门槛）。真值：零算法标注（链表归并非归并排序）。 */
struct ListNode {
    int val;
    struct ListNode *next;
};

struct ListNode *mergeTwoLists(struct ListNode *a, struct ListNode *b) {
    if (a == 0) return b;
    if (b == 0) return a;
    if (a->val <= b->val) {
        a->next = mergeTwoLists(a->next, b);
        return a;
    }
    return mergeTwoLists(a, b->next);
}

int main() {
    struct ListNode n1; struct ListNode n2; struct ListNode n3;
    n1.val = 1; n2.val = 2; n3.val = 4;
    n1.next = &n2; n2.next = 0; n3.next = 0;
    struct ListNode *m = mergeTwoLists(&n1, &n3);
    printf("%d\n", m->val);
    return 0;
}
