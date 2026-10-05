#include <stdio.h>
#include <stdlib.h>

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

int max_sum;

int maxGain(TreeNode* node) {
    if (!node) {
        return 0;
    }
    int left = maxGain(node->left);
    int right = maxGain(node->right);
    int price_newpath = node->val + left + right;
    if (price_newpath > max_sum) {
        max_sum = price_newpath;
    }
    int ret = node->val;
    if (left > 0) {
        ret += left;
    }
    if (right > 0) {
        ret += right;
    }
    return ret > 0 ? ret : 0;
}

int maxPathSum(TreeNode* root) {
    max_sum = -1000000000;
    maxGain(root);
    return max_sum;
}

int main() {
    TreeNode* root1 = newNode(1);
    root1->left = newNode(2);
    root1->right = newNode(3);
    printf("%d\n", maxPathSum(root1));

    TreeNode* root2 = newNode(-10);
    root2->left = newNode(9);
    root2->right = newNode(20);
    root2->right->left = newNode(15);
    root2->right->right = newNode(7);
    printf("%d\n", maxPathSum(root2));

    return 0;
}
