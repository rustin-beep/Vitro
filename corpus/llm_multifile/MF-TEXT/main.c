#include <stdio.h>
#include <string.h>
#include "text.h"

int main(void)
{
    TextBuffer buf;
    UndoStack undo;
    char saved[TEXT_MAX_COLS];
    char undo_char[2];
    char removed;
    int rc;

    memset(&undo, 0, sizeof undo);
    text_init(&buf);

    printf("=== insert 4 lines ===\n");
    text_insert_line(&buf, 0, "hello world");
    text_insert_line(&buf, 1, "second line");
    text_insert_line(&buf, 2, "third line");
    text_insert_line(&buf, 3, "fourth line");
    text_print(&buf);

    printf("=== edit 1: append '!' at end of line 0 ===\n");
    rc = text_insert_char(&buf, 0, (int)strlen(buf.lines[0]), '!');
    undo_push(&undo, UNDO_INSERT_CHAR, 0, (int)strlen(buf.lines[0]) - 1, NULL);
    printf("rc=%d\n", rc);
    text_print(&buf);

    printf("=== edit 2: delete char at line 1 col 0 ===\n");
    rc = text_delete_char(&buf, 1, 0, &removed);
    undo_char[0] = removed;
    undo_char[1] = '\0';
    undo_push(&undo, UNDO_DELETE_CHAR, 1, 0, undo_char);
    printf("rc=%d removed=%c\n", rc, removed);
    text_print(&buf);

    printf("=== edit 3: delete line 2 ===\n");
    text_get_line(&buf, 2, saved, sizeof saved);
    rc = text_delete_line(&buf, 2);
    undo_push(&undo, UNDO_DELETE_LINE, 2, 0, saved);
    printf("rc=%d saved=[%s]\n", rc, saved);
    text_print(&buf);

    printf("=== edit 4: insert line at index 1 ===\n");
    rc = text_insert_line(&buf, 1, "inserted line");
    undo_push(&undo, UNDO_INSERT_LINE, 1, 0, NULL);
    printf("rc=%d\n", rc);
    text_print(&buf);

    printf("=== edit 5: move cursor ===\n");
    rc = text_move_cursor(&buf, 0, 5);
    printf("rc=%d\n", rc);
    text_print(&buf);

    printf("=== counters ===\n");
    printf("edits=%d lines=%d undo_depth=%d\n", buf.edits, text_line_count(&buf), undo_depth(&undo));

    printf("=== undo step 1 ===\n");
    rc = undo_apply(&buf, &undo);
    printf("rc=%d\n", rc);
    text_print(&buf);

    printf("=== undo step 2 ===\n");
    rc = undo_apply(&buf, &undo);
    printf("rc=%d\n", rc);
    text_print(&buf);

    printf("=== undo step 3 ===\n");
    rc = undo_apply(&buf, &undo);
    printf("rc=%d\n", rc);
    text_print(&buf);

    printf("=== final ===\n");
    printf("edits=%d lines=%d undo_depth=%d\n", buf.edits, text_line_count(&buf), undo_depth(&undo));
    return 0;
}
