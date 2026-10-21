// @category: llm_scale
// 规模压力面：OS 模拟：多级反馈队列调度 + 分页 LRU + 单级文件系统 + 事件日志
// 来源：LLM 千行语料 HUGE-OS（1160 行，2026-10-21 入库；clang golden 由 clang_direct 现场生成）
// 注：本档 member_accesses 上限 400（#236 分档），见 scripts/perf_budget/rules.json
/*
 * HUGE-OS -- a small operating system simulator in one C23 file.
 *
 * The simulator owns three subsystems.
 *
 * Processes are described by a pcb that holds the process id, the state, the
 * priority, the remaining time slice, a register file, a page table and the
 * program counter. Scheduling uses a multilevel feedback queue with three
 * levels and the time slices 2, 4 and 8. A process that burns its whole
 * slice is demoted one level, a process that blocks is requeued, and every
 * few ticks the low level is boosted again.
 *
 * Memory is managed with 4 KB pages and 16 physical frames. Every process
 * owns a page table, a missing mapping causes a page fault and the missing
 * frame is taken from the least recently used victim.
 *
 * The file system is a single directory with fixed 512 byte blocks. Files
 * are created, written, read, deleted and listed, and every block
 * allocation is accounted for.
 *
 * A fixed script of commands drives the simulator. Every command prints its
 * result and a summary of the system state, and the interesting events are
 * collected in a log that is printed at the end together with the counters
 * for context switches, page faults and block usage.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

/* ------------------------------------------------------------------ */
/* limits                                                             */
/* ------------------------------------------------------------------ */

#define OS_MAX_PROCS 8
#define OS_PAGES 4
#define OS_PAGE_SIZE 4096
#define OS_FRAMES 16
#define OS_REG_COUNT 8
#define OS_QUEUE_LEN 16
#define OS_FS_MAX_FILES 8
#define OS_FS_NAME_LEN 16
#define OS_FS_BLOCK 512
#define OS_FS_BLOCKS_PER_FILE 4
#define OS_FS_MAX_BLOCKS 32
#define OS_LOG_MAX 64
#define OS_CMD_LEN 64
#define OS_TEXT_LEN 64

/* ------------------------------------------------------------------ */
/* types                                                              */
/* ------------------------------------------------------------------ */

typedef enum {
    PROC_NEW = 0,
    PROC_READY = 1,
    PROC_RUNNING = 2,
    PROC_BLOCKED = 3,
    PROC_TERMINATED = 4
} ProcState;

typedef enum {
    Q_HIGH = 0,
    Q_MEDIUM = 1,
    Q_LOW = 2,
    Q_COUNT = 3
} QueueLevel;

typedef enum {
    EV_NONE = 0,
    EV_SPAWN = 1,
    EV_SWITCH = 2,
    EV_DEMOTE = 3,
    EV_BOOST = 4,
    EV_PAGE_FAULT = 5,
    EV_FILE_CREATE = 6,
    EV_FILE_WRITE = 7,
    EV_FILE_DELETE = 8,
    EV_BLOCK_ALLOC = 9,
    EV_BLOCK_FREE = 10,
    EV_TERMINATE = 11
} EventType;

typedef struct {
    int pid;
    ProcState state;
    int priority;
    int time_slice;
    int remaining;
    int registers[OS_REG_COUNT];
    int page_table[OS_PAGES];
    int page_count;
    int pc;
    int next_page;
} Pcb;

typedef struct {
    int type;
    int pid;
    int detail;
    char text[OS_TEXT_LEN];
} OsEvent;

typedef struct {
    char name[OS_FS_NAME_LEN];
    int used;
    int size;
    int blocks[OS_FS_BLOCKS_PER_FILE];
    int block_count;
} FsFile;

typedef struct {
    FsFile files[OS_FS_MAX_FILES];
    int file_count;
    int owner[OS_FS_MAX_BLOCKS];
    char store[OS_FS_MAX_BLOCKS][OS_FS_BLOCK];
    int used_blocks;
} Fs;

