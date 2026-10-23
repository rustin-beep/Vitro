#include <stdio.h>
#include <string.h>
#include "hash.h"

static void print_pair(const char *key, int value, void *ctx)
{
    (void)ctx;
    printf("  %-12s = %d\n", key, value);
}

int main(void)
{
    HashTable table;
    char keybuf[8];
    int i;
    int rc;
    int value;
    int before_cap;

    for (i = 0; i < 20; i++) {
        sprintf(keybuf, "key%02d", i);
    }

    hash_init(&table, HASH_INIT_CAPACITY);
    printf("=== insert 20 keys ===\n");
    for (i = 0; i < 20; i++) {
        sprintf(keybuf, "key%02d", i);
        rc = hash_put(&table, keybuf, i * 10 + 5);
        printf("put %s rc=%2d count=%2d cap=%2d\n", keybuf, rc, table.count, table.capacity);
    }

    printf("=== bucket occupancy ===\n");
    for (i = 0; i < table.capacity; i++) {
        if (table.entries[i].used) {
            printf("  bucket %2d : %-8s = %d\n", i, table.entries[i].key, table.entries[i].value);
        } else {
            printf("  bucket %2d : empty\n", i);
        }
    }
    printf("collisions=%d resizes=%d\n", table.collision_count, table.resize_count);

    printf("=== get hit / miss ===\n");
    rc = hash_get(&table, "key05", &value);
    printf("get key05 rc=%2d value=%d\n", rc, value);
    rc = hash_get(&table, "key19", &value);
    printf("get key19 rc=%2d value=%d\n", rc, value);
    rc = hash_get(&table, "nope", &value);
    printf("get nope  rc=%2d\n", rc);

    printf("=== remove then get ===\n");
    rc = hash_remove(&table, "key07");
    printf("remove key07 rc=%2d count=%2d\n", rc, table.count);
    rc = hash_get(&table, "key07", &value);
    printf("get key07 rc=%2d\n", rc);

    printf("=== resize ===\n");
    before_cap = table.capacity;
    rc = hash_resize(&table, table.capacity * 2);
    printf("resize rc=%2d cap_before=%2d cap_after=%2d count=%2d\n", rc, before_cap, table.capacity, table.count);

    printf("=== foreach (insertion order) ===\n");
    rc = hash_foreach(&table, print_pair, NULL);
    printf("visited=%d\n", rc);

    hash_destroy(&table);
    printf("destroyed count=%d\n", table.count);
    return 0;
}
