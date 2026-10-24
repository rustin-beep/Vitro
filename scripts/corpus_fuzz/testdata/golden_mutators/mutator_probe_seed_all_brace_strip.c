#include <stdio.h>

int main(void) {
    int a = 1;
    int arr[3] = {1, 2, 3};
    int five = {5};
    int zero[3] = {0};
    int flat[2][2] = {{4, 5}, {6, 7}};
    char c = 'x';
    int d = 8;
    int s = 0;
    for (int i = 0; i < 3; i++) {
        s = s + d;
    }
    int q = d / 2;
    long l = (int)s;
    printf("%d %d %d %d %d %c %d %ld\n", a, arr[0], zero[0], flat[0][0], s, c, q, l);
    return 0;
}
