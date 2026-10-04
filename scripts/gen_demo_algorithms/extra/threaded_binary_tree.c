#include <stdio.h>
#include <stdlib.h>

#define LINK 0
#define THREAD 1

struct ThreadedNode {
    int data;
    struct ThreadedNode* left;
    struct ThreadedNode* right;
    int ltag;
    int rtag;
};

struct ThreadedNode* createThreadedNode(int data) {
    struct ThreadedNode* n = (struct ThreadedNode*)malloc(sizeof(struct ThreadedNode));
    n->data = data;
    n->left = NULL;
    n->right = NULL;
    n->ltag = LINK;
    n->rtag = LINK;
    return n;
}

void inorderThreadedTree(struct ThreadedNode* p, struct ThreadedNode** prev) {
    if (p == NULL) return;
    inorderThreadedTree(p->left, prev);
    if (p->left == NULL) {
        p->ltag = THREAD;
        p->left = *prev;
    }
    if (*prev != NULL && (*prev)->right == NULL) {
        (*prev)->rtag = THREAD;
        (*prev)->right = p;
    }
    *prev = p;
    inorderThreadedTree(p->right, prev);
}

int main() {
    struct ThreadedNode* a = createThreadedNode(1);
    struct ThreadedNode* b = createThreadedNode(2);
    struct ThreadedNode* c = createThreadedNode(3);
    a->left = b;
    a->right = c;
    struct ThreadedNode* prev = NULL;
    inorderThreadedTree(a, &prev);
    printf("线索化完成 ltag(b)=%d\n", b->ltag);
    return 0;
}
