#include <stdio.h>
struct ListNode {
    int val;
    ListNode* next;
};
ListNode* mergeTwoLists(ListNode* l1, ListNode* l2) {
    ListNode dummy;
    dummy.next = (ListNode*)0;
    ListNode* t = &dummy;
    while (l1 && l2) {
        if (l1->val < l2->val) { t->next = l1; l1 = l1->next; }
        else { t->next = l2; l2 = l2->next; }
        t = t->next;
    }
    if (l1) t->next = l1;
    else t->next = l2;
    return dummy.next;
}
int main() {
    ListNode a1, a2, b1, b2, b3;
    a1.val = 1; a1.next = &a2; a2.val = 2; a2.next = (ListNode*)0;
    b1.val = 1; b1.next = &b2; b2.val = 3; b2.next = &b3; b3.val = 4; b3.next = (ListNode*)0;
    ListNode* h = mergeTwoLists(&a1, &b1);
    while (h) { printf("%d\n", h->val); h = h->next; }
    return 0;
}
