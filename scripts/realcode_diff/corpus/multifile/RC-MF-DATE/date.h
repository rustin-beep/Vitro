#ifndef DATE_H
#define DATE_H

#include <stddef.h>

typedef struct {
    int year;
    int month;
    int day;
} Date;

/* parses "YYYY-MM-DD"; returns 0 on success */
int date_parse(const char *text, Date *out);

/* writes "YYYY-MM-DD"; returns the number of characters written or -1 */
int date_format(const Date *date, char *out, size_t cap);

int date_is_valid(const Date *date);
int date_is_leap(int year);
int date_days_in_month(int year, int month);

/* adds a number of days, the result may land in another year */
int date_add_days(const Date *date, int days, Date *out);

/* day of week with 0 = Sunday and 6 = Saturday, computed with Zeller */
int date_weekday(const Date *date);

/* day of the year, 1 based */
int date_day_of_year(const Date *date);

/* number of days between two dates, the result is b - a */
int date_diff_days(const Date *a, const Date *b);

/* advances over the weekend, days must not be negative */
int date_add_business_days(const Date *date, int days, Date *out);

/* negative when a is earlier, zero when both dates are equal */
int date_compare(const Date *a, const Date *b);

extern int date_calls;

#endif /* DATE_H */
