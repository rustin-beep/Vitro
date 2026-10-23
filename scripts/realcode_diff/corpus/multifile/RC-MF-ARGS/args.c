#include "args.h"

int args_ops = 0;
#include <string.h>
#include <stdio.h>

static void args_copy(char *dst, size_t cap, const char *src)
{
    size_t n;

    if (dst == NULL || src == NULL || cap == 0) {
        return;
    }
    n = strlen(src);
    if (n > cap - 1) {
        n = cap - 1;
    }
    memcpy(dst, src, n);
    dst[n] = '\0';
}

void args_init(Args *args)
{
    int i;

    if (args == NULL) {
        return;
    }
    memset(args, 0, sizeof(Args));
    for (i = 0; i < ARGS_MAX_OPTIONS; i++) {
        args->values[i][0] = '\0';
        args->is_set[i] = 0;
        args->source[i] = ARGS_SOURCE_DEFAULT;
        args->occurrences[i] = 0;
    }
    args->option_count = 0;
    args->positional_count = 0;
    args->errors = 0;
    args->error_message[0] = '\0';
}

int args_add_option(Args *args, const char *long_name, char short_name, int has_arg,
                    const char *default_value, const char *help)
{
    ArgOption *option;

    if (args == NULL || long_name == NULL) {
        return -1;
    }
    if (args->option_count >= ARGS_MAX_OPTIONS) {
        return -2;
    }
    option = &args->options[args->option_count];
    args_copy(option->long_name, sizeof option->long_name, long_name);
    option->short_name = short_name;
    option->has_arg = has_arg;
    args_copy(option->default_value, sizeof option->default_value,
              (default_value != NULL) ? default_value : "");
    args_copy(option->help, sizeof option->help, (help != NULL) ? help : "");
    args_copy(args->values[args->option_count], sizeof args->values[0], option->default_value);
    args->source[args->option_count] = ARGS_SOURCE_DEFAULT;
    args->option_count++;
    args_ops++;
    return 0;
}

static int args_find_long(const Args *args, const char *name)
{
    int i;

    for (i = 0; i < args->option_count; i++) {
        if (strcmp(args->options[i].long_name, name) == 0) {
            return i;
        }
    }
    return -1;
}

static int args_find_short(const Args *args, char name)
{
    int i;

    if (name == '\0') {
        return -1;
    }
    for (i = 0; i < args->option_count; i++) {
        if (args->options[i].short_name == name) {
            return i;
        }
    }
    return -1;
}

int args_edit_distance(const char *a, const char *b)
{
    int previous[ARGS_MAX_NAME + 1];
    int current[ARGS_MAX_NAME + 1];
    size_t len_a;
    size_t len_b;
    size_t i;
    size_t j;

    if (a == NULL || b == NULL) {
        return 0;
    }
    len_a = strlen(a);
    len_b = strlen(b);
    if (len_a > ARGS_MAX_NAME) {
        len_a = ARGS_MAX_NAME;
    }
    if (len_b > ARGS_MAX_NAME) {
        len_b = ARGS_MAX_NAME;
    }
    for (j = 0; j <= len_b; j++) {
        previous[j] = (int)j;
    }
    for (i = 1; i <= len_a; i++) {
        current[0] = (int)i;
        for (j = 1; j <= len_b; j++) {
            int cost = (a[i - 1] == b[j - 1]) ? 0 : 1;
            int delete = previous[j] + 1;
            int insert = current[j - 1] + 1;
            int replace = previous[j - 1] + cost;
            int best = delete;
            if (insert < best) {
                best = insert;
            }
            if (replace < best) {
                best = replace;
            }
            current[j] = best;
        }
        for (j = 0; j <= len_b; j++) {
            previous[j] = current[j];
        }
    }
    return previous[len_b];
}

static void args_set_value(Args *args, int index, const char *value)
{
    args_copy(args->values[index], sizeof args->values[0], value);
    args->is_set[index] = 1;
    args->source[index] = ARGS_SOURCE_EXPLICIT;
    args->occurrences[index]++;
}

static void args_report_error(Args *args, const char *message)
{
    args->errors++;
    if (args->error_message[0] == '\0') {
        args_copy(args->error_message, sizeof args->error_message, message);
    }
}

static void args_suggest(const Args *args, const char *name, char *out, size_t cap)
{
    int best = -1;
    int best_distance = 4;
    int i;

    out[0] = '\0';
    for (i = 0; i < args->option_count; i++) {
        int distance = args_edit_distance(name, args->options[i].long_name);
        if (distance < best_distance) {
            best_distance = distance;
            best = i;
        }
    }
    if (best >= 0) {
        args_copy(out, cap, args->options[best].long_name);
    }
}

