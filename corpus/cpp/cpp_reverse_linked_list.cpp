#include <stdio.h>
struct ListNode {
    int val;
    ListNode* next;
};
ListNode* reverseList(ListNode* head) {
    ListNode* p = (ListNode*)0;
    while (head) {
        ListNode* n = head->next;
        head->next = p;
        p = head;
        head = n;
    }
    return p;
}
int main() {
    ListNode a, b, c;
    a.val = 1; a.next = &b;
    b.val = 2; b.next = &c;
    c.val = 3; c.next = (ListNode*)0;
    ListNode* h = reverseList(&a);
    while (h) { printf("%d\n", h->val); h = h->next; }
    return 0;
}
