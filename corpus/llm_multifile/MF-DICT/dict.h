#ifndef DICT_H
#define DICT_H

#include <stddef.h>

#define DICT_MAX_NODES 64
#define DICT_KEY_LEN 32

typedef struct {
    char key[DICT_KEY_LEN];
    int value;
    int left;
    int right;
    int used;
} DictNode;

typedef struct {
    DictNode nodes[DICT_MAX_NODES];
    int root;
    int count;
    long comparisons;
} Dict;

void dict_init(Dict *dict);

/* inserts or updates a key, returns 0 on success */
int dict_put(Dict *dict, const char *key, int value);

/* looks a key up, returns 0 on success and fills the value */
int dict_get(const Dict *dict, const char *key, int *value, int *comparisons);

/* removes a key, returns 0 on success */
int dict_remove(Dict *dict, const char *key);

/* in order traversal into a caller supplied array, returns the number of keys */
int dict_keys_in_order(const Dict *dict, char keys[][DICT_KEY_LEN], int max_keys);

/* keys of the range [lo, hi] in ascending order */
int dict_range(const Dict *dict, const char *lo, const char *hi,
               char keys[][DICT_KEY_LEN], int max_keys);

int dict_min_key(const Dict *dict, char *out, size_t cap);
int dict_max_key(const Dict *dict, char *out, size_t cap);
int dict_size(const Dict *dict);
long dict_comparisons(const Dict *dict);

extern int dict_ops;

#endif /* DICT_H */
