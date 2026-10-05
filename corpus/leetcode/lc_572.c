#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct TreeNode {
    int val;
    struct TreeNode* left;
    struct TreeNode* right;
};

int isSame(struct TreeNode* s, struct TreeNode* t) {
    if (s == NULL && t == NULL) return 1;
    if (s == NULL || t == NULL) return 0;
    return s->val == t->val && isSame(s->left, t->left) && isSame(s->right, t->right);
}

int isSubtree(struct TreeNode* root, struct TreeNode* subRoot) {
    if (root == NULL) return 0;
    if (isSame(root, subRoot)) return 1;
    return isSubtree(root->left, subRoot) || isSubtree(root->right, subRoot);
}

struct TreeNode* newNode(int val) {
    struct TreeNode* n = (struct TreeNode*)malloc(sizeof(struct TreeNode));
    n->val = val;
    n->left = NULL;
    n->right = NULL;
    return n;
}

void freeTree(struct TreeNode* root) {
    if (root == NULL) return;
    freeTree(root->left);
    freeTree(root->right);
    free(root);
}

int main() {
    struct TreeNode* root = newNode(3);
    root->left = newNode(4);
    root->right = newNode(5);
    root->left->left = newNode(1);
    root->left->right = newNode(2);

    struct TreeNode* sub = newNode(4);
    sub->left = newNode(1);
    sub->right = newNode(2);

    printf("%d\n", isSubtree(root, sub));

    root->left->right->left = newNode(0);
    printf("%d\n", isSubtree(root, sub));

    freeTree(root);
    freeTree(sub);

    return 0;
}
