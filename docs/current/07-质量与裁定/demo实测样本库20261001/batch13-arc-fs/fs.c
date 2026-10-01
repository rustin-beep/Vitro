/* fs.c —— 玩具文件系统
 *
 * 编译: gcc -Wall -O2 -std=c11 -o fs fs.c
 * 运行: ./fs
 *
 * 磁盘布局（每块 512 字节，共 1024 块 = 512 KB）:
 *   块 0       超级块
 *   块 1       inode 位图（128 位）
 *   块 2       数据块位图（1024 位）
 *   块 3-18    inode 表（128 个 × 64 字节）
 *   块 19+     数据块（1005 个）
 *
 * 支持:
 *   - 分层目录
 *   - 每个文件最多 8 个直接块（≤ 4 KB）
 *   - 创建 / 读写 / 删除文件
 *   - 创建 / 删除 / 遍历目录
 *   - 硬链接（多个目录项指向同一 inode）
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <assert.h>

/* ================================================================
 * 磁盘布局
 * ================================================================ */
#define BLOCK_SIZE      512
#define N_BLOCKS        1024
#define N_INODES        128
#define N_DIRECT        8
#define ROOT_INO        1
#define MAX_NAME_LEN    27

#define SUPER_BLOCK     0
#define INODE_BITMAP    1
#define BLOCK_BITMAP    2
#define INODE_TABLE     3
#define INODES_PER_BLK  (BLOCK_SIZE / (int)sizeof(Inode))
#define INODE_BLKS      ((N_INODES + INODES_PER_BLK - 1) / INODES_PER_BLK)
#define DATA_START      (INODE_TABLE + INODE_BLKS)
#define N_DATA_BLOCKS   (N_BLOCKS - DATA_START)
#define DIRS_PER_BLOCK  (BLOCK_SIZE / (int)sizeof(DirEntry))

#define INODE_FREE      0
#define INODE_FILE      1
#define INODE_DIR       2

typedef struct {
    uint8_t  type;
    uint8_t  nlinks;
    uint16_t size;
    uint32_t blocks[N_DIRECT];
    uint8_t  _pad[64 - 1 - 1 - 2 - N_DIRECT * 4];
} Inode;

typedef struct {
    char     name[28];
    uint32_t ino;
} DirEntry;

_Static_assert(sizeof(Inode) == 64, "Inode 必须 64 字节");
_Static_assert(sizeof(DirEntry) == 32, "DirEntry 必须 32 字节");

static uint8_t g_disk[N_BLOCKS][BLOCK_SIZE];
static bool    g_mounted     = false;
static long    g_blocks_used = 0;
static long    g_inodes_used = 0;

/* ================================================================
 * 底层：块 I/O
 * ================================================================ */
static void disk_read(uint32_t blk, void *buf) {
    if (blk >= N_BLOCKS) { fprintf(stderr, "read 越界: %u\n", blk); abort(); }
    memcpy(buf, g_disk[blk], BLOCK_SIZE);
}

static void disk_write(uint32_t blk, const void *buf) {
    if (blk >= N_BLOCKS) { fprintf(stderr, "write 越界: %u\n", blk); abort(); }
    memcpy(g_disk[blk], buf, BLOCK_SIZE);
}

/* ================================================================
 * 位图
 * ================================================================ */
static bool inode_bm_test(uint32_t i)  { return (g_disk[INODE_BITMAP][i/8] >> (i%8)) & 1; }
static void inode_bm_set(uint32_t i)   { g_disk[INODE_BITMAP][i/8] |=  (uint8_t)(1u << (i%8)); }
static void inode_bm_clear(uint32_t i) { g_disk[INODE_BITMAP][i/8] &= (uint8_t)~(1u << (i%8)); }

static bool block_bm_test(uint32_t i)  { return (g_disk[BLOCK_BITMAP][i/8] >> (i%8)) & 1; }
static void block_bm_set(uint32_t i)   { g_disk[BLOCK_BITMAP][i/8] |=  (uint8_t)(1u << (i%8)); }
static void block_bm_clear(uint32_t i) { g_disk[BLOCK_BITMAP][i/8] &= (uint8_t)~(1u << (i%8)); }

/* ================================================================
 * Inode 访问
 * ================================================================ */
