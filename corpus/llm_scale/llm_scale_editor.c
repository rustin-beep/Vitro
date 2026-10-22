// @category: llm_scale
// 规模压力面：行缓冲编辑器：插入/删除/光标 + 撤销重做双栈 + 查找替换 + 宏录制
// 来源：LLM 千行语料 HUGE-EDITOR（1279 行，2026-10-21 入库；clang golden 由 clang_direct 现场生成）
// 注：本档 member_accesses 上限 400（#236 分档），见 scripts/perf_budget/rules.json
/*
 * HUGE-EDITOR -- a line oriented text editor engine in one C23 file.
 *
 * The editor keeps a fixed 64 line by 128 column buffer and offers:
 *
 *   - line insertion and deletion
 *   - single character insertion and deletion
 *   - cursor movement (up, down, left, right, home, end) that never leaves
 *     the buffer
 *   - a command parser that splits a command line by hand with strspn and
 *     strcspn instead of a tokenizer library
 *   - an undo and a redo stack, each 32 entries deep
 *   - fixed string find and replace, both "first occurrence" and "all"
 *   - macros: a named batch of commands that can be recorded and replayed
 *
 * The demo drives the editor with a fixed script of 40 commands, dumps the
 * whole document with line numbers every 8 commands, and finally reports the
 * command, undo and replace counters.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

/* ------------------------------------------------------------------ */
/* constants                                                          */
/* ------------------------------------------------------------------ */

#define ED_MAX_LINES 64
#define ED_MAX_COLS 128
#define ED_MAX_UNDO 32
#define ED_MAX_REDO 32
#define ED_MAX_MACROS 8
#define ED_MAX_MACRO_CMDS 32
#define ED_NAME_LEN 32
#define ED_CMD_LEN 128
#define ED_TEXT_LEN 128

#define ED_OK 0
#define ED_ERR_RANGE (-1)
#define ED_ERR_FULL (-2)
#define ED_ERR_ARG (-3)
#define ED_ERR_UNDO (-4)
#define ED_ERR_REDO (-5)
#define ED_ERR_PARSE (-6)

#define ACT_INSERT_LINE 1
#define ACT_DELETE_LINE 2
#define ACT_INSERT_CHAR 3
#define ACT_DELETE_CHAR 4
#define ACT_SET_LINE 5
#define ACT_REPLACE 6
#define ACT_MOVE 7

/* ------------------------------------------------------------------ */
/* types                                                              */
/* ------------------------------------------------------------------ */

typedef struct {
    char lines[ED_MAX_LINES][ED_MAX_COLS];
    int line_count;
    int cur_line;
    int cur_col;
    long edits;
} Editor;

typedef struct {
    int type;
    int line;
    int col;
    int new_line;
    int new_col;
    char text[ED_TEXT_LEN];
    char after[ED_TEXT_LEN];
} EditRecord;

typedef struct {
    EditRecord items[ED_MAX_UNDO];
    int count;
} UndoStack;

typedef struct {
    EditRecord items[ED_MAX_REDO];
    int count;
} RedoStack;

typedef struct {
    char name[ED_NAME_LEN];
    char commands[ED_MAX_MACRO_CMDS][ED_CMD_LEN];
    int count;
} Macro;

typedef struct {
    Macro macros[ED_MAX_MACROS];
    int count;
    int recording;
    int record_index;
} MacroTable;

typedef struct {
    long commands;
    long executed;
    long undos;
    long redos;
    long replaces;
    long finds;
    long errors;
    long macros_replayed;
} EditorStats;

typedef struct {
    int found;
    int line;
    int col;
} FindResult;

/* undo_push is used by the replace helpers below its own definition */
static int undo_push(UndoStack *stack, int type, int line, int col,
                     int new_line, int new_col, const char *text, const char *after);

/* ------------------------------------------------------------------ */
/* tiny string helpers                                                */
/* ------------------------------------------------------------------ */

static int str_copy(char *dst, size_t cap, const char *src)
{
    size_t n;

    if (dst == NULL || src == NULL || cap == 0) {
        return ED_ERR_ARG;
    }
    n = strlen(src);
    if (n + 1 > cap) {
        n = cap - 1;
    }
    memcpy(dst, src, n);
    dst[n] = '\0';
    return ED_OK;
}

static int str_copy_n(char *dst, size_t cap, const char *src, size_t n)
{
    if (dst == NULL || src == NULL || cap == 0) {
        return ED_ERR_ARG;
    }
    if (n + 1 > cap) {
        n = cap - 1;
    }
    memcpy(dst, src, n);
    dst[n] = '\0';
    return ED_OK;
}

static void str_trim(char *s)
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