typedef struct {
    Pcb procs[OS_MAX_PROCS];
    int proc_count;
    int queues[Q_COUNT][OS_QUEUE_LEN];
    int queue_len[Q_COUNT];
    int frames[OS_FRAMES];
    int frame_page[OS_FRAMES];
    int frame_time[OS_FRAMES];
    int clock;
    int current_pid;
    long context_switches;
    long page_faults;
    long blocks_allocated;
    long blocks_freed;
    long demotions;
    long boosts;
    OsEvent log[OS_LOG_MAX];
    int log_count;
} Os;

/* ------------------------------------------------------------------ */
/* helpers                                                            */
/* ------------------------------------------------------------------ */

static void os_copy(char *dst, size_t cap, const char *src)
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

static const char *os_state_name(ProcState state)
{
    switch (state) {
        case PROC_NEW:
            return "new";
        case PROC_READY:
            return "ready";
        case PROC_RUNNING:
            return "running";
        case PROC_BLOCKED:
            return "blocked";
        case PROC_TERMINATED:
            return "terminated";
        default:
            return "unknown";
    }
}

static const char *os_event_name(int type)
{
    switch (type) {
        case EV_SPAWN:
            return "spawn";
        case EV_SWITCH:
            return "switch";
        case EV_DEMOTE:
            return "demote";
        case EV_BOOST:
            return "boost";
        case EV_PAGE_FAULT:
            return "page fault";
        case EV_FILE_CREATE:
            return "file create";
        case EV_FILE_WRITE:
            return "file write";
        case EV_FILE_DELETE:
            return "file delete";
        case EV_BLOCK_ALLOC:
            return "block alloc";
        case EV_BLOCK_FREE:
            return "block free";
        case EV_TERMINATE:
            return "terminate";
        default:
            return "event";
    }
}

static void os_log(Os *os, int type, int pid, int detail, const char *text)
{
    OsEvent *event;

    if (os->log_count >= OS_LOG_MAX) {
        return;
    }
    event = &os->log[os->log_count];
    event->type = type;
    event->pid = pid;
    event->detail = detail;
    os_copy(event->text, OS_TEXT_LEN, (text != NULL) ? text : "");
    os->log_count++;
}

/* ------------------------------------------------------------------ */
/* process management                                                 */
/* ------------------------------------------------------------------ */

static void os_init(Os *os)
{
    int i;
    int j;

    memset(os, 0, sizeof(Os));
    for (i = 0; i < OS_MAX_PROCS; i++) {
        os->procs[i].pid = -1;
        os->procs[i].state = PROC_NEW;
        for (j = 0; j < OS_PAGES; j++) {
            os->procs[i].page_table[j] = -1;
        }
    }
    for (i = 0; i < OS_FRAMES; i++) {
        os->frames[i] = -1;
        os->frame_page[i] = -1;
        os->frame_time[i] = 0;
    }
    for (i = 0; i < Q_COUNT; i++) {
        os->queue_len[i] = 0;
    }
    os->current_pid = -1;
    os->log_count = 0;
}

static Pcb *os_find(Os *os, int pid)
{
    int i;

    for (i = 0; i < OS_MAX_PROCS; i++) {
        if (os->procs[i].pid == pid) {
            return &os->procs[i];
        }
    }
    return NULL;
}

static int os_enqueue(Os *os, int pid, int level);

static int os_spawn(Os *os, int pid, int priority, int pages)
{
    Pcb *proc;
    int i;

    if (os_find(os, pid) != NULL) {
        return -1;
    }
    if (os->proc_count >= OS_MAX_PROCS) {
        return -2;
    }
    if (priority < 0) {
        priority = 0;
    }
    if (priority >= Q_COUNT) {
        priority = Q_COUNT - 1;
    }
    if (pages <= 0) {
        pages = 1;
    }
    if (pages > OS_PAGES) {
        pages = OS_PAGES;
    }
    for (i = 0; i < OS_MAX_PROCS; i++) {
        if (os->procs[i].pid == -1) {
            break;
        }
    }
    proc = &os->procs[i];
    proc->pid = pid;
    proc->state = PROC_READY;
    proc->priority = priority;
    proc->time_slice = (priority == Q_HIGH) ? 2 : ((priority == Q_MEDIUM) ? 4 : 8);
    proc->remaining = proc->time_slice;
    proc->page_count = pages;
    proc->pc = 0;
    proc->next_page = 0;
    for (i = 0; i < OS_REG_COUNT; i++) {
        proc->registers[i] = pid * 10 + i;
    }
    for (i = 0; i < OS_PAGES; i++) {
        proc->page_table[i] = -1;
    }
    os->proc_count++;
    os_enqueue(os, pid, priority);
    os_log(os, EV_SPAWN, pid, pages, "process created");
    return 0;
}

