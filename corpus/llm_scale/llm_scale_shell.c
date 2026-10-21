// @category: llm_scale
// 规模压力面：shell 模拟：管道 + 重定向 + 引号 + 内存文件系统 + 内建命令
// 来源：LLM 千行语料 HUGE-SHELL（1073 行，2026-10-21 入库；clang golden 由 clang_direct 现场生成）
// 注：本档 member_accesses 上限 400（#236 分档），见 scripts/perf_budget/rules.json
/*
 * HUGE-SHELL -- a shell interpreter simulator in one C23 file.
 *
 * Nothing is executed outside of the program, every command is answered by
 * a built in implementation.
 *
 * The line parser understands the pipe character, the output redirection
 * with the greater than sign and the append variant with two greater than
 * signs, the input redirection with the less than sign, single and double
 * quotes, comments that start with a hash and the semicolon as the command
 * separator.
 *
 * The built in commands are echo, ls, cat, grep, wc, sort, head, tail, env,
 * set and exit. They all work on an in memory file system with ten files
 * and on a table of variables.
 *
 * A pipe is executed by handing the output buffer of one stage to the
 * input buffer of the next stage, the program reports how many bytes
 * entered and left every stage.
 *
 * Variables are written with the dollar sign, the set command stores a
 * value and echo expands it.
 *
 * The demo runs a fixed script of fifteen commands with pipes, with
 * redirections, with variable expansions and with a command that fails.
 * Every command prints its result and its exit code, at the end the
 * statistics about the executed commands, the pipes, the redirections and
 * the errors are printed together with the state of the file system.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

/* ------------------------------------------------------------------ */
/* limits                                                             */
/* ------------------------------------------------------------------ */

#define MAX_FILES 10
#define MAX_FILE_NAME 24
#define MAX_FILE_LEN 256
#define MAX_VARS 16
#define MAX_VAR_NAME 24
#define MAX_VAR_VALUE 128
#define MAX_ARGS 8
#define MAX_ARG 64
#define MAX_STATEMENTS 8
#define MAX_STAGES 4
#define MAX_LINE 256
#define MAX_PIPE_BUF 512

/* ------------------------------------------------------------------ */
/* types                                                              */
/* ------------------------------------------------------------------ */

typedef struct {
    char name[MAX_FILE_NAME];
    char content[MAX_FILE_LEN];
    int length;
    int used;
} ShellFile;

typedef struct {
    ShellFile files[MAX_FILES];
    int count;
} FileSystem;

typedef struct {
    char name[MAX_VAR_NAME];
    char value[MAX_VAR_VALUE];
} Variable;

typedef struct {
    Variable vars[MAX_VARS];
    int count;
} ShellEnv;

typedef struct {
    char argv[MAX_ARGS][MAX_ARG];
    int argc;
    char input_file[MAX_FILE_NAME];
    char output_file[MAX_FILE_NAME];
    int has_input;
    int has_output;
    int append_output;
} Stage;

typedef struct {
    Stage stages[MAX_STAGES];
    int stage_count;
    char raw[MAX_LINE];
} Statement;

typedef struct {
    int executed;
    int pipes;
    int redirections;
    int errors;
    int stages_run;
    int bytes_in;
    int bytes_out;
} ShellStats;

typedef struct {
    FileSystem fs;
    ShellEnv env;
    ShellStats stats;
    int exit_code;
    int exited;
} Shell;

/* ------------------------------------------------------------------ */
/* string helpers                                                     */
/* ------------------------------------------------------------------ */

static void sh_copy(char *dst, size_t cap, const char *src)
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

static void sh_trim(char *s)
{
    size_t n;
    size_t start;
    size_t end;

    if (s == NULL) {
        return;
    }
    n = strlen(s);
    start = 0;
    while (start < n && isspace((unsigned char)s[start])) {
        start++;
    }
    end = n;
    while (end > start && isspace((unsigned char)s[end - 1])) {
        end--;
    }
    if (start > 0) {
        memmove(s, s + start, end - start);
    }
    s[end - start] = '\0';
}

static int sh_is_quote(char c)
{
    return (c == '\'' || c == '"') ? 1 : 0;
}

/* ------------------------------------------------------------------ */
/* the in memory file system                                           */
/* ------------------------------------------------------------------ */

