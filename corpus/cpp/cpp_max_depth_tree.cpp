#include <stdio.h>
struct TreeNode {
    int val;
    TreeNode* left;
    TreeNode* right;
};
int maxDepth(TreeNode* root) {
    if (!root) return 0;
    int l = maxDepth(root->left);
    int r = maxDepth(root->right);
    return 1 + (l > r ? l : r);
}
int main() {
    TreeNode a, b, c;
    a.val = 3; a.left = &b; a.right = &c;
    b.val = 9; b.left = b.right = (TreeNode*)0;
    c.val = 20; c.left = c.right = (TreeNode*)0;
    printf("%d\n", maxDepth(&a));
    return 0;
}
