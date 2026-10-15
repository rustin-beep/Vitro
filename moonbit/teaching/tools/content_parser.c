/* content_parser.c —— 教学内容真源解析器（#125 批 A，2026-10-15）。
 *
 * 地位：本文件是**随包发布的引擎侧资产**（moonbit/** 入 mooncakes），
 * 由 Vitro 自己编译运行——自己吃自己狗粮；兼作常驻语料：CI 以
 * vitro ≡ clang 双臂对拍本文件，即编译器常驻自测（AGENTS #14 同款）。
 *
 * 三 schema 模式（argv[1] 选，缺省/未知 = 红）：
 *   trap          stdin=content/trap_messages.md  → assets/trap_messages_gen.mbt
 *   suggestions   stdin=content/suggestions.md    → assets/suggestions_gen.mbt
 *   builtin_notes stdin=content/builtin_notes.md  → assets/builtin_notes_gen.mbt
 *
 * 真源 schema（`## key` 节式**纯文本**切段——markdown 语法不生效）：
 *   - `## <key>` 起一节；节标题后须空行；重复键 = 红；键字符集按模式
 *     （trap 含大写码段 [A-Za-z_0-9]，另两模式 [a-z_0-9]）；
 *   - 头部字段（连续非空行，可省略；有头部字段时其后须空行再进正文）：
 *       trap     placeholders: <名,...>   ends_with_newline: <1|2>
 *                （占位符集须与正文 {name} 双向相等——contract_wbtest 锚；
 *                 尾换行显式记数——禁靠尾部空行暗示，与节间分隔歧义）
 *       builtin  count_note: <整句>       param_notes[<i>]: <整句>
 *                （显式参数位、缺位=空串——typeck 按位索引，fwrite 有洞）
 *       sugg     （无头部字段；正文 v0 单行，空行 = 红）
 *   - 正文：trap = 模板原样（空行=文案里空行；尾部空行至多 1 行=节间分隔）。
 *
 * 产出（stdout）：@generated 的 .mbt；验收判据 = 与 #60 双出口期
 * .json.mbt **除头注外逐字节一致**（载体迁移判据语义零变化）。
 * 注意：数组换行形态以 moon fmt 为准——驱动管线 = 本输出 → moon fmt →
 * 与入库产物比对（生成器契约第 2 条；trap 实测 fmt 恒等）。
 *
 * 用法：
 *   scripts/bin/vitro run moonbit/teaching/tools/content_parser.c \
 *     -i moonbit/teaching/content/trap_messages.md -- trap > out.mbt
 *
 * fail loud：未知头部字段 / 重复键 / 空正文 / 条数 ≠ 基线 / 行超长 /
 * 尾空行噪声 / 未知模式一律 stderr + exit(1)，禁静默 default。
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_LINE   4096
#define MAX_KEY    64
#define MAX_KEYS   64
#define MAX_PH     8
#define MAX_PHNAME 32
#define MAX_SLOTS  16
#define SLOT_CAP   512
#define TXT_CAP    16384
#define EXPECTED_TRAP    45
#define EXPECTED_SUGG    43
#define EXPECTED_BUILTIN 12

/* 模式 */
#define MODE_TRAP    0
#define MODE_SUGG    1
#define MODE_BUILTIN 2

/* 状态机：PRE(前导) → HEADBLANK(标题后须空行) → HEAD(头部字段收集)
 * → BODY(正文)。 */
#define ST_PRE       0
#define ST_HEADBLANK 1
#define ST_HEAD      2
#define ST_BODY      3

/* ── 状态 ─────────────────────────────────────────────────────────── */

static int g_mode = MODE_TRAP;
static int g_expected = 0;

static char line_buf[MAX_LINE];              /* 当前物理行（CRLF 已归一） */
static char key_buf[MAX_KEY];                /* 当前节键 */
static char keys[MAX_KEYS][MAX_KEY];         /* 已见键（重复检查 + sugg 枚举臂序） */
static int  entry_count = 0;
static int  line_no = 0;                     /* 物理行号（报错定位） */

static char txt[TXT_CAP];                    /* 当前节正文（原文未转义） */
static size_t txt_len = 0;

static char ph_names[MAX_PH][MAX_PHNAME];    /* trap: placeholders */
static int  ph_count = 0;
static int  trailing_nl = 0;                 /* trap: ends_with_newline 记数 */