static ShellFile *fs_find(FileSystem *fs, const char *name)
{
    int i;

    for (i = 0; i < MAX_FILES; i++) {
        if (fs->files[i].used && strcmp(fs->files[i].name, name) == 0) {
            return &fs->files[i];
        }
    }
    return NULL;
}

static ShellFile *fs_create(FileSystem *fs, const char *name)
{
    ShellFile *file;
    int i;

    file = fs_find(fs, name);
    if (file != NULL) {
        return file;
    }
    for (i = 0; i < MAX_FILES; i++) {
        if (fs->files[i].used) {
            continue;
        }
        file = &fs->files[i];
        memset(file, 0, sizeof(ShellFile));
        file->used = 1;
        sh_copy(file->name, MAX_FILE_NAME, name);
        fs->count++;
        return file;
    }
    return NULL;
}

static int fs_write(FileSystem *fs, const char *name, const char *text, int append)
{
    ShellFile *file = fs_find(fs, name);
    int length;

    if (file == NULL) {
        file = fs_create(fs, name);
        if (file == NULL) {
            return -1;
        }
        file->length = 0;
    }
    length = (int)strlen(text);
    if (append) {
        if (file->length + length + 1 > MAX_FILE_LEN) {
            length = MAX_FILE_LEN - file->length - 1;
        }
    } else {
        length = (length > MAX_FILE_LEN - 1) ? MAX_FILE_LEN - 1 : length;
    }
    memcpy(file->content + file->length, text, (size_t)length);
    file->length += length;
    file->content[file->length] = '\0';
    return length;
}

static void fs_list(const FileSystem *fs)
{
    int i;

    for (i = 0; i < MAX_FILES; i++) {
        if (!fs->files[i].used) {
            continue;
        }
        printf("%-16s %5d bytes\n", fs->files[i].name, fs->files[i].length);
    }
}

static void fs_print_state(const FileSystem *fs)
{
    int i;

    printf("  files=%d\n", fs->count);
    for (i = 0; i < MAX_FILES; i++) {
        if (!fs->files[i].used) {
            continue;
        }
        printf("    %-16s length=%d\n", fs->files[i].name, fs->files[i].length);
    }
}

/* ------------------------------------------------------------------ */
/* variables                                                          */
/* ------------------------------------------------------------------ */

static const char *env_get(const ShellEnv *env, const char *name)
{
    int i;

    for (i = 0; i < env->count; i++) {
        if (strcmp(env->vars[i].name, name) == 0) {
            return env->vars[i].value;
        }
    }
    return NULL;
}

static int env_set(ShellEnv *env, const char *name, const char *value)
{
    int i;

    for (i = 0; i < env->count; i++) {
        if (strcmp(env->vars[i].name, name) == 0) {
            sh_copy(env->vars[i].value, MAX_VAR_VALUE, value);
            return 0;
        }
    }
    if (env->count >= MAX_VARS) {
        return -1;
    }
    sh_copy(env->vars[env->count].name, MAX_VAR_NAME, name);
    sh_copy(env->vars[env->count].value, MAX_VAR_VALUE, value);
    env->count++;
    return 0;
}

static void env_print(const ShellEnv *env)
{
    int i;

    for (i = 0; i < env->count; i++) {
        printf("%s=%s\n", env->vars[i].name, env->vars[i].value);
    }
}

/* expands the dollar sign variables inside a text */
static void env_expand(const ShellEnv *env, const char *text, char *out, size_t cap)
{
    size_t o = 0;
    size_t i = 0;

    while (text[i] != '\0' && o + 1 < cap) {
        if (text[i] == '$' && (isalpha((unsigned char)text[i + 1]) || text[i + 1] == '_')) {
            char name[MAX_VAR_NAME];
            int length = 0;
            int k;
            const char *value;
            i++;
            while ((isalnum((unsigned char)text[i]) || text[i] == '_') && length < MAX_VAR_NAME - 1) {
                name[length] = text[i];
                length++;
                i++;
            }
            name[length] = '\0';
            value = env_get(env, name);
            if (value != NULL) {
                for (k = 0; value[k] != '\0' && o + 1 < cap; k++) {
                    out[o] = value[k];
                    o++;
                }
            } else {
                if (o + 1 < cap) {
                    out[o] = '\0';
                }
                out[o] = '\0';
                return;
            }
            continue;
        }
        out[o] = text[i];
        o++;
        i++;
    }
    out[o] = '\0';
}