static int str_equal(const char *a, const char *b)
{
    if (a == NULL || b == NULL) {
        return 0;
    }
    return strcmp(a, b) == 0 ? 1 : 0;
}

static int str_starts_with(const char *s, const char *prefix)
{
    size_t n;

    if (s == NULL || prefix == NULL) {
        return 0;
    }
    n = strlen(prefix);
    if (n == 0) {
        return 1;
    }
    if (strlen(s) < n) {
        return 0;
    }
    return strncmp(s, prefix, n) == 0 ? 1 : 0;
}

/* ------------------------------------------------------------------ */
/* editor buffer primitives                                           */
/* ------------------------------------------------------------------ */

static void editor_init(Editor *editor)
{
    int i;

    for (i = 0; i < ED_MAX_LINES; i++) {
        editor->lines[i][0] = '\0';
    }
    editor->line_count = 0;
    editor->cur_line = 0;
    editor->cur_col = 0;
    editor->edits = 0;
}

static int editor_line_length(const Editor *editor, int line)
{
    if (editor == NULL || line < 0 || line >= editor->line_count) {
        return 0;
    }
    return (int)strlen(editor->lines[line]);
}

static int editor_get_line(const Editor *editor, int line, char *out, size_t cap)
{
    size_t n;

    if (editor == NULL || out == NULL || cap == 0) {
        return ED_ERR_ARG;
    }
    if (line < 0 || line >= editor->line_count) {
        return ED_ERR_RANGE;
    }
    n = strlen(editor->lines[line]);
    if (n + 1 > cap) {
        return ED_ERR_FULL;
    }
    memcpy(out, editor->lines[line], n + 1);
    return ED_OK;
}

static int editor_set_line(Editor *editor, int line, const char *text)
{
    size_t n;

    if (editor == NULL || text == NULL) {
        return ED_ERR_ARG;
    }
    if (line < 0 || line >= editor->line_count) {
        return ED_ERR_RANGE;
    }
    n = strlen(text);
    if (n + 1 > ED_MAX_COLS) {
        return ED_ERR_FULL;
    }
    memcpy(editor->lines[line], text, n + 1);
    editor->edits++;
    return ED_OK;
}

static int editor_insert_line(Editor *editor, int index, const char *text)
{
    int i;
    size_t n;

    if (editor == NULL || text == NULL) {
        return ED_ERR_ARG;
    }
    if (index < 0 || index > editor->line_count) {
        return ED_ERR_RANGE;
    }
    if (editor->line_count >= ED_MAX_LINES) {
        return ED_ERR_FULL;
    }
    for (i = editor->line_count; i > index; i--) {
        memcpy(editor->lines[i], editor->lines[i - 1], ED_MAX_COLS);
    }
    n = strlen(text);
    if (n > ED_MAX_COLS - 1) {
        n = ED_MAX_COLS - 1;
    }
    memcpy(editor->lines[index], text, n);
    editor->lines[index][n] = '\0';
    editor->line_count++;
    editor->edits++;
    return ED_OK;
}

static int editor_delete_line(Editor *editor, int index, char *saved)
{
    int i;

    if (editor == NULL) {
        return ED_ERR_ARG;
    }
    if (index < 0 || index >= editor->line_count) {
        return ED_ERR_RANGE;
    }
    if (saved != NULL) {
        str_copy(saved, ED_TEXT_LEN, editor->lines[index]);
    }
    for (i = index; i < editor->line_count - 1; i++) {
        memcpy(editor->lines[i], editor->lines[i + 1], ED_MAX_COLS);
    }
    editor->line_count--;
    editor->lines[editor->line_count][0] = '\0';
    if (editor->cur_line >= editor->line_count) {
        editor->cur_line = editor->line_count - 1;
    }
    if (editor->cur_line < 0) {
        editor->cur_line = 0;
    }
    if (editor->cur_col > editor_line_length(editor, editor->cur_line)) {
        editor->cur_col = editor_line_length(editor, editor->cur_line);
    }
    editor->edits++;
    return ED_OK;
}

static int editor_insert_char(Editor *editor, int line, int col, char c)
{
    int len;
    int i;

    if (editor == NULL) {
        return ED_ERR_ARG;
    }
    if (line < 0 || line >= editor->line_count) {
        return ED_ERR_RANGE;
    }
    len = editor_line_length(editor, line);
    if (col < 0 || col > len) {
        return ED_ERR_RANGE;
    }
    if (len + 1 >= ED_MAX_COLS) {
        return ED_ERR_FULL;
    }
    for (i = len; i > col; i--) {
        editor->lines[line][i] = editor->lines[line][i - 1];
    }
    editor->lines[line][col] = c;
    editor->lines[line][len + 1] = '\0';
    editor->edits++;
    return ED_OK;
}