static int os_enqueue(Os *os, int pid, int level)
{
    Pcb *proc = os_find(os, pid);
    int slot;

    if (proc == NULL) {
        return -1;
    }
    if (level < 0 || level >= Q_COUNT) {
        return -2;
    }
    if (os->queue_len[level] >= OS_QUEUE_LEN) {
        return -3;
    }
    slot = os->queue_len[level];
    os->queues[level][slot] = pid;
    os->queue_len[level]++;
    proc->state = PROC_READY;
    proc->priority = level;
    return 0;
}

static int os_dequeue(Os *os, int level)
{
    int i;
    int pid;

    if (level < 0 || level >= Q_COUNT) {
        return -1;
    }
    if (os->queue_len[level] <= 0) {
        return -1;
    }
    pid = os->queues[level][0];
    for (i = 1; i < os->queue_len[level]; i++) {
        os->queues[level][i - 1] = os->queues[level][i];
    }
    os->queue_len[level]--;
    return pid;
}

static int os_ready_count(const Os *os)
{
    int total = 0;
    int i;

    for (i = 0; i < Q_COUNT; i++) {
        total += os->queue_len[i];
    }
    return total;
}

static int os_frames_used(const Os *os)
{
    int used = 0;
    int i;

    for (i = 0; i < OS_FRAMES; i++) {
        if (os->frames[i] >= 0) {
            used++;
        }
    }
    return used;
}

static void os_print_queues(const Os *os)
{
    int level;
    int i;

    for (level = 0; level < Q_COUNT; level++) {
        printf("    q%d:", level);
        for (i = 0; i < os->queue_len[level]; i++) {
            printf(" %d", os->queues[level][i]);
        }
        printf(" (len=%d)\n", os->queue_len[level]);
    }
}

/* ------------------------------------------------------------------ */
/* memory management                                                  */
/* ------------------------------------------------------------------ */

static int os_frame_victim(Os *os, int pid)
{
    int victim = -1;
    int oldest = 0;
    int i;

    for (i = 0; i < OS_FRAMES; i++) {
        if (os->frames[i] < 0) {
            return i;
        }
        if (os->frames[i] == pid) {
            continue;
        }
        if (victim < 0 || os->frame_time[i] < oldest) {
            victim = i;
            oldest = os->frame_time[i];
        }
    }
    return victim;
}

static int os_page_fault(Os *os, int pid, int vpage)
{
    Pcb *proc = os_find(os, pid);
    int frame;

    if (proc == NULL) {
        return -1;
    }
    if (vpage < 0 || vpage >= OS_PAGES) {
        return -2;
    }
    frame = os_frame_victim(os, pid);
    if (frame < 0) {
        return -3;
    }
    if (os->frames[frame] >= 0) {
        Pcb *owner = os_find(os, os->frames[frame]);
        if (owner != NULL) {
            int i;
            for (i = 0; i < OS_PAGES; i++) {
                if (owner->page_table[i] == frame) {
                    owner->page_table[i] = -1;
                }
            }
        }
    }
    os->frames[frame] = pid;
    os->frame_page[frame] = vpage;
    os->clock++;
    os->frame_time[frame] = os->clock;
    proc->page_table[vpage] = frame;
    os->page_faults++;
    os_log(os, EV_PAGE_FAULT, pid, vpage, "frame allocated");
    return frame;
}

