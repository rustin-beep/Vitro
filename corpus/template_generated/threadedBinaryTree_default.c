// @category: baseline
#include <stdio.h>
#include <stdlib.h>

typedef enum { Link, Thread } PointerTag;

struct BiThrNode {
    int data;
    struct BiThrNode* lchild;
    struct BiThrNode* rchild;
    PointerTag LTag;
    PointerTag RTag;
};

struct BiThrNode* createNode(int data) {
    struct BiThrNode* node = (struct BiThrNode*)malloc(sizeof(struct BiThrNode));
    node->data = data;
    node->lchild = NULL;
    node->rchild = NULL;
    node->LTag = Link;
    node->RTag = Link;
    return node;
}

struct BiThrNode* pre = NULL;

void InThreading(struct BiThrNode* p) {
    if (p) {
        InThreading(p->lchild);
        if (p->lchild == NULL) {
            p->LTag = Thread;
            p->lchild = pre;
        }
        if (pre && pre->rchild == NULL) {
            pre->RTag = Thread;
            pre->rchild = p;
        }
        pre = p;
        InThreading(p->rchild);
    }
}

void InOrderTraverse_Thr(struct BiThrNode* head) {
    struct BiThrNode* p = head->lchild;
    while (p != head) {
        while (p->LTag == Link) p = p->lchild;
        printf("%d ", p->data);
        while (p->RTag == Thread && p->rchild != head) {
            p = p->rchild;
            printf("%d ", p->data);
        }
        p = p->rchild;
    }
}

int main() {
    struct BiThrNode* head = createNode(0);
    head->LTag = Link;
    head->RTag = Thread;
    head->rchild = head;

    struct BiThrNode* root = createNode(1);
    root->lchild = createNode(2);
    root->rchild = createNode(3);
    root->lchild->lchild = createNode(4);
    root->lchild->rchild = createNode(5);

    head->lchild = root;
    InThreading(root);

    // 收尾：把中序第一个节点的左线索和最后一个节点的右线索都连回头节点。
    struct BiThrNode* first = root;
    while (first->LTag == Link) first = first->lchild;
    first->lchild = head;
    first->LTag = Thread;

    pre->rchild = head;
    pre->RTag = Thread;

    InOrderTraverse_Thr(head);
    printf("\n");
    return 0;
}

