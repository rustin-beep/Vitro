#include <stdio.h>
#include "config.h"

static const char *CONFIG_TEXT =
    "# sample configuration\n"
    "\n"
    "name = vitro\n"
    "version = 0.8.0\n"
    "title = \"Vitro C23 Compiler\"\n"
    "  spaced_key   =   spaced value   \n"
    "mode=release\n"
    "broken line without separator\n"
    "= empty key\n"
    "trailing = last\n";

int main(void)
{
    Config cfg;
    ConfigError errors[CONFIG_MAX_ERRORS];
    char value[CONFIG_MAX_VALUE];
    int rc;
    int i;

    for (i = 0; i < CONFIG_MAX_ERRORS; i++) {
        errors[i].line = 0;
        errors[i].code = 0;
        errors[i].message[0] = '\0';
    }

    rc = config_parse(&cfg, CONFIG_TEXT, errors, CONFIG_MAX_ERRORS);
    printf("=== parsed %d items ===\n", rc);
    config_print(&cfg);

    printf("=== query existing ===\n");
    rc = config_get(&cfg, "name", value, sizeof value);
    printf("get name     rc=%2d value=[%s]\n", rc, value);
    rc = config_get(&cfg, "version", value, sizeof value);
    printf("get version  rc=%2d value=[%s]\n", rc, value);
    rc = config_get(&cfg, "title", value, sizeof value);
    printf("get title    rc=%2d value=[%s]\n", rc, value);

    printf("=== query missing ===\n");
    rc = config_get(&cfg, "missing_key", value, sizeof value);
    printf("get missing_key rc=%2d\n", rc);
    rc = config_get(&cfg, "another_missing", value, sizeof value);
    printf("get another_missing rc=%2d\n", rc);

    printf("=== set then reprint ===\n");
    rc = config_set(&cfg, "version", "0.9.0");
    printf("set version rc=%2d\n", rc);
    rc = config_set(&cfg, "build", "ci-42");
    printf("set new key rc=%2d count=%d\n", rc, config_count(&cfg));
    config_print(&cfg);

    printf("=== errors ===\n");
    printf("error_count=%d\n", cfg.error_count);
    for (i = 0; i < CONFIG_MAX_ERRORS; i++) {
        if (errors[i].line == 0) {
            break;
        }
        printf("  line %d code=%d reason=%s\n", errors[i].line, errors[i].code, errors[i].message);
    }
    return 0;
}