int args_parse(Args *args, int argc, char **argv)
{
    int i;
    int only_positional = 0;

    if (args == NULL) {
        return -1;
    }
    for (i = 0; i < args->option_count; i++) {
        args_copy(args->values[i], sizeof args->values[0], args->options[i].default_value);
        args->is_set[i] = 0;
        args->source[i] = ARGS_SOURCE_DEFAULT;
        args->occurrences[i] = 0;
    }
    args->positional_count = 0;
    args->errors = 0;
    args->error_message[0] = '\0';

    for (i = 1; i < argc; i++) {
        const char *arg = argv[i];
        if (arg == NULL) {
            continue;
        }
        if (only_positional) {
            if (args->positional_count < ARGS_MAX_POSITIONAL) {
                args_copy(args->positional[args->positional_count],
                          sizeof args->positional[0], arg);
                args->positional_count++;
            } else {
                args_report_error(args, "too many positional arguments");
            }
            continue;
        }
        if (strcmp(arg, "--") == 0) {
            only_positional = 1;
            continue;
        }
        if (arg[0] == '-' && arg[1] == '-') {
            char name[ARGS_MAX_NAME];
            const char *equals = strchr(arg + 2, '=');
            int index;
            if (equals != NULL) {
                size_t n = (size_t)(equals - (arg + 2));
                if (n > ARGS_MAX_NAME - 1) {
                    n = ARGS_MAX_NAME - 1;
                }
                memcpy(name, arg + 2, n);
                name[n] = '\0';
            } else {
                args_copy(name, sizeof name, arg + 2);
            }
            index = args_find_long(args, name);
            if (index < 0) {
                char suggestion[ARGS_MAX_NAME];
                char message[ARGS_MAX_MESSAGE];
                args_suggest(args, name, suggestion, sizeof suggestion);
                if (suggestion[0] != '\0') {
                    sprintf(message, "unknown option --%s, did you mean --%s?", name, suggestion);
                } else {
                    sprintf(message, "unknown option --%s", name);
                }
                args_report_error(args, message);
                continue;
            }
            if (args->options[index].has_arg) {
                if (equals != NULL) {
                    args_set_value(args, index, equals + 1);
                } else if (i + 1 < argc && argv[i + 1] != NULL) {
                    i++;
                    args_set_value(args, index, argv[i]);
                } else {
                    args_report_error(args, "option needs a value");
                }
            } else {
                args_set_value(args, index, "1");
            }
            continue;
        }
        if (arg[0] == '-' && arg[1] != '\0') {
            int index = args_find_short(args, arg[1]);
            if (index < 0) {
                char message[ARGS_MAX_MESSAGE];
                sprintf(message, "unknown option -%c", arg[1]);
                args_report_error(args, message);
                continue;
            }
            if (args->options[index].has_arg) {
                if (arg[2] != '\0') {
                    args_set_value(args, index, arg + 2);
                } else if (i + 1 < argc && argv[i + 1] != NULL) {
                    i++;
                    args_set_value(args, index, argv[i]);
                } else {
                    args_report_error(args, "option needs a value");
                }
            } else {
                args_set_value(args, index, "1");
            }
            continue;
        }
        if (args->positional_count < ARGS_MAX_POSITIONAL) {
            args_copy(args->positional[args->positional_count], sizeof args->positional[0], arg);
            args->positional_count++;
        } else {
            args_report_error(args, "too many positional arguments");
        }
    }
    return args->errors;
}

int args_get_value(const Args *args, const char *long_name, char *out, size_t cap)
{
    int index;

    if (args == NULL || long_name == NULL || out == NULL) {
        return -1;
    }
    index = args_find_long(args, long_name);
    if (index < 0) {
        return -2;
    }
    args_copy(out, cap, args->values[index]);
    return 0;
}

int args_is_set(const Args *args, const char *long_name)
{
    int index;

    if (args == NULL || long_name == NULL) {
        return 0;
    }
    index = args_find_long(args, long_name);
    if (index < 0) {
        return 0;
    }
    return args->is_set[index];
}

int args_source(const Args *args, const char *long_name)
{
    int index;

    if (args == NULL || long_name == NULL) {
        return ARGS_SOURCE_DEFAULT;
    }
    index = args_find_long(args, long_name);
    if (index < 0) {
        return ARGS_SOURCE_DEFAULT;
    }
    return args->source[index];
}

int args_occurrences(const Args *args, const char *long_name)
{
    int index;

    if (args == NULL || long_name == NULL) {
        return 0;
    }
    index = args_find_long(args, long_name);
    if (index < 0) {
        return 0;
    }
    return args->occurrences[index];
}

int args_positional_count(const Args *args)
{
    if (args == NULL) {
        return 0;
    }
    return args->positional_count;
}

int args_error_count(const Args *args)
{
    if (args == NULL) {
        return 0;
    }
    return args->errors;
}

const char *args_error_message(const Args *args)
{
    if (args == NULL) {
        return "";
    }
    return args->error_message;
}

void args_print_help(const Args *args)
{
    int i;

    if (args == NULL) {
        return;
    }
    printf("usage: program [options] [arguments]\n");
    printf("options:\n");
    for (i = 0; i < args->option_count; i++) {
        const ArgOption *option = &args->options[i];
        printf("  --%-10s -%-2c %-40s %s\n",
               option->long_name,
               (option->short_name != '\0') ? option->short_name : ' ',
               option->has_arg ? "<value>" : "",
               option->help);
    }
}