static Inode *inode_get(uint32_t ino) {
    if (ino == 0 || ino >= N_INODES) return NULL;
    uint32_t blk = INODE_TABLE + ino / INODES_PER_BLK;
    uint32_t off = (ino % INODES_PER_BLK) * sizeof(Inode);
    return (Inode *)&g_disk[blk][off];
}

/* ================================================================
 * 分配 / 释放
 * ================================================================ */
static uint32_t alloc_block(void) {
    for (uint32_t b = DATA_START; b < N_BLOCKS; b++) {
        if (!block_bm_test(b)) {
            block_bm_set(b);
            memset(g_disk[b], 0, BLOCK_SIZE);
            g_blocks_used++;
            return b;
        }
    }
    return 0;
}

static void free_block(uint32_t blk) {
    if (blk < DATA_START || blk >= N_BLOCKS) return;
    if (!block_bm_test(blk)) return;
    block_bm_clear(blk);
    g_blocks_used--;
}

static uint32_t alloc_inode(uint8_t type) {
    for (uint32_t i = ROOT_INO + 1; i < N_INODES; i++) {
        if (!inode_bm_test(i)) {
            inode_bm_set(i);
            Inode *ip = inode_get(i);
            memset(ip, 0, sizeof(*ip));
            ip->type = type;
            ip->nlinks = 1;
            g_inodes_used++;
            return i;
        }
    }
    return 0;
}

static void free_inode(uint32_t ino) {
    inode_bm_clear(ino);
    Inode *ip = inode_get(ino);
    if (ip) memset(ip, 0, sizeof(*ip));
    g_inodes_used--;
}

/* ================================================================
 * 目录操作
 * ================================================================ */
static int dir_nentries(Inode *dp) {
    return dp->size / (int)sizeof(DirEntry);
}

static bool dir_read(Inode *dp, int idx, DirEntry *out) {
    if (idx < 0 || idx >= N_DIRECT * DIRS_PER_BLOCK) return false;
    int b = idx / DIRS_PER_BLOCK;
    int off = (idx % DIRS_PER_BLOCK) * sizeof(DirEntry);
    if (dp->blocks[b] == 0) return false;
    memcpy(out, &g_disk[dp->blocks[b]][off], sizeof(DirEntry));
    return true;
}

static bool dir_write(Inode *dp, int idx, const DirEntry *de) {
    if (idx < 0 || idx >= N_DIRECT * DIRS_PER_BLOCK) return false;
    int b = idx / DIRS_PER_BLOCK;
    int off = (idx % DIRS_PER_BLOCK) * sizeof(DirEntry);
    if (dp->blocks[b] == 0) {
        uint32_t nb = alloc_block();
        if (nb == 0) return false;
        dp->blocks[b] = nb;
    }
    memcpy(&g_disk[dp->blocks[b]][off], de, sizeof(DirEntry));
    return true;
}

static uint32_t dir_lookup(Inode *dp, const char *name) {
    int n = dir_nentries(dp);
    DirEntry de;
    for (int i = 0; i < n; i++) {
        if (dir_read(dp, i, &de) && strcmp(de.name, name) == 0)
            return de.ino;
    }
    return 0;
}

static bool dir_add(Inode *dp, const char *name, uint32_t ino) {
    if (dir_lookup(dp, name) != 0) return false;
    int idx = dir_nentries(dp);
    DirEntry de;
    memset(&de, 0, sizeof(de));
    strncpy(de.name, name, MAX_NAME_LEN);
    de.ino = ino;
    if (!dir_write(dp, idx, &de)) return false;
    dp->size += sizeof(DirEntry);
    return true;
}

static bool dir_remove(Inode *dp, const char *name) {
    int n = dir_nentries(dp);
    DirEntry de;
    for (int i = 0; i < n; i++) {
        if (dir_read(dp, i, &de) && strcmp(de.name, name) == 0) {
            if (i < n - 1) {
                DirEntry last;
                dir_read(dp, n - 1, &last);
                dir_write(dp, i, &last);
            }
            DirEntry empty;
            memset(&empty, 0, sizeof(empty));
            dir_write(dp, n - 1, &empty);
            dp->size -= sizeof(DirEntry);
            return true;
        }
    }
    return false;
}

/* ================================================================
 * 路径解析
 *
 *   返回 inode 号；同时通过 parent_out 返回父目录 inode，
 *   通过 leaf_out 返回最后一段的名字。
 * ================================================================ */
