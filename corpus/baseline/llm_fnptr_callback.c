// @category: llm_regression
// #201 红锚：回调注册表（监听器数组 + qsort 排序 + 启用/禁用）
// 来源：LLM 探针批 12 q36a3b/CALLBACK_s1（223 行，2026-10-21 入库；clang golden 由 clang_direct 现场生成）
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <math.h>

/* Event Enum */
typedef enum {
    EVT_MOUSE_CLICK = 0,
    EVT_KEY_PRESS = 1,
    EVT_TIMER_TICK = 2,
    EVT_CLOSE = 3,
    EVT_COUNT = 4
} EventType;

/* Listener Structure */
typedef struct {
    void (*fn)(int event, int data);
    int enabled;
    int order;
    int id;
    EventType interested_events[EVT_COUNT];
    int interested_count;
} Listener;

/* Global State */
static Listener listeners[10];
static int listener_count = 0;

/* Helper: Get Event Name */
const char* get_event_name(int event) {
    if (event == EVT_MOUSE_CLICK) return "MOUSE_CLICK";
    if (event == EVT_KEY_PRESS) return "KEY_PRESS";
    if (event == EVT_TIMER_TICK) return "TIMER_TICK";
    if (event == EVT_CLOSE) return "CLOSE";
    return "UNKNOWN";
}

/* Callbacks */
void cb_id_0(int event, int data) {
    printf("ID:0, Event:%s, Data:%d\n", get_event_name(event), data);
}

void cb_id_1(int event, int data) {
    printf("ID:1, Event:%s, Data:%d\n", get_event_name(event), data);
}

void cb_id_2(int event, int data) {
    printf("ID:2, Event:%s, Data:%d\n", get_event_name(event), data);
}

void cb_id_3(int event, int data) {
    printf("ID:3, Event:%s, Data:%d\n", get_event_name(event), data);
}

void cb_id_4(int event, int data) {
    printf("ID:4, Event:%s, Data:%d\n", get_event_name(event), data);
}

void cb_id_5(int event, int data) {
    printf("ID:5, Event:%s, Data:%d\n", get_event_name(event), data);
}

/* Comparator for qsort to sort listeners by order */
int compare_listeners(const void *a, const void *b) {
    const Listener *la = (const Listener *)a;
    const Listener *lb = (const Listener *)b;
    return la->order - lb->order;
}

/* Register a listener */
int add_listener(void (*fn)(int, int), int order, int interested_event, int interested_event2, int interested_event3) {
    if (listener_count >= 10) return -1;
    
    int id = listener_count;
    Listener *l = &listeners[id];
    l->fn = fn;
    l->enabled = 1;
    l->order = order;
    l->id = id;
    l->interested_count = 0;
    
    if (interested_event >= 0) {
        l->interested_events[l->interested_count++] = (EventType)interested_event;
    }
    if (interested_event2 >= 0) {
        l->interested_events[l->interested_count++] = (EventType)interested_event2;
    }
    if (interested_event3 >= 0) {
        l->interested_events[l->interested_count++] = (EventType)interested_event3;
    }
    
    listener_count++;
    return id;
}

/* Remove a listener */
void remove_listener(int id) {
    if (id < 0 || id >= listener_count) return;
    
    /* Shift remaining listeners to fill the gap */
    for (int i = id; i < listener_count - 1; i++) {
        listeners[i] = listeners[i + 1];
    }
    listener_count--;
    
    /* Reassign IDs to maintain consistency */
    for (int i = 0; i < listener_count; i++) {
        listeners[i].id = i;
    }
}

/* Enable/Disable Listener */
void enable_listener(int id) {
    if (id >= 0 && id < listener_count) {
        listeners[id].enabled = 1;
    }
}

void disable_listener(int id) {
    if (id >= 0 && id < listener_count) {
        listeners[id].enabled = 0;
    }
}

/* Dispatch Event */
int dispatch_event(int event, int data) {
    /* Sort listeners by order */
    qsort(listeners, (size_t)listener_count, sizeof(Listener), compare_listeners);
    
    int called_count = 0;
    
    for (int i = 0; i < listener_count; i++) {
        Listener *l = &listeners[i];
        
        /* Check if enabled */
        if (l->enabled != 1) continue;
        
        /* Check if interested in this event */
        int interested = 0;
        for (int j = 0; j < l->interested_count; j++) {
            if (l->interested_events[j] == (EventType)event) {
                interested = 1;
                break;
            }
        }
        
        if (interested == 1) {
            /* Call the function pointer */
            if (l->fn != 0) {
                l->fn(event, data);
                called_count++;
            }
        }
    }
    
    return called_count;
}

/* Print Final Status */
void print_status() {
    printf("Final Status:\n");
    for (int i = 0; i < listener_count; i++) {
        Listener *l = &listeners[i];
        printf("ID:%d, Order:%d, Enabled:%d, Interested:[", l->id, l->order, l->enabled);
        for (int j = 0; j < l->interested_count; j++) {
            printf("%s", get_event_name((int)l->interested_events[j]));
            if (j < l->interested_count - 1) printf(",");
        }
        printf("]\n");
    }
}

int main(void) {
    /* Register 6 listeners */
    /* 2 listeners interested in MOUSE_CLICK */
    add_listener(cb_id_0, 0, EVT_MOUSE_CLICK, -1, -1);
    add_listener(cb_id_1, 1, EVT_MOUSE_CLICK, -1, -1);
    add_listener(cb_id_2, 2, EVT_KEY_PRESS, -1, -1);
    add_listener(cb_id_3, 3, EVT_TIMER_TICK, -1, -1);
    add_listener(cb_id_4, 4, EVT_CLOSE, -1, -1);
    add_listener(cb_id_5, 5, EVT_MOUSE_CLICK, EVT_KEY_PRESS, -1);

    /* Trigger 4 events */
    printf("Triggering MOUSE_CLICK(100):\n");
    int c1 = dispatch_event(EVT_MOUSE_CLICK, 100);
    printf("Callbacks called: %d\n", c1);

    printf("Triggering KEY_PRESS(200):\n");
    int c2 = dispatch_event(EVT_KEY_PRESS, 200);
    printf("Callbacks called: %d\n", c2);

    printf("Triggering TIMER_TICK(300):\n");
    int c3 = dispatch_event(EVT_TIMER_TICK, 300);
    printf("Callbacks called: %d\n", c3);

    printf("Triggering CLOSE(400):\n");
    int c4 = dispatch_event(EVT_CLOSE, 400);
    printf("Callbacks called: %d\n", c4);

    /* Disable listener ID 1 */
    printf("\nDisabling Listener ID 1\n");
    disable_listener(1);

    /* Trigger MOUSE_CLICK again to verify ID 1 is skipped */
    printf("Triggering MOUSE_CLICK(101) after disabling ID 1:\n");
    int c5 = dispatch_event(EVT_MOUSE_CLICK, 101);
    printf("Callbacks called: %d\n", c5);

    /* Remove listener ID 2 */
    printf("\nRemoving Listener ID 2\n");
    remove_listener(2);

    /* Trigger KEY_PRESS again to verify ID 2 is gone */
    printf("Triggering KEY_PRESS(201) after removing ID 2:\n");
    int c6 = dispatch_event(EVT_KEY_PRESS, 201);
    printf("Callbacks called: %d\n", c6);

    /* Print final status */
    print_status();

    return 0;
}
