/* Vitro time.h stub */
typedef long long time_t;
typedef long long clock_t;

#define CLOCKS_PER_SEC 1000000

time_t time(time_t* tloc);
double difftime(time_t time1, time_t time0);
clock_t clock(void);
