#include <stdio.h>
#include <stdlib.h>

struct ListNode {
    int val;
    struct ListNode* next;
};

struct ListNode* detectCycle(struct ListNode* head) {
    struct ListNode* slow = head;
    struct ListNode* fast = head;
    while (fast != NULL && fast->next != NULL) {
        slow = slow->next;
        fast = fast->next->next;
        if (slow == fast) {
            struct ListNode* ptr = head;
            while (ptr != slow) {
                ptr = ptr->next;
                slow = slow->next;
            }
            return ptr;
        }
    }
    return NULL;
}

struct ListNode* make_node(int val) {
    struct ListNode* node = (struct ListNode*)malloc(sizeof(struct ListNode));
    node->val = val;
    node->next = NULL;
    return node;
}

int node_val_or_minus(struct ListNode* node) {
    if (node == NULL) {
        return -1;
    }
    return node->val;
}

void free_list(struct ListNode* head, int has_cycle) {
    if (has_cycle) {
        return;
    }
    while (head != NULL) {
        struct ListNode* next = head->next;
        free(head);
        head = next;
    }
}

int main() {
    struct ListNode* n1 = make_node(3);
    struct ListNode* n2 = make_node(2);
    struct ListNode* n3 = make_node(0);
    struct ListNode* n4 = make_node(-4);
    n1->next = n2;
    n2->next = n3;
    n3->next = n4;
    n4->next = n2;
    printf("%d\n", node_val_or_minus(detectCycle(n1)));

    struct ListNode* m1 = make_node(1);
    struct ListNode* m2 = make_node(2);
    m1->next = m2;
    m2->next = m1;
    printf("%d\n", node_val_or_minus(detectCycle(m1)));

    struct ListNode* p1 = make_node(1);
    printf("%d\n", node_val_or_minus(detectCycle(p1)));

    return 0;
}
