#ifndef CONFIG_H
#define CONFIG_H

#include <stddef.h>

#define CONFIG_MAX_ITEMS 64
#define CONFIG_MAX_KEY   32
#define CONFIG_MAX_VALUE 64
#define CONFIG_MAX_ERRORS 16

#define CONFIG_OK           0
#define CONFIG_ERR_NULL   (-1)
#define CONFIG_ERR_FULL   (-2)
#define CONFIG_ERR_NOTFOUND (-3)

typedef struct {
    char key[CONFIG_MAX_KEY];
    char value[CONFIG_MAX_VALUE];
} ConfigItem;

typedef struct {
    ConfigItem items[CONFIG_MAX_ITEMS];
    int count;
    int error_count;
} Config;

typedef struct {
    int line;
    int code;
    char message[64];
} ConfigError;

#define CONFIG_ERR_MISSING_EQUALS 1
#define CONFIG_ERR_EMPTY_KEY      2
#define CONFIG_ERR_TOO_MANY       3

/* parses "key = value" lines, "# comments" and blank lines; quoted values keep spaces */
int config_parse(Config *cfg, const char *text, ConfigError *errors, int max_errors);
int config_get(const Config *cfg, const char *key, char *out, size_t cap);
int config_set(Config *cfg, const char *key, const char *value);
int config_count(const Config *cfg);
void config_print(const Config *cfg);

#endif /* CONFIG_H */