static uint32_t path_resolve(const char *path, uint32_t *parent_out, char *leaf_out) {
    if (parent_out) *parent_out = 0;
    if (leaf_out) leaf_out[0] = '\0';

    if (!path || path[0] != '/') return 0;

    uint32_t cur = ROOT_INO;
    const char *p = path + 1;

    while (*p) {
        char name[MAX_NAME_LEN + 1];
        int n = 0;
        while (*p && *p != '/' && n < MAX_NAME_LEN)
            name[n++] = *p++;
        name[n] = '\0';
        while (*p == '/') p++;

        if (n == 0) continue;

        Inode *dp = inode_get(cur);
        if (!dp || dp->type != INODE_DIR) return 0;

        uint32_t next = dir_lookup(dp, name);

        if (*p == '\0') {
            if (parent_out) *parent_out = cur;
            if (leaf_out) strcpy(leaf_out, name);
            return next;   /* 0 表示最后一段不存在 */
        }

        if (next == 0) return 0;
        Inode *np = inode_get(next);
        if (!np || np->type != INODE_DIR) return 0;
        cur = next;
    }

    if (parent_out) *parent_out = 0;
    if (leaf_out) leaf_out[0] = '\0';
    return cur;   /* 路径是 "/" */
}

/* ================================================================
 * 格式化
 * ================================================================ */
static void fs_format(void) {
    memset(g_disk, 0, sizeof(g_disk));
    g_blocks_used = 0;
    g_inodes_used = 0;

    /* 元数据块标记为已用 */
    for (uint32_t b = 0; b < DATA_START; b++) {
        block_bm_set(b);
        g_blocks_used++;
    }

    /* 根 inode */
    inode_bm_set(ROOT_INO);
    Inode *root = inode_get(ROOT_INO);
    memset(root, 0, sizeof(*root));
    root->type = INODE_DIR;
    root->nlinks = 1;
    g_inodes_used++;

    uint32_t rb = alloc_block();
    root->blocks[0] = rb;

    DirEntry de;
    memset(&de, 0, sizeof(de));
    strcpy(de.name, ".");
    de.ino = ROOT_INO;
    dir_write(root, 0, &de);

    memset(&de, 0, sizeof(de));
    strcpy(de.name, "..");
    de.ino = ROOT_INO;
    dir_write(root, 1, &de);

    root->size = 2 * sizeof(DirEntry);

    g_mounted = true;
    printf("文件系统已格式化:\n");
    printf("  总块数:    %d\n", N_BLOCKS);
    printf("  块大小:    %d 字节\n", BLOCK_SIZE);
    printf("  数据块:    %d (从块 %d 开始)\n", N_DATA_BLOCKS, DATA_START);
    printf("  inode 数:  %d\n", N_INODES);
    printf("  最大文件:  %d 字节 (%d 个直接块)\n",
           N_DIRECT * BLOCK_SIZE, N_DIRECT);
}

/* ================================================================
 * 系统调用风格的操作
 * ================================================================ */

static uint32_t sys_create(const char *path) {
    uint32_t parent;
    char leaf[MAX_NAME_LEN + 1];
    uint32_t exist = path_resolve(path, &parent, leaf);
    if (exist) return 0;
    if (parent == 0) return 0;

    Inode *dp = inode_get(parent);
    if (!dp || dp->type != INODE_DIR) return 0;

    uint32_t ino = alloc_inode(INODE_FILE);
    if (ino == 0) return 0;

    if (!dir_add(dp, leaf, ino)) { free_inode(ino); return 0; }
    return ino;
}

static uint32_t sys_mkdir(const char *path) {
    uint32_t parent;
    char leaf[MAX_NAME_LEN + 1];
    uint32_t exist = path_resolve(path, &parent, leaf);
    if (exist) return 0;
    if (parent == 0) return 0;

    Inode *dp = inode_get(parent);
    if (!dp || dp->type != INODE_DIR) return 0;

    uint32_t ino = alloc_inode(INODE_DIR);
    if (ino == 0) return 0;

    Inode *np = inode_get(ino);
    uint32_t nb = alloc_block();
    if (nb == 0) { free_inode(ino); return 0; }
    np->blocks[0] = nb;

    DirEntry de;
    memset(&de, 0, sizeof(de));
    strcpy(de.name, ".");
    de.ino = ino;
    dir_write(np, 0, &de);

    memset(&de, 0, sizeof(de));
    strcpy(de.name, "..");
    de.ino = parent;
    dir_write(np, 1, &de);

    np->size = 2 * sizeof(DirEntry);

    if (!dir_add(dp, leaf, ino)) {
        free_block(nb);
        free_inode(ino);
        return 0;
    }
    dp->nlinks++;
    return ino;
}

