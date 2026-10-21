// @category: llm_scale
// 规模压力面：内存数据库：定长记录表 + 哈希/有序双索引 + 四类查询 + 序列化 round-trip
// 来源：LLM 千行语料 HUGE-DB（1532 行，2026-10-21 入库；clang golden 由 clang_direct 现场生成）
// 注：本档 member_accesses 上限 400（#236 分档），见 scripts/perf_budget/rules.json
/*
 * HUGE-DB -- a self contained in-memory database engine in one C23 file.
 *
 * The engine keeps a fixed capacity record table and maintains two secondary
 * indexes on top of it: a chained hash index over the record name and an
 * ordered index over the record score. Four query shapes are supported:
 *
 *   GET id=N             point lookup by primary key
 *   RANGE score=A..B     scan over the ordered score index
 *   TOP K by score       k largest records by score
 *   COUNT where flags&m  mask test over the flag field
 *
 * The whole table can be serialized into a flat binary buffer and parsed back
 * again; the round trip is verified field by field at runtime.
 *
 * Everything is deterministic: the demo data comes from a fixed seed linear
 * congruential generator, never from rand().
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <math.h>

/* ------------------------------------------------------------------ */
/* constants                                                          */
/* ------------------------------------------------------------------ */

#define DB_MAX_RECORDS 512
#define DB_NAME_LEN 32
#define DB_HASH_BUCKETS 1024
#define DB_MAX_ROWS 512
#define DB_MAX_QUERY_ROWS 64
#define DB_SERIAL_HEADER "VITRODB1"
#define DB_SERIAL_HEADER_LEN 8
#define DB_RECORD_BYTES (DB_NAME_LEN + 4 + 8 + 4)
#define DB_SERIAL_MAX (DB_SERIAL_HEADER_LEN + 4 + DB_MAX_RECORDS * DB_RECORD_BYTES)

#define DB_FLAG_ACTIVE 1
#define DB_FLAG_VIP 2
#define DB_FLAG_LOCKED 4
#define DB_FLAG_ARCHIVED 8

#define DB_OK 0
#define DB_ERR_FULL (-1)
#define DB_ERR_NOTFOUND (-2)
#define DB_ERR_ARG (-3)
#define DB_ERR_STATE (-4)

/* ------------------------------------------------------------------ */
/* types                                                              */
/* ------------------------------------------------------------------ */

typedef struct {
    char name[DB_NAME_LEN];
    int id;
    double score;
    int flags;
} Record;

typedef struct {
    Record rows[DB_MAX_RECORDS];
    int count;
    int next_id;
} RecordTable;

typedef struct {
    int bucket_head[DB_HASH_BUCKETS];
    int next[DB_MAX_RECORDS];
    int row_of[DB_MAX_RECORDS];
    int used[DB_MAX_RECORDS];
    int count;
    int collisions;
    int probes;
} NameIndex;

typedef struct {
    int order[DB_MAX_ROWS];
    int size;
} ScoreIndex;

typedef struct {
    RecordTable table;
    NameIndex names;
    ScoreIndex scores;
    long inserts;
    long updates;
    long deletes;
    long queries;
} Database;

typedef struct {
    int row;
    int id;
    double score;
    int flags;
} QueryHit;

typedef struct {
    QueryHit hits[DB_MAX_QUERY_ROWS];
    int count;
    int truncated;
} QueryResult;

typedef struct {
    int matched;
    int scanned;
} MaskCount;

typedef struct {
    unsigned char *bytes;
    int length;
    int capacity;
} ByteBuffer;

typedef struct {
    int ok;
    int records;
    int mismatches;
} RoundTrip;

/* ------------------------------------------------------------------ */
/* small string helpers                                               */
/* ------------------------------------------------------------------ */

static int str_copy(char *dst, size_t cap, const char *src)
{
    size_t n;

    if (dst == NULL || src == NULL || cap == 0) {
        return DB_ERR_ARG;
    }
    n = strlen(src);
    if (n + 1 > cap) {
        n = cap - 1;
    }
    memcpy(dst, src, n);
    dst[n] = '\0';
    return DB_OK;
}

