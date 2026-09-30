/* huffman.c —— Huffman 压缩 / 解压
 *
 * 编译: gcc -Wall -O2 -o huffman huffman.c
 * 用法:
 *   ./huffman c <输入文件> <输出文件.huff>   压缩
 *   ./huffman d <输入文件.huff> <输出文件>   解压
 *
 * 文件格式:
 *   [4 字节] 原始长度
 *   [2 字节] 码表条目数
 *   [N 字节] 码表：(1 字节字符 + 4 字节频率) × N
 *   [...]    压缩后的比特流
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#define MAX_SYMS 256

/* ================================================================
 * 1. Huffman 树节点
 * ================================================================ */
typedef struct Node {
    unsigned char  ch;      /* 叶子节点才有意义 */
    uint32_t       freq;
    struct Node   *left, *right;
} Node;

/* ================================================================
 * 2. 最小堆（按频率排序）
 *
 *    每次都从堆里取出频率最小的两个节点合并，
 *    这是 Huffman 算法的核心操作，用堆让它变成 O(n log n)。
 * ================================================================ */
typedef struct {
    Node   *items[MAX_SYMS];
    int     n;
} Heap;

static void heap_push(Heap *h, Node *node)
{
    int i = h->n++;
    h->items[i] = node;

    while (i > 0) {
        int p = (i - 1) / 2;
        if (h->items[p]->freq <= h->items[i]->freq) break;
        Node *t = h->items[p]; h->items[p] = h->items[i]; h->items[i] = t;
        i = p;
    }
}

static Node *heap_pop(Heap *h)
{
    Node *top = h->items[0];
    h->items[0] = h->items[--h->n];

    int i = 0;
    for (;;) {
        int l = 2*i + 1, r = 2*i + 2, m = i;
        if (l < h->n && h->items[l]->freq < h->items[m]->freq) m = l;
        if (r < h->n && h->items[r]->freq < h->items[m]->freq) m = r;
        if (m == i) break;
        Node *t = h->items[m]; h->items[m] = h->items[i]; h->items[i] = t;
        i = m;
    }
    return top;
}

/* ================================================================
 * 3. 构建 Huffman 树
 * ================================================================ */
static Node *new_node(unsigned char ch, uint32_t freq)
{
    Node *n = (Node *)calloc(1, sizeof(Node));
    n->ch = ch;
    n->freq = freq;
    return n;
}

static Node *build_tree(const uint32_t freq[MAX_SYMS])
{
    Heap h = { .n = 0 };

    for (int i = 0; i < MAX_SYMS; i++)
        if (freq[i] > 0)
            heap_push(&h, new_node((unsigned char)i, freq[i]));

    /* 边界：只有一种字符 */
    if (h.n == 1)
        return heap_pop(&h);

    while (h.n > 1) {
        Node *a = heap_pop(&h);
        Node *b = heap_pop(&h);

        Node *parent = new_node(0, a->freq + b->freq);
        parent->left  = a;
        parent->right = b;

        heap_push(&h, parent);
    }
    return heap_pop(&h);
}

/* ================================================================
 * 4. 生成编码表：遍历树，左=0、右=1
 * ================================================================ */
typedef struct {
    char     bits[64];    /* 最多 256 种符号，码长不会超过 255 位 */
    int      len;
} Code;

static Code g_codes[MAX_SYMS];

static void build_codes(Node *node, char *path, int depth)
{
    if (!node) return;

    if (!node->left && !node->right) {
        /* 叶子 */
        if (depth == 0) {
            /* 只有一种字符的特例：给个长度 1 的码 */
            g_codes[node->ch].bits[0] = '0';
            g_codes[node->ch].len     = 1;
        } else {
            memcpy(g_codes[node->ch].bits, path, (size_t)depth);
            g_codes[node->ch].len = depth;
        }
        return;
    }

    path[depth] = '0';
    build_codes(node->left,  path, depth + 1);
    path[depth] = '1';
    build_codes(node->right, path, depth + 1);
}

/* ================================================================
 * 5. 比特流写入器：把 0/1 攒够 8 个才写一个字节出去
 * ================================================================ */
typedef struct {
    FILE   *fp;
    unsigned char byte;
    int    nbits;         /* 当前字节已经填了几位 */
} BitWriter;

static void bw_init(BitWriter *bw, FILE *fp)
{
    bw->fp    = fp;
    bw->byte  = 0;
    bw->nbits = 0;
}

static void bw_put(BitWriter *bw, int bit)
{
    bw->byte = (unsigned char)((bw->byte << 1) | (bit & 1));
    bw->nbits++;

    if (bw->nbits == 8) {
        fputc(bw->byte, bw->fp);
        bw->byte  = 0;
        bw->nbits = 0;
    }
}

static void bw_flush(BitWriter *bw)
{
    if (bw->nbits > 0) {
        /* 剩下的位左移补齐，凑成一个完整字节 */
        bw->byte <<= (8 - bw->nbits);
        fputc(bw->byte, bw->fp);
        bw->nbits = 0;
    }
}

/* ================================================================
 * 6. 压缩
 * ================================================================ */
