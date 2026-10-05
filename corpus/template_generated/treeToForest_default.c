// @category: baseline
#include <stdio.h>
#include <stdlib.h>

struct CSNode {
    int data;
    struct CSNode* firstChild;
    struct CSNode* nextSibling;
};

struct CSNode* createNode(int data) {
    struct CSNode* node = (struct CSNode*)malloc(sizeof(struct CSNode));
    node->data = data;
    node->firstChild = NULL;
    node->nextSibling = NULL;
    return node;
}

void traverse(struct CSNode* root) {
    if (root == NULL) return;
    printf("%d ", root->data);
    traverse(root->firstChild);
    traverse(root->nextSibling);
}

int main() {
    struct CSNode* root = createNode(1);
    root->firstChild = createNode(2);
    root->firstChild->nextSibling = createNode(3);
    root->firstChild->nextSibling->nextSibling = createNode(4);
    root->firstChild->firstChild = createNode(5);
    traverse(root);
    printf("\n");
    return 0;
}

