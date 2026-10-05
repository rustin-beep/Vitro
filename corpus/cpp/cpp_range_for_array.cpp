#include <stdio.h>
int main() {
    int arr[] = {1, 2, 3};
    int sum = 0;
    for (int x : arr) sum = sum + x;
    printf("%d\n", sum);
    return 0;
}