/* ------------------------------------------------------------------ */
/* the parser                                                         */
/* ------------------------------------------------------------------ */

/* splits a line into statements at the semicolons that are not quoted */
static int sh_split_statements(const char *line, Statement *statements, int max_statements)
{
    int count = 0;
    size_t i = 0;
    char current[MAX_LINE];
    int length = 0;
    char quote = '\0';

    while (line[i] != '\0' && count < max_statements) {
        char c = line[i];
        if (quote != '\0') {
            if (c == quote) {
                quote = '\0';
            }
        } else if (sh_is_quote(c)) {
            quote = c;
        } else if (c == '#') {
            while (line[i] != '\0' && line[i] != ';') {
                i++;
            }
            continue;
        } else if (c == ';') {
            current[length] = '\0';
            sh_trim(current);
            if (length > 0) {
                sh_copy(statements[count].raw, MAX_LINE, current);
                count++;
            }
            length = 0;
            i++;
            continue;
        }
        if (length < MAX_LINE - 1) {
            current[length] = c;
            length++;
        }
        i++;
    }
    current[length] = '\0';
    sh_trim(current);
    if (length > 0 && count < max_statements) {
        sh_copy(statements[count].raw, MAX_LINE, current);
        count++;
    }
    return count;
}

/* splits a statement into the stages of a pipe */
static int sh_split_stages(const char *statement, char stages[][MAX_LINE], int max_stages)
{
    int count = 0;
    size_t i = 0;
    char current[MAX_LINE];
    int length = 0;
    char quote = '\0';

    while (statement[i] != '\0' && count < max_stages) {
        char c = statement[i];
        if (quote != '\0') {
            if (c == quote) {
                quote = '\0';
            }
        } else if (sh_is_quote(c)) {
            quote = c;
        } else if (c == '|') {
            current[length] = '\0';
            sh_trim(current);
            if (length > 0) {
                sh_copy(stages[count], MAX_LINE, current);
                count++;
            }
            length = 0;
            i++;
            continue;
        }
        if (length < MAX_LINE - 1) {
            current[length] = c;
            length++;
        }
        i++;
    }
    current[length] = '\0';
    sh_trim(current);
    if (length > 0 && count < max_stages) {
        sh_copy(stages[count], MAX_LINE, current);
        count++;
    }
    return count;
}

/* splits one stage into the arguments, the redirections are removed */
static int sh_tokenize(const char *stage, Stage *out)
{
    int count = 0;
    size_t i = 0;
    char token[MAX_ARG];
    int length = 0;
    char quote = '\0';

    memset(out, 0, sizeof(Stage));
    while (stage[i] != '\0') {
        char c = stage[i];
        if (quote != '\0') {
            if (c == quote) {
                quote = '\0';
                i++;
                continue;
            }
            if (length < MAX_ARG - 1) {
                token[length] = c;
                length++;
            }
            i++;
            continue;
        }
        if (sh_is_quote(c)) {
            quote = c;
            i++;
            continue;
        }
        if (isspace((unsigned char)c)) {
            if (length > 0) {
                token[length] = '\0';
                if (count < MAX_ARGS) {
                    sh_copy(out->argv[count], MAX_ARG, token);
                    count++;
                }
                length = 0;
            }
            i++;
            continue;
        }
        if (c == '>') {
            int append = 0;
            i++;
            if (stage[i] == '>') {
                append = 1;
                i++;
            }
            while (stage[i] == ' ' || stage[i] == '\t') {
                i++;
            }
            length = 0;
            while (stage[i] != '\0' && !isspace((unsigned char)stage[i])) {
                if (length < MAX_FILE_NAME - 1) {
                    token[length] = stage[i];
                    length++;
                }
                i++;
            }
            token[length] = '\0';
            sh_copy(out->output_file, MAX_FILE_NAME, token);
            out->has_output = 1;
            out->append_output = append;
            continue;
        }
        if (c == '<') {
            i++;
            while (stage[i] == ' ' || stage[i] == '\t') {
                i++;
            }
            length = 0;
            while (stage[i] != '\0' && !isspace((unsigned char)stage[i])) {
                if (length < MAX_FILE_NAME - 1) {
                    token[length] = stage[i];
                    length++;
                }
                i++;
            }
            token[length] = '\0';
            sh_copy(out->input_file, MAX_FILE_NAME, token);
            out->has_input = 1;
            continue;
        }
        if (length < MAX_ARG - 1) {
            token[length] = c;
            length++;
        }
        i++;
    }
    if (length > 0) {
        token[length] = '\0';
        if (count < MAX_ARGS) {
            sh_copy(out->argv[count], MAX_ARG, token);
            count++;
        }
    }
    out->argc = count;
    return count;
}

