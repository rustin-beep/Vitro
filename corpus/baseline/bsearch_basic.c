// @category: baseline
#include <stdio.h>
#include <stdlib.h>
int cmp(const void* a, const void* b) {
    int x = *(int*)a;
    int y = *(int*)b;
    return x - y;
}
int main() {
    int arr[] = {1, 3, 5, 7, 9};
    int key = 5;
    int* p = bsearch(&key, arr, 5, sizeof(int), cmp);
    printf("%d\n", p ? *p : -1);
    return 0;
}
