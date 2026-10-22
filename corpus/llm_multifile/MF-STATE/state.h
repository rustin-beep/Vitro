#ifndef STATE_H
#define STATE_H

#define STATE_MAX_STATES 12
#define STATE_MAX_EVENTS 12
#define STATE_MAX_TRANSITIONS 32
#define STATE_NAME_LEN 24

typedef enum {
    STATE_ACTION_NONE = 0,
    STATE_ACTION_PRINT,
    STATE_ACTION_LOG
} StateAction;

typedef struct {
    int id;
    char name[STATE_NAME_LEN];
} StateDefinition;

typedef struct {
    int id;
    char name[STATE_NAME_LEN];
} EventDefinition;

typedef struct {
    int from_state;
    int event;
    int to_state;
    StateAction enter_action;
    StateAction leave_action;
    char message[STATE_NAME_LEN];
} Transition;

typedef void (*StateCallback)(const char *message, int from_state, int to_state);

typedef struct {
    StateDefinition states[STATE_MAX_STATES];
    int state_count;
    EventDefinition events[STATE_MAX_EVENTS];
    int event_count;
    Transition transitions[STATE_MAX_TRANSITIONS];
    int transition_count;
    int current;
    int visits[STATE_MAX_STATES];
    int invalid_events;
    StateCallback callback;
} StateMachine;

void state_init(StateMachine *machine);
int state_add_state(StateMachine *machine, const char *name);
int state_add_event(StateMachine *machine, const char *name);
int state_add_transition(StateMachine *machine, const char *from, const char *event,
                        const char *to, const char *message);
int state_find_state(const StateMachine *machine, const char *name);
int state_find_event(const StateMachine *machine, const char *name);
int state_dispatch(StateMachine *machine, const char *event);
int state_current(const StateMachine *machine);
void state_print_table(const StateMachine *machine);
void state_print_visits(const StateMachine *machine);

#endif /* STATE_H */