static int editor_delete_char(Editor *editor, int line, int col, char *removed)
{
    int len;
    int i;

    if (editor == NULL) {
        return ED_ERR_ARG;
    }
    if (line < 0 || line >= editor->line_count) {
        return ED_ERR_RANGE;
    }
    len = editor_line_length(editor, line);
    if (col < 0 || col >= len) {
        return ED_ERR_RANGE;
    }
    if (removed != NULL) {
        *removed = editor->lines[line][col];
    }
    for (i = col; i < len - 1; i++) {
        editor->lines[line][i] = editor->lines[line][i + 1];
    }
    editor->lines[line][len - 1] = '\0';
    editor->edits++;
    return ED_OK;
}

static int editor_move_cursor(Editor *editor, int dline, int dcol)
{
    int len;

    if (editor == NULL) {
        return ED_ERR_ARG;
    }
    if (editor->line_count == 0) {
        editor->cur_line = 0;
        editor->cur_col = 0;
        return ED_OK;
    }
    editor->cur_line += dline;
    if (editor->cur_line < 0) {
        editor->cur_line = 0;
    }
    if (editor->cur_line >= editor->line_count) {
        editor->cur_line = editor->line_count - 1;
    }
    len = editor_line_length(editor, editor->cur_line);
    editor->cur_col += dcol;
    if (editor->cur_col < 0) {
        editor->cur_col = 0;
    }
    if (editor->cur_col > len) {
        editor->cur_col = len;
    }
    return ED_OK;
}

static int editor_move_home(Editor *editor)
{
    if (editor == NULL) {
        return ED_ERR_ARG;
    }
    editor->cur_col = 0;
    return ED_OK;
}

static int editor_move_end(Editor *editor)
{
    if (editor == NULL) {
        return ED_ERR_ARG;
    }
    editor->cur_col = editor_line_length(editor, editor->cur_line);
    return ED_OK;
}

static void editor_print(const Editor *editor)
{
    int i;

    if (editor == NULL) {
        return;
    }
    for (i = 0; i < editor->line_count; i++) {
        printf("  %2d | %s\n", i, editor->lines[i]);
    }
    printf("  cursor=(%d,%d) lines=%d edits=%ld\n",
           editor->cur_line, editor->cur_col, editor->line_count, editor->edits);
}

/* ------------------------------------------------------------------ */
/* find and replace                                                   */
/* ------------------------------------------------------------------ */

static int replace_in_line(const char *line, const char *needle, const char *repl,
                           char *out, size_t cap, int *count)
{
    size_t nlen;
    size_t rlen;
    size_t oi;
    const char *p;

    if (line == NULL || needle == NULL || repl == NULL || out == NULL) {
        return ED_ERR_ARG;
    }
    nlen = strlen(needle);
    rlen = strlen(repl);
    oi = 0;
    *count = 0;
    if (nlen == 0) {
        return str_copy(out, cap, line);
    }
    p = line;
    while (*p != '\0') {
        if (strncmp(p, needle, nlen) == 0) {
            if (oi + rlen + 1 > cap) {
                return ED_ERR_FULL;
            }
            memcpy(out + oi, repl, rlen);
            oi += rlen;
            p += nlen;
            (*count)++;
            continue;
        }
        if (oi + 2 > cap) {
            return ED_ERR_FULL;
        }
        out[oi] = *p;
        oi++;
        p++;
    }
    out[oi] = '\0';
    return ED_OK;
}

static int editor_find(const Editor *editor, const char *needle, int from_line,
                       int from_col, FindResult *out)
{
    int line;
    int col;

    if (editor == NULL || needle == NULL || out == NULL) {
        return ED_ERR_ARG;
    }
    if (needle[0] == '\0') {
        return ED_ERR_ARG;
    }
    out->found = 0;
    out->line = -1;
    out->col = -1;
    for (line = (from_line < 0) ? 0 : from_line; line < editor->line_count; line++) {
        const char *hay = editor->lines[line];
        int start = 0;
        if (line == from_line && from_col > 0) {
            start = from_col;
        }
        for (col = start; hay[col] != '\0'; col++) {
            if (strncmp(hay + col, needle, strlen(needle)) == 0) {
                out->found = 1;
                out->line = line;
                out->col = col;
                return ED_OK;
            }
        }
    }
    return ED_ERR_RANGE;
}