static char count_note[SLOT_CAP];            /* builtin: count_note（原文） */
static char slots[MAX_SLOTS][SLOT_CAP];      /* builtin: param_notes 定位槽 */
static int  slot_used[MAX_SLOTS];
static int  slot_max = -1;                   /* 最大已写槽位（-1=无） */

static char arr_buf[TXT_CAP];                /* sugg: 数组条目缓冲（枚举先行，两段发射） */
static size_t arr_len = 0;

static void fail(const char *what) {
    fprintf(stderr, "content_parser: FAIL: 行 %d 附近: %s\n", line_no, what);
    exit(1);
}

/* ── 基元 ─────────────────────────────────────────────────────────── */

/* 读一行；CRLF 归一（clang Windows 文本模式 / autocrlf 双防）。返回 1=有行 0=EOF */
static int read_line(void) {
    int c, n = 0;
    c = fgetc(stdin);
    if (c == EOF) {
        return 0;
    }
    while (c != EOF && c != '\n') {
        if (c != '\r') {
            if (n + 2 >= MAX_LINE) {
                fail("行超长");
            }
            line_buf[n] = (char)c;
            n++;
        }
        c = fgetc(stdin);
    }
    line_buf[n] = (char)'\0';
    line_no++;
    return 1;
}

static int is_blank(const char *s) {
    while (*s == ' ' || *s == '\t') {
        s++;
    }
    return *s == '\0';
}

static int starts_with(const char *s, const char *pre) {
    size_t n = strlen(pre);
    return strncmp(s, pre, n) == 0;
}

/* 原文追加（维持 NUL 终止——缓冲跨节复用，漏终止符会让 fputs 吐残留
 * 【首版实测：输出翻倍 + 跨条目污染，2026-10-15】） */
static void txt_append(const char *s) {
    size_t n = strlen(s);
    if (txt_len + n + 2 >= TXT_CAP) {
        fail("正文缓冲区超限");
    }
    memcpy((void *)(txt + txt_len), (const void *)s, n);
    txt_len += n;
    txt[txt_len] = (char)'\0';
}

static void txt_append_ch(char c) {
    if (txt_len + 2 >= TXT_CAP) {
        fail("正文缓冲区超限");
    }
    txt[txt_len] = c;
    txt_len++;
    txt[txt_len] = (char)'\0';
}

/* stdout 直出 MoonBit 转义（\n \t \r \" \\；其余字节原样） */
static void emit_escaped(const char *s) {
    for (; *s != (char)'\0'; s++) {
        unsigned char c = (unsigned char)*s;
        if (c == '\\') {
            fputs("\\\\", stdout);
        } else if (c == '"') {
            fputs("\\\"", stdout);
        } else if (c == '\n') {
            fputs("\\n", stdout);
        } else if (c == '\t') {
            fputs("\\t", stdout);
        } else if (c == '\r') {
            fputs("\\r", stdout);
        } else {
            putchar((int)c);
        }
    }
}

/* ── 头部字段（按模式） ───────────────────────────────────────────── */

/* 值段提取：冒号后去前导空白（真源键后恒一格；多余空白宽容） */
static const char *value_after(const char *line, const char *key) {
    const char *p = line + strlen(key);
    while (*p == ' ' || *p == '\t') {
        p++;
    }
    return p;
}

