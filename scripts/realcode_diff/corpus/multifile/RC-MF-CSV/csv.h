#ifndef CSV_H
#define CSV_H

#include <stddef.h>

#define CSV_MAX_FIELDS 16
#define CSV_MAX_FIELD  64
#define CSV_MAX_LINES  32

#define CSV_OK           0
#define CSV_ERR_NULL   (-1)
#define CSV_ERR_BOUNDS (-2)
#define CSV_ERR_NOTFOUND (-3)

typedef struct {
    int field_count;
    char fields[CSV_MAX_FIELDS][CSV_MAX_FIELD];
    int skipped_escapes;
} CsvLine;

typedef struct {
    CsvLine lines[CSV_MAX_LINES];
    int line_count;
    int total_skipped_escapes;
} CsvTable;

/* parses comma separated text; double quoted fields keep separators and "" is an escaped quote */
int csv_parse(const char *text, CsvTable *table);

/* looks a column up by its header name and returns the value of the given row */
int csv_field_by_name(const CsvTable *table, const char *name, int row, char *out, size_t cap);

/* returns the value of the given row and column index */
int csv_field_by_index(const CsvTable *table, int row, int col, char *out, size_t cap);

/* number of rows that carry a value in the given column */
int csv_column_count(const CsvTable *table, int col);

void csv_print(const CsvTable *table);

#endif /* CSV_H */
