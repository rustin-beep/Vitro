#include <stdio.h>
#include <stdlib.h>

typedef struct ListNode {
    int val;
    struct ListNode* next;
} ListNode;

ListNode* newNode(int val) {
    ListNode* node = (ListNode*)malloc(sizeof(ListNode));
    node->val = val;
    node->next = NULL;
    return node;
}

ListNode* reverseKGroup(ListNode* head, int k) {
    ListNode dummy;
    dummy.next = head;
    ListNode* group_prev = &dummy;
    while (1) {
        ListNode* kth = group_prev;
        for (int i = 0; i < k && kth; i++) {
            kth = kth->next;
        }
        if (!kth) {
            break;
        }
        ListNode* group_next = kth->next;
        ListNode* prev = kth->next;
        ListNode* curr = group_prev->next;
        while (curr != group_next) {
            ListNode* next = curr->next;
            curr->next = prev;
            prev = curr;
            curr = next;
        }
        ListNode* tmp = group_prev->next;
        group_prev->next = kth;
        group_prev = tmp;
    }
    return dummy.next;
}

void printList(ListNode* head) {
    while (head) {
        printf("%d", head->val);
        if (head->next) {
            printf(" ");
        }
        head = head->next;
    }
    printf("\n");
}

int main() {
    ListNode* head = newNode(1);
    head->next = newNode(2);
    head->next->next = newNode(3);
    head->next->next->next = newNode(4);
    head->next->next->next->next = newNode(5);
    printList(reverseKGroup(head, 2));

    ListNode* head2 = newNode(1);
    head2->next = newNode(2);
    head2->next->next = newNode(3);
    head2->next->next->next = newNode(4);
    head2->next->next->next->next = newNode(5);
    printList(reverseKGroup(head2, 3));

    return 0;
}