/* 返回 1 = 是头部字段且已消费；0 = 不是（正文起点） */
static int try_head_line(void) {
    if (g_mode == MODE_TRAP) {
        if (starts_with(line_buf, "placeholders:")) {
            const char *p = value_after(line_buf, "placeholders:");
            ph_count = 0;
            for (;;) {
                const char *end;
                size_t len;
                while (*p == ' ' || *p == '\t') {
                    p++;
                }
                if (*p == '\0') {
                    break;
                }
                end = p;
                while (*end != '\0' && *end != ',') {
                    end++;
                }
                len = (size_t)(end - p);
                while (len > 0 && (p[len - 1] == ' ' || p[len - 1] == '\t')) {
                    len--;
                }
                if (len == 0) {
                    fail("placeholders 有空项");
                }
                if (ph_count >= MAX_PH) {
                    fail("placeholders 超上限");
                }
                if (len >= MAX_PHNAME) {
                    fail("占位符名超长");
                }
                memcpy((void *)ph_names[ph_count], (const void *)p, len);
                ph_names[ph_count][len] = (char)'\0';
                ph_count++;
                if (*end == ',') {
                    p = end + 1;
                } else {
                    break;
                }
            }
            return 1;
        }
        if (starts_with(line_buf, "ends_with_newline:")) {
            const char *p = value_after(line_buf, "ends_with_newline:");
            if (p[0] == '1' && p[1] == '\0') {
                trailing_nl = 1;
            } else if (p[0] == '2' && p[1] == '\0') {
                trailing_nl = 2;
            } else {
                fail("ends_with_newline 取值非法（须 1 或 2；缺省 0）");
            }
            return 1;
        }
        return 0;
    }
    if (g_mode == MODE_BUILTIN) {
        if (starts_with(line_buf, "count_note:")) {
            const char *v = value_after(line_buf, "count_note:");
            if (strlen(v) + 2 >= SLOT_CAP) {
                fail("count_note 超长");
            }
            count_note[0] = (char)'\0';
            memcpy((void *)count_note, (const void *)v, strlen(v) + 1);
            return 1;
        }
        if (starts_with(line_buf, "param_notes[")) {
            const char *p = line_buf + strlen("param_notes[");
            const char *close = strchr(p, ']');
            const char *v;
            int idx = 0;
            if (close == NULL || close[1] != ':') {
                fail("param_notes 须形如 param_notes[<i>]: <整句>");
            }
            while (p < close) {
                if (*p < '0' || *p > '9') {
                    fail("param_notes 槽位非数字");
                }
                idx = idx * 10 + (*p - '0');
                p++;
            }
            if (idx >= MAX_SLOTS) {
                fail("param_notes 槽位超上限");
            }
            if (slot_used[idx]) {
                fail("param_notes 槽位重复");
            }
            slot_used[idx] = 1;
            if (idx > slot_max) {
                slot_max = idx;
            }
            v = close + 2; /* 跳过 ]: */
            while (*v == ' ' || *v == '\t') {
                v++;
            }
            if (strlen(v) + 2 >= SLOT_CAP) {
                fail("param_note 超长");
            }
            slots[idx][0] = (char)'\0';
            memcpy((void *)slots[idx], (const void *)v, strlen(v) + 1);
            return 1;
        }
        return 0;
    }
    return 0; /* MODE_SUGG：无头部字段 */
}

/* ── 键与臂名 ─────────────────────────────────────────────────────── */

static void check_key_charset(const char *k, size_t len) {
    size_t i;
    for (i = 0; i < len; i++) {
        char c = k[i];
        int ok;
        if (g_mode == MODE_TRAP) {
            ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                 (c >= '0' && c <= '9') || c == '_';
        } else {
            ok = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_';
        }
        if (!ok) {
            fail("节标题含非法字符");
        }
    }
}

/* suggestions：snake_case → 枚举臂名（bubble_sort → BubbleSort）。
 * 与 #60 双出口期臂名逐一对应；漏推/拼错 ⇒ map.mbt 43 臂 match 非穷尽红。 */
static void arm_name_into(const char *id, char *out) {
    const char *p = id;
    int cap_next = 1;
    size_t n = 0;
    for (; *p != (char)'\0'; p++) {
        if (*p == '_') {
            cap_next = 1;
            continue;
        }
        if (cap_next && *p >= 'a' && *p <= 'z') {
            out[n] = (char)(*p - 'a' + 'A');
        } else {
            out[n] = *p;
        }
        n++;
        cap_next = 0;
    }
    out[n] = (char)'\0';
}

/* ── sugg 数组缓冲 ────────────────────────────────────────────────── */

static void arr_append(const char *s) {
    size_t n = strlen(s);
    if (arr_len + n + 2 >= TXT_CAP) {
        fail("数组缓冲区超限");
    }
    memcpy((void *)(arr_buf + arr_len), (const void *)s, n);
    arr_len += n;
    arr_buf[arr_len] = (char)'\0';
}

/* ── 发射 ─────────────────────────────────────────────────────────── */

static void emit_header(void) {
    fputs("// @generated by moonbit/teaching/tools/content_parser.c —— 禁手改"
          "（git/diff 工具链按 @generated 识别）。\n", stdout);
    fputs("// 源：moonbit/teaching/content/", stdout);
    if (g_mode == MODE_TRAP) {
        fputs("trap_messages.md", stdout);
    } else if (g_mode == MODE_SUGG) {
        fputs("suggestions.md", stdout);
    } else {
        fputs("builtin_notes.md", stdout);
    }
    fputs("（#125 批 A：md+.c 唯一真源入包，C 解析器自举）\n", stdout);
    fputs("// 再生：scripts/bin/vitro run moonbit/teaching/tools/content_parser.c"
          " -i moonbit/teaching/content/<真源> -- <模式>\n", stdout);
    fputs("// 数组换行形态以 moon fmt 为准（驱动管线：本输出 → moon fmt → 比对）。\n", stdout);
    fputs("\n", stdout);
}

