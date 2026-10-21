// @category: llm_scale
// 规模压力面：关系库：hash + 有序双索引 + WHERE/ORDER/LIMIT + INNER JOIN + GROUP BY + 事务日志回滚
// 来源：LLM 千行语料 HUGE-DB2（1135 行，2026-10-21 入库；clang golden 由 clang_direct 现场生成）
// 注：本档 member_accesses 上限 400（#236 分档），见 scripts/perf_budget/rules.json
/*
 * HUGE-DB2 -- a small relational database engine in one C23 file.
 *
 * The engine holds two tables. The table students has the columns id, name,
 * dept_id and score and starts with twenty rows, the table depts has the
 * columns id, name and budget and starts with five rows.
 *
 * Two indexes are maintained. A hash index over the primary key gives a
 * direct access to a row, an ordered index over the score column keeps the
 * row numbers sorted so that a range scan and an ordered result are cheap.
 * Both indexes are updated when a row is inserted or removed.
 *
 * The query engine understands a single table select with a where clause
 * that compares a column with a constant, the comparisons ==, !=, <, >, <=
 * and >= can be combined with and or, plus an order by clause and a limit.
 * A join between students and depts over the column dept_id is implemented
 * as well.
 *
 * Aggregates group the students by dept_id and report the count, the sum,
 * the average, the maximum and the minimum of the score.
 *
 * Every modification is written into a transaction log that keeps the old
 * value of the changed cell, the log can roll back the last three
 * modifications.
 *
 * The main function runs ten fixed statements and prints the result of
 * every statement together with the number of scanned rows and the number of
 * index hits.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

/* ------------------------------------------------------------------ */
/* limits                                                             */
/* ------------------------------------------------------------------ */

#define MAX_STUDENTS 64
#define MAX_DEPTS 16
#define MAX_DEPT_NAME 24
#define MAX_STUDENT_NAME 24
#define HASH_BUCKETS 32
#define MAX_LOG 32
#define MAX_QUERY_ROWS 64
#define MAX_CONDITIONS 4
#define LINE_LEN 128

#define DB_OK 0
#define DB_ERR_FULL (-1)
#define DB_ERR_NOTFOUND (-2)
#define DB_ERR_ARG (-3)
#define DB_ERR_STATE (-4)

/* ------------------------------------------------------------------ */
/* types                                                              */
/* ------------------------------------------------------------------ */

typedef struct {
    int id;
    char name[MAX_STUDENT_NAME];
    int dept_id;
    int score;
} Student;

typedef struct {
    int id;
    char name[MAX_DEPT_NAME];
    int budget;
} Dept;

typedef struct {
    Student rows[MAX_STUDENTS];
    int count;
} StudentTable;

typedef struct {
    Dept rows[MAX_DEPTS];
    int count;
} DeptTable;

typedef struct {
    int head[HASH_BUCKETS];
    int next[MAX_STUDENTS];
    int row_of[MAX_STUDENTS];
    int used[MAX_STUDENTS];
    int count;
    int collisions;
    int lookups;
} IdIndex;

typedef struct {
    int order[MAX_STUDENTS];
    int size;
} ScoreIndex;

typedef enum {
    LOG_UPDATE = 1,
    LOG_INSERT,
    LOG_DELETE
} LogKind;

typedef struct {
    LogKind kind;
    int row;
    int field;
    int old_value;
    char old_text[MAX_STUDENT_NAME];
} LogEntry;

typedef struct {
    LogEntry items[MAX_LOG];
    int count;
} TransactionLog;

typedef struct {
    char field[16];
    char op[4];
    char value[24];
    int has_second;
    char op2[4];
    char value2[24];
    char logic[4];
} Condition;

typedef struct {
    Condition conditions[MAX_CONDITIONS];
    int condition_count;
    char order_field[16];
    int order_descending;
    int limit;
} Query;

typedef struct {
    int rows_scanned;
    int index_hits;
    int matched;
} QueryStats;

typedef struct {
    StudentTable students;
    DeptTable depts;
    IdIndex id_index;
    ScoreIndex score_index;
    TransactionLog log;
} Database;

