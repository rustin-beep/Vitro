#include <stdio.h>
struct TreeNode {
    int val;
    TreeNode* left;
    TreeNode* right;
};
int isSameTree(TreeNode* p, TreeNode* q) {
    if (!p && !q) return 1;
    if (!p || !q) return 0;
    return p->val == q->val && isSameTree(p->left, q->left) && isSameTree(p->right, q->right);
}
int main() {
    TreeNode a, b, c, d;
    a.val = 1; a.left = &b; a.right = &c;
    b.val = 2; b.left = b.right = (TreeNode*)0;
    c.val = 3; c.left = c.right = (TreeNode*)0;
    d.val = 1; d.left = &b; d.right = &c;
    printf("%d\n", isSameTree(&a, &d));
    return 0;
}
