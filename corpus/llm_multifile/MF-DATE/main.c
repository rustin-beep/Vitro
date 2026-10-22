#include <stdio.h>
#include <string.h>
#include "date.h"

static const char *WEEKDAY_NAMES[7] = {
    "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"
};

static void show_date(const char *label, const Date *date)
{
    char text[16];
    int weekday;

    date_format(date, text, sizeof text);
    weekday = date_weekday(date);
    printf("  %-22s %s  weekday=%d (%s)  day_of_year=%3d  leap=%d\n",
           label, text, weekday, WEEKDAY_NAMES[weekday],
           date_day_of_year(date), date_is_leap(date->year));
}

int main(void)
{
    static const char *const SAMPLES[] = {
        "2024-02-29",
        "2023-02-28",
        "2023-01-31",
        "2023-12-31",
        "2024-01-01",
        "2024-12-31",
        "1900-01-01",
        "2000-02-29",
        "2100-12-31"
    };
    static const int SAMPLE_COUNT = (int)(sizeof SAMPLES / sizeof SAMPLES[0]);

    Date parsed;
    Date shifted;
    Date business;
    Date other;
    char text[16];
    int i;

    printf("=== fixed dates ===\n");
    for (i = 0; i < SAMPLE_COUNT; i++) {
        if (date_parse(SAMPLES[i], &parsed) != 0) {
            printf("  parse(%s) failed\n", SAMPLES[i]);
            continue;
        }
        show_date(SAMPLES[i], &parsed);
    }

    printf("=== add days ===\n");
    date_parse("2023-12-31", &parsed);
    date_add_days(&parsed, 1, &shifted);
    show_date("2023-12-31 + 1", &shifted);
    date_add_days(&parsed, 365, &shifted);
    show_date("2023-12-31 + 365", &shifted);
    date_parse("2024-02-28", &parsed);
    date_add_days(&parsed, 1, &shifted);
    show_date("2024-02-28 + 1", &shifted);
    date_add_days(&parsed, 2, &shifted);
    show_date("2024-02-28 + 2", &shifted);
    date_parse("2023-01-31", &parsed);
    date_add_days(&parsed, 1, &shifted);
    show_date("2023-01-31 + 1", &shifted);

    printf("=== difference in days ===\n");
    date_parse("2023-01-01", &parsed);
    date_parse("2023-12-31", &other);
    printf("  2023-01-01 -> 2023-12-31 = %d days\n", date_diff_days(&parsed, &other));
    date_parse("2024-01-01", &other);
    printf("  2023-01-01 -> 2024-01-01 = %d days\n", date_diff_days(&parsed, &other));
    date_parse("2024-03-01", &other);
    printf("  2024-01-01 -> 2024-03-01 = %d days\n", date_diff_days(&parsed, &other));

    printf("=== weekdays of representatives ===\n");
    for (i = 0; i < SAMPLE_COUNT; i++) {
        if (date_parse(SAMPLES[i], &parsed) != 0) {
            continue;
        }
        printf("  %-12s -> %s\n", SAMPLES[i], WEEKDAY_NAMES[date_weekday(&parsed)]);
    }

    printf("=== business days ===\n");
    date_parse("2023-06-12", &parsed);
    show_date("start 2023-06-12", &parsed);
    date_add_business_days(&parsed, 1, &business);
    show_date("+1 business day", &business);
    date_add_business_days(&parsed, 5, &business);
    show_date("+5 business days", &business);
    date_add_business_days(&parsed, 10, &business);
    show_date("+10 business days", &business);
    date_parse("2023-12-22", &parsed);
    show_date("start 2023-12-22", &parsed);
    date_add_business_days(&parsed, 3, &business);
    show_date("+3 business days", &business);

    printf("=== parse format round trip ===\n");
    {
        int all_ok = 1;
        for (i = 0; i < SAMPLE_COUNT; i++) {
            Date again;
            int rc;
            if (date_parse(SAMPLES[i], &parsed) != 0) {
                continue;
            }
            date_format(&parsed, text, sizeof text);
            rc = date_parse(text, &again);
            if (rc != 0 || date_compare(&parsed, &again) != 0) {
                all_ok = 0;
                printf("  mismatch for %s\n", SAMPLES[i]);
            }
        }
        printf("  round_trip_all_equal = %s\n", all_ok ? "yes" : "no");
    }

    printf("  date_calls=%d\n", date_calls);
    printf("=== invalid input ===\n");
    printf("  parse(2023-02-29) rc=%d\n", date_parse("2023-02-29", &parsed));
    printf("  parse(2024-13-01) rc=%d\n", date_parse("2024-13-01", &parsed));
    printf("  parse(2024/01/01) rc=%d\n", date_parse("2024/01/01", &parsed));
    printf("  parse(abc) rc=%d\n", date_parse("abc", &parsed));
    return 0;
}
