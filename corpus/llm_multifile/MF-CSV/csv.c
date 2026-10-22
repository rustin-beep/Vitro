#include "csv.h"
#include <stdio.h>
#include <string.h>

int csv_parse(const char *text, CsvTable *table)
{
    char field[CSV_MAX_FIELD];
    const char *p;
    size_t total;
    int flen;
    int in_quotes;
    int skipped;

    if (text == NULL || table == NULL) {
        return CSV_ERR_NULL;
    }
    table->line_count = 0;
    table->total_skipped_escapes = 0;
    field[0] = '\0';
    flen = 0;
    in_quotes = 0;
    skipped = 0;
    p = text;
    total = strlen(text);

    while (p < text + total || (p == text + total && flen > 0)) {
        char ch = (p < text + total) ? *p : '\0';

        if (in_quotes) {
            if (ch == '"') {
                if (p + 1 < text + total && p[1] == '"') {
                    if (flen < CSV_MAX_FIELD - 1) {
                        field[flen] = '"';
                        flen++;
                    }
                    skipped++;
                    p += 2;
                    continue;
                }
                in_quotes = 0;
                p++;
                continue;
            }
            if (ch == '\0') {
                in_quotes = 0;
            } else {
                if (flen < CSV_MAX_FIELD - 1) {
                    field[flen] = ch;
                    flen++;
                }
                p++;
                continue;
            }
        }

        if (ch == '"' && flen == 0) {
            in_quotes = 1;
            p++;
            continue;
        }

        if (ch == ',' || ch == '\n' || ch == '\0') {
            if (table->line_count < CSV_MAX_LINES) {
                CsvLine *row = &table->lines[table->line_count];
                if (row->field_count < CSV_MAX_FIELDS) {
                    memcpy(row->fields[row->field_count], field, (size_t)flen);
                    row->fields[row->field_count][flen] = '\0';
                    row->field_count++;
                }
            }
            flen = 0;
            if (ch == ',') {
                p++;
                continue;
            }
            if (table->line_count < CSV_MAX_LINES) {
                CsvLine *row = &table->lines[table->line_count];
                row->skipped_escapes = skipped;
                table->total_skipped_escapes += skipped;
            }
            skipped = 0;
            table->line_count++;
            if (ch == '\0') {
                break;
            }
            p++;
            continue;
        }

        if (flen < CSV_MAX_FIELD - 1) {
            field[flen] = ch;
            flen++;
        }
        p++;
    }
    return table->line_count;
}

static int csv_find_column(const CsvTable *table, const char *name)
{
    if (table->line_count <= 0) {
        return -1;
    }
    for (int i = 0; i < table->lines[0].field_count; i++) {
        if (strcmp(table->lines[0].fields[i], name) == 0) {
            return i;
        }
    }
    return -1;
}

int csv_field_by_name(const CsvTable *table, const char *name, int row, char *out, size_t cap)
{
    int col;
    size_t n;

    if (table == NULL || name == NULL || out == NULL || cap == 0) {
        return CSV_ERR_NULL;
    }
    if (row < 0 || row >= table->line_count) {
        return CSV_ERR_BOUNDS;
    }
    col = csv_find_column(table, name);
    if (col < 0) {
        return CSV_ERR_NOTFOUND;
    }
    if (col >= table->lines[row].field_count) {
        return CSV_ERR_BOUNDS;
    }
    n = strlen(table->lines[row].fields[col]);
    if (n + 1 > cap) {
        return CSV_ERR_BOUNDS;
    }
    memcpy(out, table->lines[row].fields[col], n + 1);
    return CSV_OK;
}

int csv_field_by_index(const CsvTable *table, int row, int col, char *out, size_t cap)
{
    size_t n;

    if (table == NULL || out == NULL || cap == 0) {
        return CSV_ERR_NULL;
    }
    if (row < 0 || row >= table->line_count) {
        return CSV_ERR_BOUNDS;
    }
    if (col < 0 || col >= table->lines[row].field_count) {
        return CSV_ERR_BOUNDS;
    }
    n = strlen(table->lines[row].fields[col]);
    if (n + 1 > cap) {
        return CSV_ERR_BOUNDS;
    }
    memcpy(out, table->lines[row].fields[col], n + 1);
    return CSV_OK;
}

int csv_column_count(const CsvTable *table, int col)
{
    int count = 0;

    if (table == NULL) {
        return CSV_ERR_NULL;
    }
    for (int i = 0; i < table->line_count; i++) {
        if (col < table->lines[i].field_count) {
            count++;
        }
    }
    return count;
}

void csv_print(const CsvTable *table)
{
    int i;
    int j;

    if (table == NULL) {
        return;
    }
    for (i = 0; i < table->line_count; i++) {
        const CsvLine *row = &table->lines[i];
        printf("  row%d fields=%d:", i, row->field_count);
        for (j = 0; j < row->field_count; j++) {
            printf(" [%s]", row->fields[j]);
        }
        printf("\n");
    }
}