static int sys_write(const char *path, const void *data, int len) {
    uint32_t ino = path_resolve(path, NULL, NULL);
    if (ino == 0) return -1;
    Inode *ip = inode_get(ino);
    if (!ip || ip->type != INODE_FILE) return -1;

    if (len > N_DIRECT * BLOCK_SIZE) len = N_DIRECT * BLOCK_SIZE;

    const uint8_t *src = data;
    int written = 0;
    for (int b = 0; b < N_DIRECT && written < len; b++) {
        int chunk = len - written;
        if (chunk > BLOCK_SIZE) chunk = BLOCK_SIZE;

        if (ip->blocks[b] == 0) {
            uint32_t nb = alloc_block();
            if (nb == 0) break;
            ip->blocks[b] = nb;
        }
        memcpy(g_disk[ip->blocks[b]], src + written, chunk);
        written += chunk;
    }
    ip->size = (uint16_t)written;
    return written;
}

static int sys_read(const char *path, void *buf, int len) {
    uint32_t ino = path_resolve(path, NULL, NULL);
    if (ino == 0) return -1;
    Inode *ip = inode_get(ino);
    if (!ip || ip->type != INODE_FILE) return -1;

    int n = ip->size < len ? ip->size : len;
    uint8_t *dst = buf;
    int rd = 0;
    for (int b = 0; b < N_DIRECT && rd < n; b++) {
        int chunk = n - rd;
        if (chunk > BLOCK_SIZE) chunk = BLOCK_SIZE;
        if (ip->blocks[b] == 0) break;
        memcpy(dst + rd, g_disk[ip->blocks[b]], chunk);
        rd += chunk;
    }
    return rd;
}

static bool sys_unlink(const char *path) {
    uint32_t parent;
    char leaf[MAX_NAME_LEN + 1];
    uint32_t ino = path_resolve(path, &parent, leaf);
    if (ino == 0 || parent == 0) return false;
    if (ino == ROOT_INO) return false;

    Inode *dp = inode_get(parent);
    Inode *ip = inode_get(ino);
    if (!dp || !ip) return false;

    if (ip->type == INODE_DIR) {
        int n = dir_nentries(ip);
        if (n > 2) return false;   /* 非空目录 */
        dp->nlinks--;
    }

    for (int b = 0; b < N_DIRECT; b++) {
        if (ip->blocks[b]) {
            free_block(ip->blocks[b]);
            ip->blocks[b] = 0;
        }
    }

    dir_remove(dp, leaf);

    ip->nlinks--;
    if (ip->nlinks == 0) free_inode(ino);
    return true;
}

/* 硬链接：把 old_path 指向的 inode 再挂一份到 new_path */
static bool sys_link(const char *old_path, const char *new_path) {
    uint32_t old_ino = path_resolve(old_path, NULL, NULL);
    if (old_ino == 0) return false;

    Inode *ip = inode_get(old_ino);
    if (!ip || ip->type == INODE_DIR) return false;

    uint32_t parent;
    char leaf[MAX_NAME_LEN + 1];
    if (path_resolve(new_path, &parent, leaf) != 0) return false;
    if (parent == 0 || leaf[0] == '\0') return false;

    Inode *dp = inode_get(parent);
    if (!dp || dp->type != INODE_DIR) return false;

    if (!dir_add(dp, leaf, old_ino)) return false;
    ip->nlinks++;
    return true;
}

/* ================================================================
 * 显示
 * ================================================================ */
static const char *type_str(Inode *ip) {
    if (!ip) return "?";
    if (ip->type == INODE_FILE) return "文件";
    if (ip->type == INODE_DIR)  return "目录";
    return "空闲";
}

static void show_inode(uint32_t ino, const char *name) {
    Inode *ip = inode_get(ino);
    if (!ip) return;

    printf("  %-14s inode=%3u  类型=%-4s  大小=%4u  链接=%u  块: ",
           name, ino, type_str(ip), ip->size, ip->nlinks);

    bool first = true;
    for (int i = 0; i < N_DIRECT; i++) {
        if (ip->blocks[i] == 0) break;
        if (!first) printf(",");
        printf("%u", ip->blocks[i]);
        first = false;
    }
    printf("\n");
}

