#include <stdio.h>
#include <string.h>
#include "dict.h"

static const char *const KEYS[15] = {
    "apple", "banana", "cherry", "date", "elderberry",
    "fig", "grape", "honeydew", "kiwi", "lemon",
    "mango", "nectarine", "orange", "papaya", "quince"
};

static void show_order(const Dict *dict, const char *label)
{
    char keys[DICT_MAX_NODES][DICT_KEY_LEN];
    int count = dict_keys_in_order(dict, keys, DICT_MAX_NODES);
    int i;

    printf("  %-22s size=%2d order=", label, dict_size(dict));
    for (i = 0; i < count; i++) {
        printf("%s%s", (i > 0) ? "," : "", keys[i]);
    }
    printf("\n");
}

static const char *node_kind(const Dict *dict, const char *key)
{
    int i;

    for (i = 0; i < DICT_MAX_NODES; i++) {
        if (dict->nodes[i].used && strcmp(dict->nodes[i].key, key) == 0) {
            int left = dict->nodes[i].left >= 0;
            int right = dict->nodes[i].right >= 0;
            if (left && right) {
                return "two children";
            }
            if (left || right) {
                return "one child";
            }
            return "leaf";
        }
    }
    return "missing";
}

int main(void)
{
    Dict dict;
    char keys[DICT_MAX_NODES][DICT_KEY_LEN];
    char best[DICT_KEY_LEN];
    int i;
    int rc;
    int value;
    int comparisons;

    dict_init(&dict);

    printf("=== insert 15 keys ===\n");
    for (i = 0; i < 15; i++) {
        rc = dict_put(&dict, KEYS[i], (i + 1) * 11);
        printf("  put %-12s value=%3d rc=%d\n", KEYS[i], (i + 1) * 11, rc);
        show_order(&dict, "in order");
    }

    printf("=== remove three keys ===\n");
    {
        static const char *const REMOVALS[3] = { "fig", "grape", "elderberry" };
        for (i = 0; i < 3; i++) {
            printf("  removing %-12s kind=%s\n", REMOVALS[i], node_kind(&dict, REMOVALS[i]));
            rc = dict_remove(&dict, REMOVALS[i]);
            printf("    rc=%d\n", rc);
            show_order(&dict, "in order");
        }
    }
    rc = dict_remove(&dict, "not-there");
    printf("  remove unknown key rc=%d\n", rc);

    printf("=== lookups ===\n");
    {
        static const char *const HITS[3] = { "apple", "kiwi", "quince" };
        static const char *const MISSES[3] = { "zebra", "banana2", "zzz" };
        for (i = 0; i < 3; i++) {
            rc = dict_get(&dict, HITS[i], &value, &comparisons);
            printf("  get %-10s rc=%2d comparisons=%2d value=%d\n", HITS[i], rc, comparisons, value);
        }
        for (i = 0; i < 3; i++) {
            rc = dict_get(&dict, MISSES[i], &value, &comparisons);
            printf("  get %-10s rc=%2d comparisons=%2d (not found)\n", MISSES[i], rc, comparisons);
        }
    }

    printf("=== bounds ===\n");
    dict_min_key(&dict, best, sizeof best);
    printf("  min_key=%s\n", best);
    dict_max_key(&dict, best, sizeof best);
    printf("  max_key=%s\n", best);
    printf("  size=%d total_comparisons=%ld\n", dict_size(&dict), dict_comparisons(&dict));

    printf("=== range query ===\n");
    {
        int count = dict_range(&dict, "date", "mango", keys, DICT_MAX_NODES);
        printf("  range [date, mango] count=%d\n", count);
        for (i = 0; i < count; i++) {
            rc = dict_get(&dict, keys[i], &value, &comparisons);
            printf("    %-12s = %d (rc=%d)\n", keys[i], value, rc);
        }
        count = dict_range(&dict, "a", "z", keys, DICT_MAX_NODES);
        printf("  range [a, z] count=%d\n", count);
        count = dict_range(&dict, "p", "q", keys, DICT_MAX_NODES);
        printf("  range [p, q] count=%d\n", count);
    }

    printf("=== update an existing key ===\n");
    rc = dict_put(&dict, "kiwi", 999);
    printf("  put kiwi=999 rc=%d\n", rc);
    rc = dict_get(&dict, "kiwi", &value, &comparisons);
    printf("  get kiwi rc=%d value=%d size=%d\n", rc, value, dict_size(&dict));
    show_order(&dict, "in order");
    printf("  dict_ops=%d\n", dict_ops);
    return 0;
}
