#ifndef TEXT_H
#define TEXT_H

#include <stddef.h>

#define TEXT_MAX_LINES 64
#define TEXT_MAX_COLS  128
#define TEXT_UNDO_MAX  16

#define TEXT_OK          0
#define TEXT_ERR_NULL  (-1)
#define TEXT_ERR_BOUNDS (-2)
#define TEXT_ERR_FULL   (-3)

typedef struct {
    char lines[TEXT_MAX_LINES][TEXT_MAX_COLS];
    int line_count;
    int cur_line;
    int cur_col;
    int edits;
} TextBuffer;

#define UNDO_INSERT_CHAR 1
#define UNDO_DELETE_CHAR 2
#define UNDO_INSERT_LINE 3
#define UNDO_DELETE_LINE 4

typedef struct {
    int type;
    int line;
    int col;
    char saved[TEXT_MAX_COLS];
} TextUndo;

typedef struct {
    TextUndo items[TEXT_UNDO_MAX];
    int top;
} UndoStack;

void text_init(TextBuffer *buf);
int text_insert_line(TextBuffer *buf, int index, const char *content);
int text_delete_line(TextBuffer *buf, int index);
int text_insert_char(TextBuffer *buf, int line, int col, char c);
int text_delete_char(TextBuffer *buf, int line, int col, char *removed);
int text_move_cursor(TextBuffer *buf, int dline, int dcol);
int text_line_count(const TextBuffer *buf);
int text_get_line(const TextBuffer *buf, int index, char *out, size_t cap);
void text_print(const TextBuffer *buf);

int undo_push(UndoStack *stack, int type, int line, int col, const char *saved);
int undo_apply(TextBuffer *buf, UndoStack *stack);
int undo_depth(const UndoStack *stack);

#endif /* TEXT_H */