static void emit_prologue(void) {
    if (g_mode == MODE_TRAP) {
        fputs("///|\npub struct TrapMessage {\n  template : String\n"
              "  placeholders : Array[String]\n}\n\n///|\n", stdout);
        fputs("pub let trap_messages : Map[String, TrapMessage] = {\n", stdout);
    } else if (g_mode == MODE_BUILTIN) {
        fputs("///|\npub struct BuiltinNote {\n  count_note : String\n"
              "  param_notes : Array[String]\n}\n\n///|\n", stdout);
        fputs("pub let builtin_notes : Map[String, BuiltinNote] = {\n", stdout);
    }
    /* MODE_SUGG：枚举收齐后于 epilogue 发射（枚举先于数组，两段形态） */
}

static void emit_entry(void) {
    int i;
    fputs("  \"", stdout);
    emit_escaped(key_buf);
    if (g_mode == MODE_TRAP) {
        fputs("\": TrapMessage::{\n    template: \"", stdout);
        emit_escaped(txt);
        fputs("\",\n    placeholders: [", stdout);
        for (i = 0; i < ph_count; i++) {
            if (i > 0) {
                fputs(", ", stdout);
            }
            putchar((int)'"');
            emit_escaped(ph_names[i]);
            putchar((int)'"');
        }
        fputs("],\n  },\n", stdout);
    } else {
        fputs("\": BuiltinNote::{\n    count_note: \"", stdout);
        emit_escaped(count_note);
        fputs("\",\n    param_notes: [", stdout);
        for (i = 0; i <= slot_max; i++) {
            if (i > 0) {
                fputs(", ", stdout);
            }
            putchar((int)'"');
            emit_escaped(slots[i]);
            putchar((int)'"');
        }
        fputs("],\n  },\n", stdout);
    }
}

/* suggestions：数组条目进缓冲（枚举先行，epilogue 统一发射） */
static void emit_entry_sugg(void) {
    char arm[MAX_KEY];
    char seg[MAX_LINE];
    const char *p = txt;
    arm_name_into(key_buf, arm);
    arr_append("  ");
    arr_append(arm);
    arr_append("(\n    (\n");
    for (;;) {
        const char *nl = strchr(p, '\n');
        size_t n = (nl != NULL) ? (size_t)(nl - p) : strlen(p);
        if (n > 0) {
            if (n >= MAX_LINE) {
                fail("正文行超长");
            }
            memcpy((void *)seg, (const void *)p, n);
            seg[n] = (char)'\0';
            arr_append("      #| ");
            arr_append(seg);
            arr_append("\n");
        }
        if (nl == NULL) {
            break;
        }
        p = nl + 1;
    }
    arr_append("    ),\n  ),\n");
}

/* 节收束（按模式） */
static void flush_entry(void) {
    int k;
    if (txt_len == 0 && g_mode != MODE_BUILTIN) {
        fail("节正文为空");
    }
    if (g_mode == MODE_TRAP) {
        for (k = 0; k < trailing_nl; k++) {
            txt_append_ch('\n');
        }
        emit_entry();
    } else if (g_mode == MODE_SUGG) {
        emit_entry_sugg();
    } else {
        emit_entry();
    }
    entry_count++;
}

/* ── 主流程 ───────────────────────────────────────────────────────── */

