/* minigit.c —— 迷你 Git：内容寻址存储 + 提交历史
 *
 * 编译: gcc -Wall -O2 -o minigit minigit.c
 * 用法:
 *   ./minigit init
 *   ./minigit add <文件>...
 *   ./minigit commit <消息>
 *   ./minigit log
 *   ./minigit cat <哈希>
 *   ./minigit status
 *
 * 与真实 git 的差异:
 *   - 不压缩对象（真实 git 用 zlib）
 *   - 每次提交是一个 tree，不做子目录
 *   - 用 .minigit/HEAD 代替 refs/heads 分支
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

/* <sys/stat.h> 里的 mkdir，自己声明 */
extern int mkdir(const char *pathname, unsigned int mode);

#define REPO      ".minigit"
#define HASH_HEX  40
#define MAX_FILES 128

/* ================================================================
 * 1. SHA-1：内容寻址的核心
 *
 *    任何一段字节，进去是 160 位指纹出来。
 *    git 之所以能"看一眼内容就知道变没变"，靠的就是它。
 * ================================================================ */
static uint32_t rol(uint32_t x, int n)
{
    return (x << n) | (x >> (32 - n));
}

static void sha1_block(uint32_t h[5], const unsigned char *p)
{
    uint32_t w[80];
    for (int i = 0; i < 16; i++) {
        w[i] = ((uint32_t)p[i*4]     << 24)
             | ((uint32_t)p[i*4 + 1] << 16)
             | ((uint32_t)p[i*4 + 2] <<  8)
             | ((uint32_t)p[i*4 + 3]);
    }
    for (int i = 16; i < 80; i++)
        w[i] = rol(w[i-3] ^ w[i-8] ^ w[i-14] ^ w[i-16], 1);

    uint32_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4];
    for (int i = 0; i < 80; i++) {
        uint32_t f, k;
        if      (i < 20) { f = (b & c) | (~b & d);          k = 0x5A827999; }
        else if (i < 40) { f = b ^ c ^ d;                    k = 0x6ED9EBA1; }
        else if (i < 60) { f = (b & c) | (b & d) | (c & d);  k = 0x8F1BBCDC; }
        else             { f = b ^ c ^ d;                    k = 0xCA62C1D6; }

        uint32_t t = rol(a, 5) + f + e + k + w[i];
        e = d; d = c; c = rol(b, 30); b = a; a = t;
    }
    h[0] += a; h[1] += b; h[2] += c; h[3] += d; h[4] += e;
}

static void sha1_hash(const void *data, size_t len, unsigned char out[20])
{
    uint32_t h[5] = { 0x67452301, 0xEFCDAB89, 0x98BADCFE,
                      0x10325476, 0xC3D2E1F0 };

    const unsigned char *p = data;
    size_t remaining = len;

    /* 整块处理 */
    while (remaining >= 64) {
        sha1_block(h, p);
        p += 64;
        remaining -= 64;
    }

    /* 尾部 + 填充 */
    unsigned char tail[128] = {0};
    memcpy(tail, p, remaining);
    tail[remaining] = 0x80;

    size_t total = remaining + 1;
    while ((total % 64) != 56) tail[total++] = 0;

    uint64_t bits = (uint64_t)len * 8;
    for (int i = 0; i < 8; i++)
        tail[total++] = (unsigned char)(bits >> (56 - i * 8));

    for (size_t i = 0; i < total; i += 64)
        sha1_block(h, tail + i);

    for (int i = 0; i < 5; i++) {
        out[i*4    ] = (unsigned char)(h[i] >> 24);
        out[i*4 + 1] = (unsigned char)(h[i] >> 16);
        out[i*4 + 2] = (unsigned char)(h[i] >>  8);
        out[i*4 + 3] = (unsigned char)(h[i]);
    }
}

static void hex_encode(const unsigned char *b, int n, char *out)
{
    static const char *H = "0123456789abcdef";
    for (int i = 0; i < n; i++) {
        out[i*2]     = H[b[i] >> 4];
        out[i*2 + 1] = H[b[i] & 15];
    }
    out[n*2] = '\0';
}

static void hash_to_hex(const void *data, size_t len, char out[HASH_HEX + 1])
{
    unsigned char d[20];
    sha1_hash(data, len, d);
    hex_encode(d, 20, out);
}

/* ================================================================
 * 2. 对象存储
 *
 *    路径: .minigit/objects/XX/YYYY...
 *    XX 是哈希的前两个十六进制字符，YYYY... 是剩下 38 个。
 *    这样每个目录下最多 256 个对象，避免一个目录塞几万个文件。
 *
 *    为什么这么设计？——**内容即地址**。
 *    你把同样内容再 add 一次，算出的哈希一模一样，
 *    自然就写到了同一个文件，等于自动去重。
 * ================================================================ */
