#include "date.h"

int date_calls = 0;
#include <stdio.h>
#include <string.h>
#include <ctype.h>

int date_is_leap(int year)
{
    if (year % 400 == 0) {
        return 1;
    }
    if (year % 100 == 0) {
        return 0;
    }
    return (year % 4 == 0) ? 1 : 0;
}

int date_days_in_month(int year, int month)
{
    static const int DAYS[12] = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };

    if (month < 1 || month > 12) {
        return 0;
    }
    if (month == 2 && date_is_leap(year)) {
        return 29;
    }
    return DAYS[month - 1];
}

int date_is_valid(const Date *date)
{
    if (date == NULL) {
        return 0;
    }
    if (date->year < 1 || date->year > 9999) {
        return 0;
    }
    if (date->month < 1 || date->month > 12) {
        return 0;
    }
    if (date->day < 1 || date->day > date_days_in_month(date->year, date->month)) {
        return 0;
    }
    return 1;
}

static int date_read_digits(const char *text, int *pos, int count, int *out)
{
    int value = 0;
    int i;

    for (i = 0; i < count; i++) {
        char c = text[*pos + i];
        if (!isdigit((unsigned char)c)) {
            return 0;
        }
        value = value * 10 + (c - '0');
    }
    *pos += count;
    *out = value;
    return 1;
}

int date_parse(const char *text, Date *out)
{
    int pos = 0;
    Date tmp;

    if (text == NULL || out == NULL) {
        return -1;
    }
    if (!date_read_digits(text, &pos, 4, &tmp.year)) {
        return -1;
    }
    if (pos >= (int)strlen(text) || text[pos] != '-') {
        return -1;
    }
    pos++;
    if (!date_read_digits(text, &pos, 2, &tmp.month)) {
        return -1;
    }
    if (pos >= (int)strlen(text) || text[pos] != '-') {
        return -1;
    }
    pos++;
    if (!date_read_digits(text, &pos, 2, &tmp.day)) {
        return -1;
    }
    if (text[pos] != '\0') {
        return -1;
    }
    if (!date_is_valid(&tmp)) {
        return -1;
    }
    *out = tmp;
    date_calls++;
    return 0;
}

int date_format(const Date *date, char *out, size_t cap)
{
    int written;

    if (date == NULL || out == NULL || cap < 11) {
        return -1;
    }
    written = sprintf(out, "%04d-%02d-%02d", date->year, date->month, date->day);
    if (written < 0) {
        return -1;
    }
    return written;
}

/* days since 1970-01-01 for a proleptic Gregorian date */
static long date_serial(const Date *date)
{
    long y = (long)date->year;
    unsigned long m = (unsigned long)date->month;
    unsigned long d = (unsigned long)date->day;
    long era;
    unsigned long yoe;
    unsigned long doy;
    unsigned long doe;

    y -= (m <= 2UL) ? 1 : 0;
    era = (y >= 0 ? y : y - 399) / 400;
    yoe = (unsigned long)(y - era * 400);
    doy = (153UL * (m + ((m > 2UL) ? 9UL : 3UL)) + 2UL) / 5UL + d - 1UL;
    doe = yoe * 365UL + yoe / 4UL - yoe / 100UL + doy;
    return era * 146097L + (long)doe - 719468L;
}

static void date_from_serial(long serial, Date *out)
{
    long z = serial + 719468L;
    long era;
    unsigned long doe;
    unsigned long yoe;
    unsigned long doy;
    unsigned long mp;
    long y;
    long m;
    long d;

    era = (z >= 0 ? z : z - 146096L) / 146097L;
    doe = (unsigned long)(z - era * 146097L);
    yoe = (doe - doe / 1460UL + doe / 36524UL - doe / 146096UL) / 365UL;
    y = (long)yoe + era * 400L;
    doy = doe - (365UL * yoe + yoe / 4UL - yoe / 100UL);
    mp = (5UL * doy + 2UL) / 153UL;
    d = (long)(doy - (153UL * mp + 2UL) / 5UL + 1UL);
    m = (mp < 10UL) ? (long)mp + 3L : (long)mp - 9L;
    y += (m <= 2L) ? 1L : 0L;
    out->year = (int)y;
    out->month = (int)m;
    out->day = (int)d;
}

int date_add_days(const Date *date, int days, Date *out)
{
    if (date == NULL || out == NULL) {
        return -1;
    }
    if (!date_is_valid(date)) {
        return -1;
    }
    date_from_serial(date_serial(date) + (long)days, out);
    return 0;
}

int date_weekday(const Date *date)
{
    int q;
    int m;
    int k;
    int j;
    int h;

    if (date == NULL) {
        return -1;
    }
    if (date->month < 3) {
        m = date->month + 12;
        k = (date->year - 1) % 100;
        j = (date->year - 1) / 100;
    } else {
        m = date->month;
        k = date->year % 100;
        j = date->year / 100;
    }
    q = date->day;
    h = (q + (13 * (m + 1)) / 5 + k + k / 4 + j / 4 + 5 * j) % 7;
    return (h + 6) % 7;
}

int date_day_of_year(const Date *date)
{
    int total = 0;
    int m;

    if (date == NULL || !date_is_valid(date)) {
        return -1;
    }
    for (m = 1; m < date->month; m++) {
        total += date_days_in_month(date->year, m);
    }
    return total + date->day;
}

int date_diff_days(const Date *a, const Date *b)
{
    long from;
    long to;

    if (a == NULL || b == NULL) {
        return 0;
    }
    if (!date_is_valid(a) || !date_is_valid(b)) {
        return 0;
    }
    from = date_serial(a);
    to = date_serial(b);
    return (int)(to - from);
}

int date_add_business_days(const Date *date, int days, Date *out)
{
    Date current;
    int remaining;

    if (date == NULL || out == NULL || days < 0) {
        return -1;
    }
    if (!date_is_valid(date)) {
        return -1;
    }
    current = *date;
    remaining = days;
    while (remaining > 0) {
        int weekday;
        if (date_add_days(&current, 1, &current) != 0) {
            return -1;
        }
        weekday = date_weekday(&current);
        if (weekday != 0 && weekday != 6) {
            remaining--;
        }
    }
    *out = current;
    return 0;
}

int date_compare(const Date *a, const Date *b)
{
    if (a == NULL || b == NULL) {
        return 0;
    }
    if (a->year != b->year) {
        return (a->year < b->year) ? -1 : 1;
    }
    if (a->month != b->month) {
        return (a->month < b->month) ? -1 : 1;
    }
    if (a->day != b->day) {
        return (a->day < b->day) ? -1 : 1;
    }
    return 0;
}
