// @category: baseline
#include <stdio.h>

void selectActivities(int start[], int finish[], int n) {
    int i = 0;
    printf("%d ", i);
    for (int j = 1; j < n; j++) {
        if (start[j] >= finish[i]) {
            printf("%d ", j);
            i = j;
        }
    }
    printf("\n");
}

int main() {
    int start[] = {1, 3, 0, 5, 8, 5};
    int finish[] = {2, 4, 6, 7, 9, 9};
    int n = 6;
    selectActivities(start, finish, n);
    return 0;
}