/* ------------------------------------------------------------------ */
/* text helpers used by the built in commands                         */
/* ------------------------------------------------------------------ */

static int sh_count_text(const char *text, int *lines, int *words, int *chars)
{
    int line_count = 1;
    int word_count = 0;
    int char_count = 0;
    int in_word = 0;
    size_t i;

    if (text == NULL) {
        *lines = 0;
        *words = 0;
        *chars = 0;
        return 0;
    }
    for (i = 0; text[i] != '\0'; i++) {
        char_count++;
        if (text[i] == '\n') {
            line_count++;
            in_word = 0;
            continue;
        }
        if (isspace((unsigned char)text[i])) {
            in_word = 0;
            continue;
        }
        if (!in_word) {
            word_count++;
            in_word = 1;
        }
    }
    *lines = line_count;
    *words = word_count;
    *chars = char_count;
    return char_count;
}

static int sh_split_lines(const char *text, char lines[][MAX_LINE], int max_lines)
{
    int count = 0;
    size_t i = 0;
    size_t start = 0;

    if (text == NULL) {
        return 0;
    }
    while (text[i] != '\0' && count < max_lines) {
        if (text[i] == '\n') {
            size_t len = i - start;
            if (len > MAX_LINE - 1) {
                len = MAX_LINE - 1;
            }
            memcpy(lines[count], text + start, len);
            lines[count][len] = '\0';
            count++;
            start = i + 1;
        }
        i++;
    }
    if (start < i && count < max_lines) {
        size_t len = i - start;
        if (len > MAX_LINE - 1) {
            len = MAX_LINE - 1;
        }
        memcpy(lines[count], text + start, len);
        lines[count][len] = '\0';
        count++;
    }
    return count;
}

static int sh_append(char *buffer, int cap, int *length, const char *text)
{
    int len = (int)strlen(text);

    if (*length + len + 1 > cap) {
        len = cap - *length - 1;
    }
    if (len <= 0) {
        return 0;
    }
    memcpy(buffer + *length, text, (size_t)len);
    *length += len;
    buffer[*length] = '\0';
    return len;
}

/* ------------------------------------------------------------------ */
/* the built in commands                                              */
/* ------------------------------------------------------------------ */

static int sh_builtin_echo(Shell *shell, const Stage *stage, const char *input,
                           char *output, int cap, int *out_len)
{
    int i;

    (void)input;

    for (i = 1; i < stage->argc; i++) {
        char expanded[MAX_ARG];
        env_expand(&shell->env, stage->argv[i], expanded, sizeof expanded);
        sh_append(output, cap, out_len, expanded);
        if (i + 1 < stage->argc) {
            sh_append(output, cap, out_len, " ");
        }
    }
    sh_append(output, cap, out_len, "\n");
    return 0;
}

static int sh_builtin_ls(Shell *shell, const Stage *stage, const char *input,
                         char *output, int cap, int *out_len)
{
    int i;

    (void)stage;
    (void)input;
    char line[MAX_LINE];

    for (i = 0; i < MAX_FILES; i++) {
        if (!shell->fs.files[i].used) {
            continue;
        }
        sprintf(line, "%-16s %5d bytes\n", shell->fs.files[i].name,
                shell->fs.files[i].length);
        sh_append(output, cap, out_len, line);
    }
    return 0;
}

static int sh_builtin_cat(Shell *shell, const Stage *stage, const char *input,
                          char *output, int cap, int *out_len)
{
    if (stage->argc > 1) {
        ShellFile *file = fs_find(&shell->fs, stage->argv[1]);
        if (file == NULL) {
            return 1;
        }
        sh_append(output, cap, out_len, file->content);
        return 0;
    }
    sh_append(output, cap, out_len, input);
    return 0;
}

