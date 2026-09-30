/* mini_json.c —— JSON 解析器 + 路径查询（迷你 jq）
 *
 * 编译: gcc -Wall -O2 -o mini_json mini_json.c
 * 用法: ./mini_json <路径> [文件] [-c]
 *
 * 路径语法:
 *   .              根对象
 *   .foo           取属性
 *   .foo.bar       属性链
 *   .items[0]      数组索引
 *   .items[]       数组迭代（每个元素各打印一行）
 *   .users[].name  迭代后再取属性
 *   -c             紧凑输出（默认美化）
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

/* ================================================================
 * 1. JSON 值
 * ================================================================ */
typedef enum { J_NULL, J_BOOL, J_NUM, J_STR, J_ARR, J_OBJ } JType;

typedef struct JValue JValue;
struct JValue {
    JType type;
    union {
        int    b;
        double n;
        struct { char  *s; int len; } str;
        struct { JValue **items; int count; } arr;
        struct { char **keys; JValue **vals; int count; } obj;
    } u;
};

static JValue *j_new(JType t)
{
    JValue *v = (JValue *)calloc(1, sizeof(JValue));
    if (!v) { perror("calloc"); exit(1); }
    v->type = t;
    return v;
}

static JValue *j_null(void)    { return j_new(J_NULL); }
static JValue *j_bool(int b)   { JValue *v = j_new(J_BOOL); v->u.b = b; return v; }
static JValue *j_num(double n) { JValue *v = j_new(J_NUM);  v->u.n = n; return v; }

static JValue *j_str(const char *s, int len)
{
    JValue *v = j_new(J_STR);
    v->u.str.s = (char *)malloc((size_t)len + 1);
    memcpy(v->u.str.s, s, (size_t)len);
    v->u.str.s[len] = '\0';
    v->u.str.len = len;
    return v;
}

/* ================================================================
 * 2. 解析器（递归下降）
 * ================================================================ */
typedef struct { const char *s; int p; } P;

static JValue *parse_value(P *ps);

static void skip_ws(P *ps)
{
    while (ps->s[ps->p] == ' '  || ps->s[ps->p] == '\t' ||
           ps->s[ps->p] == '\n' || ps->s[ps->p] == '\r')
        ps->p++;
}

/* Unicode 码点 → UTF-8 */
static void utf8_encode(char *buf, int *n, unsigned cp)
{
    if (cp < 0x80) {
        buf[(*n)++] = (char)cp;
    } else if (cp < 0x800) {
        buf[(*n)++] = (char)(0xC0 | (cp >> 6));
        buf[(*n)++] = (char)(0x80 | (cp & 0x3F));
    } else if (cp < 0x10000) {
        buf[(*n)++] = (char)(0xE0 | (cp >> 12));
        buf[(*n)++] = (char)(0x80 | ((cp >> 6) & 0x3F));
        buf[(*n)++] = (char)(0x80 | (cp & 0x3F));
    } else {
        buf[(*n)++] = (char)(0xF0 | (cp >> 18));
        buf[(*n)++] = (char)(0x80 | ((cp >> 12) & 0x3F));
        buf[(*n)++] = (char)(0x80 | ((cp >>  6) & 0x3F));
        buf[(*n)++] = (char)(0x80 | (cp & 0x3F));
    }
}

/* 读一个原始字符串（含转义处理），返回 malloc 的内存 */
static char *parse_raw_string(P *ps, int *out_len)
{
    if (ps->s[ps->p] != '"') return NULL;
    ps->p++;

    int cap = 32, n = 0;
    char *buf = (char *)malloc((size_t)cap);

    while (ps->s[ps->p] && ps->s[ps->p] != '"') {
        if (n + 8 >= cap) {
            cap *= 2;
            buf = (char *)realloc(buf, (size_t)cap);
        }
        char c = ps->s[ps->p++];
        if (c == '\\') {
            char e = ps->s[ps->p++];
            switch (e) {
            case 'n':  buf[n++] = '\n'; break;
            case 't':  buf[n++] = '\t'; break;
            case 'r':  buf[n++] = '\r'; break;
            case 'b':  buf[n++] = '\b'; break;
            case 'f':  buf[n++] = '\f'; break;
            case '"':  buf[n++] = '"';  break;
            case '\\': buf[n++] = '\\'; break;
            case '/':  buf[n++] = '/';  break;
            case 'u': {
                unsigned cp = 0;
                for (int i = 0; i < 4; i++) {
                    char h = ps->s[ps->p++];
                    cp = cp * 16 + (unsigned)(h <= '9' ? h - '0'
                                             : (tolower((unsigned char)h) - 'a' + 10));
                }
                utf8_encode(buf, &n, cp);
                break;
            }
            default: buf[n++] = e;
            }
        } else {
            buf[n++] = c;
        }
    }
    if (ps->s[ps->p] == '"') ps->p++;
    buf[n] = '\0';
    *out_len = n;
    return buf;
}

static JValue *parse_string(P *ps)
{
    int len;
    char *s = parse_raw_string(ps, &len);
    JValue *v = j_str(s, len);
    free(s);
    return v;
}

