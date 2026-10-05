#include <stdio.h>
class Sorter {
public:
    void sort(int* a, int n) {
        for (int i = 0; i < n - 1; i++)
            for (int j = 0; j < n - i - 1; j++)
                if (a[j] > a[j + 1]) { int t = a[j]; a[j] = a[j + 1]; a[j + 1] = t; }
    }
};
int main() {
    int a[] = {5, 2, 4, 1, 3};
    Sorter s;
    s.sort(a, 5);
    for (int i = 0; i < 5; i++) printf("%d\n", a[i]);
    return 0;
}