static int editor_replace_first(Editor *editor, const char *needle, const char *repl,
                                char *old_line, char *new_line)
{
    FindResult hit;
    char buffer[ED_MAX_COLS];
    int count;
    int rc;

    if (editor == NULL || needle == NULL || repl == NULL) {
        return ED_ERR_ARG;
    }
    rc = editor_find(editor, needle, 0, 0, &hit);
    if (rc != ED_OK || !hit.found) {
        return ED_ERR_RANGE;
    }
    rc = replace_in_line(editor->lines[hit.line], needle, repl, buffer, sizeof buffer, &count);
    if (rc != ED_OK) {
        return rc;
    }
    if (old_line != NULL) {
        str_copy(old_line, ED_TEXT_LEN, editor->lines[hit.line]);
    }
    if (new_line != NULL) {
        str_copy(new_line, ED_TEXT_LEN, buffer);
    }
    editor_set_line(editor, hit.line, buffer);
    return count;
}

static int editor_replace_all(Editor *editor, const char *needle, const char *repl,
                               UndoStack *undo, int *total, int *touched_lines)
{
    int line;
    int count;
    int rc;
    char buffer[ED_MAX_COLS];

    if (editor == NULL || needle == NULL || repl == NULL || total == NULL) {
        return ED_ERR_ARG;
    }
    *total = 0;
    if (touched_lines != NULL) {
        *touched_lines = 0;
    }
    for (line = 0; line < editor->line_count; line++) {
        char old_line[ED_TEXT_LEN];
        rc = replace_in_line(editor->lines[line], needle, repl, buffer, sizeof buffer, &count);
        if (rc != ED_OK) {
            return rc;
        }
        if (count == 0) {
            continue;
        }
        str_copy(old_line, ED_TEXT_LEN, editor->lines[line]);
        editor_set_line(editor, line, buffer);
        if (undo != NULL) {
            undo_push(undo, ACT_REPLACE, line, 0, 0, 0, old_line, buffer);
        }
        *total += count;
        if (touched_lines != NULL) {
            (*touched_lines)++;
        }
    }
    return ED_OK;
}

/* ------------------------------------------------------------------ */
/* undo and redo stacks                                               */
/* ------------------------------------------------------------------ */

static void undo_init(UndoStack *stack)
{
    stack->count = 0;
}

static void redo_init(RedoStack *stack)
{
    stack->count = 0;
}

static int undo_push(UndoStack *stack, int type, int line, int col,
                     int new_line, int new_col, const char *text, const char *after)
{
    EditRecord *rec;

    if (stack == NULL) {
        return ED_ERR_ARG;
    }
    if (stack->count >= ED_MAX_UNDO) {
        return ED_ERR_FULL;
    }
    rec = &stack->items[stack->count];
    rec->type = type;
    rec->line = line;
    rec->col = col;
    rec->new_line = new_line;
    rec->new_col = new_col;
    rec->text[0] = '\0';
    rec->after[0] = '\0';
    if (text != NULL) {
        str_copy(rec->text, ED_TEXT_LEN, text);
    }
    if (after != NULL) {
        str_copy(rec->after, ED_TEXT_LEN, after);
    }
    stack->count++;
    return ED_OK;
}

static int redo_push(RedoStack *stack, const EditRecord *rec)
{
    if (stack == NULL || rec == NULL) {
        return ED_ERR_ARG;
    }
    if (stack->count >= ED_MAX_REDO) {
        return ED_ERR_FULL;
    }
    stack->items[stack->count] = *rec;
    stack->count++;
    return ED_OK;
}

static int undo_pop(UndoStack *stack, EditRecord *out)
{
    if (stack == NULL || out == NULL) {
        return ED_ERR_ARG;
    }
    if (stack->count <= 0) {
        return ED_ERR_UNDO;
    }
    stack->count--;
    *out = stack->items[stack->count];
    return ED_OK;
}

static int redo_pop(RedoStack *stack, EditRecord *out)
{
    if (stack == NULL || out == NULL) {
        return ED_ERR_ARG;
    }
    if (stack->count <= 0) {
        return ED_ERR_REDO;
    }
    stack->count--;
    *out = stack->items[stack->count];
    return ED_OK;
}

static int action_revert(Editor *editor, const EditRecord *rec)
{
    if (editor == NULL || rec == NULL) {
        return ED_ERR_ARG;
    }
    switch (rec->type) {
        case ACT_INSERT_LINE:
            return editor_delete_line(editor, rec->line, NULL);
        case ACT_DELETE_LINE:
            return editor_insert_line(editor, rec->line, rec->text);
        case ACT_INSERT_CHAR:
            return editor_delete_char(editor, rec->line, rec->col, NULL);
        case ACT_DELETE_CHAR:
            return editor_insert_char(editor, rec->line, rec->col, rec->text[0]);
        case ACT_SET_LINE:
        case ACT_REPLACE:
            return editor_set_line(editor, rec->line, rec->text);
        case ACT_MOVE:
            editor->cur_line = rec->line;
            editor->cur_col = rec->col;
            return ED_OK;
        default:
            return ED_ERR_ARG;
    }
}