static int os_access_page(Os *os, int pid, int vpage)
{
    Pcb *proc = os_find(os, pid);
    int frame;

    if (proc == NULL) {
        return -1;
    }
    if (vpage < 0 || vpage >= OS_PAGES) {
        return -2;
    }
    frame = proc->page_table[vpage];
    if (frame < 0) {
        frame = os_page_fault(os, pid, vpage);
        if (frame < 0) {
            return frame;
        }
        printf("    page fault pid=%d vpage=%d -> frame=%d\n", pid, vpage, frame);
        return frame;
    }
    os->clock++;
    os->frame_time[frame] = os->clock;
    printf("    hit pid=%d vpage=%d frame=%d\n", pid, vpage, frame);
    return frame;
}

static void os_print_frames(const Os *os)
{
    int i;

    printf("    frames:");
    for (i = 0; i < OS_FRAMES; i++) {
        if (os->frames[i] >= 0) {
            printf(" %d:p%d", os->frames[i], os->frame_page[i]);
        } else {
            printf(" _");
        }
    }
    printf("\n");
}

/* ------------------------------------------------------------------ */
/* scheduling                                                         */
/* ------------------------------------------------------------------ */

static int os_pick(Os *os)
{
    int level;

    for (level = 0; level < Q_COUNT; level++) {
        if (os->queue_len[level] > 0) {
            return level;
        }
    }
    return -1;
}

static void os_demote(Os *os, int pid)
{
    Pcb *proc = os_find(os, pid);
    int target;

    if (proc == NULL) {
        return;
    }
    target = proc->priority;
    if (target < Q_COUNT - 1) {
        target++;
    }
    proc->time_slice = (target == Q_HIGH) ? 2 : ((target == Q_MEDIUM) ? 4 : 8);
    proc->remaining = proc->time_slice;
    os->demotions++;
    os_enqueue(os, pid, target);
    os_log(os, EV_DEMOTE, pid, target, "time slice expired");
}

static void os_boost(Os *os)
{
    int pid;

    while (os->queue_len[Q_LOW] > 0) {
        pid = os_dequeue(os, Q_LOW);
        os_enqueue(os, pid, Q_HIGH);
        os->boosts++;
        os_log(os, EV_BOOST, pid, Q_HIGH, "priority boost");
    }
}

static int os_step(Os *os)
{
    int level;
    int pid;
    Pcb *proc;
    int vpage;

    level = os_pick(os);
    if (level < 0) {
        return -1;
    }
    pid = os_dequeue(os, level);
    proc = os_find(os, pid);
    if (proc == NULL) {
        return -1;
    }
    if (os->current_pid != pid) {
        os->context_switches++;
        os_log(os, EV_SWITCH, pid, os->current_pid, "context switch");
        os->current_pid = pid;
    }
    proc->state = PROC_RUNNING;
    proc->pc++;
    proc->registers[0] += 1;
    proc->registers[1] = proc->registers[0] * 2;
    proc->remaining--;
    vpage = proc->next_page % proc->page_count;
    proc->next_page = (proc->next_page + 1) % OS_PAGES;
    os_access_page(os, pid, vpage);
    if (proc->remaining <= 0) {
        os_demote(os, pid);
    } else {
        os_enqueue(os, pid, level);
    }
    if (proc->pc >= 24) {
        proc->state = PROC_TERMINATED;
        os_log(os, EV_TERMINATE, pid, proc->pc, "process finished");
    }
    return pid;
}

static void os_run(Os *os, int steps)
{
    int i;

    for (i = 0; i < steps; i++) {
        if (os_step(os) < 0) {
            printf("    no runnable process at step %d\n", i + 1);
            return;
        }
        if ((i + 1) % 6 == 0) {
            os_boost(os);
        }
    }
}

/* ------------------------------------------------------------------ */
/* file system                                                        */
/* ------------------------------------------------------------------ */

static void fs_init(Fs *fs)
{
    int i;

    memset(fs, 0, sizeof(Fs));
    for (i = 0; i < OS_FS_MAX_FILES; i++) {
        fs->files[i].used = 0;
        fs->files[i].name[0] = '\0';
    }
    for (i = 0; i < OS_FS_MAX_BLOCKS; i++) {
        fs->owner[i] = -1;
    }
    fs->file_count = 0;
    fs->used_blocks = 0;
}

