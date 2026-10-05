#include <stdio.h>

void readBinaryWatch(int turnedOn, int* returnSize) {
    *returnSize = 0;
    for (int h = 0; h < 12; h++) {
        for (int m = 0; m < 60; m++) {
            int bits = 0;
            int v = h;
            while (v) { bits += v & 1; v >>= 1; }
            v = m;
            while (v) { bits += v & 1; v >>= 1; }
            if (bits == turnedOn) {
                printf("%d:%02d\n", h, m);
                (*returnSize)++;
            }
        }
    }
}

int main(void) {
    int size;
    readBinaryWatch(1, &size);
    return 0;
}
