#include "event.h"

int event_ops = 0;
#include <string.h>

int event_find_by_id(const EventLoop *loop, int id)
{
    int i;

    if (loop == NULL) {
        return -1;
    }
    for (i = 0; i < loop->count; i++) {
        if (loop->events[i].id == id) {
            return i;
        }
    }
    return -1;
}

int event_schedule(EventLoop *loop, EventType type, int due, EventCallback callback,
                   int data, void *context)
{
    Event fresh;
    int position;
    int i;

    if (loop == NULL) {
        return -1;
    }
    if (loop->count >= EVENT_MAX) {
        return -1;
    }
    fresh.id = loop->next_id;
    loop->next_id++;
    fresh.type = type;
    fresh.due = due;
    fresh.data = data;
    fresh.registered_at = loop->tick;
    fresh.fired = 0;
    fresh.cancelled = 0;
    fresh.callback = callback;
    fresh.context = context;

    /* keep the array sorted by the due time */
    position = loop->count;
    for (i = 0; i < loop->count; i++) {
        if (loop->events[i].due > due) {
            position = i;
            break;
        }
    }
    for (i = loop->count; i > position; i--) {
        loop->events[i] = loop->events[i - 1];
    }
    loop->events[position] = fresh;
    loop->count++;
    event_ops++;
    return fresh.id;
}

int event_cancel(EventLoop *loop, int id)
{
    int index;

    if (loop == NULL) {
        return -1;
    }
    index = event_find_by_id(loop, id);
    if (index < 0) {
        return -1;
    }
    if (loop->events[index].cancelled) {
        return -2;
    }
    loop->events[index].cancelled = 1;
    loop->cancelled_count++;
    return 0;
}

int event_due_count(const EventLoop *loop, int tick)
{
    int count = 0;
    int i;

    if (loop == NULL) {
        return 0;
    }
    for (i = 0; i < loop->count; i++) {
        if (loop->events[i].cancelled) {
            continue;
        }
        if (loop->events[i].due == tick) {
            count++;
        }
    }
    return count;
}

int event_run_tick(EventLoop *loop)
{
    int ids[EVENT_MAX];
    int count = 0;
    int fired = 0;
    int i;

    if (loop == NULL) {
        return 0;
    }
    for (i = 0; i < loop->count; i++) {
        if (loop->events[i].cancelled) {
            continue;
        }
        if (loop->events[i].due == loop->tick) {
            ids[count] = loop->events[i].id;
            count++;
        }
    }
    for (i = 0; i < count; i++) {
        int index = event_find_by_id(loop, ids[i]);
        Event current;
        if (index < 0) {
            continue;
        }
        current = loop->events[index];
        if (current.cancelled) {
            continue;
        }
        loop->events[index].fired = 1;
        loop->fired_total++;
        loop->delay_total += (long)(current.due - current.registered_at);
        fired++;
        if (current.callback != NULL) {
            current.callback(loop, current.id, current.data, current.context);
        }
    }
    return fired;
}

int event_run_loop(EventLoop *loop, int until_tick)
{
    if (loop == NULL) {
        return -1;
    }
    while (loop->tick <= until_tick) {
        event_run_tick(loop);
        loop->tick++;
    }
    return loop->tick;
}

int event_queue_length(const EventLoop *loop)
{
    int count = 0;
    int i;

    if (loop == NULL) {
        return 0;
    }
    for (i = 0; i < loop->count; i++) {
        if (!loop->events[i].cancelled) {
            count++;
        }
    }
    return count;
}

int event_fired_count(const EventLoop *loop)
{
    if (loop == NULL) {
        return 0;
    }
    return (int)loop->fired_total;
}

double event_average_delay(const EventLoop *loop)
{
    if (loop == NULL || loop->fired_total == 0) {
        return 0.0;
    }
    return (double)loop->delay_total / (double)loop->fired_total;
}
