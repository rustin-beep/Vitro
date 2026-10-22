#include "http.h"

int http_ops = 0;
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void http_copy(char *dst, size_t cap, const char *src)
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

static void http_trim(char *s)
{
    size_t n;
    size_t start;
    size_t end;

    if (s == NULL) {
        return;
    }
    n = strlen(s);
    start = 0;
    while (start < n && (s[start] == ' ' || s[start] == '\t')) {
        start++;
    }
    end = n;
    while (end > start && (s[end - 1] == ' ' || s[end - 1] == '\t' || s[end - 1] == '\r')) {
        end--;
    }
    if (start > 0) {
        memmove(s, s + start, end - start);
    }
    s[end - start] = '\0';
}

/* splits the message into lines, the line endings are removed */
static int http_split_lines(const char *text, char lines[][HTTP_MAX_VALUE], int max_lines)
{
    int count = 0;
    size_t i = 0;

    if (text == NULL) {
        return 0;
    }
    while (text[i] != '\0' && count < max_lines) {
        size_t start = i;
        size_t len = 0;
        while (text[i] != '\0' && text[i] != '\n') {
            i++;
            len++;
        }
        if (len > 0 && text[start + len - 1] == '\r') {
            len--;
        }
        if (len > HTTP_MAX_VALUE - 1) {
            len = HTTP_MAX_VALUE - 1;
        }
        memcpy(lines[count], text + start, len);
        lines[count][len] = '\0';
        count++;
        if (text[i] == '\n') {
            i++;
        }
    }
    return count;
}

static int http_add_header(HttpHeader *headers, int *count, const char *line)
{
    const char *colon;
    char name[HTTP_MAX_NAME];
    size_t len;

    if (headers == NULL || count == NULL || line == NULL) {
        return -1;
    }
    colon = strchr(line, ':');
    if (colon == NULL) {
        return -2;
    }
    len = (size_t)(colon - line);
    if (len > HTTP_MAX_NAME - 1) {
        len = HTTP_MAX_NAME - 1;
    }
    memcpy(name, line, len);
    name[len] = '\0';
    http_trim(name);
    if (*count >= HTTP_MAX_HEADERS) {
        return -3;
    }
    http_copy(headers[*count].name, HTTP_MAX_NAME, name);
    http_copy(headers[*count].value, HTTP_MAX_VALUE, colon + 1);
    http_trim(headers[*count].value);
    (*count)++;
    return 0;
}

static int http_find_header(const HttpHeader *headers, int count, const char *name)
{
    int i;

    for (i = 0; i < count; i++) {
        if (strcmp(headers[i].name, name) == 0) {
            return i;
        }
    }
    return -1;
}

const char *http_request_header(const HttpRequest *request, const char *name)
{
    int index;

    if (request == NULL || name == NULL) {
        return NULL;
    }
    index = http_find_header(request->headers, request->header_count, name);
    if (index < 0) {
        return NULL;
    }
    return request->headers[index].value;
}

const char *http_response_header(const HttpResponse *response, const char *name)
{
    int index;

    if (response == NULL || name == NULL) {
        return NULL;
    }
    index = http_find_header(response->headers, response->header_count, name);
    if (index < 0) {
        return NULL;
    }
    return response->headers[index].value;
}

static int http_split_request_line(const char *line, HttpRequest *out)
{
    char method[32];
    char path[256];
    char version[32];
    int i = 0;
    int j = 0;

    while (line[i] != '\0' && line[i] != ' ') {
        method[i] = line[i];
        i++;
    }
    method[i] = '\0';
    i++;
    while (line[i] != '\0' && line[i] != ' ') {
        path[j] = line[i];
        i++;
        j++;
    }
    path[j] = '\0';
    i++;
    j = 0;
    while (line[i] != '\0') {
        version[j] = line[i];
        i++;
        j++;
    }
    version[j] = '\0';
    if (method[0] == '\0' || path[0] == '\0' || version[0] == '\0') {
        return -1;
    }
    http_copy(out->method, sizeof out->method, method);
    http_copy(out->path, sizeof out->path, path);
    http_copy(out->version, sizeof out->version, version);
    return 0;
}

