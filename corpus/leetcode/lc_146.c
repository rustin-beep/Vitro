#include <stdio.h>

#define CAPACITY 4

int keys[CAPACITY];
int values[CAPACITY];
int used[CAPACITY];

void lru_init() {
    for (int i = 0; i < CAPACITY; i++) {
        used[i] = 0;
    }
}

void touch(int idx) {
    int k = keys[idx];
    int v = values[idx];
    for (int i = idx; i > 0; i--) {
        keys[i] = keys[i - 1];
        values[i] = values[i - 1];
        used[i] = used[i - 1];
    }
    keys[0] = k;
    values[0] = v;
    used[0] = 1;
}

int get(int key) {
    for (int i = 0; i < CAPACITY; i++) {
        if (used[i] && keys[i] == key) {
            touch(i);
            return values[0];
        }
    }
    return -1;
}

void put(int key, int value) {
    for (int i = 0; i < CAPACITY; i++) {
        if (used[i] && keys[i] == key) {
            values[i] = value;
            touch(i);
            return;
        }
    }
    for (int i = CAPACITY - 1; i > 0; i--) {
        keys[i] = keys[i - 1];
        values[i] = values[i - 1];
        used[i] = used[i - 1];
    }
    keys[0] = key;
    values[0] = value;
    used[0] = 1;
}

int main() {
    lru_init();
    put(1, 1);
    put(2, 2);
    printf("%d\n", get(1));
    put(3, 3);
    printf("%d\n", get(2));
    put(4, 4);
    printf("%d\n", get(1));
    printf("%d\n", get(3));
    printf("%d\n", get(4));
    return 0;
}
