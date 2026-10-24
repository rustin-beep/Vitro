#include "hash.h"
#include <stdlib.h>
#include <string.h>

int hash_is_prime(int n)
{
    int d;

    if (n < 2) {
        return 0;
    }
    if (n % 2 == 0) {
        return (n == 2) ? 1 : 0;
    }
    for (d = 3; d * d <= n; d += 2) {
        if (n % d == 0) {
            return 0;
        }
    }
    return 1;
}

static int hash_next_prime(int n)
{
    int candidate = (n < 2) ? 2 : n;
    while (!hash_is_prime(candidate)) {
        candidate++;
    }
    return candidate;
}

unsigned long hash_str(const char *text)
{
    unsigned long h = 5381UL;

    if (text == NULL) {
        return 0UL;
    }
    for (const char *p = text; *p != '\0'; p++) {
        h = h * 33UL + (unsigned long)(unsigned char)*p;
    }
    return h;
}

int hash_init(HashTable *table, int capacity)
{
    if (table == NULL) {
        return HASH_ERR_NULL;
    }
    table->capacity = hash_next_prime(capacity);
    table->count = 0;
    table->resize_count = 0;
    table->collision_count = 0;
    table->order_len = 0;
    table->order_cap = table->capacity * 2;
    table->entries = (HashEntry *)calloc((size_t)table->capacity, sizeof(HashEntry));
    table->order = (char **)calloc((size_t)table->order_cap, sizeof(char *));
    if (table->entries == NULL || table->order == NULL) {
        free(table->entries);
        free(table->order);
        table->entries = NULL;
        table->order = NULL;
        return HASH_ERR_NOMEM;
    }
    return HASH_OK;
}

static int hash_find_slot(const HashTable *table, const char *key, int for_insert)
{
    unsigned long h = hash_str(key);
    int idx = (int)(h % (unsigned long)table->capacity);
    int probes = 0;

    while (probes < table->capacity) {
        HashEntry *entry = &table->entries[idx];
        if (!entry->used) {
            return for_insert ? idx : -1;
        }
        if (strcmp(entry->key, key) == 0) {
            return idx;
        }
        idx = (idx + 1) % table->capacity;
        probes++;
    }
    return -1;
}

static int hash_order_append(HashTable *table, const char *key)
{
    if (table->order_len >= table->order_cap) {
        int new_cap = table->order_cap * 2;
        char **grown = (char **)realloc(table->order, (size_t)new_cap * sizeof(char *));
        if (grown == NULL) {
            return HASH_ERR_NOMEM;
        }
        table->order = grown;
        table->order_cap = new_cap;
    }
    table->order[table->order_len] = (char *)malloc(strlen(key) + 1);
    if (table->order[table->order_len] == NULL) {
        return HASH_ERR_NOMEM;
    }
    memcpy(table->order[table->order_len], key, strlen(key) + 1);
    table->order_len++;
    return HASH_OK;
}

static int hash_order_remove(HashTable *table, const char *key)
{
    int i;

    for (i = 0; i < table->order_len; i++) {
        if (strcmp(table->order[i], key) == 0) {
            free(table->order[i]);
            for (int j = i; j < table->order_len - 1; j++) {
                table->order[j] = table->order[j + 1];
            }
            table->order_len--;
            return HASH_OK;
        }
    }
    return HASH_ERR_NOTFOUND;
}

static int hash_insert_raw(HashTable *table, const char *key, int value)
{
    unsigned long h = hash_str(key);
    int idx = (int)(h % (unsigned long)table->capacity);
    int probes = 0;

    while (probes < table->capacity) {
        HashEntry *entry = &table->entries[idx];
        if (!entry->used) {
            entry->key = (char *)malloc(strlen(key) + 1);
            if (entry->key == NULL) {
                return HASH_ERR_NOMEM;
            }
            memcpy(entry->key, key, strlen(key) + 1);
            entry->value = value;
            entry->used = 1;
            table->count++;
            return HASH_OK;
        }
        if (strcmp(entry->key, key) == 0) {
            entry->value = value;
            return HASH_OK;
        }
        idx = (idx + 1) % table->capacity;
        probes++;
    }
    return HASH_ERR_FULL;
}

