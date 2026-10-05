#include <stdio.h>
#include <stdlib.h>

struct TreeNode {
    int val;
    struct TreeNode* left;
    struct TreeNode* right;
};

int height(struct TreeNode* root) {
    if (root == NULL) return 0;
    int left = height(root->left);
    if (left == -1) return -1;
    int right = height(root->right);
    if (right == -1) return -1;
    if (left - right > 1 || right - left > 1) return -1;
    return (left > right ? left : right) + 1;
}

int isBalanced(struct TreeNode* root) {
    return height(root) != -1;
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
    root->left = newNode(9);
    root->right = newNode(20);
    root->right->left = newNode(15);
    root->right->right = newNode(7);
    printf("%d\n", isBalanced(root));
    freeTree(root);

    root = newNode(1);
    root->left = newNode(2);
    root->right = newNode(2);
    root->left->left = newNode(3);
    root->left->right = newNode(3);
    root->left->left->left = newNode(4);
    root->left->left->right = newNode(4);
    printf("%d\n", isBalanced(root));
    freeTree(root);

    printf("%d\n", isBalanced(NULL));

    return 0;
}