static int action_apply(Editor *editor, const EditRecord *rec)
{
    if (editor == NULL || rec == NULL) {
        return ED_ERR_ARG;
    }
    switch (rec->type) {
        case ACT_INSERT_LINE:
            return editor_insert_line(editor, rec->line, rec->text);
        case ACT_DELETE_LINE:
            return editor_delete_line(editor, rec->line, NULL);
        case ACT_INSERT_CHAR:
            return editor_insert_char(editor, rec->line, rec->col, rec->text[0]);
        case ACT_DELETE_CHAR:
            return editor_delete_char(editor, rec->line, rec->col, NULL);
        case ACT_SET_LINE:
        case ACT_REPLACE:
            return editor_set_line(editor, rec->line, rec->after);
        case ACT_MOVE:
            editor->cur_line = rec->new_line;
            editor->cur_col = rec->new_col;
            return ED_OK;
        default:
            return ED_ERR_ARG;
    }
}

static int undo_step(Editor *editor, UndoStack *undo, RedoStack *redo, EditorStats *stats)
{
    EditRecord rec;
    int rc;

    if (editor == NULL || undo == NULL || redo == NULL) {
        return ED_ERR_ARG;
    }
    rc = undo_pop(undo, &rec);
    if (rc != ED_OK) {
        return rc;
    }
    rc = action_revert(editor, &rec);
    if (rc != ED_OK) {
        undo_push(undo, rec.type, rec.line, rec.col, rec.new_line, rec.new_col, rec.text, rec.after);
        return rc;
    }
    redo_push(redo, &rec);
    if (stats != NULL) {
        stats->undos++;
    }
    return ED_OK;
}

static int redo_step(Editor *editor, UndoStack *undo, RedoStack *redo, EditorStats *stats)
{
    EditRecord rec;
    int rc;

    if (editor == NULL || undo == NULL || redo == NULL) {
        return ED_ERR_ARG;
    }
    rc = redo_pop(redo, &rec);
    if (rc != ED_OK) {
        return rc;
    }
    rc = action_apply(editor, &rec);
    if (rc != ED_OK) {
        redo_push(redo, &rec);
        return rc;
    }
    undo_push(undo, rec.type, rec.line, rec.col, rec.new_line, rec.new_col, rec.text, rec.after);
    if (stats != NULL) {
        stats->redos++;
    }
    return ED_OK;
}

/* ------------------------------------------------------------------ */
/* command tokenizer built on strspn and strcspn                       */
/* ------------------------------------------------------------------ */

static int next_token(const char *s, int *pos, char *out, size_t cap)
{
    size_t start;
    size_t len;

    if (s == NULL || pos == NULL || out == NULL || cap == 0) {
        return 0;
    }
    start = (size_t)*pos;
    start += strspn(s + start, " \t");
    if (s[start] == '\0') {
        *pos = (int)start;
        return 0;
    }
    len = strcspn(s + start, " \t");
    if (len > cap - 1) {
        len = cap - 1;
    }
    str_copy_n(out, cap, s + start, len);
    *pos = (int)(start + len);
    return 1;
}

static int rest_of_line(const char *s, int pos, char *out, size_t cap)
{
    if (s == NULL || out == NULL) {
        return ED_ERR_ARG;
    }
    while (s[pos] == ' ' || s[pos] == '\t') {
        pos++;
    }
    return str_copy(out, cap, s + pos);
}

static int parse_int_token(const char *token, int *out)
{
    int value = 0;
    int i;

    if (token == NULL || out == NULL) {
        return 0;
    }
    if (token[0] == '\0') {
        return 0;
    }
    for (i = 0; token[i] != '\0'; i++) {
        if (!isdigit((unsigned char)token[i])) {
            return 0;
        }
        value = value * 10 + (token[i] - '0');
    }
    *out = value;
    return 1;
}

/* ------------------------------------------------------------------ */
/* macro table                                                        */
/* ------------------------------------------------------------------ */

static void macro_table_init(MacroTable *table)
{
    int i;
    int j;

    for (i = 0; i < ED_MAX_MACROS; i++) {
        table->macros[i].name[0] = '\0';
        table->macros[i].count = 0;
        for (j = 0; j < ED_MAX_MACRO_CMDS; j++) {
            table->macros[i].commands[j][0] = '\0';
        }
    }
    table->count = 0;
    table->recording = 0;
    table->record_index = -1;
}

static Macro *macro_find(MacroTable *table, const char *name)
{
    int i;

    if (table == NULL || name == NULL) {
        return NULL;
    }
    for (i = 0; i < table->count; i++) {
        if (str_equal(table->macros[i].name, name)) {
            return &table->macros[i];
        }
    }
    return NULL;
}

