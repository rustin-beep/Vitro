#include <stdio.h>
#include <string.h>
#include "args.h"

int main(void)
{
    Args args;
    char arg0[] = "app";
    char arg1[] = "--output=report.txt";
    char arg2[] = "-v";
    char arg3[] = "-n";
    char arg4[] = "5";
    char arg5[] = "--verbos";
    char arg6[] = "--output";
    char arg7[] = "second.txt";
    char arg8[] = "--";
    char arg9[] = "positional1";
    char arg10[] = "positional2";
    char *argv[12];
    int argc;
    char value[ARGS_MAX_VALUE];
    int errors;
    int i;

    argv[0] = arg0;
    argv[1] = arg1;
    argv[2] = arg2;
    argv[3] = arg3;
    argv[4] = arg4;
    argv[5] = arg5;
    argv[6] = arg6;
    argv[7] = arg7;
    argv[8] = arg8;
    argv[9] = arg9;
    argv[10] = arg10;
    argv[11] = NULL;
    argc = 11;

    args_init(&args);
    args_add_option(&args, "output", 'o', 1, "default.out", "file the report is written to");
    args_add_option(&args, "verbose", 'v', 0, "0", "print more information");
    args_add_option(&args, "count", 'n', 1, "1", "how many items are processed");
    args_add_option(&args, "level", 'l', 1, "info", "verbosity level");

    printf("=== parse ===\n");
    errors = args_parse(&args, argc, argv);
    printf("  errors=%d\n", errors);
    printf("  message=%s\n", args_error_message(&args));

    printf("=== option values ===\n");
    for (i = 0; i < args.option_count; i++) {
        const char *source = (args_source(&args, args.options[i].long_name) == ARGS_SOURCE_EXPLICIT)
                                 ? "explicit" : "default";
        args_get_value(&args, args.options[i].long_name, value, sizeof value);
        printf("  --%-8s value=%-12s source=%-8s set=%d occurrences=%d\n",
               args.options[i].long_name, value, source,
               args_is_set(&args, args.options[i].long_name),
               args_occurrences(&args, args.options[i].long_name));
    }

    printf("=== positional arguments ===\n");
    printf("  count=%d\n", args_positional_count(&args));
    for (i = 0; i < args.positional_count; i++) {
        printf("  [%d] %s\n", i, args.positional[i]);
    }

    printf("=== help ===\n");
    args_print_help(&args);

    printf("=== suggestions ===\n");
    printf("  edit_distance(output,ouput)=%d\n", args_edit_distance("output", "ouput"));
    printf("  edit_distance(output,verbose)=%d\n", args_edit_distance("output", "verbose"));
    printf("  edit_distance(level,levels)=%d\n", args_edit_distance("level", "levels"));
    printf("  args_ops=%d\n", args_ops);
    return 0;
}
