#include <stdio.h>
void swap(int v[], int i, int j) {
    int temp = v[i]; v[i] = v[j]; v[j] = temp;
}
int cmp_desc(int a, int b) { return b - a; }
void qsortt(int v[], int left, int right, int (*comp)(int, int)) {
    int i, last;
    if (left >= right) return;
    swap(v, left, (left + right) / 2);
    last = left;
    for (i = left + 1; i <= right; i++)
        if ((*comp)(v[i], v[left]) < 0)
            swap(v, ++last, i);
    swap(v, left, last);
    qsortt(v, left, last - 1, comp);
    qsortt(v, last + 1, right, comp);
}
int main() {
    int v[] = {5, 3, 8, 1, 2, 7, 4, 6};
    qsortt(v, 0, 7, cmp_desc);
    for (int i = 0; i < 8; i++)
        printf("%d ", v[i]);
    printf("\n");
    return 0;
}