int hash_put(HashTable *table, const char *key, int value)
{
    int idx;
    int probes;

    if (table == NULL || key == NULL || table->entries == NULL) {
        return HASH_ERR_NULL;
    }
    idx = hash_find_slot(table, key, 1);
    if (idx < 0) {
        return HASH_ERR_FULL;
    }
    if (table->entries[idx].used) {
        table->entries[idx].value = value;
        return HASH_OK;
    }
    probes = (int)(hash_str(key) % (unsigned long)table->capacity);
    if (probes != idx) {
        table->collision_count++;
    }
    table->entries[idx].key = (char *)malloc(strlen(key) + 1);
    if (table->entries[idx].key == NULL) {
        return HASH_ERR_NOMEM;
    }
    memcpy(table->entries[idx].key, key, strlen(key) + 1);
    table->entries[idx].value = value;
    table->entries[idx].used = 1;
    table->count++;
    if (hash_order_append(table, key) != HASH_OK) {
        return HASH_ERR_NOMEM;
    }
    if (table->count * HASH_LOAD_DEN > table->capacity * HASH_LOAD_NUM) {
        return hash_resize(table, table->capacity * 2);
    }
    return HASH_OK;
}

int hash_get(const HashTable *table, const char *key, int *out)
{
    int idx;

    if (table == NULL || key == NULL || out == NULL) {
        return HASH_ERR_NULL;
    }
    idx = hash_find_slot(table, key, 0);
    if (idx < 0) {
        return HASH_ERR_NOTFOUND;
    }
    *out = table->entries[idx].value;
    return HASH_OK;
}

int hash_remove(HashTable *table, const char *key)
{
    int idx;

    if (table == NULL || key == NULL) {
        return HASH_ERR_NULL;
    }
    idx = hash_find_slot(table, key, 0);
    if (idx < 0) {
        return HASH_ERR_NOTFOUND;
    }
    free(table->entries[idx].key);
    table->entries[idx].key = NULL;
    table->entries[idx].value = 0;
    table->entries[idx].used = 0;
    table->count--;
    hash_order_remove(table, key);
    return HASH_OK;
}

int hash_resize(HashTable *table, int new_capacity)
{
    HashEntry *old_entries;
    int old_cap;
    int old_count;
    int i;

    if (table == NULL || table->entries == NULL) {
        return HASH_ERR_NULL;
    }
    old_entries = table->entries;
    old_cap = table->capacity;
    old_count = table->count;
    table->entries = (HashEntry *)calloc((size_t)hash_next_prime(new_capacity), sizeof(HashEntry));
    if (table->entries == NULL) {
        table->entries = old_entries;
        return HASH_ERR_NOMEM;
    }
    table->capacity = hash_next_prime(new_capacity);
    table->count = 0;
    table->resize_count++;
    for (i = 0; i < old_cap; i++) {
        if (old_entries[i].used) {
            hash_insert_raw(table, old_entries[i].key, old_entries[i].value);
            free(old_entries[i].key);
        }
    }
    (void)old_count;
    return HASH_OK;
}

int hash_foreach(const HashTable *table, HashForeachFn fn, void *ctx)
{
    int visited = 0;
    int i;

    if (table == NULL || fn == NULL) {
        return HASH_ERR_NULL;
    }
    for (i = 0; i < table->order_len; i++) {
        int value = 0;
        if (hash_get(table, table->order[i], &value) == HASH_OK) {
            fn(table->order[i], value, ctx);
            visited++;
        }
    }
    return visited;
}

void hash_destroy(HashTable *table)
{
    int i;

    if (table == NULL) {
        return;
    }
    if (table->entries != NULL) {
        for (i = 0; i < table->capacity; i++) {
            if (table->entries[i].used) {
                free(table->entries[i].key);
            }
        }
        free(table->entries);
        table->entries = NULL;
    }
    if (table->order != NULL) {
        for (i = 0; i < table->order_len; i++) {
            free(table->order[i]);
        }
        free(table->order);
        table->order = NULL;
    }
    table->count = 0;
    table->order_len = 0;
}
