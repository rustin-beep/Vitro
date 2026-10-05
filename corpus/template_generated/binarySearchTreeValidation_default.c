// @category: baseline
#include <stdio.h>
#include <stdlib.h>
#include <limits.h>

struct TreeNode {
    int val;
    struct TreeNode* left;
    struct TreeNode* right;
};

struct TreeNode* createNode(int val) {
    struct TreeNode* node = (struct TreeNode*)malloc(sizeof(struct TreeNode));
    node->val = val;
    node->left = NULL;
    node->right = NULL;
    return node;
}

int isValidBST(struct TreeNode* root, long long min, long long max) {
    if (root == NULL) return 1;
    if (root->val <= min || root->val >= max) return 0;
    return isValidBST(root->left, min, root->val) &&
           isValidBST(root->right, root->val, max);
}

int main() {
    struct TreeNode* root = createNode(5);
    root->left = createNode(3);
    root->right = createNode(7);
    root->left->left = createNode(1);
    root->left->right = createNode(4);
    if (isValidBST(root, (long long)INT_MIN - 1, (long long)INT_MAX + 1))
        printf("valid\n");
    else
        printf("invalid\n");
    return 0;
}

