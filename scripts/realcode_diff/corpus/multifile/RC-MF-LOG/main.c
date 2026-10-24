#include <stdio.h>
#include "log.h"

int main(void)
{
    int i;
    int rc;

    printf("=== level = INFO, 8 messages ===\n");
    log_set_level(LOG_INFO);
    log_write(LOG_DEBUG, "debug message 1");
    log_write(LOG_DEBUG, "debug message 2");
    log_write(LOG_INFO, "info message 1");
    log_write(LOG_INFO, "info message 2");
    log_write(LOG_WARN, "warn message 1");
    log_write(LOG_WARN, "warn message 2");
    log_write(LOG_ERROR, "error message 1");
    log_write(LOG_ERROR, "error message 2");

    printf("=== level = WARN, 4 messages ===\n");
    log_set_level(LOG_WARN);
    log_write(LOG_DEBUG, "filtered debug 3");
    log_write(LOG_INFO, "filtered info 3");
    log_write(LOG_WARN, "warn message 3");
    log_write(LOG_ERROR, "error message 3");

    printf("=== level = DEBUG, 2 messages ===\n");
    log_set_level(LOG_DEBUG);
    log_write(LOG_DEBUG, "debug message 3");
    log_write(LOG_INFO, "info message 3");

    printf("=== level names ===\n");
    for (i = 0; i < LOG_LEVEL_COUNT; i++) {
        LogLevel level = (LogLevel)i;
        printf("  %d -> %s\n", (int)level, log_level_name(level));
    }
    printf("  from_name(\"WARN\") = %d\n", (int)log_level_from_name("WARN"));
    printf("  from_name(\"NOPE\") = %d\n", (int)log_level_from_name("NOPE"));

    printf("=== error handling ===\n");
    rc = log_write(LOG_LEVEL_COUNT, "bad level");
    printf("write bad level rc=%d\n", rc);
    rc = log_write(LOG_INFO, NULL);
    printf("write null msg rc=%d\n", rc);

    printf("=== statistics ===\n");
    for (i = 0; i < LOG_LEVEL_COUNT; i++) {
        LogLevel level = (LogLevel)i;
        printf("  %-5s written=%d emitted=%d\n", log_level_name(level),
               log_count_written(level), log_count_emitted(level));
    }
    printf("sequence=%d current_level=%s\n", log_sequence, log_level_name(log_current_level));
    return 0;
}