static JValue *parse_number(P *ps)
{
    char *end;
    double d = strtod(ps->s + ps->p, &end);
    ps->p = (int)(end - ps->s);
    return j_num(d);
}

static JValue *parse_array(P *ps)
{
    ps->p++;   /* [ */
    JValue *v = j_new(J_ARR);

    int cap = 4;
    v->u.arr.items = (JValue **)malloc((size_t)cap * sizeof(JValue *));
    v->u.arr.count = 0;

    skip_ws(ps);
    if (ps->s[ps->p] == ']') { ps->p++; return v; }

    for (;;) {
        if (v->u.arr.count >= cap) {
            cap *= 2;
            v->u.arr.items = (JValue **)realloc(v->u.arr.items,
                                                (size_t)cap * sizeof(JValue *));
        }
        v->u.arr.items[v->u.arr.count++] = parse_value(ps);
        skip_ws(ps);

        char c = ps->s[ps->p];
        if (c == ',') { ps->p++; skip_ws(ps); continue; }
        if (c == ']') { ps->p++; break; }
        break;
    }
    return v;
}

static JValue *parse_object(P *ps)
{
    ps->p++;   /* { */
    JValue *v = j_new(J_OBJ);

    int cap = 4;
    v->u.obj.keys = (char **)malloc((size_t)cap * sizeof(char *));
    v->u.obj.vals = (JValue **)malloc((size_t)cap * sizeof(JValue *));
    v->u.obj.count = 0;

    skip_ws(ps);
    if (ps->s[ps->p] == '}') { ps->p++; return v; }

    for (;;) {
        skip_ws(ps);
        int klen;
        char *key = parse_raw_string(ps, &klen);
        if (!key) break;

        skip_ws(ps);
        if (ps->s[ps->p] == ':') ps->p++;
        skip_ws(ps);

        if (v->u.obj.count >= cap) {
            cap *= 2;
            v->u.obj.keys = (char **)realloc(v->u.obj.keys,
                                             (size_t)cap * sizeof(char *));
            v->u.obj.vals = (JValue **)realloc(v->u.obj.vals,
                                               (size_t)cap * sizeof(JValue *));
        }
        v->u.obj.keys[v->u.obj.count] = key;
        v->u.obj.vals[v->u.obj.count] = parse_value(ps);
        v->u.obj.count++;

        skip_ws(ps);
        char c = ps->s[ps->p];
        if (c == ',') { ps->p++; continue; }
        if (c == '}') { ps->p++; break; }
        break;
    }
    return v;
}

static JValue *parse_value(P *ps)
{
    skip_ws(ps);
    char c = ps->s[ps->p];
    if (c == '{') return parse_object(ps);
    if (c == '[') return parse_array(ps);
    if (c == '"') return parse_string(ps);
    if (c == 't' && !strncmp(ps->s + ps->p, "true",  4)) { ps->p += 4; return j_bool(1); }
    if (c == 'f' && !strncmp(ps->s + ps->p, "false", 5)) { ps->p += 5; return j_bool(0); }
    if (c == 'n' && !strncmp(ps->s + ps->p, "null",  4)) { ps->p += 4; return j_null(); }
    return parse_number(ps);
}

/* ================================================================
 * 3. 打印
 * ================================================================ */
static void print_value(FILE *f, const JValue *v, int indent, int pretty);

static void print_ind(FILE *f, int ind)
{
    for (int i = 0; i < ind; i++) fputs("  ", f);
}

static void print_str_escaped(FILE *f, const char *s)
{
    fputc('"', f);
    for (const unsigned char *p = (const unsigned char *)s; *p; p++) {
        switch (*p) {
        case '"':  fputs("\\\"", f); break;
        case '\\': fputs("\\\\", f); break;
        case '\n': fputs("\\n",  f); break;
        case '\t': fputs("\\t",  f); break;
        case '\r': fputs("\\r",  f); break;
        case '\b': fputs("\\b",  f); break;
        case '\f': fputs("\\f",  f); break;
        default:
            if (*p < 0x20) fprintf(f, "\\u%04x", *p);
            else           fputc(*p, f);
        }
    }
    fputc('"', f);
}

static void print_value(FILE *f, const JValue *v, int indent, int pretty)
{
    if (!v) { fputs("null", f); return; }

    switch (v->type) {
    case J_NULL: fputs("null", f); break;
    case J_BOOL: fputs(v->u.b ? "true" : "false", f); break;

    case J_NUM: {
        double d = v->u.n;
        if (d == (double)(long)d) fprintf(f, "%ld", (long)d);
        else                      fprintf(f, "%g",  d);
        break;
    }

    case J_STR:
        print_str_escaped(f, v->u.str.s);
        break;

    case J_ARR:
        fputc('[', f);
        if (v->u.arr.count == 0) { fputc(']', f); break; }
        for (int i = 0; i < v->u.arr.count; i++) {
            if (pretty) { fputc('\n', f); print_ind(f, indent + 1); }
            print_value(f, v->u.arr.items[i], indent + 1, pretty);
            if (i < v->u.arr.count - 1) fputc(',', f);
        }
        if (pretty) { fputc('\n', f); print_ind(f, indent); }
        fputc(']', f);
        break;

    case J_OBJ:
        fputc('{', f);
        if (v->u.obj.count == 0) { fputc('}', f); break; }
        for (int i = 0; i < v->u.obj.count; i++) {
            if (pretty) { fputc('\n', f); print_ind(f, indent + 1); }
            print_str_escaped(f, v->u.obj.keys[i]);
            fputs(pretty ? ": " : ":", f);
            print_value(f, v->u.obj.vals[i], indent + 1, pretty);
            if (i < v->u.obj.count - 1) fputc(',', f);
        }
        if (pretty) { fputc('\n', f); print_ind(f, indent); }
        fputc('}', f);
        break;
    }
}

