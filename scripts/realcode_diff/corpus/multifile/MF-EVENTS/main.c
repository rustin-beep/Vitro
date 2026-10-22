#include <stdio.h>
#include <string.h>
#include "event.h"

typedef struct {
    int ids[EVENT_MAX];
    int data[EVENT_MAX];
    int count;
} FireLog;

static void on_event(EventLoop *loop, int id, int data, void *context)
{
    FireLog *log = (FireLog *)context;

    printf("    fired id=%d data=%d at tick=%d\n", id, data, loop->tick);
    if (log != NULL && log->count < EVENT_MAX) {
        log->ids[log->count] = id;
        log->data[log->count] = data;
        log->count++;
    }
}

static void on_spawning_event(EventLoop *loop, int id, int data, void *context)
{
    FireLog *log = (FireLog *)context;
    int child;

    printf("    fired id=%d data=%d at tick=%d (spawns a child event)\n", id, data, loop->tick);
    if (log != NULL && log->count < EVENT_MAX) {
        log->ids[log->count] = id;
        log->data[log->count] = data;
        log->count++;
    }
    child = event_schedule(loop, EVENT_CUSTOM, loop->tick + 4, on_event, data * 10, context);
    printf("    registered child id=%d due tick=%d\n", child, loop->tick + 4);
}

int main(void)
{
    EventLoop loop;
    FireLog log;
    int ids[8];
    int i;
    int cancelled_id;

    memset(&loop, 0, sizeof loop);
    memset(&log, 0, sizeof log);

    printf("=== registration ===\n");
    loop.tick = 0;
    ids[0] = event_schedule(&loop, EVENT_TIMER, 3, on_event, 100, &log);
    printf("  registered id=%d due=3\n", ids[0]);
    loop.tick = 1;
    ids[1] = event_schedule(&loop, EVENT_CALLBACK, 5, on_event, 200, &log);
    printf("  registered id=%d due=5\n", ids[1]);
    loop.tick = 2;
    ids[2] = event_schedule(&loop, EVENT_TIMER, 5, on_event, 300, &log);
    printf("  registered id=%d due=5 (same tick as id=%d)\n", ids[2], ids[1]);
    loop.tick = 3;
    ids[3] = event_schedule(&loop, EVENT_CUSTOM, 10, on_event, 400, &log);
    printf("  registered id=%d due=10 (will be cancelled)\n", ids[3]);
    loop.tick = 4;
    ids[4] = event_schedule(&loop, EVENT_TIMER, 8, on_event, 500, &log);
    printf("  registered id=%d due=8\n", ids[4]);
    loop.tick = 5;
    ids[5] = event_schedule(&loop, EVENT_CALLBACK, 12, on_spawning_event, 600, &log);
    printf("  registered id=%d due=12 (registers a child)\n", ids[5]);
    loop.tick = 6;
    ids[6] = event_schedule(&loop, EVENT_TIMER, 15, on_event, 700, &log);
    printf("  registered id=%d due=15\n", ids[6]);
    loop.tick = 7;
    ids[7] = event_schedule(&loop, EVENT_CUSTOM, 20, on_event, 800, &log);
    printf("  registered id=%d due=20\n", ids[7]);
    cancelled_id = ids[3];

    printf("=== run loop ===\n");
    for (i = 0; i <= 20; i++) {
        loop.tick = i;
        if (i == 9) {
            int rc = event_cancel(&loop, cancelled_id);
            printf("  cancel id=%d rc=%d\n", cancelled_id, rc);
        }
        printf("  tick=%2d due=%d queue=%d\n",
               loop.tick, event_due_count(&loop, loop.tick), event_queue_length(&loop));
        event_run_tick(&loop);
    }

    printf("=== event states ===\n");
    for (i = 0; i < loop.count; i++) {
        printf("  id=%d due=%2d registered=%2d fired=%d cancelled=%d\n",
               loop.events[i].id, loop.events[i].due, loop.events[i].registered_at,
               loop.events[i].fired, loop.events[i].cancelled);
    }

    printf("=== verification ===\n");
    {
        int never_fired = 1;
        int index = event_find_by_id(&loop, cancelled_id);
        if (index >= 0 && loop.events[index].fired != 0) {
            never_fired = 0;
        }
        printf("  cancelled_event_never_fired = %s\n", never_fired ? "yes" : "no");
        printf("  total_fired=%d recorded_in_log=%d\n", event_fired_count(&loop), log.count);
        printf("  average_delay=%.4f\n", event_average_delay(&loop));
        printf("  queue_length=%d cancelled=%d\n", event_queue_length(&loop), loop.cancelled_count);
        printf("  event_ops=%d\n", event_ops);
    }
    printf("=== data seen by the callbacks ===\n");
    for (i = 0; i < log.count; i++) {
        printf("  id=%d data=%d\n", log.ids[i], log.data[i]);
    }
    return 0;
}
