#include <stdio.h>
template<class T>
void sort(T* a, int n) {
    for (int i = 0; i < n - 1; i++)
        for (int j = 0; j < n - i - 1; j++)
            if (a[j] > a[j + 1]) { T t = a[j]; a[j] = a[j + 1]; a[j + 1] = t; }
}
int main() {
    int a[] = {3, 1, 4, 1, 5};
    sort(a, 5);
    for (int i = 0; i < 5; i++) printf("%d\n", a[i]);
    return 0;
}