static int macro_start(MacroTable *table, const char *name)
{
    Macro *macro;

    if (table == NULL || name == NULL || name[0] == '\0') {
        return ED_ERR_ARG;
    }
    macro = macro_find(table, name);
    if (macro == NULL) {
        if (table->count >= ED_MAX_MACROS) {
            return ED_ERR_FULL;
        }
        macro = &table->macros[table->count];
        table->count++;
    }
    str_copy(macro->name, ED_NAME_LEN, name);
    macro->count = 0;
    table->record_index = (int)(macro - table->macros);
    table->recording = 1;
    return ED_OK;
}

static int macro_stop(MacroTable *table)
{
    if (table == NULL) {
        return ED_ERR_ARG;
    }
    if (!table->recording) {
        return ED_ERR_RANGE;
    }
    table->recording = 0;
    table->record_index = -1;
    return ED_OK;
}

static int macro_record(MacroTable *table, const char *cmd)
{
    Macro *macro;

    if (table == NULL || cmd == NULL) {
        return ED_ERR_ARG;
    }
    if (!table->recording || table->record_index < 0) {
        return ED_OK;
    }
    macro = &table->macros[table->record_index];
    if (macro->count >= ED_MAX_MACRO_CMDS) {
        return ED_ERR_FULL;
    }
    str_copy(macro->commands[macro->count], ED_CMD_LEN, cmd);
    macro->count++;
    return ED_OK;
}

/* ------------------------------------------------------------------ */
/* command execution                                                  */
/* ------------------------------------------------------------------ */

