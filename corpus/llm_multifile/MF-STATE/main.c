// @category: llm_multifile
// 工程：MF-STATE — 表驱动状态机：电梯 + 订单两实例共用一套库
// 来源：LLM 多文件语料（2026-10-21 入库；clang golden 由 clang_direct 工程模式现场生成）
#include <stdio.h>
#include <string.h>
#include "state.h"

static void on_transition(const char *message, int from_state, int to_state)
{
    printf("      action: %s (%d -> %d)\n",
           (message != NULL && message[0] != '\0') ? message : "none", from_state, to_state);
}

static void build_elevator(StateMachine *machine)
{
    state_init(machine);
    machine->callback = on_transition;
    state_add_state(machine, "IDLE");
    state_add_state(machine, "UP");
    state_add_state(machine, "DOWN");
    state_add_state(machine, "DOOR_OPEN");
    state_add_event(machine, "CALL_UP");
    state_add_event(machine, "CALL_DOWN");
    state_add_event(machine, "ARRIVE");
    state_add_event(machine, "TIMEOUT");
    state_add_transition(machine, "IDLE", "CALL_UP", "UP", "elevator starts to go up");
    state_add_transition(machine, "IDLE", "CALL_DOWN", "DOWN", "elevator starts to go down");
    state_add_transition(machine, "UP", "ARRIVE", "DOOR_OPEN", "elevator arrived upstairs");
    state_add_transition(machine, "DOWN", "ARRIVE", "DOOR_OPEN", "elevator arrived downstairs");
    state_add_transition(machine, "DOOR_OPEN", "TIMEOUT", "IDLE", "the doors close again");
    state_add_transition(machine, "IDLE", "TIMEOUT", "IDLE", "nothing to do");
}

static void build_order(StateMachine *machine)
{
    state_init(machine);
    machine->callback = on_transition;
    state_add_state(machine, "CREATED");
    state_add_state(machine, "PAID");
    state_add_state(machine, "SHIPPED");
    state_add_state(machine, "DONE");
    state_add_state(machine, "CANCELLED");
    state_add_event(machine, "PAY");
    state_add_event(machine, "SHIP");
    state_add_event(machine, "COMPLETE");
    state_add_event(machine, "CANCEL");
    state_add_transition(machine, "CREATED", "PAY", "PAID", "the order is paid");
    state_add_transition(machine, "CREATED", "CANCEL", "CANCELLED", "the order is cancelled");
    state_add_transition(machine, "PAID", "SHIP", "SHIPPED", "the parcel leaves the warehouse");
    state_add_transition(machine, "SHIPPED", "COMPLETE", "DONE", "the order is finished");
    state_add_transition(machine, "SHIPPED", "CANCEL", "CANCELLED", "the order was cancelled on the way");
}

static void run_machine(const char *title, StateMachine *machine, const char *start_state,
                        const char *const *events, int event_count)
{
    int i;

    printf("=== %s ===\n", title);
    machine->current = state_find_state(machine, start_state);
    machine->visits[machine->current]++;
    printf("  start state=%s\n", machine->states[machine->current].name);
    for (i = 0; i < event_count; i++) {
        printf("  step %d event=%s\n", i + 1, events[i]);
        state_dispatch(machine, events[i]);
        printf("      current=%s\n", machine->states[state_current(machine)].name);
    }
    state_print_table(machine);
    state_print_visits(machine);
}

int main(void)
{
    static const char *const ELEVATOR_EVENTS[10] = {
        "CALL_UP", "ARRIVE", "TIMEOUT", "CALL_DOWN", "ARRIVE", "TIMEOUT",
        "CALL_UP", "PAY", "COMPLETE", "CALL_UP"
    };
    static const char *const ORDER_EVENTS[9] = {
        "PAY", "SHIP", "COMPLETE", "CANCEL", "PAY", "SHIP", "COMPLETE",
        "CANCEL", "SHIP"
    };
    StateMachine machine;

    build_elevator(&machine);
    run_machine("elevator", &machine, "IDLE", ELEVATOR_EVENTS, 10);

    build_order(&machine);
    run_machine("order", &machine, "CREATED", ORDER_EVENTS, 9);
    printf("=== done ===\n");
    return 0;
}