static FsFile *fs_find(Fs *fs, const char *name)
{
    int i;

    for (i = 0; i < OS_FS_MAX_FILES; i++) {
        if (fs->files[i].used && strcmp(fs->files[i].name, name) == 0) {
            return &fs->files[i];
        }
    }
    return NULL;
}

static int fs_alloc_block(Fs *fs, int file_index)
{
    int i;

    for (i = 0; i < OS_FS_MAX_BLOCKS; i++) {
        if (fs->owner[i] >= 0) {
            continue;
        }
        fs->owner[i] = file_index;
        fs->used_blocks++;
        return i;
    }
    return -1;
}

static void fs_free_block(Fs *fs, int block)
{
    if (block < 0 || block >= OS_FS_MAX_BLOCKS) {
        return;
    }
    if (fs->owner[block] < 0) {
        return;
    }
    fs->owner[block] = -1;
    fs->used_blocks--;
}

static int fs_create(Fs *fs, const char *name)
{
    FsFile *file;
    int i;

    if (fs_find(fs, name) != NULL) {
        return -1;
    }
    for (i = 0; i < OS_FS_MAX_FILES; i++) {
        if (!fs->files[i].used) {
            break;
        }
    }
    if (i >= OS_FS_MAX_FILES) {
        return -2;
    }
    file = &fs->files[i];
    memset(file, 0, sizeof(FsFile));
    file->used = 1;
    os_copy(file->name, OS_FS_NAME_LEN, name);
    file->size = 0;
    file->block_count = 0;
    fs->file_count++;
    return i;
}

static int fs_write(Fs *fs, const char *name, int block_index, const char *text)
{
    FsFile *file = fs_find(fs, name);
    int block;
    size_t n;

    if (file == NULL) {
        return -1;
    }
    if (block_index < 0 || block_index >= OS_FS_BLOCKS_PER_FILE) {
        return -2;
    }
    if (file->block_count > block_index) {
        block = file->blocks[block_index];
    } else {
        block = fs_alloc_block(fs, (int)(file - fs->files));
        if (block < 0) {
            return -3;
        }
        file->blocks[file->block_count] = block;
        file->block_count++;
    }
    memset(fs->store[block], 0, OS_FS_BLOCK);
    n = strlen(text);
    if (n > OS_FS_BLOCK - 1) {
        n = OS_FS_BLOCK - 1;
    }
    memcpy(fs->store[block], text, n);
    fs->store[block][n] = '\0';
    file->size = (int)n;
    return block;
}

static int fs_read(const Fs *fs, const char *name, int block_index, char *out, size_t cap)
{
    const FsFile *file = fs_find((Fs *)fs, name);

    if (file == NULL) {
        return -1;
    }
    if (block_index < 0 || block_index >= file->block_count) {
        return -2;
    }
    os_copy(out, cap, fs->store[file->blocks[block_index]]);
    return (int)strlen(out);
}

static int fs_delete(Fs *fs, const char *name)
{
    FsFile *file = fs_find(fs, name);
    int i;

    if (file == NULL) {
        return -1;
    }
    for (i = 0; i < file->block_count; i++) {
        fs_free_block(fs, file->blocks[i]);
    }
    file->used = 0;
    file->name[0] = '\0';
    file->block_count = 0;
    file->size = 0;
    fs->file_count--;
    return 0;
}

static void fs_list(const Fs *fs)
{
    int i;

    printf("    files:\n");
    for (i = 0; i < OS_FS_MAX_FILES; i++) {
        if (!fs->files[i].used) {
            continue;
        }
        printf("      %-12s size=%4d blocks=%d\n",
               fs->files[i].name, fs->files[i].size, fs->files[i].block_count);
    }
}

/* ------------------------------------------------------------------ */
/* command parsing                                                    */
/* ------------------------------------------------------------------ */