static int sh_builtin_grep(Shell *shell, const Stage *stage, const char *input,
                           char *output, int cap, int *out_len)
{
    char lines[32][MAX_LINE];
    char source[MAX_FILE_LEN];
    int count;
    int i;

    if (stage->argc < 2) {
        return 1;
    }
    if (stage->argc > 2) {
        ShellFile *file = fs_find(&shell->fs, stage->argv[2]);
        if (file == NULL) {
            return 1;
        }
        sh_copy(source, sizeof source, file->content);
    } else {
        sh_copy(source, sizeof source, input);
    }
    count = sh_split_lines(source, lines, 32);
    for (i = 0; i < count; i++) {
        if (strstr(lines[i], stage->argv[1]) != NULL) {
            sh_append(output, cap, out_len, lines[i]);
            sh_append(output, cap, out_len, "\n");
        }
    }
    return 0;
}

static int sh_builtin_wc(Shell *shell, const Stage *stage, const char *input,
                         char *output, int cap, int *out_len)
{
    char source[MAX_FILE_LEN];
    int lines = 0;
    int words = 0;
    int chars = 0;
    char line[MAX_LINE];

    if (stage->argc > 1) {
        ShellFile *file = fs_find(&shell->fs, stage->argv[1]);
        if (file == NULL) {
            return 1;
        }
        sh_copy(source, sizeof source, file->content);
    } else {
        sh_copy(source, sizeof source, input);
    }
    sh_count_text(source, &lines, &words, &chars);
    sprintf(line, "%d %d %d\n", lines, words, chars);
    sh_append(output, cap, out_len, line);
    return 0;
}

static int sh_builtin_sort(Shell *shell, const Stage *stage, const char *input,
                           char *output, int cap, int *out_len)
{
    char lines[32][MAX_LINE];
    char source[MAX_FILE_LEN];
    int count;
    int i;
    int j;

    if (stage->argc > 1) {
        ShellFile *file = fs_find(&shell->fs, stage->argv[1]);
        if (file == NULL) {
            return 1;
        }
        sh_copy(source, sizeof source, file->content);
    } else {
        sh_copy(source, sizeof source, input);
    }
    count = sh_split_lines(source, lines, 32);
    for (i = 1; i < count; i++) {
        char current[MAX_LINE];
        sh_copy(current, sizeof current, lines[i]);
        for (j = i - 1; j >= 0; j--) {
            if (strcmp(lines[j], current) <= 0) {
                break;
            }
            sh_copy(lines[j + 1], MAX_LINE, lines[j]);
            sh_copy(lines[j], MAX_LINE, current);
        }
    }
    for (i = 0; i < count; i++) {
        sh_append(output, cap, out_len, lines[i]);
        sh_append(output, cap, out_len, "\n");
    }
    return 0;
}

static int sh_builtin_head_tail(Shell *shell, const Stage *stage, const char *input,
                                char *output, int cap, int *out_len, int tail)
{
    char lines[32][MAX_LINE];
    char source[MAX_FILE_LEN];
    int count;
    int wanted = 10;
    int i;
    int arg = 1;

    if (stage->argc > 1 && stage->argv[1][0] >= '0' && stage->argv[1][0] <= '9') {
        wanted = atoi(stage->argv[1]);
        arg = 2;
    }
    if (stage->argc > arg) {
        ShellFile *file = fs_find(&shell->fs, stage->argv[arg]);
        if (file == NULL) {
            return 1;
        }
        sh_copy(source, sizeof source, file->content);
    } else {
        sh_copy(source, sizeof source, input);
    }
    count = sh_split_lines(source, lines, 32);
    for (i = 0; i < count; i++) {
        if (tail) {
            if (i < count - wanted) {
                continue;
            }
        } else {
            if (i >= wanted) {
                break;
            }
        }
        sh_append(output, cap, out_len, lines[i]);
        sh_append(output, cap, out_len, "\n");
    }
    return 0;
}

static int sh_builtin_head(Shell *shell, const Stage *stage, const char *input,
                           char *output, int cap, int *out_len)
{
    return sh_builtin_head_tail(shell, stage, input, output, cap, out_len, 0);
}