static void ensure_dirs(void)
{
    mkdir(REPO, 0755);
    mkdir(REPO "/objects", 0755);
}

static void object_write(const char *hash, const void *data, size_t len)
{
    char dir[64], path[128];
    snprintf(dir,  sizeof(dir),  REPO "/objects/%c%c", hash[0], hash[1]);
    mkdir(dir, 0755);
    snprintf(path, sizeof(path), "%s/%s", dir, hash + 2);

    FILE *fp = fopen(path, "wb");
    if (!fp) { perror(path); exit(1); }
    fwrite(data, 1, len, fp);
    fclose(fp);
}

static char *object_read(const char *hash, size_t *out_len)
{
    char path[128];
    snprintf(path, sizeof(path), REPO "/objects/%c%c/%s",
             hash[0], hash[1], hash + 2);

    FILE *fp = fopen(path, "rb");
    if (!fp) return NULL;

    fseek(fp, 0, SEEK_END);
    long len = ftell(fp);
    fseek(fp, 0, SEEK_SET);

    char *buf = (char *)malloc((size_t)len + 1);
    if (!buf) { fclose(fp); return NULL; }

    if (fread(buf, 1, (size_t)len, fp) != (size_t)len) {
        free(buf); fclose(fp); return NULL;
    }
    buf[len] = '\0';
    *out_len = (size_t)len;
    fclose(fp);
    return buf;
}

/* ================================================================
 * 3. 索引（暂存区）
 * ================================================================ */
typedef struct {
    char hash[HASH_HEX + 1];
    char fname[256];
} IdxEntry;

static int load_index(IdxEntry *entries, int max)
{
    FILE *fp = fopen(REPO "/index", "r");
    if (!fp) return 0;

    int n = 0;
    char line[512];
    while (n < max && fgets(line, sizeof(line), fp)) {
        if (sscanf(line, "%40s %255s", entries[n].hash, entries[n].fname) == 2)
            n++;
    }
    fclose(fp);
    return n;
}

static void save_index(const IdxEntry *entries, int n)
{
    FILE *fp = fopen(REPO "/index", "w");
    if (!fp) { perror("index"); exit(1); }
    for (int i = 0; i < n; i++)
        fprintf(fp, "%s %s\n", entries[i].hash, entries[i].fname);
    fclose(fp);
}

/* ================================================================
 * 4. 命令
 * ================================================================ */
static void cmd_init(void)
{
    ensure_dirs();
    printf("初始化空仓库: %s/\n", REPO);
}

static void cmd_add(int argc, char **argv)
{
    if (argc == 0) { fprintf(stderr, "用法: minigit add <文件>...\n"); return; }

    IdxEntry entries[MAX_FILES];
    int n = load_index(entries, MAX_FILES);

    for (int i = 0; i < argc; i++) {
        const char *fname = argv[i];
        FILE *fp = fopen(fname, "rb");
        if (!fp) { perror(fname); continue; }

        fseek(fp, 0, SEEK_END);
        long len = ftell(fp);
        fseek(fp, 0, SEEK_SET);

        char *data = (char *)malloc((size_t)len);
        if (fread(data, 1, (size_t)len, fp) != (size_t)len) {
            free(data); fclose(fp); continue;
        }
        fclose(fp);

        char hash[HASH_HEX + 1];
        hash_to_hex(data, (size_t)len, hash);
        object_write(hash, data, (size_t)len);

        int found = -1;
        for (int j = 0; j < n; j++)
            if (!strcmp(entries[j].fname, fname)) { found = j; break; }

        if (found >= 0) {
            strcpy(entries[found].hash, hash);
        } else if (n < MAX_FILES) {
            strcpy(entries[n].hash, hash);
            strncpy(entries[n].fname, fname, 255);
            entries[n].fname[255] = '\0';
            n++;
        }
        printf("add '%s'  blob %s\n", fname, hash);
        free(data);
    }
    save_index(entries, n);
}

