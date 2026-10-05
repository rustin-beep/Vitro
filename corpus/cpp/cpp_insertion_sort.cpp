#include <stdio.h>
class Sorter {
public:
    void sort(int* a, int n) {
        for (int i = 1; i < n; i++) {
            int k = a[i];
            int j = i - 1;
            while (j >= 0 && a[j] > k) { a[j + 1] = a[j]; j--; }
            a[j + 1] = k;
        }
    }
};
int main() {
    int a[] = {5, 2, 4, 1, 3};
    Sorter s;
    s.sort(a, 5);
    for (int i = 0; i < 5; i++) printf("%d\n", a[i]);
    return 0;
}