/* ------------------------------------------------------------------ */
/* string helpers                                                     */
/* ------------------------------------------------------------------ */

static void db_copy(char *dst, size_t cap, const char *src)
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

static void db_trim(char *s)
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

static int db_starts_with(const char *text, const char *prefix)
{
    size_t n;

    if (text == NULL || prefix == NULL) {
        return 0;
    }
    n = strlen(prefix);
    if (n == 0) {
        return 1;
    }
    if (strlen(text) < n) {
        return 0;
    }
    return strncmp(text, prefix, n) == 0 ? 1 : 0;
}

static int db_parse_int(const char *text, int *out)
{
    int value = 0;
    int i;
    int start = 0;

    if (text == NULL || out == NULL) {
        return 0;
    }
    while (text[start] == ' ' || text[start] == '\t') {
        start++;
    }
    if (text[start] == '\0') {
        return 0;
    }
    for (i = start; text[i] != '\0'; i++) {
        if (!isdigit((unsigned char)text[i]) && text[i] != '-') {
            return 0;
        }
        if (text[i] == '-') {
            continue;
        }
        value = value * 10 + (text[i] - '0');
    }
    *out = value;
    return 1;
}

/* ------------------------------------------------------------------ */
/* indexes                                                            */
/* ------------------------------------------------------------------ */

static void id_index_init(IdIndex *index)
{
    int i;

    for (i = 0; i < HASH_BUCKETS; i++) {
        index->head[i] = -1;
    }
    for (i = 0; i < MAX_STUDENTS; i++) {
        index->next[i] = -1;
        index->row_of[i] = -1;
        index->used[i] = 0;
    }
    index->count = 0;
    index->collisions = 0;
    index->lookups = 0;
}

static int id_index_put(IdIndex *index, int id, int row)
{
    int bucket;
    int slot;

    if (index->count >= MAX_STUDENTS) {
        return DB_ERR_FULL;
    }
    for (slot = 0; slot < MAX_STUDENTS; slot++) {
        if (index->used[slot]) {
            continue;
        }
        break;
    }
    if (slot >= MAX_STUDENTS) {
        return DB_ERR_FULL;
    }
    bucket = id % HASH_BUCKETS;
    if (bucket < 0) {
        bucket += HASH_BUCKETS;
    }
    if (index->head[bucket] >= 0) {
        index->collisions++;
    }
    index->used[slot] = 1;
    index->row_of[slot] = row;
    index->next[slot] = index->head[bucket];
    index->head[bucket] = slot;
    index->count++;
    return DB_OK;
}

static int id_index_find(IdIndex *index, int id)
{
    int bucket;
    int slot;
    int guard = 0;

    if (index == NULL) {
        return -1;
    }
    bucket = id % HASH_BUCKETS;
    if (bucket < 0) {
        bucket += HASH_BUCKETS;
    }
    slot = index->head[bucket];
    while (slot >= 0 && guard < MAX_STUDENTS) {
        if (index->row_of[slot] >= 0) {
            index->lookups++;
            return index->row_of[slot];
        }
        slot = index->next[slot];
        guard++;
    }
    return -1;
}

static int id_index_remove(IdIndex *index, int id)
{
    int bucket;
    int slot;
    int prev = -1;
    int guard = 0;

    if (index == NULL) {
        return DB_ERR_NOTFOUND;
    }
    bucket = id % HASH_BUCKETS;
    if (bucket < 0) {
        bucket += HASH_BUCKETS;
    }
    slot = index->head[bucket];
    while (slot >= 0 && guard < MAX_STUDENTS) {
        if (index->row_of[slot] == id) {
            if (prev < 0) {
                index->head[bucket] = index->next[slot];
            } else {
                index->next[prev] = index->next[slot];
            }
            index->used[slot] = 0;
            index->row_of[slot] = -1;
            index->next[slot] = -1;
            index->count--;
            return DB_OK;
        }
        prev = slot;
        slot = index->next[slot];
        guard++;
    }
    return DB_ERR_NOTFOUND;
}

