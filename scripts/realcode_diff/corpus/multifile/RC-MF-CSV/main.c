#include <stdio.h>
#include <string.h>
#include "csv.h"

static const char *CSV_TEXT =
    "name,age,city,note\n"
    "alice,30,beijing,\"hello world\"\n"
    "bob,25,shanghai,\"say \"\"hi\"\" now\"\n";

int main(void)
{
    CsvTable table;
    char buf[CSV_MAX_FIELD];
    int rc;
    int i;

    memset(&table, 0, sizeof table);
    rc = csv_parse(CSV_TEXT, &table);
    printf("=== parsed %d rows ===\n", rc);
    csv_print(&table);

    printf("=== by column name ===\n");
    rc = csv_field_by_name(&table, "name", 1, buf, sizeof buf);
    printf("row1 name rc=%d value=[%s]\n", rc, buf);
    rc = csv_field_by_name(&table, "city", 2, buf, sizeof buf);
    printf("row2 city rc=%d value=[%s]\n", rc, buf);
    rc = csv_field_by_name(&table, "note", 2, buf, sizeof buf);
    printf("row2 note rc=%d value=[%s]\n", rc, buf);
    rc = csv_field_by_name(&table, "missing", 1, buf, sizeof buf);
    printf("row1 missing rc=%d\n", rc);

    printf("=== by index ===\n");
    rc = csv_field_by_index(&table, 1, 1, buf, sizeof buf);
    printf("row1 col1 rc=%d value=[%s]\n", rc, buf);
    rc = csv_field_by_index(&table, 2, 3, buf, sizeof buf);
    printf("row2 col3 rc=%d value=[%s]\n", rc, buf);
    rc = csv_field_by_index(&table, 2, 9, buf, sizeof buf);
    printf("row2 col9 rc=%d\n", rc);
    rc = csv_field_by_index(&table, 9, 0, buf, sizeof buf);
    printf("row9 col0 rc=%d\n", rc);

    printf("=== column population ===\n");
    for (i = 0; i < 4; i++) {
        printf("  column %d used by %d rows\n", i, csv_column_count(&table, i));
    }

    printf("=== escaped characters ===\n");
    for (i = 0; i < table.line_count; i++) {
        printf("  row%d skipped=%d\n", i, table.lines[i].skipped_escapes);
    }
    printf("total_skipped=%d\n", table.total_skipped_escapes);
    return 0;
}