static int cmd_next_token(const char *line, int *pos, char *out, size_t cap)
{
    size_t start;
    size_t len;

    if (line == NULL || pos == NULL || out == NULL || cap == 0) {
        return 0;
    }
    start = (size_t)*pos;
    start += strspn(line + start, " \t");
    if (line[start] == '\0') {
        *pos = (int)start;
        return 0;
    }
    len = strcspn(line + start, " \t");
    if (len > cap - 1) {
        len = cap - 1;
    }
    memcpy(out, line + start, len);
    out[len] = '\0';
    *pos = (int)(start + len);
    return 1;
}

static int cmd_int(const char *token, int *out)
{
    int value = 0;
    int i;

    if (token == NULL || out == NULL || token[0] == '\0') {
        return 0;
    }
    for (i = 0; token[i] != '\0'; i++) {
        if (!isdigit((unsigned char)token[i])) {
            return 0;
        }
        value = value * 10 + (token[i] - '0');
    }
    *out = value;
    return 1;
}

/* ------------------------------------------------------------------ */
/* state reporting                                                    */
/* ------------------------------------------------------------------ */

static void os_print_procs(const Os *os)
{
    int i;
    int j;

    printf("    processes:\n");
    for (i = 0; i < OS_MAX_PROCS; i++) {
        const Pcb *proc = &os->procs[i];
        if (proc->pid < 0) {
            continue;
        }
        printf("      pid=%d state=%-9s prio=%d slice=%d pc=%2d regs=[",
               proc->pid, os_state_name(proc->state), proc->priority,
               proc->remaining, proc->pc);
        for (j = 0; j < 4; j++) {
            printf("%d%s", proc->registers[j], (j < 3) ? "," : "");
        }
        printf("] pages=");
        for (j = 0; j < proc->page_count; j++) {
            printf(" %d", proc->page_table[j]);
        }
        printf("\n");
    }
}

static void os_print_summary(const Os *os, const Fs *fs)
{
    printf("    summary: running_queue=%d frames_used=%d/%d files=%d blocks=%d/%d\n",
           os_ready_count(os), os_frames_used(os), OS_FRAMES,
           fs->file_count, fs->used_blocks, OS_FS_MAX_BLOCKS);
    os_print_queues(os);
}

static void os_print_log(const Os *os)
{
    int i;

    printf("  === event log ===\n");
    for (i = 0; i < os->log_count; i++) {
        const OsEvent *event = &os->log[i];
        printf("    %-12s pid=%-3d detail=%-4d %s\n",
               os_event_name(event->type), event->pid, event->detail, event->text);
    }
    if (os->log_count == 0) {
        printf("    (empty)\n");
    }
}

static void os_print_stats(const Os *os, const Fs *fs)
{
    printf("  === statistics ===\n");
    printf("    context_switches=%ld\n", os->context_switches);
    printf("    page_faults=%ld frames_used=%d/%d\n", os->page_faults, os_frames_used(os), OS_FRAMES);
    printf("    demotions=%ld boosts=%ld\n", os->demotions, os->boosts);
    printf("    block_usage=%d/%d (%.1f%%) files=%d\n",
           fs->used_blocks, OS_FS_MAX_BLOCKS,
           (100.0 * (double)fs->used_blocks) / (double)OS_FS_MAX_BLOCKS,
           fs->file_count);
    printf("    log_entries=%d processes=%d\n", os->log_count, os->proc_count);
}

/* ------------------------------------------------------------------ */
/* command handlers                                                   */
/* ------------------------------------------------------------------ */

static void cmd_spawn(Os *os, Fs *fs, const char *args)
{
    char token[32];
    int pos = 0;
    int pid = 0;
    int priority = 0;
    int pages = 1;
    int rc;

    cmd_next_token(args, &pos, token, sizeof token);
    if (!cmd_int(token, &pid)) {
        printf("    spawn: bad pid\n");
        return;
    }
    cmd_next_token(args, &pos, token, sizeof token);
    if (!cmd_int(token, &priority)) {
        priority = 0;
    }
    cmd_next_token(args, &pos, token, sizeof token);
    if (!cmd_int(token, &pages)) {
        pages = 1;
    }
    rc = os_spawn(os, pid, priority, pages);
    printf("    spawn pid=%d priority=%d pages=%d rc=%d\n", pid, priority, pages, rc);
    os_print_summary(os, fs);
}