static int cmd_execute(Editor *editor, const char *cmd, UndoStack *undo, RedoStack *redo,
                        MacroTable *macros, EditorStats *stats, int depth)
{
    char raw[ED_CMD_LEN];
    char verb[ED_NAME_LEN];
    char token[ED_TEXT_LEN];
    char text[ED_TEXT_LEN];
    int pos;
    int rc;
    int number;

    if (editor == NULL || cmd == NULL) {
        return ED_ERR_ARG;
    }
    if (depth > 4) {
        return ED_ERR_RANGE;
    }
    str_copy(raw, sizeof raw, cmd);
    str_trim(raw);
    if (raw[0] == '\0') {
        return ED_OK;
    }
    if (stats != NULL) {
        stats->commands++;
    }
    pos = 0;
    if (!next_token(raw, &pos, verb, sizeof verb)) {
        return ED_OK;
    }
    if (macros != NULL && macros->recording && depth == 0 &&
        !str_equal(verb, "M") && !str_equal(verb, "E") && !str_starts_with(verb, "@")) {
        macro_record(macros, raw);
    }

    if (str_equal(verb, "i")) {
        if (!next_token(raw, &pos, token, sizeof token) || !parse_int_token(token, &number)) {
            return ED_ERR_PARSE;
        }
        rest_of_line(raw, pos, text, sizeof text);
        rc = editor_insert_line(editor, number, text);
        if (rc == ED_OK && undo != NULL) {
            undo_push(undo, ACT_INSERT_LINE, number, 0, 0, 0, text, NULL);
        }
        return rc;
    }
    if (str_equal(verb, "d")) {
        char removed[ED_TEXT_LEN];
        if (!next_token(raw, &pos, token, sizeof token) || !parse_int_token(token, &number)) {
            return ED_ERR_PARSE;
        }
        removed[0] = '\0';
        rc = editor_delete_line(editor, number, removed);
        if (rc == ED_OK && undo != NULL) {
            undo_push(undo, ACT_DELETE_LINE, number, 0, 0, 0, removed, NULL);
        }
        return rc;
    }
    if (str_equal(verb, "x")) {
        char col_token[ED_TEXT_LEN];
        char removed[2];
        int col;
        if (!next_token(raw, &pos, token, sizeof token) || !parse_int_token(token, &number)) {
            return ED_ERR_PARSE;
        }
        if (!next_token(raw, &pos, col_token, sizeof col_token) || !parse_int_token(col_token, &col)) {
            return ED_ERR_PARSE;
        }
        removed[0] = '\0';
        removed[1] = '\0';
        rc = editor_delete_char(editor, number, col, &removed[0]);
        if (rc == ED_OK && undo != NULL) {
            undo_push(undo, ACT_DELETE_CHAR, number, col, 0, 0, removed, NULL);
        }
        return rc;
    }
    if (str_equal(verb, "a")) {
        char col_token[ED_TEXT_LEN];
        char ch[4];
        int col;
        if (!next_token(raw, &pos, token, sizeof token) || !parse_int_token(token, &number)) {
            return ED_ERR_PARSE;
        }
        if (!next_token(raw, &pos, col_token, sizeof col_token) || !parse_int_token(col_token, &col)) {
            return ED_ERR_PARSE;
        }
        if (!next_token(raw, &pos, ch, sizeof ch)) {
            return ED_ERR_PARSE;
        }
        rc = editor_insert_char(editor, number, col, ch[0]);
        if (rc == ED_OK && undo != NULL) {
            undo_push(undo, ACT_INSERT_CHAR, number, col, 0, 0, ch, NULL);
        }
        return rc;
    }
    if (str_equal(verb, "s")) {
        char old_line[ED_TEXT_LEN];
        if (!next_token(raw, &pos, token, sizeof token) || !parse_int_token(token, &number)) {
            return ED_ERR_PARSE;
        }
        rest_of_line(raw, pos, text, sizeof text);
        old_line[0] = '\0';
        editor_get_line(editor, number, old_line, sizeof old_line);
        rc = editor_set_line(editor, number, text);
        if (rc == ED_OK && undo != NULL) {
            undo_push(undo, ACT_SET_LINE, number, 0, 0, 0, old_line, text);
        }
        return rc;
    }
    if (str_equal(verb, "m")) {
        int old_line;
        int old_col;
        if (!next_token(raw, &pos, token, sizeof token)) {
            return ED_ERR_PARSE;
        }
        old_line = editor->cur_line;
        old_col = editor->cur_col;
        if (str_equal(token, "up")) {
            editor_move_cursor(editor, -1, 0);
        } else if (str_equal(token, "down")) {
            editor_move_cursor(editor, 1, 0);
        } else if (str_equal(token, "left")) {
            editor_move_cursor(editor, 0, -1);
        } else if (str_equal(token, "right")) {
            editor_move_cursor(editor, 0, 1);
        } else if (str_equal(token, "home")) {
            editor_move_home(editor);
        } else if (str_equal(token, "end")) {
            editor_move_end(editor);
        } else {
            return ED_ERR_PARSE;
        }
        if (undo != NULL) {
            undo_push(undo, ACT_MOVE, old_line, old_col, editor->cur_line, editor->cur_col, NULL, NULL);
        }
        return ED_OK;
    }
    if (str_equal(verb, "f")) {
        FindResult hit;
        rest_of_line(raw, pos, text, sizeof text);
        rc = editor_find(editor, text, 0, 0, &hit);
        if (stats != NULL) {
            stats->finds++;
        }
        if (rc == ED_OK && hit.found) {
            printf("  find [%s] -> line %d col %d\n", text, hit.line, hit.col);
        } else {
            printf("  find [%s] -> not found\n", text);
        }
        return ED_OK;
    }
    if (str_equal(verb, "r") || str_equal(verb, "R")) {
        char needle[ED_TEXT_LEN];
        char repl[ED_TEXT_LEN];
        int total = 0;
        int touched = 0;
        if (!next_token(raw, &pos, needle, sizeof needle)) {
            return ED_ERR_PARSE;
        }
        rest_of_line(raw, pos, repl, sizeof repl);
        if (str_equal(verb, "R")) {
            char old_line[ED_TEXT_LEN];
            char new_line[ED_TEXT_LEN];
            old_line[0] = '\0';
            new_line[0] = '\0';
            rc = editor_replace_first(editor, needle, repl, old_line, new_line);
            total = (rc > 0) ? 1 : 0;
            touched = total;
            if (rc > 0 && undo != NULL) {
                undo_push(undo, ACT_REPLACE, 0, 0, 0, 0, old_line, new_line);
            }
            if (rc < 0) {
                rc = ED_OK;
            }
        } else {
            rc = editor_replace_all(editor, needle, repl, undo, &total, &touched);
        }
        if (stats != NULL) {
            stats->replaces += total;
        }
        printf("  replace [%s] -> [%s] hits=%d lines=%d\n", needle, repl, total, touched);
        return (rc == ED_OK) ? ED_OK : rc;
    }
    if (str_equal(verb, "u")) {
        return undo_step(editor, undo, redo, stats);
    }
    if (str_equal(verb, "v")) {
        return redo_step(editor, undo, redo, stats);
    }
    if (str_equal(verb, "M")) {
        if (!next_token(raw, &pos, token, sizeof token)) {
            return ED_ERR_PARSE;
        }
        rc = macro_start(macros, token);
        if (rc == ED_OK) {
            printf("  macro [%s] recording\n", token);
        }
        return rc;
    }
    if (str_equal(verb, "E")) {
        rc = macro_stop(macros);
        if (rc == ED_OK && macros != NULL && macros->record_index >= 0) {
            printf("  macro [%s] stopped with %d commands\n",
                   macros->macros[macros->record_index].name,
                   macros->macros[macros->record_index].count);
        }
        return rc;
    }
    if (str_equal(verb, "@")) {
        Macro *macro;
        if (!next_token(raw, &pos, token, sizeof token)) {
            return ED_ERR_PARSE;
        }
        macro = macro_find(macros, token);
        if (macro == NULL) {
            return ED_ERR_RANGE;
        }
        {
            int i;
            int commands = macro->count;
            char saved[ED_MAX_MACRO_CMDS][ED_CMD_LEN];
            for (i = 0; i < commands; i++) {
                str_copy(saved[i], ED_CMD_LEN, macro->commands[i]);
            }
            for (i = 0; i < commands; i++) {
                cmd_execute(editor, saved[i], undo, redo, macros, stats, depth + 1);
            }
        }
        if (stats != NULL) {
            stats->macros_replayed++;
        }
        printf("  macro [%s] replayed %d commands\n", token, macro->count);
        return ED_OK;
    }
    return ED_ERR_PARSE;
}

