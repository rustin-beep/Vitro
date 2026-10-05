// @category: baseline
#include <stdio.h>
#include <stdlib.h>
#define M 3

struct BTreeNode {
    int keys[M];
    struct BTreeNode* children[M + 1];
    int keyCount;
    int isLeaf;
};

struct BTreeNode* createNode(int isLeaf) {
    struct BTreeNode* node = (struct BTreeNode*)malloc(sizeof(struct BTreeNode));
    node->keyCount = 0;
    node->isLeaf = isLeaf;
    for (int i = 0; i <= M; i++) node->children[i] = NULL;
    return node;
}

void traverse(struct BTreeNode* root) {
    if (root) {
        int i;
        for (i = 0; i < root->keyCount; i++) {
            if (!root->isLeaf) traverse(root->children[i]);
            printf("%d ", root->keys[i]);
        }
        if (!root->isLeaf) traverse(root->children[i]);
    }
}

int search(struct BTreeNode* root, int key) {
    int i = 0;
    while (i < root->keyCount && key > root->keys[i]) i++;
    if (i < root->keyCount && key == root->keys[i]) return 1;
    if (root->isLeaf) return 0;
    return search(root->children[i], key);
}

void splitChild(struct BTreeNode* parent, int i, struct BTreeNode* child) {
    struct BTreeNode* newNode = createNode(child->isLeaf);
    newNode->keyCount = M / 2;
    for (int j = 0; j < M / 2; j++)
        newNode->keys[j] = child->keys[j + M / 2 + 1];
    if (!child->isLeaf) {
        for (int j = 0; j <= M / 2; j++)
            newNode->children[j] = child->children[j + M / 2 + 1];
    }
    child->keyCount = M / 2;
    for (int j = parent->keyCount; j >= i + 1; j--)
        parent->children[j + 1] = parent->children[j];
    parent->children[i + 1] = newNode;
    for (int j = parent->keyCount - 1; j >= i; j--)
        parent->keys[j + 1] = parent->keys[j];
    parent->keys[i] = child->keys[M / 2];
    parent->keyCount++;
}

void insertNonFull(struct BTreeNode* node, int key) {
    int i = node->keyCount - 1;
    if (node->isLeaf) {
        while (i >= 0 && key < node->keys[i]) {
            node->keys[i + 1] = node->keys[i];
            i--;
        }
        node->keys[i + 1] = key;
        node->keyCount++;
    } else {
        while (i >= 0 && key < node->keys[i]) i--;
        i++;
        if (node->children[i]->keyCount == M - 1) {
            splitChild(node, i, node->children[i]);
            if (key > node->keys[i]) i++;
        }
        insertNonFull(node->children[i], key);
    }
}

struct BTreeNode* insert(struct BTreeNode* root, int key) {
    if (!root) root = createNode(1);
    if (root->keyCount == M - 1) {
        struct BTreeNode* newRoot = createNode(0);
        newRoot->children[0] = root;
        splitChild(newRoot, 0, root);
        insertNonFull(newRoot, key);
        return newRoot;
    }
    insertNonFull(root, key);
    return root;
}

int main() {
    struct BTreeNode* root = NULL;
    root = insert(root, 10);
    root = insert(root, 20);
    root = insert(root, 5);
    root = insert(root, 6);
    root = insert(root, 12);
    root = insert(root, 30);
    root = insert(root, 7);
    root = insert(root, 17);
    printf("%d\n", search(root, 6));
    traverse(root);
    printf("\n");
    return 0;
}

