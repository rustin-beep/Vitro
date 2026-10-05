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

ListNode* mergeTwoLists(ListNode* l1, ListNode* l2) {
    ListNode dummy;
    ListNode* tail = &dummy;
    dummy.next = NULL;
    while (l1 && l2) {
        if (l1->val < l2->val) {
            tail->next = l1;
            l1 = l1->next;
        } else {
            tail->next = l2;
            l2 = l2->next;
        }
        tail = tail->next;
    }
    tail->next = l1 ? l1 : l2;
    return dummy.next;
}

ListNode* mergeKLists(ListNode** lists, int listsSize) {
    if (listsSize == 0) {
        return NULL;
    }
    int interval = 1;
    while (interval < listsSize) {
        for (int i = 0; i + interval < listsSize; i += interval * 2) {
            lists[i] = mergeTwoLists(lists[i], lists[i + interval]);
        }
        interval *= 2;
    }
    return lists[0];
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
    ListNode* l1 = newNode(1);
    l1->next = newNode(4);
    l1->next->next = newNode(5);

    ListNode* l2 = newNode(1);
    l2->next = newNode(3);
    l2->next->next = newNode(4);

    ListNode* l3 = newNode(2);
    l3->next = newNode(6);

    ListNode* lists[3] = {l1, l2, l3};
    ListNode* result = mergeKLists(lists, 3);
    printList(result);

    return 0;
}
