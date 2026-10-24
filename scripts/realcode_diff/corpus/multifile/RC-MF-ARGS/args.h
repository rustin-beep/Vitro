#ifndef ARGS_H
#define ARGS_H

#include <stddef.h>

#define ARGS_MAX_OPTIONS 16
#define ARGS_MAX_NAME 32
#define ARGS_MAX_VALUE 64
#define ARGS_MAX_HELP 64
#define ARGS_MAX_POSITIONAL 16
#define ARGS_MAX_MESSAGE 128

#define ARGS_SOURCE_DEFAULT 0
#define ARGS_SOURCE_EXPLICIT 1

typedef struct {
    char long_name[ARGS_MAX_NAME];
    char short_name;
    int has_arg;
    char default_value[ARGS_MAX_VALUE];
    char help[ARGS_MAX_HELP];
} ArgOption;

typedef struct {
    ArgOption options[ARGS_MAX_OPTIONS];
    int option_count;
    char values[ARGS_MAX_OPTIONS][ARGS_MAX_VALUE];
    int is_set[ARGS_MAX_OPTIONS];
    int source[ARGS_MAX_OPTIONS];
    int occurrences[ARGS_MAX_OPTIONS];
    char positional[ARGS_MAX_POSITIONAL][ARGS_MAX_VALUE];
    int positional_count;
    int errors;
    char error_message[ARGS_MAX_MESSAGE];
} Args;

void args_init(Args *args);

/* registers an option, returns 0 on success */
int args_add_option(Args *args, const char *long_name, char short_name, int has_arg,
                    const char *default_value, const char *help);

/* parses the argument vector, returns the number of errors */
int args_parse(Args *args, int argc, char **argv);

int args_get_value(const Args *args, const char *long_name, char *out, size_t cap);
int args_is_set(const Args *args, const char *long_name);
int args_source(const Args *args, const char *long_name);
int args_occurrences(const Args *args, const char *long_name);
int args_positional_count(const Args *args);
int args_error_count(const Args *args);
const char *args_error_message(const Args *args);
void args_print_help(const Args *args);
int args_edit_distance(const char *a, const char *b);

extern int args_ops;

#endif /* ARGS_H */