static void cmd_mem(Os *os, Fs *fs, const char *args)
{
    char token[32];
    int pos = 0;
    int pid = 0;
    int vpage = 0;
    int frame;

    cmd_next_token(args, &pos, token, sizeof token);
    if (!cmd_int(token, &pid)) {
        printf("    mem: bad pid\n");
        return;
    }
    cmd_next_token(args, &pos, token, sizeof token);
    if (!cmd_int(token, &vpage)) {
        vpage = 0;
    }
    frame = os_access_page(os, pid, vpage);
    printf("    mem pid=%d vpage=%d frame=%d\n", pid, vpage, frame);
    os_print_summary(os, fs);
}

static void cmd_page(Os *os, Fs *fs, const char *args)
{
    char token[32];
    int pos = 0;
    int pid = 0;
    int vpage = 0;
    int value = 0;
    Pcb *proc;
    int frame;

    cmd_next_token(args, &pos, token, sizeof token);
    if (!cmd_int(token, &pid)) {
        printf("    page: bad pid\n");
        return;
    }
    cmd_next_token(args, &pos, token, sizeof token);
    if (!cmd_int(token, &vpage)) {
        vpage = 0;
    }
    cmd_next_token(args, &pos, token, sizeof token);
    if (!cmd_int(token, &value)) {
        value = 0;
    }
    frame = os_access_page(os, pid, vpage);
    proc = os_find(os, pid);
    if (proc != NULL && frame >= 0) {
        proc->registers[2] = value;
    }
    printf("    page pid=%d vpage=%d value=%d frame=%d\n", pid, vpage, value, frame);
    os_print_summary(os, fs);
}

static void cmd_fs(Os *os, Fs *fs, const char *args)
{
    char verb[32];
    char token[64];
    int pos = 0;
    int rc;

    if (!cmd_next_token(args, &pos, verb, sizeof verb)) {
        printf("    fs: missing sub command\n");
        return;
    }
    if (strcmp(verb, "create") == 0) {
        if (!cmd_next_token(args, &pos, token, sizeof token)) {
            printf("    fs create: missing name\n");
            return;
        }
        rc = fs_create(fs, token);
        printf("    fs create %s rc=%d\n", token, rc);
        if (rc >= 0) {
            os_log(os, EV_FILE_CREATE, rc, 0, token);
        }
    } else if (strcmp(verb, "write") == 0) {
        char name[OS_FS_NAME_LEN];
        int block = 0;
        int pos2 = 0;
        if (!cmd_next_token(args, &pos, name, sizeof name)) {
            printf("    fs write: missing name\n");
            return;
        }
        cmd_next_token(args, &pos, token, sizeof token);
        if (!cmd_int(token, &block)) {
            block = 0;
        }
        pos2 = pos;
        while (args[pos2] == ' ' || args[pos2] == '\t') {
            pos2++;
        }
        os_copy(token, sizeof token, args + pos2);
        rc = fs_write(fs, name, block, token);
        printf("    fs write %s block=%d rc=%d\n", name, block, rc);
        if (rc >= 0) {
            os_log(os, EV_FILE_WRITE, rc, block, name);
            os_log(os, EV_BLOCK_ALLOC, rc, block, "block for the file");
            os->blocks_allocated++;
        }
    } else if (strcmp(verb, "read") == 0) {
        char name[OS_FS_NAME_LEN];
        int block = 0;
        char out[OS_FS_BLOCK];
        if (!cmd_next_token(args, &pos, name, sizeof name)) {
            printf("    fs read: missing name\n");
            return;
        }
        cmd_next_token(args, &pos, token, sizeof token);
        if (!cmd_int(token, &block)) {
            block = 0;
        }
        out[0] = '\0';
        rc = fs_read(fs, name, block, out, sizeof out);
        printf("    fs read %s block=%d rc=%d content=[%s]\n", name, block, rc, out);
    } else if (strcmp(verb, "delete") == 0) {
        if (!cmd_next_token(args, &pos, token, sizeof token)) {
            printf("    fs delete: missing name\n");
            return;
        }
        rc = fs_delete(fs, token);
        printf("    fs delete %s rc=%d\n", token, rc);
        if (rc == 0) {
            os_log(os, EV_FILE_DELETE, 0, 0, token);
            os_log(os, EV_BLOCK_FREE, 0, 0, "blocks released");
            os->blocks_freed++;
        }
    } else if (strcmp(verb, "list") == 0) {
        fs_list(fs);
    } else {
        printf("    fs: unknown sub command [%s]\n", verb);
    }
    os_print_summary(os, fs);
}

