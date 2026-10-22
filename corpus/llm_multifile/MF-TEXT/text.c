#include "text.h"
#include <stdio.h>
#include <string.h>

void text_init(TextBuffer *buf)
{
    int i;

    if (buf == NULL) {
        return;
    }
    for (i = 0; i < TEXT_MAX_LINES; i++) {
        buf->lines[i][0] = '\0';
    }
    buf->line_count = 0;
    buf->cur_line = 0;
    buf->cur_col = 0;
    buf->edits = 0;
}

int text_insert_line(TextBuffer *buf, int index, const char *content)
{
    int i;
    size_t n;

    if (buf == NULL || content == NULL) {
        return TEXT_ERR_NULL;
    }
    if (index < 0 || index > buf->line_count) {
        return TEXT_ERR_BOUNDS;
    }
    if (buf->line_count >= TEXT_MAX_LINES) {
        return TEXT_ERR_FULL;
    }
    for (i = buf->line_count; i > index; i--) {
        memcpy(buf->lines[i], buf->lines[i - 1], TEXT_MAX_COLS);
    }
    n = strlen(content);
    if (n > TEXT_MAX_COLS - 1) {
        n = TEXT_MAX_COLS - 1;
    }
    memcpy(buf->lines[index], content, n);
    buf->lines[index][n] = '\0';
    buf->line_count++;
    buf->edits++;
    return TEXT_OK;
}

int text_delete_line(TextBuffer *buf, int index)
{
    int i;

    if (buf == NULL) {
        return TEXT_ERR_NULL;
    }
    if (index < 0 || index >= buf->line_count) {
        return TEXT_ERR_BOUNDS;
    }
    for (i = index; i < buf->line_count - 1; i++) {
        memcpy(buf->lines[i], buf->lines[i + 1], TEXT_MAX_COLS);
    }
    buf->line_count--;
    buf->lines[buf->line_count][0] = '\0';
    if (buf->cur_line >= buf->line_count) {
        buf->cur_line = buf->line_count - 1;
    }
    if (buf->cur_line < 0) {
        buf->cur_line = 0;
    }
    buf->edits++;
    return TEXT_OK;
}

int text_insert_char(TextBuffer *buf, int line, int col, char c)
{
    size_t len;
    int i;

    if (buf == NULL) {
        return TEXT_ERR_NULL;
    }
    if (line < 0 || line >= buf->line_count) {
        return TEXT_ERR_BOUNDS;
    }
    len = strlen(buf->lines[line]);
    if (col < 0 || (size_t)col > len) {
        return TEXT_ERR_BOUNDS;
    }
    if (len + 1 >= TEXT_MAX_COLS) {
        return TEXT_ERR_FULL;
    }
    for (i = (int)len; i > col; i--) {
        buf->lines[line][i] = buf->lines[line][i - 1];
    }
    buf->lines[line][col] = c;
    buf->lines[line][len + 1] = '\0';
    buf->edits++;
    return TEXT_OK;
}

int text_delete_char(TextBuffer *buf, int line, int col, char *removed)
{
    size_t len;
    int i;

    if (buf == NULL) {
        return TEXT_ERR_NULL;
    }
    if (line < 0 || line >= buf->line_count) {
        return TEXT_ERR_BOUNDS;
    }
    len = strlen(buf->lines[line]);
    if (col < 0 || (size_t)col >= len) {
        return TEXT_ERR_BOUNDS;
    }
    if (removed != NULL) {
        *removed = buf->lines[line][col];
    }
    for (i = col; i < (int)len - 1; i++) {
        buf->lines[line][i] = buf->lines[line][i + 1];
    }
    buf->lines[line][len - 1] = '\0';
    buf->edits++;
    return TEXT_OK;
}

int text_move_cursor(TextBuffer *buf, int dline, int dcol)
{
    size_t len;

    if (buf == NULL) {
        return TEXT_ERR_NULL;
    }
    if (buf->line_count == 0) {
        return TEXT_ERR_BOUNDS;
    }
    buf->cur_line += dline;
    if (buf->cur_line < 0) {
        buf->cur_line = 0;
    }
    if (buf->cur_line >= buf->line_count) {
        buf->cur_line = buf->line_count - 1;
    }
    len = strlen(buf->lines[buf->cur_line]);
    buf->cur_col += dcol;
    if (buf->cur_col < 0) {
        buf->cur_col = 0;
    }
    if ((size_t)buf->cur_col > len) {
        buf->cur_col = (int)len;
    }
    return TEXT_OK;
}

int text_line_count(const TextBuffer *buf)
{
    if (buf == NULL) {
        return TEXT_ERR_NULL;
    }
    return buf->line_count;
}

int text_get_line(const TextBuffer *buf, int index, char *out, size_t cap)
{
    size_t n;

    if (buf == NULL || out == NULL || cap == 0) {
        return TEXT_ERR_NULL;
    }
    if (index < 0 || index >= buf->line_count) {
        return TEXT_ERR_BOUNDS;
    }
    n = strlen(buf->lines[index]);
    if (n + 1 > cap) {
        return TEXT_ERR_BOUNDS;
    }
    memcpy(out, buf->lines[index], n + 1);
    return TEXT_OK;
}

void text_print(const TextBuffer *buf)
{
    int i;

    if (buf == NULL) {
        return;
    }
    for (i = 0; i < buf->line_count; i++) {
        printf("  %2d | %s\n", i, buf->lines[i]);
    }
    printf("  cursor=(%d,%d) lines=%d edits=%d\n",
           buf->cur_line, buf->cur_col, buf->line_count, buf->edits);
}

int undo_push(UndoStack *stack, int type, int line, int col, const char *saved)
{
    TextUndo *entry;

    if (stack == NULL) {
        return TEXT_ERR_NULL;
    }
    if (stack->top >= TEXT_UNDO_MAX) {
        return TEXT_ERR_FULL;
    }
    entry = &stack->items[stack->top];
    entry->type = type;
    entry->line = line;
    entry->col = col;
    entry->saved[0] = '\0';
    if (saved != NULL) {
        size_t n = strlen(saved);
        if (n > TEXT_MAX_COLS - 1) {
            n = TEXT_MAX_COLS - 1;
        }
        memcpy(entry->saved, saved, n);
        entry->saved[n] = '\0';
    }
    stack->top++;
    return TEXT_OK;
}

int undo_apply(TextBuffer *buf, UndoStack *stack)
{
    TextUndo entry;
    int rc;

    if (buf == NULL || stack == NULL) {
        return TEXT_ERR_NULL;
    }
    if (stack->top <= 0) {
        return TEXT_ERR_BOUNDS;
    }
    stack->top--;
    entry = stack->items[stack->top];
    switch (entry.type) {
        case UNDO_DELETE_CHAR:
            rc = text_insert_char(buf, entry.line, entry.col, entry.saved[0]);
            break;
        case UNDO_INSERT_CHAR:
            rc = text_delete_char(buf, entry.line, entry.col, NULL);
            break;
        case UNDO_DELETE_LINE:
            rc = text_insert_line(buf, entry.line, entry.saved);
            break;
        case UNDO_INSERT_LINE:
            rc = text_delete_line(buf, entry.line);
            break;
        default:
            rc = TEXT_ERR_BOUNDS;
            break;
    }
    return rc;
}

int undo_depth(const UndoStack *stack)
{
    if (stack == NULL) {
        return TEXT_ERR_NULL;
    }
    return stack->top;
}