static int str_copy_n(char *dst, size_t cap, const char *src, size_t n)
{
    if (dst == NULL || src == NULL || cap == 0) {
        return DB_ERR_ARG;
    }
    if (n + 1 > cap) {
        n = cap - 1;
    }
    memcpy(dst, src, n);
    dst[n] = '\0';
    return DB_OK;
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

static int str_equals(const char *a, const char *b)
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

static int str_split_at(const char *s, char sep, char *left, size_t left_cap,
                         char *right, size_t right_cap)
{
    const char *hit;
    size_t n;

    if (s == NULL || left == NULL || right == NULL) {
        return DB_ERR_ARG;
    }
    hit = strchr(s, sep);
    if (hit == NULL) {
        str_copy(left, left_cap, "");
        str_copy(right, right_cap, s);
        return DB_ERR_NOTFOUND;
    }
    n = (size_t)(hit - s);
    str_copy_n(left, left_cap, s, n);
    str_copy(right, right_cap, hit + 1);
    return DB_OK;
}

/* ------------------------------------------------------------------ */
/* number parsing helpers                                             */
/* ------------------------------------------------------------------ */

static int parse_int(const char *s, int *out)
{
    const char *p;
    int sign;
    long value;

    if (s == NULL || out == NULL) {
        return 0;
    }
    p = s;
    while (*p != '\0' && isspace((unsigned char)*p)) {
        p++;
    }
    if (*p == '\0') {
        return 0;
    }
    sign = 1;
    if (*p == '-') {
        sign = -1;
        p++;
    } else if (*p == '+') {
        p++;
    }
    if (!isdigit((unsigned char)*p)) {
        return 0;
    }
    value = 0;
    while (isdigit((unsigned char)*p)) {
        value = value * 10 + (*p - '0');
        if (value > 1000000000L) {
            value = 1000000000L;
        }
        p++;
    }
    *out = (int)(sign * value);
    return 1;
}

static int parse_double(const char *s, double *out)
{
    const char *p;
    double value;
    double frac;
    int negative;
    int digits;

    if (s == NULL || out == NULL) {
        return 0;
    }
    p = s;
    while (*p != '\0' && isspace((unsigned char)*p)) {
        p++;
    }
    if (*p == '\0') {
        return 0;
    }
    negative = 0;
    if (*p == '-') {
        negative = 1;
        p++;
    } else if (*p == '+') {
        p++;
    }
    value = 0.0;
    digits = 0;
    while (isdigit((unsigned char)*p)) {
        value = value * 10.0 + (double)(*p - '0');
        p++;
        digits++;
    }
    if (*p == '.') {
        p++;
        frac = 0.1;
        while (isdigit((unsigned char)*p)) {
            value += (double)(*p - '0') * frac;
            frac *= 0.1;
            p++;
            digits++;
        }
    }
    if (digits == 0) {
        return 0;
    }
    *out = negative ? -value : value;
    return 1;
}

static int parse_range(const char *s, double *low, double *high)
{
    const char *dots;
    char left[64];
    char right[64];
    size_t n;

    if (s == NULL || low == NULL || high == NULL) {
        return 0;
    }
    dots = strstr(s, "..");
    if (dots == NULL) {
        return 0;
    }
    n = (size_t)(dots - s);
    if (n > sizeof left - 1) {
        n = sizeof left - 1;
    }
    str_copy_n(left, sizeof left, s, n);
    str_copy(right, sizeof right, dots + 2);
    if (!parse_double(left, low) || !parse_double(right, high)) {
        return 0;
    }
    return 1;
}

/* ------------------------------------------------------------------ */
/* deterministic random source                                        */
/* ------------------------------------------------------------------ */

static unsigned int lcg_next(unsigned int *state)
{
    *state = (*state) * 1103515245u + 12345u;
    return (*state >> 16) & 0x7fffu;
}

static double lcg_unit(unsigned int *state)
{
    return (double)(lcg_next(state) % 1000u) / 1000.0;
}

/* ------------------------------------------------------------------ */
/* byte buffer helpers                                                */
/* ------------------------------------------------------------------ */

static void buffer_init(ByteBuffer *buf, int capacity)
{
    buf->bytes = (unsigned char *)malloc((size_t)capacity);
    buf->length = 0;
    buf->capacity = (buf->bytes != NULL) ? capacity : 0;
}

static void buffer_free(ByteBuffer *buf)
{
    if (buf == NULL) {
        return;
    }
    free(buf->bytes);
    buf->bytes = NULL;
    buf->length = 0;
    buf->capacity = 0;
}

static int buffer_reserve(ByteBuffer *buf, int extra)
{
    unsigned char *grown;
    int wanted;

    if (buf == NULL || buf->bytes == NULL) {
        return DB_ERR_STATE;
    }
    if (buf->length + extra <= buf->capacity) {
        return DB_OK;
    }
    wanted = buf->capacity * 2;
    while (wanted < buf->length + extra) {
        wanted *= 2;
    }
    grown = (unsigned char *)realloc(buf->bytes, (size_t)wanted);
    if (grown == NULL) {
        return DB_ERR_FULL;
    }
    buf->bytes = grown;
    buf->capacity = wanted;
    return DB_OK;
}

static int buffer_put(ByteBuffer *buf, const void *data, int len)
{
    if (buf == NULL || data == NULL || len < 0) {
        return DB_ERR_ARG;
    }
    if (buffer_reserve(buf, len) != DB_OK) {
        return DB_ERR_FULL;
    }
    memcpy(buf->bytes + buf->length, data, (size_t)len);
    buf->length += len;
    return DB_OK;
}

static int buffer_put_int(ByteBuffer *buf, int value)
{
    unsigned char raw[4];

    raw[0] = (unsigned char)(value & 0xff);
    raw[1] = (unsigned char)((value >> 8) & 0xff);
    raw[2] = (unsigned char)((value >> 16) & 0xff);
    raw[3] = (unsigned char)((value >> 24) & 0xff);
    return buffer_put(buf, raw, 4);
}

static int buffer_put_double(ByteBuffer *buf, double value)
{
    unsigned char raw[8];
    unsigned long long bits;
    int i;

    memcpy(&bits, &value, sizeof bits);
    for (i = 0; i < 8; i++) {
        raw[i] = (unsigned char)((bits >> (i * 8)) & 0xffULL);
    }
    return buffer_put(buf, raw, 8);
}

static int buffer_get_int(const unsigned char *data, int *out)
{
    unsigned int value;

    if (data == NULL || out == NULL) {
        return DB_ERR_ARG;
    }
    value = (unsigned int)data[0] | ((unsigned int)data[1] << 8) |
            ((unsigned int)data[2] << 16) | ((unsigned int)data[3] << 24);
    *out = (int)value;
    return DB_OK;
}

static int buffer_get_double(const unsigned char *data, double *out)
{
    unsigned long long bits;
    int i;

    if (data == NULL || out == NULL) {
        return DB_ERR_ARG;
    }
    bits = 0ULL;
    for (i = 7; i >= 0; i--) {
        bits = (bits << 8) | (unsigned long long)data[i];
    }
    memcpy(out, &bits, sizeof(double));
    return DB_OK;
}

static void hex_dump(const unsigned char *data, int length, int max_bytes)
{
    int i;
    int limit;

    if (data == NULL) {
        return;
    }
    limit = (length < max_bytes) ? length : max_bytes;
    for (i = 0; i < limit; i += 16) {
        int j;
        printf("  %04x  ", i);
        for (j = 0; j < 16; j++) {
            if (i + j < limit) {
                printf("%02x ", data[i + j]);
            } else {
                printf("   ");
            }
        }
        printf(" |");
        for (j = 0; j < 16 && i + j < limit; j++) {
            unsigned char c = data[i + j];
            if (c >= 32 && c < 127) {
                putchar((int)c);
            } else {
                putchar('.');
            }
        }
        printf("|\n");
    }
}

/* ------------------------------------------------------------------ */
/* name hash index                                                    */
/* ------------------------------------------------------------------ */

static unsigned int name_hash(const char *name)
{
    unsigned int h = 2166136261u;
    int i;

    if (name == NULL) {
        return 0u;
    }
    for (i = 0; name[i] != '\0'; i++) {
        h ^= (unsigned char)name[i];
        h *= 16777619u;
    }
    return h;
}

static void name_index_init(NameIndex *index)
{
    int i;

    for (i = 0; i < DB_HASH_BUCKETS; i++) {
        index->bucket_head[i] = -1;
    }
    for (i = 0; i < DB_MAX_RECORDS; i++) {
        index->next[i] = -1;
        index->used[i] = 0;
    }
    index->count = 0;
    index->collisions = 0;
    index->probes = 0;
}

static int name_index_put(NameIndex *index, const char *name, int row)
{
    unsigned int bucket;
    int slot;

    if (index == NULL || name == NULL || row < 0 || row >= DB_MAX_RECORDS) {
        return DB_ERR_ARG;
    }
    bucket = name_hash(name) % (unsigned int)DB_HASH_BUCKETS;
    if (index->bucket_head[bucket] >= 0) {
        index->collisions++;
    }
    for (slot = 0; slot < DB_MAX_RECORDS; slot++) {
        if (index->used[slot]) {
            continue;
        }
        index->used[slot] = 1;
        index->row_of[slot] = row;
        index->next[slot] = index->bucket_head[bucket];
        index->bucket_head[bucket] = slot;
        index->count++;
        return DB_OK;
    }
    return DB_ERR_FULL;
}

static int name_index_find(NameIndex *index, const RecordTable *table, const char *name)
{
    unsigned int bucket;
    int slot;
    int guard;

    if (index == NULL || table == NULL || name == NULL) {
        return -1;
    }
    bucket = name_hash(name) % (unsigned int)DB_HASH_BUCKETS;
    slot = index->bucket_head[bucket];
    guard = 0;
    while (slot >= 0 && guard < DB_MAX_RECORDS) {
        index->probes++;
        if (index->row_of[slot] < table->count &&
            str_equals(table->rows[index->row_of[slot]].name, name)) {
            return index->row_of[slot];
        }
        slot = index->next[slot];
        guard++;
    }
    return -1;
}

static int name_index_repoint(NameIndex *index, int old_row, int new_row)
{
    int slot;

    if (index == NULL) {
        return DB_ERR_ARG;
    }
    for (slot = 0; slot < DB_MAX_RECORDS; slot++) {
        if (index->used[slot] && index->row_of[slot] == old_row) {
            index->row_of[slot] = new_row;
        }
    }
    return DB_OK;
}

static int name_index_remove(NameIndex *index, const RecordTable *table, const char *name)
{
    unsigned int bucket;
    int slot;
    int prev;
    int guard;

    if (index == NULL || table == NULL || name == NULL) {
        return DB_ERR_NOTFOUND;
    }
    bucket = name_hash(name) % (unsigned int)DB_HASH_BUCKETS;
    prev = -1;
    slot = index->bucket_head[bucket];
    guard = 0;
    while (slot >= 0 && guard < DB_MAX_RECORDS) {
        if (index->row_of[slot] < table->count &&
            str_equals(table->rows[index->row_of[slot]].name, name)) {
            index->used[slot] = 0;
            index->count--;
            if (prev < 0) {
                index->bucket_head[bucket] = index->next[slot];
            } else {
                index->next[prev] = index->next[slot];
            }
            index->next[slot] = -1;
            return DB_OK;
        }
        prev = slot;
        slot = index->next[slot];
        guard++;
    }
    return DB_ERR_NOTFOUND;
}

/* ------------------------------------------------------------------ */
/* ordered score index                                                */
/* ------------------------------------------------------------------ */

static void score_index_init(ScoreIndex *index)
{
    index->size = 0;
}

static int score_compare(const RecordTable *table, int row_a, int row_b)
{
    double sa = table->rows[row_a].score;
    double sb = table->rows[row_b].score;

    if (sa < sb) {
        return -1;
    }
    if (sa > sb) {
        return 1;
    }
    if (table->rows[row_a].id < table->rows[row_b].id) {
        return -1;
    }
    if (table->rows[row_a].id > table->rows[row_b].id) {
        return 1;
    }
    return 0;
}

/* binary search: returns the position where row should be inserted */
static int score_find_position(const ScoreIndex *index, const RecordTable *table, int row)
{
    int low;
    int high;

    low = 0;
    high = index->size;
    while (low < high) {
        int mid = (low + high) / 2;
        if (score_compare(table, index->order[mid], row) < 0) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    return low;
}

static int score_index_insert(ScoreIndex *index, const RecordTable *table, int row)
{
    int pos;
    int i;

    if (index == NULL || table == NULL) {
        return DB_ERR_ARG;
    }
    if (index->size >= DB_MAX_ROWS) {
        return DB_ERR_FULL;
    }
    pos = score_find_position(index, table, row);
    for (i = index->size; i > pos; i--) {
        index->order[i] = index->order[i - 1];
    }
    index->order[pos] = row;
    index->size++;
    return DB_OK;
}

static int score_index_remove(ScoreIndex *index, const RecordTable *table, int row)
{
    int i;

    if (index == NULL || table == NULL) {
        return DB_ERR_ARG;
    }
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

static void score_index_rebuild(ScoreIndex *index, const RecordTable *table)
{
    int i;
    int j;

    index->size = 0;
    for (i = 0; i < table->count; i++) {
        for (j = index->size; j > 0; j--) {
            if (score_compare(table, index->order[j - 1], i) <= 0) {
                break;
            }
            index->order[j] = index->order[j - 1];
        }
        index->order[j] = i;
        if (index->size < DB_MAX_ROWS) {
            index->size++;
        }
    }
}

static int score_index_verify(const ScoreIndex *index, const RecordTable *table)
{
    int i;

    for (i = 1; i < index->size; i++) {
        if (score_compare(table, index->order[i - 1], index->order[i]) > 0) {
            return i;
        }
    }
    return -1;
}

static int score_index_rank(const ScoreIndex *index, int row)
{
    int i;

    for (i = 0; i < index->size; i++) {
        if (index->order[i] == row) {
            return i;
        }
    }
    return -1;
}

/* ------------------------------------------------------------------ */
/* record table primitives                                            */
/* ------------------------------------------------------------------ */

static void table_init(RecordTable *table)
{
    int i;

    for (i = 0; i < DB_MAX_RECORDS; i++) {
        table->rows[i].name[0] = '\0';
        table->rows[i].id = 0;
        table->rows[i].score = 0.0;
        table->rows[i].flags = 0;
    }
    table->count = 0;
    table->next_id = 1;
}

static int table_find_by_id(const RecordTable *table, int id)
{
    int i;

    for (i = 0; i < table->count; i++) {
        if (table->rows[i].id == id) {
            return i;
        }
    }
    return -1;
}

static int table_find_by_name(const RecordTable *table, const char *name)
{
    int i;

    if (name == NULL) {
        return -1;
    }
    for (i = 0; i < table->count; i++) {
        if (str_equals(table->rows[i].name, name)) {
            return i;
        }
    }
    return -1;
}

static void print_record(const Record *record, int index)
{
    printf("  [%3d] id=%-4d name=%-12s score=%9.4f flags=0x%02x\n",
           index, record->id, record->name, record->score, record->flags);
}

static void print_header(const char *title)
{
    printf("=== %s ===\n", title);
}

/* ------------------------------------------------------------------ */
/* database level operations                                          */
/* ------------------------------------------------------------------ */

static void db_init(Database *db)
{
    table_init(&db->table);
    name_index_init(&db->names);
    score_index_init(&db->scores);
    db->inserts = 0;
    db->updates = 0;
    db->deletes = 0;
    db->queries = 0;
}

static int db_insert(Database *db, const char *name, double score, int flags, int *out_id)
{
    int row;
    int id;

    if (db == NULL || name == NULL) {
        return DB_ERR_ARG;
    }
    if (db->table.count >= DB_MAX_RECORDS) {
        return DB_ERR_FULL;
    }
    if (table_find_by_name(&db->table, name) >= 0) {
        return DB_ERR_STATE;
    }
    id = db->table.next_id;
    db->table.next_id++;
    row = db->table.count;
    str_copy(db->table.rows[row].name, DB_NAME_LEN, name);
    db->table.rows[row].id = id;
    db->table.rows[row].score = score;
    db->table.rows[row].flags = flags;
    db->table.count++;
    name_index_put(&db->names, name, row);
    score_index_insert(&db->scores, &db->table, row);
    db->inserts++;
    if (out_id != NULL) {
        *out_id = id;
    }
    return DB_OK;
}

static int db_find_by_id(const Database *db, int id, Record *out)
{
    int row;

    if (db == NULL || out == NULL) {
        return DB_ERR_ARG;
    }
    row = table_find_by_id(&db->table, id);
    if (row < 0) {
        return DB_ERR_NOTFOUND;
    }
    *out = db->table.rows[row];
    return DB_OK;
}

static int db_find_by_name(const Database *db, const char *name, Record *out)
{
    int row;

    if (db == NULL || out == NULL || name == NULL) {
        return DB_ERR_ARG;
    }
    row = table_find_by_name(&db->table, name);
    if (row < 0) {
        return DB_ERR_NOTFOUND;
    }
    *out = db->table.rows[row];
    return DB_OK;
}

static int db_update_score(Database *db, int id, double score)
{
    int row;

    if (db == NULL) {
        return DB_ERR_ARG;
    }
    row = table_find_by_id(&db->table, id);
    if (row < 0) {
        return DB_ERR_NOTFOUND;
    }
    score_index_remove(&db->scores, &db->table, row);
    db->table.rows[row].score = score;
    score_index_insert(&db->scores, &db->table, row);
    db->updates++;
    return DB_OK;
}

static int db_update_flags(Database *db, int id, int flags)
{
    int row;

    if (db == NULL) {
        return DB_ERR_ARG;
    }
    row = table_find_by_id(&db->table, id);
    if (row < 0) {
        return DB_ERR_NOTFOUND;
    }
    db->table.rows[row].flags = flags;
    db->updates++;
    return DB_OK;
}

static int db_update_name(Database *db, int id, const char *name)
{
    int row;

    if (db == NULL || name == NULL) {
        return DB_ERR_ARG;
    }
    row = table_find_by_id(&db->table, id);
    if (row < 0) {
        return DB_ERR_NOTFOUND;
    }
    name_index_remove(&db->names, &db->table, db->table.rows[row].name);
    str_copy(db->table.rows[row].name, DB_NAME_LEN, name);
    name_index_put(&db->names, name, row);
    db->updates++;
    return DB_OK;
}

static int db_delete_by_id(Database *db, int id)
{
    int row;
    int last;

    if (db == NULL) {
        return DB_ERR_ARG;
    }
    row = table_find_by_id(&db->table, id);
    if (row < 0) {
        return DB_ERR_NOTFOUND;
    }
    name_index_remove(&db->names, &db->table, db->table.rows[row].name);
    score_index_remove(&db->scores, &db->table, row);
    last = db->table.count - 1;
    if (row != last) {
        db->table.rows[row] = db->table.rows[last];
        name_index_repoint(&db->names, last, row);
    }
    db->table.rows[last].name[0] = '\0';
    db->table.rows[last].id = 0;
    db->table.rows[last].score = 0.0;
    db->table.rows[last].flags = 0;
    db->table.count--;
    score_index_rebuild(&db->scores, &db->table);
    db->deletes++;
    return DB_OK;
}

static int db_count(const Database *db)
{
    if (db == NULL) {
        return 0;
    }
    return db->table.count;
}

/* ------------------------------------------------------------------ */
/* query engine                                                       */
/* ------------------------------------------------------------------ */

static void result_init(QueryResult *result)
{
    result->count = 0;
    result->truncated = 0;
}

static void result_add(QueryResult *result, const RecordTable *table, int row)
{
    if (row < 0 || row >= table->count) {
        return;
    }
    if (result->count >= DB_MAX_QUERY_ROWS) {
        result->truncated = 1;
        return;
    }
    result->hits[result->count].row = row;
    result->hits[result->count].id = table->rows[row].id;
    result->hits[result->count].score = table->rows[row].score;
    result->hits[result->count].flags = table->rows[row].flags;
    result->count++;
}

static int query_get(Database *db, int id, QueryResult *result)
{
    int row;

    if (db == NULL || result == NULL) {
        return DB_ERR_ARG;
    }
    result_init(result);
    row = table_find_by_id(&db->table, id);
    if (row < 0) {
        return DB_ERR_NOTFOUND;
    }
    result_add(result, &db->table, row);
    db->queries++;
    return DB_OK;
}

static int query_by_name(Database *db, const char *name, QueryResult *result)
{
    int row;

    if (db == NULL || result == NULL || name == NULL) {
        return DB_ERR_ARG;
    }
    result_init(result);
    row = name_index_find(&db->names, &db->table, name);
    if (row < 0) {
        return DB_ERR_NOTFOUND;
    }
    result_add(result, &db->table, row);
    db->queries++;
    return DB_OK;
}

static int query_range(Database *db, double low, double high, QueryResult *result)
{
    int i;

    if (db == NULL || result == NULL) {
        return DB_ERR_ARG;
    }
    result_init(result);
    for (i = 0; i < db->scores.size; i++) {
        int row = db->scores.order[i];
        double score = db->table.rows[row].score;
        if (score < low) {
            continue;
        }
        if (score > high) {
            break;
        }
        result_add(result, &db->table, row);
    }
    db->queries++;
    return result->count;
}

static int query_top_k(Database *db, int k, QueryResult *result)
{
    int i;
    int taken;

    if (db == NULL || result == NULL || k < 0) {
        return DB_ERR_ARG;
    }
    result_init(result);
    taken = 0;
    for (i = db->scores.size - 1; i >= 0 && taken < k; i--) {
        result_add(result, &db->table, db->scores.order[i]);
        taken++;
    }
    db->queries++;
    return result->count;
}

static int query_count_mask(Database *db, int mask, MaskCount *out)
{
    int i;

    if (db == NULL || out == NULL) {
        return DB_ERR_ARG;
    }
    out->matched = 0;
    out->scanned = 0;
    for (i = 0; i < db->table.count; i++) {
        out->scanned++;
        if ((db->table.rows[i].flags & mask) == mask && mask != 0) {
            out->matched++;
        }
    }
    db->queries++;
    return out->matched;
}

static void print_result(const QueryResult *result)
{
    int i;

    if (result == NULL) {
        return;
    }
    printf("  rows=%d truncated=%d\n", result->count, result->truncated);
    for (i = 0; i < result->count; i++) {
        printf("    id=%-4d score=%9.4f flags=0x%02x row=%d\n",
               result->hits[i].id, result->hits[i].score,
               result->hits[i].flags, result->hits[i].row);
    }
}

static int query_parse(Database *db, const char *text, QueryResult *result, MaskCount *mask_out)
{
    char verb[32];
    char rest[128];
    int rc;

    if (db == NULL || text == NULL || result == NULL) {
        return DB_ERR_ARG;
    }
    result_init(result);
    if (str_split_at(text, ' ', verb, sizeof verb, rest, sizeof rest) != DB_OK) {
        return DB_ERR_ARG;
    }
    str_trim(verb);
    str_trim(rest);
    if (str_equals(verb, "GET")) {
        char key[64];
        char value[64];
        int id;
        if (str_split_at(rest, '=', key, sizeof key, value, sizeof value) != DB_OK) {
            return DB_ERR_ARG;
        }
        if (!parse_int(value, &id)) {
            return DB_ERR_ARG;
        }
        rc = query_get(db, id, result);
        return rc;
    }
    if (str_equals(verb, "RANGE")) {
        char key[64];
        char value[64];
        double low;
        double high;
        if (str_split_at(rest, '=', key, sizeof key, value, sizeof value) != DB_OK) {
            return DB_ERR_ARG;
        }
        if (!parse_range(value, &low, &high)) {
            return DB_ERR_ARG;
        }
        return query_range(db, low, high, result);
    }
    if (str_equals(verb, "TOP")) {
        int k = 0;
        if (!parse_int(rest, &k)) {
            k = 0;
        }
        return query_top_k(db, k, result);
    }
    if (str_equals(verb, "COUNT")) {
        int mask = 0;
        if (mask_out == NULL) {
            return DB_ERR_ARG;
        }
        mask_out->matched = 0;
        mask_out->scanned = 0;
        if (str_starts_with(rest, "where ")) {
            const char *tail = rest + 6;
            const char *amp = strchr(tail, '&');
            if (amp != NULL && !parse_int(amp + 1, &mask)) {
                return DB_ERR_ARG;
            }
        }
        return query_count_mask(db, mask, mask_out);
    }
    return DB_ERR_NOTFOUND;
}

/* ------------------------------------------------------------------ */
/* serialization                                                      */
/* ------------------------------------------------------------------ */

static int serialize_table(const Database *db, ByteBuffer *buf)
{
    int i;

    if (db == NULL || buf == NULL) {
        return DB_ERR_ARG;
    }
    buf->length = 0;
    if (buffer_put(buf, DB_SERIAL_HEADER, DB_SERIAL_HEADER_LEN) != DB_OK) {
        return DB_ERR_FULL;
    }
    if (buffer_put_int(buf, db->table.count) != DB_OK) {
        return DB_ERR_FULL;
    }
    for (i = 0; i < db->table.count; i++) {
        const Record *record = &db->table.rows[i];
        char name_field[DB_NAME_LEN];
        int n = (int)strlen(record->name);
        if (n > DB_NAME_LEN - 1) {
            n = DB_NAME_LEN - 1;
        }
        memset(name_field, 0, sizeof name_field);
        memcpy(name_field, record->name, (size_t)n);
        if (buffer_put(buf, name_field, DB_NAME_LEN) != DB_OK) {
            return DB_ERR_FULL;
        }
        if (buffer_put_int(buf, record->id) != DB_OK) {
            return DB_ERR_FULL;
        }
        if (buffer_put_double(buf, record->score) != DB_OK) {
            return DB_ERR_FULL;
        }
        if (buffer_put_int(buf, record->flags) != DB_OK) {
            return DB_ERR_FULL;
        }
    }
    return DB_OK;
}

static int deserialize_table(const unsigned char *data, int length, RecordTable *table)
{
    int count;
    int offset;
    int i;

    if (data == NULL || table == NULL) {
        return DB_ERR_ARG;
    }
    if (length < DB_SERIAL_HEADER_LEN + 4) {
        return DB_ERR_ARG;
    }
    if (memcmp(data, DB_SERIAL_HEADER, DB_SERIAL_HEADER_LEN) != 0) {
        return DB_ERR_STATE;
    }
    if (buffer_get_int(data + DB_SERIAL_HEADER_LEN, &count) != DB_OK) {
        return DB_ERR_ARG;
    }
    if (count < 0 || count > DB_MAX_RECORDS) {
        return DB_ERR_STATE;
    }
    if (length < DB_SERIAL_HEADER_LEN + 4 + count * DB_RECORD_BYTES) {
        return DB_ERR_STATE;
    }
    table_init(table);
    offset = DB_SERIAL_HEADER_LEN + 4;
    for (i = 0; i < count; i++) {
        const unsigned char *p = data + offset;
        int id;
        int flags;
        double score;
        if (buffer_get_int(p + DB_NAME_LEN, &id) != DB_OK) {
            return DB_ERR_ARG;
        }
        if (buffer_get_double(p + DB_NAME_LEN + 4, &score) != DB_OK) {
            return DB_ERR_ARG;
        }
        if (buffer_get_int(p + DB_NAME_LEN + 12, &flags) != DB_OK) {
            return DB_ERR_ARG;
        }
        memcpy(table->rows[i].name, p, DB_NAME_LEN);
        table->rows[i].name[DB_NAME_LEN - 1] = '\0';
        table->rows[i].id = id;
        table->rows[i].score = score;
        table->rows[i].flags = flags;
        offset += DB_RECORD_BYTES;
    }
    table->count = count;
    table->next_id = count + 1;
    return DB_OK;
}

static int compare_tables(const RecordTable *a, const RecordTable *b)
{
    int i;

    if (a == NULL || b == NULL) {
        return 0;
    }
    if (a->count != b->count) {
        return 1;
    }
    for (i = 0; i < a->count; i++) {
        if (a->rows[i].id != b->rows[i].id) {
            return 1;
        }
        if (!str_equals(a->rows[i].name, b->rows[i].name)) {
            return 1;
        }
        if (fabs(a->rows[i].score - b->rows[i].score) > 1e-9) {
            return 1;
        }
        if (a->rows[i].flags != b->rows[i].flags) {
            return 1;
        }
    }
    return 0;
}

static int print_table_diff(const RecordTable *a, const RecordTable *b)
{
    int i;
    int diffs = 0;

    if (a == NULL || b == NULL) {
        return 0;
    }
    if (a->count != b->count) {
        printf("  count differs: %d vs %d\n", a->count, b->count);
        return 1;
    }
    for (i = 0; i < a->count; i++) {
        if (a->rows[i].id != b->rows[i].id ||
            !str_equals(a->rows[i].name, b->rows[i].name) ||
            fabs(a->rows[i].score - b->rows[i].score) > 1e-9 ||
            a->rows[i].flags != b->rows[i].flags) {
            printf("  row %d differs:\n", i);
            print_record(&a->rows[i], i);
            print_record(&b->rows[i], i);
            diffs++;
            if (diffs >= 5) {
                break;
            }
        }
    }
    return diffs;
}

static RoundTrip roundtrip_check(Database *db, ByteBuffer *buf)
{
    RecordTable restored;
    RoundTrip report;

    report.ok = 0;
    report.records = 0;
    report.mismatches = 0;
    if (serialize_table(db, buf) != DB_OK) {
        return report;
    }
    if (deserialize_table(buf->bytes, buf->length, &restored) != DB_OK) {
        return report;
    }
    report.records = restored.count;
    report.mismatches = compare_tables(&db->table, &restored);
    if (report.mismatches != 0) {
        print_table_diff(&db->table, &restored);
    }
    report.ok = (report.mismatches == 0) ? 1 : 0;
    return report;
}

/* ------------------------------------------------------------------ */
/* demo data                                                          */
/* ------------------------------------------------------------------ */

static int build_demo_data(Database *db, int wanted)
{
    unsigned int seed = 20261021u;
    char name[DB_NAME_LEN];
    int i;

    for (i = 0; i < wanted; i++) {
        double score = lcg_unit(&seed) * 100.0;
        int flags = DB_FLAG_ACTIVE;
        int id = 0;
        if ((i % 3) == 0) {
            flags |= DB_FLAG_VIP;
        }
        if ((i % 7) == 0) {
            flags |= DB_FLAG_LOCKED;
        }
        if ((i % 11) == 0) {
            flags |= DB_FLAG_ARCHIVED;
        }
        sprintf(name, "user_%02d", i);
        if (db_insert(db, name, score, flags, &id) != DB_OK) {
            return i;
        }
    }
    return wanted;
}

/* ------------------------------------------------------------------ */
/* main                                                               */
/* ------------------------------------------------------------------ */

int main(void)
{
    Database db;
    ByteBuffer buffer;
    QueryResult result;
    MaskCount mask_count;
    RoundTrip report;
    Record record;
    int i;
    int rc;
    int affected;

    db_init(&db);
    buffer_init(&buffer, 4096);
    print_header("insert 60 records");
    affected = build_demo_data(&db, 60);
    printf("  inserted=%d total_rows=%d\n", affected, db_count(&db));

    print_header("update 10 records");
    affected = 0;
    for (i = 0; i < 10; i++) {
        int id = i * 5 + 1;
        if (db_update_score(&db, id, 10.0 + (double)i * 2.5) == DB_OK) {
            affected++;
        }
    }
    printf("  updated=%d total_rows=%d score_index=%d\n", affected, db_count(&db), db.scores.size);

    print_header("update flags and names");
    affected = 0;
    for (i = 0; i < 4; i++) {
        int id = i * 9 + 3;
        if (db_update_flags(&db, id, DB_FLAG_ACTIVE | DB_FLAG_VIP) == DB_OK) {
            affected++;
        }
    }
    printf("  flags_updated=%d\n", affected);
    affected = 0;
    for (i = 0; i < 3; i++) {
        char renamed[DB_NAME_LEN];
        int id = i * 13 + 4;
        sprintf(renamed, "renamed_%02d", i);
        if (db_update_name(&db, id, renamed) == DB_OK) {
            affected++;
        }
    }
    printf("  names_updated=%d\n", affected);
    rc = db_find_by_id(&db, 4, &record);
    printf("  db_find_by_id(4) rc=%d name=%s score=%.4f\n", rc, record.name, record.score);
    rc = query_by_name(&db, "renamed_00", &result);
    printf("  query_by_name(renamed_00) rc=%d rows=%d\n", rc, result.count);
    if (rc == DB_OK) {
        print_record(&db.table.rows[result.hits[0].row], result.hits[0].row);
    }
    printf("  rank_of_row_0=%d\n", score_index_rank(&db.scores, 0));

    print_header("delete 5 records");
    affected = 0;
    for (i = 0; i < 5; i++) {
        int id = i * 7 + 2;
        if (db_delete_by_id(&db, id) == DB_OK) {
            affected++;
        }
    }
    printf("  deleted=%d total_rows=%d score_index=%d\n", affected, db_count(&db), db.scores.size);

    print_header("query GET id=12");
    rc = query_get(&db, 12, &result);
    printf("  rc=%d\n", rc);
    print_result(&result);

    print_header("score index integrity");
    printf("  entries=%d first_break=%d\n", db.scores.size,
           score_index_verify(&db.scores, &db.table));
    for (i = 0; i < 10 && i < db.scores.size; i++) {
        int row = db.scores.order[i];
        printf("    pos=%2d row=%3d id=%-4d score=%9.4f\n",
               i, row, db.table.rows[row].id, db.table.rows[row].score);
    }

    print_header("query RANGE score=20..40");
    rc = query_range(&db, 20.0, 40.0, &result);
    printf("  rc=%d\n", rc);
    print_result(&result);

    print_header("query TOP 5 by score");
    rc = query_top_k(&db, 5, &result);
    printf("  rc=%d\n", rc);
    print_result(&result);

    print_header("query COUNT where flags&2");
    rc = query_count_mask(&db, DB_FLAG_VIP, &mask_count);
    printf("  rc=%d matched=%d scanned=%d\n", rc, mask_count.matched, mask_count.scanned);

    print_header("query parser");
    {
        const char *scripts[4];
        scripts[0] = "GET id=30";
        scripts[1] = "RANGE score=50..70";
        scripts[2] = "TOP 3";
        scripts[3] = "COUNT where flags&4";
        for (i = 0; i < 4; i++) {
            rc = query_parse(&db, scripts[i], &result, &mask_count);
            printf("  script=[%s] rc=%d rows=%d\n", scripts[i], rc, result.count);
        }
    }

    print_header("name index lookup");
    rc = db_find_by_name(&db, "user_03", &record);
    printf("  lookup user_03 rc=%d id=%d score=%.4f\n", rc, record.id, record.score);
    rc = name_index_find(&db.names, &db.table, "user_03");
    printf("  hash index row=%d probes=%d collisions=%d entries=%d\n",
           rc, db.names.probes, db.names.collisions, db.names.count);

    print_header("serialization");
    rc = serialize_table(&db, &buffer);
    printf("  serialized rc=%d bytes=%d\n", rc, buffer.length);
    hex_dump(buffer.bytes, buffer.length, 64);
    report = roundtrip_check(&db, &buffer);
    printf("  roundtrip ok=%d records=%d mismatches=%d\n",
           report.ok, report.records, report.mismatches);

    print_header("statistics");
    printf("  inserts=%ld updates=%ld deletes=%ld queries=%ld\n",
           db.inserts, db.updates, db.deletes, db.queries);
    printf("  total_rows=%d score_index_entries=%d hash_index_entries=%d\n",
           db_count(&db), db.scores.size, db.names.count);
    printf("  hash_collisions=%d hash_probes=%d\n", db.names.collisions, db.names.probes);

    buffer_free(&buffer);
    print_header("done");
    return 0;
}
