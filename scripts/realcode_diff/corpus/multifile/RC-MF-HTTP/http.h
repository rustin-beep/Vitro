#ifndef HTTP_H
#define HTTP_H

#include <stddef.h>

#define HTTP_MAX_HEADERS 16
#define HTTP_MAX_NAME 32
#define HTTP_MAX_VALUE 128
#define HTTP_MAX_BODY 512
#define HTTP_MAX_ERROR 128

typedef struct {
    char name[HTTP_MAX_NAME];
    char value[HTTP_MAX_VALUE];
} HttpHeader;

typedef struct {
    char method[16];
    char path[128];
    char version[16];
    HttpHeader headers[HTTP_MAX_HEADERS];
    int header_count;
    char body[HTTP_MAX_BODY];
    int body_length;
    char error[HTTP_MAX_ERROR];
} HttpRequest;

typedef struct {
    char version[16];
    int status;
    char reason[64];
    HttpHeader headers[HTTP_MAX_HEADERS];
    int header_count;
    char body[HTTP_MAX_BODY];
    int body_length;
    char error[HTTP_MAX_ERROR];
} HttpResponse;

/* parses a request, returns 0 on success and a negative code on error */
int http_parse_request(const char *text, HttpRequest *out);

/* parses a response, returns 0 on success and a negative code on error */
int http_parse_response(const char *text, HttpResponse *out);

/* rebuilds the message, returns the number of characters or -1 */
int http_build_request(const HttpRequest *request, char *out, size_t cap);
int http_build_response(const HttpResponse *response, char *out, size_t cap);

const char *http_request_header(const HttpRequest *request, const char *name);
const char *http_response_header(const HttpResponse *response, const char *name);

void http_print_request(const HttpRequest *request);
void http_print_response(const HttpResponse *response);
const char *http_status_text(int status);

extern int http_ops;

#endif /* HTTP_H */