int http_parse_request(const char *text, HttpRequest *out)
{
    char lines[HTTP_MAX_HEADERS + 8][HTTP_MAX_VALUE];
    int line_count;
    int i;
    int header_end = -1;

    if (text == NULL || out == NULL) {
        return -1;
    }
    memset(out, 0, sizeof(HttpRequest));
    out->error[0] = '\0';
    line_count = http_split_lines(text, lines, HTTP_MAX_HEADERS + 8);
    if (line_count == 0) {
        http_copy(out->error, sizeof out->error, "empty message");
        return -2;
    }
    if (http_split_request_line(lines[0], out) != 0) {
        http_copy(out->error, sizeof out->error, "malformed request line");
        return -3;
    }
    for (i = 1; i < line_count; i++) {
        if (lines[i][0] == '\0') {
            header_end = i;
            break;
        }
        if (http_add_header(out->headers, &out->header_count, lines[i]) != 0) {
            http_copy(out->error, sizeof out->error, "malformed header line");
            return -4;
        }
    }
    if (header_end < 0) {
        header_end = line_count;
    }
    if (http_find_header(out->headers, out->header_count, "Host") < 0) {
        http_copy(out->error, sizeof out->error, "missing Host header");
        return -5;
    }
    {
        const char *length_text = http_request_header(out, "Content-Length");
        for (i = header_end + 1; i < line_count; i++) {
            int len = (int)strlen(lines[i]);
            if (out->body_length + len + 1 > HTTP_MAX_BODY) {
                http_copy(out->error, sizeof out->error, "body too large");
                return -7;
            }
            memcpy(out->body + out->body_length, lines[i], (size_t)len);
            out->body_length += len;
            if (i < line_count - 1) {
                out->body[out->body_length] = '\n';
                out->body_length++;
            }
        }
        out->body[out->body_length] = '\0';
        http_ops++;
        if (length_text != NULL) {
            int declared = atoi(length_text);
            if (declared != out->body_length) {
                http_copy(out->error, sizeof out->error, "Content-Length does not match the body");
                return -6;
            }
        }
    }
    return 0;
}

int http_parse_response(const char *text, HttpResponse *out)
{
    char lines[HTTP_MAX_HEADERS + 8][HTTP_MAX_VALUE];
    int line_count;
    int i;
    int header_end = -1;
    char version[32];
    char status[32];
    char reason[128];
    int j;

    if (text == NULL || out == NULL) {
        return -1;
    }
    memset(out, 0, sizeof(HttpResponse));
    out->error[0] = '\0';
    line_count = http_split_lines(text, lines, HTTP_MAX_HEADERS + 8);
    if (line_count == 0) {
        http_copy(out->error, sizeof out->error, "empty message");
        return -2;
    }
    j = 0;
    i = 0;
    while (lines[0][i] != '\0' && lines[0][i] != ' ') {
        version[j] = lines[0][i];
        i++;
        j++;
    }
    version[j] = '\0';
    i++;
    j = 0;
    while (lines[0][i] != '\0' && lines[0][i] != ' ') {
        status[j] = lines[0][i];
        i++;
        j++;
    }
    status[j] = '\0';
    i++;
    http_copy(reason, sizeof reason, lines[0] + i);
    http_trim(reason);
    if (version[0] == '\0' || status[0] == '\0') {
        http_copy(out->error, sizeof out->error, "malformed status line");
        return -3;
    }
    http_copy(out->version, sizeof out->version, version);
    out->status = atoi(status);
    http_copy(out->reason, sizeof out->reason, reason);
    for (i = 1; i < line_count; i++) {
        if (lines[i][0] == '\0') {
            header_end = i;
            break;
        }
        if (http_add_header(out->headers, &out->header_count, lines[i]) != 0) {
            http_copy(out->error, sizeof out->error, "malformed header line");
            return -4;
        }
    }
    if (header_end < 0) {
        header_end = line_count;
    }
    for (i = header_end + 1; i < line_count; i++) {
        int len = (int)strlen(lines[i]);
        if (out->body_length + len + 1 > HTTP_MAX_BODY) {
            http_copy(out->error, sizeof out->error, "body too large");
            return -5;
        }
        memcpy(out->body + out->body_length, lines[i], (size_t)len);
        out->body_length += len;
        if (i < line_count - 1) {
            out->body[out->body_length] = '\n';
            out->body_length++;
        }
    }
    out->body[out->body_length] = '\0';
    return 0;
}

