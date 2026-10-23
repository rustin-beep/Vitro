#ifndef UNIT_H
#define UNIT_H

#include <stddef.h>

#define UNIT_MAX_CASES 16
#define UNIT_NAME_LEN 48
#define UNIT_MAX_ASSERTIONS 64

typedef struct {
    const char *file;
    int line;
    const char *expression;
    const char *detail;
} UnitFailure;

typedef int (*UnitTestFunction)(void);

typedef struct {
    const char *name;
    UnitTestFunction function;
} UnitCase;

typedef struct {
    UnitCase cases[UNIT_MAX_CASES];
    int case_count;
    UnitFailure failures[UNIT_MAX_ASSERTIONS];
    int failure_count;
    int assertion_count;
    int current_case;
    int aborted;
} UnitRunner;

void unit_init(UnitRunner *runner);
int unit_register(UnitRunner *runner, const char *name, UnitTestFunction function);
int unit_run_all(UnitRunner *runner);
void unit_report(const UnitRunner *runner);
int unit_fail(UnitRunner *runner, const char *file, int line, const char *expression,
              const char *detail);
void unit_pass(UnitRunner *runner);

#define ASSERT_TRUE(runner, condition) \
    unit_pass(runner); \
    if (!(condition)) { \
        unit_fail(runner, __FILE__, __LINE__, #condition, "expected true"); \
    }

#define ASSERT_EQ_INT(runner, actual, expected) \
    unit_pass(runner); \
    if ((actual) != (expected)) { \
        unit_fail(runner, __FILE__, __LINE__, #actual " == " #expected, "values differ"); \
    }

#define ASSERT_EQ_STR(runner, actual, expected) \
    unit_pass(runner); \
    if (strcmp((actual), (expected)) != 0) { \
        unit_fail(runner, __FILE__, __LINE__, #actual " == " #expected, "strings differ"); \
    }

#define ASSERT_NEAR(runner, actual, expected, tolerance) \
    unit_pass(runner); \
    if (((actual) - (expected) > (tolerance)) || ((expected) - (actual) > (tolerance))) { \
        unit_fail(runner, __FILE__, __LINE__, #actual " near " #expected, "values differ"); \
    }

#endif /* UNIT_H */
