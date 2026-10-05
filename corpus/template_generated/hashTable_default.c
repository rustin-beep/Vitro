// @category: baseline
#include <stdio.h>
#define TABLE_SIZE 10

struct HashEntry {
    int key;
    int occupied;
};

int hash(int key) {
    return key % TABLE_SIZE;
}

void insert(struct HashEntry table[], int key) {
    int idx = hash(key);
    while (table[idx].occupied) {
        idx = (idx + 1) % TABLE_SIZE;
    }
    table[idx].key = key;
    table[idx].occupied = 1;
}

int search(struct HashEntry table[], int key) {
    int idx = hash(key);
    while (table[idx].occupied) {
        if (table[idx].key == key) return idx;
        idx = (idx + 1) % TABLE_SIZE;
    }
    return -1;
}

int main() {
    struct HashEntry table[TABLE_SIZE];
    for (int i = 0; i < TABLE_SIZE; i++) {
        table[i].occupied = 0;
    }
    insert(table, 5);
    insert(table, 15);
    insert(table, 25);
    int idx = search(table, 15);
    printf("%d\n", idx);
    return 0;
}