static int compress_file(const char *in_name, const char *out_name)
{
    FILE *in = fopen(in_name, "rb");
    if (!in) { perror(in_name); return 1; }

    /* 统计频率 */
    uint32_t freq[MAX_SYMS] = {0};
    uint32_t total = 0;
    int      c;
    while ((c = fgetc(in)) != EOF) {
        freq[(unsigned char)c]++;
        total++;
    }

    if (total == 0) {
        fprintf(stderr, "输入文件为空\n");
        fclose(in);
        return 1;
    }

    /* 建树 + 生成码表 */
    Node *root = build_tree(freq);
    memset(g_codes, 0, sizeof(g_codes));
    char path[256];
    build_codes(root, path, 0);

    /* 写文件头 */
    FILE *out = fopen(out_name, "wb");
    if (!out) { perror(out_name); fclose(in); return 1; }

    fwrite(&total, 4, 1, out);

    uint16_t nsyms = 0;
    for (int i = 0; i < MAX_SYMS; i++)
        if (freq[i] > 0) nsyms++;
    fwrite(&nsyms, 2, 1, out);

    for (int i = 0; i < MAX_SYMS; i++) {
        if (freq[i] > 0) {
            unsigned char ch = (unsigned char)i;
            fwrite(&ch,   1, 1, out);
            fwrite(&freq[i], 4, 1, out);
        }
    }

    /* 写压缩数据 */
    rewind(in);
    BitWriter bw;
    bw_init(&bw, out);

    while ((c = fgetc(in)) != EOF) {
        Code *code = &g_codes[(unsigned char)c];
        for (int i = 0; i < code->len; i++)
            bw_put(&bw, code->bits[i] - '0');
    }
    bw_flush(&bw);

    fclose(in);
    fclose(out);
    return 0;
}

/* ================================================================
 * 7. 解压
 * ================================================================ */
static int decompress_file(const char *in_name, const char *out_name)
{
    FILE *in = fopen(in_name, "rb");
    if (!in) { perror(in_name); return 1; }

    uint32_t total;
    uint16_t nsyms;

    if (fread(&total, 4, 1, in) != 1) { fclose(in); return 1; }
    if (fread(&nsyms, 2, 1, in) != 1) { fclose(in); return 1; }

    /* 读码表并重建 Huffman 树 */
    uint32_t freq[MAX_SYMS] = {0};
    for (int i = 0; i < nsyms; i++) {
        unsigned char ch;
        uint32_t f;
        if (fread(&ch, 1, 1, in) != 1) { fclose(in); return 1; }
        if (fread(&f,  4, 1, in) != 1) { fclose(in); return 1; }
        freq[ch] = f;
    }

    Node *root = build_tree(freq);

    FILE *out = fopen(out_name, "wb");
    if (!out) { perror(out_name); fclose(in); return 1; }

    /* 沿树逐位下降，到底就输出一个字符 */
    Node *cur = root;
    uint32_t written = 0;

    while (written < total) {
        int b = fgetc(in);
        if (b == EOF) break;

        for (int i = 7; i >= 0 && written < total; i--) {
            int bit = (b >> i) & 1;
            cur = bit ? cur->right : cur->left;

            if (!cur) {   /* 数据损坏 */
                fprintf(stderr, "压缩数据损坏\n");
                fclose(in); fclose(out);
                return 1;
            }

            if (!cur->left && !cur->right) {
                fputc(cur->ch, out);
                written++;
                cur = root;
            }
        }
    }

    fclose(in);
    fclose(out);
    return 0;
}

/* ================================================================
 * 8. 辅助：释放树
 * ================================================================ */
static void free_tree(Node *n)
{
    if (!n) return;
    free_tree(n->left);
    free_tree(n->right);
    free(n);
}

/* ================================================================
 * 9. main
 * ================================================================ */
static long file_size(const char *name)
{
    FILE *fp = fopen(name, "rb");
    if (!fp) return -1;
    fseek(fp, 0, SEEK_END);
    long sz = ftell(fp);
    fclose(fp);
    return sz;
}

static void show_stats(const char *orig, const char *huff)
{
    long a = file_size(orig);
    long b = file_size(huff);
    if (a < 0 || b < 0) return;

    printf("  原始大小: %ld 字节\n", a);
    printf("  压缩后:   %ld 字节\n", b);
    if (a > 0) {
        printf("  压缩率:   %.1f%%\n", 100.0 * b / a);
        printf("  节省:     %.1f%%\n", 100.0 * (a - b) / a);
    }
}

int main(int argc, char **argv)
{
    if (argc < 4) {
        fprintf(stderr,
            "用法:\n"
            "  %s c <输入> <输出.huff>    压缩\n"
            "  %s d <输入.huff> <输出>    解压\n",
            argv[0], argv[0]);
        return 1;
    }

    const char *mode = argv[1];
    const char *in   = argv[2];
    const char *out  = argv[3];

    if (mode[0] == 'c') {
        printf("压缩: %s → %s\n", in, out);
        if (compress_file(in, out) != 0) return 1;
        show_stats(in, out);

        /* 顺便验证一下解压是否一致 */
        char verify[] = "/tmp/.huffman_verify.tmp";
        if (decompress_file(out, verify) == 0) {
            long a = file_size(in);
            long b = file_size(verify);
            printf("  验证:    %s\n", a == b ? "✓ 大小一致" : "✗ 大小不同");
        }
    } else if (mode[0] == 'd') {
        printf("解压: %s → %s\n", in, out);
        if (decompress_file(in, out) != 0) return 1;
        printf("  输出大小: %ld 字节\n", file_size(out));
    } else {
        fprintf(stderr, "未知模式: %s\n", mode);
        return 1;
    }

    return 0;
}