static int sh_builtin_tail(Shell *shell, const Stage *stage, const char *input,
                           char *output, int cap, int *out_len)
{
    return sh_builtin_head_tail(shell, stage, input, output, cap, out_len, 1);
}

static int sh_builtin_env(Shell *shell, const Stage *stage, const char *input,
                          char *output, int cap, int *out_len)
{
    int i;

    (void)stage;
    (void)input;
    char line[MAX_LINE];

    for (i = 0; i < shell->env.count; i++) {
        sprintf(line, "%s=%s\n", shell->env.vars[i].name, shell->env.vars[i].value);
        sh_append(output, cap, out_len, line);
    }
    return 0;
}

static int sh_builtin_set(Shell *shell, const Stage *stage, const char *input,
                          char *output, int cap, int *out_len)
{
    char name[MAX_VAR_NAME];
    char value[MAX_VAR_VALUE];
    const char *equals;
    size_t len;

    if (stage->argc < 2) {
        return 1;
    }
    (void)input;
    (void)output;
    (void)cap;
    (void)out_len;
    equals = strchr(stage->argv[1], '=');
    if (equals == NULL) {
        return 1;
    }
    len = (size_t)(equals - stage->argv[1]);
    if (len > MAX_VAR_NAME - 1) {
        len = MAX_VAR_NAME - 1;
    }
    memcpy(name, stage->argv[1], len);
    name[len] = '\0';
    sh_copy(value, sizeof value, equals + 1);
    return env_set(&shell->env, name, value);
}

static int sh_builtin_exit(Shell *shell, const Stage *stage, const char *input,
                           char *output, int cap, int *out_len)
{
    int code = 0;

    (void)input;
    (void)output;
    (void)cap;
    (void)out_len;

    if (stage->argc > 1) {
        code = atoi(stage->argv[1]);
    }
    shell->exit_code = code;
    shell->exited = 1;
    return code;
}

static int sh_builtin_unknown(Shell *shell, const Stage *stage, const char *input,
                              char *output, int cap, int *out_len)
{
    char line[MAX_LINE];

    (void)shell;
    (void)input;

    sprintf(line, "sh: %s: command not found\n", (stage->argc > 0) ? stage->argv[0] : "?");
    sh_append(output, cap, out_len, line);
    return 127;
}

/* ------------------------------------------------------------------ */
/* the executor                                                       */
/* ------------------------------------------------------------------ */

static int sh_run_stage(Shell *shell, const Stage *stage, const char *input,
                        char *output, int cap, int *out_len)
{
    const char *name;

    *out_len = 0;
    output[0] = '\0';
    if (stage->argc == 0) {
        return 0;
    }
    name = stage->argv[0];
    if (strcmp(name, "echo") == 0) {
        return sh_builtin_echo(shell, stage, input, output, cap, out_len);
    }
    if (strcmp(name, "ls") == 0) {
        return sh_builtin_ls(shell, stage, input, output, cap, out_len);
    }
    if (strcmp(name, "cat") == 0) {
        return sh_builtin_cat(shell, stage, input, output, cap, out_len);
    }
    if (strcmp(name, "grep") == 0) {
        return sh_builtin_grep(shell, stage, input, output, cap, out_len);
    }
    if (strcmp(name, "wc") == 0) {
        return sh_builtin_wc(shell, stage, input, output, cap, out_len);
    }
    if (strcmp(name, "sort") == 0) {
        return sh_builtin_sort(shell, stage, input, output, cap, out_len);
    }
    if (strcmp(name, "head") == 0) {
        return sh_builtin_head(shell, stage, input, output, cap, out_len);
    }
    if (strcmp(name, "tail") == 0) {
        return sh_builtin_tail(shell, stage, input, output, cap, out_len);
    }
    if (strcmp(name, "env") == 0) {
        return sh_builtin_env(shell, stage, input, output, cap, out_len);
    }
    if (strcmp(name, "set") == 0) {
        return sh_builtin_set(shell, stage, input, output, cap, out_len);
    }
    if (strcmp(name, "exit") == 0) {
        return sh_builtin_exit(shell, stage, input, output, cap, out_len);
    }
    return sh_builtin_unknown(shell, stage, input, output, cap, out_len);
}

