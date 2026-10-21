// @category: llm_regression
// #201 红锚：函数指针分发表（struct 含函数指针成员 + 字符串查表）
// 来源：LLM 探针批 12 q36a3b/CMDTAB_s1（277 行，2026-10-21 入库；clang golden 由 clang_direct 现场生成）
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <math.h>

/* 
 * C23 Teaching Subset Command Dispatcher
 * 
 * Constraints:
 * - No stdint.h types (use unsigned char, unsigned int, unsigned long long)
 * - No bitfields, restrict, _Static_assert, _Alignas, _Complex, va_list, VLA, compound literals, _Generic, nested functions
 * - Global/static arrays <= 60KB
 * - No %p, no printing pointers
 * - ASCII only output
 * - No direct printing of ctype return values
 * - Fixed seed LCG for random (not used here but available if needed)
 * - Initialize buffers before use
 * - Function pointers in struct at end
 * - Explicit (p) != 0 checks for function pointers
 */

/* Command structure definition */
typedef struct {
    char name[16];
    char help[40];
    void (*handler)(int argc, const char *argv[]);
} Command;

/* Global command table */
static Command command_table[100];
static int command_count = 0;

/* Helper: find command by name */
static int find_command(const char *name) {
    int i;
    for (i = 0; i < command_count; i++) {
        if (strcmp(command_table[i].name, name) == 0) {
            return i;
        }
    }
    return -1;
}

/* Handler implementations */
static void handler_help(int argc, const char *argv[]) {
    printf("Command: help\n");
    printf("Args count: %d\n", argc);
    if (argc > 0) {
        int i;
        printf("Args:");
        for (i = 0; i < argc; i++) {
            printf(" %s", argv[i]);
        }
        printf("\n");
    }
}

static void handler_add(int argc, const char *argv[]) {
    printf("Command: add\n");
    printf("Args count: %d\n", argc);
    if (argc > 0) {
        int i;
        printf("Args:");
        for (i = 0; i < argc; i++) {
            printf(" %s", argv[i]);
        }
        printf("\n");
    }
}

static void handler_sub(int argc, const char *argv[]) {
    printf("Command: sub\n");
    printf("Args count: %d\n", argc);
    if (argc > 0) {
        int i;
        printf("Args:");
        for (i = 0; i < argc; i++) {
            printf(" %s", argv[i]);
        }
        printf("\n");
    }
}

static void handler_mul(int argc, const char *argv[]) {
    printf("Command: mul\n");
    printf("Args count: %d\n", argc);
    if (argc > 0) {
        int i;
        printf("Args:");
        for (i = 0; i < argc; i++) {
            printf(" %s", argv[i]);
        }
        printf("\n");
    }
}

static void handler_list(int argc, const char *argv[]) {
    printf("Command: list\n");
    printf("Args count: %d\n", argc);
    if (argc > 0) {
        int i;
        printf("Args:");
        for (i = 0; i < argc; i++) {
            printf(" %s", argv[i]);
        }
        printf("\n");
    }
}

static void handler_exit(int argc, const char *argv[]) {
    printf("Command: exit\n");
    printf("Args count: %d\n", argc);
    if (argc > 0) {
        int i;
        printf("Args:");
        for (i = 0; i < argc; i++) {
            printf(" %s", argv[i]);
        }
        printf("\n");
    }
}

/* Register a command */
int register_command(const char *name, void (*handler)(int argc, const char *argv[]), const char *help) {
    int idx;
    if (command_count >= 100) {
        return 0;
    }
    idx = find_command(name);
    if (idx >= 0) {
        return 0;
    }
    strncpy(command_table[command_count].name, name, 15);
    command_table[command_count].name[15] = '\0';
    strncpy(command_table[command_count].help, help, 39);
    command_table[command_count].help[39] = '\0';
    command_table[command_count].handler = handler;
    command_count++;
    return 1;
}

/* Unregister a command */
int unregister_command(const char *name) {
    int idx;
    idx = find_command(name);
    if (idx < 0) {
        return 0;
    }
    /* Shift remaining commands down */
    int i;
    for (i = idx; i < command_count - 1; i++) {
        command_table[i] = command_table[i + 1];
    }
    command_count--;
    return 1;
}

/* Dispatch a line of input */
void dispatch(const char *line) {
    char buffer[256];
    const char *p;
    char *args[50];
    int argc;
    int i;
    
    /* Copy line to buffer */
    strncpy(buffer, line, 255);
    buffer[255] = '\0';
    
    /* Trim trailing whitespace */
    int len = strlen(buffer);
    while (len > 0 && isspace((unsigned char)buffer[len - 1])) {
        buffer[len - 1] = '\0';
        len--;
    }
    
    if (len == 0) {
        return;
    }
    
    /* Tokenize by spaces using strspn/strcscn */
    argc = 0;
    p = buffer;
    while (*p != '\0' && argc < 50) {
        /* Skip leading spaces */
        while (*p != '\0' && isspace((unsigned char)*p)) {
            p++;
        }
        if (*p == '\0') {
            break;
        }
        
        /* Find end of token */
        const char *start = p;
        while (*p != '\0' && !isspace((unsigned char)*p)) {
            p++;
        }
        
        /* Save token */
        args[argc] = (char *)malloc((size_t)(p - start + 1));
        if (args[argc] != 0) {
            strncpy(args[argc], start, (size_t)(p - start));
            args[argc][p - start] = '\0';
            argc++;
        }
    }
    
    if (argc == 0) {
        /* Clean up */
        for (i = 0; i < argc; i++) {
            free(args[i]);
        }
        return;
    }
    
    /* Find command */
    int cmd_idx = find_command(args[0]);
    if (cmd_idx < 0) {
        printf("Unknown command: %s\n", args[0]);
        for (i = 0; i < argc; i++) {
            free(args[i]);
        }
        return;
    }
    
    /* Call handler */
    if (command_table[cmd_idx].handler != 0) {
        command_table[cmd_idx].handler(argc - 1, (const char **)(args + 1));
    }
    
    /* Clean up args */
    for (i = 0; i < argc; i++) {
        free(args[i]);
    }
}

/* Main function */
int main(void) {
    /* Register initial commands */
    register_command("help", handler_help, "Show help");
    register_command("add", handler_add, "Add values");
    register_command("sub", handler_sub, "Subtract values");
    register_command("mul", handler_mul, "Multiply values");
    register_command("list", handler_list, "List items");
    register_command("exit", handler_exit, "Exit program");
    
    /* Test cases */
    dispatch("help");
    dispatch("add 1 2 3");
    dispatch("sub 10 5");
    dispatch("mul 3 4");
    dispatch("list");
    dispatch("exit");
    dispatch("help foo bar");
    dispatch("add");
    dispatch("unknown_cmd");
    dispatch("another_unknown");
    dispatch("add 1"); /* Parameter count mismatch - just shows args */
    
    /* Unregister a command */
    unregister_command("add");
    
    /* Try to dispatch unregistered command */
    dispatch("add 1 2");
    
    /* Print command table info */
    printf("Command count: %d\n", command_count);
    printf("Commands:");
    int i;
    for (i = 0; i < command_count; i++) {
        printf(" %s", command_table[i].name);
    }
    printf("\n");
    
    return 0;
}
