#include "dict.h"

int dict_ops = 0;
#include <string.h>
#include <stdio.h>

static void dict_copy_key(char *dst, const char *src)
{
    size_t n = strlen(src);

    if (n > (size_t)DICT_KEY_LEN - 1) {
        n = (size_t)DICT_KEY_LEN - 1;
    }
    memcpy(dst, src, n);
    dst[n] = '\0';
}

static void dict_copy_bounded(char *dst, size_t cap, const char *src)
{
    size_t n = strlen(src);

    if (n > cap - 1) {
        n = cap - 1;
    }
    memcpy(dst, src, n);
    dst[n] = '\0';
}

void dict_init(Dict *dict)
{
    int i;

    if (dict == NULL) {
        return;
    }
    for (i = 0; i < DICT_MAX_NODES; i++) {
        dict->nodes[i].key[0] = '\0';
        dict->nodes[i].value = 0;
        dict->nodes[i].left = -1;
        dict->nodes[i].right = -1;
        dict->nodes[i].used = 0;
    }
    dict->root = -1;
    dict->count = 0;
    dict->comparisons = 0;
}

static int dict_compare_keys(const char *a, const char *b)
{
    int result;

    if (a == NULL || b == NULL) {
        return 0;
    }
    result = strcmp(a, b);
    if (result < 0) {
        return -1;
    }
    if (result > 0) {
        return 1;
    }
    return 0;
}

static int dict_new_node(Dict *dict, const char *key, int value)
{
    int i;

    for (i = 0; i < DICT_MAX_NODES; i++) {
        if (dict->nodes[i].used) {
            continue;
        }
        dict_copy_key(dict->nodes[i].key, key);
        dict->nodes[i].value = value;
        dict->nodes[i].left = -1;
        dict->nodes[i].right = -1;
        dict->nodes[i].used = 1;
        return i;
    }
    return -1;
}

static int dict_search(const Dict *dict, const char *key, int *found)
{
    int current = dict->root;
    int steps = 0;

    *found = -1;
    while (current >= 0) {
        steps++;
        if (dict_compare_keys(dict->nodes[current].key, key) == 0) {
            *found = current;
            break;
        }
        if (dict_compare_keys(key, dict->nodes[current].key) < 0) {
            current = dict->nodes[current].left;
        } else {
            current = dict->nodes[current].right;
        }
    }
    return steps;
}

int dict_put(Dict *dict, const char *key, int value)
{
    int current;
    int parent = -1;
    int steps = 0;

    if (dict == NULL || key == NULL) {
        return -1;
    }
    current = dict->root;
    while (current >= 0) {
        int order;
        steps++;
        parent = current;
        order = dict_compare_keys(key, dict->nodes[current].key);
        if (order == 0) {
            dict->nodes[current].value = value;
            dict->comparisons += steps;
            return 0;
        }
        if (order < 0) {
            current = dict->nodes[current].left;
        } else {
            current = dict->nodes[current].right;
        }
    }
    current = dict_new_node(dict, key, value);
    if (current < 0) {
        return -2;
    }
    if (parent < 0) {
        dict->root = current;
    } else if (dict_compare_keys(key, dict->nodes[parent].key) < 0) {
        dict->nodes[parent].left = current;
    } else {
        dict->nodes[parent].right = current;
    }
    dict->count++;
    dict_ops++;
    dict->comparisons += steps;
    return 0;
}

int dict_get(const Dict *dict, const char *key, int *value, int *comparisons)
{
    int found;
    int steps;

    if (dict == NULL || key == NULL || value == NULL) {
        return -1;
    }
    steps = dict_search(dict, key, &found);
    if (comparisons != NULL) {
        *comparisons = steps;
    }
    if (found < 0) {
        return -2;
    }
    *value = dict->nodes[found].value;
    return 0;
}

static int dict_min_node(const Dict *dict, int index)
{
    while (index >= 0 && dict->nodes[index].left >= 0) {
        index = dict->nodes[index].left;
    }
    return index;
}

static int dict_max_node(const Dict *dict, int index)
{
    while (index >= 0 && dict->nodes[index].right >= 0) {
        index = dict->nodes[index].right;
    }
    return index;
}