static int cmd_run_script(Editor *editor, const char *const *script, int count,
                          UndoStack *undo, RedoStack *redo, MacroTable *macros,
                          EditorStats *stats, int dump_every)
{
    int i;

    for (i = 0; i < count; i++) {
        int rc;
        printf("  cmd %2d: %s\n", i + 1, script[i]);
        rc = cmd_execute(editor, script[i], undo, redo, macros, stats, 0);
        if (rc != ED_OK) {
            if (stats != NULL) {
                stats->errors++;
            }
            printf("    -> error %d\n", rc);
        } else if (stats != NULL) {
            stats->executed++;
        }
        if (dump_every > 0 && ((i + 1) % dump_every) == 0) {
            printf("  --- dump after %d commands ---\n", i + 1);
            editor_print(editor);
        }
    }
    return count;
}

/* ------------------------------------------------------------------ */
/* main                                                               */
/* ------------------------------------------------------------------ */

int main(void)
{
    static const char *const SCRIPT[] = {
        "i 0 alpha line",
        "i 1 beta line",
        "i 2 gamma line",
        "i 3 delta line",
        "s 1 changed beta",
        "a 0 5 !",
        "x 2 0",
        "m down",
        "m end",
        "m up",
        "m home",
        "d 3",
        "i 3 restored delta",
        "f beta",
        "r beta BETA",
        "R gamma GAMMA",
        "u",
        "v",
        "u",
        "M demo",
        "i 4 recorded line",
        "i 5 another recorded line",
        "E",
        "@ demo",
        "s 0 first line again",
        "a 1 4 ?",
        "d 0",
        "i 0 top line",
        "m down",
        "m down",
        "x 2 1",
        "f line",
        "r line LINE",
        "u",
        "v",
        "s 5 tail",
        "d 6",
        "i 6 appended",
        "m up",
        "m home"
    };
    static const int SCRIPT_LEN = (int)(sizeof SCRIPT / sizeof SCRIPT[0]);

    Editor editor;
    UndoStack undo;
    RedoStack redo;
    MacroTable macros;
    EditorStats stats;
    int i;

    editor_init(&editor);
    undo_init(&undo);
    redo_init(&redo);
    macro_table_init(&macros);
    stats.commands = 0;
    stats.executed = 0;
    stats.undos = 0;
    stats.redos = 0;
    stats.replaces = 0;
    stats.finds = 0;
    stats.errors = 0;
    stats.macros_replayed = 0;

    printf("=== editor start ===\n");
    editor_print(&editor);

    printf("=== run %d commands ===\n", SCRIPT_LEN);
    cmd_run_script(&editor, SCRIPT, SCRIPT_LEN, &undo, &redo, &macros, &stats, 8);

    printf("=== final document ===\n");
    editor_print(&editor);

    printf("=== macros ===\n");
    for (i = 0; i < macros.count; i++) {
        int k;
        printf("  macro [%s] commands=%d\n", macros.macros[i].name, macros.macros[i].count);
        for (k = 0; k < macros.macros[i].count; k++) {
            printf("    %2d: %s\n", k + 1, macros.macros[i].commands[k]);
        }
    }

    printf("=== statistics ===\n");
    printf("  total_commands=%ld executed=%ld errors=%ld\n",
           stats.commands, stats.executed, stats.errors);
    printf("  undo_count=%ld redo_count=%ld undo_depth=%d redo_depth=%d\n",
           stats.undos, stats.redos, undo.count, redo.count);
    printf("  replace_count=%ld find_count=%ld macros_replayed=%ld\n",
           stats.replaces, stats.finds, stats.macros_replayed);
    printf("  final_lines=%d cursor=(%d,%d) edits=%ld\n",
           editor.line_count, editor.cur_line, editor.cur_col, editor.edits);
    return 0;
}