static void cmd_commit(const char *msg)
{
    if (!msg) { fprintf(stderr, "用法: minigit commit <消息>\n"); return; }

    IdxEntry entries[MAX_FILES];
    int n = load_index(entries, MAX_FILES);
    if (n == 0) { fprintf(stderr, "没有暂存的文件\n"); return; }

    /* ---- 构建 tree 对象 ---- */
    char tree_buf[1 << 16];
    size_t tlen = 0;
    for (int i = 0; i < n; i++) {
        tlen += (size_t)sprintf(tree_buf + tlen, "%s %s\n",
                                entries[i].hash, entries[i].fname);
    }

    char tree_hash[HASH_HEX + 1];
    hash_to_hex(tree_buf, tlen, tree_hash);
    object_write(tree_hash, tree_buf, tlen);

    /* ---- 读父提交 ---- */
    char parent[HASH_HEX + 1] = "";
    FILE *fp = fopen(REPO "/HEAD", "r");
    if (fp) {
        if (fgets(parent, sizeof(parent), fp)) {
            char *nl = strchr(parent, '\n');
            if (nl) *nl = '\0';
        }
        fclose(fp);
    }

    /* ---- 构建 commit 对象 ---- */
    char cbuf[4096];
    int  clen;
    if (parent[0])
        clen = snprintf(cbuf, sizeof(cbuf),
                        "tree %s\nparent %s\n%s\n", tree_hash, parent, msg);
    else
        clen = snprintf(cbuf, sizeof(cbuf),
                        "tree %s\n%s\n", tree_hash, msg);

    char commit_hash[HASH_HEX + 1];
    hash_to_hex(cbuf, (size_t)clen, commit_hash);
    object_write(commit_hash, cbuf, (size_t)clen);

    /* ---- 更新 HEAD ---- */
    fp = fopen(REPO "/HEAD", "w");
    if (!fp) { perror("HEAD"); return; }
    fprintf(fp, "%s\n", commit_hash);
    fclose(fp);

    printf("[%s] %s\n", commit_hash, msg);
}

static void cmd_log(void)
{
    char cur[HASH_HEX + 1] = "";
    FILE *fp = fopen(REPO "/HEAD", "r");
    if (!fp) { printf("还没有提交\n"); return; }
    if (fgets(cur, sizeof(cur), fp)) {
        char *nl = strchr(cur, '\n');
        if (nl) *nl = '\0';
    }
    fclose(fp);

    while (cur[0]) {
        size_t len;
        char *data = object_read(cur, &len);
        if (!data) break;

        char tree[HASH_HEX + 1]    = "";
        char parent[HASH_HEX + 1]  = "";
        char message[512]          = "";

        char *p   = data;
        char *end = data + len;

        if (p < end) {
            char *nl = memchr(p, '\n', (size_t)(end - p));
            if (!nl) nl = end;
            sscanf(p, "tree %40s", tree);
            p = (nl < end) ? nl + 1 : end;
        }
        if (p < end && !strncmp(p, "parent ", 7)) {
            char *nl = memchr(p, '\n', (size_t)(end - p));
            if (!nl) nl = end;
            sscanf(p, "parent %40s", parent);
            p = (nl < end) ? nl + 1 : end;
        }
        if (p < end) {
            size_t mlen = (size_t)(end - p);
            if (mlen >= sizeof(message)) mlen = sizeof(message) - 1;
            memcpy(message, p, mlen);
            message[mlen] = '\0';
            char *nl = strchr(message, '\n');
            if (nl) *nl = '\0';
        }

        printf("commit %s\n", cur);
        printf("  tree   %s\n", tree);
        if (parent[0]) printf("  parent %s\n", parent);
        printf("  %s\n\n", message);

        free(data);
        strcpy(cur, parent);
    }
}

static void cmd_cat(const char *hash)
{
    if (!hash) { fprintf(stderr, "用法: minigit cat <哈希>\n"); return; }
    size_t len;
    char *data = object_read(hash, &len);
    if (!data) { fprintf(stderr, "找不到对象 %s\n", hash); return; }
    fwrite(data, 1, len, stdout);
    if (len == 0 || data[len - 1] != '\n') putchar('\n');
    free(data);
}

static void cmd_status(void)
{
    IdxEntry entries[MAX_FILES];
    int n = load_index(entries, MAX_FILES);
    if (n == 0) { printf("暂存区为空\n"); return; }
    printf("已暂存的变更:\n");
    for (int i = 0; i < n; i++)
        printf("  新文件: %s  (%s)\n", entries[i].fname, entries[i].hash);
}

/* ================================================================
 * 5. main
 * ================================================================ */
static void usage(const char *p)
{
    fprintf(stderr,
        "用法:\n"
        "  %s init\n"
        "  %s add <文件>...\n"
        "  %s commit <消息>\n"
        "  %s log\n"
        "  %s cat <哈希>\n"
        "  %s status\n", p, p, p, p, p, p);
}

int main(int argc, char **argv)
{
    if (argc < 2) { usage(argv[0]); return 1; }

    const char *cmd = argv[1];

    if      (!strcmp(cmd, "init"))   cmd_init();
    else if (!strcmp(cmd, "add"))    cmd_add(argc - 2, argv + 2);
    else if (!strcmp(cmd, "commit")) cmd_commit(argc > 2 ? argv[2] : NULL);
    else if (!strcmp(cmd, "log"))    cmd_log();
    else if (!strcmp(cmd, "cat"))    cmd_cat(argc > 2 ? argv[2] : NULL);
    else if (!strcmp(cmd, "status")) cmd_status();
    else { usage(argv[0]); return 1; }

    return 0;
}
