#include "config.h"
#include <ctype.h>
#include <stdio.h>
#include <string.h>

static void config_trim(char *s)
{
    size_t n = strlen(s);
    size_t start = 0;
    size_t end = n;

    while (start < n && isspace((unsigned char)s[start])) {
        start++;
    }
    while (end > start && isspace((unsigned char)s[end - 1])) {
        end--;
    }
    if (start > 0) {
        memmove(s, s + start, end - start);
    }
    s[end - start] = '\0';
}

static int config_store(Config *cfg, const char *key, const char *value)
{
    if (cfg->count >= CONFIG_MAX_ITEMS) {
        return CONFIG_ERR_FULL;
    }
    memcpy(cfg->items[cfg->count].key, key, strlen(key) + 1);
    memcpy(cfg->items[cfg->count].value, value, strlen(value) + 1);
    cfg->count++;
    return CONFIG_OK;
}

static void config_record_error(ConfigError *errors, int max_errors, int *counter, int line, int code, const char *message)
{
    if (errors == NULL || max_errors <= 0 || *counter >= max_errors) {
        return;
    }
    errors[*counter].line = line;
    errors[*counter].code = code;
    memcpy(errors[*counter].message, message, strlen(message) + 1);
    (*counter)++;
}

int config_parse(Config *cfg, const char *text, ConfigError *errors, int max_errors)
{
    char line[CONFIG_MAX_KEY + CONFIG_MAX_VALUE + 8];
    int line_no;
    size_t pos;
    size_t total;
    int errors_seen;

    if (cfg == NULL || text == NULL) {
        return CONFIG_ERR_NULL;
    }
    cfg->count = 0;
    cfg->error_count = 0;
    errors_seen = 0;
    line_no = 0;
    pos = 0;
    total = strlen(text);
    while (pos < total) {
        size_t len = 0;
        while (pos + len < total && text[pos + len] != '\n') {
            len++;
        }
        if (len >= sizeof line) {
            len = sizeof line - 1;
        }
        memcpy(line, text + pos, len);
        line[len] = '\0';
        line_no++;
        pos += len;
        if (pos < total && text[pos] == '\n') {
            pos++;
        }
        config_trim(line);
        if (line[0] == '\0' || line[0] == '#') {
            continue;
        }
        {
            char *eq = strchr(line, '=');
            char *value;
            if (eq == NULL) {
                cfg->error_count++;
                config_record_error(errors, max_errors, &errors_seen, line_no,
                                    CONFIG_ERR_MISSING_EQUALS, "missing '=' separator");
                continue;
            }
            *eq = '\0';
            config_trim(line);
            value = eq + 1;
            config_trim(value);
            if (line[0] == '\0') {
                cfg->error_count++;
                config_record_error(errors, max_errors, &errors_seen, line_no,
                                    CONFIG_ERR_EMPTY_KEY, "empty key");
                continue;
            }
            if (value[0] == '"' && strlen(value) >= 2) {
                size_t vlen = strlen(value);
                if (value[vlen - 1] == '"') {
                    value[vlen - 1] = '\0';
                    value++;
                }
            }
            if (config_store(cfg, line, value) != CONFIG_OK) {
                cfg->error_count++;
                config_record_error(errors, max_errors, &errors_seen, line_no,
                                    CONFIG_ERR_TOO_MANY, "too many configuration items");
            }
        }
    }
    return cfg->count;
}

int config_get(const Config *cfg, const char *key, char *out, size_t cap)
{
    int i;

    if (cfg == NULL || key == NULL || out == NULL || cap == 0) {
        return CONFIG_ERR_NULL;
    }
    for (i = 0; i < cfg->count; i++) {
        if (strcmp(cfg->items[i].key, key) == 0) {
            size_t n = strlen(cfg->items[i].value);
            if (n + 1 > cap) {
                return CONFIG_ERR_FULL;
            }
            memcpy(out, cfg->items[i].value, n + 1);
            return CONFIG_OK;
        }
    }
    return CONFIG_ERR_NOTFOUND;
}

int config_set(Config *cfg, const char *key, const char *value)
{
    int i;

    if (cfg == NULL || key == NULL || value == NULL) {
        return CONFIG_ERR_NULL;
    }
    for (i = 0; i < cfg->count; i++) {
        if (strcmp(cfg->items[i].key, key) == 0) {
            size_t n = strlen(value);
            if (n + 1 > CONFIG_MAX_VALUE) {
                return CONFIG_ERR_FULL;
            }
            memcpy(cfg->items[i].value, value, n + 1);
            return CONFIG_OK;
        }
    }
    return config_store(cfg, key, value);
}

int config_count(const Config *cfg)
{
    if (cfg == NULL) {
        return CONFIG_ERR_NULL;
    }
    return cfg->count;
}

void config_print(const Config *cfg)
{
    int i;

    if (cfg == NULL) {
        return;
    }
    for (i = 0; i < cfg->count; i++) {
        printf("  %-10s = %s\n", cfg->items[i].key, cfg->items[i].value);
    }
}