static int sh_run_statement(Shell *shell, const Statement *statement)
{
    char stages[MAX_STAGES][MAX_LINE];
    int stage_count = sh_split_stages(statement->raw, stages, MAX_STAGES);
    char buffer[MAX_PIPE_BUF];
    char next[MAX_PIPE_BUF];
    int length = 0;
    int exit_code = 0;
    int i;

    buffer[0] = '\0';
    if (stage_count > 1) {
        shell->stats.pipes++;
    }
    for (i = 0; i < stage_count; i++) {
        Stage stage;
        int out_len = 0;
        int code;

        sh_tokenize(stages[i], &stage);
        if (stage.has_input) {
            ShellFile *file = fs_find(&shell->fs, stage.input_file);
            if (file == NULL) {
                printf("    sh: %s: no such file\n", stage.input_file);
                shell->stats.errors++;
                return 1;
            }
            sh_copy(buffer, MAX_PIPE_BUF, file->content);
            length = (int)strlen(buffer);
        }
        if (stage.has_output) {
            shell->stats.redirections++;
        }
        code = sh_run_stage(shell, &stage, buffer, next, MAX_PIPE_BUF, &out_len);
        exit_code = code;
        shell->stats.stages_run++;
        shell->stats.bytes_in += length;
        shell->stats.bytes_out += out_len;
        printf("    stage %d: %s -> in=%d out=%d exit=%d\n", i + 1, stage.argv[0],
               length, out_len, code);
        if (i + 1 < stage_count) {
            sh_copy(buffer, MAX_PIPE_BUF, next);
            length = out_len;
        } else {
            if (stage.has_output) {
                fs_write(&shell->fs, stage.output_file, next, stage.append_output);
                printf("    redirected %d bytes into %s\n", out_len, stage.output_file);
            } else {
                printf("%s", next);
            }
        }
    }
    return exit_code;
}

/* ------------------------------------------------------------------ */
/* main                                                               */
/* ------------------------------------------------------------------ */

int main(void)
{
    static const char *const SCRIPT[15] = {
        "echo hello world",
        "set NAME=vitro",
        "echo hello $NAME",
        "ls",
        "cat notes.txt",
        "echo 'single quoted text'",
        "echo \"double quoted $NAME\"",
        "cat notes.txt | wc",
        "cat notes.txt | grep alpha",
        "cat notes.txt | sort",
        "cat notes.txt | head 2",
        "cat notes.txt | tail 1",
        "echo redirected > out.txt",
        "cat out.txt",
        "nosuchcommand"
    };
    Shell shell;
    Statement statements[MAX_STATEMENTS];
    int count;
    int i;
    int j;

    memset(&shell, 0, sizeof(Shell));
    fs_write(&shell.fs, "notes.txt", "alpha line\nbeta line\ngamma line\n", 0);
    fs_write(&shell.fs, "data.txt", "one\ntwo\nthree\n", 0);
    env_set(&shell.env, "HOME", "/tmp");
    env_set(&shell.env, "SHELL", "vitro-sh");

    printf("=== shell start ===\n");
    printf("  files=%d variables=%d\n", shell.fs.count, shell.env.count);
    printf("  builtin commands: echo ls cat grep wc sort head tail env set exit\n");

    printf("=== fifteen commands ===\n");
    for (i = 0; i < 15; i++) {
        int exit_code;
        printf("  [%2d] %s\n", i + 1, SCRIPT[i]);
        count = sh_split_statements(SCRIPT[i], statements, MAX_STATEMENTS);
        for (j = 0; j < count; j++) {
            exit_code = sh_run_statement(&shell, &statements[j]);
            shell.stats.executed++;
            if (exit_code != 0) {
                shell.stats.errors++;
            }
            printf("    exit_code=%d\n", exit_code);
        }
    }

    printf("=== statistics ===\n");
    printf("  executed=%d stages=%d pipes=%d redirections=%d errors=%d\n",
           shell.stats.executed, shell.stats.stages_run, shell.stats.pipes,
           shell.stats.redirections, shell.stats.errors);
    printf("  bytes_in=%d bytes_out=%d\n", shell.stats.bytes_in, shell.stats.bytes_out);

    printf("=== file system state ===\n");
    fs_list(&shell.fs);
    fs_print_state(&shell.fs);

    printf("=== variables ===\n");
    env_print(&shell.env);
    printf("=== done ===\n");
    return 0;
}
