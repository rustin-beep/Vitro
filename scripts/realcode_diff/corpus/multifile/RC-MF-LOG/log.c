#include "log.h"
#include <stdio.h>
#include <string.h>

LogLevel log_current_level = LOG_INFO;
int log_sequence = 0;

static int level_written[LOG_LEVEL_COUNT];
static int level_emitted[LOG_LEVEL_COUNT];

void log_set_level(LogLevel level)
{
    if (level < LOG_DEBUG || level >= LOG_LEVEL_COUNT) {
        return;
    }
    log_current_level = level;
}

const char *log_level_name(LogLevel level)
{
    switch (level) {
        case LOG_DEBUG:
            return "DEBUG";
        case LOG_INFO:
            return "INFO";
        case LOG_WARN:
            return "WARN";
        case LOG_ERROR:
            return "ERROR";
        default:
            return "UNKNOWN";
    }
}

LogLevel log_level_from_name(const char *name)
{
    if (name == NULL) {
        return LOG_LEVEL_COUNT;
    }
    if (strcmp(name, "DEBUG") == 0) {
        return LOG_DEBUG;
    }
    if (strcmp(name, "INFO") == 0) {
        return LOG_INFO;
    }
    if (strcmp(name, "WARN") == 0) {
        return LOG_WARN;
    }
    if (strcmp(name, "ERROR") == 0) {
        return LOG_ERROR;
    }
    return LOG_LEVEL_COUNT;
}

int log_write(LogLevel level, const char *msg)
{
    if (msg == NULL) {
        return LOG_ERR_NULL;
    }
    if (level < LOG_DEBUG || level >= LOG_LEVEL_COUNT) {
        return LOG_ERR_LEVEL;
    }
    log_sequence++;
    level_written[level]++;
    if (level < log_current_level) {
        return LOG_OK;
    }
    printf("[%-5s] #%03d %s\n", log_level_name(level), log_sequence, msg);
    level_emitted[level]++;
    return LOG_OK;
}

int log_count_written(LogLevel level)
{
    if (level < LOG_DEBUG || level >= LOG_LEVEL_COUNT) {
        return LOG_ERR_LEVEL;
    }
    return level_written[level];
}

int log_count_emitted(LogLevel level)
{
    if (level < LOG_DEBUG || level >= LOG_LEVEL_COUNT) {
        return LOG_ERR_LEVEL;
    }
    return level_emitted[level];
}

void log_reset_stats(void)
{
    int i;

    for (i = 0; i < LOG_LEVEL_COUNT; i++) {
        level_written[i] = 0;
        level_emitted[i] = 0;
    }
    log_sequence = 0;
}
