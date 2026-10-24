#ifndef HASH_H
#define HASH_H

#define HASH_INIT_CAPACITY 31
#define HASH_LOAD_NUM     7
#define HASH_LOAD_DEN    10

#define HASH_OK            0
#define HASH_ERR_NULL    (-1)
#define HASH_ERR_FULL    (-2)
#define HASH_ERR_NOMEM   (-3)
#define HASH_ERR_NOTFOUND (-4)

typedef struct {
    char *key;
    int value;
    int used;
} HashEntry;

typedef struct {
    HashEntry *entries;
    int capacity;
    int count;
    int resize_count;
    int collision_count;
    char **order;
    int order_len;
    int order_cap;
} HashTable;

typedef void (*HashForeachFn)(const char *key, int value, void *ctx);

int hash_init(HashTable *table, int capacity);
int hash_put(HashTable *table, const char *key, int value);
int hash_get(const HashTable *table, const char *key, int *out);
int hash_remove(HashTable *table, const char *key);
int hash_resize(HashTable *table, int new_capacity);
int hash_foreach(const HashTable *table, HashForeachFn fn, void *ctx);
void hash_destroy(HashTable *table);
unsigned long hash_str(const char *text);
int hash_is_prime(int n);

#endif /* HASH_H */
