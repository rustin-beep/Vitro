#include <stdio.h>
struct TreeNode {
    int val;
    TreeNode* left;
    TreeNode* right;
};
TreeNode* invertTree(TreeNode* root) {
    if (!root) return (TreeNode*)0;
    TreeNode* t = root->left;
    root->left = invertTree(root->right);
    root->right = invertTree(t);
    return root;
}
void inorder(TreeNode* p) {
    if (p) { inorder(p->left); printf("%d\n", p->val); inorder(p->right); }
}
int main() {
    TreeNode a, b, c;
    a.val = 2; a.left = &b; a.right = &c;
    b.val = 1; b.left = b.right = (TreeNode*)0;
    c.val = 3; c.left = c.right = (TreeNode*)0;
    invertTree(&a);
    inorder(&a);
    return 0;
}
