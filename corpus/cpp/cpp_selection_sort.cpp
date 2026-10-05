#include <stdio.h>
class Sorter {
public:
    void sort(int* a, int n) {
        for (int i = 0; i < n - 1; i++) {
            int m = i;
            for (int j = i + 1; j < n; j++) if (a[j] < a[m]) m = j;
            int t = a[i]; a[i] = a[m]; a[m] = t;
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