int http_build_request(const HttpRequest *request, char *out, size_t cap)
{
    int written = 0;
    int i;

    if (request == NULL || out == NULL || cap == 0) {
        return -1;
    }
    written = snprintf(out, cap, "%s %s %s\r\n", request->method, request->path, request->version);
    if (written < 0) {
        return -1;
    }
    for (i = 0; i < request->header_count; i++) {
        int n = snprintf(out + written, cap - (size_t)written, "%s: %s\r\n",
                         request->headers[i].name, request->headers[i].value);
        if (n < 0) {
            return -1;
        }
        written += n;
    }
    if (written + 2 >= (int)cap) {
        return -1;
    }
    out[written] = '\r';
    out[written + 1] = '\n';
    written += 2;
    if (request->body_length > 0) {
        int n = snprintf(out + written, cap - (size_t)written, "%s", request->body);
        if (n < 0) {
            return -1;
        }
        written += n;
    }
    return written;
}

int http_build_response(const HttpResponse *response, char *out, size_t cap)
{
    int written = 0;
    int i;

    if (response == NULL || out == NULL || cap == 0) {
        return -1;
    }
    written = snprintf(out, cap, "%s %d %s\r\n", response->version, response->status, response->reason);
    if (written < 0) {
        return -1;
    }
    for (i = 0; i < response->header_count; i++) {
        int n = snprintf(out + written, cap - (size_t)written, "%s: %s\r\n",
                         response->headers[i].name, response->headers[i].value);
        if (n < 0) {
            return -1;
        }
        written += n;
    }
    if (written + 2 >= (int)cap) {
        return -1;
    }
    out[written] = '\r';
    out[written + 1] = '\n';
    written += 2;
    if (response->body_length > 0) {
        int n = snprintf(out + written, cap - (size_t)written, "%s", response->body);
        if (n < 0) {
            return -1;
        }
        written += n;
    }
    return written;
}

const char *http_status_text(int status)
{
    switch (status) {
        case 200:
            return "OK";
        case 201:
            return "Created";
        case 204:
            return "No Content";
        case 400:
            return "Bad Request";
        case 404:
            return "Not Found";
        case 500:
            return "Internal Server Error";
        default:
            return "Unknown";
    }
}

void http_print_request(const HttpRequest *request)
{
    int i;

    if (request == NULL) {
        return;
    }
    printf("  method=%s path=%s version=%s\n", request->method, request->path, request->version);
    for (i = 0; i < request->header_count; i++) {
        printf("    header %s: %s\n", request->headers[i].name, request->headers[i].value);
    }
    printf("    body_length=%d\n", request->body_length);
    if (request->body_length > 0) {
        printf("    body_first_32=[%.*s]\n",
               (request->body_length < 32) ? request->body_length : 32, request->body);
    }
    if (request->error[0] != '\0') {
        printf("    error=%s\n", request->error);
    }
}

void http_print_response(const HttpResponse *response)
{
    int i;

    if (response == NULL) {
        return;
    }
    printf("  version=%s status=%d reason=%s\n", response->version, response->status, response->reason);
    for (i = 0; i < response->header_count; i++) {
        printf("    header %s: %s\n", response->headers[i].name, response->headers[i].value);
    }
    printf("    body_length=%d\n", response->body_length);
    if (response->body_length > 0) {
        printf("    body_first_32=[%.*s]\n",
               (response->body_length < 32) ? response->body_length : 32, response->body);
    }
    if (response->error[0] != '\0') {
        printf("    error=%s\n", response->error);
    }
}
