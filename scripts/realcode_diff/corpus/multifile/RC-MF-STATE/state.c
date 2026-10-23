#include "state.h"
#include <stdio.h>
#include <string.h>

static void state_copy(char *dst, size_t cap, const char *src)
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

void state_init(StateMachine *machine)
{
    memset(machine, 0, sizeof(StateMachine));
    machine->current = -1;
}

int state_add_state(StateMachine *machine, const char *name)
{
    StateDefinition *state;

    if (machine->state_count >= STATE_MAX_STATES) {
        return -1;
    }
    state = &machine->states[machine->state_count];
    state->id = machine->state_count;
    state_copy(state->name, STATE_NAME_LEN, name);
    machine->state_count++;
    return state->id;
}

int state_add_event(StateMachine *machine, const char *name)
{
    EventDefinition *event;

    if (machine->event_count >= STATE_MAX_EVENTS) {
        return -1;
    }
    event = &machine->events[machine->event_count];
    event->id = machine->event_count;
    state_copy(event->name, STATE_NAME_LEN, name);
    machine->event_count++;
    return event->id;
}

int state_find_state(const StateMachine *machine, const char *name)
{
    int i;

    for (i = 0; i < machine->state_count; i++) {
        if (strcmp(machine->states[i].name, name) == 0) {
            return machine->states[i].id;
        }
    }
    return -1;
}

int state_find_event(const StateMachine *machine, const char *name)
{
    int i;

    for (i = 0; i < machine->event_count; i++) {
        if (strcmp(machine->events[i].name, name) == 0) {
            return machine->events[i].id;
        }
    }
    return -1;
}

int state_add_transition(StateMachine *machine, const char *from, const char *event,
                        const char *to, const char *message)
{
    Transition *transition;
    int from_id = state_find_state(machine, from);
    int event_id = state_find_event(machine, event);
    int to_id = state_find_state(machine, to);

    if (from_id < 0 || event_id < 0 || to_id < 0) {
        return -1;
    }
    if (machine->transition_count >= STATE_MAX_TRANSITIONS) {
        return -2;
    }
    transition = &machine->transitions[machine->transition_count];
    transition->from_state = from_id;
    transition->event = event_id;
    transition->to_state = to_id;
    transition->enter_action = (message != NULL && message[0] != '\0') ? STATE_ACTION_PRINT : STATE_ACTION_NONE;
    transition->leave_action = STATE_ACTION_NONE;
    state_copy(transition->message, STATE_NAME_LEN, (message != NULL) ? message : "");
    machine->transition_count++;
    return machine->transition_count - 1;
}

int state_dispatch(StateMachine *machine, const char *event_name)
{
    int event_id = state_find_event(machine, event_name);
    int i;

    if (event_id < 0) {
        machine->invalid_events++;
        printf("    event %s is not known\n", event_name);
        return -1;
    }
    for (i = 0; i < machine->transition_count; i++) {
        Transition *transition = &machine->transitions[i];
        if (transition->from_state != machine->current || transition->event != event_id) {
            continue;
        }
        {
            int previous = machine->current;
            machine->current = transition->to_state;
            machine->visits[machine->current]++;
            printf("    %-12s -> %-12s  %s\n",
                   machine->events[event_id].name, machine->states[machine->current].name,
                   transition->message);
            if (machine->callback != NULL) {
                machine->callback(transition->message, previous, machine->current);
            }
        }
        return 0;
    }
    machine->invalid_events++;
    printf("    event %s is not allowed in state %s\n", event_name,
           (machine->current >= 0) ? machine->states[machine->current].name : "?");
    return -2;
}

int state_current(const StateMachine *machine)
{
    return machine->current;
}

void state_print_table(const StateMachine *machine)
{
    int i;

    printf("  states:");
    for (i = 0; i < machine->state_count; i++) {
        printf(" %s", machine->states[i].name);
    }
    printf("\n  events:");
    for (i = 0; i < machine->event_count; i++) {
        printf(" %s", machine->events[i].name);
    }
    printf("\n  transitions:\n");
    for (i = 0; i < machine->transition_count; i++) {
        const Transition *transition = &machine->transitions[i];
        printf("    %-12s %-12s -> %-12s %s\n",
               machine->states[transition->from_state].name,
               machine->events[transition->event].name,
               machine->states[transition->to_state].name,
               transition->message);
    }
}

void state_print_visits(const StateMachine *machine)
{
    int i;

    printf("  visits:");
    for (i = 0; i < machine->state_count; i++) {
        printf(" %s=%d", machine->states[i].name, machine->visits[i]);
    }
    printf("\n  invalid_events=%d\n", machine->invalid_events);
}