static void cmd_run(Os *os, Fs *fs, const char *args)
{
    char token[32];
    int pos = 0;
    int steps = 1;

    cmd_next_token(args, &pos, token, sizeof token);
    if (!cmd_int(token, &steps)) {
        steps = 1;
    }
    printf("    run %d scheduling steps\n", steps);
    os_run(os, steps);
    os_print_summary(os, fs);
}

static void cmd_stat(Os *os, Fs *fs)
{
    os_print_procs(os);
    os_print_frames(os);
    os_print_summary(os, fs);
}

static int cmd_execute(Os *os, Fs *fs, const char *line)
{
    char verb[32];
    char args[OS_CMD_LEN];
    int pos = 0;

    if (!cmd_next_token(line, &pos, verb, sizeof verb)) {
        return -1;
    }
    args[0] = '\0';
    while (line[pos] == ' ' || line[pos] == '\t') {
        pos++;
    }
    os_copy(args, sizeof args, line + pos);
    if (strcmp(verb, "spawn") == 0) {
        cmd_spawn(os, fs, args);
    } else if (strcmp(verb, "mem") == 0) {
        cmd_mem(os, fs, args);
    } else if (strcmp(verb, "page") == 0) {
        cmd_page(os, fs, args);
    } else if (strcmp(verb, "fs") == 0) {
        cmd_fs(os, fs, args);
    } else if (strcmp(verb, "run") == 0) {
        cmd_run(os, fs, args);
    } else if (strcmp(verb, "stat") == 0) {
        cmd_stat(os, fs);
    } else {
        printf("    unknown command [%s]\n", verb);
        return -1;
    }
    return 0;
}

/* ------------------------------------------------------------------ */
/* main                                                               */
/* ------------------------------------------------------------------ */

int main(void)
{
    static const char *const SCRIPT[] = {
        "spawn 1 0 2",
        "spawn 2 1 3",
        "spawn 3 2 4",
        "stat",
        "mem 1 0",
        "mem 1 1",
        "mem 2 0",
        "mem 2 1",
        "mem 2 2",
        "mem 3 0",
        "mem 3 1",
        "mem 3 2",
        "mem 3 3",
        "run 6",
        "run 6",
        "run 6",
        "page 1 0 4096",
        "page 2 2 8192",
        "fs create notes.txt",
        "fs write notes.txt 0 hello world",
        "fs write notes.txt 1 second block",
        "fs read notes.txt 0",
        "fs read notes.txt 1",
        "fs list",
        "run 6",
        "fs delete notes.txt",
        "fs list",
        "stat"
    };
    static const int SCRIPT_LEN = (int)(sizeof SCRIPT / sizeof SCRIPT[0]);
    Os os;
    Fs fs;
    int i;

    os_init(&os);
    fs_init(&fs);

    printf("=== system boot ===\n");
    printf("  processes=%d frames=%d page_size=%d block_size=%d\n",
           OS_MAX_PROCS, OS_FRAMES, OS_PAGE_SIZE, OS_FS_BLOCK);
    os_print_summary(&os, &fs);

    printf("=== command script (%d commands) ===\n", SCRIPT_LEN);
    for (i = 0; i < SCRIPT_LEN; i++) {
        printf("  [%2d] %s\n", i + 1, SCRIPT[i]);
        cmd_execute(&os, &fs, SCRIPT[i]);
    }

    printf("=== process table ===\n");
    os_print_procs(&os);
    printf("=== frames ===\n");
    os_print_frames(&os);
    printf("=== files ===\n");
    fs_list(&fs);

    os_print_log(&os);
    os_print_stats(&os, &fs);
    return 0;
}
