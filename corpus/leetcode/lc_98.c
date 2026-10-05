#include <stdio.h>
#include <stdlib.h>
#include <limits.h>

typedef struct TreeNode {
    int val;
    struct TreeNode* left;
    struct TreeNode* right;
} TreeNode;

TreeNode* newNode(int val) {
    TreeNode* node = (TreeNode*)malloc(sizeof(TreeNode));
    node->val = val;
    node->left = NULL;
    node->right = NULL;
    return node;
}

int isValidBSTHelper(TreeNode* node, long long min_val, long long max_val) {
    if (node == NULL) {
        return 1;
    }
    if (node->val <= min_val || node->val >= max_val) {
        return 0;
    }
    return isValidBSTHelper(node->left, min_val, node->val) &&
           isValidBSTHelper(node->right, node->val, max_val);
}

int isValidBST(TreeNode* root) {
    return isValidBSTHelper(root, (long long)INT_MIN - 1, (long long)INT_MAX + 1);
}

int main() {
    TreeNode* root1 = newNode(2);
    root1->left = newNode(1);
    root1->right = newNode(3);
    printf("%d\n", isValidBST(root1));

    TreeNode* root2 = newNode(5);
    root2->left = newNode(1);
    root2->right = newNode(4);
    root2->right->left = newNode(3);
    root2->right->right = newNode(6);
    printf("%d\n", isValidBST(root2));

    TreeNode* root3 = newNode(2147483647);
    printf("%d\n", isValidBST(root3));

    return 0;
}