static void cmd_ls(const char *path) {
    uint32_t ino = path_resolve(path, NULL, NULL);
    if (ino == 0) { printf("  ls: %s: 不存在\n", path); return; }

    Inode *dp = inode_get(ino);
    if (!dp) return;

    if (dp->type == INODE_FILE) {
        show_inode(ino, path);
        return;
    }

    printf("  \033[1;33m%s\033[0m 的内容:\n", path);
    int n = dir_nentries(dp);
    DirEntry de;
    for (int i = 0; i < n; i++) {
        if (dir_read(dp, i, &de)) {
            Inode *ci = inode_get(de.ino);
            printf("    %-14s inode=%3u  %s (%u 字节)\n",
                   de.name, de.ino, type_str(ci),
                   ci ? ci->size : 0);
        }
    }
}

static void tree_recursive(uint32_t ino, int depth) {
    Inode *dp = inode_get(ino);
    if (!dp || dp->type != INODE_DIR) return;

    int n = dir_nentries(dp);
    DirEntry de;
    for (int i = 0; i < n; i++) {
        if (!dir_read(dp, i, &de)) continue;
        if (strcmp(de.name, ".") == 0 || strcmp(de.name, "..") == 0) continue;

        for (int d = 0; d < depth; d++) printf("  ");
        Inode *ci = inode_get(de.ino);

        if (ci && ci->type == INODE_DIR) {
            printf("\033[1;34m%s/\033[0m\n", de.name);
            tree_recursive(de.ino, depth + 1);
        } else {
            printf("%s  \033[90m(%u 字节)\033[0m\n",
                   de.name, ci ? ci->size : 0);
        }
    }
}

static void cmd_tree(const char *path) {
    uint32_t ino = path_resolve(path, NULL, NULL);
    if (ino == 0) { printf("  tree: %s: 不存在\n", path); return; }
    printf("  \033[1;33m%s\033[0m\n", path);
    tree_recursive(ino, 1);
}

static void show_stats(void) {
    printf("\n\033[1;36m--- 文件系统状态 ---\033[0m\n");
    long used_data = g_blocks_used - DATA_START;
    printf("  已用数据块: %ld / %d   (%.1f%%)\n",
           used_data, N_DATA_BLOCKS,
           100.0 * used_data / N_DATA_BLOCKS);
    printf("  已用 inode: %ld / %d\n", g_inodes_used, N_INODES - 1);
    printf("  元数据块:   %d (块 0 ~ %d)\n", DATA_START, DATA_START - 1);

    long free_blocks = 0;
    for (uint32_t b = DATA_START; b < N_BLOCKS; b++)
        if (!block_bm_test(b)) free_blocks++;
    printf("  空闲数据块: %ld\n", free_blocks);
}

/* ================================================================
 * main —— 演示
 * ================================================================ */