static void score_index_init(ScoreIndex *index)
{
    index->size = 0;
}

static int score_index_insert(ScoreIndex *index, const StudentTable *table, int row)
{
    int low;
    int high;
    int i;

    if (index->size >= MAX_STUDENTS) {
        return DB_ERR_FULL;
    }
    low = 0;
    high = index->size;
    while (low < high) {
        int mid = (low + high) / 2;
        if (table->rows[index->order[mid]].score < table->rows[row].score) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    for (i = index->size; i > low; i--) {
        index->order[i] = index->order[i - 1];
    }
    index->order[low] = row;
    index->size++;
    return DB_OK;
}

static int score_index_remove(ScoreIndex *index, int row)
{
    int i;

    for (i = 0; i < index->size; i++) {
        if (index->order[i] != row) {
            continue;
        }
        for (; i < index->size - 1; i++) {
            index->order[i] = index->order[i + 1];
        }
        index->size--;
        return DB_OK;
    }
    return DB_ERR_NOTFOUND;
}

static void score_index_rebuild(ScoreIndex *index, const StudentTable *table)
{
    int i;
    int j;

    index->size = 0;
    for (i = 0; i < table->count; i++) {
        for (j = index->size; j > 0; j--) {
            if (table->rows[index->order[j - 1]].score <= table->rows[i].score) {
                break;
            }
            index->order[j] = index->order[j - 1];
        }
        index->order[j] = i;
        if (index->size < MAX_STUDENTS) {
            index->size++;
        }
    }
}

/* ------------------------------------------------------------------ */
/* transaction log                                                    */
/* ------------------------------------------------------------------ */

static void log_init(TransactionLog *log)
{
    log->count = 0;
}

static void log_push(TransactionLog *log, LogKind kind, int row, int field,
                     int old_value, const char *old_text)
{
    LogEntry *entry;

    if (log->count >= MAX_LOG) {
        return;
    }
    entry = &log->items[log->count];
    entry->kind = kind;
    entry->row = row;
    entry->field = field;
    entry->old_value = old_value;
    db_copy(entry->old_text, MAX_STUDENT_NAME, (old_text != NULL) ? old_text : "");
    log->count++;
}

static int log_rollback(Database *db, int steps)
{
    int done = 0;
    int i;

    while (done < steps && db->log.count > 0) {
        LogEntry *entry = &db->log.items[db->log.count - 1];
        if (entry->kind == LOG_UPDATE) {
            if (entry->field == 0) {
                db->students.rows[entry->row].score = entry->old_value;
            } else if (entry->field == 1) {
                db->students.rows[entry->row].dept_id = entry->old_value;
            } else {
                db_copy(db->students.rows[entry->row].name, MAX_STUDENT_NAME, entry->old_text);
            }
        } else if (entry->kind == LOG_INSERT) {
            db->students.count--;
        } else if (entry->kind == LOG_DELETE) {
            db->students.count++;
        }
        db->log.count--;
        done++;
    }
    if (done > 0) {
        score_index_rebuild(&db->score_index, &db->students);
        id_index_init(&db->id_index);
        for (i = 0; i < db->students.count; i++) {
            id_index_put(&db->id_index, db->students.rows[i].id, i);
        }
    }
    return done;
}

/* ------------------------------------------------------------------ */
/* table operations                                                   */
/* ------------------------------------------------------------------ */

static void db_init(Database *db)
{
    memset(db, 0, sizeof(Database));
    id_index_init(&db->id_index);
    score_index_init(&db->score_index);
    log_init(&db->log);
}

static int table_find_by_id(const StudentTable *table, int id);

static void print_record(const Student *student)
{
    printf("      id=%-3d name=%-12s dept=%-3d score=%-4d\n", student->id, student->name,
           student->dept_id, student->score);
}

static int student_insert(Database *db, const char *name, int dept_id, int score)
{
    Student *student;
    int row;

    if (db->students.count >= MAX_STUDENTS) {
        return DB_ERR_FULL;
    }
    if (table_find_by_id(&db->students, db->students.count + 1) >= 0) {
        return DB_ERR_STATE;
    }
    row = db->students.count;
    student = &db->students.rows[row];
    student->id = row + 1;
    db_copy(student->name, MAX_STUDENT_NAME, name);
    student->dept_id = dept_id;
    student->score = score;
    db->students.count++;
    id_index_put(&db->id_index, student->id, row);
    score_index_insert(&db->score_index, &db->students, row);
    log_push(&db->log, LOG_INSERT, row, 0, 0, name);
    return row;
}

static int table_find_by_id(const StudentTable *table, int id)
{
    int i;

    for (i = 0; i < table->count; i++) {
        if (table->rows[i].id == id) {
            return i;
        }
    }
    return -1;
}

static int student_update_score(Database *db, int id, int score)
{
    int row = table_find_by_id(&db->students, id);

    if (row < 0) {
        return DB_ERR_NOTFOUND;
    }
    log_push(&db->log, LOG_UPDATE, row, 0, db->students.rows[row].score, NULL);
    db->students.rows[row].score = score;
    score_index_remove(&db->score_index, row);
    score_index_insert(&db->score_index, &db->students, row);
    return DB_OK;
}

static int student_update_dept(Database *db, int id, int dept_id)
{
    int row = table_find_by_id(&db->students, id);

    if (row < 0) {
        return DB_ERR_NOTFOUND;
    }
    log_push(&db->log, LOG_UPDATE, row, 1, db->students.rows[row].dept_id, NULL);
    db->students.rows[row].dept_id = dept_id;
    return DB_OK;
}

static int student_update_name(Database *db, int id, const char *name)
{
    int row = table_find_by_id(&db->students, id);

    if (row < 0) {
        return DB_ERR_NOTFOUND;
    }
    log_push(&db->log, LOG_UPDATE, row, 2, 0, db->students.rows[row].name);
    db_copy(db->students.rows[row].name, MAX_STUDENT_NAME, name);
    return DB_OK;
}

static int student_delete(Database *db, int id)
{
    int row = table_find_by_id(&db->students, id);
    int i;

    if (row < 0) {
        return DB_ERR_NOTFOUND;
    }
    log_push(&db->log, LOG_DELETE, row, 0, 0, db->students.rows[row].name);
    id_index_remove(&db->id_index, id);
    for (i = row; i < db->students.count - 1; i++) {
        db->students.rows[i] = db->students.rows[i + 1];
    }
    db->students.count--;
    score_index_rebuild(&db->score_index, &db->students);
    id_index_init(&db->id_index);
    for (i = 0; i < db->students.count; i++) {
        id_index_put(&db->id_index, db->students.rows[i].id, i);
    }
    return DB_OK;
}

static int dept_find(const DeptTable *table, int id)
{
    int i;

    for (i = 0; i < table->count; i++) {
        if (table->rows[i].id == id) {
            return i;
        }
    }
    return -1;
}

static void dept_insert(DeptTable *table, const char *name, int budget)
{
    Dept *dept;

    if (table->count >= MAX_DEPTS) {
        return;
    }
    dept = &table->rows[table->count];
    dept->id = table->count + 1;
    db_copy(dept->name, MAX_DEPT_NAME, name);
    dept->budget = budget;
    table->count++;
}

/* ------------------------------------------------------------------ */
/* the query engine                                                   */
/* ------------------------------------------------------------------ */

static int db_parse_field_int(const char *text, int *out)
{
    const char *equals = strchr(text, '=');
    int value = 0;

    if (equals == NULL) {
        return db_parse_int(text, out);
    }
    if (!db_parse_int(equals + 1, &value)) {
        return 0;
    }
    *out = value;
    return 1;
}

static int condition_parse(Condition *condition, const char *text)
{
    char buffer[LINE_LEN];
    const char *operators[7];
    int found = -1;
    size_t position = 0;
    int i;

    operators[0] = "==";
    operators[1] = "!=";
    operators[2] = "<=";
    operators[3] = ">=";
    operators[4] = "<";
    operators[5] = ">";
    operators[6] = "=";
    db_copy(buffer, sizeof buffer, text);
    db_trim(buffer);
    for (i = 0; i < 7; i++) {
        const char *hit = strstr(buffer, operators[i]);
        if (hit != NULL && (found < 0 || hit < buffer + position)) {
            found = i;
            position = (size_t)(hit - buffer);
        }
    }
    if (found < 0) {
        return DB_ERR_ARG;
    }
    db_copy(condition->field, sizeof condition->field, buffer);
    condition->field[position] = '\0';
    db_trim(condition->field);
    db_copy(condition->op, sizeof condition->op, operators[found]);
    db_copy(condition->value, sizeof condition->value, buffer + position + strlen(operators[found]));
    db_trim(condition->value);
    if (condition->value[0] == '\'' && strlen(condition->value) >= 2) {
        size_t len = strlen(condition->value);
        memmove(condition->value, condition->value + 1, len - 2);
        condition->value[len - 2] = '\0';
    }
    condition->has_second = 0;
    condition->op2[0] = '\0';
    condition->value2[0] = '\0';
    condition->logic[0] = '\0';
    return DB_OK;
}

static int query_parse(Query *query, const char *statement)
{
    const char *where = strstr(statement, " WHERE ");
    const char *order = strstr(statement, " ORDER BY ");
    const char *limit = strstr(statement, " LIMIT ");
    char buffer[LINE_LEN];

    memset(query, 0, sizeof(Query));
    query->limit = MAX_QUERY_ROWS;
    if (where != NULL) {
        const char *end = (order != NULL) ? order : ((limit != NULL) ? limit : (where + strlen(where)));
        size_t len = (size_t)(end - (where + 7));
        if (len > sizeof buffer - 1) {
            len = sizeof buffer - 1;
        }
        memcpy(buffer, where + 7, len);
        buffer[len] = '\0';
        db_trim(buffer);
        {
            char *connector = strstr(buffer, " AND ");
            int use_or = 0;
            if (connector == NULL) {
                connector = strstr(buffer, " OR ");
                use_or = 1;
            }
            if (connector != NULL) {
                *connector = '\0';
                if (query->condition_count < MAX_CONDITIONS) {
                    condition_parse(&query->conditions[query->condition_count], buffer);
                    query->condition_count++;
                }
                if (query->condition_count < MAX_CONDITIONS) {
                    condition_parse(&query->conditions[query->condition_count], connector + 5);
                    query->conditions[query->condition_count].has_second = 1;
                    db_copy(query->conditions[query->condition_count].logic,
                            sizeof query->conditions[0].logic, use_or ? "OR" : "AND");
                    query->condition_count++;
                }
            } else {
                if (query->condition_count < MAX_CONDITIONS) {
                    condition_parse(&query->conditions[query->condition_count], buffer);
                    query->condition_count++;
                }
            }
        }
    }
    if (order != NULL) {
        const char *end = (limit != NULL) ? limit : (order + strlen(order));
        size_t len = (size_t)(end - (order + 10));
        if (len > sizeof buffer - 1) {
            len = sizeof buffer - 1;
        }
        memcpy(buffer, order + 10, len);
        buffer[len] = '\0';
        db_trim(buffer);
        if (strlen(buffer) > 4 && strcmp(buffer + strlen(buffer) - 4, " DESC") == 0) {
            query->order_descending = 1;
            buffer[strlen(buffer) - 4] = '\0';
            db_trim(buffer);
        }
        db_copy(query->order_field, sizeof query->order_field, buffer);
    }
    if (limit != NULL) {
        int value = 0;
        db_copy(buffer, sizeof buffer, limit + 7);
        db_trim(buffer);
        if (db_parse_int(buffer, &value)) {
            query->limit = value;
        }
    }
    return DB_OK;
}

static int student_field_value(const Student *student, const char *field, int *out, char *text, size_t cap)
{
    if (strcmp(field, "id") == 0) {
        *out = student->id;
        return 1;
    }
    if (strcmp(field, "score") == 0) {
        *out = student->score;
        return 1;
    }
    if (strcmp(field, "dept_id") == 0) {
        *out = student->dept_id;
        return 1;
    }
    if (strcmp(field, "name") == 0) {
        db_copy(text, cap, student->name);
        return 2;
    }
    return 0;
}

static int compare_value(const char *op, int left, const char *right, int *result)
{
    int right_value = 0;

    if (!db_parse_int(right, &right_value)) {
        return 0;
    }
    if (strcmp(op, "==") == 0 || strcmp(op, "=") == 0) {
        *result = (left == right_value) ? 1 : 0;
    } else if (strcmp(op, "!=") == 0) {
        *result = (left != right_value) ? 1 : 0;
    } else if (strcmp(op, "<") == 0) {
        *result = (left < right_value) ? 1 : 0;
    } else if (strcmp(op, ">") == 0) {
        *result = (left > right_value) ? 1 : 0;
    } else if (strcmp(op, "<=") == 0) {
        *result = (left <= right_value) ? 1 : 0;
    } else if (strcmp(op, ">=") == 0) {
        *result = (left >= right_value) ? 1 : 0;
    } else {
        return 0;
    }
    return 1;
}

static int row_matches(const Student *student, const Condition *condition)
{
    int value = 0;
    int result = 0;
    char text[MAX_STUDENT_NAME];

    if (student_field_value(student, condition->field, &value, text, sizeof text) == 0) {
        return 0;
    }
    if (student_field_value(student, condition->field, &value, text, sizeof text) == 2) {
        return strcmp(text, condition->value) == 0 ? 1 : 0;
    }
    if (compare_value(condition->op, value, condition->value, &result) == 0) {
        return 0;
    }
    return result;
}

static int query_execute(Database *db, const Query *query, QueryStats *stats, int *out_rows)
{
    int matched[MAX_QUERY_ROWS];
    int count = 0;
    int i;
    int j;

    stats->rows_scanned = 0;
    stats->index_hits = 0;
    stats->matched = 0;
    if (query->condition_count == 1 && strcmp(query->conditions[0].field, "id") == 0 &&
        (strcmp(query->conditions[0].op, "==") == 0 || strcmp(query->conditions[0].op, "=") == 0)) {
        int wanted = 0;
        int direct;
        if (db_parse_int(query->conditions[0].value, &wanted)) {
            direct = id_index_find(&db->id_index, wanted);
            if (direct >= 0) {
                stats->index_hits++;
                stats->rows_scanned++;
                if (out_rows != NULL) {
                    out_rows[0] = direct;
                }
                stats->matched = 1;
                return 1;
            }
        }
    }
    for (i = 0; i < db->students.count; i++) {
        int ok = 1;
        int k;
        stats->rows_scanned++;
        for (k = 0; k < query->condition_count; k++) {
            int single = row_matches(&db->students.rows[i], &query->conditions[k]);
            if (k == 0) {
                ok = single;
            } else if (query->conditions[k].logic[0] == 'O') {
                ok = ok || single;
            } else {
                ok = ok && single;
            }
        }
        if (query->condition_count == 0) {
            ok = 1;
        }
        if (ok && count < MAX_QUERY_ROWS) {
            matched[count] = i;
            count++;
        }
    }
    if (query->order_field[0] != '\0') {
        for (i = 1; i < count; i++) {
            int current = matched[i];
            int value_current = 0;
            int value_other = 0;
            char text[MAX_STUDENT_NAME];
            student_field_value(&db->students.rows[current], query->order_field,
                                &value_current, text, sizeof text);
            for (j = i - 1; j >= 0; j--) {
                int other = matched[j];
                int swap = 0;
                student_field_value(&db->students.rows[other], query->order_field,
                                    &value_other, text, sizeof text);
                if (query->order_descending) {
                    swap = (value_other < value_current);
                } else {
                    swap = (value_current < value_other);
                }
                if (!swap) {
                    break;
                }
                matched[j + 1] = matched[j];
                matched[j] = current;
            }
        }
    }
    if (count > query->limit) {
        count = query->limit;
    }
    stats->matched = count;
    if (out_rows != NULL) {
        for (i = 0; i < count; i++) {
            out_rows[i] = matched[i];
        }
    }
    return count;
}

static void query_print(const StudentTable *table, const int *rows, int count)
{
    int i;

    printf("      id  name              dept  score\n");
    for (i = 0; i < count; i++) {
        const Student *student = &table->rows[rows[i]];
        printf("    %3d  %-16s %4d  %5d\n", student->id, student->name,
               student->dept_id, student->score);
    }
}

/* ------------------------------------------------------------------ */
/* join and aggregates                                               */
/* ------------------------------------------------------------------ */

static int join_tables(Database *db, int *pairs, int max_pairs)
{
    int count = 0;
    int i;

    for (i = 0; i < db->students.count; i++) {
        int dept = dept_find(&db->depts, db->students.rows[i].dept_id);
        if (dept < 0) {
            continue;
        }
        if (count < max_pairs) {
            pairs[count] = i;
            count++;
        }
    }
    return count;
}

static void print_join(Database *db)
{
    int pairs[MAX_QUERY_ROWS];
    int count = join_tables(db, pairs, MAX_QUERY_ROWS);
    int i;

    printf("      student          dept             budget\n");
    for (i = 0; i < count; i++) {
        const Student *student = &db->students.rows[pairs[i]];
        const Dept *dept = &db->depts.rows[dept_find(&db->depts, student->dept_id)];
        printf("    %-16s %-16s %6d\n", student->name, dept->name, dept->budget);
    }
    printf("    joined rows=%d\n", count);
}

static void group_aggregate(Database *db)
{
    int d;

    printf("      dept   count    sum    avg    max    min\n");
    for (d = 0; d < db->depts.count; d++) {
        int count = 0;
        int sum = 0;
        int max = -1000000;
        int min = 1000000;
        int i;
        for (i = 0; i < db->students.count; i++) {
            const Student *student = &db->students.rows[i];
            if (student->dept_id != db->depts.rows[d].id) {
                continue;
            }
            count++;
            sum += student->score;
            if (student->score > max) {
                max = student->score;
            }
            if (student->score < min) {
                min = student->score;
            }
        }
        if (count == 0) {
            printf("    %-6s %5d %7d %6s %6s %6s\n", db->depts.rows[d].name, 0, 0, "-", "-", "-");
            continue;
        }
        printf("    %-6s %5d %7d %6.2f %6d %6d\n", db->depts.rows[d].name, count, sum,
               (double)sum / (double)count, max, min);
    }
}

/* ------------------------------------------------------------------ */
/* main                                                               */
/* ------------------------------------------------------------------ */

static void fill_data(Database *db)
{
    static const char *const NAMES[20] = {
        "alice", "bob", "carol", "dave", "erin",
        "frank", "grace", "heidi", "ivan", "judy",
        "mallory", "niaj", "olivia", "peggy", "rupert",
        "sybil", "trent", "victor", "walter", "zoe"
    };
    static const int DEPTS[20] = {
        1, 2, 1, 3, 2, 4, 1, 5, 3, 2,
        4, 1, 5, 3, 2, 4, 5, 1, 3, 2
    };
    static const int SCORES[20] = {
        88, 72, 95, 61, 79, 84, 90, 55, 68, 93,
        77, 81, 59, 86, 74, 92, 66, 83, 70, 87
    };
    int i;

    dept_insert(&db->depts, "comp", 50000);
    dept_insert(&db->depts, "math", 30000);
    dept_insert(&db->depts, "physics", 42000);
    dept_insert(&db->depts, "history", 18000);
    dept_insert(&db->depts, "arts", 25000);
    for (i = 0; i < 20; i++) {
        student_insert(db, NAMES[i], DEPTS[i], SCORES[i]);
    }
}

int main(void)
{
    static const char *const SCRIPT[10] = {
        "SELECT * FROM students WHERE score >= 85 ORDER BY score DESC LIMIT 5",
        "SELECT * FROM students WHERE dept_id = 2 AND score > 75",
        "SELECT * FROM students WHERE name = 'erin'",
        "UPDATE students SET score = 99 WHERE id = 3",
        "SELECT * FROM students WHERE id = 3",
        "DELETE FROM students WHERE id = 12",
        "SELECT * FROM students WHERE score < 70 ORDER BY score ASC LIMIT 4",
        "SELECT * FROM students WHERE dept_id = 1 OR score > 90",
        "SELECT * FROM students WHERE score != 0 AND dept_id = 5",
        "SELECT * FROM students WHERE score > 80"
    };
    Database db;
    Query query;
    QueryStats stats;
    int i;

    db_init(&db);
    fill_data(&db);

    printf("=== initial tables ===\n");
    printf("  students=%d depts=%d id_index=%d score_index=%d collisions=%d\n",
           db.students.count, db.depts.count, db.id_index.count,
           db.score_index.size, db.id_index.collisions);
    printf("  score order (ascending):");
    for (i = 0; i < db.score_index.size; i++) {
        printf(" %d", db.students.rows[db.score_index.order[i]].score);
    }
    printf("\n");

    printf("=== ten statements ===\n");
    for (i = 0; i < 10; i++) {
        printf("  [%2d] %s\n", i + 1, SCRIPT[i]);
        if (db_starts_with(SCRIPT[i], "SELECT")) {
            int rows[MAX_QUERY_ROWS];
            int count;
            query_parse(&query, SCRIPT[i]);
            count = query_execute(&db, &query, &stats, rows);
            printf("    rows=%d scanned=%d index_hits=%d\n",
                   count, stats.rows_scanned, stats.index_hits);
            query_print(&db.students, rows, count);
        } else if (db_starts_with(SCRIPT[i], "UPDATE")) {
            int id = 0;
            int value = 0;
            const char *set = strstr(SCRIPT[i], "SET ");
            const char *where = strstr(SCRIPT[i], "WHERE ");
            char field[16];
            char buffer[LINE_LEN];
            size_t len;
            int rc;
            len = (size_t)((where - set) - 4);
            if (len > sizeof buffer - 1) {
                len = sizeof buffer - 1;
            }
            memcpy(buffer, set + 4, len);
            buffer[len] = '\0';
            db_trim(buffer);
            {
                char *space = strchr(buffer, ' ');
                if (space != NULL) {
                    *space = '\0';
                    db_copy(field, sizeof field, buffer);
                    db_parse_int(space + 1, &value);
                } else {
                    db_copy(field, sizeof field, buffer);
                }
            }
            db_parse_field_int(where + 6, &id);
            if (strcmp(field, "score") == 0) {
                rc = student_update_score(&db, id, value);
            } else if (strcmp(field, "dept_id") == 0) {
                rc = student_update_dept(&db, id, value);
            } else {
                rc = student_update_name(&db, id, buffer);
            }
            printf("    rc=%d affected=1\n", rc);
        } else if (db_starts_with(SCRIPT[i], "DELETE")) {
            const char *where = strstr(SCRIPT[i], "WHERE ");
            int id = 0;
            int rc;
            db_parse_field_int(where + 6, &id);
            rc = student_delete(&db, id);
            printf("    rc=%d affected=%d\n", rc, (rc == DB_OK) ? 1 : 0);
        }
    }

    printf("=== join ===\n");
    print_join(&db);

    printf("=== group by dept_id ===\n");
    group_aggregate(&db);

    printf("=== rollback the last three modifications ===\n");
    printf("  log entries before=%d\n", db.log.count);
    {
        int done = log_rollback(&db, 3);
        printf("  rolled back=%d log entries after=%d\n", done, db.log.count);
    }
    printf("  students after rollback=%d\n", db.students.count);
    for (i = 0; i < db.students.count && i < 5; i++) {
        print_record(&db.students.rows[i]);
    }

    printf("=== final statistics ===\n");
    printf("  students=%d depts=%d\n", db.students.count, db.depts.count);
    printf("  id_index_entries=%d collisions=%d lookups=%d\n",
           db.id_index.count, db.id_index.collisions, db.id_index.lookups);
    printf("  score_index_entries=%d log_entries=%d\n", db.score_index.size, db.log.count);
    printf("=== done ===\n");
    return 0;
}
