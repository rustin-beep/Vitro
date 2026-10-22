#ifndef EVENT_H
#define EVENT_H

#define EVENT_MAX 32

typedef struct EventLoop EventLoop;

typedef enum {
    EVENT_TIMER = 0,
    EVENT_CALLBACK = 1,
    EVENT_CUSTOM = 2
} EventType;

typedef void (*EventCallback)(EventLoop *loop, int id, int data, void *context);

typedef struct {
    int id;
    EventType type;
    int due;
    int data;
    int registered_at;
    int fired;
    int cancelled;
    EventCallback callback;
    void *context;
} Event;

struct EventLoop {
    Event events[EVENT_MAX];
    int count;
    int tick;
    int next_id;
    int cancelled_count;
    long fired_total;
    long delay_total;
};

/* registers an event, returns its id or -1 when the queue is full */
int event_schedule(EventLoop *loop, EventType type, int due, EventCallback callback,
                   int data, void *context);

/* cancels an event, returns 0 on success */
int event_cancel(EventLoop *loop, int id);

/* number of active events that are due at the given tick */
int event_due_count(const EventLoop *loop, int tick);

/* fires every event that is due at the current tick, returns the number fired */
int event_run_tick(EventLoop *loop);

/* runs until the given tick is reached */
int event_run_loop(EventLoop *loop, int until_tick);

int event_queue_length(const EventLoop *loop);
int event_fired_count(const EventLoop *loop);
double event_average_delay(const EventLoop *loop);
int event_find_by_id(const EventLoop *loop, int id);

extern int event_ops;

#endif /* EVENT_H */