int main(void) {
    printf("\033[1;36m");
    printf("╔══════════════════════════════════════════════════╗\n");
    printf("║           玩具文件系统  fs                       ║\n");
    printf("╚══════════════════════════════════════════════════╝\n");
    printf("\033[0m\n");

    fs_format();

    printf("\n\033[1m━━━ 1. 在根目录创建文件 ━━━\033[0m\n");
    sys_create("/hello.txt");
    sys_write("/hello.txt", "Hello, filesystem!\n", 19);
    show_inode(path_resolve("/hello.txt", NULL, NULL), "/hello.txt");

    sys_create("/readme.md");
    sys_write("/readme.md", "# 玩具文件系统\n", 19);
    show_inode(path_resolve("/readme.md", NULL, NULL), "/readme.md");

    printf("\n\033[1m━━━ 2. 创建目录 ━━━\033[0m\n");
    sys_mkdir("/home");
    sys_mkdir("/home/alice");
    sys_mkdir("/home/bob");
    sys_mkdir("/etc");
    printf("  创建了 /home, /home/alice, /home/bob, /etc\n");

    printf("\n\033[1m━━━ 3. 在子目录里创建文件 ━━━\033[0m\n");
    sys_create("/home/alice/notes.txt");
    sys_write("/home/alice/notes.txt", "alice's notes\n", 14);
    sys_create("/home/bob/todo.txt");
    sys_write("/home/bob/todo.txt", "1. buy milk\n2. write code\n", 26);
    sys_create("/etc/config.ini");
    sys_write("/etc/config.ini", "[main]\nkey = value\n", 19);

    printf("\n\033[1m━━━ 4. 读回文件内容 ━━━\033[0m\n");
    const char *paths[] = {
        "/hello.txt", "/readme.md",
        "/home/alice/notes.txt", "/home/bob/todo.txt",
        "/etc/config.ini"
    };
    for (size_t i = 0; i < sizeof(paths) / sizeof(paths[0]); i++) {
        char buf[256];
        int n = sys_read(paths[i], buf, sizeof(buf) - 1);
        if (n > 0) {
            buf[n] = '\0';
            printf("  \033[1;33m%s\033[0m 的内容:\n", paths[i]);
            printf("    %s", buf);
            if (buf[n - 1] != '\n') putchar('\n');
        }
    }

    printf("\n\033[1m━━━ 5. 目录列表 ━━━\033[0m\n");
    cmd_ls("/");
    putchar('\n');
    cmd_ls("/home");
    putchar('\n');
    cmd_ls("/home/alice");

    printf("\n\033[1m━━━ 6. 目录树 ━━━\033[0m\n");
    cmd_tree("/");

    show_stats();

    printf("\n\033[1m━━━ 7. 硬链接 ━━━\033[0m\n");
    printf("  把 /etc/config.ini 硬链接到 /home/alice/cfg.ini\n");
    if (sys_link("/etc/config.ini", "/home/alice/cfg.ini")) {
        uint32_t i1 = path_resolve("/etc/config.ini", NULL, NULL);
        uint32_t i2 = path_resolve("/home/alice/cfg.ini", NULL, NULL);
        printf("  两个路径的 inode: %u, %u  %s\n",
               i1, i2, i1 == i2 ? "（同一个 inode ✓）" : "（不同 ✗）");
        show_inode(i1, "/etc/config.ini");

        printf("  通过新路径读内容:\n");
        char buf[128];
        int n = sys_read("/home/alice/cfg.ini", buf, sizeof(buf) - 1);
        if (n > 0) { buf[n] = '\0'; printf("    %s", buf); }
    }

    printf("\n\033[1m━━━ 8. 删除文件 ━━━\033[0m\n");
    if (sys_unlink("/readme.md"))
        printf("  已删除 /readme.md\n");
    if (sys_unlink("/home/bob/todo.txt"))
        printf("  已删除 /home/bob/todo.txt\n");

    printf("\n\033[1m━━━ 9. 硬链接的 inode 还在 ━━━\033[0m\n");
    printf("  删除 /etc/config.ini，但 /home/alice/cfg.ini 还在\n");
    sys_unlink("/etc/config.ini");
    show_inode(path_resolve("/home/alice/cfg.ini", NULL, NULL),
               "/home/alice/cfg.ini");

    printf("\n\033[1m━━━ 10. 尝试删除非空目录 ━━━\033[0m\n");
    if (!sys_unlink("/home"))
        printf("  /home 非空，拒绝删除（正确行为）\n");

    printf("\n\033[1m━━━ 11. 删除空目录 ━━━\033[0m\n");
    if (sys_unlink("/home/bob"))
        printf("  已删除 /home/bob\n");

    printf("\n\033[1m━━━ 12. 删除后的目录树 ━━━\033[0m\n");
    cmd_tree("/");

    show_stats();

    printf("\n\033[1m━━━ 13. 大文件（跨多个块） ━━━\033[0m\n");
    sys_create("/big.dat");
    static char big[3000];
    for (int i = 0; i < 3000; i++) big[i] = (char)('A' + (i % 26));
    int wrote = sys_write("/big.dat", big, 3000);
    printf("  写入 %d 字节到 /big.dat\n", wrote);
    show_inode(path_resolve("/big.dat", NULL, NULL), "/big.dat");

    static char readback[3000];
    int rd = sys_read("/big.dat", readback, sizeof(readback));
    bool ok = (rd == wrote) && (memcmp(big, readback, (size_t)wrote) == 0);
    printf("  读回 %d 字节，内容 %s\n", rd, ok ? "一致 ✓" : "不一致 ✗");

    printf("\n全部演示完成。\n");
    return 0;
}