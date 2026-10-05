#include <stdio.h>
void swap(int v[], int i, int j) {
    int temp;
    temp = v[i];
    v[i] = v[j];
    v[j] = temp;
}
void qsort(int v[], int left, int right) {
    int i, last;
    if (left >= right)
        return;
    swap(v, left, (left + right) / 2);
    last = left;
    for (i = left + 1; i <= right; i++)
        if (v[i] < v[left])
            swap(v, ++last, i);
    swap(v, left, last);
    qsort(v, left, last - 1);
    qsort(v, last + 1, right);
}
int main() {
    int v[] = {5, 3, 8, 1, 2, 7, 4, 6};
    qsort(v, 0, 7);
    for (int i = 0; i < 8; i++)
        printf("%d ", v[i]);
    printf("\n");
    return 0;
}