static int dict_collect(const Dict *dict, int index, char keys[][DICT_KEY_LEN], int max_keys, int *count)
{
    if (index < 0) {
        return 0;
    }
    dict_collect(dict, dict->nodes[index].left, keys, max_keys, count);
    if (*count < max_keys) {
        dict_copy_key(keys[*count], dict->nodes[index].key);
        (*count)++;
    }
    dict_collect(dict, dict->nodes[index].right, keys, max_keys, count);
    return *count;
}

int dict_keys_in_order(const Dict *dict, char keys[][DICT_KEY_LEN], int max_keys)
{
    int count = 0;

    if (dict == NULL || keys == NULL || max_keys <= 0) {
        return 0;
    }
    dict_collect(dict, dict->root, keys, max_keys, &count);
    return count;
}

int dict_range(const Dict *dict, const char *lo, const char *hi,
               char keys[][DICT_KEY_LEN], int max_keys)
{
    char all[DICT_MAX_NODES][DICT_KEY_LEN];
    int count;
    int i;
    int written = 0;

    if (dict == NULL || keys == NULL || lo == NULL || hi == NULL || max_keys <= 0) {
        return 0;
    }
    count = dict_keys_in_order(dict, all, DICT_MAX_NODES);
    for (i = 0; i < count && written < max_keys; i++) {
        if (dict_compare_keys(all[i], lo) >= 0 && dict_compare_keys(all[i], hi) <= 0) {
            dict_copy_key(keys[written], all[i]);
            written++;
        }
    }
    return written;
}

int dict_remove(Dict *dict, const char *key)
{
    int found;
    int parent = -1;
    int current;
    int steps;

    if (dict == NULL || key == NULL) {
        return -1;
    }
    steps = dict_search(dict, key, &found);
    if (found < 0) {
        return -2;
    }
    current = found;
    parent = -1;
    {
        int walker = dict->root;
        while (walker >= 0 && walker != found) {
            parent = walker;
            if (dict_compare_keys(key, dict->nodes[walker].key) < 0) {
                walker = dict->nodes[walker].left;
            } else {
                walker = dict->nodes[walker].right;
            }
        }
    }
    dict->comparisons += steps;
    if (dict->nodes[current].left >= 0 && dict->nodes[current].right >= 0) {
        int successor = dict_min_node(dict, dict->nodes[current].right);
        int succ_parent = current;
        while (dict->nodes[successor].left >= 0) {
            succ_parent = successor;
            successor = dict->nodes[successor].left;
        }
        dict_copy_key(dict->nodes[current].key, dict->nodes[successor].key);
        dict->nodes[current].value = dict->nodes[successor].value;
        current = successor;
        parent = succ_parent;
    }
    {
        int child = dict->nodes[current].left >= 0 ? dict->nodes[current].left : dict->nodes[current].right;
        if (parent < 0) {
            dict->root = child;
        } else if (dict->nodes[parent].left == current) {
            dict->nodes[parent].left = child;
        } else {
            dict->nodes[parent].right = child;
        }
    }
    dict->nodes[current].used = 0;
    dict->nodes[current].left = -1;
    dict->nodes[current].right = -1;
    dict->count--;
    return 0;
}

int dict_min_key(const Dict *dict, char *out, size_t cap)
{
    int index;

    if (dict == NULL || out == NULL || cap == 0) {
        return -1;
    }
    index = dict_min_node(dict, dict->root);
    if (index < 0) {
        out[0] = '\0';
        return 0;
    }
    dict_copy_bounded(out, cap, dict->nodes[index].key);
    return 1;
}

int dict_max_key(const Dict *dict, char *out, size_t cap)
{
    int index;

    if (dict == NULL || out == NULL || cap == 0) {
        return -1;
    }
    index = dict_max_node(dict, dict->root);
    if (index < 0) {
        out[0] = '\0';
        return 0;
    }
    dict_copy_bounded(out, cap, dict->nodes[index].key);
    return 1;
}

int dict_size(const Dict *dict)
{
    if (dict == NULL) {
        return 0;
    }
    return dict->count;
}

long dict_comparisons(const Dict *dict)
{
    if (dict == NULL) {
        return 0;
    }
    return dict->comparisons;
}