/* ================================================================
 * 4. 路径查询
 * ================================================================ */
typedef enum { K_KEY, K_IDX, K_ITER } KOpType;

typedef struct {
    KOpType t;
    char    key[128];
    int     idx;
} KOp;

static int parse_path(const char *path, KOp *ops, int max)
{
    int n = 0;
    const char *p = path;

    while (*p && n < max) {
        if (*p == '.') {
            p++;
            if (*p == '\0' || *p == '[' || *p == '.') continue;
            char *q = ops[n].key;
            int   k = 0;
            while (*p && *p != '.' && *p != '[' && k < 127)
                q[k++] = *p++;
            q[k] = '\0';
            ops[n].t = K_KEY;
            n++;
        } else if (*p == '[') {
            p++;
            if (*p == ']') {
                ops[n].t = K_ITER;
                n++;
                p++;
            } else {
                int idx = 0;
                while (isdigit((unsigned char)*p))
                    idx = idx * 10 + (*p++ - '0');
                if (*p == ']') p++;
                ops[n].t   = K_IDX;
                ops[n].idx = idx;
                n++;
            }
        } else {
            p++;
        }
    }
    return n;
}

static JValue *jv_get(const JValue *v, const char *key)
{
    if (!v || v->type != J_OBJ) return NULL;
    for (int i = 0; i < v->u.obj.count; i++)
        if (!strcmp(v->u.obj.keys[i], key)) return v->u.obj.vals[i];
    return NULL;
}

static JValue *jv_at(const JValue *v, int i)
{
    if (!v || v->type != J_ARR) return NULL;
    if (i < 0 || i >= v->u.arr.count) return NULL;
    return v->u.arr.items[i];
}

static void apply_and_print(FILE *f, JValue *v, KOp *ops, int n,
                            int i, int pretty)
{
    if (i >= n) {
        print_value(f, v, 0, pretty);
        fputc('\n', f);
        return;
    }

    if (ops[i].t == K_KEY) {
        apply_and_print(f, jv_get(v, ops[i].key), ops, n, i + 1, pretty);
    } else if (ops[i].t == K_IDX) {
        apply_and_print(f, jv_at(v, ops[i].idx), ops, n, i + 1, pretty);
    } else {   /* K_ITER */
        if (v && v->type == J_ARR) {
            for (int k = 0; k < v->u.arr.count; k++)
                apply_and_print(f, v->u.arr.items[k], ops, n, i + 1, pretty);
        }
    }
}

/* ================================================================
 * 5. main
 * ================================================================ */
static void usage(const char *prog)
{
    fprintf(stderr,
        "用法: %s <路径> [文件] [-c]\n"
        "  路径: .foo.bar    .items[0]    .users[].name    .\n"
        "  -c:   紧凑输出（默认美化）\n"
        "  无文件时从 stdin 读取\n", prog);
}

int main(int argc, char **argv)
{
    const char *path = NULL;
    const char *file = NULL;
    int pretty = 1;

    for (int i = 1; i < argc; i++) {
        if      (!strcmp(argv[i], "-c"))  pretty = 0;
        else if (!strcmp(argv[i], "-h") || !strcmp(argv[i], "--help")) {
            usage(argv[0]); return 0;
        }
        else if (!path) path = argv[i];
        else if (!file) file = argv[i];
    }
    if (!path) { usage(argv[0]); return 1; }

    FILE *in = stdin;
    if (file) {
        in = fopen(file, "rb");
        if (!in) { perror(file); return 1; }
    }

    /* 一次读全部 */
    size_t cap = 65536, len = 0;
    char  *buf = (char *)malloc(cap);
    size_t r;
    while ((r = fread(buf + len, 1, cap - len - 1, in)) > 0) {
        len += r;
        if (len + 1 >= cap) {
            cap *= 2;
            buf = (char *)realloc(buf, cap);
        }
    }
    buf[len] = '\0';
    if (file) fclose(in);

    P ps = { buf, 0 };
    JValue *root = parse_value(&ps);

    KOp ops[64];
    int nops = parse_path(path, ops, 64);

    apply_and_print(stdout, root, ops, nops, 0, pretty);

    free(buf);
    /* 简化：进程退出，不递归释放 JValue */
    return 0;
}
