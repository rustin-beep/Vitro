#ifndef LOG_H
#define LOG_H

typedef enum {
    LOG_DEBUG = 0,
    LOG_INFO = 1,
    LOG_WARN = 2,
    LOG_ERROR = 3,
    LOG_LEVEL_COUNT = 4
} LogLevel;

/* current filter level; defined in log.c and shared through this header */
extern LogLevel log_current_level;

/* global message counter; defined in log.c */
extern int log_sequence;

#define LOG_OK         0
#define LOG_ERR_NULL (-1)
#define LOG_ERR_LEVEL (-2)

void log_set_level(LogLevel level);
LogLevel log_level_from_name(const char *name);
const char *log_level_name(LogLevel level);

/* writes a single formatted line "[LEVEL] #seq message"; filtered messages are counted but not printed */
int log_write(LogLevel level, const char *msg);
int log_count_written(LogLevel level);
int log_count_emitted(LogLevel level);
void log_reset_stats(void);

#endif /* LOG_H */