int main(int argc, char **argv) {
    int st = ST_PRE;
    int started = 0;        /* 正文是否已出现非空行 */
    int pending_blank = 0;  /* 正文尾部待定空行数（>1 = 红） */
    int head_seen = 0;      /* 本节是否已见头部字段 */

    if (argc < 2) {
        fprintf(stderr, "content_parser: FAIL: 缺模式参数"
                "（-- trap | suggestions | builtin_notes）\n");
        return 1;
    }
    if (strcmp(argv[1], "trap") == 0) {
        g_mode = MODE_TRAP;
        g_expected = EXPECTED_TRAP;
    } else if (strcmp(argv[1], "suggestions") == 0) {
        g_mode = MODE_SUGG;
        g_expected = EXPECTED_SUGG;
    } else if (strcmp(argv[1], "builtin_notes") == 0) {
        g_mode = MODE_BUILTIN;
        g_expected = EXPECTED_BUILTIN;
    } else {
        fprintf(stderr, "content_parser: FAIL: 未知模式 %s\n", argv[1]);
        return 1;
    }

    emit_header();
    emit_prologue();

    for (;;) {
        int has = read_line();
        if (!has || starts_with(line_buf, "## ")) {
            /* 节界（EOF 或下一节标题） */
            if (st == ST_BODY || st == ST_HEAD || st == ST_HEADBLANK) {
                if (entry_count >= g_expected) {
                    fail("条数超基线");
                }
                if (entry_count >= MAX_KEYS) {
                    fail("键表超限");
                }
                memcpy((void *)keys[entry_count], (const void *)key_buf,
                       strlen(key_buf) + 1);
                flush_entry();
            }
            if (!has) {
                break;
            }
            /* 开新节 */
            {
                const char *k = line_buf + 3;
                size_t len = strlen(k);
                int i;
                while (len > 0 && (k[len - 1] == ' ' || k[len - 1] == '\t')) {
                    len--;
                }
                if (len == 0 || len >= MAX_KEY) {
                    fail("节标题非标识符形态");
                }
                check_key_charset(k, len);
                memcpy((void *)key_buf, (const void *)k, len);
                key_buf[len] = (char)'\0';
                for (i = 0; i < entry_count; i++) {
                    if (strcmp(keys[i], key_buf) == 0) {
                        fail("节标题重复");
                    }
                }
            }
            ph_count = 0;
            trailing_nl = 0;
            txt_len = 0;
            txt[0] = (char)'\0';
            count_note[0] = (char)'\0';
            slot_max = -1;
            head_seen = 0;
            started = 0;
            pending_blank = 0;
            {
                int i;
                for (i = 0; i < MAX_SLOTS; i++) {
                    slot_used[i] = 0;
                    slots[i][0] = (char)'\0';
                }
            }
            st = ST_HEADBLANK;
            continue;
        }

        switch (st) {
        case ST_PRE:
            break; /* 前导说明跳过 */
        case ST_HEADBLANK:
            if (!is_blank(line_buf)) {
                fail("节标题后须有空行");
            }
            st = ST_HEAD;
            break;
        case ST_HEAD:
            if (is_blank(line_buf)) {
                st = ST_BODY; /* 头部块结束（该空行 = 与正文的分隔） */
            } else if (try_head_line()) {
                head_seen = 1;
            } else if (head_seen) {
                fail("头部元数据与正文之间须有空行");
            } else if (g_mode == MODE_BUILTIN) {
                fail("builtin 节不应有正文（只有头部字段）");
            } else {
                st = ST_BODY;
                txt_append(line_buf);
                started = 1;
            }
            break;
        case ST_BODY:
            if (is_blank(line_buf)) {
                pending_blank++;
                if (pending_blank > 1) {
                    fail("正文后多于 1 行空行（节间分隔只许 1 行）");
                }
            } else if (g_mode == MODE_SUGG && pending_blank > 0) {
                fail("suggestions 正文出现空行分段（v0 单行口径）");
            } else {
                int j;
                if (pending_blank > 0) {
                    for (j = 0; j < pending_blank + 1; j++) {
                        txt_append_ch('\n');
                    }
                    pending_blank = 0;
                } else if (started) {
                    txt_append_ch('\n');
                }
                txt_append(line_buf);
                started = 1;
            }
            break;
        default:
            fail("状态机漂移");
        }
    }

    if (entry_count != g_expected) {
        fprintf(stderr, "content_parser: FAIL: 条数 %d != 基线 %d"
                "——真源已变更，请人工核对后更新基线并登记差异\n",
                entry_count, g_expected);
        return 1;
    }

    if (g_mode == MODE_TRAP || g_mode == MODE_BUILTIN) {
        fputs("}\n", stdout);
    } else {
        /* MODE_SUGG：枚举 + 数组两段 */
        int i;
        fputs("///|\npub enum AlgoSuggestion {\n", stdout);
        for (i = 0; i < entry_count; i++) {
            char arm[MAX_KEY];
            fputs("  ", stdout);
            arm_name_into(keys[i], arm);
            fputs(arm, stdout);
            fputs("(String)\n", stdout);
        }
        fputs("}\n\n///|\n", stdout);
        fputs("pub let suggestions : Array[AlgoSuggestion] = [\n", stdout);
        fputs(arr_buf, stdout);
        fputs("]\n", stdout);
    }
    return 0;
}
